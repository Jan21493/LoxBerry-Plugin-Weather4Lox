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


##########################################################################
# Modules
##########################################################################
use DateTime;
use DateTime::Format::ISO8601;
use Config::Simple;
use File::HomeDir;
use Cwd 'abs_path';
use CGI::Carp qw(fatalsToBrowser);
use CGI qw/:standard/;
#use strict;
#use warnings;
use JSON::PP ();
use utf8;
use Encode qw(encode_utf8);
use Scalar::Util qw(looks_like_number);
use File::Copy;


##########################################################################
# Settings
##########################################################################

# Version of this script
my $version = "4.7.0.2";

# Figure out in which subfolder we are installed
our $psubfolder = abs_path($0);
our $psubfolder =~ s/(.*)\/(.*)\/(.*)$/$2/g;
our $home = File::HomeDir->my_home;
our $webpath = "/plugins/$psubfolder";

our $cfg             = new Config::Simple("$home/config/system/general.cfg");
our $installfolder   = $cfg->param("BASE.INSTALLFOLDER");
our $lang            = $cfg->param("BASE.LANG");

our $pcfg            = new Config::Simple("$installfolder/config/plugins/$psubfolder/weather4lox.cfg");
our $stdtheme        = $pcfg->param("WEB.THEME");
our $stdiconset      = $pcfg->param("WEB.ICONSET");
our $metric          = $pcfg->param("SERVER.METRIC");

# If Theme Lang is set, us it instead of system lang
if (defined $pcfg->param("WEB.LANG")) {
	$lang = $pcfg->param("WEB.LANG");
}

# Check for parameters we got from URL
foreach (split(/&/,$ENV{'QUERY_STRING'})){
  ($namef,$value) = split(/=/,$_,2);
  $namef =~ tr/+/ /;
  $namef =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
  $value =~ tr/+/ /;
  $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
  if($query{$namef}){
    $query{$namef} .= ",$value";
    $Multiple{$namef} = 1;
  }else{
    $query{$namef} = $value;
  }
}
foreach $var ("theme","lang","map","iconset","dfc","hfc") {
  if ($query{$var}) {
    ${$var} = $query{$var};
  }
}

# If params are not set via URL, use defaults from config
if (!$theme) {
  $theme = $stdtheme;
}
if (!$iconset) {
  $iconset = $stdiconset;
}

# Build complete themeurl
$themeurl = "$ENV{REQUEST_URI}";
#$themeurl = "$ENV{HTTP_HOST}$ENV{REQUEST_URI}";
$themeurl =~ s/(.*)\?(.*)$/$1/eg;
$themeurl = $themeurl."?theme=".$theme."&lang=".$lang."&iconset=".$iconset;
$themeurlmain = "$themeurl";
$themeurldfc = "$themeurl&dfc=1";
$themeurlhfc = "$themeurl&hfc=1";
$themeurlmap = "$themeurl&map=1";

my $main_file = "$home/templates/plugins/$psubfolder/themes/$lang/$theme.main.html";
my $dfc_file  = "$home/templates/plugins/$psubfolder/themes/$lang/$theme.dfc.html";
my $hfc_file  = "$home/templates/plugins/$psubfolder/themes/$lang/$theme.hfc.html";
my $map_file  = "$home/templates/plugins/$psubfolder/themes/$lang/$theme.map.html";

# new style themes only use the main template for all views, the specific templates are only used for old style themes
my $newstyle = 0;
if (!-e $dfc_file || !-e $hfc_file) {
  $dfc = 1;
  $hfc = 1;
  $newstyle = 1;
}

# NOTE: Code is more or less duplicated from datatoloxone.pl, because it will be removed soon
#       New theme system will fetch all data directly from JSON files and not via variables 
#       on HTML template files that need to be replaced with values on the server side.

##########################################################################
# Load all JSON files at script startup
##########################################################################

# read JSON file with current conditions, daily and hourly forecasts
my $weather_key = "current";
my $envelope = readJsonFile("$home/webfrontend/html/plugins/$psubfolder", $weather_key);
my $cur = $envelope->{$weather_key} // {};
my $location = $envelope->{location} // {};

my $weather_key = "dailyforecast";
my $envelope = readJsonFile("$home/webfrontend/html/plugins/$psubfolder", $weather_key);
my $dfcData = $envelope->{$weather_key} // [];

