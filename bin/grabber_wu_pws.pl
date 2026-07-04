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
my $wuurl       = $pcfg->param("WUNDERGROUND.URL");
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

GetOptions ('verbose' => \$verbose,
            'interval=i' => \$refresh,
            'quiet'   => sub { $verbose = 0 });

if ($verbose) {
    $log->stdout(1);
    $log->loglevel(7);
}

LOGSTART "Weather4Lox $grabberLabel GRABBER process started";
LOGDEB "This is $0 Version $version";

# all values in current, daily, and hourly JSONs are in local time, so proper time zone information is important
my $timezone = _systemTimezone();
LOGDEB "Using timezone: $timezone, current local system time is " . _epochToIso(time(), $timezone);


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
    url => "$wuurl?apiKey=$apikey&stationId=$stationid&format=json&units=m&numericPrecision=decimal",
    # maskkeys => $maskkeys, # no masking needed here, because key was retrieved from public web page 
    # keyparam => 'apiKey',
    # apikey => $apikey,
    info => "for PWS station ID $stationid (current weather observation data)",
);

# read JSON file for current conditions get basic weather data
my $weatherKey = "current";
my $envelope = readJsonFile($lbplogdir, $weatherKey);
my $cur = $envelope->{$weatherKey} // {};

LOGDEB "Adding $grabberLabel data to $weatherKey weather data (existing values for same keys will be overwritten).";

my $currentEpoch = getValue($resCurrent, 'observations', 0, 'epoch');
my $dtCurrent = _epochToIso($currentEpoch, $timezone);
LOGINF "Observation time was $dtCurrent (epoch: $currentEpoch)";

# time
$cur->{time}{datetime}   = $dtCurrent;                                                             # cur_date     - is always in UNIX epoch time
$cur->{time}{epoch}      = $currentEpoch;                                                          # cur_date_des - is always in local time of Loxberry

# real (air) temperature, feels like, wind chill and heat index
my $temp = getFormatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'temp');
my $windChill = getFormatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'windChill');
my $heatIndex = getFormatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'heatIndex');

# Only set temperature if it is defined, otherwise we might overwrite existing valid data with undefined values
if (defined $temp) {
    LOGDEB "Adding/overwriting temperature/air with $temp degC.";
    $cur->{temperature}{air} = $temp;                                                              # cur_tt        - hourly max temperature (°C)
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
        direction       => $windDir,                                                               # cur_w_dir     - wind direction (degree)
        cardinal        => getWindDirCardinal($windDir),                                           #               - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
        speed           => $windSpeed,                                                             # cur_w_sp      - wind speed (km/h)
    };
    # wind gust may not be provided at all times
    if (defined $windGust) {
        LOGDEB "Adding/overwriting wind/gust with $windGust km/h.";
        $cur->{wind}{gust} = $windGust;                                                            # cur_w_gu      - wind gust (km/h)
    }
}

# other weather data - only set if defined, otherwise we might overwrite existing valid data with undefined values
my $humidity = getFormatted('%.1f', $resCurrent, 'observations', 0, 'humidity');
if (defined $humidity) {
    LOGDEB "Adding/overwriting humidity with $humidity %.";
    $cur->{humidity} = $humidity;                                                                  # cur_hu        - humidity
}
my $pressure = getFormatted('%.0f', $resCurrent, 'observations', 0, 'metric', 'pressure');
if (defined $pressure) {
    LOGDEB "Adding/overwriting pressure with $pressure hPa.";
    $cur->{pressure} = $pressure;                                                                  # cur_pr        - air pressure (hPa)
}
my $dewpoint = getFormatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'dewpt');
if (defined $dewpoint) {
    LOGDEB "Adding/overwriting dewpoint with $dewpoint degC.";
    $cur->{dewpoint} = $dewpoint;                                                                  # cur_dp        - dew point (°C)
}
my $uvIndex = getFormatted('%.1f', $resCurrent, 'observations', 0, 'uv');
if (defined $uvIndex) {
    LOGDEB "Adding/overwriting uvIndex with $uvIndex.";
    $cur->{uvIndex} = $uvIndex;                                                                    # cur_uvi       - UV index
}
my $visibility = getPercentage('%.0f', $resCurrent, 'observations', 0, 'visibility');
if (defined $visibility) {
    LOGDEB "Adding/overwriting visibility with $visibility.";
    $cur->{visibility} = $visibility;                                                              # cur_vis       - visibility (m/km as needed)
}
my $solarRadiation = getFormatted('%.1f', $resCurrent, 'observations', 0, 'solarRadiation');
if (defined $solarRadiation) {
    LOGDEB "Adding/overwriting solarRadiation with $solarRadiation W/m2.";
    $cur->{solarRadiation} = $solarRadiation;                                                      # cur_sr        - solar radiation (W/m²)
}

# precipitation - only set if defined, otherwise we might overwrite existing valid data with undefined values
my %precipitation = %{ $cur->{precipitation} // {} };

my $rainToday = getFormatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'precipTotal');
if (defined $rainToday) {
    LOGDEB "Adding/overwriting precipitation/rainToday with $rainToday mm.";
    $precipitation{rainToday} = $rainToday;                                                        # cur_prec_today, today precipitation in mm
}
# 1h precipitation amount in mm may not be provided at all times, using precipRate (actual rate of precipitation in mm/h) instead
my $rain1hr = getFormatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'precipRate');
if (defined $rain1hr) {
    LOGDEB "Adding/overwriting precipitation/rain1hr with $rain1hr mm.";
    $precipitation{rain1hr} = $rain1hr;                                                            # cur_prec_1hr, 1h precipitation in mm
}

$cur->{precipitation} = \%precipitation;

# Add station information and metadata
my $stationID = getValue($resCurrent, 'observations', 0, 'stationID');                             # station ID from WU data, e.g. ISCHLESW69
my $obsTimeLocal = getValue($resCurrent, 'observations', 0, 'obsTimeLocal');                       # observation time in local time, e.g. 2026-03-16 00:44:29

my $generatedAt = _epochToIso(time(), $timezone);
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

# Exit
exit;

END
{
    LOGEND;
}