#!/usr/bin/perl

# Grabber for overwriting data by WeatherUnderground data

# Copyright 2016-2023 Michael Schlenstedt, michael@loxberry.de
#                     Christian Fenzl, christian@loxberry.de
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
use utf8;
use Encode qw(encode_utf8);
use Getopt::Long;
use Time::Piece;
#use Data::Dumper;

require "$lbpbindir/grabber_utils.pl";

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

# params from config
my $pcfg        = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $wuurl       = "https://api.weather.com/v2/pws/observations";
my $stationid   = $pcfg->param("WUNDERGROUND.STATIONID");

# names for JSON 
my $grabberFile     = basename(__FILE__);
my $grabberLabel    = "Weather Underground PWS";
my $grabberKey      = "wunderground";          # name in JSONs
my $refresh         = 60;

# Get the public API key from the WU website
# curl -Ss https://www.wunderground.com/dashboard/pws/ISACHSEN347 | grep apiKey | sed -r 's/.*apiKey=([0-9a-z]*)\&.*/\1/g'
# $content = qx(curl -Ss https://www.wunderground.com/dashboard/pws/ISACHSEN347 | grep apiKey);
my $urlGetKeyRaw = "https://www.wunderground.com/dashboard/pws/$stationid";

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
    package => 'weather4lox',
    name => "$grabberLabel",
    logdir => "$lbplogdir",
);

# Commandline options
my $verbose = '';
my $history = '';

GetOptions ('verbose' => \$verbose,
            'history'  => \$history,
            'interval=i' => \$refresh,
            'quiet'   => sub { $verbose = 0 });

if ($verbose) {
    $log->stdout(1);
    $log->loglevel(7);
}

LOGSTART "Weather4Lox $grabberLabel GRABBER process started";
LOGDEB "This is $0 Version $version";

my $timezone = _systemTimezone();
LOGDEB "Using timezone: $timezone, current local system time is " . localtime->datetime;

# see https://developer.weather.com/docs/openapi/pws-observations-current-conditions-2-0/get-v2-pws-observations-current-by-stationid
my $apikey = apiCall(
    url => "$urlGetKeyRaw",
    # maskkeys => $maskkeys,    # no masking needed here as there are no secret API keys
    # keyparam => 'appid',
    # apikey => $apikey, 
    info => "for PWS station ID $stationid (getting API key only)",
    match => qr/.*apiKey=([0-9a-z]*)\&.*/s,
);

# Get data from Wunderground Server (API request) for current conditions
my $resCurrent = apiCall(
    url => "$wuurl/current?apiKey=$apikey&stationId=$stationid&format=json&units=m&numericPrecision=decimal",
    # maskkeys => $maskkeys, # no masking needed here, because key was retrieved from public web page 
    # keyparam => 'apiKey',
    # apikey => $apikey,
    info => "for PWS station ID $stationid (current weather data)",
);

# read JSON file for current conditions get basic weather data
my $weatherKey = "current";
my $envelope = readJsonFile($lbplogdir, $weatherKey);
my $cur = $envelope->{$weatherKey} // {};

LOGINF "Adding $grabberLabel data to $weatherKey weather data (existing values for same keys will be overwritten).";

# real (air) temperature, feels like, wind chill and heat index
my $temp = getFormatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'temp');
my $windChill = getFormatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'windChill');
my $heatIndex = getFormatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'heatIndex');

# Only set temperature if it is defined, otherwise we might overwrite existing valid data with undefined values
if (defined $temp) {
    LOGDEB "Adding/overwriting temperature/air with $temp degC.";
    $cur->{temperature}{air} = $temp;                                                                    # cur_tt        - hourly max temperature (°C)
}
# Windchill is only relevant if it differs significantly from the actual temperature
if (defined $windChill && defined $temp && abs($windChill - $temp) > 0.1 || !defined $cur->{temperature}{windChill}) {
    LOGDEB "Adding/overwriting temperature/windChill with $windChill degC.";
    $cur->{temperature}{windChill} = $windChill;                                                   # cur_w_ch      - min feels-like temperature, same as cur_w_ch  - wind chill (feel)
}
# Heat index is only relevant if it differs significantly from the actual temperature
if (defined $heatIndex && defined $temp && abs($heatIndex - $temp) > 0.1 || !defined $cur->{temperature}{heatIndex}) {
    LOGDEB "Adding/overwriting temperature/heatIndex with $heatIndex degC.";
    $cur->{temperature}{heatIndex} = $heatIndex;                                                   # cur_hi        - heat index (°C)
}

# wind data
my $windDir = getFormatted('%.0f', $resCurrent, 'observations', 0, 'winddir');
my $windSpeed = getFormatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'windSpeed');
my $windGust = getFormatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'windGust');

