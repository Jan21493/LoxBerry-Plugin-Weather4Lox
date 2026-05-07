#!/usr/bin/perl

# Copyright 2016-2023 Michael Schlenstedt, michael@loxberry.de
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

##########################################################################
# Standard Modules (no error handling in case of missing modules)
##########################################################################

use LoxBerry::System;
use LoxBerry::IO;
use LoxBerry::Log;
use Getopt::Long;
use IO::Socket; # For sending UDP packages
use DateTime;
use Time::HiRes;
use Net::MQTT::Simple;
#use Data::Dumper;
use Config::Simple;
use JSON::PP ();
use utf8;
use Encode qw(encode_utf8);
use POSIX qw(setlocale LC_NUMERIC);

use constant MM_TO_INCH    => 0.0393700787;  # millimetres to inches
use constant CM_TO_INCH    => 0.393700787;   # centimetres to inches
use constant KMH_TO_MPH    => 0.621371192;   # km/h to mph
use constant C_TO_F_FACTOR => 1.8;           # Celsius to Fahrenheit (multiply)
use constant C_TO_F_OFFSET => 32;            # Celsius to Fahrenheit (add)
use constant HPA_TO_INHG   => 0.0295301;     # conversion from hPa (hectopascal) to inHg (Inches of mercury)

##########################################################################
# Read settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

our $pcfg             = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my  $udpport          = $pcfg->param("SERVER.UDPPORT");
# hashref for quick lookup, e.g. $dfcAllowed->{1} is true if period 1 should be sent
my  $dfcAllowed       = { map { $_ => 1 } split /;/, $pcfg->param('SERVER.SENDDFC') };
my  $hfcAllowed       = { map { $_ => 1 } split /;/, $pcfg->param('SERVER.SENDHFC') };
our $sendUDP          = $pcfg->param("SERVER.SENDUDP");
our $metric           = $pcfg->param("SERVER.METRIC");
our $emu              = $pcfg->param("SERVER.EMU");
our $stdTheme         = $pcfg->param("WEB.THEME");
our $stdIconSet       = $pcfg->param("WEB.ICONSET");
our $stdMode          = $pcfg->param("WEB.MODE") // "system";
our $topic            = $pcfg->param("SERVER.TOPIC") // "w4lx";
our $sendMQTT         = 0;
our $mqtt;
our $data;

# Hash that tracks every template variable set via sendToLox().
# Template rendering only substitutes variables present in this hash,
# which prevents theme files from accidentally exposing internal scalars
# like $lbpconfigdir, $pcfg, etc. via the <!--$varname--> syntax.
our %tmpl_vars;

my $scriptLabel    = "Data to Loxone";
my $scriptKey      = "datatoloxone";          # name in JSONs

# Language
our $lang = lblanguage();

# Create a logging object
my $log = LoxBerry::Log->new (
    package => 'weather4lox',
    name => "$scriptLabel",
    logdir => "$lbplogdir",
    #filename => "$lbplogdir/weather4lox.log",
    #append => 1,
);

# Commandline options
my $verbose = '';
my $maskKeys = 1;

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 },
            'maskkeys' => \$maskKeys,
            );

# Due to a bug in the Logging routine, set the loglevel fix to 3
#$log->loglevel(3);
if ($verbose) {
        $log->stdout(1);
        $log->loglevel(7);
}

LOGSTART "Weather4Lox $scriptLabel process started";
LOGDEB "This is $0 Version $version";

require "$lbpbindir/grabber_utils.pl";
requireOrLogdie('DateTime::Format::ISO8601');


##########################################################################
# Main program
##########################################################################

# Force C locale for numeric formatting so that printf always uses '.' as
# the decimal separator regardless of the system LC_NUMERIC setting.
# Without this, a German locale produces "4,25" instead of "4.25" in
# index.txt, which causes the Loxone Miniserver to report "Liefert keine Werte".
setlocale(LC_NUMERIC, "C");

my $i;

# theme language has priority over system language
if (defined $pcfg->param("WEB.LANG")) {
    $lang = $pcfg->param("WEB.LANG");
}  

my %L = LoxBerry::System::readlanguage("language.ini");

# weather code descriptions are stored in a separate language file, because they are needed in the theme for the weather codes list.

my $langData = readJsonFile("$lbhomedir/webfrontend/html/plugins/$lbpplugindir", "lang-$lang") // {};

# Create new HTML page with all weather data
open(F,">$lbplogdir/weatherdata.html") or LOGERR "Cannot open $lbplogdir/weatherdata.html for writing: $!";
flock(F,2);
binmode F, ':encoding(UTF-8)';
print F "<!DOCTYPE HTML>\n<html>\n<head>\n";
print F "<meta http-equiv='Content-Type' content='text/html; charset=utf-8'>\n</head>\n<body>";
#flock(F,8);
close(F);


# MQTT
&mqttconnect();

##########################################################################
# Load all JSON files at script startup
##########################################################################

LOGINF "Loading JSON data files ...";

# read JSON file with current conditions, daily and hourly forecasts
my $weatherKey = "current";
my $envelope = readJsonFile($lbplogdir, $weatherKey);
my $cur = $envelope->{$weatherKey} // {};
my $location = $envelope->{location} // {};

$weatherKey = "dailyforecast";
$envelope = readJsonFile($lbplogdir, $weatherKey);
my $dfc = $envelope->{$weatherKey} // [];

$weatherKey = "hourlyforecast";
$envelope = readJsonFile($lbplogdir, $weatherKey);
my $hfc = $envelope->{$weatherKey} // [];

my $iconMapping = readJsonFile("$lbphtmldir/icons/$stdIconSet", "icon_mapping") // {};

LOGOK "JSON data files loaded successfully.";

##########################################################################
# Send current conditions to Loxone via HTML webpage, MQTT and UDP
##########################################################################

# Send all values to Loxone via HTML webpage and prepare param/value for theme web pages,
# but send only some values to MS via MQTT and UDP - $toMS is used for values that should be sent to MS
my $toMS = 1;

LOGINF "--------------------------------------------------------------------------------";
LOGINF "Sending current weather data to Loxone ...";

# Queue for UDP sending - filled by send() function and sent by sendUDP() function
our $sendUDPqueue;

