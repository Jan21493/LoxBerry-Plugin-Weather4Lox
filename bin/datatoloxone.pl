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

#use strict;
#use warnings;

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
use File::HomeDir;
use JSON::PP ();
use utf8;
use Encode qw(encode_utf8);

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
our $stdtheme         = $pcfg->param("WEB.THEME");
our $stdiconset       = $pcfg->param("WEB.ICONSET");
our $topic            = $pcfg->param("SERVER.TOPIC");
our $sendMQTT         = 0;
our $mqtt;
our $data;

# Language
our $lang = lblanguage();

# Create a logging object
my $log = LoxBerry::Log->new (
    package => 'weather4lox',
    name => 'datatoloxone',
    logdir => "$lbplogdir",
    #filename => "$lbplogdir/weather4lox.log",
    #append => 1,
);

# Commandline options
my $verbose = '';

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 });

# Due to a bug in the Logging routine, set the loglevel fix to 3
#$log->loglevel(3);
if ($verbose) {
        $log->stdout(1);
        $log->loglevel(7);
}

LOGSTART "Weather4Lox DATATOLOXONE process started";
LOGDEB "This is $0 Version $version";

require "$lbpbindir/grabber_utils.pl";
requireOrLogdie('DateTime::Format::ISO8601');


##########################################################################
# Main program
##########################################################################

my $i;

# Create new HTML page with all weather data
open(F,">$lbplogdir/weatherdata.html");
flock(F,2);
binmode F, ':encoding(UTF-8)';
print F "<!DOCTYPE HTML>\n<html>\n<head>\n";
print F "<meta http-equiv='Content-Type' content='text/html; charset=utf-8'>\n</head>\n<body>";
flock(F,8);
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

my $weatherKey = "dailyforecast";
my $envelope = readJsonFile($lbplogdir, $weatherKey);
my $dfc = $envelope->{$weatherKey} // [];

my $weatherKey = "hourlyforecast";
my $envelope = readJsonFile($lbplogdir, $weatherKey);
my $hfc = $envelope->{$weatherKey} // [];

my $iconMapping = readJsonFile("$lbphtmldir/icons/$stdiconset", "icon_mapping") // {};

LOGOK "JSON data files loaded successfully.";

##########################################################################
# Send current conditions to Loxone via HTML webpage, MQTT and UDP
##########################################################################

# Send all values to Loxone via HTML webpage and prepare param/value for theme web pages,
# but send only some values to MS via MQTT and UDP - $toMS is used for values that should be sent to MS
my $toMS = 1;

LOGINF "---------------------------------------------- Sending current weather data to Loxone ...";

# Queue for UDP sending - filled by send() function and sent by sendUDP() function
our $sendUDPqueue;

