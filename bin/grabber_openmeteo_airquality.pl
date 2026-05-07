#!/usr/bin/perl

# grabber for fetching air quality and pollen data from Open-Meteo Air Quality API
# fetches air quality and pollen forecast data from air-quality-api.open-meteo.com
# merges AQ data into current.json and pollen data into all 3 JSON files

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
use File::Basename qw(basename);
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
my $lat    = $pcfg->param("SERVER.COORDLAT");
my $lon    = $pcfg->param("SERVER.COORDLONG");

# names for JSON
my $grabberFile     = basename(__FILE__);
my $grabberLabel    = "Open-Meteo Air Quality and Pollen";
my $grabberKey      = "openmeteo_airquality";              # name in JSONs
my $refresh         = $pcfg->param("SERVER.CRON") // 60;

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
	name => "$grabberLabel",
	logdir => "$lbplogdir",
);

# Commandline options
my $verbose = '';
GetOptions ('verbose' => \$verbose,
            'interval=i' => \$refresh,
            'quiet'   => sub { $verbose = 0 },
            );

if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGSTART "Weather4Lox $grabberLabel GRABBER process started";
LOGDEB "This is $0 Version $version";

# Validate coordinates
if ( !defined $lat || $lat eq '' || !defined $lon || $lon eq '' ) {
	LOGCRIT "No coordinates configured. Please set COORDLAT and COORDLONG in [SERVER] section.";
	exit 1;
}

LOGINF "Using coordinates: lat=$lat, lon=$lon";

##########################################################################
# Pollen sensitivity from config [POLLEN] section
##########################################################################

my %pollenSensitivity = (
    alder   => $pcfg->param("POLLEN.ALDER")   // 0,
    birch   => $pcfg->param("POLLEN.BIRCH")    // 0,
    grass   => $pcfg->param("POLLEN.GRASS")    // 0,
    mugwort => $pcfg->param("POLLEN.MUGWORT")  // 0,
    olive   => $pcfg->param("POLLEN.OLIVE")    // 0,
    ragweed => $pcfg->param("POLLEN.RAGWEED")  // 0,
);

##########################################################################
# Fetch data from Open-Meteo Air Quality API
##########################################################################

my @pollenTypes = qw(alder birch grass mugwort olive ragweed);
my $pollens = 'alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen';

my @airQualityTypes = qw(pm25 pm10 dust uvIndex uvIndexClearSky carbonMonoxide carbonDioxide ozone ammonia methane aerosolOpticalDepth sulphurDioxide nitrogenDioxide);
my $airQualityParams = 'pm2_5,pm10,dust,uv_index,uv_index_clear_sky,carbon_monoxide,carbon_dioxide,ozone,ammonia,methane,aerosol_optical_depth,sulphur_dioxide,nitrogen_dioxide';

my @europeanAqiTypes = qw(maximum pm25 pm10 ozone nitrogenDioxide sulphurDioxide);
my $europeanAqiParams = 'european_aqi,european_aqi_pm2_5,european_aqi_pm10,european_aqi_ozone,european_aqi_nitrogen_dioxide,european_aqi_sulphur_dioxide';

my $url = "https://air-quality-api.open-meteo.com/v1/air-quality"
        . "?latitude=$lat&longitude=$lon"
#        . "&current=$airQualityParams,$europeanAqiParams,$pollens"
        . "&hourly=$airQualityParams,$europeanAqiParams,$pollens"
        . "&forecast_days=5&timezone=$timezone";

my $resOM = apiCall(
	url      => $url,
	maskKeys => 0,
	info     => "air quality and pollen data for lat=$lat lon=$lon and timezone=$timezone",
);

##########################################################################
# Pollen helpers
##########################################################################

