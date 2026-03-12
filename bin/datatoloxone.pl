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
# Modules
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

##########################################################################
# Read settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

our $pcfg             = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my  $udpport          = $pcfg->param("SERVER.UDPPORT");
my  $senddfc          = $pcfg->param("SERVER.SENDDFC");
my  $sendhfc          = $pcfg->param("SERVER.SENDHFC");
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

##########################################################################
# JSON helper subroutines
##########################################################################

sub load_json_file {
    my ($path) = @_;
    unless (-f $path) {
        LOGCRIT "Required JSON file not found: $path";
        LOGEND;
        exit 1;
    }
    local $/;
    open(my $fh, '<:raw', $path) or do {
        LOGCRIT "Cannot open $path: $!";
        LOGEND;
        exit 1;
    };
    flock($fh, 1);  # LOCK_SH — shared read lock
    my $raw = <$fh>;
    flock($fh, 8);  # LOCK_UN
    close($fh);
    my $decoded = eval { JSON::PP->new->utf8->decode($raw) };
    if ($@ || !$decoded) {
        LOGCRIT "JSON parse error in $path: $@";
        LOGEND;
        exit 1;
    }
    return $decoded;
}

# Null-safe value helper: return -9999 for undef (JSON null) where Loxone expects it
sub _jval {
    my ($v) = @_;
    return defined($v) ? $v : -9999;
}

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
my $cur_json = load_json_file("$lbplogdir/current.json");
my $dfc_json = load_json_file("$lbplogdir/dailyforecast.json");
my $hfc_json = load_json_file("$lbplogdir/hourlyforecast.json");

my $cur  = $cur_json->{data};           # hashref
my @dfc  = @{ $dfc_json->{data} };     # array of hashrefs, ordered by period
my @hfc  = @{ $hfc_json->{data} };     # array of hashrefs, ordered by period

LOGOK "JSON data files loaded successfully.";

#
# Print out current conditions
#

our $sendqueue = 0;
our $value;
our $name;
our $tmpudp;
our $udp;

# Check for empty/missing epoch
if (!defined($cur->{epoch}) || $cur->{epoch} eq "") {
  $cur->{epoch} = 1230764400;
}

# Derive timezone offset from datetime ISO string for Loxone epoch correction
# $cur->{datetime} = "2026-03-12T20:45:00+01:00"
my $tzseconds = 0;
if (defined($cur->{datetime}) && $cur->{datetime} =~ /([+-])(\d{2}):(\d{2})$/) {
    my $sign = ($1 eq '+') ? 1 : -1;
    $tzseconds = $sign * ($2 * 3600 + $3 * 60);
}

# EpochDate - Corrected by TZ
our $epochdate = DateTime->from_epoch(
      epoch      => $cur->{epoch},
);
$epochdate->add( seconds => $tzseconds );

$name = "cur_date";
$value = $cur->{epoch} - $dateref->epoch() + $tzseconds;
&send;

# Derive legacy timezone fields from JSON
# cur_date_des: was RFC822, now ISO 8601
my $cur_date_des = $cur->{datetime};

# cur_date_tz_des: IANA timezone name
my $cur_date_tz_des = $cur->{timezone};

# cur_date_tz_des_sh: short tz abbreviation — derive via DateTime with tz
my $cur_date_tz_des_sh = "";
if (defined($cur->{timezone}) && defined($cur->{epoch})) {
    eval {
        my $dt_cur = DateTime->from_epoch(
            epoch     => $cur->{epoch},
            time_zone => $cur->{timezone},
        );
        $cur_date_tz_des_sh = $dt_cur->time_zone_short_name();
    };
    if ($@) { $cur_date_tz_des_sh = $cur->{timezone}; }
}

# cur_date_tz: numeric offset e.g. "+0100"
my $cur_date_tz = "";
if (defined($cur->{datetime}) && $cur->{datetime} =~ /([+-])(\d{2}):(\d{2})$/) {
    $cur_date_tz = sprintf("%s%02d%02d", $1, $2, $3);
}

$name = "cur_date_des";
$value = $cur_date_des;
&send;

$name = "cur_date_tz_des_sh";
$value = $cur_date_tz_des_sh;
&send;

$name = "cur_date_tz_des";
$value = $cur_date_tz_des;
&send;

$name = "cur_date_tz";
$value = $cur_date_tz;
&send;

$name = "cur_day";
$value = $epochdate->day;
&send;

$name = "cur_month";
$value = $epochdate->month;
&send;

$name = "cur_year";
$value = $epochdate->year;
&send;

$name = "cur_hour";
$value = $epochdate->hour;
&send;

$name = "cur_min";
$value = $epochdate->minute;
&send;

$name = "cur_loc_n";
$value = $cur->{city};
&send;

$name = "cur_loc_c";
$value = $cur->{country};
&send;

$name = "cur_loc_ccode";
$value = $cur->{country_code};
&send;

$name = "cur_loc_lat";
$value = $cur->{latitude};
&send;

$name = "cur_loc_long";
$value = $cur->{longitude};
&send;

$name = "cur_loc_el";
$value = $cur->{elevation};
&send;

$name = "cur_tt";
if (!$metric) {$value = $cur->{temperature}*1.8+32} else {$value = $cur->{temperature}};
&send;

$name = "cur_tt_fl";
if (!$metric) {$value = $cur->{feelslike}*1.8+32} else {$value = $cur->{feelslike}};
&send;

$name = "cur_hu";
$value = $cur->{humidity};
&send;

$name = "cur_w_dirdes";
$value = $cur->{wind_direction_desc};
&send;

$name = "cur_w_dir";
$value = $cur->{wind_direction_deg};
&send;

$name = "cur_w_sp";
if (!$metric) {$value = $cur->{wind_speed}*0.621371192} else {$value = $cur->{wind_speed}};
&send;

$name = "cur_w_gu";
if (!$metric) {$value = $cur->{wind_gust}*0.621371192} else {$value = $cur->{wind_gust}};
&send;

$name = "cur_w_ch";
if (!$metric) {$value = $cur->{windchill}*1.8+32} else {$value = $cur->{windchill}};
&send;

$name = "cur_pr";
if (!$metric) {$value = $cur->{pressure}*0.0295301} else {$value = $cur->{pressure}};
&send;

$name = "cur_dp";
if (!$metric) {$value = $cur->{dewpoint}*1.8+32} else {$value = $cur->{dewpoint}};
&send;

$name = "cur_vis";
if (!$metric) {$value = $cur->{visibility}*0.621371192} else {$value = $cur->{visibility}};
&send;

$name = "cur_sr";
$value = $cur->{solar_radiation};
&send;

$name = "cur_hi";
if (!$metric) {$value = $cur->{heat_index}*1.8+32} else {$value = $cur->{heat_index}};
&send;

$name = "cur_uvi";
$value = $cur->{uv_index};
&send;

$name = "cur_prec_today";
if (!$metric) {$value = $cur->{precip_today_mm}*0.0393700787} else {$value = $cur->{precip_today_mm}};
&send;

$name = "cur_prec_1hr";
if (!$metric) {$value = $cur->{precip_1hr_mm}*0.0393700787} else {$value = $cur->{precip_1hr_mm}};
&send;

$name = "cur_we_icon";
$value = $cur->{weather_icon};
&send;

$name = "cur_we_code";
$value = $cur->{weather_code};
&send;

$name = "cur_we_des";
$value = $cur->{weather_description};
&send;

$name = "cur_moon_p";
$value = $cur->{moon_percent};
&send;

$name = "cur_moon_a";
$value = $cur->{moon_age};
&send;

$name = "cur_moon_ph";
$value = $cur->{moon_phase};
&send;

$name = "cur_moon_h";
$value = $cur->{moon_hemisphere};
&send;

# Create Sunset/rise Date in Loxone Epoch Format (1.1.2009)
# JSON delivers "HH:MM" string; split(':') to get hour and minute
# Sunrise
my ($sunr_h, $sunr_m) = defined($cur->{sunrise})
    ? split(/:/, $cur->{sunrise})
    : (undef, undef);

