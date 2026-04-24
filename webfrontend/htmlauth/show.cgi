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
use LoxBerry::System;
use LoxBerry::Log;

require "$lbpbindir/grabber_utils.pl";

# Hash populated by build_tmpl_vars() before each template rendering pass.
# Only variables whose names match the expected template naming patterns are
# exposed – this prevents theme files from leaking internal scalars like
# $home, $pcfg, $lbpconfigdir, etc. via <!--$varname--> substitution.
our %tmpl_vars;

# Collect all package scalars whose names match known template-variable
# patterns into %tmpl_vars.  Must be called just before each template
# rendering pass so that the hash is current.
sub build_tmpl_vars {
    %tmpl_vars = ();
    for my $n (keys %main::) {
        # Allow only names that follow the known template-variable naming
        # patterns: lowercase letters, digits and underscores only.
        # \w* expands to [a-zA-Z0-9_]* – dots, slashes and other characters
        # that could be used for path traversal or injection are rejected.
        next unless $n =~ /\A(?:cur_|dfc\d+_|hfc\d+_|themeurl|mapurl|webpath)[a-zA-Z0-9_]*\z/;
        no strict 'refs';
        $tmpl_vars{$n} = ${$n} if defined ${$n};
    }
    # Always expose the helper URL vars even if they happen to be undef
    for my $n (qw(themeurl themeurlmain themeurldfc themeurlhfc themeurlmap)) {
        no strict 'refs';
        $tmpl_vars{$n} = ${$n} // '' unless exists $tmpl_vars{$n};
    }
}

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

# Lade Sprachstrings (language.ini + sprachspezifische Dateien)
my %L = LoxBerry::System::readlanguage("language.ini");

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

# weather code descriptions are stored in a separate language file, because they are needed in the theme for the weather codes list.
my $lang_data = readJsonFile("$home/webfrontend/html/plugins/$psubfolder", "lang-$lang") // {};

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
my $curDate_LoxoneEpoch = toLoxEpoch($curDate_midnight->epoch);

