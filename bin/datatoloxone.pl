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
my  $alloweddfc       = map { $_ => 1 } split /;/, $pcfg->param("SERVER.SENDDFC"); # Hash for quick lookup, e.g. $alloweddfc{1} is true if period 1 should be sent
my  $allowedhfc       = map { $_ => 1 } split /;/, $pcfg->param("SERVER.SENDHFC");
our $sendudp          = $pcfg->param("SERVER.SENDUDP");
our $metric           = $pcfg->param("SERVER.METRIC");
our $emu              = $pcfg->param("SERVER.EMU");
our $stdtheme         = $pcfg->param("WEB.THEME");
our $stdiconset       = $pcfg->param("WEB.ICONSET");
our $topic            = $pcfg->param("SERVER.TOPIC");
our $sendmqtt         = 0;
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
require_or_logdie('DateTime::Format::ISO8601');


##########################################################################
# Main program
##########################################################################

my $i;

# Clear HTML database
open(F,">$lbplogdir/weatherdata.html");
flock(F,2);
binmode F, ':encoding(UTF-8)';
print F "<!DOCTYPE HTML>\n<html>\n<head>\n";
print F "<meta http-equiv='Content-Type' content='text/html; charset=utf-8'>\n</head>\n<body>";
flock(F,8);
close(F);

# Current date
my $datenow = DateTime->now;

# Date Reference: Convert into Loxone Epoche (1.1.2009)
my $dateref = DateTime->new(
      year      => 2009,
      month     => 1,
      day       => 1,
);

# MQTT
&mqttconnect();

##########################################################################
# Load all JSON files at script startup (fail-fast)
##########################################################################

LOGINF "Loading JSON data files...";

# read JSON file with current conditions, daily and hourly forecasts
my $weather_key = "current";
my $envelope = read_json_file($lbplogdir, $weather_key);
my $cur = $envelope->{$weather_key} // {};
my $location = $envelope->{location} // {};

my $weather_key = "dailyforecast";
my $envelope = read_json_file($lbplogdir, $weather_key);
my $dfc = $envelope->{$weather_key} // [];

my $weather_key = "hourlyforecast";
my $envelope = read_json_file($lbplogdir, $weather_key);
my $hfc = $envelope->{$weather_key} // [];

LOGOK "JSON data files loaded successfully.";

#
# Send current conditions to Loxone via HTML webpage, MQTT and UDP
#

our $sendqueue = 0;
our $tmpudp;
our $udp;