my $sunrdate;
if (defined($sunr_h) && $sunr_h < 24 && $sunr_h >= 0
    && defined($sunr_m) && $sunr_m < 60 && $sunr_m >= 0) {
	$sunrdate = DateTime->new(
	      year      => $epochdate -> year(),
	      month     => $epochdate -> month(),
	      day       => $epochdate -> day(),
	      hour      => $sunr_h,
	      minute    => $sunr_m,
	);
	$name = "cur_sun_r";
	$value = $sunrdate->epoch() - $dateref->epoch();
} else {
	$sunrdate = "-9999";
	$name = "cur_sun_r";
	$value = $sunrdate;
}
&send;

# Sunset
my ($suns_h, $suns_m) = defined($cur->{sunset})
    ? split(/:/, $cur->{sunset})
    : (undef, undef);

my $sunsdate;
if (defined($suns_h) && $suns_h < 24 && $suns_h >= 0
    && defined($suns_m) && $suns_m < 60 && $suns_m >= 0) {
	$sunsdate = DateTime->new(
	      year      => $epochdate -> year(),
	      month     => $epochdate -> month(),
	      day       => $epochdate -> day(),
	      hour      => $suns_h,
	      minute    => $suns_m,
	);
	$name = "cur_sun_s";
	$value = $sunsdate->epoch() - $dateref->epoch();
} else {
	$sunsdate = "-9999";
	$name = "cur_sun_s";
	$value = $sunsdate;
}
&send;

$name = "cur_ozone";
$value = _jval($cur->{ozone});
&send;

$name = "cur_sky";
$value = _jval($cur->{cloud_cover});
&send;

$name = "cur_pop";
$value = _jval($cur->{precip_probability});
&send;

$name = "cur_snow";
$value = _jval($cur->{snow});
$udp = 1; # Really send now in one run
&send;

# Send raw current observation data over MQTT
#$name = "current";
#$value = $cur->{datetime};
#&sendmqtt;

#
# Print out Daily Forecast
#

$data = "";

foreach my $dfc_entry (@dfc) {

  my $per = $dfc_entry->{period};

  # Send values only if we should do so
  our $send = 0;
  foreach (split(/;/,$senddfc)){
    if ($_ eq $per) {
      $send = 1;
    }
  }
  if (!$send) {
    next;
  }

  # DFC: Today is dfc0
  $per = $per - 1;

  # Check for empty data
  if (!defined($dfc_entry->{epoch}) || $dfc_entry->{epoch} eq "") {
    $dfc_entry->{epoch} = 1230764400;
  }

  # Calculate Epoch Date for this forecast day
  my $epochdatedfc = DateTime->from_epoch(
      epoch      => $dfc_entry->{epoch},
  );
  $epochdatedfc->add( seconds => $tzseconds );

  $name = "dfc$per\_per";
  $value = $per;
  &send;

  $name = "dfc$per\_date";
  $value = $dfc_entry->{epoch} - $dateref->epoch();
  &send;

  $name = "dfc$per\_day";
  $value = $epochdatedfc->day;
  &send;

  $name = "dfc$per\_month";
  $value = $epochdatedfc->month;
  &send;

  $name = "dfc$per\_monthn";
  $value = $epochdatedfc->month_name;
  &send;

  $name = "dfc$per\_monthn_sh";
  $value = $epochdatedfc->month_abbr;
  &send;

  $name = "dfc$per\_year";
  $value = $epochdatedfc->year;
  &send;

  $name = "dfc$per\_hour";
  $value = $epochdatedfc->hour;
  &send;

  $name = "dfc$per\_min";
  $value = $epochdatedfc->minute;
  &send;

  $name = "dfc$per\_wday";
  $value = $epochdatedfc->day_name;
  &send;

  $name = "dfc$per\_wday_sh";
  $value = $epochdatedfc->day_abbr;
  &send;

  $name = "dfc$per\_tt_h";
  if (!$metric) {$value = $dfc_entry->{high_temp}*1.8+32} else {$value = $dfc_entry->{high_temp};}
  &send;

  $name = "dfc$per\_tt_l";
  if (!$metric) {$value = $dfc_entry->{low_temp}*1.8+32} else {$value = $dfc_entry->{low_temp};}
  &send;

  $name = "dfc$per\_pop";
  $value = $dfc_entry->{precip_probability};
  &send;

  $name = "dfc$per\_prec";
  if (!$metric) {$value = $dfc_entry->{precip_mm}*0.0393700787} else {$value = $dfc_entry->{precip_mm};}
  &send;

  $name = "dfc$per\_snow";
  if (!$metric) {$value = $dfc_entry->{snow_cm}*0.393700787} else {$value = $dfc_entry->{snow_cm};}
  &send;

  $name = "dfc$per\_w_sp_h";
  if (!$metric) {$value = $dfc_entry->{wind_speed_max}*0.621} else {$value = $dfc_entry->{wind_speed_max};}
  &send;

  $name = "dfc$per\_w_dirdes_h";
  $value = $dfc_entry->{wind_dir_max_desc};
  &send;

  $name = "dfc$per\_w_dir_h";
  $value = $dfc_entry->{wind_dir_max_deg};
  &send;

  $name = "dfc$per\_w_sp_a";
  if (!$metric) {$value = $dfc_entry->{wind_speed_avg}*0.621} else {$value = $dfc_entry->{wind_speed_avg};}
  &send;

  $name = "dfc$per\_w_dirdes_a";
  $value = $dfc_entry->{wind_dir_avg_desc};
  &send;

  $name = "dfc$per\_w_dir_a";
  $value = $dfc_entry->{wind_dir_avg_deg};
  &send;

  $name = "dfc$per\_hu_a";
  $value = $dfc_entry->{humidity_avg};
  &send;

  $name = "dfc$per\_hu_h";
  $value = $dfc_entry->{humidity_max};
  &send;

  $name = "dfc$per\_hu_l";
  $value = $dfc_entry->{humidity_min};
  &send;

  $name = "dfc$per\_we_icon";
  $value = $dfc_entry->{weather_icon};
  &send;

  $name = "dfc$per\_we_code";
  $value = $dfc_entry->{weather_code};
  &send;

  $name = "dfc$per\_we_des";
  $value = $dfc_entry->{weather_description};
  &send;

  $name = "dfc$per\_ozone";
  $value = _jval($dfc_entry->{ozone});
  &send;

  $name = "dfc$per\_moon_p";
  $value = $dfc_entry->{moon_percent};
  &send;

  $name = "dfc$per\_dp";
  if (!$metric) {$value = $dfc_entry->{dewpoint}*1.8+32} else {$value = $dfc_entry->{dewpoint};}
  &send;

  $name = "dfc$per\_pr";
  if (!$metric) {$value = $dfc_entry->{pressure}*0.0295301} else {$value = $dfc_entry->{pressure}};
  &send;

  $name = "dfc$per\_uvi";
  $value = $dfc_entry->{uv_index};
  &send;

  # Create Sunset/rise Date in Loxone Epoch Format (1.1.2009)
  # Per Pitfall 4: use $epochdate (current conditions date) as base — preserving existing behavior
  # Sunrise
  my ($dfc_sunr_h, $dfc_sunr_m) = defined($dfc_entry->{sunrise})
      ? split(/:/, $dfc_entry->{sunrise})
      : (undef, undef);

  my $sunrdate;
  if (defined($dfc_sunr_h) && $dfc_sunr_h < 24 && $dfc_sunr_h >= 0
      && defined($dfc_sunr_m) && $dfc_sunr_m < 60 && $dfc_sunr_m >= 0) {
	$sunrdate = DateTime->new(
	      year      => $epochdate -> year(),
	      month     => $epochdate -> month(),
	      day       => $epochdate -> day(),
	      hour      => $dfc_sunr_h,
	      minute    => $dfc_sunr_m,
	);
	$name = "dfc$per\_sun_r";
	$value = $sunrdate->epoch() - $dateref->epoch();
  } else {
	$sunrdate = "-9999";
	$name = "dfc$per\_sun_r";
	$value = $sunrdate;
  }
  &send;

  # Sunset
  my ($dfc_suns_h, $dfc_suns_m) = defined($dfc_entry->{sunset})
      ? split(/:/, $dfc_entry->{sunset})
      : (undef, undef);

  my $sunsdate;
  if (defined($dfc_suns_h) && $dfc_suns_h < 24 && $dfc_suns_h >= 0
      && defined($dfc_suns_m) && $dfc_suns_m < 60 && $dfc_suns_m >= 0) {
	$sunsdate = DateTime->new(
	      year      => $epochdate -> year(),
	      month     => $epochdate -> month(),
	      day       => $epochdate -> day(),
	      hour      => $dfc_suns_h,
	      minute    => $dfc_suns_m,
	);
  	$name = "dfc$per\_sun_s";
	$value = $sunsdate->epoch() - $dateref->epoch();
  } else {
	$sunsdate = "-9999";
  	$name = "dfc$per\_sun_s";
	$value = $sunsdate;
  }
  &send;

  $name = "dfc$per\_vis";
  $value = $dfc_entry->{visibility};
  &send;

  $name = "dfc$per\_moon_a";
  $value = $dfc_entry->{moon_age};
  &send;

  $name = "dfc$per\_moon_ph";
  $value = $dfc_entry->{moon_phase};
  $udp = 1; # Really send now in one run
  &send;
}