# TODO: To be verified if + $tzseconds is correct 
${"cur_date"} = toLoxEpoch($cur->{time}{epoch});                                          # Loxone epoch (1.1.2009, MEZ), e.g. 542934004
${"cur_date_des"} = $cur->{time}{datetime};                                               # was RFC822, now ISO 8601, e.g. Mon, 16 Mar 2026 23:00:04 +0100
${"cur_date_tz_des_sh"} = $cur->{time}{timezone};                                         # IANA timezone name, e.g. Europe/Berlin
${"cur_date_tz_des"} = $cur->{time}{tzShort};                                             # Time Zone Abbreviation, e.g. CET
${"cur_date_tz"} = $cur->{time}{tzOffset};                                                # Numeric timezone offset, e.g. +0100
${"cur_day"} = encode_utf8(sprintf("%02d", $curDate->day));
${"cur_month"} = encode_utf8(sprintf("%02d", $curDate->month));
${"cur_year"} = encode_utf8($curDate->year);
${"cur_hour"} = encode_utf8(sprintf("%02d", $curDate->hour));
${"cur_min"} = encode_utf8(sprintf("%02d", $curDate->minute));
${"cur_loc_n"} = encode_utf8($location->{city});
${"cur_loc_c"} = encode_utf8($location->{country});
${"cur_loc_ccode"} = encode_utf8($location->{countryCode});
${"cur_loc_lat"} = $location->{latitude};
${"cur_loc_long"} = $location->{longitude};
${"cur_loc_el"} = $location->{elevation};
${"cur_tt"} = !$metric ? $cur->{temperature}{air}*1.8+32 : $cur->{temperature}{air};
${"cur_tt_fl"} = !$metric ? $cur->{temperature}{feelsLike}*1.8+32 : $cur->{temperature}{feelsLike};
${"cur_hu"} = $cur->{humidity};
${"cur_w_dirdes"} = encode_utf8(getWindDirectionLabel($cur->{wind}{direction}, \%L) // '');
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
${"cur_prec_today"} = !$metric ? $cur->{precipitation}{rainToday}*0.0393700787 : $cur->{precipitation}{rainToday};
${"cur_prec_1hr"} = !$metric ? $cur->{precipitation}{rain1hr}*0.0393700787 : $cur->{precipitation}{rain1hr};
${"cur_snow"} = !$metric ? $cur->{precipitation}{snowToday}*0.393700787 : $cur->{precipitation}{snowToday};
${"cur_we_code"} = $cur->{weatherCode}{loxone};
${"cur_we_des"} = encode_utf8($lang_data->{weather_descriptions}{$cur->{weatherCode}{weather4lox}} // '-');
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
    build_tmpl_vars();
    while (<F>) {
        $_ =~ s/<!--\$(.*?)-->/exists $tmpl_vars{$1} ? $tmpl_vars{$1} : ''/ge;
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
        my $dfcDate_LoxoneEpoch = toLoxEpoch($dfcDate_midnight->epoch);

        ${"dfc${per}_per"} = $per; # period starting with 0 for today, 1 for tomorrow, ...
        ${"dfc${per}_date"} = toLoxEpoch($dfcEntry->{time}{epoch});
        ${"dfc${per}_day"} = encode_utf8(sprintf("%02d", $dfcDate->day));
        ${"dfc${per}_month"} = encode_utf8(sprintf("%02d", $dfcDate->month));
        ${"dfc${per}_monthn"} = encode_utf8($dfcDate->month_name);
        ${"dfc${per}_monthn_sh"} = encode_utf8($dfcDate->month_abbr);
        ${"dfc${per}_year"} = encode_utf8($dfcDate->year);
        ${"dfc${per}_hour"} = encode_utf8(sprintf("%02d", $dfcDate->hour));
        ${"dfc${per}_min"} = encode_utf8(sprintf("%02d", $dfcDate->minute));
        ${"dfc${per}_wday"} = encode_utf8($dfcDate->day_name);
        ${"dfc${per}_wday_sh"} = encode_utf8($dfcDate->day_abbr);
        ${"dfc${per}_tt_h"} = !$metric ? $dfcEntry->{temperature}{max}{air}*1.8+32 : $dfcEntry->{temperature}{max}{air};
        ${"dfc${per}_tt_l"} = !$metric ? $dfcEntry->{temperature}{min}{air}*1.8+32 : $dfcEntry->{temperature}{min}{air};
        ${"dfc${per}_pop"} = $dfcEntry->{precipitation}{probability};
        ${"dfc${per}_prec"} = !$metric ? $dfcEntry->{precipitation}{rainHigh}*0.0393700787 : $dfcEntry->{precipitation}{rainHigh};
        ${"dfc${per}_snow"} = !$metric ? $dfcEntry->{precipitation}{snowHigh}*0.393700787 : $dfcEntry->{precipitation}{snowHigh};
        ${"dfc${per}_w_sp_h"} = !$metric ? $dfcEntry->{wind}{max}{speed}*0.621371192 : $dfcEntry->{wind}{max}{speed};
        ${"dfc${per}_w_gu_h"} = !$metric ? $dfcEntry->{wind}{max}{gust}*0.621371192 : $dfcEntry->{wind}{max}{gust};
        ${"dfc${per}_w_dirdes_h"} = encode_utf8(getWindDirectionLabel($dfcEntry->{wind}{max}{direction}, \%L) // '');
        ${"dfc${per}_w_dir_h"} = $dfcEntry->{wind}{max}{direction};
        ${"dfc${per}_w_sp_a"} = !$metric ? $dfcEntry->{wind}{avg}{speed}*0.621371192 : $dfcEntry->{wind}{avg}{speed};
        ${"dfc${per}_w_gu_a"} = !$metric ? $dfcEntry->{wind}{avg}{gust}*0.621371192 : $dfcEntry->{wind}{avg}{gust};
        ${"dfc${per}_w_dirdes_a"} = encode_utf8(getWindDirectionLabel($dfcEntry->{wind}{avg}{direction}, \%L) // '');
        ${"dfc${per}_w_dir_a"} = $dfcEntry->{wind}{avg}{direction};
        ${"dfc${per}_hu_a"} = $dfcEntry->{humidity}{avg};
        ${"dfc${per}_hu_h"} = $dfcEntry->{humidity}{max};
        ${"dfc${per}_hu_l"} = $dfcEntry->{humidity}{min};
        ${"dfc${per}_we_code"} = $dfcEntry->{weatherCode}{loxone};
        ${"dfc${per}_we_des"} = encode_utf8($lang_data->{weather_descriptions}{$dfcEntry->{weatherCode}{weather4lox}} // '-');
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
        ${"hfc${per}_date"} = toLoxEpoch($hfcEntry->{time}{epoch});
        ${"hfc${per}_day"} = encode_utf8(sprintf("%02d", $hfcDate->day));
        ${"hfc${per}_month"} = encode_utf8(sprintf("%02d", $hfcDate->month));
        ${"hfc${per}_monthn"} = encode_utf8($hfcDate->month_name);
        ${"hfc${per}_monthn_sh"} = encode_utf8($hfcDate->month_abbr);
        ${"hfc${per}_year"} = encode_utf8($hfcDate->year);
        ${"hfc${per}_hour"} = encode_utf8(sprintf("%02d", $hfcDate->hour));
        ${"hfc${per}_min"} = encode_utf8(sprintf("%02d", $hfcDate->minute));
        ${"hfc${per}_wday"} = encode_utf8($hfcDate->day_name);
        ${"hfc${per}_wday_sh"} = encode_utf8($hfcDate->day_abbr);
        ${"hfc${per}_tt"} = !$metric ? $hfcEntry->{temperature}{air}*1.8+32 : $hfcEntry->{temperature}{air};
        ${"hfc${per}_tt_fl"} = !$metric ? $hfcEntry->{temperature}{feelsLike}*1.8+32 : $hfcEntry->{temperature}{feelsLike};
        ${"hfc${per}_pop"} = $hfcEntry->{precipitation}{probability};
        ${"hfc${per}_prec"} = !$metric ? $hfcEntry->{precipitation}{rainHigh}*0.0393700787 : $hfcEntry->{precipitation}{rainHigh};
        ${"hfc${per}_snow"} = !$metric ? $hfcEntry->{precipitation}{snowHigh}*0.393700787 : $hfcEntry->{precipitation}{snowHigh};
        ${"hfc${per}_w_sp"} = !$metric ? $hfcEntry->{wind}{speed}*0.621371192 : $hfcEntry->{wind}{speed};
        ${"hfc${per}_w_gu"} = !$metric ? $hfcEntry->{wind}{gust}*0.621371192 : $hfcEntry->{wind}{gust};
        ${"hfc${per}_w_ch"} = !$metric ? $hfcEntry->{temperature}{feelsLike}*1.8+32 : $hfcEntry->{temperature}{feelsLike};
        ${"hfc${per}_w_dirdes"} = encode_utf8(getWindDirectionLabel($hfcEntry->{wind}{direction}, \%L) // '');
        ${"hfc${per}_w_dir"} = $hfcEntry->{wind}{direction};
        ${"hfc${per}_hu"} = $hfcEntry->{humidity};
        ${"hfc${per}_we_code"} = $hfcEntry->{weatherCode}{loxone};
        ${"hfc${per}_we_des"} = encode_utf8($lang_data->{weather_descriptions}{$hfcEntry->{weatherCode}{weather4lox}} // '-');
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
        ${"hfc${per}_sky_des"} = encode_utf8($lang_data->{weather_descriptions}{$hfcEntry->{weatherCode}{weather4lox}} // '-');

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
        build_tmpl_vars();
        while (<F>) {
            $_ =~ s/<!--\$(.*?)-->/exists $tmpl_vars{$1} ? $tmpl_vars{$1} : ''/ge;
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
build_tmpl_vars();
while (<F>) {
    $_ =~ s/<!--\$(.*?)-->/exists $tmpl_vars{$1} ? $tmpl_vars{$1} : ''/ge;
    print $_;
}
close(F);

exit;
