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
use LWP::UserAgent;
use JSON::PP;
use File::Copy;
use Getopt::Long;
use DateTime;
use POSIX qw(floor);
use utf8;
use Encode qw(encode_utf8);

require "$lbpbindir/grabber_utils.pl";

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

my $pcfg   = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $lat    = $pcfg->param("OPENMETEOAIRQUALITY.COORDLAT");
my $lon    = $pcfg->param("OPENMETEOAIRQUALITY.COORDLONG");

# Determine system timezone (Debian / DietPi)
my $timezone = $ENV{TZ} // '';

if (!$timezone) {
    if (open my $tzfh, '<:encoding(UTF-8)', '/etc/timezone') {
        $timezone = <$tzfh>;
        chomp $timezone if defined $timezone;
        close $tzfh;
    }
}

# Validate that zoneinfo exists (avoid invalid names)
if (!$timezone || !-f "/usr/share/zoneinfo/$timezone") {
    # Fallback to UTC if not found
    $timezone = 'UTC';
}

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
        . "&forecast_days=5&timezone=$timezone";

my $resOM = apiCall(
	url      => $url,
	maskKeys => 0,
	info     => "air quality and pollen data for lat=$lat lon=$lon and timezone=$timezone",
);

##########################################################################
# Process pollen data
##########################################################################

# Pollen level thresholds (grains/m³) -> level 0-4
# Returns level 0-4 for a given concentration value
sub pollenLevel {
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
my $times = $resOM->{hourly}{time}          // [];
my %hourly_pollen = (
	alder   => $resOM->{hourly}{alder_pollen}   // [],
	birch   => $resOM->{hourly}{birch_pollen}   // [],
	grass   => $resOM->{hourly}{grass_pollen}   // [],
	mugwort => $resOM->{hourly}{mugwort_pollen} // [],
	olive   => $resOM->{hourly}{olive_pollen}   // [],
	ragweed => $resOM->{hourly}{ragweed_pollen} // [],
);

# Determine today and tomorrow date strings from the first timestamp
my ( $todayDate, $tomorrowDate );
if ( @$times ) {
	# timestamps are like "2026-03-01T00:00"
	$todayDate    = substr($times->[0], 0, 10);
	# compute tomorrow
	my ($y, $m, $d) = split(/-/, $todayDate);
	# Simple date increment
	my @daysInMonth = (0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
	# leap year check
	$daysInMonth[2] = 29 if ($y % 4 == 0 && ($y % 100 != 0 || $y % 400 == 0));
	$d++;
	if ($d > $daysInMonth[$m]) {
		$d = 1;
		$m++;
		if ($m > 12) { $m = 1; $y++; }
	}
	$tomorrowDate = sprintf("%04d-%02d-%02d", $y, $m, $d);
}

LOGINF "Today: $todayDate, Tomorrow: $tomorrowDate";

# For each pollen type compute todayAvg, todayMax, tomorrowAvg, tomorrowMax
my %pollenResult;
my @pollenTypes = qw(alder birch grass mugwort olive ragweed);

for my $ptype (@pollenTypes) {
	my @todayLevels    = ();
	my @tomorrowLevels = ();

	for my $i (0 .. $#$times) {
		my $ts    = $times->[$i];
		my $date  = substr($ts, 0, 10);
		my $raw   = $hourly_pollen{$ptype}[$i];
		my $level = pollenLevel($ptype, $raw);

		if ($date eq $todayDate) {
			push @todayLevels, $level;
		} elsif ($date eq $tomorrowDate) {
			push @tomorrowLevels, $level;
		}
	}

	my $todayAvg    = 0;
	my $todayMax    = 0;
	my $tomorrowAvg = 0;
	my $tomorrowMax = 0;

	if (@todayLevels) {
		my $sum = 0;
		for my $l (@todayLevels) { $sum += $l; $todayMax = $l if $l > $todayMax; }
		$todayAvg = int($sum / scalar(@todayLevels) + 0.5);
	}
	if (@tomorrowLevels) {
		my $sum = 0;
		for my $l (@tomorrowLevels) { $sum += $l; $tomorrowMax = $l if $l > $tomorrowMax; }
		$tomorrowAvg = int($sum / scalar(@tomorrowLevels) + 0.5);
	}

	$pollenResult{$ptype} = {
		todayAvg    => $todayAvg,
		todayMax    => $todayMax,
		tomorrowAvg => $tomorrowAvg,
		tomorrowMax => $tomorrowMax,
	};

	LOGDEB "Pollen $ptype: todayAvg=$todayAvg todayMax=$todayMax tomorrowAvg=$tomorrowAvg tomorrowMax=$tomorrowMax";
}

# Overall today and tomorrow (max of all todayMax / tomorrowMax)
my $overallToday    = 0;
my $overallTomorrow = 0;
for my $ptype (@pollenTypes) {
	$overallToday    = $pollenResult{$ptype}{todayMax}    if $pollenResult{$ptype}{todayMax}    > $overallToday;
	$overallTomorrow = $pollenResult{$ptype}{tomorrowMax} if $pollenResult{$ptype}{tomorrowMax} > $overallTomorrow;
}

##########################################################################
# Current AQI values
##########################################################################

my $europeanAqi  = $resOM->{current}{european_aqi} // 0;
my $usAqi        = $resOM->{current}{us_aqi}       // 0;
my $pm10         = $resOM->{current}{pm10}         // 0;
my $pm2_5        = $resOM->{current}{pm2_5}        // 0;

LOGINF "Current AQI: european=$europeanAqi us=$usAqi pm10=$pm10 pm2_5=$pm2_5";

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
		europeanAqi => $europeanAqi + 0,
		usAqi       => $usAqi + 0,
		pm10        => $pm10 + 0,
		pm2_5       => $pm2_5 + 0,
	},
	pollen           => \%pollenResult,
	overallToday     => $overallToday,
	overallTomorrow  => $overallTomorrow,
);

my $jsonObj  = JSON->new->pretty->canonical;
my $jsonText = $jsonObj->encode(\%result);

# Write atomically: write to .tmp, then rename
my $outfile = "$lbplogdir/airquality_pollen.json";
my $tmpfile = "$outfile.tmp";

open(my $fh, '>', $tmpfile) or do {
	LOGCRIT "Cannot write to $tmpfile: $!";
	exit 1;
};
print $fh $jsonText;
close($fh);

File::Copy::move($tmpfile, $outfile) or do {
	LOGCRIT "Cannot rename $tmpfile to $outfile: $!";
	exit 1;
};

# Legacy: keep airquality_pollen.json for backward compatibility
LOGOK "Air quality and pollen data written to $outfile";

# AQ/pollen data stays exclusively in airquality_pollen.json (written above).
# No merge into current.json — pollen data is separate by design.

exit;

END
{
	LOGOK "Done";
	LOGEND;
}