my $weather_key = "hourlyforecast";
my $envelope = readJsonFile("$home/webfrontend/html/plugins/$psubfolder", $weather_key);
my $hfcData = $envelope->{$weather_key} // [];

my $iconMapping = readJsonFile("$home/webfrontend/html/plugins/$psubfolder/icons/$iconset", "icon_mapping") // {};

##########################################################################
# Prepare param/value for theme web pages - Current conditions
##########################################################################

# Get timezone offset in seconds from tzOffset, e.g. "+0100" => 3600, "-0230" => -9000
my $tzseconds = tzOffsetSeconds($cur->{time}{tzOffset} // "");

# Times are send in local time 
my $curDate = DateTime->from_epoch(epoch => $cur->{time}{epoch}, time_zone => $location->{timezone});
my $curDate_midnight = $curDate->clone->set(hour => 0, minute => 0, second => 0);
my $curDate_LoxoneEpoch = toLoxoneEpoch($curDate_midnight->epoch);

# TODO: To be verified if + $tzseconds is correct 
${"cur_date"} = toLoxoneEpoch($cur->{time}{epoch});                                          # Loxone epoch (1.1.2009, MEZ), e.g. 542934004
${"cur_date_des"} = $cur->{time}{datetime};                                                 # was RFC822, now ISO 8601, e.g. Mon, 16 Mar 2026 23:00:04 +0100
${"cur_date_tz_des_sh"} = $cur->{time}{timezone};                                           # IANA timezone name, e.g. Europe/Berlin
${"cur_date_tz_des"} = $cur->{time}{tzShort};                                              # Time Zone Abbreviation, e.g. CET
${"cur_date_tz"} = $cur->{time}{tzOffset};                                                 # Numeric timezone offset, e.g. +0100
${"cur_day"} = sprintf("%02d", $curDate->day);
${"cur_month"} = sprintf("%02d", $curDate->month);
${"cur_year"} = $curDate->year;
${"cur_hour"} = sprintf("%02d", $curDate->hour);
${"cur_min"} = sprintf("%02d", $curDate->minute);
${"cur_loc_n"} = $location->{city};
${"cur_loc_c"} = $location->{country};
${"cur_loc_ccode"} = $location->{countryCode};
${"cur_loc_lat"} = $location->{latitude};
${"cur_loc_long"} = $location->{longitude};
${"cur_loc_el"} = $location->{elevation};
${"cur_tt"} = !$metric ? $cur->{temperature}{air}*1.8+32 : $cur->{temperature}{air};
${"cur_tt_fl"} = !$metric ? $cur->{temperature}{feelsLike}*1.8+32 : $cur->{temperature}{feelsLike};
${"cur_hu"} = $cur->{humidity};
${"cur_w_dirdes"} = $cur->{wind}{dirLabel};
${"cur_w_dir"} = $cur->{wind}{direction};
${"cur_w_sp"} = !$metric ? $cur->{wind}{speed}*0.621371192 : $cur->{wind}{speed};
${"cur_w_gu"} = !$metric ? $cur->{wind}{gust}*0.621371192 : $cur->{wind}{gust};
${"cur_w_ch"} = !$metric ? $cur->{temperature}{windChill}*1.8+32 : $cur->{temperature}{windChill};
${"cur_pr"} = !$metric ? $cur->{pressure}*0.0295301 : $cur->{pressure};
${"cur_dp"} = !$metric ? $cur->{dewpoint}*1.8+32 : $cur->{dewpoint};
${"cur_vis"} = !$metric ? $cur->{visibility}*0.621371192 : $cur->{visibility};
${"cur_sr"} = $cur->{solarRadiation};
${"cur_hi"} = !$metric ? $cur->{heatIndex}*1.8+32 : $cur->{heatIndex};
${"cur_uvi"} = $cur->{uvIndex};
${"cur_pop"} = $cur->{precipitation}{probability};
# TODO: Verify names
${"cur_prec_today"} = !$metric ? $cur->{precipitation}{rain_today_mm}*0.0393700787 : $cur->{precipitation}{rain_today_mm};
${"cur_prec_1hr"} = !$metric ? $cur->{precipitation}{rain_1hr_mm}*0.0393700787 : $cur->{precipitation}{rain_1hr_mm};
${"cur_snow"} = !$metric ? $cur->{precipitation}{snow_today_cm}*0.393700787 : $cur->{precipitation}{snow_today_cm};
${"cur_we_code"} = $cur->{weatherCode}{loxone};
${"cur_we_des"} = encode_utf8($cur->{weatherCode}{description});
${"cur_moon_p"} = $cur->{moon}{percent};
${"cur_moon_a"} = $cur->{moon}{age};
${"cur_moon_ph"} = $cur->{moon}{phase};
${"cur_moon_h"} = $cur->{moon}{hemisphere};
${"cur_sun_r"} = $curDate_LoxoneEpoch + timeToSec($cur->{sunrise});
${"cur_sun_s"} = $curDate_LoxoneEpoch + timeToSec($cur->{sunset});
${"cur_ozone"} = $cur->{ozone};
${"cur_sky"} = $cur->{cloudCover};

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


#############################################
# MAP VIEW
#############################################

# If map view is requested, open template
if ($map) {
    # Output Theme ot Browser
    print "Content-type: text/html\n\n";
    
    # Try to open map.html, if not available, fallback to main.html, if not available, die with error
    if (open(F, "<", $map_file)) {
    } elsif (open(F, "<", $main_file)) {
    } else {
        die "Missing template: neither $map_file nor $main_file could be opened";
    }
    # Process template with data and output to browser
    while (<F>) {
        $_ =~ s/<!--\$(.*?)-->/${$1}/g;
        print $_;
    }
    close(F);

    exit;
}

#############################################
# Daily Forecast
#############################################

if ($dfc) {

    foreach my $dfcEntry (@$dfcData) {

        # Today is dfc0, tomorrow is dfc1, ...
        my $per = $dfcEntry->{day};

        # Times are send in local time 
        my $dfcDate = DateTime->from_epoch(epoch => $dfcEntry->{time}{epoch}, time_zone => $location->{timezone});

        my $dfcDate_midnight = $dfcDate->clone->set(hour => 0, minute => 0, second => 0);
        my $dfcDate_LoxoneEpoch = toLoxoneEpoch($dfcDate_midnight->epoch);

        ${"dfc${per}_per"} = $per; # period starting with 0 for today, 1 for tomorrow, ...
        ${"dfc${per}_date"} = toLoxoneEpoch($dfcEntry->{time}{epoch});
        ${"dfc${per}_day"} = sprintf("%02d", $dfcDate->day);
        ${"dfc${per}_month"} = sprintf("%02d", $dfcDate->month);
        ${"dfc${per}_monthn"} = $dfcDate->month_name;
        ${"dfc${per}_monthn_sh"} = $dfcDate->month_abbr;
        ${"dfc${per}_year"} = $dfcDate->year;
        ${"dfc${per}_hour"} = sprintf("%02d", $dfcDate->hour);
        ${"dfc${per}_min"} = sprintf("%02d", $dfcDate->minute);
        ${"dfc${per}_wday"} = $dfcDate->day_name;
        ${"dfc${per}_wday_sh"} = $dfcDate->day_abbr;
        ${"dfc${per}_tt_h"} = !$metric ? $dfcEntry->{temperature}{max}{air}*1.8+32 : $dfcEntry->{temperature}{max}{air};
        ${"dfc${per}_tt_l"} = !$metric ? $dfcEntry->{temperature}{min}{air}*1.8+32 : $dfcEntry->{temperature}{min}{air};
        ${"dfc${per}_pop"} = $dfcEntry->{precipitation}{probability};
        ${"dfc${per}_prec"} = !$metric ? $dfcEntry->{precipitation}{rainHigh}*0.0393700787 : $dfcEntry->{precipitation}{rainHigh};
        ${"dfc${per}_snow"} = !$metric ? $dfcEntry->{precipitation}{snowHigh}*0.393700787 : $dfcEntry->{precipitation}{snowHigh};
        ${"dfc${per}_w_sp_h"} = !$metric ? $dfcEntry->{wind}{max}{speed}*0.621371192 : $dfcEntry->{wind}{max}{speed};
        ${"dfc${per}_w_gu_h"} = !$metric ? $dfcEntry->{wind}{max}{gust}*0.621371192 : $dfcEntry->{wind}{max}{gust};
        ${"dfc${per}_w_dirdes_h"} = encode_utf8($dfcEntry->{wind}{max}{dirLabel});
        ${"dfc${per}_w_dir_h"} = $dfcEntry->{wind}{max}{direction};
        ${"dfc${per}_w_sp_a"} = !$metric ? $dfcEntry->{wind}{avg}{speed}*0.621371192 : $dfcEntry->{wind}{avg}{speed};
        ${"dfc${per}_w_gu_a"} = !$metric ? $dfcEntry->{wind}{avg}{gust}*0.621371192 : $dfcEntry->{wind}{avg}{gust};
        ${"dfc${per}_w_dirdes_a"} = encode_utf8($dfcEntry->{wind}{avg}{dirLabel});
        ${"dfc${per}_w_dir_a"} = $dfcEntry->{wind}{avg}{direction};
        ${"dfc${per}_hu_a"} = $dfcEntry->{humidity}{avg};
        ${"dfc${per}_hu_h"} = $dfcEntry->{humidity}{max};
        ${"dfc${per}_hu_l"} = $dfcEntry->{humidity}{min};
        ${"dfc${per}_we_code"} = $dfcEntry->{weatherCode}{loxone};
        ${"dfc${per}_we_des"} = encode_utf8($dfcEntry->{weatherCode}{description});
        ${"dfc${per}_ozone"} = $dfcEntry->{ozone};
        ${"dfc${per}_moon_p"} = $dfcEntry->{moon}{percent};
        ${"dfc${per}_dp"} = !$metric ? $dfcEntry->{dewpoint}*1.8+32 : $dfcEntry->{dewpoint};
        ${"dfc${per}_pr"} = !$metric ? $dfcEntry->{pressure}*0.0295301 : $dfcEntry->{pressure};
        ${"dfc${per}_uvi"} = $dfcEntry->{uvIndex};
        ${"dfc${per}_vis"} = !$metric ? $dfcEntry->{visibility}*0.621371192 : $dfcEntry->{visibility};
        ${"dfc${per}_moon_a"} = $dfcEntry->{moon}{age};
        ${"dfc${per}_moon_ph"} = $dfcEntry->{moon}{phase};
        ${"dfc${per}_sun_r"} = $dfcDate_LoxoneEpoch + timeToSec($dfcEntry->{sunrise});
        ${"dfc${per}_sun_s"} = $dfcDate_LoxoneEpoch + timeToSec($dfcEntry->{sunset});

        # special handling for sunrise and sunset: send as loxone epoch time for easier processing in Loxone,
        # but need to be in hh:mm format on web page
        ${"dfc${per}_sun_r"} = $dfcEntry->{sunrise};
        ${"dfc${per}_sun_s"} = $dfcEntry->{sunset};

        my $iconName = $iconMapping->{icons}{$dfcEntry->{weatherCode}{weather4lox}}{"iconDay"};
        ${"dfc${per}_we_icon"} = $iconName . "." . $iconMapping->{format};
    }

    if (!$newstyle) {
    
        # Output Theme to Browser
        print "Content-type: text/html\n\n";
        open(F,"<$home/templates/plugins/$psubfolder/themes/$lang/$theme.dfc.html") || die "Missing template <$home/templates/plugins/$psubfolder/themes/$lang/$theme.dfc.html";
        while (<F>) {
            $_ =~ s/<!--\$(.*?)-->/${$1}/g;
            print $_;
        }
        close(F);

        exit;
    }
}

#############################################
# Hourly Forecast
#############################################

if ($hfc) {

  ##########################################################################
# Prepare param/value for theme web pages - Hourly forecast
##########################################################################

    foreach my $hfcEntry (@$hfcData) {

        # Today is hfc0, tomorrow is hfc1, ...
        my $per = $hfcEntry->{hour};

        # Times are send in local time 
        my $hfcDate = DateTime->from_epoch(epoch => $hfcEntry->{time}{epoch}, time_zone => $location->{timezone});

        ${"hfc${per}_per"} = $per;
        ${"hfc${per}_date"} = toLoxoneEpoch($hfcEntry->{time}{epoch});
        ${"hfc${per}_day"} = sprintf("%02d", $hfcDate->day);
        ${"hfc${per}_month"} = sprintf("%02d", $hfcDate->month);
        ${"hfc${per}_monthn"} = $hfcDate->month_name;
        ${"hfc${per}_monthn_sh"} = $hfcDate->month_abbr;
        ${"hfc${per}_year"} = $hfcDate->year;
        ${"hfc${per}_hour"} = sprintf("%02d", $hfcDate->hour);
        ${"hfc${per}_min"} = sprintf("%02d", $hfcDate->minute);
        ${"hfc${per}_wday"} = $hfcDate->day_name;
        ${"hfc${per}_wday_sh"} = $hfcDate->day_abbr;
        ${"hfc${per}_tt"} = !$metric ? $hfcEntry->{temperature}{air}*1.8+32 : $hfcEntry->{temperature}{air};
        ${"hfc${per}_tt_fl"} = !$metric ? $hfcEntry->{temperature}{feelsLike}*1.8+32 : $hfcEntry->{temperature}{feelsLike};
        ${"hfc${per}_pop"} = $hfcEntry->{precipitation}{probability};
        ${"hfc${per}_prec"} = !$metric ? $hfcEntry->{precipitation}{rainHigh}*0.0393700787 : $hfcEntry->{precipitation}{rainHigh};
        ${"hfc${per}_snow"} = !$metric ? $hfcEntry->{precipitation}{snowHigh}*0.393700787 : $hfcEntry->{precipitation}{snowHigh};
        ${"hfc${per}_w_sp"} = !$metric ? $hfcEntry->{wind}{speed}*0.621371192 : $hfcEntry->{wind}{speed};
        ${"hfc${per}_w_gu"} = !$metric ? $hfcEntry->{wind}{gust}*0.621371192 : $hfcEntry->{wind}{gust};
        ${"hfc${per}_w_ch"} = !$metric ? $hfcEntry->{temperature}{feelsLike}*1.8+32 : $hfcEntry->{temperature}{feelsLike};
        ${"hfc${per}_w_dirdes"} = encode_utf8($hfcEntry->{wind}{dirLabel});
        ${"hfc${per}_w_dir"} = $hfcEntry->{wind}{direction};
        ${"hfc${per}_hu"} = $hfcEntry->{humidity};
        ${"hfc${per}_we_code"} = $hfcEntry->{weatherCode}{loxone};
        ${"hfc${per}_we_des"} = encode_utf8($hfcEntry->{weatherCode}{description});
        ${"hfc${per}_ozone"} = $hfcEntry->{ozone};
        ${"hfc${per}_moon_p"} = $hfcEntry->{moon}{percent};
        ${"hfc${per}_dp"} = !$metric ? $hfcEntry->{dewpoint}*1.8+32 : $hfcEntry->{dewpoint};
        ${"hfc${per}_pr"} = !$metric ? $hfcEntry->{pressure}*0.0295301 : $hfcEntry->{pressure};
        ${"hfc${per}_uvi"} = $hfcEntry->{uvIndex};
        ${"hfc${per}_vis"} = !$metric ? $hfcEntry->{visibility}*0.621371192 : $hfcEntry->{visibility};
        ${"hfc${per}_moon_a"} = $hfcEntry->{moon}{age};
        ${"hfc${per}_moon_ph"} = $hfcEntry->{moon}{phase};
        ${"hfc${per}_sr"} = $hfcEntry->{solarRadiation};
        ${"hfc${per}_hi"} = !$metric ? $hfcEntry->{heatIndex}*1.8+32 : $hfcEntry->{heatIndex};
        ${"hfc${per}_sky"} = $hfcEntry->{cloudCover};
        ${"hfc${per}_sky_des"} = encode_utf8($hfcEntry->{weatherCode}{description});

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

    if (!$newstyle) {
        # Output Theme to Browser
        print "Content-type: text/html\n\n";
        open(F,"<$home/templates/plugins/$psubfolder/themes/$lang/$theme.hfc.html") || die "Missing template <$home/templates/plugins/$psubfolder/themes/$lang/$theme.hfc.html";
        while (<F>) {
            $_ =~ s/<!--\$(.*?)-->/${$1}/g;
            print $_;
        }
        close(F);

        exit;
    }
}

#############################################
# CURRENT CONDITIONS
#############################################

# Output Theme to Browser
print "Content-type: text/html\n\n";
open(F,"<$home/templates/plugins/$psubfolder/themes/$lang/$theme.main.html") || die "Missing template <$home/templates/plugins/$psubfolder/themes/$lang/$theme.main.html";
while (<F>) {
    $_ =~ s/<!--\$(.*?)-->/${$1}/g;
    print $_;
}
close(F);

##########################################################################
# Helpers to retrieve values from object structure including arrays 
# these function are used to extracts values from API responses (decoded JSONs)
##########################################################################

##########################################################################
# Get a value (string or number from decoded JSON, returns undef if any path 
# segment is missing or invalid.
# Parameters:
#   $root  - root data structure
#   @path  - path elements (tree and param to retrieve)
# Returns:
#   rounded numeric value (e.g. 4.1) or undef if value missing/invalid
# Note: If the current node is an ARRAYref, only numeric indices are accepted.

sub getValue {
    my ($root, @path) = @_;
    my $cur = $root;

    for my $p (@path) {
        return undef unless defined $cur;

        if (ref $cur eq 'ARRAY') {
            # only accept numeric indices for arrays
            return undef unless defined $p && looks_like_number($p);
            my $idx = int($p);
            return undef if $idx < 0 || $idx > $#$cur;    # out of bounds
            $cur = $cur->[$idx];
        }
        elsif (ref $cur eq 'HASH') {
            return undef unless exists $cur->{$p};
            $cur = $cur->{$p};
        }
        else {
            return undef;
        }
    }
    return $cur;
}


##########################################################################
# Get a formatted value (numbers only) from decoded JSON, used for rounding
# Parameters:
#   $fmt   - sprintf format, e.g. '%.2f', round to two decimal places
#   $root  - root data structure
#   @path  - path elements passed to getValue
# Returns:
#   rounded numeric value (e.g. 4.1) or undef if value missing/invalid

sub getFormatted {
    my ($fmt, $root, @path) = @_;

    my $v = getValue($root, @path);
    return undef unless defined $v;
  
    # Trim leading/trailing whitespace (only scalar strings)
    if (!ref $v) {
        $v =~ s/^\s+|\s+$//g;
    }
    # Only accept numerical values
    return undef unless looks_like_number($v);
    return undef if $v =~ /^(?:nan|inf|infinity)$/i;  # just in case

    my $s = sprintf($fmt, $v);
    return $s + 0; # return as number
}

##########################################################################
# Get a formatted value (numbers only) from decoded JSON, used for rounding
# Parameters:
#   $fmt      - sprintf format, e.g. '%H:%M'
#   $root     - root data structure
#   @path     - path elements passed to getValue
# Returns:
#   time information (e.g. 23:10) or undef if value missing/invalid

sub getTimeFormatted {
    my ($fmt, $timezone, $root, @path) = @_;

    # Get value and verify if it is not empty
    my $iso_time = getValue($root, @path);
    return undef unless defined $iso_time && $iso_time ne '';

    my $dt = eval { DateTime::Format::ISO8601->parse_datetime($iso_time) };
    return undef unless $dt;

    # all times are local times, so global variable must be set in grabber
    if ($timezone eq '') {
        $timezone = 'UTC';
    }
    $dt->set_time_zone($timezone);

    return $dt->strftime('%H:%M');
}

##########################################################################
# Get a percentage value by calling getFormatted and multiplying the result by 100.
# Parameters:
#   $fmt   - sprintf format used by getFormatted (e.g. '%.2f')
#   $root  - root data structure (same as for getFormatted)
#   @path  - path elements passed to getFormatted
# Returns:
#   numeric percentage (e.g. 46) or undef if value missing/invalid

sub getPercentage {
    my ($fmt, $root, @path) = @_;

    my $v = getFormatted($fmt, $root, @path);
    return undef unless defined $v;

    return $v * 100;
}

##########################################################################
# Get label for a wind direction in degrees
# Parameters:
#   $deg  - wind direction in degrees (number from 0 to 360 expected)
#   $Lref - optional hashref to localization hash (e.g. \%L)
# Return:
#   $label or (undef, undef) on invalid input

sub getWindDirectionLabel {
    my ($deg, $Lref) = @_;

    # validate/normalize input
    return (undef, undef) unless defined $deg;
    $deg =~ s/^\s+|\s+$//g if !ref $deg;
    return (undef, undef) unless $deg =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/;

    $deg += 0;                              # numericify
    $deg = ($deg % 360 + 360) % 360;        # 0..359.999...

    # wind direction labels for eight‑point compass rose
    my @dirs = qw(N NE E SE S SW W NW);

    # calculate section on eight‑point compass rose
    my $wdir = $dirs[int((($deg + 22.5) / 45)) % 8];

    # take localized labels (either from provided hashref or from global %L)
    my $L = $Lref // \%main::L;
    $L = {} unless defined $L && ref $L eq 'HASH';
    
    my %dirLabels = (
        N  => $L->{'GRABBER.LABEL_N'}  // 'North',
        NE => $L->{'GRABBER.LABEL_NE'} // 'North-East',
        E  => $L->{'GRABBER.LABEL_E'}  // 'East',
        SE => $L->{'GRABBER.LABEL_SE'} // 'South-East',
        S  => $L->{'GRABBER.LABEL_S'}  // 'South',
        SW => $L->{'GRABBER.LABEL_SW'} // 'South-West',
        W  => $L->{'GRABBER.LABEL_W'}  // 'West',
        NW => $L->{'GRABBER.LABEL_NW'} // 'North-West',
    );

    # cur_w_dirdes, wind direction description, e.g. "South",
    my $label = $dirLabels{$wdir};
    $label = defined $label ? Encode::decode("UTF-8", $label) : undef;

    return $label;
}


##########################################################################
# Calculate short name for wind direction from long name
sub getWindDirectionShort {
    my ($wind_descr) = @_;
    
    # calculate short name from description
    my $short = join('', $wind_descr =~ /([A-Z]+)/g);

    return $short;
}


##########################################################################
# Get short and full label for a wind direction in degrees
# Parameters:
#   $deg  - wind direction in degrees (number from 0 to 360 expected)
#   $Lref - optional hashref to localization hash (e.g. \%L)
# Return:
#   ($label, $short) or (undef, undef) on invalid input

sub getWindDirectionInfo {
    my ($deg, $Lref) = @_;

    my $label = getWindDirectionLabel($deg, $Lref);
    my $short = getWindDirectionShort($label);

    return ($label, $short);
}


##########################################################################
# getCoverage($w4l_code) -> returns estimated sky cover percentage (0..100) or undef
# getMetarCode($w4l_code) -> returns METAR cloud code ('SKC','FEW','SCT','BKN','OVC') or undef
#
# Both functions normalize the icon name (trim, lowercase) and strip intensity suffixes
# like "_1", "_2", "_3" before lookup. If the icon is not found in the compact mapping,
# a small pattern-based fallback is applied.

my %W4L_COVERAGE_MAP = (
    clear                      => [  0, 'SKC' ],
    fair                       => [ 10, 'FEW' ],
    partly_cloudy              => [ 40, 'SCT' ],
    cloudy                     => [ 70, 'BKN' ],
    overcast                   => [100, 'OVC' ],

    cloudy_shower              => [ 70, 'BKN' ],
    overcast_shower            => [100, 'OVC' ],

    cloudy_rain                => [ 75, 'BKN' ],
    overcast_rain              => [100, 'OVC' ],

    cloudy_sleet               => [ 75, 'BKN' ],
    overcast_sleet             => [100, 'OVC' ],

    cloudy_snow                => [ 75, 'BKN' ],
    overcast_snow              => [100, 'OVC' ],

    cloudy_freezingrain        => [ 80, 'BKN' ],
    overcast_freezingrain      => [100, 'OVC' ],

    cloudy_thunderstorm        => [ 85, 'OVC' ],
    overcast_thunderstorm      => [100, 'OVC' ],

    cloudy_snowthunderstorm    => [ 85, 'OVC' ],
    overcast_snowthunderstorm  => [100, 'OVC' ],

    cloudy_fog                 => [ 90, 'OVC' ],
    overcast_fog               => [100, 'OVC' ],

    overcast_hail              => [100, 'OVC' ],

    no_data                    => [ undef, undef ],
);

sub _normalizeIcon {
    my ($w4l_code) = @_;
    return undef unless defined $w4l_code;
    $w4l_code =~ s/^\s+|\s+$//g;
    $w4l_code = lc $w4l_code;
    $w4l_code =~ s/_[1-3]$//;    # strip intensity suffix like _1, _2, _3
    return $w4l_code;
}

sub _fallbackMap {
    my ($w4l_code) = @_;
    return (100, 'OVC') if $w4l_code =~ /overcast|ovc|overcast_/;
    return (90,  'OVC') if $w4l_code =~ /thunder|storm/;
    return (90,  'OVC') if $w4l_code =~ /fog|mist|smog|haze/;
    return (80,  'BKN') if $w4l_code =~ /snow|sleet|graupel/;
    return (85,  'OVC') if $w4l_code =~ /freezingrain|freezing/;
    return (75,  'BKN') if $w4l_code =~ /rain|shower|drizzle/;
    return (40,  'SCT') if $w4l_code =~ /partly|partly_cloudy/;
    return (70,  'BKN') if $w4l_code =~ /cloudy|cloud/;
    return (10,  'FEW') if $w4l_code =~ /fair/;
    return (0,   'SKC') if $w4l_code =~ /clear|sun/;
    return (undef, undef);
}


##########################################################################
# Public: returns sky cover percentage (0..100) or undef
sub getCoverage {
    my ($w4l_code) = @_;
    my $w4l_short_code = _normalizeIcon($w4l_code);
    return undef unless defined $w4l_short_code;

    if (exists $W4L_COVERAGE_MAP{$w4l_short_code}) {
        return $W4L_COVERAGE_MAP{$w4l_short_code}[0];
    }

    my ($pct, $metar) = _fallbackMap($w4l_short_code);
    return $pct;
}


##########################################################################
# Public: returns METAR cloud code (SKC, FEW, SCT, BKN, OVC) or undef
sub getMetarCode {
    my ($w4l_code) = @_;
    my $w4l_short_code = _normalizeIcon($w4l_code);
    return undef unless defined $w4l_short_code;

    if (exists $W4L_COVERAGE_MAP{$w4l_short_code}) {
        return $W4L_COVERAGE_MAP{$w4l_short_code}[1];
    }

    my ($pct, $metar) = _fallbackMap($w4l_short_code);
    return $metar;
}

# Example usage:
# my $cover = getCoverage('cloudy_rain_1');   # -> e.g. 75
# my $metar = getMetarCode('cloudy_rain_1');# -> e.g. 'BKN'


##########################################################################
# Returns the moon waxing/waning state
sub getMoonDirection {
    my $age = shift;                 # moon age in days (0..29.53)
    my $synodicMonth = 29.53;

    $age = $age % $synodicMonth; # normalize age

    # Determine direction: waxing (<full moon), waning (>full moon)
    if ($age < ($synodicMonth / 2)) {
        return 'waxing';
    } else {
        return 'waning';
    }
}


##########################################################################
# Returns the moon phase part, either quarter (0q, 1q, 2q, 3q, 4q) or half (0h, 1h, 2h)
# phases 0q = new, 1q = waxing crescent, 2q = first quarter, 3q = waxing gibbous, 4q = full
#        3q = waning gibbous, 2q = last quarter, 1q = waning crescent
# Parameters:
#   $age:         moon age in days (0..29.53)
#   $resolution:  5 for 'quarter' or 3 for 'half' (default: 'quarter')

sub getMoonPhasePart {
    my ($age, $resolution) = @_;
    my $synodicMonth = 29.53;

    # normalize age to 0..29.53
    $age = $age % $synodicMonth;

    # full moon is at half of the synodic month
    my $fullSize = $synodicMonth / 2;
    
    # For the second half (full to new), the quarter is proportional to the remaining time.
    $age = $synodicMonth - $age if ($age > $fullSize);

    return int($age / $fullSize * ($resolution - 1) + 0.5); # round to nearest integer
}


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
    #     time_zone => 'MEZ'     # time reference is Kollerschlag time (MEZ/UTC+1) according to findings, not UTC!
    # );
    # my $loxone_epoch = $date->epoch - $loxone_ref->epoch;

    my $loxone_ref = 1230764400;                        # time reference is Kollerschlag time (MEZ/UTC+1) according to findings, not UTC!
    my $loxone_epoch = $date->epoch - $loxone_ref;

    return $loxone_epoch;
}


##########################################################################
# Get timezone offset in seconds from tzOffset, e.g. "+01:00" => 3600,
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


##########################################################################
# Generalized JSON file reader for any weather type (current, daily, hourly).
# Parameter:
#   weather_key:        'current' | 'dailyforecast' | 'hourlyforecast'
#   filepath:           directory for file

sub readJsonFile {
    my ($filepath, $weather_key) = @_;

    my $filename = "$filepath/$weather_key.json";

    # Existenz prüfen
    unless (-f $filename) {
        print "File not found: $filename";
        return undef;
    }

    # Datei lesen und parsen
    my $json_text;
    eval {
        open my $fh, '<:raw', $filename or die "Cannot open $filename: $!";
        local $/;
        flock($fh, 1);  # LOCK_SH — shared read lock
        $json_text = <$fh>;
        flock($fh, 8);  # LOCK_UN
        close $fh;
    };
    if ($@) {
        print "Failed to read $filename: $@";
        return undef;
    }

    # JSON-Deserialisierung    
    my $data;
    eval {
        $data = JSON::PP->new->utf8->decode($json_text);
    };
    if ($@) {
        print "Failed to decode JSON from $filename: $@";
        return undef;
    }

    return $data;
}

exit;