# Get timezone offset in seconds from tz_offset, e.g. "+0100" => 3600, "-0230" => -9000
my $tzseconds = tzOffsetSeconds($cur->{time}{tz_offset} // "");

# Times are send in local time 
my $cur_date = DateTime->from_epoch(epoch => $cur->{time}{epoch}, time_zone => $location->{timezone});
my $cur_date_midnight = $cur_date->clone->set(hour => 0, minute => 0, second => 0);
my $cur_date_LoxoneEpoch = toLoxoneEpoch($cur_date_midnight->epoch);

# TODO: To be verified if + $tzseconds is correct 
sendToLox("cur_date", toLoxoneEpoch($cur->{time}{epoch}));                                         # Loxone epoch (1.1.2009, MEZ), e.g. 542934004
sendToLox("cur_date_des", $cur->{time}{datetime});                                                 # was RFC822, now ISO 8601, e.g. Mon, 16 Mar 2026 23:00:04 +0100
sendToLox("cur_date_tz_des_sh", $cur->{time}{timezone});                                           # IANA timezone name, e.g. Europe/Berlin
sendToLox("cur_date_tz_des", $cur->{time}{tz_short});                                              # Time Zone Abbreviation, e.g. CET
sendToLox("cur_date_tz", $cur->{time}{tz_offset});                                                 # Numeric timezone offset, e.g. +0100
sendToLox("cur_day", $cur_date->day);
sendToLox("cur_month", $cur_date->month);
sendToLox("cur_year", $cur_date->year);
sendToLox("cur_hour", $cur_date->hour);
sendToLox("cur_min", $cur_date->minute);
sendToLox("cur_loc_n", $location->{city});
sendToLox("cur_loc_c", $location->{country});
sendToLox("cur_loc_ccode", $location->{country_code});
sendToLox("cur_loc_lat", $location->{latitude});
sendToLox("cur_loc_long", $location->{longitude});
sendToLox("cur_loc_el", $location->{elevation});
sendToLox("cur_tt", !$metric ? $cur->{temperature}{air}*1.8+32 : $cur->{temperature}{air});
sendToLox("cur_tt_fl", !$metric ? $cur->{temperature}{feelslike}*1.8+32 : $cur->{temperature}{feelslike});
sendToLox("cur_hu", $cur->{humidity});
sendToLox("cur_w_dirdes", $cur->{wind}{dir_label});
sendToLox("cur_w_dir", $cur->{wind}{direction});
sendToLox("cur_w_sp", !$metric ? $cur->{wind}{speed}*0.621371192 : $cur->{wind}{speed});
sendToLox("cur_w_gu", !$metric ? $cur->{wind}{gust}*0.621371192 : $cur->{wind}{gust});
sendToLox("cur_w_ch", !$metric ? $cur->{temperature}{feelslike}*1.8+32 : $cur->{temperature}{feelslike}); # same as cur_tt_fl - wind chill (feel)
sendToLox("cur_pr", !$metric ? $cur->{pressure}*0.0295301 : $cur->{pressure});
sendToLox("cur_dp", !$metric ? $cur->{dewpoint}*1.8+32 : $cur->{dewpoint});
sendToLox("cur_vis", !$metric ? $cur->{visibility}*0.621371192 : $cur->{visibility});
sendToLox("cur_sr", $cur->{solar_radiation});
sendToLox("cur_hi", !$metric ? $cur->{heat_index}*1.8+32 : $cur->{heat_index});
sendToLox("cur_uvi", $cur->{uv_index});
sendToLox("cur_pop", $cur->{precipitation}{probability});
# TODO: Verify names
sendToLox("cur_prec_today", !$metric ? $cur->{precipitation}{rain_today_mm}*0.0393700787 : $cur->{precipitation}{rain_today_mm});
sendToLox("cur_prec_1hr", !$metric ? $cur->{precipitation}{rain_1hr_mm}*0.0393700787 : $cur->{precipitation}{rain_1hr_mm});
sendToLox("cur_snow", !$metric ? $cur->{precipitation}{snow_today_cm}*0.393700787 : $cur->{precipitation}{snow_today_cm});
sendToLox("cur_we_icon", $cur->{weather_codes}{weather4lox});
sendToLox("cur_we_code", $cur->{weather_codes}{loxone});
sendToLox("cur_we_des", encode_utf8($cur->{weather_codes}{description}));
sendToLox("cur_moon_p", $cur->{moon}{percent});
sendToLox("cur_moon_a", $cur->{moon}{age});
sendToLox("cur_moon_ph", $cur->{moon}{phase});
sendToLox("cur_moon_h", $cur->{moon}{hemisphere});
sendToLox("cur_sun_r", $cur_date_LoxoneEpoch + timeToSec($cur->{sunrise}));
sendToLox("cur_sun_s", $cur_date_LoxoneEpoch + timeToSec($cur->{sunset}));
sendToLox("cur_ozone", $cur->{ozone});
sendToLox("cur_sky", $cur->{cloud_cover});

# Use night icons between sunset and sunrise
my $cur_sec = timeToSec('$cur_date->hour:$cur_date->minute');
my $sunrise_sec = timeToSec($cur->{sunrise}) // 6;
my $sunset_sec = timeToSec($cur->{sunset}) // 18;

# used for day / night weather icons on webpage 
if ($cur_sec < $sunrise_sec || $cur_sec > $sunset_sec) {
    our  $cur_dayornight = "night";
} else {
    our  $cur_dayornight = "day";
}

#
# Send daily forecast to Loxone via HTML webpage, MQTT and UDP
#

foreach my $dfc_entry (@$dfc) {

    # Today is dfc0, tomorrow is dfc1, ...
    my $per = $dfc_entry->{period} - 1;

    # Send values only if we should do so
    if (!$alloweddfc{$per}) {
        next;
    }
    # Times are send in local time 
    my $dfc_date = DateTime->from_epoch(epoch => $dfc_entry->{time}{epoch}, time_zone => $location->{timezone});

    my $dfc_date_midnight = $dfc_date->clone->set(hour => 0, minute => 0, second => 0);
    my $dfc_date_LoxoneEpoch = toLoxoneEpoch($dfc_date_midnight->epoch);

    sendToLox("dfc$per\_per", $per);
    sendToLox("dfc$per\_date", toLoxoneEpoch($dfc_entry->{time}{epoch}));
    sendToLox("dfc$per\_day", $dfc_date->day);
    sendToLox("dfc$per\_month", $dfc_date->month);
    sendToLox("dfc$per\_monthn", $dfc_date->month_name);
    sendToLox("dfc$per\_monthn_sh", $dfc_date->month_abbr);
    sendToLox("dfc$per\_year", $dfc_date->year);
    sendToLox("dfc$per\_hour", $dfc_date->hour);
    sendToLox("dfc$per\_min", $dfc_date->minute);
    sendToLox("dfc$per\_wday", $dfc_date->day_name);
    sendToLox("dfc$per\_wday_sh", $dfc_date->day_abbr);
    sendToLox("dfc$per\_tt_h", !$metric ? $dfc_entry->{temperature}{air_max}*1.8+32 : $dfc_entry->{temperature}{air_max});
    sendToLox("dfc$per\_tt_l", !$metric ? $dfc_entry->{temperature}{air_min}*1.8+32 : $dfc_entry->{temperature}{air_min});
    sendToLox("dfc$per\_pop", $dfc_entry->{precipitation}{probability});
    sendToLox("dfc$per\_prec", !$metric ? $dfc_entry->{precipitation}{rain_mm_high}*0.0393700787 : $dfc_entry->{precipitation}{rain_mm_high});
    sendToLox("dfc$per\_snow", !$metric ? $dfc_entry->{precipitation}{snow_cm_high}*0.393700787 : $dfc_entry->{precipitation}{snow_cm_high});
    sendToLox("dfc$per\_w_sp_h", !$metric ? $dfc_entry->{wind}{max}{speed}*0.621371192 : $dfc_entry->{wind}{max}{speed});
    sendToLox("dfc$per\_w_gu_h", !$metric ? $dfc_entry->{wind}{max}{gust}*0.621371192 : $dfc_entry->{wind}{max}{gust});
    sendToLox("dfc$per\_w_dirdes_h", $dfc_entry->{wind}{max}{dir_label});
    sendToLox("dfc$per\_w_dir_h", $dfc_entry->{wind}{max}{direction});
    sendToLox("dfc$per\_w_sp_a", !$metric ? $dfc_entry->{wind}{avg}{speed}*0.621371192 : $dfc_entry->{wind}{avg}{speed});
    sendToLox("dfc$per\_w_gu_a", !$metric ? $dfc_entry->{wind}{avg}{gust}*0.621371192 : $dfc_entry->{wind}{avg}{gust});
    sendToLox("dfc$per\_w_dirdes_a", $dfc_entry->{wind}{avg}{dir_label});
    sendToLox("dfc$per\_w_dir_a", $dfc_entry->{wind}{avg}{direction});
    sendToLox("dfc$per\_hu_a", $dfc_entry->{humidity}{avg});
    sendToLox("dfc$per\_hu_h", $dfc_entry->{humidity}{max});
    sendToLox("dfc$per\_hu_l", $dfc_entry->{humidity}{min});
    sendToLox("dfc$per\_we_icon", $dfc_entry->{weather_codes}{weather4lox});
    sendToLox("dfc$per\_we_code", $dfc_entry->{weather_codes}{loxone});
    sendToLox("dfc$per\_we_des", encode_utf8($dfc_entry->{weather_codes}{description}));
    sendToLox("dfc$per\_ozone", _jval($dfc_entry->{ozone}));
    sendToLox("dfc$per\_moon_p", $dfc_entry->{moon}{percent});
    sendToLox("dfc$per\_dp", !$metric ? $dfc_entry->{dewpoint}*1.8+32 : $dfc_entry->{dewpoint});
    sendToLox("dfc$per\_pr", !$metric ? $dfc_entry->{pressure}*0.0295301 : $dfc_entry->{pressure});
    sendToLox("dfc$per\_uvi", $dfc_entry->{uv_index});
    sendToLox("dfc$per\_vis", !$metric ? $dfc_entry->{visibility}*0.621371192 : $dfc_entry->{visibility});
    sendToLox("dfc$per\_moon_a", $dfc_entry->{moon}{age});
    sendToLox("dfc$per\_moon_ph", $dfc_entry->{moon}{phase});
    sendToLox("dfc$per\_sun_r", $dfc_date_LoxoneEpoch + timeToSec($dfc_entry->{sunrise}));
    sendToLox("dfc$per\_sun_s", $dfc_date_LoxoneEpoch + timeToSec($dfc_entry->{sunset}));
}

#
# Send hourly forecast to Loxone via HTML webpage, MQTT and UDP
#

foreach my $hfc_entry (@$hfc) {

    # Today is dfc0, tomorrow is dfc1, ...
    my $per = $hfc_entry->{period} - 1;

    # Send values only if we should do so
    if (!$alloweddfc{$per}) {
        next;
    }
    # Times are send in local time 
    my $hfc_date = DateTime->from_epoch(epoch => $hfc_entry->{time}{epoch}, time_zone => $location->{timezone});

    sendToLox("hfc$per\_per", $per);
    sendToLox("hfc$per\_date", toLoxoneEpoch($hfc_entry->{time}{epoch}));
    sendToLox("hfc$per\_day", $hfc_date->day);
    sendToLox("hfc$per\_month", $hfc_date->month);
    sendToLox("hfc$per\_monthn", $hfc_date->month_name);
    sendToLox("hfc$per\_monthn_sh", $hfc_date->month_abbr);
    sendToLox("hfc$per\_year", $hfc_date->year);
    sendToLox("hfc$per\_hour", $hfc_date->hour);
    sendToLox("hfc$per\_min", $hfc_date->minute);
    sendToLox("hfc$per\_wday", $hfc_date->day_name);
    sendToLox("hfc$per\_wday_sh", $hfc_date->day_abbr);
    sendToLox("hfc$per\_tt", !$metric ? $hfc_entry->{temperature}{air}*1.8+32 : $hfc_entry->{temperature}{air});
    sendToLox("hfc$per\_tt_fl", !$metric ? $hfc_entry->{temperature}{feelslike}*1.8+32 : $hfc_entry->{temperature}{feelslike});
    sendToLox("hfc$per\_pop", $hfc_entry->{precipitation}{probability});
    sendToLox("hfc$per\_prec", !$metric ? $hfc_entry->{precipitation}{rain_mm_high}*0.0393700787 : $hfc_entry->{precipitation}{rain_mm_high});
    sendToLox("hfc$per\_snow", !$metric ? $hfc_entry->{precipitation}{snow_cm_high}*0.393700787 : $hfc_entry->{precipitation}{snow_cm_high});
    sendToLox("hfc$per\_w_sp", !$metric ? $hfc_entry->{wind}{speed}*0.621371192 : $hfc_entry->{wind}{speed});
    sendToLox("hfc$per\_w_gu", !$metric ? $hfc_entry->{wind}{gust}*0.621371192 : $hfc_entry->{wind}{gust});
    sendToLox("hfc$per\_w_ch", !$metric ? $hfc_entry->{temperature}{feelslike}*1.8+32 : $hfc_entry->{temperature}{feelslike});
    sendToLox("hfc$per\_w_dirdes", $hfc_entry->{wind}{dir_label});
    sendToLox("hfc$per\_w_dir", $hfc_entry->{wind}{direction});
    sendToLox("hfc$per\_hu", $hfc_entry->{humidity});
    sendToLox("hfc$per\_we_icon", $hfc_entry->{weather_codes}{weather4lox});
    sendToLox("hfc$per\_we_code", $hfc_entry->{weather_codes}{loxone});
    sendToLox("hfc$per\_we_des", encode_utf8($hfc_entry->{weather_codes}{description}));
    sendToLox("hfc$per\_ozone", _jval($hfc_entry->{ozone}));
    sendToLox("hfc$per\_moon_p", $hfc_entry->{moon}{percent});
    sendToLox("hfc$per\_dp", !$metric ? $hfc_entry->{dewpoint}*1.8+32 : $hfc_entry->{dewpoint});
    sendToLox("hfc$per\_pr", !$metric ? $hfc_entry->{pressure}*0.0295301 : $hfc_entry->{pressure});
    sendToLox("hfc$per\_uvi", $hfc_entry->{uv_index});
    sendToLox("hfc$per\_vis", !$metric ? $hfc_entry->{visibility}*0.621371192 : $hfc_entry->{visibility});
    sendToLox("hfc$per\_moon_a", $hfc_entry->{moon}{age});
    sendToLox("hfc$per\_moon_ph", $hfc_entry->{moon}{phase});
    sendToLox("hfc$per\_sr", $hfc_entry->{solar_radiation});
    sendToLox("hfc$per\_hi", !$metric ? $hfc_entry->{heat_index}*1.8+32 : $hfc_entry->{heat_index});
    sendToLox("hfc$per\_sky", $hfc_entry->{cloud_cover});
    sendToLox("hfc$per\_sky\_des", encode_utf8($hfc_entry->{weather_codes}{description}));

    # Use night icons between sunset and sunrise on webpage
    if ($hfc_entry->{is_nighttime}) {
        ${hfc.$per._dayornight} = "night";
    } else {
        ${hfc.$per._dayornight} = "day";
    }
}

#
# Calcualate aggregated values for each 4 hour period and send to Loxone via HTML webpage, MQTT and UDP
#

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

foreach my $hfc_entry (@$hfc) {

    # Set defaults for the first period object

    for my $p (@periods) {
        next unless $hfc_entry->{period} <= $p;

        $var{prec}{$p}  += $hfc_entry->{precipitation}{rain_mm_high} if defined $hfc_entry->{precipitation}{rain_mm_high} && $hfc_entry->{precipitation}{rain_mm_high} > 0;
        $var{snow}{$p}  += $hfc_entry->{precipitation}{snow_cm_high} if defined $hfc_entry->{precipitation}{snow_cm_high} && $hfc_entry->{precipitation}{snow_cm_high} > 0;
        
        $var{sr}{$p}    += $hfc_entry->{solar_radiation}  if defined $hfc_entry->{solar_radiation}  && $hfc_entry->{solar_radiation} > 0;

        # For temperature, we take the minimum and maximum value of the included hourly forecasts
        if (defined $hfc_entry->{temperature}{air}) {
            $var{ttmin}{$p} = $hfc_entry->{temperature}{air} if $var{ttmin}{$p} > $hfc_entry->{temperature}{air};
            $var{ttmax}{$p} = $hfc_entry->{temperature}{air} if $var{ttmax}{$p} < $hfc_entry->{temperature}{air};
            push @{ $var{ttmean}{$p} }, $hfc_entry->{temperature}{air};
        }
        # For precipitation probability, we take the minimum and maximum value of the included hourly forecasts
        if (defined $hfc_entry->{precipitation}{probability}) {
            $var{popmin}{$p} = $hfc_entry->{precipitation}{probability} if $var{popmin}{$p} > $hfc_entry->{precipitation}{probability};
            $var{popmax}{$p} = $hfc_entry->{precipitation}{probability} if $var{popmax}{$p} < $hfc_entry->{precipitation}{probability};
        }
    }
}

for my $p (@periods) {
    sendToLox("calc+$p\_prec", !$metric ? sprintf("%.2f", $var{prec}{$p}*0.0393700787) : sprintf("%.2f", $var{prec}{$p}));
    sendToLox("calc+$p\_snow", !$metric ? sprintf("%.2f", $var{snow}{$p}*0.393700787) : sprintf("%.2f", $var{snow}{$p}));
    sendToLox("calc+$p\_sr", sprintf("%.0f", $var{sr}{$p}));
    sendToLox("calc+$p\_ttmin", !$metric ? sprintf("%.1f", $var{ttmin}{$p}*1.8+32) : sprintf("%.1f", $var{ttmin}{$p}));
    sendToLox("calc+$p\_ttmax", !$metric ? sprintf("%.1f", $var{ttmax}{$p}*1.8+32) : sprintf("%.1f", $var{ttmax}{$p}));
    sendToLox("calc+$p\_ttmean", !$metric ? sprintf("%.1f", mean(@{ $var{ttmean}{$p} })*1.8+32) : sprintf("%.1f", mean(@{ $var{ttmean}{$p} })));
    sendToLox("calc+$p\_popmin", sprintf("%.0f", $var{popmin}{$p}));
    sendToLox("calc+$p\_popmax", sprintf("%.0f", $var{popmax}{$p}));
}

# send out all queued name / value pairs via UDP
sendudp();

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

LOGINF "Creating Webpages...";

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
# Create Cloud Weather Emu
#

# Mapping of the documented Loxone Picto-Codes from https://www.loxone.com/dede/kb/weather-service/
# to the codes used in the Weather Emulator
my %lox_to_emu = (
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
    my $emu_tz_str = sprintf("UTC%+06.2f", $tzseconds / 3600);

    # Calculate precipitation in the last hour and snow fraction for current conditions
    my $rain_1hr_mm = $cur->{precipitation}{rain_1hr_mm} // 0;
    my $snow_1hr_cm = $cur->{precipitation}{snow_1hr_cm} // 0;
    my $precip_1hr = $rain_1hr_mm + $snow_1hr_cm ;                                                    # 1cm snow counts as 1mm
    my $snow_fraction = $rain_1hr_mm > 0 ? $snow_1hr_cm / $precip_1hr : ($snow_1hr_cm > 0 ? 1 : 0);   # Snow fraction in precipitation in %
    my $precip_prob = $cur->{precipitation}{probability} // 0;

    open(F,">$lbplogdir/index.txt");
    flock(F,2);
    print F "<mb_metadata>\n";
    print F "id;name;longitude;latitude;height (m.asl.);country;timezone;utc-timedifference;sunrise;sunset;\n";
    print F "local date;weekday;local time;temperature(C);feeledTemperature(C);windspeed(km/h);winddirection(degr);wind gust(km/h);low clouds(%);medium clouds(%);high clouds(%);precipitation(mm);probability of Precip(%);snowFraction;sea level pressure(hPa);relative humidity(%);CAPE;picto-code;radiation (W/m2);\n";
    print F "</mb_metadata>\n";
    print F "<valid_until>" . (($datenow->year)+5) . "-12-31</valid_until>\n";
    print F "<station>\n";
    print F ";" . $location->{city} . ";" . $location->{longitude} . ";" . $location->{latitude} . ";" . $location->{elevation} . ";" . $location->{country} . ";" . $cur->{time}{tz_short} . ";" . $emu_tz_str;
    print F ";" . (defined($cur->{sunrise}) ? $cur->{sunrise} : "") . ";" . (defined($cur->{sunset}) ? $cur->{sunset} : "") . ";\n";
    print F $cur_date->strftime('%d.%m.%Y') . ";\t";           # Local date in format "dd.mm.yyyy"
    print F $cur_date->day_abbr() . ";\t";                     # Weekday (abbreviated)
    printf F "%02d",$cur_date->hour() ;                        # Local time (hour)
    print F ";\t";
    printf ( F "%1.2f", $cur->{temperature}{air});             # Temperature in Celsius
    print F ";\t";
    printf ( F "%1.1f", $cur->{temperature}{feels_like});      # Feels like temperature in Celsius
    print F ";\t";
    printf ( F "%1d", $cur->{wind}{speed});                    # Wind speed in km/h
    print F ";\t";
    printf ( F "%1d", $cur->{wind}{direction});                # Wind direction in degrees
    print F ";\t";
    printf ( F "%1d", $cur->{wind}{gust});                     # Wind gust in km/h
    print F ";\t";
    printf ( F "%1d", 0);                                      # Low clouds in %
    print F ";\t";
    printf ( F "%1d", 0);                                      # Medium clouds in %
    print F ";\t";
    printf ( F "%1d", 0);                                      # High clouds in %
    print F ";\t";
    printf ( F "%1.1f", $precip_1hr);                          # Precipitation in mm
    print F ";\t";
    printf ( F "%1d", $precip_prob);                           # Probability of precipitation in % 
    print F ";\t";
    printf ( F "%1.1f", $snow_fraction * 100);                 # Snow fraction in precipitation in %   
    print F ";\t";
    printf ( F "%1d", $cur->{pressure});                       # Sea level pressure in hPa
    print F ";\t";
    printf ( F "%1d", $cur->{humidity});                       # Relative humidity in %
    print F ";\t";
    printf ( F "%1d", 0);                                      # CAPE, Convective Available Potential Energy in J/kg, indicator for thunderstorm potential and strength (not available in Weather4Lox, so set to 0)
    print F ";\t";
    printf ( F "%1d", $lox_to_emu{int($cur->{weather_codes}{loxone})});  # Picto code (mapped from Loxone code to Weather Emulator code)
    print F ";\t";
    printf ( F "%1.2f", $cur->{solar_radiation});              # Solar radiation in W/m2
    print F ";\n";
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

    foreach my $hfc_entry (@$hfc) {

        # skip datasets in the past
        if ( $hfc_entry->{time}{epoch} < $cur->{time}{epoch} ) { next; } 

        # Stop after 168 datasets (7 days * 24 hours), because the original file has 169 datasets
        if ( $i >= 168 ) { last; }

        # Construct hfc date from epoch (per Research Pattern 7)
        my $hfc_date = DateTime->from_epoch(epoch => $hfc_entry->{time}{epoch}, time_zone => $location->{timezone});

        # Calculate precipitation in the last hour and snow fraction for current conditions
        my $rain_mm = $hfc_entry->{precipitation}{rain_mm_high} // 0;
        my $snow_cm = $hfc_entry->{precipitation}{snow_cm_high} // 0;
        my $precip_1hr = $rain_mm + $snow_cm ;                                                # 1cm snow counts as 1mm
        my $snow_fraction = $rain_mm > 0 ? $snow_cm / $precip_1hr : ($snow_cm > 0 ? 1 : 0);   # Snow fraction in precipitation in %
        my $precip_prob = $hfc_entry->{precipitation}{probability} // 0;

        # "local date;weekday;local time;temperature(C);feeledTemperature(C);windspeed(km/h);winddirection(degr);wind gust(km/h);low clouds(%);medium clouds(%);high clouds(%);precipitation(mm);probability of Precip(%);snowFraction;sea level pressure(hPa);relative humidity(%);CAPE;picto-code;radiation (W/m2);\n";
        print F $hfc_date->strftime('%d.%m.%Y') . ";\t";
        print F $hfc_date->day_abbr() . ";\t";
        printf ( F "%02d;\t",$hfc_date->hour() );
        printf ( F "%1.2f;\t", $hfc_entry->{temperature}{air});
        printf ( F "%1.2f;\t", $hfc_entry->{temperature}{feels_like});
        printf ( F "%1d;\t", $hfc_entry->{wind}{speed} // 0);
        printf ( F "%1d;\t", $hfc_entry->{wind}{direction} // 0);
        printf ( F "%1d;\t", $hfc_entry->{wind}{gust} // 0);
        printf ( F "%1d;\t", $hfc_entry->{clouds}{low} // 0);
        printf ( F "%1d;\t", $hfc_entry->{clouds}{medium} // 0);
        printf ( F "%1d;\t", $hfc_entry->{clouds}{high} // 0);
        printf ( F "%1.1f;\t", $precip_1hr // 0);
        printf ( F "%1d;\t", $precip_prob // 0);
        printf ( F "%1.1f;\t", $snow_fraction * 100 // 0);
        printf ( F "%1d;\t", $hfc_entry->{pressure} // 0);
        printf ( F "%1d;\t", $hfc_entry->{humidity} // 0);
        printf ( F "%1d;\t", 0);
        printf ( F "%1d;\t", $lox_to_emu{int($hfc_entry->{weather_codes}{loxone})});
        printf ( F "%1.2f;\n", $hfc_entry->{solar_radiation} // 0);

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
#   name:      name of value (e.g. "current_temperature")
#   value:     value to send (e.g. "20.5")

sub sendToLox {
    my ($name, $value) = @_;

    if (!defined($value)) {
      $value = 0;
    }
    # Create HTML webpage
    LOGINF "Adding value to weatherdata.html.     $name\@$value";

    open(F,">>$lbplogdir/weatherdata.html");
    flock(F,2);
        binmode F, ':encoding(UTF-8)';
        print F "$name\@" . Encode::decode("UTF-8", $value) . "<br>\n";
    flock(F,8);
    close(F);

    # Create variable for searching and replacing in templates for themes (in case of old-style themes)
    { no strict 'refs'; ${$name} = $value }

    # Send MQTT data
    sendmqtt($name, $value);

    # Send UDP data
    if ($sendudp) {
        $tmpudp .= "$name\@$value; ";
        LOGINF "Adding value to UDP send queue.       $name\@$value";
    }

    return();
}

##########################################################################
# Send queued udp data to Loxone via UDP
# Parameter:
#   none - $tmpudp was filled by send() function and is defined globally

sub sendudp {

    my $msno = defined $pcfg->param("SERVER.MSNO") ? $pcfg->param("SERVER.MSNO") : 1;
    my %miniservers = LoxBerry::System::get_miniservers();
    if ($miniservers{$msno}{IPAddress} ne "" && $udpport ne "") {
        LOGINF "$sendqueue: Send Data to " . $miniservers{$msno}{Name};
        # Send value
        my $sock = IO::Socket::INET->new(
            Proto    => 'udp',
            PeerPort => $udpport,
            PeerAddr => $miniservers{$msno}{IPAddress},
        );
        $sock->send($tmpudp);
        LOGOK "$sendqueue: Sent OK to " . $miniservers{$msno}{Name} . ". IP:" . $miniservers{$msno}{IPAddress} . " Port:$udpport";
        $sendqueue++;
        Time::HiRes::usleep (10000); # 10 Milliseconds
    }
    $tmpudp = "";
    return();
}


# Null-safe value helper: return -9999 for undef (JSON null) where Loxone expects it
sub _jval {
    my ($v) = @_;
    return defined($v) ? $v : -9999;
}

##########################################################################
# Send data to Loxone (HTML, MQTT, UDP)
# Parameter:
#   name:      name of value (e.g. "current_temperature")
#   value:     value to send (e.g. "20.5")

sub sendmqtt {
  my ($name, $value) = @_;

  if ($sendmqtt) {
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
    $sendmqtt = 1;
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
    $sendmqtt = 0;
    return();
  };

  # Update Plugin Status
  $topic = "weather4lox" if !$topic;; # Use standard if not defined
  LOGINF "Publishing " . $topic . "/plugin/lastupdate_epoche" . " " . time();
  $mqtt->retain($topic . "/plugin/lastupdate_epoche", time());

  return();

};

##########################################################################
# Converts time to seconds since midnight
# Parameter:
#   time:      time to convert (e.g. "01:30" or "01:30:45")

sub timeToSec() {
    my ($time) = @_;

    my ($hour, $minute, $second) = split /:/, $time;
    $second //= 0;  # Setze $second auf 0, falls nicht vorhanden
    my $seconds = $hour * 3600 + $minute * 60 + $second;
    return $seconds;
}


##########################################################################
# Converts time to Loxone epoch time (seconds since 01.01.1970)
# Parameter:
#   time:      time to convert - datetime object or unix epoch timestamp

sub toLoxoneEpoch() {
    my ($dt_input) = @_;

    my $date;
    # Check, if $dt_input is a DateTime object
    if (ref($dt_input) eq 'DateTime') {
        $date = $dt_input;
    }
    # Check, if $dt_input is numeric (Epoch)
    elsif ($dt_input =~ /^\d+$/) {
        $date = DateTime->from_epoch(epoch => $dt_input);
    }
    # Otherwise: Try to parse ISO8601 string
    else {
        $date = DateTime::Format::ISO8601->parse_datetime($dt_input);
    }

    # see https://www.loxforum.com/forum/german/software-konfiguration-programm-und-visualisierung/451911-arbeitsweise-der-neueren-zähler?p=452490#post452490
    # for discussion about Loxone epoch "zero point"
    # Base: January 1, 2009, 00:00:00 UTC
    # my $loxone_ref = DateTime->new(
    #     year   => 2009,
    #     month  => 1,
    #     day    => 1,
    #     hour   => 0,
    #     minute => 0,
    #     second => 0,
    #     time_zone => 'MEZ'     # time reference is Kollerschlag time (MEZ/UTC+1) according findings, not UTC!
    # );
    # my $loxone_epoch = $date->epoch - $loxone_ref->epoch;

    my $loxone_ref = 1230764400;                        # time reference is Kollerschlag time (MEZ/UTC+1) according findings, not UTC!
    my $loxone_epoch = $date->epoch - $loxone_ref;

    return $loxone_epoch;
}


##########################################################################
# Get timezone offset in seconds from tz_offset, e.g. "+01:00" => 3600,
# "-02:30" => -9000, "2026-03-16T20:00:04+02:00" => 7200
sub tzOffsetSeconds() {
    my ($dt_input) = @_;

    my $tzseconds = 0;
    if (defined($dt_input) && $dt_input =~ /([+-])(\d{2}):(\d{2})$/) {
        my $sign = ($1 eq '+') ? 1 : -1;
        $tzseconds = $sign * ($2 * 3600 + $3 * 60);
    }
    return $tzseconds;
}


##########################################################################
# Calculate average / mean of a list of numbers

sub mean
{
  #print Dumper @_;
  my (@data) = @_;

  my $sum;
  foreach (@data) {
    $sum += $_;
  }
  if (@data == 0) {
    return undef; # Avoid division by zero
  }
  return ( $sum / @data );
}

END
{
  LOGEND;
}