# Only set wind data if all values are defined, otherwise we might overwrite existing valid data with undefined values
if ( (defined $windDir && defined $windSpeed)) {
    LOGDEB "Adding/overwriting wind/direction=$windDir, wind/speed=$windSpeed, wind/cardinal=" . getWindDirCardinal($windDir);
    $cur->{wind} = {
        direction       => $windDir,                                                                  # cur_w_dir     - wind direction (degree)
        cardinal        => getWindDirCardinal($windDir),                                              #               - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
        speed           => $windSpeed,                                                                # cur_w_sp      - wind speed (km/h)
    };
    # wind gust may not be provided at all times
    if (defined $windGust) {
        LOGDEB "Adding/overwriting wind/gust with $windGust km/h.";
        $cur->{wind}{gust} = $windGust;                                                                # cur_w_gu      - wind gust (km/h)
    }
}

# other weather data - only set if defined, otherwise we might overwrite existing valid data with undefined values
my $humidity = getFormatted('%.1f', $resCurrent, 'observations', 0, 'humidity');
if (defined $humidity) {
    LOGDEB "Adding/overwriting humidity with $humidity %.";
    $cur->{humidity} = $humidity;                                                                 # cur_hu        - humidity
}
my $pressure = getFormatted('%.0f', $resCurrent, 'observations', 0, 'metric', 'pressure');
if (defined $pressure) {
    LOGDEB "Adding/overwriting pressure with $pressure hPa.";
    $cur->{pressure} = $pressure;                                                                 # cur_pr        - air pressure (hPa)
}
my $dewpoint = getFormatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'dewpt');
if (defined $dewpoint) {
    LOGDEB "Adding/overwriting dewpoint with $dewpoint degC.";
    $cur->{dewpoint} = $dewpoint;                                                                 # cur_dp        - dew point (°C)
}
my $uvIndex = getFormatted('%.1f', $resCurrent, 'observations', 0, 'uv');
if (defined $uvIndex) {
    LOGDEB "Adding/overwriting uvIndex with $uvIndex.";
    $cur->{uvIndex} = $uvIndex;                                                                   # cur_uvi       - UV index
}
my $visibility = getPercentage('%.0f', $resCurrent, 'observations', 0, 'visibility');
if (defined $visibility) {
    LOGDEB "Adding/overwriting visibility with $visibility.";
    $cur->{visibility} = $visibility;                                                             # cur_vis       - visibility (m/km as needed)
}
my $solarRadiation = getFormatted('%.1f', $resCurrent, 'observations', 0, 'solarRadiation');
if (defined $solarRadiation) {
    LOGDEB "Adding/overwriting solarRadiation with $solarRadiation W/m2.";
    $cur->{solarRadiation} = $solarRadiation;                                                     # cur_sr        - solar radiation (W/m²)
}

# precipitation - only set if defined, otherwise we might overwrite existing valid data with undefined values
my %precipitation = %{ $cur->{precipitation} // {} };

# WU provides total precipitation for today in mm since midnight
my $rainToday = getFormatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'precipTotal');
if (defined $rainToday) {
    LOGDEB "Adding/overwriting precipitation/rainToday with $rainToday mm.";
    $precipitation{rainToday} = $rainToday;                                                    # cur_prec_today, today precipitation in mm
}

# according to WU documentation, precipRate is the current precipitation rate in mm/hr,
my $precipRate = getFormatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'precipRate');
if (defined $precipRate) {
    LOGDEB "Adding/overwriting precipitation/rate with $precipRate mm/hr.";
    $precipitation{rate} = $precipRate;                                                        # cur_prec_rate, precipitation in mm/hr
}

$cur->{precipitation} = \%precipitation;

# Add station information and metadata
my $stationID = getValue($resCurrent, 'observations', 0, 'stationID'); # station ID from WU data, e.g. ISCHLESW69
my $obsTimeLocal = getValue($resCurrent, 'observations', 0, 'obsTimeLocal'); # observation time in local time, e.g. 2026-03-16 00:44:29

my $generatedAt = localtime->datetime;
$envelope->{$grabberKey} = {
    filename        => "$lbplogdir/$weatherKey.json",
    generatedAt     => $generatedAt,
    observedAt      => $obsTimeLocal,
    grabberLabel    => $grabberLabel,
    grabberScript   => $grabberFile,
    stationID       => $stationID,
    schemaVersion   => "v1.0",
};
$envelope->{$weatherKey} = $cur;

if ($refresh < $envelope->{refresh}) {
    LOGINF "Reducing refresh interval for $weatherKey weather data from $envelope->{refresh} to $refresh minutes.";
    $envelope->{refresh} = $refresh;
}
$envelope->{generatedAt} = $generatedAt;

# Write JSON back to file
writeJsonFile($lbplogdir, $weatherKey, $envelope);

