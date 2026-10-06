#!/usr/bin/perl

# Grabber for overwriting data by FOSHK Plugin data

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
use File::Basename qw(basename);
use utf8;
use Encode qw(encode_utf8);
use Getopt::Long;
use Time::Piece;

require "$lbpbindir/grabber_utils.pl";
require "$lbpbindir/weather4lox_log.pl";

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

# params from config
my $pcfg        = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $url         = "JSON?units=m&status&apiKey=MMM&stationId=FOSHKplugin";
my $server      = $pcfg->param("FOSHK.SERVER");
my $port        = $pcfg->param("FOSHK.PORT");

# names for JSON
my $grabberFile     = basename(__FILE__);
my $grabberLabel    = "FOSHK Weather Station NATIVE format";
my $grabberKey      = "foshk";              # name in JSONs
my $refresh         = 60;

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my %logOptions = (
	package => 'weather4lox',
	name => "$grabberLabel",
	logdir => "$lbplogdir",
);

# Commandline options
my $verbose = '';

GetOptions ('verbose' => \$verbose,
            'interval=i' => \$refresh,
            'quiet'   => sub { $verbose = 0 });

my $log = startWeatherLog(%logOptions, verbose => $verbose,
    message => "GRABBER process to retrieve weather data from the FOSHK Plugin Server in NATIVE format");
if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGOK "-------------------- START OF: $0, Version $version --------------------";

# all values in current, daily, and hourly JSONs are in local time, so proper time zone information is important
my $timezone = _systemTimezone();
LOGDEB "Using timezone: $timezone, current local system time is " . _epochToIso(time(), $timezone);

# Get data from FOSHK Plugin Server for current conditions
my $results = apiCall(
	url => "http://$server\:$port/$url",
	info => "from $grabberLabel (current weather in NATIVE format) at $server\:$port",
);

# Read existing current.json envelope
my $weatherKey = "current";
my $envelope = readJsonFile($lbplogdir, $weatherKey);
my $cur = $envelope->{$weatherKey} // {};

LOGDEB "Adding $grabberLabel data to $weatherKey weather data (existing values for same keys will be overwritten).";

my $currentEpoch = getValue($results, 'loxtime');                              # FOSHK plugin provides Loxone epoch time with this API call
if (!defined $currentEpoch) {
    LOGWARN "Could not get Loxone epoch time from FOSHK plugin results, using current system time instead.";
    $currentEpoch = time();
} else {
    $currentEpoch = lox2epoch($currentEpoch);
}
my $dtCurrent = _epochToIso($currentEpoch, $timezone);
LOGINF "Local observation time was " . $dtCurrent . " (epoch: $currentEpoch)";

# time
$cur->{time}{datetime}   = $dtCurrent;                                         # cur_date     - is always in UNIX epoch time
$cur->{time}{epoch}      = $currentEpoch;                                      # cur_date_des - is always in local time of Loxberry

# real (air) temperature, feels like / wind chill
my $temp      = getFormatted('%.1f', $results, 'tempc');
LOGDEB "Adding/overwriting temperature/air with $temp degrees Celsius.";
$cur->{temperature}{air}       = $temp;                                        # cur_tt  - air temperature (°C)

# feels like temperature
my $feelsLike = getFormatted('%.1f', $results, 'feelslikec');
if (defined $feelsLike && defined $temp && abs($feelsLike - $temp) > 0.1 || !defined $cur->{temperature}{feelsLike}) {
    $cur->{temperature}{feelsLike} = $feelsLike;                               # cur_tt_fl - feels like temperature (°C)
}

# Windchill is only relevant if it differs significantly from the actual temperature
my $windChill = getFormatted('%.1f', $results, 'windchillc');
if (defined $windChill && defined $temp && abs($windChill - $temp) > 0.1 || !defined $cur->{temperature}{windChill}) {
    LOGDEB "Adding/overwriting temperature/windChill with $windChill degrees Celsius.";
    $cur->{temperature}{windChill} = $windChill;                               # cur_w_ch / cur_tt_fl - wind chill (°C)
}