# Send raw daily forecast data over MQTT
#$name = "daily";
#$value = $data;
#&sendmqtt;

#
# Print out Hourly Forecast
#

$data = "";

foreach my $hfc_entry (@hfc) {

  my $per = $hfc_entry->{period};

  # Send values only if we should do so
  $send = 0;
  foreach (split(/;/,$sendhfc)){
    if ($_ eq $per) {
      $send = 1;
    }
  }
  if (!$send) {
    next;
  }

  # Check for empty data
  if (!defined($hfc_entry->{epoch}) || $hfc_entry->{epoch} eq "") {
    $hfc_entry->{epoch} = 1230764400;
  }

  # Calculate Epoch Date for this hourly forecast entry
  my $epochdatehfc = DateTime->from_epoch(
      epoch      => $hfc_entry->{epoch},
  );
  $epochdatehfc->add( seconds => $tzseconds );

  $name = "hfc$per\_per";
  $value = $hfc_entry->{period};
  &send;

  $name = "hfc$per\_date";
  $value = $hfc_entry->{epoch} - $dateref->epoch();
  &send;

  $name = "hfc$per\_day";
  $value = $epochdatehfc->day;
  &send;

  $name = "hfc$per\_month";
  $value = $epochdatehfc->month;
  &send;

  $name = "hfc$per\_monthn";
  $value = $epochdatehfc->month_name;
  &send;

  $name = "hfc$per\_monthn_sh";
  $value = $epochdatehfc->month_abbr;
  &send;

  $name = "hfc$per\_year";
  $value = $epochdatehfc->year;
  &send;

  $name = "hfc$per\_hour";
  $value = $epochdatehfc->hour;
  &send;

  $name = "hfc$per\_min";
  $value = $epochdatehfc->minute;
  &send;

  $name = "hfc$per\_wday";
  $value = $epochdatehfc->day_name;
  &send;

  $name = "hfc$per\_wday_sh";
  $value = $epochdatehfc->day_abbr;
  &send;

  $name = "hfc$per\_tt";
  if (!$metric) {$value = $hfc_entry->{temperature}*1.8+32} else {$value = $hfc_entry->{temperature};}
  &send;

  $name = "hfc$per\_tt_fl";
  if (!$metric) {$value = $hfc_entry->{feelslike}*1.8+32} else {$value = $hfc_entry->{feelslike};}
  &send;

  $name = "hfc$per\_hi";
  if (!$metric) {$value = $hfc_entry->{heat_index}*1.8+32} else {$value = $hfc_entry->{heat_index};}
  &send;

  $name = "hfc$per\_hu";
  $value = $hfc_entry->{humidity};
  &send;

  $name = "hfc$per\_w_dirdes";
  $value = $hfc_entry->{wind_direction_desc};
  &send;

  $name = "hfc$per\_w_dir";
  $value = $hfc_entry->{wind_direction_deg};
  &send;

  $name = "hfc$per\_w_sp";
  if (!$metric) {$value = $hfc_entry->{wind_speed}*0.621} else {$value = $hfc_entry->{wind_speed};}
  &send;

  $name = "hfc$per\_w_ch";
  if (!$metric) {$value = $hfc_entry->{windchill}*1.8+32} else {$value = $hfc_entry->{windchill}};
  &send;

  $name = "hfc$per\_pr";
  $value = $hfc_entry->{pressure};
  &send;

  $name = "hfc$per\_dp";
  $value = $hfc_entry->{dewpoint};
  &send;

  $name = "hfc$per\_sky";
  $value = $hfc_entry->{sky_percent};
  &send;

  $name = "hfc$per\_sky\_des";
  $value = $hfc_entry->{sky_description};
  &send;

  $name = "hfc$per\_uvi";
  $value = $hfc_entry->{uv_index};
  &send;

  $name = "hfc$per\_prec";
  if (!$metric) {$value = $hfc_entry->{precip_mm}*0.0393700787} else {$value = $hfc_entry->{precip_mm};}
  &send;

  $name = "hfc$per\_snow";
  if (!$metric) {$value = $hfc_entry->{snow_cm}*0.393700787} else {$value = $hfc_entry->{snow_cm};}
  &send;

  $name = "hfc$per\_pop";
  $value = $hfc_entry->{precip_probability};
  &send;

  $name = "hfc$per\_we_code";
  $value = $hfc_entry->{weather_code};
  &send;

  $name = "hfc$per\_we_icon";
  $value = $hfc_entry->{weather_icon};
  &send;

  $name = "hfc$per\_we_des";
  $value = $hfc_entry->{weather_description};
  &send;

  $name = "hfc$per\_ozone";
  $value = _jval($hfc_entry->{ozone});
  &send;

  $name = "hfc$per\_sr";
  $value = $hfc_entry->{solar_radiation};
  &send;

  $name = "hfc$per\_vis";
  $value = $hfc_entry->{visibility};
  &send;

  $name = "hfc$per\_moon_p";
  $value = $hfc_entry->{moon_percent};
  &send;

  $name = "hfc$per\_moon_a";
  $value = $hfc_entry->{moon_age};
  &send;

  $name = "hfc$per\_moon_ph";
  $value = $hfc_entry->{moon_phase};
  $udp = 1; # Really send now in one run
  &send;
}

# Send raw hourly forecast data over MQTT
#$name = "hourly";
#$value = $data;
#&sendmqtt;

#
# Print out calculated Forecast values
#

# Prec within the next hours
my $tmpprec4 = 0;
my $tmpprec8 = 0;
my $tmpprec12 = 0;
my $tmpprec16 = 0;
my $tmpprec24 = 0;
my $tmpprec32 = 0;
my $tmpprec40 = 0;
my $tmpprec48 = 0;

# Snow within the next hours
my $tmpsnow4 = 0;
my $tmpsnow8 = 0;
my $tmpsnow12 = 0;
my $tmpsnow16 = 0;
my $tmpsnow24 = 0;
my $tmpsnow32 = 0;
my $tmpsnow40 = 0;
my $tmpsnow48 = 0;

# Solar Rad within the next hours
my $tmpsr4 = 0;
my $tmpsr8 = 0;
my $tmpsr12 = 0;
my $tmpsr16 = 0;
my $tmpsr24 = 0;
my $tmpsr32 = 0;
my $tmpsr40 = 0;
my $tmpsr48 = 0;

# Min Temp within the next hours
my $tmpttmin4 = 0;
my $tmpttmin8 = 0;
my $tmpttmin12 = 0;
my $tmpttmin16 = 0;
my $tmpttmin24 = 0;
my $tmpttmin32 = 0;
my $tmpttmin40 = 0;
my $tmpttmin48 = 0;

# Max Temp within the next hours
my $tmpttmax4 = 0;
my $tmpttmax8 = 0;
my $tmpttmax12 = 0;
my $tmpttmax16 = 0;
my $tmpttmax24 = 0;
my $tmpttmax32 = 0;
my $tmpttmax40 = 0;
my $tmpttmax48 = 0;