# Give OK status to client.
LOGOK "Current weather data is saved successfully.";

# Retrieves hourly weather observations for the past 7 days from a specific Personal Weather Station (PWS) using the station ID
# https://developer.weather.com/docs/openapi/pws-recent-history-7-day-hourly-history-2-0/get-v2-pws-observations-hourly-7day-by-stationid

# hourly weather observations data is only retrieved once per hour
if ($history) {

    # Get data from Wunderground Server (API request) for hourly observations
    my $resObservations = apiCall(
        url => "$wuurl/hourly/7day?apiKey=$apikey&stationId=$stationid&format=json&units=m&numericPrecision=decimal",
        # maskkeys => $maskkeys, # no masking needed here, because key was retrieved from public web page 
        # keyparam => 'apiKey',
        # apikey => $apikey,
        info => "for PWS station ID $stationid (hourly weather observations for past 7 days)",
    );

    # read JSON file for historical conditions get basic weather data
    my $weatherKey = "hourlyobservations";
    my $envelope = readJsonFile($lbplogdir, $weatherKey);
    my $hObs = $envelope->{$weatherKey} // {};
    
    my @hourlyData;
    # For observations, we use the same structure as for hourly forecast, but with different meaning of the hour index:
    # hour 1 is the first completed hour, hour 2 is the hour before, etc.
    # 0 is current hour which is not completed yet, 1 for first completed hour, 2 for hour before, etc. 
    my $hour = 0;

    LOGINF "Adding $grabberLabel data to $weatherKey weather data (existing values for same keys will be overwritten).";

    for my $resHour ( reverse @{$resObservations->{observations}} ) {

        my $hObsHour = $hObs->[$hour];

        # Get observation time and convert to local time zone
        my $obsEpoch = getValue($resHour, 'epoch'); # observation time in epoch seconds

        # time
        if (defined $obsEpoch && defined $hObsHour->{time}{epoch} && abs($obsEpoch - $hObsHour->{time}{epoch}) > 3600) {
            LOGDEB "Observation time for hour $hour (hob${hour}_...) is more than 1 hour away from existing data. Updating time from " . $hObsHour->{time}{datetime} . 
                   " to " . _epochToIso($obsEpoch, $timezone) . " (epoch: $obsEpoch).";
        } elsif (defined $obsEpoch && !defined $hObsHour->{time}{epoch}) {
            LOGDEB "Setting observation time for hour $hour (hob${hour}_...) to " . _epochToIso($obsEpoch, $timezone) . " (epoch: $obsEpoch) as it was not set before.";
        }
         elsif (defined $obsEpoch) {
            LOGDEB "Observation time for hour $hour (hob${hour}_...) is within 1 hour of existing data. Keeping existing time " . $hObsHour->{time}{datetime} . 
                   " (epoch: " . $hObsHour->{time}{epoch} . ") and not updating to " . _epochToIso($obsEpoch, $timezone) . " (epoch: $obsEpoch).";
        }
         else {
            LOGDEB "Observation time for hour $hour (hob${hour}_...) is not defined in the new data. Keeping existing time " . ($hObsHour->{time}{datetime} // "undefined") . 
                   " (epoch: " . ($hObsHour->{time}{epoch} // "undefined") . ") and not updating.";
        }
        $hObsHour->{time}{datetime} = _epochToIso($obsEpoch, $timezone);
        $hObsHour->{time}{epoch}    = $obsEpoch;

        # temperature - real (air) temperature, wind chill and heat index
        my $temp       = getFormatted('%.1f', $resHour, 'metric', 'tempAvg');                              # hob<X>_tt        - hourly average temperature (°C)
        my $windChill = getFormatted('%.1f', $resHour, 'metric', 'windchillAvg');                          # hob<X>_tt_fl     - average feels-like temperature
        my $heatIndex = getFormatted('%.1f', $resHour, 'metric', 'heatindexAvg');                          # hob<X>_tt_fl     - average feels-like temperature

        # Only set temperature if it is defined, otherwise we might overwrite existing valid data with undefined values
        if (defined $temp) {
            $hObsHour->{temperature}{air} = $temp;                                                             # hob<X>_tt        - hourly average temperature (°C)
        }
        # Windchill is only relevant if it differs significantly from the actual temperature
        if (defined $windChill && defined $temp && abs($windChill - $temp) > 0.1 || !defined $hObsHour->{temperature}{windChill}) {
            $hObsHour->{temperature}{windChill} = $windChill;                                                  # hob<X>_tt_fl     - average feels-like temperature
        }
        # Heat index is only relevant if it differs significantly from the actual temperature
        if (defined $heatIndex && defined $temp && abs($heatIndex - $temp) > 0.1 || !defined $hObsHour->{temperature}{heatIndex}) {
            $hObsHour->{temperature}{heatIndex} = $heatIndex;                                                  # hob<X>_tt_fl     - average feels-like temperature
        }

        # wind data - average values for the hour
        my $windDirAvg = getFormatted('%.0f', $resHour, 'winddirAvg');
        my $windSpeedAvg = getFormatted('%.2f', $resHour, 'metric', 'windspeedAvg');
        my $windGustAvg = getFormatted('%.2f', $resHour, 'metric', 'windgustAvg');

        # Only set wind data if all values are defined, otherwise we might overwrite existing valid data with undefined values
        if ( (defined $windDirAvg && defined $windSpeedAvg)) {
            $hObsHour->{wind} = {
                direction       => $windDirAvg,                                                            # hob<X>_w_dir     - wind direction (degree)
                cardinal        => getWindDirCardinal($windDirAvg),                                        #                  - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
                speed           => $windSpeedAvg,                                                          # hob<X>_w_sp      - wind speed (km/h)
            };
            # wind gust may not be provided at all times
            if (defined $windGustAvg) {
                $hObsHour->{wind}{gust} = $windGustAvg;                                                        # hob<X>_w_gu      - wind gust (km/h)
            }
        }

        # other weather data - only set if defined, otherwise we might overwrite existing valid data with undefined values
        my $humidityAvg = getFormatted('%.1f', $resHour, 'observations', 'humidityAvg');
        if (defined $humidityAvg) {
            $hObsHour->{humidity} = $humidityAvg;                                                              # hob<X>_hu        - humidity
        }
        my $pressureMin = getFormatted('%.0f', $resHour, 'observations', 'metric', 'pressureMin');
        my $pressureMax = getFormatted('%.0f', $resHour, 'observations', 'metric', 'pressureMax');
        if (defined $pressureMax && defined $pressureMin) {
            $hObsHour->{pressure} = ($pressureMax + $pressureMin) / 2;                                         # hob<X>_pr        - air pressure (hPa)
        }
        my $dewpoint = getFormatted('%.1f', $resHour, 'observations', 'metric', 'dewptAvg');
        if (defined $dewpoint) {
            $hObsHour->{dewpoint} = $dewpoint;                                                                 # hob<X>_dp        - dew point (°C)
        }
        my $uvIndex = getFormatted('%.1f', $resHour, 'observations', 'uvHigh');
        if (defined $uvIndex) {
            $hObsHour->{uvIndex} = $uvIndex;                                                                   # hob<X>_uvi       - UV index
        }
        my $solarRadiation = getFormatted('%.1f', $resHour, 'observations', 'solarRadiationHigh');
        if (defined $solarRadiation) {
            $hObsHour->{solarRadiation} = $solarRadiation;                                                     # hob<X>_sr        - solar radiation (W/m²)
        }

        # precipitation - only set if defined, otherwise we might overwrite existing valid data with undefined values
        my %precipitation = %{ $hObsHour->{precipitation} // {} };

        # WU provides total precipitation for today in mm since midnight
        my $rainToday = getFormatted('%.2f', $resHour, 'observations', 'metric', 'precipTotal');
        if (defined $rainToday) {
            $precipitation{rainToday} = $rainToday;                                                    # hob<X>_prec_today, today precipitation in mm
        }

        # according to WU documentation, precipRate is the current precipitation rate in mm/hr,
        my $rain1hr = getFormatted('%.2f', $resHour, 'observations', 'metric', 'precipRate');
        if (defined $rain1hr) {
            $precipitation{rain1hr} = $rain1hr;                                                        # hob<X>_prec_1hr, 1h precipitation in mm
        }

        $hObsHour->{precipitation} = \%precipitation;
    
        $hour++;
    }

    # Add station information and metadata


    my $stationID = getValue($resObservations, 'observations', 0, 'stationID'); # station ID from WU data, e.g. ISCHLESW69
    my $obsTimeLocal = getValue($resObservations, 'observations', 0, 'obsTimeLocal'); # observation time in local time, e.g. 2026-03-16 00:44:29

    my $generatedAt = localtime->datetime;
    $envelope->{$grabberKey} = {
        filename        => "$lbplogdir/$weatherKey.json",
        generatedAt     => $generatedAt,
        observedAt      => $obsTimeLocal,
        grabberLabel    => $grabberLabel,
        grabberScript   => $grabberFile,
        stationID       => $stationID,
        schemaVersion   => "v1.0",
    };
    $envelope->{$weatherKey} = $hObs;
    $envelope->{generatedAt} = $generatedAt;

    # Write JSON back to file
    writeJsonFile($lbplogdir, $weatherKey, $envelope);

    # Give OK status to client.
    LOGOK "Historical weather data is saved successfully.";
}

# Exit
exit;

END
{
    LOGEND;
}