# Pollen level thresholds (grains/m3) -> level 0-7
sub pollenLevel {
    my ($type, $value) = @_;
    return 0 unless defined $value && $value > 0;
    $value = 0 + $value;

    if ($type eq 'alder' || $type eq 'birch' || $type eq 'olive') {
        return 1 if $value <= 5;
        return 2 if $value <= 15;
        return 3 if $value <= 30;
        return 4 if $value <= 60;
        return 5 if $value <= 100;
        return 6 if $value <= 200;
        return 7;
    } elsif ($type eq 'grass' || $type eq 'mugwort' || $type eq 'ragweed') {
        return 1 if $value <= 2;
        return 2 if $value <= 5;
        return 3 if $value <= 10;
        return 4 if $value <= 20;
        return 5 if $value <= 35;
        return 6 if $value <= 50;
        return 7;
    }
    return 0;
}

# Weighted personal mix from pollen levels and config sensitivities
sub calculatePersonalMix {
    my ($pollenLevels, $sensitivities) = @_;
    my $weightedSum = 0;
    my $weightedMax = 0;
    my $totalWeight = 0;
    my $weightedValue = 0;

    for my $type (keys %$pollenLevels) {
        my $configKey = lc($type);
        my $weight = $sensitivities->{$configKey} // 0;

        # square to give more weight to higher sensitivity values and higher pollen levels, and divide by max to normalize back to 0-7 range
        $weightedValue = ($pollenLevels->{$type} ** 2) * $weight / 49;

        $weightedSum += $weightedValue;
        $totalWeight += $weight;
        $weightedMax = $weightedSum if $weightedSum > $weightedMax;
    }
    return 0 unless $totalWeight > 0;
    return int($weightedMax / $totalWeight + 0.5);
}

##########################################################################
# Extract hourly pollen data from API response
##########################################################################

my $times = $resOM->{hourly}{time}          // [];

my %hourlyPollen = (
    alder   => $resOM->{hourly}{alder_pollen}   // [],
    birch   => $resOM->{hourly}{birch_pollen}    // [],
    grass   => $resOM->{hourly}{grass_pollen}    // [],
    mugwort => $resOM->{hourly}{mugwort_pollen}  // [],
    olive   => $resOM->{hourly}{olive_pollen}    // [],
    ragweed => $resOM->{hourly}{ragweed_pollen}  // [],
);

my %hourlyAirQuality = (
    pm25                => $resOM->{hourly}{pm2_5}  // [],
    pm10                => $resOM->{hourly}{pm10}   // [],
    dust                => $resOM->{hourly}{dust}   // [],
    uvIndex             => $resOM->{hourly}{uv_index} // [],
    uvIndexClearSky     => $resOM->{hourly}{uv_index_clear_sky} // [],
    carbonMonoxide      => $resOM->{hourly}{carbon_monoxide} // [],
    carbonDioxide       => $resOM->{hourly}{carbon_dioxide} // [],
    ozone               => $resOM->{hourly}{ozone} // [],
    ammonia             => $resOM->{hourly}{ammonia} // [],
    methane             => $resOM->{hourly}{methane} // [],
    aerosolOpticalDepth => $resOM->{hourly}{aerosol_optical_depth} // [],
    sulphurDioxide      => $resOM->{hourly}{sulphur_dioxide} // [],
    nitrogenDioxide     => $resOM->{hourly}{nitrogen_dioxide} // [],
);

my %hourlyEuropeanAqi = (
    maximum             => $resOM->{hourly}{european_aqi} // [],
    pm25                => $resOM->{hourly}{european_aqi_pm2_5}  // [],
    pm10                => $resOM->{hourly}{european_aqi_pm10}   // [],
    ozone               => $resOM->{hourly}{european_aqi_ozone} // [],
    nitrogenDioxide     => $resOM->{hourly}{european_aqi_nitrogen_dioxide} // [],
    sulphurDioxide      => $resOM->{hourly}{european_aqi_sulphur_dioxide} // [],
);

# Find the index matching the current hour in the hourly time array
sub findCurrentHourIndex {
    my ($timesRef) = @_;
    my @lt = localtime(time);
    my $nowHour = sprintf("%04d-%02d-%02dT%02d", $lt[5]+1900, $lt[4]+1, $lt[3], $lt[2]);
    for my $i (0 .. $#$timesRef) {
        return $i if substr($timesRef->[$i], 0, 13) eq $nowHour;
    }
    return 0;  # fallback to first entry
}