# Mean Temp within the next hours
my $tmpttmean4 = 0;
my $tmpttmean8 = 0;
my $tmpttmean12 = 0;
my $tmpttmean16 = 0;
my $tmpttmean24 = 0;
my $tmpttmean32 = 0;
my $tmpttmean40 = 0;
my $tmpttmean48 = 0;
my @tmpttmean4;
my @tmpttmean8;
my @tmpttmean12;
my @tmpttmean16;
my @tmpttmean24;
my @tmpttmean32;
my @tmpttmean40;
my @tmpttmean48;

# Min Pop within the next hours
my $tmppopmin4 = 0;
my $tmppopmin8 = 0;
my $tmppopmin12 = 0;
my $tmppopmin16 = 0;
my $tmppopmin24 = 0;
my $tmppopmin32 = 0;
my $tmppopmin40 = 0;
my $tmppopmin48 = 0;

# Max Pop within the next hours
my $tmppopmax4 = 0;
my $tmppopmax8 = 0;
my $tmppopmax12 = 0;
my $tmppopmax16 = 0;
my $tmppopmax24 = 0;
my $tmppopmax32 = 0;
my $tmppopmax40 = 0;
my $tmppopmax48 = 0;

foreach my $hfc_entry (@hfc) {

  # Default values for min/max (use period 1 as baseline)
  if ( $hfc_entry->{period} == 1 ) {
      $tmpttmax4 = $hfc_entry->{temperature};
      $tmpttmin4 = $hfc_entry->{temperature};
      $tmpttmax8 = $hfc_entry->{temperature};
      $tmpttmin8 = $hfc_entry->{temperature};
      $tmpttmax12 = $hfc_entry->{temperature};
      $tmpttmin12 = $hfc_entry->{temperature};
      $tmpttmax16 = $hfc_entry->{temperature};
      $tmpttmin16 = $hfc_entry->{temperature};
      $tmpttmax24 = $hfc_entry->{temperature};
      $tmpttmin24 = $hfc_entry->{temperature};
      $tmpttmax32 = $hfc_entry->{temperature};
      $tmpttmin32 = $hfc_entry->{temperature};
      $tmpttmax40 = $hfc_entry->{temperature};
      $tmpttmin40 = $hfc_entry->{temperature};
      $tmpttmax48 = $hfc_entry->{temperature};
      $tmpttmin48 = $hfc_entry->{temperature};

      $tmppopmax4 = $hfc_entry->{precip_probability};
      $tmppopmin4 = $hfc_entry->{precip_probability};
      $tmppopmax8 = $hfc_entry->{precip_probability};
      $tmppopmin8 = $hfc_entry->{precip_probability};
      $tmppopmax12 = $hfc_entry->{precip_probability};
      $tmppopmin12 = $hfc_entry->{precip_probability};
      $tmppopmax16 = $hfc_entry->{precip_probability};
      $tmppopmin16 = $hfc_entry->{precip_probability};
      $tmppopmax24 = $hfc_entry->{precip_probability};
      $tmppopmin24 = $hfc_entry->{precip_probability};
      $tmppopmax32 = $hfc_entry->{precip_probability};
      $tmppopmin32 = $hfc_entry->{precip_probability};
      $tmppopmax40 = $hfc_entry->{precip_probability};
      $tmppopmin40 = $hfc_entry->{precip_probability};
      $tmppopmax48 = $hfc_entry->{precip_probability};
      $tmppopmin48 = $hfc_entry->{precip_probability};
  }
  if ( $hfc_entry->{period} <= 4 ) {
    $tmpprec4 = $tmpprec4 + $hfc_entry->{precip_mm}
        if defined($hfc_entry->{precip_mm}) && $hfc_entry->{precip_mm} > 0;
    $tmpsnow4 = $tmpsnow4 + $hfc_entry->{snow_cm}
        if defined($hfc_entry->{snow_cm}) && $hfc_entry->{snow_cm} > 0;
    $tmpsr4 = $tmpsr4 + $hfc_entry->{solar_radiation}
        if defined($hfc_entry->{solar_radiation}) && $hfc_entry->{solar_radiation} > 0;
    if (defined($hfc_entry->{temperature})) {
        if ( $tmpttmin4 > $hfc_entry->{temperature} ) { $tmpttmin4 = $hfc_entry->{temperature}; }
        if ( $tmpttmax4 < $hfc_entry->{temperature} ) { $tmpttmax4 = $hfc_entry->{temperature}; }
    }
    if (defined($hfc_entry->{precip_probability})) {
        if ( $tmppopmin4 > $hfc_entry->{precip_probability} ) { $tmppopmin4 = $hfc_entry->{precip_probability}; }
        if ( $tmppopmax4 < $hfc_entry->{precip_probability} ) { $tmppopmax4 = $hfc_entry->{precip_probability}; }
    }
    push(@tmpttmean4, $hfc_entry->{temperature}) if defined($hfc_entry->{temperature});
  }
  if ( $hfc_entry->{period} <= 8 ) {
    $tmpprec8 = $tmpprec8 + $hfc_entry->{precip_mm}
        if defined($hfc_entry->{precip_mm}) && $hfc_entry->{precip_mm} > 0;
    $tmpsnow8 = $tmpsnow8 + $hfc_entry->{snow_cm}
        if defined($hfc_entry->{snow_cm}) && $hfc_entry->{snow_cm} > 0;
    $tmpsr8 = $tmpsr8 + $hfc_entry->{solar_radiation}
        if defined($hfc_entry->{solar_radiation}) && $hfc_entry->{solar_radiation} > 0;
    if (defined($hfc_entry->{temperature})) {
        if ( $tmpttmin8 > $hfc_entry->{temperature} ) { $tmpttmin8 = $hfc_entry->{temperature}; }
        if ( $tmpttmax8 < $hfc_entry->{temperature} ) { $tmpttmax8 = $hfc_entry->{temperature}; }
    }
    if (defined($hfc_entry->{precip_probability})) {
        if ( $tmppopmin8 > $hfc_entry->{precip_probability} ) { $tmppopmin8 = $hfc_entry->{precip_probability}; }
        if ( $tmppopmax8 < $hfc_entry->{precip_probability} ) { $tmppopmax8 = $hfc_entry->{precip_probability}; }
    }
    push(@tmpttmean8, $hfc_entry->{temperature}) if defined($hfc_entry->{temperature});
  }
  if ( $hfc_entry->{period} <= 12 ) {
    $tmpprec12 = $tmpprec12 + $hfc_entry->{precip_mm}
        if defined($hfc_entry->{precip_mm}) && $hfc_entry->{precip_mm} > 0;
    $tmpsnow12 = $tmpsnow12 + $hfc_entry->{snow_cm}
        if defined($hfc_entry->{snow_cm}) && $hfc_entry->{snow_cm} > 0;
    $tmpsr12 = $tmpsr12 + $hfc_entry->{solar_radiation}
        if defined($hfc_entry->{solar_radiation}) && $hfc_entry->{solar_radiation} > 0;
    if (defined($hfc_entry->{temperature})) {
        if ( $tmpttmin12 > $hfc_entry->{temperature} ) { $tmpttmin12 = $hfc_entry->{temperature}; }
        if ( $tmpttmax12 < $hfc_entry->{temperature} ) { $tmpttmax12 = $hfc_entry->{temperature}; }
    }
    if (defined($hfc_entry->{precip_probability})) {
        if ( $tmppopmin12 > $hfc_entry->{precip_probability} ) { $tmppopmin12 = $hfc_entry->{precip_probability}; }
        if ( $tmppopmax12 < $hfc_entry->{precip_probability} ) { $tmppopmax12 = $hfc_entry->{precip_probability}; }
    }
    push(@tmpttmean12, $hfc_entry->{temperature}) if defined($hfc_entry->{temperature});
  }
  if ( $hfc_entry->{period} <= 16 ) {
    $tmpprec16 = $tmpprec16 + $hfc_entry->{precip_mm}
        if defined($hfc_entry->{precip_mm}) && $hfc_entry->{precip_mm} > 0;
    $tmpsnow16 = $tmpsnow16 + $hfc_entry->{snow_cm}
        if defined($hfc_entry->{snow_cm}) && $hfc_entry->{snow_cm} > 0;
    $tmpsr16 = $tmpsr16 + $hfc_entry->{solar_radiation}
        if defined($hfc_entry->{solar_radiation}) && $hfc_entry->{solar_radiation} > 0;
    if (defined($hfc_entry->{temperature})) {
        if ( $tmpttmin16 > $hfc_entry->{temperature} ) { $tmpttmin16 = $hfc_entry->{temperature}; }
        if ( $tmpttmax16 < $hfc_entry->{temperature} ) { $tmpttmax16 = $hfc_entry->{temperature}; }
    }
    if (defined($hfc_entry->{precip_probability})) {
        if ( $tmppopmin16 > $hfc_entry->{precip_probability} ) { $tmppopmin16 = $hfc_entry->{precip_probability}; }
        if ( $tmppopmax16 < $hfc_entry->{precip_probability} ) { $tmppopmax16 = $hfc_entry->{precip_probability}; }
    }
    push(@tmpttmean16, $hfc_entry->{temperature}) if defined($hfc_entry->{temperature});
  }
  if ( $hfc_entry->{period} <= 24 ) {
    $tmpprec24 = $tmpprec24 + $hfc_entry->{precip_mm}
        if defined($hfc_entry->{precip_mm}) && $hfc_entry->{precip_mm} > 0;
    $tmpsnow24 = $tmpsnow24 + $hfc_entry->{snow_cm}
        if defined($hfc_entry->{snow_cm}) && $hfc_entry->{snow_cm} > 0;
    $tmpsr24 = $tmpsr24 + $hfc_entry->{solar_radiation}
        if defined($hfc_entry->{solar_radiation}) && $hfc_entry->{solar_radiation} > 0;
    if (defined($hfc_entry->{temperature})) {
        if ( $tmpttmin24 > $hfc_entry->{temperature} ) { $tmpttmin24 = $hfc_entry->{temperature}; }
        if ( $tmpttmax24 < $hfc_entry->{temperature} ) { $tmpttmax24 = $hfc_entry->{temperature}; }
    }
    if (defined($hfc_entry->{precip_probability})) {
        if ( $tmppopmin24 > $hfc_entry->{precip_probability} ) { $tmppopmin24 = $hfc_entry->{precip_probability}; }
        if ( $tmppopmax24 < $hfc_entry->{precip_probability} ) { $tmppopmax24 = $hfc_entry->{precip_probability}; }
    }
    push(@tmpttmean24, $hfc_entry->{temperature}) if defined($hfc_entry->{temperature});
  }
  if ( $hfc_entry->{period} <= 32 ) {
    $tmpprec32 = $tmpprec32 + $hfc_entry->{precip_mm}
        if defined($hfc_entry->{precip_mm}) && $hfc_entry->{precip_mm} > 0;
    $tmpsnow32 = $tmpsnow32 + $hfc_entry->{snow_cm}
        if defined($hfc_entry->{snow_cm}) && $hfc_entry->{snow_cm} > 0;
    $tmpsr32 = $tmpsr32 + $hfc_entry->{solar_radiation}
        if defined($hfc_entry->{solar_radiation}) && $hfc_entry->{solar_radiation} > 0;
    if (defined($hfc_entry->{temperature})) {
        if ( $tmpttmin32 > $hfc_entry->{temperature} ) { $tmpttmin32 = $hfc_entry->{temperature}; }
        if ( $tmpttmax32 < $hfc_entry->{temperature} ) { $tmpttmax32 = $hfc_entry->{temperature}; }
    }
    if (defined($hfc_entry->{precip_probability})) {
        if ( $tmppopmin32 > $hfc_entry->{precip_probability} ) { $tmppopmin32 = $hfc_entry->{precip_probability}; }
        if ( $tmppopmax32 < $hfc_entry->{precip_probability} ) { $tmppopmax32 = $hfc_entry->{precip_probability}; }
    }
    push(@tmpttmean32, $hfc_entry->{temperature}) if defined($hfc_entry->{temperature});
  }
  if ( $hfc_entry->{period} <= 40 ) {
    $tmpprec40 = $tmpprec40 + $hfc_entry->{precip_mm}
        if defined($hfc_entry->{precip_mm}) && $hfc_entry->{precip_mm} > 0;
    $tmpsnow40 = $tmpsnow40 + $hfc_entry->{snow_cm}
        if defined($hfc_entry->{snow_cm}) && $hfc_entry->{snow_cm} > 0;
    $tmpsr40 = $tmpsr40 + $hfc_entry->{solar_radiation}
        if defined($hfc_entry->{solar_radiation}) && $hfc_entry->{solar_radiation} > 0;
    if (defined($hfc_entry->{temperature})) {
        if ( $tmpttmin40 > $hfc_entry->{temperature} ) { $tmpttmin40 = $hfc_entry->{temperature}; }
        if ( $tmpttmax40 < $hfc_entry->{temperature} ) { $tmpttmax40 = $hfc_entry->{temperature}; }
    }
    if (defined($hfc_entry->{precip_probability})) {
        if ( $tmppopmin40 > $hfc_entry->{precip_probability} ) { $tmppopmin40 = $hfc_entry->{precip_probability}; }
        if ( $tmppopmax40 < $hfc_entry->{precip_probability} ) { $tmppopmax40 = $hfc_entry->{precip_probability}; }
    }
    push(@tmpttmean40, $hfc_entry->{temperature}) if defined($hfc_entry->{temperature});
  }
  if ( $hfc_entry->{period} <= 48 ) {
    $tmpprec48 = $tmpprec48 + $hfc_entry->{precip_mm}
        if defined($hfc_entry->{precip_mm}) && $hfc_entry->{precip_mm} > 0;
    $tmpsnow48 = $tmpsnow48 + $hfc_entry->{snow_cm}
        if defined($hfc_entry->{snow_cm}) && $hfc_entry->{snow_cm} > 0;
    $tmpsr48 = $tmpsr48 + $hfc_entry->{solar_radiation}
        if defined($hfc_entry->{solar_radiation}) && $hfc_entry->{solar_radiation} > 0;
    if (defined($hfc_entry->{temperature})) {
        if ( $tmpttmin48 > $hfc_entry->{temperature} ) { $tmpttmin48 = $hfc_entry->{temperature}; }
        if ( $tmpttmax48 < $hfc_entry->{temperature} ) { $tmpttmax48 = $hfc_entry->{temperature}; }
    }
    if (defined($hfc_entry->{precip_probability})) {
        if ( $tmppopmin48 > $hfc_entry->{precip_probability} ) { $tmppopmin48 = $hfc_entry->{precip_probability}; }
        if ( $tmppopmax48 < $hfc_entry->{precip_probability} ) { $tmppopmax48 = $hfc_entry->{precip_probability}; }
    }
    push(@tmpttmean48, $hfc_entry->{temperature}) if defined($hfc_entry->{temperature});
  }

}