# Get timezone offset in seconds from tz_offset, e.g. "+0100" => 3600, "-0230" => -9000
my $tzseconds = tzOffsetSeconds($location->{tzOffset} // "");

# Times are send in local time 
my $curDate = DateTime->from_epoch(epoch => $cur->{time}{epoch}, time_zone => $location->{timezone});
my $curDateMidnight = $curDate->clone->set(hour => 0, minute => 0, second => 0);
my $curDateLoxEpoch = toLoxEpoch($curDateMidnight->epoch);

my $doLog = 1; # log the first data set in detail, but not all subsequent ones to avoid log flooding

# sending to Loxone Miniserver via MQTT, HTML webpage and UDP with logging of each value
sendToLox($toMS, $doLog, "cur_date", toLoxEpoch($cur->{time}{epoch}));                             # Loxone epoch (1.1.2009, MEZ), e.g. 542934004
sendToLox($toMS, $doLog, "cur_date_des", $cur->{time}{datetime});                                  # was RFC822, now ISO 8601, e.g. Mon, 16 Mar 2026 23:00:04 +0100
sendToLox($toMS, $doLog, "cur_date_tz_des_sh", $location->{timezone});                             # IANA timezone name, e.g. Europe/Berlin
sendToLox($toMS, $doLog, "cur_date_tz_des", $location->{tzShort});                                 # Time Zone Abbreviation, e.g. CET
sendToLox($toMS, $doLog, "cur_date_tz", $location->{tzOffset});                                    # Numeric timezone offset, e.g. +0100
sendToLox($toMS, $doLog, "cur_day", encode_utf8(sprintf("%02d", $curDate->day)));
sendToLox($toMS, $doLog, "cur_month", encode_utf8(sprintf("%02d", $curDate->month)));
sendToLox($toMS, $doLog, "cur_year", encode_utf8($curDate->year));
sendToLox($toMS, $doLog, "cur_hour", encode_utf8(sprintf("%02d", $curDate->hour)));
sendToLox($toMS, $doLog, "cur_min", encode_utf8(sprintf("%02d", $curDate->minute)));
sendToLox($toMS, $doLog, "cur_loc_n", encode_utf8($location->{city}));
sendToLox($toMS, $doLog, "cur_loc_c", encode_utf8($location->{country}));
sendToLox($toMS, $doLog, "cur_loc_ccode", encode_utf8($location->{countryCode}));
sendToLox($toMS, $doLog, "cur_loc_lat", $location->{latitude});
sendToLox($toMS, $doLog, "cur_loc_long", $location->{longitude});
sendToLox($toMS, $doLog, "cur_loc_el", $location->{elevation});
sendToLox($toMS, $doLog, "cur_tt", !$metric ? $cur->{temperature}{air}*C_TO_F_FACTOR+C_TO_F_OFFSET : $cur->{temperature}{air});
sendToLox($toMS, $doLog, "cur_tt_fl", !$metric ? $cur->{temperature}{feelsLike}*C_TO_F_FACTOR+C_TO_F_OFFSET : $cur->{temperature}{feelsLike});
sendToLox($toMS, $doLog, "cur_hu", $cur->{humidity});
sendToLox($toMS, $doLog, "cur_w_dirdes", encode_utf8($langData->{wind_directions}{getWindDirCardinal($cur->{wind}{direction})} // '-'));
sendToLox($toMS, $doLog, "cur_w_dir", $cur->{wind}{direction});
sendToLox($toMS, $doLog, "cur_w_sp", !$metric ? $cur->{wind}{speed}*KMH_TO_MPH : $cur->{wind}{speed});
sendToLox($toMS, $doLog, "cur_w_gu", !$metric ? $cur->{wind}{gust}*KMH_TO_MPH : $cur->{wind}{gust});
sendToLox($toMS, $doLog, "cur_w_ch", !$metric ? $cur->{temperature}{windChill}*C_TO_F_FACTOR+C_TO_F_OFFSET : $cur->{temperature}{windChill});
sendToLox($toMS, $doLog, "cur_pr", !$metric ? $cur->{pressure}*HPA_TO_INHG : $cur->{pressure});
sendToLox($toMS, $doLog, "cur_dp", !$metric ? $cur->{dewpoint}*C_TO_F_FACTOR+C_TO_F_OFFSET : $cur->{dewpoint});
sendToLox($toMS, $doLog, "cur_vis", !$metric ? $cur->{visibility}*KMH_TO_MPH : $cur->{visibility});
sendToLox($toMS, $doLog, "cur_sr", $cur->{solarRadiation});
sendToLox($toMS, $doLog, "cur_hi", !$metric ? $cur->{temperature}{heatIndex}*C_TO_F_FACTOR+C_TO_F_OFFSET : $cur->{temperature}{heatIndex});
sendToLox($toMS, $doLog, "cur_uvi", $cur->{uvIndex});
sendToLox($toMS, $doLog, "cur_pop", $cur->{precipitation}{probability});
sendToLox($toMS, $doLog, "cur_prec_today", !$metric ? $cur->{precipitation}{rainToday}*MM_TO_INCH : $cur->{precipitation}{rainToday});
sendToLox($toMS, $doLog, "cur_prec_1hr", !$metric ? $cur->{precipitation}{rain1hr}*MM_TO_INCH : $cur->{precipitation}{rain1hr});
sendToLox($toMS, $doLog, "cur_snow", !$metric ? $cur->{precipitation}{snowToday}*CM_TO_INCH : $cur->{precipitation}{snowToday});
sendToLox($toMS, $doLog, "cur_we_icon", $cur->{weatherCode}{weather4lox});
sendToLox($toMS, $doLog, "cur_we_code", w4l_to_oldW4lCode($cur->{weatherCode}{weather4lox}));
sendToLox($toMS, $doLog, "cur_we_code_lox", $cur->{weatherCode}{loxone});
sendToLox($toMS, $doLog, "cur_we_des", encode_utf8($langData->{weather_descriptions}{$cur->{weatherCode}{weather4lox}} // '-'));
sendToLox($toMS, $doLog, "cur_moon_p", $cur->{moon}{percent});
sendToLox($toMS, $doLog, "cur_moon_a", $cur->{moon}{age});
sendToLox($toMS, $doLog, "cur_moon_ph", $cur->{moon}{phase});
sendToLox($toMS, $doLog, "cur_moon_h", $cur->{moon}{direction});
sendToLox($toMS, $doLog, "cur_sun_r", $curDateLoxEpoch + timeToSec($cur->{sunrise}));
sendToLox($toMS, $doLog, "cur_sun_s", $curDateLoxEpoch + timeToSec($cur->{sunset}));
sendToLox($toMS, $doLog, "cur_ozone", $cur->{airQuality}{ozone});
sendToLox($toMS, $doLog, "cur_sky", $cur->{cloudCover});

# Use night icons between sunset and sunrise
my $curSec = timeToSec($curDate->hour . ":" . $curDate->minute);
my $sunriseSec = timeToSec($cur->{sunrise}) // 6;
my $sunsetSec = timeToSec($cur->{sunset}) // 18;
my $iconName = '';
my $moonPhases;

if ($curSec < $sunriseSec || $curSec > $sunsetSec) {
    $iconName = $iconMapping->{icons}{$cur->{weatherCode}{weather4lox}}{"iconNight"} // 'no_mapping';

    # add moon quarter / half to night icon name, if icon sets demands this
    $moonPhases = $iconMapping->{icons}{$cur->{weatherCode}{weather4lox}}{moonPhases} // 0;
    if ($moonPhases == 5) {
        $iconName .= "_" . getMoonPhasePart($cur->{moon}{age}, 5) . "q";
    } elsif ($moonPhases == 3) {
        $iconName .= "_" . getMoonPhasePart($cur->{moon}{age}, 3) . "h";
    }
} else {
    $iconName = $iconMapping->{icons}{$cur->{weatherCode}{weather4lox}}{"iconDay"} // 'no_mapping' ;
}
# special handling for sunrise and sunset: send as loxone epoch time to Loxone for easier processing,
# but need to be in hh:mm format on theme web page
{ 
    no strict 'refs';
    ${"cur_sun_r"} = $cur->{sunrise};
    ${"cur_sun_s"} = $cur->{sunset};
    ${"cur_we_icon"} = $iconName . "." . ($iconMapping->{format} // 'no_format');
}

#
# Send daily forecast to Loxone via HTML webpage, MQTT and UDP
#

LOGINF "--------------------------------------------------------------------------------";
LOGINF "Sending daily weather forecast to Loxone ...";

foreach my $dfcEntry (@$dfc) {

    # Today is day 0 (dfc0), tomorrow is dfc1, ...
    my $per = $dfcEntry->{day};

    # Check if we should send this period to MS via MQTT and UDP - first period is 1 for current day (dfc0)
    $toMS = $dfcAllowed->{$per + 1};

    LOGINF "Processing daily forecast entry for day $per (dfc${per}) with date " . $dfcEntry->{time}{datetime} . ($toMS ? " and sending data to MS (as configured)." : ", but not sending data to MS (as configured).");

    # Times are send in local time 
    my $dfcDate = DateTime->from_epoch(epoch => $dfcEntry->{time}{epoch}, time_zone => $location->{timezone});

    my $dfcDate_midnight = $dfcDate->clone->set(hour => 0, minute => 0, second => 0);
    my $dfcDate_LoxoneEpoch = toLoxEpoch($dfcDate_midnight->epoch);

    # sending to Loxone Miniserver via MQTT, HTML webpage and UDP with logging of first day (today) in detail
    sendToLox($toMS, $doLog, "dfc${per}_per", $per); # period starting with 0 for today, 1 for tomorrow, ...
    sendToLox($toMS, $doLog, "dfc${per}_date", toLoxEpoch($dfcEntry->{time}{epoch}));    # Loxone epoch (1.1.2009, MEZ), e.g. 542934004
    sendToLox($toMS, $doLog, "dfc${per}_day", encode_utf8(sprintf("%02d", $dfcDate->day)));
    sendToLox($toMS, $doLog, "dfc${per}_month", encode_utf8(sprintf("%02d", $dfcDate->month)));
    sendToLox($toMS, $doLog, "dfc${per}_monthn", encode_utf8($dfcDate->month_name));
    sendToLox($toMS, $doLog, "dfc${per}_monthn_sh", encode_utf8($dfcDate->month_abbr));
    sendToLox($toMS, $doLog, "dfc${per}_year", encode_utf8($dfcDate->year));
    sendToLox($toMS, $doLog, "dfc${per}_hour", encode_utf8(sprintf("%02d", $dfcDate->hour)));
    sendToLox($toMS, $doLog, "dfc${per}_min", encode_utf8(sprintf("%02d", $dfcDate->minute)));
    sendToLox($toMS, $doLog, "dfc${per}_wday", encode_utf8($dfcDate->day_name));
    sendToLox($toMS, $doLog, "dfc${per}_wday_sh", encode_utf8($dfcDate->day_abbr));
    sendToLox($toMS, $doLog, "dfc${per}_tt_h", !$metric ? $dfcEntry->{temperature}{max}{air}*C_TO_F_FACTOR+C_TO_F_OFFSET : $dfcEntry->{temperature}{max}{air});
    sendToLox($toMS, $doLog, "dfc${per}_tt_l", !$metric ? $dfcEntry->{temperature}{min}{air}*C_TO_F_FACTOR+C_TO_F_OFFSET : $dfcEntry->{temperature}{min}{air});
    sendToLox($toMS, $doLog, "dfc${per}_pop", $dfcEntry->{precipitation}{probability});
    sendToLox($toMS, $doLog, "dfc${per}_prec", !$metric ? $dfcEntry->{precipitation}{rainHigh}*MM_TO_INCH : $dfcEntry->{precipitation}{rainHigh});
    sendToLox($toMS, $doLog, "dfc${per}_snow", !$metric ? $dfcEntry->{precipitation}{snowHigh}*CM_TO_INCH : $dfcEntry->{precipitation}{snowHigh});
    sendToLox($toMS, $doLog, "dfc${per}_w_sp_h", !$metric ? $dfcEntry->{wind}{max}{speed}*KMH_TO_MPH : $dfcEntry->{wind}{max}{speed});
    sendToLox($toMS, $doLog, "dfc${per}_w_gu_h", !$metric ? $dfcEntry->{wind}{max}{gust}*KMH_TO_MPH : $dfcEntry->{wind}{max}{gust});
    sendToLox($toMS, $doLog, "dfc${per}_w_dirdes_h", encode_utf8($langData->{wind_directions}{getWindDirCardinal($dfcEntry->{wind}{max}{direction}) // ''} // '-')); 
    sendToLox($toMS, $doLog, "dfc${per}_w_dir_h", $dfcEntry->{wind}{max}{direction});
    sendToLox($toMS, $doLog, "dfc${per}_w_sp_a", !$metric ? $dfcEntry->{wind}{avg}{speed}*KMH_TO_MPH : $dfcEntry->{wind}{avg}{speed});
    sendToLox($toMS, $doLog, "dfc${per}_w_gu_a", !$metric ? $dfcEntry->{wind}{avg}{gust}*KMH_TO_MPH : $dfcEntry->{wind}{avg}{gust});
    sendToLox($toMS, $doLog, "dfc${per}_w_dirdes_a", encode_utf8($langData->{wind_directions}{getWindDirCardinal($dfcEntry->{wind}{avg}{direction}) // ''} // '-')); 
    sendToLox($toMS, $doLog, "dfc${per}_w_dir_a", $dfcEntry->{wind}{avg}{direction});
    sendToLox($toMS, $doLog, "dfc${per}_hu_a", $dfcEntry->{humidity}{avg});
    sendToLox($toMS, $doLog, "dfc${per}_hu_h", $dfcEntry->{humidity}{max});
    sendToLox($toMS, $doLog, "dfc${per}_hu_l", $dfcEntry->{humidity}{min});
    sendToLox($toMS, $doLog, "dfc${per}_we_code", w4l_to_oldW4lCode($dfcEntry->{weatherCode}{weather4lox}));
    sendToLox($toMS, $doLog, "dfc${per}_we_code_lox", $dfcEntry->{weatherCode}{loxone});
    sendToLox($toMS, $doLog, "dfc${per}_we_des", encode_utf8($langData->{weather_descriptions}{$dfcEntry->{weatherCode}{weather4lox}} // '-'));
    sendToLox($toMS, $doLog, "dfc${per}_ozone", _jval($dfcEntry->{airQuality}{ozone}));
    sendToLox($toMS, $doLog, "dfc${per}_moon_p", $dfcEntry->{moon}{percent});
    sendToLox($toMS, $doLog, "dfc${per}_dp", !$metric ? $dfcEntry->{dewpoint}*C_TO_F_FACTOR+C_TO_F_OFFSET : $dfcEntry->{dewpoint});
    sendToLox($toMS, $doLog, "dfc${per}_pr", !$metric ? $dfcEntry->{pressure}*HPA_TO_INHG : $dfcEntry->{pressure});
    sendToLox($toMS, $doLog, "dfc${per}_uvi", $dfcEntry->{uvIndex});
    sendToLox($toMS, $doLog, "dfc${per}_vis", !$metric ? $dfcEntry->{visibility}*KMH_TO_MPH : $dfcEntry->{visibility});
    sendToLox($toMS, $doLog, "dfc${per}_moon_a", $dfcEntry->{moon}{age});
    sendToLox($toMS, $doLog, "dfc${per}_moon_ph", $dfcEntry->{moon}{phase});
    sendToLox($toMS, $doLog, "dfc${per}_sun_r", $dfcDate_LoxoneEpoch + timeToSec($dfcEntry->{sunrise}));
    sendToLox($toMS, $doLog, "dfc${per}_sun_s", $dfcDate_LoxoneEpoch + timeToSec($dfcEntry->{sunset}));

    my $iconName = $iconMapping->{icons}{$dfcEntry->{weatherCode}{weather4lox}}{"iconDay"};

    # special handling for sunrise and sunset: send as loxone epoch time to Loxone for easier processing,
    # but need to be in hh:mm format on theme web page
    { 
        no strict 'refs';
        ${"dfc${per}_sun_r"} = $dfcEntry->{sunrise};
        ${"dfc${per}_sun_s"} = $dfcEntry->{sunset};
        ${"dfc${per}_we_icon"} = $iconName . "." . ($iconMapping->{format} // 'no_format');
    }
        
    $doLog = 0;
}

#
# Send hourly forecast to Loxone via HTML webpage, MQTT and UDP
#

LOGINF "--------------------------------------------------------------------------------";
LOGINF "Sending hourly weather forecast to Loxone ...";

$doLog = 1; # log the first data set in detail, but not all subsequent ones to avoid log flooding
foreach my $hfcEntry (@$hfc) {

    # Hours starting with 1, (hfc1) ...
    my $per = $hfcEntry->{hour};

    # Check if we should send this period to MS via MQTT and UDP
    $toMS = $hfcAllowed->{$per};

    LOGINF "Processing hourly forecast entry for hour $per (hfc${per}) with date " . $hfcEntry->{time}{datetime} . ($toMS ? " and sending data to MS (as configured)." : ", but not sending data to MS (as configured).");

    # Stop after 72 datasets (3 days * 24 hours) to avoid sending too many datasets to Loxone, which can cause performance issues
    if ( $per > 72 ) { last; }

    # Times are send in local time 
    my $hfc_date = DateTime->from_epoch(epoch => $hfcEntry->{time}{epoch}, time_zone => $location->{timezone});

    # sending to Loxone Miniserver via MQTT, HTML webpage and UDP with logging of first hour in detail
    sendToLox($toMS, $doLog, "hfc${per}_per", $per);
    sendToLox($toMS, $doLog, "hfc${per}_date", toLoxEpoch($hfcEntry->{time}{epoch}));
    sendToLox($toMS, $doLog, "hfc${per}_day", encode_utf8(sprintf("%02d", $hfc_date->day)));
    sendToLox($toMS, $doLog, "hfc${per}_month", encode_utf8(sprintf("%02d", $hfc_date->month)));
    sendToLox($toMS, $doLog, "hfc${per}_monthn", encode_utf8($hfc_date->month_name));
    sendToLox($toMS, $doLog, "hfc${per}_monthn_sh", encode_utf8($hfc_date->month_abbr));
    sendToLox($toMS, $doLog, "hfc${per}_year", encode_utf8($hfc_date->year));
    sendToLox($toMS, $doLog, "hfc${per}_hour", encode_utf8(sprintf("%02d", $hfc_date->hour)));
    sendToLox($toMS, $doLog, "hfc${per}_min", encode_utf8(sprintf("%02d", $hfc_date->minute)));
    sendToLox($toMS, $doLog, "hfc${per}_wday", encode_utf8($hfc_date->day_name));
    sendToLox($toMS, $doLog, "hfc${per}_wday_sh", encode_utf8($hfc_date->day_abbr));
    sendToLox($toMS, $doLog, "hfc${per}_tt", !$metric ? $hfcEntry->{temperature}{air}*C_TO_F_FACTOR+C_TO_F_OFFSET : $hfcEntry->{temperature}{air});
    sendToLox($toMS, $doLog, "hfc${per}_tt_fl", !$metric ? $hfcEntry->{temperature}{feelsLike}*C_TO_F_FACTOR+C_TO_F_OFFSET : $hfcEntry->{temperature}{feelsLike});
    sendToLox($toMS, $doLog, "hfc${per}_pop", $hfcEntry->{precipitation}{probability});
    sendToLox($toMS, $doLog, "hfc${per}_prec", !$metric ? $hfcEntry->{precipitation}{rainHigh}*MM_TO_INCH : $hfcEntry->{precipitation}{rainHigh});
    sendToLox($toMS, $doLog, "hfc${per}_snow", !$metric ? $hfcEntry->{precipitation}{snowHigh}*CM_TO_INCH : $hfcEntry->{precipitation}{snowHigh});
    sendToLox($toMS, $doLog, "hfc${per}_w_sp", !$metric ? $hfcEntry->{wind}{speed}*KMH_TO_MPH : $hfcEntry->{wind}{speed});
    sendToLox($toMS, $doLog, "hfc${per}_w_gu", !$metric ? $hfcEntry->{wind}{gust}*KMH_TO_MPH : $hfcEntry->{wind}{gust});
    sendToLox($toMS, $doLog, "hfc${per}_w_ch", !$metric ? $hfcEntry->{temperature}{feelsLike}*C_TO_F_FACTOR+C_TO_F_OFFSET : $hfcEntry->{temperature}{feelsLike});
    sendToLox($toMS, $doLog, "hfc${per}_w_dirdes", encode_utf8($langData->{wind_directions}{getWindDirCardinal($hfcEntry->{wind}{direction})} // '-'));
    sendToLox($toMS, $doLog, "hfc${per}_w_dir", $hfcEntry->{wind}{direction});
    sendToLox($toMS, $doLog, "hfc${per}_hu", $hfcEntry->{humidity});
    sendToLox($toMS, $doLog, "hfc${per}_we_code", w4l_to_oldW4lCode($hfcEntry->{weatherCode}{weather4lox}));
    sendToLox($toMS, $doLog, "hfc${per}_we_code_lox", $hfcEntry->{weatherCode}{loxone});
    sendToLox($toMS, $doLog, "hfc${per}_we_des", encode_utf8($langData->{weather_descriptions}{$hfcEntry->{weatherCode}{weather4lox}} // '-'));
    sendToLox($toMS, $doLog, "hfc${per}_ozone", _jval($hfcEntry->{airQuality}{ozone}));
    sendToLox($toMS, $doLog, "hfc${per}_moon_p", $hfcEntry->{moon}{percent});
    sendToLox($toMS, $doLog, "hfc${per}_dp", !$metric ? $hfcEntry->{dewpoint}*C_TO_F_FACTOR+C_TO_F_OFFSET : $hfcEntry->{dewpoint});
    sendToLox($toMS, $doLog, "hfc${per}_pr", !$metric ? $hfcEntry->{pressure}*HPA_TO_INHG : $hfcEntry->{pressure});
    sendToLox($toMS, $doLog, "hfc${per}_uvi", $hfcEntry->{uvIndex});
    sendToLox($toMS, $doLog, "hfc${per}_vis", !$metric ? $hfcEntry->{visibility}*KMH_TO_MPH : $hfcEntry->{visibility});
    sendToLox($toMS, $doLog, "hfc${per}_moon_a", $hfcEntry->{moon}{age});
    sendToLox($toMS, $doLog, "hfc${per}_moon_ph", $hfcEntry->{moon}{phase});
    sendToLox($toMS, $doLog, "hfc${per}_sr", $hfcEntry->{solarRadiation});
    sendToLox($toMS, $doLog, "hfc${per}_hi", !$metric ? $hfcEntry->{temperature}{heatIndex}*C_TO_F_FACTOR+C_TO_F_OFFSET : $hfcEntry->{temperature}{heatIndex});
    sendToLox($toMS, $doLog, "hfc${per}_sky", $hfcEntry->{cloudCover});
    sendToLox($toMS, $doLog, "hfc${per}_sky_des",encode_utf8($langData->{weather_descriptions}{$hfcEntry->{weatherCode}{weather4lox}} // '-'));

    # Use night icons between sunset and sunrise on webpage
    my $iconName;
    if ($hfcEntry->{isNight}) {
        $iconName = $iconMapping->{icons}{$hfcEntry->{weatherCode}{weather4lox}}{"iconNight"};

        # add moon quarter / half to night icon name, if icon sets support this
        $moonPhases = $iconMapping->{icons}{$hfcEntry->{weatherCode}{weather4lox}}{moonPhases} // 0;
        if ($moonPhases == 5) {
            $iconName .= "_" . getMoonPhasePart($hfcEntry->{moon}{age}, 5) . "q";
        } elsif ($moonPhases == 3) {
            $iconName .= "_" . getMoonPhasePart($hfcEntry->{moon}{age}, 3) . "h";
        }
    } else {
        $iconName = $iconMapping->{icons}{$hfcEntry->{weatherCode}{weather4lox}}{"iconDay"};
    }

    { 
        no strict 'refs';
        ${"hfc${per}_we_icon"} = $iconName . "." . ($iconMapping->{format} // 'no_format');
    }
    
    $doLog = 0;
}

#
# Calcualate aggregated values for each 4 hour period and send to Loxone via HTML webpage, MQTT and UDP
#

LOGINF "--------------------------------------------------------------------------------";
LOGINF "Aggregating hourly forecasts (sum, min, max, or mean - depending on the parameter) for next X hours (rain and temperature only) ...";

$toMS = 1;

my @periods = (4, 8, 12, 16, 24, 32, 40, 48);
my %var = (
    prec  => {},
    snow  => {},
    sr    => {},
    ttmin => {},
    ttmax => {},
    ttmean => {},
    popmin => {},
    popmax => {},
);

# Guard: if the hourly forecast is empty (e.g. after an API error) skip
# the aggregation rather than crashing on $hfc->[0] dereference.
if (!@$hfc) {
    LOGWARN "Hourly forecast is empty - skipping aggregation, sending zero defaults.";
}

# Initialize variables for each period with default values (0 for precipitation and solar radiation
# for temperatures and precipitation probability: we use the first record as default value (0 if empty)
for my $p (@periods) {
    $var{prec}{$p}   = 0;
    $var{snow}{$p}   = 0;
    $var{sr}{$p}     = 0;
    $var{ttmin}{$p}  = @$hfc ? ($hfc->[0]{temperature}{air}          // 0) : 0;
    $var{ttmax}{$p}  = @$hfc ? ($hfc->[0]{temperature}{air}          // 0) : 0;
    $var{ttmean}{$p} = [];
    $var{popmin}{$p} = @$hfc ? ($hfc->[0]{precipitation}{probability} // 0) : 0;
    $var{popmax}{$p} = @$hfc ? ($hfc->[0]{precipitation}{probability} // 0) : 0;
}

foreach my $hfcEntry (@$hfc) {

    # Set defaults for the first period object

    for my $p (@periods) {
        next unless $hfcEntry->{hour} <= $p;

        $var{prec}{$p}  += $hfcEntry->{precipitation}{rainHigh} if defined $hfcEntry->{precipitation}{rainHigh} && $hfcEntry->{precipitation}{rainHigh} > 0;
        $var{snow}{$p}  += $hfcEntry->{precipitation}{snowHigh} if defined $hfcEntry->{precipitation}{snowHigh} && $hfcEntry->{precipitation}{snowHigh} > 0;
        
        $var{sr}{$p}    += $hfcEntry->{solarRadiation}  if defined $hfcEntry->{solarRadiation}  && $hfcEntry->{solarRadiation} > 0;

        # For temperature, we take the minimum and maximum value of the included hourly forecasts
        if (defined $hfcEntry->{temperature}{air}) {
            $var{ttmin}{$p} = $hfcEntry->{temperature}{air} if $var{ttmin}{$p} > $hfcEntry->{temperature}{air};
            $var{ttmax}{$p} = $hfcEntry->{temperature}{air} if $var{ttmax}{$p} < $hfcEntry->{temperature}{air};
            push @{ $var{ttmean}{$p} }, $hfcEntry->{temperature}{air};
        }
        # For precipitation probability, we take the minimum and maximum value of the included hourly forecasts
        if (defined $hfcEntry->{precipitation}{probability}) {
            $var{popmin}{$p} = $hfcEntry->{precipitation}{probability} if $var{popmin}{$p} > $hfcEntry->{precipitation}{probability};
            $var{popmax}{$p} = $hfcEntry->{precipitation}{probability} if $var{popmax}{$p} < $hfcEntry->{precipitation}{probability};
        }
    }
}
$doLog = 1;
for my $p (@periods) {
    LOGINF "Aggregating hourly forecasts (sum, min or max - depending on the parameter) for next $p hours (nxh${p}) and sending data to MS.";

    sendToLox($toMS, $doLog, "nxh${p}_prec", !$metric ? sprintf("%.2f", $var{prec}{$p}*MM_TO_INCH) : sprintf("%.2f", $var{prec}{$p}));
    sendToLox($toMS, $doLog, "nxh${p}_snow", !$metric ? sprintf("%.2f", $var{snow}{$p}*CM_TO_INCH) : sprintf("%.2f", $var{snow}{$p}));
    sendToLox($toMS, $doLog, "nxh${p}_sr", sprintf("%.0f", $var{sr}{$p}));
    sendToLox($toMS, $doLog, "nxh${p}_ttmin", !$metric ? sprintf("%.1f", $var{ttmin}{$p}*C_TO_F_FACTOR+C_TO_F_OFFSET) : sprintf("%.1f", $var{ttmin}{$p}));
    sendToLox($toMS, $doLog, "nxh${p}_ttmax", !$metric ? sprintf("%.1f", $var{ttmax}{$p}*C_TO_F_FACTOR+C_TO_F_OFFSET) : sprintf("%.1f", $var{ttmax}{$p}));
    sendToLox($toMS, $doLog, "nxh${p}_ttmean", !$metric ? sprintf("%.1f", mean(@{ $var{ttmean}{$p} })*C_TO_F_FACTOR+C_TO_F_OFFSET) : sprintf("%.1f", mean(@{ $var{ttmean}{$p} })));
    sendToLox($toMS, $doLog, "nxh${p}_popmin", sprintf("%.0f", $var{popmin}{$p}));
    sendToLox($toMS, $doLog, "nxh${p}_popmax", sprintf("%.0f", $var{popmax}{$p}));
    $doLog = 0;
}

# send out all queued name / value pairs via UDP
if ($sendUDP) {
    LOGINF "Sending queued weather data to Loxone via UDP ...";
    sendUDP();
    LOGOK "Data sent to Loxone via UDP finished.";
}

# Close HTML database
open(F,">>$lbplogdir/weatherdata.html") or LOGERR "Cannot open $lbplogdir/weatherdata.html for appending: $!";
flock(F,2);
binmode F, ':encoding(UTF-8)';
print F "</body>\n</html>";
#flock(F,8);
close(F);

#
# Create Webpages for themes and fill them with the current data. 
#

LOGINF "Creating Webpages ...";

our $theme = $stdTheme;
our $iconset = $stdIconSet;
our $mode = $stdMode;
our $themeurlmain = "./webpage.html";
our $themeurldfc = "./webpage.dfc.html";
our $themeurlhfc = "./webpage.hfc.html";
our $themeurlmap = "./webpage.map.html";
our $webpath = "/plugins/$lbpplugindir";

# Register URL/path variables used by old-style themes in the allow-list
$tmpl_vars{$_} = do { no strict 'refs'; ${$_} } for qw(theme iconset mode themeurlmain themeurldfc themeurlhfc themeurlmap webpath);

# new style themes have a single file in webfrontend/html/<pluginname> for CSS, JS and HTML,
# so we check the existance of it first to determine if it's a new style theme
my $newStyleTheme = 0;
if (-e "$lbphtmldir/$theme.theme.html") {
    $newStyleTheme = 1;
}
# interim style themes only use the main template for all views, the specific templates are only used for old style themes
# TODO: we should remove the interim style theme option in the future and make the new style theme the default, 
# but for now we want to give users the chance to switch to the new style theme while still providing a working template for the old style theme
my $interimStyleTheme = 0;
if (!$newStyleTheme && !-e "$lbptemplatedir/themes/$lang/$theme.hfc.html" &&
    !-e "$lbptemplatedir/themes/$lang/$theme.dfc.html") {
  $interimStyleTheme = 1;
}

# fallback to english dark theme if the selected theme or language is not available, as the main template is required for both interim and classic themes
if (!$newStyleTheme && !-e "$lbptemplatedir/themes/$lang/$theme.main.html") {
    $lang = "en";
    $theme = "dark";
}

#############################################
# MAP VIEW
#############################################

if (!$interimStyleTheme && !$newStyleTheme) {
    # Write cached webpage
    open(F1,">$lbplogdir/webpage.map.html") or LOGERR "Cannot open $lbplogdir/webpage.map.html for writing: $!";
    flock(F1,2);
    open(F,"<$lbptemplatedir/themes/$lang/$theme.map.html") or LOGERR "Cannot open $lbptemplatedir/themes/$lang/$theme.map.html: $!";
    {
        while (<F>) {
            $_ =~ s/<!--\$(.*?)-->/
                if (!exists $tmpl_vars{$1}) {
                    LOGWARN "Template variable '\$$1' is undefined (line $. in $lbptemplatedir\/themes\/$lang\/$theme.map.html)";
                    '';
                } else {
                    $tmpl_vars{$1};
                }
            /ge;
            print F1 $_;
        }
    }
    close(F);
    #flock(F1,8);
    close(F1);

    if (-e "$lbplogdir/webpage.map.html") {
        LOGDEB "$lbplogdir/webpage.map.html created.";
    }
} else {
    my $fileToDelete = "$lbplogdir/webpage.map.html";
    if (-e $fileToDelete) {
        unlink $fileToDelete or warn "Delete of file $fileToDelete failed: $!";
    }
}

#############################################
# Daily Forecast
#############################################

if (!$interimStyleTheme && !$newStyleTheme) {
    # Write cached webpage
    open(F1,">$lbplogdir/webpage.dfc.html") or LOGERR "Cannot open $lbplogdir/webpage.dfc.html for writing: $!";
    flock(F1,2);
    open(F,"<$lbptemplatedir/themes/$lang/$theme.dfc.html") or LOGERR "Cannot open $lbptemplatedir/themes/$lang/$theme.dfc.html: $!";
    {
        while (<F>) {
            $_ =~ s/<!--\$(.*?)-->/
                if (!exists $tmpl_vars{$1}) {
                    LOGWARN "Template variable '\$$1' is undefined (line $. in $lbptemplatedir\/themes\/$lang\/$theme.dfc.html)";
                    '';
                } else {
                    $tmpl_vars{$1};
                }
            /ge;
            print F1 $_;
        }
    }
    close(F);
    #flock(F1,8);
    close(F1);

    if (-e "$lbplogdir/webpage.dfc.html") {
        LOGDEB "$lbplogdir/webpage.dfc.html created.";
    }
} else {
    my $fileToDelete = "$lbplogdir/webpage.dfc.html";
    if (-e $fileToDelete) {
        unlink $fileToDelete or warn "Delete of file $fileToDelete failed: $!";
    }
}

#############################################
# Hourly Forecast
#############################################

if (!$interimStyleTheme && !$newStyleTheme) {
    # Write cached webpage
    # If Theme Lang is set, us it instead of system lang
    open(F1,">$lbplogdir/webpage.hfc.html") or LOGERR "Cannot open $lbplogdir/webpage.hfc.html for writing: $!";
    flock(F1,2);
    open(F,"<$lbptemplatedir/themes/$lang/$theme.hfc.html") or LOGERR "Cannot open $lbptemplatedir/themes/$lang/$theme.hfc.html: $!";
    {
        while (<F>) {
            $_ =~ s/<!--\$(.*?)-->/
                if (!exists $tmpl_vars{$1}) {
                    LOGWARN "Template variable '\$$1' is undefined (line $. in $lbptemplatedir\/themes\/$lang\/$theme.hfc.html)";
                    '';
                } else {
                    $tmpl_vars{$1};
                }
            /ge;
            print F1 $_;
        }
    }
    close(F);
    #flock(F1,8);
    close(F1);

    if (-e "$lbplogdir/webpage.hfc.html") {
        LOGDEB "$lbplogdir/webpage.hfc.html created.";
    }
} else {
    my $fileToDelete = "$lbplogdir/webpage.hfc.html";
    if (-e $fileToDelete) {
        unlink $fileToDelete or warn "Delete of file $fileToDelete failed: $!";
    }
}

#############################################
# CURRENT CONDITIONS
#############################################

my $sourceFile;
my $destFile;

if (!$newStyleTheme) {
    # get main template for current conditions with classic style or all conditions with intermediate style themes
    $sourceFile  = "$lbptemplatedir/themes/$lang/$theme.main.html";
} else {
    # new style themes only have a single 'template' that contains a redirect to to the specific theme file in the webfrontend/html/<pluginname> directory
    $sourceFile  = "$lbptemplatedir/themes/new-style.theme.html";
    # Create variable for searching and replacing in templates for themes (in case of old-style themes)
    my $_themeurl = "./$theme.theme.html?iconset=$iconset&lang=$lang&mode=$mode";
    { no strict 'refs'; ${'themeurl'} = $_themeurl }
    $tmpl_vars{'themeurl'} = $_themeurl;
}

$destFile = "$lbplogdir/webpage.html";

# Write cached webpage
open(F1,">$destFile.tmp") or LOGERR "Cannot open $destFile.tmp for writing: $!";
flock(F1,2);
open(F,"<$sourceFile") or LOGERR "Cannot open $sourceFile: $!";
{
    while (<F>) {
        $_ =~ s/<!--\$(.*?)-->/
            if (!exists $tmpl_vars{$1}) {
                LOGWARN "Template variable '\$$1' is undefined (line $. in $sourceFile)";
                '';
            } else {
                $tmpl_vars{$1};
            }
        /ge;
        print F1 $_;
    }
}
close(F);
#flock(F1,8);
close(F1);

# Move temp file to final destination
move($destFile . ".tmp", $destFile) or warn "Move of file $destFile.tmp to $destFile failed: $!";

if (-e $destFile) {
    LOGDEB "$destFile created.";
}

LOGOK "Webpages created successfully.";

#
# Create Cloud Weather Emulator files for current conditions, daily and hourly forecast.
#

# Mapping of the documented Loxone Picto-Codes from https://www.loxone.com/dede/kb/weather-service/
# to the codes used in the Weather Emulator
my %loxToEmu = (
    1  => 1,   # Wolkenlos (day/night)
    2  => 2,   # Heiter (day/night)
    3  => 7,   # Wolkig (day/night)
    4  => 19,  # Stark bewölkt (day/night)
    5  => 22,  # Bedeckt
    6  => 16,  # Nebel
    7  => 22,  # Hochnebel -> Bedeckt
    8  => 8,   # nicht verwendet
    9  => 9,   # nicht verwendet
    10 => 33,  # Leichter Regen
    11 => 23,  # Regen
    12 => 25,  # Starker Regen
    13 => 33,  # Nieseln -> Leichter Regen
    14 => 35,  # Leichter gefrierender Regen -> Schneeregen
    15 => 35,  # Starker gefrierender Regen -> Schneeregen
    16 => 31,  # Leichter Regenschauer
    17 => 25,  # Kräftiger Regenschauer -> Starker Regen
    18 => 28,  # Gewitter
    19 => 27,  # Kräftiges Gewitter
    20 => 24,  # Leichter Schneefall -> Schneefall
    21 => 24,  # Schneefall
    22 => 26,  # Starker Schneefall
    23 => 32,  # Leichter Schneeschauer
    24 => 29,  # Starker Schneeschauer (gleiches Symbol wie Starker Schneefall)
    25 => 35,  # Leichter Schneeregen -> Schneeregen
    26 => 35,  # Schneeregen
    27 => 35,  # Starker Schneeregen -> Schneeregen
    28 => 35,  # Leichter Schneeregenschauer -> Schneeregen
    29 => 35,  # Kräftiger Schneeregenschauer -> Schneeregen
);

# Not mapped codes (because not supported by the Weather Emulator):
#  7 = Hochnebel
# 13 = Nieseln
# 14 = leichter gefrierender Regen
# 15 = starker gefrierender Regen
# 17 = kräftiger Regenschauer
# 20 = leichter Schneefall
# 23 = leichter Schneeschauer
# 24 = starker Schneeschauer
# 25 = leichter Schneeregen
# 27 = starker Schneeregen
# 28 = leichter Schneeregenschauer
# 29 = kräftiger Schneeregenschauer

# Used weather symbols in Loxone Weather Emulator (by testing, not documented by Loxone):
#  1 - wolkenlos
#  2 - heiter
#  3 - heiter
#  4 - heiter
#  5 - heiter
#  6 - heiter
#  7 - wolkig
#  8 - wolkig
#  9 - wolkig
# 10 - wolkig
# 11 - wolkig
# 12 - wolkig
# 13 - wolkenlos
# 14 - heiter
# 15 - heiter
# 16 - Nebel
# 17 - Nebel
# 18 - Nebel
# 19 - stark bewölkt
# 20 - stark bewölkt
# 21 - stark bewölkt
# 22 - bedeckt
# 23 - Regen
# 24 - Schneefall
# 25 - starker Regen
# 26 - starker Schneefall
# 27 - kräftiges Gewitter
# 28 - Gewitter
# 29 - starker Schneeschauer
# 30 - kräftiges Gewitter
# 31 - leichter Regenschauer
# 32 - leichter Schneeschauer
# 33 - leichter Regen
# 34 - leichter Schneeschauer
# 35 - Schneeregen

# Original from Loxone Testserver: (ccord changed)
# http://weather.loxone.com:6066/forecast/?user=loxone_EExxxxxxx000F&coord=13.1,54.1768&format=1&asl=115
#        ^                  ^                          ^                  ^            ^        ^
#        URL                Port                       MS MAC             Coord        Format   Height
#
# The format could be 1 or 2, although Miniserver only seems to use format=1
# (format=2 is xml-output, but with less weather data)
# The height is the geogr. height of your installation (seems to be used for windspeed etc.). You
# can give the heights in meter or set this to auto or left blank (=auto).

if ($emu) {

    LOGINF "Creating Files for Cloud Weather Emulator...";

    #############################################
    # CURRENT CONDITIONS
    #############################################

    # Original file has 169 entrys, but always starts at 0:00 today or 12:00 yesterday. We always start with current data
    # (we don't have historical data) and offer 168 hourly forcast datasets. This seems to be ok for the miniserver.

    # Derive timezone offset string for emulator header (e.g. "UTC+1.00")
    my $emuTzOffset = sprintf("UTC%+06.2f", $tzseconds / 3600);

    # Calculate precipitation in the last hour and snow fraction for current conditions
    my $rain_1hr_mm = $cur->{precipitation}{rain1hr} // 0;
    my $snow_1hr_cm = $cur->{precipitation}{snow1hr} // 0;
    my $precip_1hr = $rain_1hr_mm + $snow_1hr_cm ;                                                    # 1cm snow counts as 1mm
    my $snow_fraction = $rain_1hr_mm > 0 ? $snow_1hr_cm / $precip_1hr : ($snow_1hr_cm > 0 ? 1 : 0);   # Snow fraction in precipitation in %
    my $precip_prob = $cur->{precipitation}{probability} // 0;

    open(F,">$lbplogdir/index.txt") or LOGERR "Cannot open $lbplogdir/index.txt for writing: $!";
    flock(F,2);
    # Write header with meta data and location (semicolon separated, in the order expected by Loxone)
    print F "<mb_metadata>\n";
    print F "id;name;longitude;latitude;height (m.asl.);country;timezone;utc-timedifference;sunrise;sunset;\n";
    print F "local date;weekday;local time;temperature(C);feeledTemperature(C);windspeed(km/h);winddirection(degr);wind gust(km/h);low clouds(%);medium clouds(%);high clouds(%);precipitation(mm);probability of Precip(%);snowFraction;sea level pressure(hPa);relative humidity(%);CAPE;picto-code;radiation (W/m2);\n";
    print F "</mb_metadata>\n";
    print F "<valid_until>" . (($curDate->year)+5) . "-12-31</valid_until>\n";
    print F "<station>\n";
    print F ";" . ($location->{city} // "-") . ";" . ($location->{longitude} // "0") . ";" . ($location->{latitude} // "0");
    print F ";" . ($location->{elevation} // "0") . ";" . ($location->{country} // "-") . ";" . ($location->{tzShort} // "UTC") . ";" . ($emuTzOffset // "+0.00");
    print F ";" . ($cur->{sunrise} // "-") . ";" . ($cur->{sunset} // "-") . ";\n";
    # Data line for current conditions (semicolon separated, in the order expected by Loxone)
    print F $curDate->strftime('%d.%m.%Y') . ";\t";                      # Local date in format "dd.mm.yyyy"
    print F $curDate->day_abbr() . ";\t";                                # Weekday (abbreviated)
    printf F "%02d;\t",$curDate->hour();                                 # Local time (hour)
    printf F "%1.2f;\t", $cur->{temperature}{air};                       # Temperature in Celsius
    printf F "%1.1f;\t", $cur->{temperature}{feelsLike} // $cur->{temperature}{air} // 0 ;       # Feels like temperature in Celsius
    printf F "%1d;\t", $cur->{wind}{speed} // 0;                         # Wind speed in km/h
    printf F "%1d;\t", $cur->{wind}{direction} // 0;                     # Wind direction in degrees
    printf F "%1d;\t", $cur->{wind}{gust} // $cur->{wind}{speed} // 0;   # Wind gust in km/h
    printf F "%1d;\t", 0;                                                # Low clouds in %
    printf F "%1d;\t", 0;                                                # Medium clouds in %
    printf F "%1d;\t", 0;                                                # High clouds in %
    printf F "%1.1f;\t", $precip_1hr // 0;                               # Precipitation in mm
    printf F "%1d;\t", $precip_prob // 0;                                # Probability of precipitation in % 
    printf F "%1.1f;\t", $snow_fraction * 100;                           # Snow fraction in precipitation in %   
    printf F "%1d;\t", $cur->{pressure} // 0;                            # Sea level pressure in hPa
    printf F "%1d;\t", $cur->{humidity} // 0;                            # Relative humidity in %
    printf F "%1d;\t", 0;                                                # CAPE, Convective Available Potential Energy in J/kg, indicator for thunderstorm potential and strength (not available in Weather4Lox, so set to 0)
    printf F "%1d;\t", $loxToEmu{int($cur->{weatherCode}{loxone} // 1)}; # Picto code (mapped from Loxone code to Weather Emulator code)
    printf F "%1.2f;\n", $cur->{solarRadiation} // 0;                    # Solar radiation in W/m2
    #flock(F,8);
    close(F);

    #############################################
    # HOURLY FORECAST
    #############################################

    # Original file has 169 entrys, but always starts at 0:00 today or 12:00 yesterday. We always start with current data
    # 7 days * 24 hours = 168 datasets. It is unclear why the ms needs 7 days, because the emulator only displays 'today', 'tomorrow' and 'day after tomorrow'.

    $i = 0;

    open(F,">>$lbplogdir/index.txt") or LOGERR "Cannot open $lbplogdir/index.txt for appending: $!";
    flock(F,2);

    foreach my $hfcEntry (@$hfc) {

        # skip datasets in the past
        if ( $hfcEntry->{time}{epoch} < $cur->{time}{epoch} ) { next; } 

        # Stop after 168 datasets (7 days * 24 hours), because the original file has 169 datasets
        if ( $i >= 168 ) { last; }

        # Construct hfc date from epoch (per Research Pattern 7)
        my $hfc_date = DateTime->from_epoch(epoch => $hfcEntry->{time}{epoch}, time_zone => $location->{timezone});

        # Calculate precipitation in the last hour and snow fraction for current conditions
        my $rain_mm = $hfcEntry->{precipitation}{rainHigh} // 0;
        my $snow_cm = $hfcEntry->{precipitation}{snowHigh} // 0;
        my $precip_1hr = $rain_mm + $snow_cm ;                                                # 1cm snow counts as 1mm
        my $snow_fraction = $rain_mm > 0 ? $snow_cm / $precip_1hr : ($snow_cm > 0 ? 1 : 0);   # Snow fraction in precipitation in %
        my $precip_prob = $hfcEntry->{precipitation}{probability} // 0;

        # "local date;weekday;local time;temperature(C);feeledTemperature(C);windspeed(km/h);winddirection(degr);wind gust(km/h);low clouds(%);medium clouds(%);high clouds(%);precipitation(mm);probability of Precip(%);snowFraction;sea level pressure(hPa);relative humidity(%);CAPE;picto-code;radiation (W/m2);\n";
        print F $hfc_date->strftime('%d.%m.%Y') . ";\t";                           # Local date in format "dd.mm.yyyy"
        print F $hfc_date->day_abbr() . ";\t";                                     # Weekday abbreviation
        printf F "%02d;\t",$hfc_date->hour();                                      # Local hour
        printf F "%1.2f;\t", $hfcEntry->{temperature}{air} // 0;                   # Temperature in Celsius
        printf F "%1.2f;\t", $hfcEntry->{temperature}{feelsLike} // 0;             # Feels like temperature in Celsius
        printf F "%1d;\t", $hfcEntry->{wind}{speed} // 0;                          # Wind speed in km/h
        printf F "%1d;\t", $hfcEntry->{wind}{direction} // 0;                      # Wind direction in degrees
        printf F "%1d;\t", $hfcEntry->{wind}{gust} // 0;                           # Wind gust in km/h
        printf F "%1d;\t", $hfcEntry->{clouds}{low} // 0;                          # Low clouds in %
        printf F "%1d;\t", $hfcEntry->{clouds}{medium} // 0;                       # Medium clouds in %
        printf F "%1d;\t", $hfcEntry->{clouds}{high} // 0;                         # High clouds in %
        printf F "%1.1f;\t", $precip_1hr // 0;                                     # Precipitation in mm
        printf F "%1d;\t", $precip_prob // 0;                                      # Probability of precipitation in %
        printf F "%1.1f;\t", $snow_fraction * 100 // 0;                            # Snow fraction in %
        printf F "%1d;\t", $hfcEntry->{pressure} // 0;                             # Sea level pressure in hPa
        printf F "%1d;\t", $hfcEntry->{humidity} // 0;                             # Relative humidity in %
        printf F "%1d;\t", 0;                                                      # CAPE, Convective Available Potential Energy in J/kg
        printf F "%1d;\t", $loxToEmu{int($hfcEntry->{weatherCode}{loxone} // 1)};  # Picto code 
        printf F "%1.2f;\n", $hfcEntry->{solarRadiation} // 0;                     # Solar radiation in W/m2 

        $i++;
    }
    print F "</station>\n";

    #flock(F,8);
    close(F);

    LOGOK "Files for Cloud Weather Emulator created successfully.";
}

# Finish
LOGOK "We are done. Good bye.";
exit;


##########################################################################
# Send data to Loxone (HTML, MQTT, UDP)
# Parameter:
#   toMS:      if set to 1, data will be sent to Miniserver via MQTT and UDP,
#              otherwise only variables for themes HTML web page will be created
#   name:      name of value (e.g. "current_temperature")
#   value:     value to send (e.g. "20.5")

sub sendToLox {
    my ($toMS, $doLog, $name, $value) = @_;

    if (!defined($value)) {
      $value = 0;
    }
    # Create variable for searching and replacing in templates for themes (in case of old-style themes).
    # Also record the name in %tmpl_vars so that template rendering can use an allow-list lookup
    # instead of blindly dereferencing any package variable.
    { no strict 'refs'; ${$name} = $value }
    $tmpl_vars{$name} = $value;

    # Log data if defined (reduce loggin amount)
    if (defined $doLog && $doLog) {
        LOGINF "Adding value to weatherdata.html      $name\@$value";
    }

    # Add weather data to HTML webpage
    open(F,">>$lbplogdir/weatherdata.html") or do { LOGERR "Cannot open $lbplogdir/weatherdata.html for appending: $!"; return; };
    flock(F,2);
        binmode F, ':encoding(UTF-8)';
        print F "$name\@$value<br>\n";
    #flock(F,8);
    close(F);

    return if !$toMS; # only send to miniserver if $toMS is set to 1, otherwise only create variables for themes

    # Send weather data via MQTT to Loxone
    sendMQTT($doLog, $name, $value);

    # Add weather data to queue to send them later via UDP to Loxone
    if ($sendUDP) {
        $sendUDPqueue .= "$name\@$value; ";
        LOGINF "Adding value to UDP send queue        $name\@$value";
    }

    return();
}

##########################################################################
# Send queued udp data to Loxone via UDP
# Parameter:
#   none - $sendUDPqueue was filled by send() function and is defined globally

sub sendUDP {

    my $msno = defined $pcfg->param("SERVER.MSNO") ? $pcfg->param("SERVER.MSNO") : 1;
    my %miniservers = LoxBerry::System::get_miniservers();
    if ($miniservers{$msno}{IPAddress} ne "" && $udpport ne "") {
        LOGINF "Sending weather data via UDP to " . $miniservers{$msno}{Name}. " IP:" . $miniservers{$msno}{IPAddress} . " Port:$udpport";
        # Send value
        my $sock = IO::Socket::INET->new(
            Proto    => 'udp',
            PeerPort => $udpport,
            PeerAddr => $miniservers{$msno}{IPAddress},
        );
        $sock->send($sendUDPqueue);
        LOGOK "Sent weather data via UDP to " . $miniservers{$msno}{Name} . ". is done.";
        Time::HiRes::usleep (10000); # 10 Milliseconds
    }
    $sendUDPqueue = "";
    return();
}


# Null-safe value helper: return -9999 for undef (JSON null) where Loxone expects it
sub _jval {
    my ($v) = @_;
    return defined($v) ? $v : -9999;
}

##########################################################################
# Send data to Loxone via MQTT
# Parameter:
#   doLog:     if set to 1, data will be logged, otherwise not
#   name:      name of value (e.g. "current_temperature")
#   value:     value to send (e.g. "20.5")

sub sendMQTT {
    my ($doLog, $name, $value) = @_;

    if ($sendMQTT) {
        eval {
            $name =~ s/\+/\_\_/g;
            # Log data if defined (reduce loggin amount)
            if (defined $doLog && $doLog) {
                LOGINF "Publishing value to MQTT: " . $topic . "/" . $name . " " . $value;
            }
            $mqtt->retain($topic . "/" . $name, $value);
        };
        if ($@) {
            my $error = $@ || 'Unknown failure';
            LOGERR "An error occurred - $error";
        };
    };
}

sub mqttconnect
{

    $ENV{MQTT_SIMPLE_ALLOW_INSECURE_LOGIN} = 1;

    # From LoxBerry 3.0 on, we have MQTT onboard
    my $mqttcred = LoxBerry::IO::mqtt_connectiondetails();
    my $mqtt_username = $mqttcred->{brokeruser};
    my $mqtt_password = $mqttcred->{brokerpass};
    my $mqttbroker = $mqttcred->{brokerhost};
    my $mqttport = $mqttcred->{brokerport};

    if (!$mqttbroker || !$mqttport) {
        return();
    } else {
        $sendMQTT = 1;
    }

    # Connect
    eval {
        LOGINF "Connecting to MQTT Broker";
        $mqtt = Net::MQTT::Simple->new($mqttbroker . ":" . $mqttport);
        if( $mqtt_username and $mqtt_password ) {
            if ($maskKeys) {
                LOGDEB "MQTT Login with Username and Password: Sending $mqtt_username ***MASKED***";
            } else {
                LOGDEB "MQTT Login with Username and Password: Sending $mqtt_username $mqtt_password";
            }
            $mqtt->login($mqtt_username, $mqtt_password);
        }
    };
    if ($@ || !$mqtt) {
        my $error = $@ || 'Unknown failure';
        LOGERR "An error occurred - $error";
        $sendMQTT = 0;
        return();
    };

    # Update Plugin Status
    LOGINF "Publishing " . $topic . "/plugin/lastupdate_epoche" . " " . time();
    $mqtt->retain($topic . "/plugin/lastupdate_epoche", time());

    return();

};

END
{
  LOGEND;
}