# Current timestamp for metadata
my @lt = localtime(time);
my $generatedAt = sprintf("%04d-%02d-%02dT%02d:%02d:%02d",
    $lt[5]+1900, $lt[4]+1, $lt[3], $lt[2], $lt[1], $lt[0]);

LOGDEB "Adding $grabberLabel data to current, daily and hourly weather data (existing values for same keys will be overwritten).";

##########################################################################
# Merge into current.json
##########################################################################

my $curEnvelope = readJsonFile($lbplogdir, "current");
if ($curEnvelope && $curEnvelope->{current}) {
    my $cur = $curEnvelope->{current};

    # Pollen for current hour
    my $nowIdx = findCurrentHourIndex($times);
    my %curPollen;
    for my $type (@pollenTypes) {
        $curPollen{$type} = pollenLevel($type, $hourlyPollen{$type}[$nowIdx]);
    }
    $curPollen{personalMix} = calculatePersonalMix(\%curPollen, \%pollenSensitivity);
    $cur->{pollen} = \%curPollen;

    # Air quality details for current hour
    $cur->{airQuality} = {};
    for my $type (@airQualityTypes) {
        if ($type eq 'uvIndex' || $type eq 'uvIndexClearSky') {
            next; # handled separately below
        }
        $cur->{airQuality}{$type} = ($hourlyAirQuality{$type}[$nowIdx] // 0) + 0;
    }

    my $uvIndex = ($hourlyAirQuality{uvIndex}[$nowIdx] // 0) + 0;
    if (defined $uvIndex) {
        $cur->{uvIndex} = $uvIndex;
    }
    my $uvIndexClearSky = ($hourlyAirQuality{uvIndexClearSky}[$nowIdx] // 0) + 0;
    if (defined $uvIndexClearSky) {
        $cur->{uvIndexClearSky} = $uvIndexClearSky;
    }

    # European AQI details for current hour
    $cur->{europeanAqi} = {};
    for my $type (@europeanAqiTypes) {
        $cur->{europeanAqi}{$type} = ($hourlyEuropeanAqi{$type}[$nowIdx] // 0) + 0;
    }

    # Grabber metadata
    $curEnvelope->{openmeteoAq} = {
        filename      => "$lbplogdir/current.json",
        generatedAt   => $generatedAt,
        grabberLabel  => "Open-Meteo Air Quality",
        grabberScript => "grabber_openmeteo_airquality.pl",
        schemaVersion => "v1.0",
    };

    if ($refresh < $curEnvelope->{refresh}) {
        LOGINF "Reducing refresh interval for air quality and pollen weather data from $curEnvelope->{refresh} to $refresh minutes.";
        $curEnvelope->{refresh} = $refresh;
    }
    $curEnvelope->{generatedAt} = $generatedAt;

    writeJsonFile($lbplogdir, "current", $curEnvelope);
    LOGOK "Merged air quality + pollen into current.json";
} else {
    LOGWARN "Could not read current.json or missing 'current' key - skipping AQ merge";
}

##########################################################################
# Merge pollen into hourlyforecast.json
##########################################################################

my $hfcEnvelope = readJsonFile($lbplogdir, "hourlyforecast");
if ($hfcEnvelope && $hfcEnvelope->{hourlyforecast}) {
    for my $h (@{$hfcEnvelope->{hourlyforecast}}) {
        my $hDatetime = $h->{time}{datetime} // '';
        # Match by truncating to hour: "2026-03-24T21"
        my $hHour = substr($hDatetime, 0, 13);
        my $matchIdx;
        for my $i (0 .. $#$times) {
            if (substr($times->[$i], 0, 13) eq $hHour) {
                $matchIdx = $i;
                last;
            }
        }
        # hourly data is not guaranteed to be present for all hours in hourlyforecast, so we check if we have a match before adding pollen and AQ data
        if (defined $matchIdx) {
            # Add pollen data for this hour
            my %hPollen;
            for my $type (@pollenTypes) {
                $hPollen{$type} = pollenLevel($type, $hourlyPollen{$type}[$matchIdx]);
            }
            $hPollen{personalMix} = calculatePersonalMix(\%hPollen, \%pollenSensitivity);
            $h->{pollen} = \%hPollen;

             # Air quality details for current hour
            $h->{airQuality} = {};
            for my $type (@airQualityTypes) {
                if ($type eq 'uvIndex' || $type eq 'uvIndexClearSky') {
                    next; # handled separately below
                }
                $h->{airQuality}{$type} = ($hourlyAirQuality{$type}[$matchIdx] // 0) + 0;
            }
            my $uvIndex = ($hourlyAirQuality{uvIndex}[$matchIdx] // 0) + 0;
            if (defined $uvIndex) {
                $h->{uvIndex} = $uvIndex;
            }
            my $uvIndexClearSky = ($hourlyAirQuality{uvIndexClearSky}[$matchIdx] // 0) + 0;
            if (defined $uvIndexClearSky) {
                $h->{uvIndexClearSky} = $uvIndexClearSky;
            }

            # European AQI details for current hour
            $h->{europeanAqi} = {};
            for my $type (@europeanAqiTypes) {
                $h->{europeanAqi}{$type} = ($hourlyEuropeanAqi{$type}[$matchIdx] // 0) + 0;
            }
        } else {
            $h->{pollen} = undef;
            $h->{airQuality} = undef; 
            $h->{europeanAqi} = undef;
        }
    }

    # Grabber metadata
    $hfcEnvelope->{openmeteoAq} = {
        filename      => "$lbplogdir/hourlyforecast.json",
        generatedAt   => $generatedAt,
        grabberLabel  => "Open-Meteo Air Quality",
        grabberScript => "grabber_openmeteo_airquality.pl",
        schemaVersion => "v1.0",
    };

    if ($refresh < $hfcEnvelope->{refresh}) {
        LOGINF "Reducing refresh interval for air quality and pollen weather data from $hfcEnvelope->{refresh} to $refresh minutes.";
        $hfcEnvelope->{refresh} = $refresh;
    }
    $hfcEnvelope->{generatedAt} = $generatedAt;

    writeJsonFile($lbplogdir, "hourlyforecast", $hfcEnvelope);
    LOGOK "Merged air quality + pollen into hourlyforecast.json";
} else {
    LOGWARN "Could not read hourlyforecast.json or missing 'hourlyforecast' key - skipping pollen merge";
}

##########################################################################
# Merge pollen into dailyforecast.json (aggregated from hourly)
##########################################################################

my $dfcEnvelope = readJsonFile($lbplogdir, "dailyforecast");
if ($dfcEnvelope && $dfcEnvelope->{dailyforecast}) {
    for my $d (@{$dfcEnvelope->{dailyforecast}}) {
        my $dayDate = substr($d->{time}{datetime} // '', 0, 10);
        next unless $dayDate;

        # Collect hourly pollen levels for this day
        my %dayLevels;
        for my $i (0 .. $#$times) {
            next unless substr($times->[$i], 0, 10) eq $dayDate;
            for my $type (@pollenTypes) {
                if (defined $hourlyPollen{$type}[$i]) {
                    push @{$dayLevels{$type}}, pollenLevel($type, $hourlyPollen{$type}[$i]);
                }
            }
        }

        if (%dayLevels) {
            my %dPollen;
            for my $type (@pollenTypes) {
                my @levels = @{$dayLevels{$type} // []};
                next unless @levels;
                LOGDEB "Day $dayDate - Pollen Type $type - Levels: @levels";
                my ($sum, $max) = (0, 0);
                for my $l (@levels) { $sum += $l; $max = $l if $l > $max; }
                $dPollen{avg}{$type} = int($sum / scalar(@levels) + 0.5);
                $dPollen{max}{$type} = $max;
            }
            # personalMix for avg and max separately
            my %avgLevels = map { $_ => $dPollen{avg}{$_} } grep { exists $dPollen{avg}{$_} } @pollenTypes;
            my %maxLevels = map { $_ => $dPollen{max}{$_} } grep { exists $dPollen{max}{$_} } @pollenTypes;
            $dPollen{avg}{personalMix} = calculatePersonalMix(\%avgLevels, \%pollenSensitivity);
            $dPollen{max}{personalMix} = calculatePersonalMix(\%maxLevels, \%pollenSensitivity);
            $d->{pollen} = \%dPollen;
        } else {
            $d->{pollen} = undef;
        }

        # Collect hourly air quality values for this day
        my %dayValues;
        for my $i (0 .. $#$times) {
            next unless substr($times->[$i], 0, 10) eq $dayDate;
            for my $type (@airQualityTypes) {
                if (defined $hourlyAirQuality{$type}[$i]) {
                    push @{$dayValues{$type}}, $hourlyAirQuality{$type}[$i];
                }
            }
        }

        if (%dayValues) {
            my %dAirQuality;
            for my $type (@airQualityTypes) {
                my @levels = @{$dayValues{$type} // []};
                next unless @levels;
                LOGDEB "Day $dayDate - Air Quality Type $type - Values: @levels";
                my ($sum, $max) = (0, 0);
                for my $l (@levels) { $sum += $l; $max = $l if $l > $max; }
                if ($type eq 'uvIndex' || $type eq 'uvIndexClearSky') {
                    # For UV index only the maximum is relevant
                    $d->{$type} = $max;
                } else {
                    $dAirQuality{avg}{$type} = int($sum / scalar(@levels) + 0.5);
                    $dAirQuality{max}{$type} = $max;
                }
            }
            $d->{airQuality} = \%dAirQuality;
        } else {
            $d->{airQuality} = undef;
        }

        # Collect hourly european air quality index (AQI) levels for this day
        for my $i (0 .. $#$times) {
            next unless substr($times->[$i], 0, 10) eq $dayDate;
            for my $type (@europeanAqiTypes) {
                if (defined $hourlyEuropeanAqi{$type}[$i]) {
                    push @{$dayLevels{$type}}, $hourlyEuropeanAqi{$type}[$i];
                }
            }
        }

        if (%dayLevels) {
            my %dEuropeanAqi;
            for my $type (@europeanAqiTypes) {
                my @levels = @{$dayLevels{$type} // []};
                next unless @levels;
                LOGDEB "Day $dayDate - European Air Quality Index Type $type - Levels: @levels";
                my ($sum, $max) = (0, 0);
                for my $l (@levels) { $sum += $l; $max = $l if $l > $max; }
                $dEuropeanAqi{avg}{$type} = int($sum / scalar(@levels) + 0.5);
                $dEuropeanAqi{max}{$type} = $max;
            }
            $d->{europeanAqi} = \%dEuropeanAqi;
        } else {
            $d->{europeanAqi} = undef;
        }
    }

    # Grabber metadata
    $dfcEnvelope->{openmeteoAq} = {
        filename      => "$lbplogdir/dailyforecast.json",
        generatedAt   => $generatedAt,
        grabberLabel  => "Open-Meteo Air Quality",
        grabberScript => "grabber_openmeteo_airquality.pl",
        schemaVersion => "v1.0",
    };

    if ($refresh < $dfcEnvelope->{refresh}) {
        LOGINF "Reducing refresh interval for air quality and pollen weather data from $dfcEnvelope->{refresh} to $refresh minutes.";
        $dfcEnvelope->{refresh} = $refresh;
    }
    $dfcEnvelope->{generatedAt} = $generatedAt;

    writeJsonFile($lbplogdir, "dailyforecast", $dfcEnvelope);
    LOGOK "Merged pollen into dailyforecast.json";
} else {
    LOGWARN "Could not read dailyforecast.json or missing 'dailyforecast' key - skipping pollen merge";
}

exit;

END
{
	LOGOK "Done";
	LOGEND;
}
