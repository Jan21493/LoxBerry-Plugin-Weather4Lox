#!/usr/bin/perl

# grabber for fetching air quality and pollen data from Open-Meteo Air Quality API
# fetches air quality and pollen forecast data from air-quality-api.open-meteo.com

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
# Modules
##########################################################################

use LoxBerry::System;
use LoxBerry::Log;
use JSON qw( decode_json encode_json );
use File::Copy;
use Getopt::Long;
use POSIX qw(floor);

require "$lbpbindir/grabber_utils.pl";

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

my $pcfg   = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $lat    = $pcfg->param("OPENMETEOAIRQUALITY.COORDLAT");
my $lon    = $pcfg->param("OPENMETEOAIRQUALITY.COORDLONG");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'grabber_openmeteo_airquality',
	logdir => "$lbplogdir",
);

# Commandline options
my $verbose = '';
GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 },
            );

if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGSTART "Weather4Lox GRABBER_OPENMETEO_AIRQUALITY process started";
LOGDEB "This is $0 Version $version";

# Validate coordinates
if ( !defined $lat || $lat eq '' || !defined $lon || $lon eq '' ) {
	LOGCRIT "No coordinates configured. Please set COORDLAT and COORDLONG in [OPENMETEOAIRQUALITY] section.";
	exit 1;
}

LOGINF "Using coordinates: lat=$lat, lon=$lon";

##########################################################################
# Fetch data from Open-Meteo Air Quality API
##########################################################################

my $url = "https://air-quality-api.open-meteo.com/v1/air-quality"
        . "?latitude=$lat&longitude=$lon"
        . "&current=european_aqi,us_aqi,pm10,pm2_5"
        . "&hourly=alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"
        . "&forecast_days=5&timezone=auto";

my $decoded_json = api_call(
	url      => $url,
	maskkeys => 0,
	info     => "air quality and pollen data",
);

##########################################################################
# Process pollen data
##########################################################################

# Pollen level thresholds (grains/m³) -> level 0-4
# Returns level 0-4 for a given concentration value
sub pollen_level {
	my ($type, $value) = @_;
	return 0 unless defined $value && $value ne '' && $value ne 'null';
	$value = 0 + $value; # numeric

	if ( $type eq 'alder' || $type eq 'birch' || $type eq 'olive' ) {
		return 0 if $value == 0;
		return 1 if $value <= 10;
		return 2 if $value <= 50;
		return 3 if $value <= 200;
		return 4;
	} elsif ( $type eq 'grass' || $type eq 'mugwort' || $type eq 'ragweed' ) {
		return 0 if $value == 0;
		return 1 if $value <= 5;
		return 2 if $value <= 20;
		return 3 if $value <= 50;
		return 4;
	}
	return 0;
}

# Get hourly timestamps and pollen values
my $times = $decoded_json->{hourly}{time}          // [];
my %hourly_pollen = (
	alder   => $decoded_json->{hourly}{alder_pollen}   // [],
	birch   => $decoded_json->{hourly}{birch_pollen}   // [],
	grass   => $decoded_json->{hourly}{grass_pollen}   // [],
	mugwort => $decoded_json->{hourly}{mugwort_pollen} // [],
	olive   => $decoded_json->{hourly}{olive_pollen}   // [],
	ragweed => $decoded_json->{hourly}{ragweed_pollen} // [],
);