# Calculate mean values from arrays
$tmpttmean4 = sprintf("%.1f",mean(@tmpttmean4));
$tmpttmean8 = sprintf("%.1f",mean(@tmpttmean8));
$tmpttmean12 = sprintf("%.1f",mean(@tmpttmean12));
$tmpttmean16 = sprintf("%.1f",mean(@tmpttmean16));
$tmpttmean24 = sprintf("%.1f",mean(@tmpttmean24));
$tmpttmean32 = sprintf("%.1f",mean(@tmpttmean32));
$tmpttmean40 = sprintf("%.1f",mean(@tmpttmean40));
$tmpttmean48 = sprintf("%.1f",mean(@tmpttmean48));

# Add calculated to send queue

# ttmax
$name = "calc+4\_ttmax";
$value = $tmpttmax4;
&send;
$name = "calc+8\_ttmax";
$value = $tmpttmax8;
&send;
$name = "calc+12\_ttmax";
$value = $tmpttmax12;
&send;
$name = "calc+16\_ttmax";
$value = $tmpttmax16;
&send;
$name = "calc+24\_ttmax";
$value = $tmpttmax24;
&send;
$name = "calc+32\_ttmax";
$value = $tmpttmax32;
&send;
$name = "calc+40\_ttmax";
$value = $tmpttmax40;
&send;
$name = "calc+48\_ttmax";
$value = $tmpttmax48;
&send;