# Get timezone offset in seconds from tz_offset, e.g. "+0100" => 3600, "-0230" => -9000
my $tzseconds = tzOffsetSeconds($cur->{time}{tzOffset} // "");

# Times are send in local time 
my $curDate = DateTime->from_epoch(epoch => $cur->{time}{epoch}, time_zone => $location->{timezone});
my $curDateMidnight = $curDate->clone->set(hour => 0, minute => 0, second => 0);
my $curDateLoxEpoch = toLoxEpoch($curDateMidnight->epoch);

# TODO: To be verified if + $tzseconds is correct 
sendToLox($toMS, "cur_date", toLoxEpoch($cur->{time}{epoch}));                                         # Loxone epoch (1.1.2009, MEZ), e.g. 542934004
sendToLox($toMS, "cur_date_des", $cur->{time}{datetime});                                                 # was RFC822, now ISO 8601, e.g. Mon, 16 Mar 2026 23:00:04 +0100
sendToLox($toMS, "cur_date_tz_des_sh", $cur->{time}{timezone});                                           # IANA timezone name, e.g. Europe/Berlin
sendToLox($toMS, "cur_date_tz_des", $cur->{time}{tzShort});                                              # Time Zone Abbreviation, e.g. CET
sendToLox($toMS, "cur_date_tz", $cur->{time}{tzOffset});                                                 # Numeric timezone offset, e.g. +0100
sendToLox($toMS, "cur_day", sprintf("%02d", $curDate->day));
sendToLox($toMS, "cur_month", sprintf("%02d", $curDate->month));
sendToLox($toMS, "cur_year", $curDate->year);
sendToLox($toMS, "cur_hour", sprintf("%02d", $curDate->hour));
sendToLox($toMS, "cur_min", sprintf("%02d", $curDate->minute));
sendToLox($toMS, "cur_loc_n", $location->{city});
sendToLox($toMS, "cur_loc_c", $location->{country});
sendToLox($toMS, "cur_loc_ccode", $location->{countryCode});
sendToLox($toMS, "cur_loc_lat", $location->{latitude});
sendToLox($toMS, "cur_loc_long", $location->{longitude});
sendToLox($toMS, "cur_loc_el", $location->{elevation});
sendToLox($toMS, "cur_tt", !$metric ? $cur->{temperature}{air}*1.8+32 : $cur->{temperature}{air});
sendToLox($toMS, "cur_tt_fl", !$metric ? $cur->{temperature}{feelsLike}*1.8+32 : $cur->{temperature}{feelsLike});
sendToLox($toMS, "cur_hu", $cur->{humidity});
sendToLox($toMS, "cur_w_dirdes", $cur->{wind}{dirLabel});
sendToLox($toMS, "cur_w_dir", $cur->{wind}{direction});
sendToLox($toMS, "cur_w_sp", !$metric ? $cur->{wind}{speed}*0.621371192 : $cur->{wind}{speed});
sendToLox($toMS, "cur_w_gu", !$metric ? $cur->{wind}{gust}*0.621371192 : $cur->{wind}{gust});
sendToLox($toMS, "cur_w_ch", !$metric ? $cur->{temperature}{windChill}*1.8+32 : $cur->{temperature}{windChill});
sendToLox($toMS, "cur_pr", !$metric ? $cur->{pressure}*0.0295301 : $cur->{pressure});
sendToLox($toMS, "cur_dp", !$metric ? $cur->{dewpoint}*1.8+32 : $cur->{dewpoint});
sendToLox($toMS, "cur_vis", !$metric ? $cur->{visibility}*0.621371192 : $cur->{visibility});
sendToLox($toMS, "cur_sr", $cur->{solarRadiation});
sendToLox($toMS, "cur_hi", !$metric ? $cur->{temperature}{heatIndex}*1.8+32 : $cur->{temperature}{heatIndex});
sendToLox($toMS, "cur_uvi", $cur->{uvIndex});
sendToLox($toMS, "cur_pop", $cur->{precipitation}{probability});
sendToLox($toMS, "cur_prec_today", !$metric ? $cur->{precipitation}{rainToday}*0.0393700787 : $cur->{precipitation}{rainToday});
sendToLox($toMS, "cur_prec_1hr", !$metric ? $cur->{precipitation}{rain1hr}*0.0393700787 : $cur->{precipitation}{rain1hr});
sendToLox($toMS, "cur_snow", !$metric ? $cur->{precipitation}{snowToday}*0.393700787 : $cur->{precipitation}{snowToday});
sendToLox($toMS, "cur_we_icon", $cur->{weatherCode}{weather4lox});
sendToLox($toMS, "cur_we_code", $cur->{weatherCode}{loxone});
sendToLox($toMS, "cur_we_des", encode_utf8($cur->{weatherCode}{description}));
sendToLox($toMS, "cur_moon_p", $cur->{moon}{percent});
sendToLox($toMS, "cur_moon_a", $cur->{moon}{age});
sendToLox($toMS, "cur_moon_ph", $cur->{moon}{phase});
sendToLox($toMS, "cur_moon_h", $cur->{moon}{direction});
sendToLox($toMS, "cur_sun_r", $curDateLoxEpoch + timeToSec($cur->{sunrise}));
sendToLox($toMS, "cur_sun_s", $curDateLoxEpoch + timeToSec($cur->{sunset}));
sendToLox($toMS, "cur_ozone", $cur->{ozone});
sendToLox($toMS, "cur_sky", $cur->{cloudCover});

# special handling for sunrise and sunset: send as loxone epoch time to Loxone for easier processing,
# but need to be in hh:mm format on theme web page
${"cur_sun_r"} = $cur->{sunrise};
${"cur_sun_s"} = $cur->{sunset};

# Use night icons between sunset and sunrise
my $curSec = timeToSec($curDate->hour . ":" . $curDate->minute);
my $sunriseSec = timeToSec($cur->{sunrise}) // 6;
my $sunsetSec = timeToSec($cur->{sunset}) // 18;
my $iconName;

if ($curSec < $sunriseSec || $curSec > $sunsetSec) {
    $iconName = $iconMapping->{icons}{$cur->{weatherCode}{weather4lox}}{"iconNight"};

    # add moon quarter / half to night icon name, if icon sets demands this
    my $moonPhases = $iconMapping->{icons}{$cur->{weatherCode}{weather4lox}}{moonPhases} // 0;
    if ($moonPhases == 5) {
        $iconName .= "_" . getMoonPhasePart($cur->{moon}{age}, 5) . "q";
    } elsif ($moonPhases == 3) {
        $iconName .= "_" . getMoonPhasePart($cur->{moon}{age}, 3) . "h";
    }
} else {
    $iconName = $iconMapping->{icons}{$cur->{weatherCode}{weather4lox}}{"iconDay"};
}
${"cur_we_icon"} = $iconName . "." . $iconMapping->{format};

#
# Send daily forecast to Loxone via HTML webpage, MQTT and UDP
#

LOGINF "-------------------------------------- Sending daily weather forecast to Loxone ...";

foreach my $dfcEntry (@$dfc) {

    # Today is dfc0, tomorrow is dfc1, ...
    my $per = $dfcEntry->{day};

    # Check if we should send this period to MS via MQTT and UDP
    $toMS = $dfcAllowed->{$per + 1};

    LOGDEB "Processing daily forecast entry for period $per (day$per) with date " . $dfcEntry->{time}{datetime} . ".";

    # Times are send in local time 
    my $dfcDate = DateTime->from_epoch(epoch => $dfcEntry->{time}{epoch}, time_zone => $location->{timezone});

    my $dfcDate_midnight = $dfcDate->clone->set(hour => 0, minute => 0, second => 0);
    my $dfcDate_LoxoneEpoch = toLoxEpoch($dfcDate_midnight->epoch);

    sendToLox($toMS, "dfc${per}_per", $per); # period starting with 0 for today, 1 for tomorrow, ...
    sendToLox($toMS, "dfc${per}_date", toLoxEpoch($dfcEntry->{time}{epoch}));
    sendToLox($toMS, "dfc${per}_day", sprintf("%02d", $dfcDate->day));
    sendToLox($toMS, "dfc${per}_month", sprintf("%02d", $dfcDate->month));
    sendToLox($toMS, "dfc${per}_monthn", $dfcDate->month_name);
    sendToLox($toMS, "dfc${per}_monthn_sh", $dfcDate->month_abbr);
    sendToLox($toMS, "dfc${per}_year", $dfcDate->year);
    sendToLox($toMS, "dfc${per}_hour", sprintf("%02d", $dfcDate->hour));
    sendToLox($toMS, "dfc${per}_min", sprintf("%02d", $dfcDate->minute));
    sendToLox($toMS, "dfc${per}_wday", $dfcDate->day_name);
    sendToLox($toMS, "dfc${per}_wday_sh", $dfcDate->day_abbr);
    sendToLox($toMS, "dfc${per}_tt_h", !$metric ? $dfcEntry->{temperature}{max}{air}*1.8+32 : $dfcEntry->{temperature}{max}{air});
    sendToLox($toMS, "dfc${per}_tt_l", !$metric ? $dfcEntry->{temperature}{min}{air}*1.8+32 : $dfcEntry->{temperature}{min}{air});
    sendToLox($toMS, "dfc${per}_pop", $dfcEntry->{precipitation}{probability});
    sendToLox($toMS, "dfc${per}_prec", !$metric ? $dfcEntry->{precipitation}{rainHigh}*0.0393700787 : $dfcEntry->{precipitation}{rainHigh});
    sendToLox($toMS, "dfc${per}_snow", !$metric ? $dfcEntry->{precipitation}{snowHigh}*0.393700787 : $dfcEntry->{precipitation}{snowHigh});
    sendToLox($toMS, "dfc${per}_w_sp_h", !$metric ? $dfcEntry->{wind}{max}{speed}*0.621371192 : $dfcEntry->{wind}{max}{speed});
    sendToLox($toMS, "dfc${per}_w_gu_h", !$metric ? $dfcEntry->{wind}{max}{gust}*0.621371192 : $dfcEntry->{wind}{max}{gust});
    sendToLox($toMS, "dfc${per}_w_dirdes_h", encode_utf8($dfcEntry->{wind}{max}{dirLabel}));
    sendToLox($toMS, "dfc${per}_w_dir_h", $dfcEntry->{wind}{max}{direction});
    sendToLox($toMS, "dfc${per}_w_sp_a", !$metric ? $dfcEntry->{wind}{avg}{speed}*0.621371192 : $dfcEntry->{wind}{avg}{speed});
    sendToLox($toMS, "dfc${per}_w_gu_a", !$metric ? $dfcEntry->{wind}{avg}{gust}*0.621371192 : $dfcEntry->{wind}{avg}{gust});
    sendToLox($toMS, "dfc${per}_w_dirdes_a", encode_utf8($dfcEntry->{wind}{avg}{dirLabel}));
    sendToLox($toMS, "dfc${per}_w_dir_a", $dfcEntry->{wind}{avg}{direction});
    sendToLox($toMS, "dfc${per}_hu_a", $dfcEntry->{humidity}{avg});
    sendToLox($toMS, "dfc${per}_hu_h", $dfcEntry->{humidity}{max});
    sendToLox($toMS, "dfc${per}_hu_l", $dfcEntry->{humidity}{min});
    sendToLox($toMS, "dfc${per}_we_code", $dfcEntry->{weatherCode}{loxone});
    sendToLox($toMS, "dfc${per}_we_des", encode_utf8($dfcEntry->{weatherCode}{description}));
    sendToLox($toMS, "dfc${per}_ozone", _jval($dfcEntry->{ozone}));
    sendToLox($toMS, "dfc${per}_moon_p", $dfcEntry->{moon}{percent});
    sendToLox($toMS, "dfc${per}_dp", !$metric ? $dfcEntry->{dewpoint}*1.8+32 : $dfcEntry->{dewpoint});
    sendToLox($toMS, "dfc${per}_pr", !$metric ? $dfcEntry->{pressure}*0.0295301 : $dfcEntry->{pressure});
    sendToLox($toMS, "dfc${per}_uvi", $dfcEntry->{uvIndex});
    sendToLox($toMS, "dfc${per}_vis", !$metric ? $dfcEntry->{visibility}*0.621371192 : $dfcEntry->{visibility});
    sendToLox($toMS, "dfc${per}_moon_a", $dfcEntry->{moon}{age});
    sendToLox($toMS, "dfc${per}_moon_ph", $dfcEntry->{moon}{phase});
    sendToLox($toMS, "dfc${per}_sun_r", $dfcDate_LoxoneEpoch + timeToSec($dfcEntry->{sunrise}));
    sendToLox($toMS, "dfc${per}_sun_s", $dfcDate_LoxoneEpoch + timeToSec($dfcEntry->{sunset}));

    # special handling for sunrise and sunset: send as loxone epoch time for easier processing in Loxone,
    # but need to be in hh:mm format on web page
    ${"dfc${per}_sun_r"} = $dfcEntry->{sunrise};
    ${"dfc${per}_sun_s"} = $dfcEntry->{sunset};

    my $iconName = $iconMapping->{icons}{$dfcEntry->{weatherCode}{weather4lox}}{"iconDay"};
    ${"dfc${per}_we_icon"} = $iconName . "." . $iconMapping->{format};
}

#
# Send hourly forecast to Loxone via HTML webpage, MQTT and UDP
#

LOGINF "-------------------------------------- Sending hourly weather forecast to Loxone ...";

foreach my $hfcEntry (@$hfc) {

    # Today is hfc0, tomorrow is hfc1, ...
    my $per = $hfcEntry->{hour};

    # Check if we should send this period to MS via MQTT and UDP
    $toMS = $hfcAllowed->{$per + 1};

    LOGDEB "Processing hourly forecast entry for period $per (hour$per) with date " . $hfcEntry->{time}{datetime} . ".";

    # Stop after 72 datasets (3 days * 24 hours) to avoid sending too many datasets to Loxone, which can cause performance issues
    if ( $per > 72 ) { last; }

    # Times are send in local time 
    my $hfc_date = DateTime->from_epoch(epoch => $hfcEntry->{time}{epoch}, time_zone => $location->{timezone});

    sendToLox($toMS, "hfc${per}_per", $per);
    sendToLox($toMS, "hfc${per}_date", toLoxEpoch($hfcEntry->{time}{epoch}));
    sendToLox($toMS, "hfc${per}_day", sprintf("%02d", $hfc_date->day));
    sendToLox($toMS, "hfc${per}_month", sprintf("%02d", $hfc_date->month));
    sendToLox($toMS, "hfc${per}_monthn", $hfc_date->month_name);
    sendToLox($toMS, "hfc${per}_monthn_sh", $hfc_date->month_abbr);
    sendToLox($toMS, "hfc${per}_year", $hfc_date->year);
    sendToLox($toMS, "hfc${per}_hour", sprintf("%02d", $hfc_date->hour));
    sendToLox($toMS, "hfc${per}_min", sprintf("%02d", $hfc_date->minute));
    sendToLox($toMS, "hfc${per}_wday", $hfc_date->day_name);
    sendToLox($toMS, "hfc${per}_wday_sh", $hfc_date->day_abbr);
    sendToLox($toMS, "hfc${per}_tt", !$metric ? $hfcEntry->{temperature}{air}*1.8+32 : $hfcEntry->{temperature}{air});
    sendToLox($toMS, "hfc${per}_tt_fl", !$metric ? $hfcEntry->{temperature}{feelsLike}*1.8+32 : $hfcEntry->{temperature}{feelsLike});
    sendToLox($toMS, "hfc${per}_pop", $hfcEntry->{precipitation}{probability});
    sendToLox($toMS, "hfc${per}_prec", !$metric ? $hfcEntry->{precipitation}{rainHigh}*0.0393700787 : $hfcEntry->{precipitation}{rainHigh});
    sendToLox($toMS, "hfc${per}_snow", !$metric ? $hfcEntry->{precipitation}{snowHigh}*0.393700787 : $hfcEntry->{precipitation}{snowHigh});
    sendToLox($toMS, "hfc${per}_w_sp", !$metric ? $hfcEntry->{wind}{speed}*0.621371192 : $hfcEntry->{wind}{speed});
    sendToLox($toMS, "hfc${per}_w_gu", !$metric ? $hfcEntry->{wind}{gust}*0.621371192 : $hfcEntry->{wind}{gust});
    sendToLox($toMS, "hfc${per}_w_ch", !$metric ? $hfcEntry->{temperature}{feelsLike}*1.8+32 : $hfcEntry->{temperature}{feelsLike});
    sendToLox($toMS, "hfc${per}_w_dirdes", encode_utf8($hfcEntry->{wind}{dirLabel}));
    sendToLox($toMS, "hfc${per}_w_dir", $hfcEntry->{wind}{direction});
    sendToLox($toMS, "hfc${per}_hu", $hfcEntry->{humidity});
    sendToLox($toMS, "hfc${per}_we_code", $hfcEntry->{weatherCode}{loxone});
    sendToLox($toMS, "hfc${per}_we_des", encode_utf8($hfcEntry->{weatherCode}{description}));
    sendToLox($toMS, "hfc${per}_ozone", _jval($hfcEntry->{ozone}));
    sendToLox($toMS, "hfc${per}_moon_p", $hfcEntry->{moon}{percent});
    sendToLox($toMS, "hfc${per}_dp", !$metric ? $hfcEntry->{dewpoint}*1.8+32 : $hfcEntry->{dewpoint});
    sendToLox($toMS, "hfc${per}_pr", !$metric ? $hfcEntry->{pressure}*0.0295301 : $hfcEntry->{pressure});
    sendToLox($toMS, "hfc${per}_uvi", $hfcEntry->{uvIndex});
    sendToLox($toMS, "hfc${per}_vis", !$metric ? $hfcEntry->{visibility}*0.621371192 : $hfcEntry->{visibility});
    sendToLox($toMS, "hfc${per}_moon_a", $hfcEntry->{moon}{age});
    sendToLox($toMS, "hfc${per}_moon_ph", $hfcEntry->{moon}{phase});
    sendToLox($toMS, "hfc${per}_sr", $hfcEntry->{solarRadiation});
    sendToLox($toMS, "hfc${per}_hi", !$metric ? $hfcEntry->{temperature}{heatIndex}*1.8+32 : $hfcEntry->{temperature}{heatIndex});
    sendToLox($toMS, "hfc${per}_sky", $hfcEntry->{cloudCover});
    sendToLox($toMS, "hfc${per}_sky_des", encode_utf8($hfcEntry->{weatherCode}{description}));

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
    ${"hfc${per}_we_icon"} = $iconName . "." . $iconMapping->{format};
}

#
# Calcualate aggregated values for each 4 hour period and send to Loxone via HTML webpage, MQTT and UDP
#

LOGINF "-------------------------------------- Sending aggregated 4-hourly weather forecast to Loxone (rain and temperature only) ...";

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

# Initialize variables for each period with default values (0 for precipitation and solar radiation
# for temperatures and precipitation probability: we use the first record as default value
for my $p (@periods) {
    $var{prec}{$p}   = 0;
    $var{snow}{$p}   = 0;
    $var{sr}{$p}     = 0;
    $var{ttmin}{$p}  = $hfc->[0]{temperature}{air};
    $var{ttmax}{$p}  = $hfc->[0]{temperature}{air};
    $var{ttmean}{$p} = [];
    $var{popmin}{$p} = $hfc->[0]{precipitation}{probability};
    $var{popmax}{$p} = $hfc->[0]{precipitation}{probability};
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

for my $p (@periods) {
    sendToLox($toMS, "calc+$p\_prec", !$metric ? sprintf("%.2f", $var{prec}{$p}*0.0393700787) : sprintf("%.2f", $var{prec}{$p}));
    sendToLox($toMS, "calc+$p\_snow", !$metric ? sprintf("%.2f", $var{snow}{$p}*0.393700787) : sprintf("%.2f", $var{snow}{$p}));
    sendToLox($toMS, "calc+$p\_sr", sprintf("%.0f", $var{sr}{$p}));
    sendToLox($toMS, "calc+$p\_ttmin", !$metric ? sprintf("%.1f", $var{ttmin}{$p}*1.8+32) : sprintf("%.1f", $var{ttmin}{$p}));
    sendToLox($toMS, "calc+$p\_ttmax", !$metric ? sprintf("%.1f", $var{ttmax}{$p}*1.8+32) : sprintf("%.1f", $var{ttmax}{$p}));
    sendToLox($toMS, "calc+$p\_ttmean", !$metric ? sprintf("%.1f", mean(@{ $var{ttmean}{$p} })*1.8+32) : sprintf("%.1f", mean(@{ $var{ttmean}{$p} })));
    sendToLox($toMS, "calc+$p\_popmin", sprintf("%.0f", $var{popmin}{$p}));
    sendToLox($toMS, "calc+$p\_popmax", sprintf("%.0f", $var{popmax}{$p}));
}

# send out all queued name / value pairs via UDP
if ($sendUDP) {
    LOGINF "Sending queued weather data to Loxone via UDP ...";
    sendUDP();
    LOGOK "Data sent to Loxone via UDP finished.";
}

# Close HTML database
open(F,">>$lbplogdir/weatherdata.html");
flock(F,2);
binmode F, ':encoding(UTF-8)';
print F "</body>\n</html>";
flock(F,8);
close(F);

#
# Create Webpages for themes and fill them with the current data. 
#

LOGINF "Creating Webpages ...";

our $theme = $stdtheme;
our $iconset = $stdiconset;
our $themeurlmain = "./webpage.html";
our $themeurldfc = "./webpage.dfc.html";
our $themeurlhfc = "./webpage.hfc.html";
our $themeurlmap = "./webpage.map.html";
our $webpath = "/plugins/$lbpplugindir";

my $themelang;
if (defined $pcfg->param("WEB.LANG")) {
    $themelang = $pcfg->param("WEB.LANG");
} else {
    $themelang = $lang;
}

# new style themes only use the main template for all views, the specific templates are only used for old style themes
my $newstyle = 0;
if (!-e "$lbptemplatedir/themes/$themelang/$theme.hfc.html" &&
    !-e "$lbptemplatedir/themes/$themelang/$theme.dfc.html") {
  $newstyle = 1;
}

if (!-e "$lbptemplatedir/themes/$themelang/$theme.main.html") {
    $themelang = "en";
    $theme = "dark";
}

#############################################
# MAP VIEW
#############################################

if (!$newstyle) {
    # Write cached webpage
    open(F1,">$lbplogdir/webpage.map.html");
    flock(F1,2);
    open(F,"<$lbptemplatedir/themes/$themelang/$theme.map.html");
    while (<F>) {
        $_ =~ s/<!--\$(.*?)-->/${$1}/g;
        print F1 $_;
    }
    close(F);
    flock(F1,8);
    close(F1);

    if (-e "$lbplogdir/webpage.map.html") {
        LOGDEB "$lbplogdir/webpage.map.html created.";
    }
}

#############################################
# Daily Forecast
#############################################

if (!$newstyle) {
    # Write cached webpage
    open(F1,">$lbplogdir/webpage.dfc.html");
    flock(F1,2);
    open(F,"<$lbptemplatedir/themes/$themelang/$theme.dfc.html");
    while (<F>) {
        $_ =~ s/<!--\$(.*?)-->/${$1}/g;
        print F1 $_;
    }
    close(F);
    flock(F1,8);
    close(F1);

    if (-e "$lbplogdir/webpage.dfc.html") {
        LOGDEB "$lbplogdir/webpage.dfc.html created.";
    }
}

#############################################
# Hourly Forecast
#############################################

if (!$newstyle) {
    # Write cached webpage
    # If Theme Lang is set, us it instead of system lang
    open(F1,">$lbplogdir/webpage.hfc.html");
    flock(F1,2);
    open(F,"<$lbptemplatedir/themes/$themelang/$theme.hfc.html");
    while (<F>) {
        $_ =~ s/<!--\$(.*?)-->/${$1}/g;
        print F1 $_;
    }
    close(F);
    flock(F1,8);
    close(F1);

    if (-e "$lbplogdir/webpage.hfc.html") {
        LOGDEB "$lbplogdir/webpage.hfc.html created.";
    }
}

#############################################
# CURRENT CONDITIONS
#############################################

# Write cached webpage
open(F1,">$lbplogdir/webpage.html");
flock(F1,2);
open(F,"<$lbptemplatedir/themes/$themelang/$theme.main.html");
while (<F>) {
    $_ =~ s/<!--\$(.*?)-->/${$1}/g;
    print F1 $_;
}
close(F);
flock(F1,8);
close(F1);

if (-e "$lbplogdir/webpage.html") {
    LOGDEB "$lbplogdir/webpage.html created.";
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

    # Original file has 169 entrys, but always starts at 0:00 today or 12:00 yesterday. We alsways start with current data
    # (we don't have historical data) and offer 168 hourly forcast datasets. This seems to be ok for the miniserver.

    # Derive timezone offset string for emulator header (e.g. "UTC+1.00")
    my $emuTzOffset = sprintf("UTC%+06.2f", $tzseconds / 3600);

    # Calculate precipitation in the last hour and snow fraction for current conditions
    my $rain_1hr_mm = $cur->{precipitation}{rain1hr} // 0;
    my $snow_1hr_cm = $cur->{precipitation}{snow1h} // 0;
    my $precip_1hr = $rain_1hr_mm + $snow_1hr_cm ;                                                    # 1cm snow counts as 1mm
    my $snow_fraction = $rain_1hr_mm > 0 ? $snow_1hr_cm / $precip_1hr : ($snow_1hr_cm > 0 ? 1 : 0);   # Snow fraction in precipitation in %
    my $precip_prob = $cur->{precipitation}{probability} // 0;

    open(F,">$lbplogdir/index.txt");
    flock(F,2);
    # Write header with meta data and location (semicolon separated, in the order expected by Loxone)
    print F "<mb_metadata>\n";
    print F "id;name;longitude;latitude;height (m.asl.);country;timezone;utc-timedifference;sunrise;sunset;\n";
    print F "local date;weekday;local time;temperature(C);feeledTemperature(C);windspeed(km/h);winddirection(degr);wind gust(km/h);low clouds(%);medium clouds(%);high clouds(%);precipitation(mm);probability of Precip(%);snowFraction;sea level pressure(hPa);relative humidity(%);CAPE;picto-code;radiation (W/m2);\n";
    print F "</mb_metadata>\n";
    print F "<valid_until>" . (($curDate->year)+5) . "-12-31</valid_until>\n";
    print F "<station>\n";
    print F ";" . ($location->{city} // "-") . ";" . ($location->{longitude} // "0") . ";" . ($location->{latitude} // "0");
    print F ";" . ($location->{elevation} // "0") . ";" . ($location->{country} // "-") . ";" . ($cur->{time}{tzShort} // "UTC") . ";" . ($emuTzOffset // "+0.00");
    print F ";" . ($cur->{sunrise} // "-") . ";" . ($cur->{sunset} // "-") . ";\n";
    # Data line for current conditions (semicolon separated, in the order expected by Loxone)
    print F $curDate->strftime('%d.%m.%Y') . ";\t";                     # Local date in format "dd.mm.yyyy"
    print F $curDate->day_abbr() . ";\t";                               # Weekday (abbreviated)
    printf F "%02d;\t",$curDate->hour();                                # Local time (hour)
    printf F "%1.2f;\t", $cur->{temperature}{air};                       # Temperature in Celsius
    printf F "%1.1f;\t", $cur->{temperature}{feelsLike};                 # Feels like temperature in Celsius
    printf F "%1d;\t", $cur->{wind}{speed};                              # Wind speed in km/h
    printf F "%1d;\t", $cur->{wind}{direction};                          # Wind direction in degrees
    printf F "%1d;\t", $cur->{wind}{gust};                               # Wind gust in km/h
    printf F "%1d;\t", 0;                                                # Low clouds in %
    printf F "%1d;\t", 0;                                                # Medium clouds in %
    printf F "%1d;\t", 0;                                                # High clouds in %
    printf F "%1.1f;\t", $precip_1hr;                                    # Precipitation in mm
    printf F "%1d;\t", $precip_prob;                                     # Probability of precipitation in % 
    printf F "%1.1f;\t", $snow_fraction * 100;                           # Snow fraction in precipitation in %   
    printf F "%1d;\t", $cur->{pressure};                                 # Sea level pressure in hPa
    printf F "%1d;\t", $cur->{humidity};                                 # Relative humidity in %
    printf F "%1d;\t", 0;                                                # CAPE, Convective Available Potential Energy in J/kg, indicator for thunderstorm potential and strength (not available in Weather4Lox, so set to 0)
    printf F "%1d;\t", $loxToEmu{int($cur->{weatherCode}{loxone})};  # Picto code (mapped from Loxone code to Weather Emulator code)
    printf F "%1.2f;\n", $cur->{solarRadiation};                        # Solar radiation in W/m2
    flock(F,8);
    close(F);

    #############################################
    # HOURLY FORECAST
    #############################################

    # Original file has 169 entrys, but always starts at 0:00 today or 12:00 yesterday. We alsways start with current data
    # 7 days * 24 hours = 168 datasets. It is unclear why the ms needs 7 days, because the emulator only displays 'today', 'tomorrow' and 'day after tomorrow'.

    $i = 0;

    open(F,">>$lbplogdir/index.txt");
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
        printf F "%1.2f;\t", $hfcEntry->{temperature}{air} // 0;                  # Temperature in Celsius
        printf F "%1.2f;\t", $hfcEntry->{temperature}{feelsLike} // 0;            # Feels like temperature in Celsius
        printf F "%1d;\t", $hfcEntry->{wind}{speed} // 0;                         # Wind speed in km/h
        printf F "%1d;\t", $hfcEntry->{wind}{direction} // 0;                     # Wind direction in degrees
        printf F "%1d;\t", $hfcEntry->{wind}{gust} // 0;                          # Wind gust in km/h
        printf F "%1d;\t", $hfcEntry->{clouds}{low} // 0;                         # Low clouds in %
        printf F "%1d;\t", $hfcEntry->{clouds}{medium} // 0;                      # Medium clouds in %
        printf F "%1d;\t", $hfcEntry->{clouds}{high} // 0;                        # High clouds in %
        printf F "%1.1f;\t", $precip_1hr // 0;                                     # Precipitation in mm
        printf F "%1d;\t", $precip_prob // 0;                                      # Probability of precipitation in %
        printf F "%1.1f;\t", $snow_fraction * 100 // 0;                            # Snow fraction in %
        printf F "%1d;\t", $hfcEntry->{pressure} // 0;                            # Sea level pressure in hPa
        printf F "%1d;\t", $hfcEntry->{humidity} // 0;                            # Relative humidity in %
        printf F "%1d;\t", 0;                                                      # CAPE, Convective Available Potential Energy in J/kg
        printf F "%1d;\t", $loxToEmu{int($hfcEntry->{weatherCode}{loxone})};   # Picto code 
        printf F "%1.2f;\n", $hfcEntry->{solarRadiation} // 0;                    # Solar radiation in W/m2 

        $i++;
    }
    print F "</station>\n";

    flock(F,8);
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
    my ($toMS, $name, $value) = @_;

    if (!defined($value)) {
      $value = 0;
    }
    # Create variable for searching and replacing in templates for themes (in case of old-style themes)
    { no strict 'refs'; ${$name} = $value }

    # Add weather data to HTML webpage
    LOGINF "Adding value to weatherdata.html      $name\@$value";

    open(F,">>$lbplogdir/weatherdata.html");
    flock(F,2);
        binmode F, ':encoding(UTF-8)';
        print F "$name\@" . Encode::decode("UTF-8", $value) . "<br>\n";
    flock(F,8);
    close(F);

    return if !$toMS; # only send to miniserver if $toMS is set to 1, otherwise only create variables for themes

    # Send weather data via MQTT to Loxone
    sendMQTT($name, $value);

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
#   name:      name of value (e.g. "current_temperature")
#   value:     value to send (e.g. "20.5")

sub sendMQTT {
  my ($name, $value) = @_;

  if ($sendMQTT) {
    eval {
      $name =~ s/\+/\_\_/g;
      LOGINF "Publishing value to MQTT: " . $topic . "/" . $name . " " . $value;
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
      LOGDEB "MQTT Login with Username and Password: Sending $mqtt_username $mqtt_password";
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
  $topic = "w4lx" if !$topic;; # Use standard if not defined
  LOGINF "Publishing " . $topic . "/plugin/lastupdate_epoche" . " " . time();
  $mqtt->retain($topic . "/plugin/lastupdate_epoche", time());

  return();

};

END
{
  LOGEND;
}