# Heat index is only relevant if it differs significantly from the actual temperature
my $heatIndex = getFormatted('%.1f', $results, 'heatindexc');
if (defined $heatIndex && defined $temp && abs($heatIndex - $temp) > 0.1 || !defined $cur->{temperature}{heatIndex}) {
    LOGDEB "Adding/overwriting temperature/heatIndex with $heatIndex degrees Celsius.";
    $cur->{temperature}{heatIndex} = $heatIndex;                               # cur_hi - heat index (°C)
}

# wind data
my $windDir = getFormatted('%.0f', $results, 'winddir');
my $windSpeed = getFormatted('%.2f', $results, 'windspeedkmh');
my $windGust = getFormatted('%.2f', $results, 'windgustkmh');
$cur->{wind} = {
    direction  => $windDir,                                                    # cur_w_dir    - wind direction (degree)
    cardinal   => getWindDirCardinal($windDir),                                # to calculate cur_w_dirdes - wind direction description from (N, NE, E, SE, S, SW, W, NW)
    speed      => $windSpeed,                                                  # cur_w_sp     - wind speed (km/h)
};
LOGDEB "Adding/overwriting wind/direction=$windDir, wind/speed=$windSpeed, wind/cardinal=" . getWindDirCardinal($windDir);

# wind gust may not be provided at all times
if (defined $windGust) {
    LOGDEB "Adding/overwriting wind/gust with $windGust km/h.";
    $cur->{wind}{gust} = $windGust;                                            # cur_w_gu     - wind gust (km/h)
}

# other weather data - only set if defined, otherwise we might overwrite existing valid data with undefined values
my $humidity = getFormatted('%.1f', $results, 'humidity');
if (defined $humidity) {
    LOGDEB "Adding/overwriting humidity with $humidity %.";
    $cur->{humidity} = $humidity;                                              # cur_hu  - humidity (%)
}

my $pressure = getFormatted('%.0f', $results, 'baromrelhpa');
if (defined $pressure) {
    LOGDEB "Adding/overwriting pressure with $pressure hPa.";
    $cur->{pressure} = $pressure;                                            # cur_pr  - air pressure (hPa)
}

my $dewpoint = getFormatted('%.1f', $results, 'dewptc');
if (defined $dewpoint) {
    LOGDEB "Adding/overwriting dewpoint with $dewpoint degrees Celsius.";
    $cur->{dewpoint} = $dewpoint;                                            # cur_dp  - dew point (°C)
}

# Solar radiation: FOSHKplugin >= V0.06 uses lowercase, older uses camelCase
my $solarRadiation = getFormatted('%.0f', $results, 'solarradiation');
if (defined $solarRadiation) {
    LOGDEB "Adding/overwriting solar radiation with $solarRadiation W/m2.";
    $cur->{solarRadiation} = $solarRadiation;                                  # cur_sr  - solar radiation (W/m²)
}

# UV index: FOSHKplugin >= V0.05 uses uppercase, older uses lowercase
my $uvIndex = getFormatted('%.1f', $results, 'UV')
           // getFormatted('%.1f', $results, 'uv');                            # cur_uvi - UV index
if (defined $uvIndex) {
    LOGDEB "Adding/overwriting UV index with $uvIndex.";
    $cur->{uvIndex} = $uvIndex;
}

# precipitation
my %precipitation = %{ $cur->{precipitation} // {} };

my $rainToday = getFormatted('%.2f', $results, 'dailyrainmm');                 # cur_prec_today - today precipitation (mm)
if (defined $rainToday) {
    LOGDEB "Adding/overwriting today's precipitation with $rainToday mm.";
    $precipitation{rainToday} = $rainToday;
}

my$rain1hr   = getFormatted('%.2f', $results, 'hourlyrainmm');                 # cur_prec_1hr   - 1h precipitation rate (mm)
if (defined $rain1hr) {
    LOGDEB "Adding/overwriting 1-hour precipitation with $rain1hr mm.";
    $precipitation{rain1hr}   = $rain1hr;
}

$cur->{precipitation} = \%precipitation;

# Add grabber metadata
my $generatedAt = _epochToIso(time(), $timezone);
$envelope->{$grabberKey} = {
    filename        => "$lbplogdir/$weatherKey.json",
    generatedAt     => $generatedAt,
    grabberLabel    => $grabberLabel,
    grabberScript   => $grabberFile,
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
LOGOK "Current Data saved successfully.";

# Exit
exit;

END
{
	LOGOK "END OF: $0. We are done. Good bye." if $log;
}