# ttmin
$name = "calc+4\_ttmin";
$value = $tmpttmin4;
&send;
$name = "calc+8\_ttmin";
$value = $tmpttmin8;
&send;
$name = "calc+12\_ttmin";
$value = $tmpttmin12;
&send;
$name = "calc+16\_ttmin";
$value = $tmpttmin16;
&send;
$name = "calc+24\_ttmin";
$value = $tmpttmin24;
&send;
$name = "calc+32\_ttmin";
$value = $tmpttmin32;
&send;
$name = "calc+40\_ttmin";
$value = $tmpttmin40;
&send;
$name = "calc+48\_ttmin";
$value = $tmpttmin48;
&send;

# ttmean
$name = "calc+4\_ttmean";
$value = $tmpttmean4;
&send;
$name = "calc+8\_ttmean";
$value = $tmpttmean8;
&send;
$name = "calc+12\_ttmean";
$value = $tmpttmean12;
&send;
$name = "calc+16\_ttmean";
$value = $tmpttmean16;
&send;
$name = "calc+24\_ttmean";
$value = $tmpttmean24;
&send;
$name = "calc+32\_ttmean";
$value = $tmpttmean32;
&send;
$name = "calc+40\_ttmean";
$value = $tmpttmean40;
&send;
$name = "calc+48\_ttmean";
$value = $tmpttmean48;
&send;

# popmax
$name = "calc+4\_popmax";
$value = $tmppopmax4;
&send;
$name = "calc+8\_popmax";
$value = $tmppopmax8;
&send;
$name = "calc+12\_popmax";
$value = $tmppopmax12;
&send;
$name = "calc+16\_popmax";
$value = $tmppopmax16;
&send;
$name = "calc+24\_popmax";
$value = $tmppopmax24;
&send;
$name = "calc+32\_popmax";
$value = $tmppopmax32;
&send;
$name = "calc+40\_popmax";
$value = $tmppopmax40;
&send;
$name = "calc+48\_popmax";
$value = $tmppopmax48;
&send;

# popmin
$name = "calc+4\_popmin";
$value = $tmppopmin4;
&send;
$name = "calc+8\_popmin";
$value = $tmppopmin8;
&send;
$name = "calc+12\_popmin";
$value = $tmppopmin12;
&send;
$name = "calc+16\_popmin";
$value = $tmppopmin16;
&send;
$name = "calc+24\_popmin";
$value = $tmppopmin24;
&send;
$name = "calc+32\_popmin";
$value = $tmppopmin32;
&send;
$name = "calc+40\_popmin";
$value = $tmppopmin40;
&send;
$name = "calc+48\_popmin";
$value = $tmppopmin48;
&send;

# sr
$name = "calc+4\_sr";
$value = $tmpsr4;
&send;
$name = "calc+8\_sr";
$value = $tmpsr8;
&send;
$name = "calc+12\_sr";
$value = $tmpsr12;
&send;
$name = "calc+16\_sr";
$value = $tmpsr16;
&send;
$name = "calc+24\_sr";
$value = $tmpsr24;
&send;
$name = "calc+32\_sr";
$value = $tmpsr32;
&send;
$name = "calc+40\_sr";
$value = $tmpsr40;
&send;
$name = "calc+48\_sr";
$value = $tmpsr48;
&send;

# prec
$name = "calc+4\_prec";
$value = $tmpprec4;
&send;
$name = "calc+8\_prec";
$value = $tmpprec8;
&send;
$name = "calc+12\_prec";
$value = $tmpprec12;
&send;
$name = "calc+16\_prec";
$value = $tmpprec16;
&send;
$name = "calc+24\_prec";
$value = $tmpprec24;
&send;
$name = "calc+32\_prec";
$value = $tmpprec32;
&send;
$name = "calc+40\_prec";
$value = $tmpprec40;
&send;
$name = "calc+48\_prec";
$value = $tmpprec48;
&send;

# snow
$name = "calc+4\_snow";
$value = $tmpsnow4;
&send;
$name = "calc+8\_snow";
$value = $tmpsnow8;
&send;
$name = "calc+12\_snow";
$value = $tmpsnow12;
&send;
$name = "calc+16\_snow";
$value = $tmpsnow16;
&send;
$name = "calc+24\_snow";
$value = $tmpsnow24;
&send;
$name = "calc+32\_snow";
$value = $tmpsnow32;
&send;
$name = "calc+40\_snow";
$value = $tmpsnow40;
&send;
$name = "calc+48\_snow";
$value = $tmpsnow48;
$udp = 1; # Really send now in one run
&send;

# Close HTML database
open(F,">>$lbplogdir/weatherdata.html");
  flock(F,2);
  binmode F, ':encoding(UTF-8)';
  print F "</body>\n</html>";
  flock(F,8);
close(F);

#
# Create Webpages
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
  # Write cached weboage
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

our $per;

foreach my $dfc_entry (@dfc) {

  $per = $dfc_entry->{period} - 1;

  ${dfc.$per._per} = $dfc_entry->{period} - 1;
  ${dfc.$per._date} = $dfc_entry->{epoch};

  # Derive date components from epoch
  my $epochdatedfc_tpl = DateTime->from_epoch(epoch => $dfc_entry->{epoch});
  $epochdatedfc_tpl->add(seconds => $tzseconds);

  ${dfc.$per._day}        = $epochdatedfc_tpl->day;
  ${dfc.$per._month}      = $epochdatedfc_tpl->month;
  ${dfc.$per._monthn}     = $epochdatedfc_tpl->month_name;
  ${dfc.$per._monthn_sh}  = $epochdatedfc_tpl->month_abbr;
  ${dfc.$per._year}       = $epochdatedfc_tpl->year;
  ${dfc.$per._hour}       = $epochdatedfc_tpl->hour;
  ${dfc.$per._min}        = $epochdatedfc_tpl->minute;
  ${dfc.$per._wday}       = $epochdatedfc_tpl->day_name;
  ${dfc.$per._wday_sh}    = $epochdatedfc_tpl->day_abbr;
  ${dfc.$per._pop}        = $dfc_entry->{precip_probability};
  ${dfc.$per._w_dirdes_h} = $dfc_entry->{wind_dir_max_desc};
  ${dfc.$per._w_dir_h}    = $dfc_entry->{wind_dir_max_deg};
  ${dfc.$per._w_dirdes_a} = $dfc_entry->{wind_dir_avg_desc};
  ${dfc.$per._w_dir_a}    = $dfc_entry->{wind_dir_avg_deg};
  ${dfc.$per._hu_a}       = $dfc_entry->{humidity_avg};
  ${dfc.$per._hu_h}       = $dfc_entry->{humidity_max};
  ${dfc.$per._hu_l}       = $dfc_entry->{humidity_min};
  ${dfc.$per._we_icon}    = $dfc_entry->{weather_icon};
  ${dfc.$per._we_code}    = $dfc_entry->{weather_code};
  ${dfc.$per._we_des}     = $dfc_entry->{weather_description};
  if (!$metric) {
  ${dfc.$per._tt_h} = $dfc_entry->{high_temp}*1.8+32;
  ${dfc.$per._tt_l} = $dfc_entry->{low_temp}*1.8+32;
  ${dfc.$per._prec} = $dfc_entry->{precip_mm}*0.0393700787;
  ${dfc.$per._snow} = $dfc_entry->{snow_cm}*0.393700787;
  ${dfc.$per._w_sp_h} = $dfc_entry->{wind_speed_max}*0.621;
  ${dfc.$per._w_sp_a} = $dfc_entry->{wind_speed_avg}*0.621;
  ${dfc.$per._pr} = $dfc_entry->{pressure}*0.0295301;
  ${dfc.$per._dp} = $dfc_entry->{dewpoint}*1.8+32;
  } else {
  ${dfc.$per._tt_h} = $dfc_entry->{high_temp};
  ${dfc.$per._tt_l} = $dfc_entry->{low_temp};
  ${dfc.$per._prec} = $dfc_entry->{precip_mm};
  ${dfc.$per._snow} = $dfc_entry->{snow_cm};
  ${dfc.$per._w_sp_h} = $dfc_entry->{wind_speed_max};
  ${dfc.$per._w_sp_a} = $dfc_entry->{wind_speed_avg};
  ${dfc.$per._pr} = $dfc_entry->{pressure};
  ${dfc.$per._dp} = $dfc_entry->{dewpoint};
  }
  # Sunrise/sunset as "HH:MM" strings for template display
  ${dfc.$per._sun_r} = defined($dfc_entry->{sunrise}) ? $dfc_entry->{sunrise} : "";
  ${dfc.$per._sun_s} = defined($dfc_entry->{sunset})  ? $dfc_entry->{sunset}  : "";
  ${dfc.$per._ozone}   = _jval($dfc_entry->{ozone});
  ${dfc.$per._moon_p}  = $dfc_entry->{moon_percent};
  ${dfc.$per._moon_ph} = $dfc_entry->{moon_phase};
  ${dfc.$per._moon_a}  = $dfc_entry->{moon_age};
  ${dfc.$per._uvi}     = $dfc_entry->{uv_index};

}