# Determine today and tomorrow date strings from the first timestamp
my ( $today_date, $tomorrow_date );
if ( @$times ) {
	# timestamps are like "2026-03-01T00:00"
	$today_date    = substr($times->[0], 0, 10);
	# compute tomorrow
	my ($y, $m, $d) = split(/-/, $today_date);
	# Simple date increment
	my @days_in_month = (0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
	# leap year check
	$days_in_month[2] = 29 if ($y % 4 == 0 && ($y % 100 != 0 || $y % 400 == 0));
	$d++;
	if ($d > $days_in_month[$m]) {
		$d = 1;
		$m++;
		if ($m > 12) { $m = 1; $y++; }
	}
	$tomorrow_date = sprintf("%04d-%02d-%02d", $y, $m, $d);
}

LOGINF "Today: $today_date, Tomorrow: $tomorrow_date";

# For each pollen type compute today_avg, today_max, tomorrow_avg, tomorrow_max
my %pollen_result;
my @pollen_types = qw(alder birch grass mugwort olive ragweed);

for my $ptype (@pollen_types) {
	my @today_levels    = ();
	my @tomorrow_levels = ();

	for my $i (0 .. $#$times) {
		my $ts    = $times->[$i];
		my $date  = substr($ts, 0, 10);
		my $raw   = $hourly_pollen{$ptype}[$i];
		my $level = pollen_level($ptype, $raw);

		if ($date eq $today_date) {
			push @today_levels, $level;
		} elsif ($date eq $tomorrow_date) {
			push @tomorrow_levels, $level;
		}
	}

	my $today_avg    = 0;
	my $today_max    = 0;
	my $tomorrow_avg = 0;
	my $tomorrow_max = 0;

	if (@today_levels) {
		my $sum = 0;
		for my $l (@today_levels) { $sum += $l; $today_max = $l if $l > $today_max; }
		$today_avg = int($sum / scalar(@today_levels) + 0.5);
	}
	if (@tomorrow_levels) {
		my $sum = 0;
		for my $l (@tomorrow_levels) { $sum += $l; $tomorrow_max = $l if $l > $tomorrow_max; }
		$tomorrow_avg = int($sum / scalar(@tomorrow_levels) + 0.5);
	}

	$pollen_result{$ptype} = {
		today_avg    => $today_avg,
		today_max    => $today_max,
		tomorrow_avg => $tomorrow_avg,
		tomorrow_max => $tomorrow_max,
	};

	LOGDEB "Pollen $ptype: today_avg=$today_avg today_max=$today_max tomorrow_avg=$tomorrow_avg tomorrow_max=$tomorrow_max";
}

# Overall today and tomorrow (max of all today_max / tomorrow_max)
my $overall_today    = 0;
my $overall_tomorrow = 0;
for my $ptype (@pollen_types) {
	$overall_today    = $pollen_result{$ptype}{today_max}    if $pollen_result{$ptype}{today_max}    > $overall_today;
	$overall_tomorrow = $pollen_result{$ptype}{tomorrow_max} if $pollen_result{$ptype}{tomorrow_max} > $overall_tomorrow;
}

##########################################################################
# Current AQI values
##########################################################################

my $european_aqi = $decoded_json->{current}{european_aqi} // 0;
my $us_aqi       = $decoded_json->{current}{us_aqi}       // 0;
my $pm10         = $decoded_json->{current}{pm10}         // 0;
my $pm2_5        = $decoded_json->{current}{pm2_5}        // 0;

LOGINF "Current AQI: european=$european_aqi us=$us_aqi pm10=$pm10 pm2_5=$pm2_5";

##########################################################################
# Build result and write JSON file
##########################################################################

# Current timestamp
my @lt = localtime(time);
my $retrieved_at = sprintf("%04d-%02d-%02dT%02d:%02d:%02d",
	$lt[5]+1900, $lt[4]+1, $lt[3], $lt[2], $lt[1], $lt[0]);

my %result = (
	source       => "Open-Meteo Air Quality API",
	retrieved_at => $retrieved_at,
	coordinates  => { lat => $lat + 0, lon => $lon + 0 },
	current_aqi  => {
		european_aqi => $european_aqi + 0,
		us_aqi       => $us_aqi + 0,
		pm10         => $pm10 + 0,
		pm2_5        => $pm2_5 + 0,
	},
	pollen           => \%pollen_result,
	overall_today    => $overall_today,
	overall_tomorrow => $overall_tomorrow,
);

my $json_obj  = JSON->new->pretty->canonical;
my $json_text = $json_obj->encode(\%result);

# Write atomically: write to .tmp, then rename
my $outfile = "$lbplogdir/airquality_pollen.json";
my $tmpfile = "$outfile.tmp";

open(my $fh, '>', $tmpfile) or do {
	LOGCRIT "Cannot write to $tmpfile: $!";
	exit 1;
};
print $fh $json_text;
close($fh);

File::Copy::move($tmpfile, $outfile) or do {
	LOGCRIT "Cannot rename $tmpfile to $outfile: $!";
	exit 1;
};

LOGOK "Air quality and pollen data written to $outfile";

exit;

END
{
	LOGOK "Done";
	LOGEND;
}