if (!$newstyle) {
  # Write cached weboage
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

foreach my $hfc_entry (@hfc) {

  $per = $hfc_entry->{period};

  # Derive date/time components from epoch
  my $epochdatehfc_tpl = DateTime->from_epoch(epoch => $hfc_entry->{epoch});
  $epochdatehfc_tpl->add(seconds => $tzseconds);

  ${hfc.$per._per}        = $hfc_entry->{period};
  ${hfc.$per._date}       = $hfc_entry->{epoch};
  ${hfc.$per._day}        = $epochdatehfc_tpl->day;
  ${hfc.$per._month}      = $epochdatehfc_tpl->month;
  ${hfc.$per._monthn}     = $epochdatehfc_tpl->month_name;
  ${hfc.$per._monthn_sh}  = $epochdatehfc_tpl->month_abbr;
  ${hfc.$per._year}       = $epochdatehfc_tpl->year;
  ${hfc.$per._hour}       = $epochdatehfc_tpl->hour;
  ${hfc.$per._min}        = $epochdatehfc_tpl->minute;
  ${hfc.$per._wday}       = $epochdatehfc_tpl->day_name;
  ${hfc.$per._wday_sh}    = $epochdatehfc_tpl->day_abbr;
  ${hfc.$per._hu}         = $hfc_entry->{humidity};
  ${hfc.$per._w_dirdes}   = $hfc_entry->{wind_direction_desc};
  ${hfc.$per._w_dir}      = $hfc_entry->{wind_direction_deg};
  ${hfc.$per._pr}         = $hfc_entry->{pressure};
  ${hfc.$per._dp}         = $hfc_entry->{dewpoint};
  ${hfc.$per._sky}        = $hfc_entry->{sky_percent};
  ${hfc.$per._sky._des}   = $hfc_entry->{sky_description};
  ${hfc.$per._uvi}        = $hfc_entry->{uv_index};
  ${hfc.$per._pop}        = $hfc_entry->{precip_probability};
  ${hfc.$per._we_code}    = $hfc_entry->{weather_code};
  ${hfc.$per._we_icon}    = $hfc_entry->{weather_icon};
  ${hfc.$per._we_des}     = $hfc_entry->{weather_description};
  ${hfc.$per._ozone}      = _jval($hfc_entry->{ozone});
  ${hfc.$per._moon_p}     = $hfc_entry->{moon_percent};
  ${hfc.$per._moon_ph}    = $hfc_entry->{moon_phase};
  ${hfc.$per._moon_a}     = $hfc_entry->{moon_age};
  if (!$metric) {
  ${hfc.$per._tt}    = $hfc_entry->{temperature}*1.8+32;
  ${hfc.$per._tt_fl} = $hfc_entry->{feelslike}*1.8+32;
  ${hfc.$per._hi}    = $hfc_entry->{heat_index}*1.8+32;
  ${hfc.$per._w_sp}  = $hfc_entry->{wind_speed}*0.621;
  ${hfc.$per._w_ch}  = $hfc_entry->{windchill}*1.8+32;
  ${hfc.$per._prec}  = $hfc_entry->{precip_mm}*0.0393700787;
  ${hfc.$per._snow}  = $hfc_entry->{snow_cm}*0.393700787;
  } else {
  ${hfc.$per._tt}    = $hfc_entry->{temperature};
  ${hfc.$per._tt_fl} = $hfc_entry->{feelslike};
  ${hfc.$per._hi}    = $hfc_entry->{heat_index};
  ${hfc.$per._w_sp}  = $hfc_entry->{wind_speed};
  ${hfc.$per._w_ch}  = $hfc_entry->{windchill};
  ${hfc.$per._prec}  = $hfc_entry->{precip_mm};
  ${hfc.$per._snow}  = $hfc_entry->{snow_cm};
  }
  # Use night icons between sunset and sunrise
  if (${hfc.$per._hour} > $hour_sun_s || ${hfc.$per._hour} < $hour_sun_r) {
    ${hfc.$per._dayornight} = "n";
  } else {
    ${hfc.$per._dayornight} = "d";
  }

}

if (!$newstyle) {
  # Write cached weboage
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

our $cur_date     = $cur->{epoch};
our $cur_date_des_var = $cur->{datetime};
our $cur_date_tz_des_sh_var = $cur_date_tz_des_sh;
our $cur_date_tz_des_var = $cur->{timezone};
our $cur_date_tz_var = $cur_date_tz;

our $cur_day        = sprintf("%02d", $epochdate->day);
our $cur_month      = sprintf("%02d", $epochdate->month);
our $cur_hour       = sprintf("%02d", $epochdate->hour);
our $cur_min        = sprintf("%02d", $epochdate->minute);
our $cur_year       = $epochdate->year;
our $cur_loc_n      = $cur->{city};
our $cur_loc_c      = $cur->{country};
our $cur_loc_ccode  = $cur->{country_code};
our $cur_loc_lat    = $cur->{latitude};
our $cur_loc_long   = $cur->{longitude};
our $cur_loc_el     = $cur->{elevation};
our $cur_hu         = $cur->{humidity};
our $cur_w_dirdes   = $cur->{wind_direction_desc};
our $cur_w_dir      = $cur->{wind_direction_deg};
our $cur_sr         = $cur->{solar_radiation};
our $cur_uvi        = $cur->{uv_index};
our $cur_we_icon    = $cur->{weather_icon};
our $cur_we_code    = $cur->{weather_code};
our $cur_we_des     = $cur->{weather_description};
our $cur_moon_p     = $cur->{moon_percent};
our $cur_moon_a     = $cur->{moon_age};
our $cur_moon_ph    = $cur->{moon_phase};
our $cur_moon_h     = $cur->{moon_hemisphere};

if (!$metric) {
our $cur_tt         = $cur->{temperature}*1.8+32;
our $cur_tt_fl      = $cur->{feelslike}*1.8+32;
our $cur_w_sp       = $cur->{wind_speed}*0.621371192;
our $cur_w_gu       = $cur->{wind_gust}*0.621371192;
our $cur_w_ch       = $cur->{windchill}*1.8+32;
our $cur_pr         = $cur->{pressure}*0.0295301;
our $cur_dp         = $cur->{dewpoint}*1.8+32;
our $cur_vis        = $cur->{visibility}*0.621371192;
our $cur_hi         = $cur->{heat_index}*1.8+32;
our $cur_prec_today = $cur->{precip_today_mm}*0.0393700787;
our $cur_prec_1hr   = $cur->{precip_1hr_mm}*0.0393700787;
} else {
our $cur_tt         = $cur->{temperature};
our $cur_tt_fl      = $cur->{feelslike};
our $cur_w_sp       = $cur->{wind_speed};
our $cur_w_gu       = $cur->{wind_gust};
our $cur_w_ch       = $cur->{windchill};
our $cur_pr         = $cur->{pressure};
our $cur_dp         = $cur->{dewpoint};
our $cur_vis        = $cur->{visibility};
our $cur_hi         = $cur->{heat_index};
our $cur_prec_today = $cur->{precip_today_mm};
our $cur_prec_1hr   = $cur->{precip_1hr_mm};
}

# Sunrise/sunset as "HH:MM" strings for template display
our $cur_sun_r = defined($cur->{sunrise}) ? $cur->{sunrise} : "";
our $cur_sun_s = defined($cur->{sunset})  ? $cur->{sunset}  : "";
our $cur_ozone = _jval($cur->{ozone});
our $cur_sky   = _jval($cur->{cloud_cover});
our $cur_pop   = _jval($cur->{precip_probability});

# Use night icons between sunset and sunrise
# Extract hours from "HH:MM" sunrise/sunset strings
our $hour_sun_r = defined($sunr_h) ? $sunr_h : 0;
our $hour_sun_s = defined($suns_h) ? $suns_h : 24;
if ($cur_hour > $hour_sun_s || $cur_hour < $hour_sun_r) {
our  $cur_dayornight = "n";
} else {
our  $cur_dayornight = "d";
}

# Write cached weboage
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

#
# Create Cloud Weather Emu
#

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
  my $emu_tz_str = "UTC+0.00";
  if (defined($cur->{datetime}) && $cur->{datetime} =~ /([+-])(\d{2}):(\d{2})$/) {
    my $sign = $1;
    my $h    = int($2);
    my $m    = int($3);
    my $frac = $h + $m/60;
    $emu_tz_str = sprintf("UTC%s%.2f", $sign, $frac);
  }

  open(F,">$lbplogdir/index.txt");
    flock(F,2);
    print F "<mb_metadata>\n";
    print F "id;name;longitude;latitude;height (m.asl.);country;timezone;utc-timedifference;sunrise;sunset;\n";
    print F "local date;weekday;local time;temperature(C);feeledTemperature(C);windspeed(km/h);winddirection(degr);wind gust(km/h);low clouds(%);medium clouds(%);high clouds(%);precipitation(mm);probability of Precip(%);snowFraction;sea level pressure(hPa);relative humidity(%);CAPE;picto-code;radiation (W/m2);\n";
    print F "</mb_metadata>\n";
    print F "<valid_until>" . (($datenow->year)+5) . "-12-31</valid_until>\n";
    print F "<station>\n";
    print F ";" . $cur->{city} . ";" . $cur->{longitude} . ";" . $cur->{latitude} . ";" . $cur->{elevation} . ";" . $cur->{country} . ";" . $cur_date_tz_des_sh . ";" . $emu_tz_str;
    print F ";" . (defined($cur->{sunrise}) ? $cur->{sunrise} : "") . ";" . (defined($cur->{sunset}) ? $cur->{sunset} : "") . ";\n";
    print F $epochdate->dmy('.') . ";\t";
    print F $epochdate->day_abbr() . ";\t";
    printf ( F "%02d",$epochdate->hour() );
    print F ";\t";
    printf ( F "%1.2f", $cur->{temperature});
    print F ";\t";
    printf ( F "%1.1f", $cur->{feelslike});
    print F ";\t";
    printf ( F "%1d", $cur->{wind_speed});
    print F ";\t";
    printf ( F "%1d", $cur->{wind_direction_deg});
    print F ";\t";
    printf ( F "%1d", $cur->{wind_gust});
    print F ";\t";
    printf ( F "%1d", 0);
    print F ";\t";
    printf ( F "%1d", 0);
    print F ";\t";
    printf ( F "%1d", 0);
    print F ";\t";
    printf ( F "%1.1f", $cur->{precip_1hr_mm});
    print F ";\t";
    printf ( F "%1d", 0);
    print F ";\t";
    printf ( F "%1.1f", 0);
    print F ";\t";
    printf ( F "%1d", $cur->{pressure});
    print F ";\t";
    printf ( F "%1d", $cur->{humidity});
    print F ";\t";
    printf ( F "%1d", 0);
    print F ";\t";
    printf ( F "%1d", $lox_to_emu{int($cur->{weather_code})} // int($cur->{weather_code}));
    print F ";\t";
    printf ( F "%1.2f", $cur->{solar_radiation});
    print F ";\n";
  flock(F,8);
  close(F);

  #############################################
  # HOURLY FORECAST
  #############################################

  # Original file has 169 entrys, but always starts at 0:00 today or 12:00 yesterday. We alsways start with current data
  # 7 days * 24 hours = 168 datasets. It is unclear why the ms needs 7 days, because the emulator only displays 'today', 'tomorrow' and 'day after tomorrow'.

  $i = 0;
  my $hfcdate;

  open(F,">>$lbplogdir/index.txt");
  flock(F,2);

    foreach my $hfc_entry (@hfc) {

      # Construct hfcdate from epoch (per Research Pattern 7)
      $hfcdate = DateTime->from_epoch(epoch => $hfc_entry->{epoch});

      if ( DateTime->compare($epochdate, $hfcdate) == 1 ) { next; } # Exclude already past forecasts

      if ( $i >= 168 ) { last; } # Stop after 168 datasets

      # "local date;weekday;local time;temperature(C);feeledTemperature(C);windspeed(km/h);winddirection(degr);wind gust(km/h);low clouds(%);medium clouds(%);high clouds(%);precipitation(mm);probability of Precip(%);snowFraction;sea level pressure(hPa);relative humidity(%);CAPE;picto-code;radiation (W/m2);\n";
      print F $hfcdate->dmy('.') . ";\t";
      print F $hfcdate->day_abbr() . ";\t";
      printf ( F "%02d",$hfcdate->hour() );
      print F ";\t";
      printf ( F "%1.2f", $hfc_entry->{temperature});
      print F ";\t";
      printf ( F "%1.2f", $hfc_entry->{feelslike});
      print F ";\t";
      printf ( F "%1d", $hfc_entry->{wind_speed});
      print F ";\t";
      printf ( F "%1d", $hfc_entry->{wind_direction_deg});
      print F ";\t";
      printf ( F "%1d", $hfc_entry->{wind_speed});
      print F ";\t";
      printf ( F "%1d", $hfc_entry->{sky_percent});
      print F ";\t";
      printf ( F "%1d", $hfc_entry->{sky_percent});
      print F ";\t";
      printf ( F "%1d", $hfc_entry->{sky_percent});
      print F ";\t";
      printf ( F "%1.1f", $hfc_entry->{precip_mm});
      print F ";\t";
      printf ( F "%1d", $hfc_entry->{precip_probability});
      print F ";\t";
      printf ( F "%1.1f", 0);
      print F ";\t";
      printf ( F "%1d", $hfc_entry->{pressure});
      print F ";\t";
      printf ( F "%1d", $hfc_entry->{humidity});
      print F ";\t";
      printf ( F "%1d", 0);
      print F ";\t";
      printf ( F "%1d", $lox_to_emu{int($hfc_entry->{weather_code})} // int($hfc_entry->{weather_code}));
      print F ";\t";
      printf ( F "%1.2f", $hfc_entry->{solar_radiation});
      print F ";\n";

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

#
# Subroutines
#

sub send {

	# Create HTML webpage
	LOGINF "Adding value to weatherdata.html. Value: $name\@$value";
	open(F,">>$lbplogdir/weatherdata.html");
	flock(F,2);
		binmode F, ':encoding(UTF-8)';
		print F "$name\@" . Encode::decode("UTF-8", $value) . "<br>\n";
	flock(F,8);
	close(F);

	# Send MQTT data
	&sendmqtt();

	# Send UDP data
	if ($sendudp) {
		$tmpudp .= "$name\@$value; ";
		LOGINF "Adding value to UDP send queue. Value: $name\@$value";
		if ($udp == 1) {
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
			$udp = 0;
			$tmpudp = "";
		}
	}

	return();
}

sub sendmqtt {
	if ($sendmqtt) {
		eval {
			$name =~ s/\+/\_\_/g;
			LOGINF "Publishing " . $topic . "/" . $name . " " . $value;
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

sub mean
{
	#print Dumper @_;
	my (@data) = @_;
	my $sum;
	foreach (@data) {
		$sum += $_;
	}
	return ( $sum / @data );
}

END
{
	LOGEND;
}
