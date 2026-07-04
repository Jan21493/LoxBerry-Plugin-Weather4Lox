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

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

# params from config
my $pcfg        = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $url         = "JSON?units=m?status";
my $server      = $pcfg->param("FOSHK.SERVER");
my $port        = $pcfg->param("FOSHK.PORT");

# names for JSON
my $grabberFile     = basename(__FILE__);
my $grabberLabel    = "FOSHK Weather Station";
my $grabberKey      = "foshk";              # name in JSONs
my $refresh         = 60;

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

# Get data from FOSHK Plugin Server for current conditions
my $results = apiCall(
	url => "http://$server\:$port/$url",
	info => "from $grabberLabel (NEW API via /JSON) at $server\:$port (Current Weather Data)",
);

# Read existing current.json envelope
my $weatherKey = "current";
my $envelope = readJsonFile($lbplogdir, $weatherKey);
my $cur = $envelope->{$weatherKey} // {};

LOGDEB "Adding $grabberLabel data to $weatherKey weather data (existing values for same keys will be overwritten).";

my $currentEpoch = toUnixEpoch(getValue($results, 'time'));                    # FOSHK plugin provides Loxone epoch time with this API call
my $dtCurrent = _epochToIso($currentEpoch, $timezone);
LOGINF "Observation time was $dtCurrent (epoch: $currentEpoch)";

# time
$cur->{time}{datetime}   = $dtCurrent;                                         # cur_date     - is always in UNIX epoch time
$cur->{time}{epoch}      = $currentEpoch;                                      # cur_date_des - is always in local time of Loxberry

# real (air) temperature, feels like / wind chill
my $temp      = getFormatted('%.1f', $results, 'tempc');
$cur->{temperature}{air}       = $temp;                                        # cur_tt  - air temperature (°C)

# feels like temperature
my $feelsLike = getFormatted('%.1f', $results, 'feelslikec');
if (defined $feelsLike && defined $temp && abs($feelsLike - $temp) > 0.1 || !defined $cur->{temperature}{feelsLike}) {
    $cur->{temperature}{feelsLike} = $feelsLike;                               # cur_tt_fl - feels like temperature (°C)
}

# Windchill is only relevant if it differs significantly from the actual temperature
my $windChill = getFormatted('%.1f', $results, 'windchillc');
if (defined $windChill && defined $temp && abs($windChill - $temp) > 0.1 || !defined $cur->{temperature}{windChill}) {
    $cur->{temperature}{windChill} = $windChill;                               # cur_w_ch / cur_tt_fl - wind chill (°C)
}

# Heat index is only relevant if it differs significantly from the actual temperature
my $heatIndex = getFormatted('%.1f', $results, 'heatindexc');
if (defined $heatIndex && defined $temp && abs($heatIndex - $temp) > 0.1 || !defined $cur->{temperature}{heatIndex}) {
    $cur->{temperature}{heatIndex} = $heatIndex;                               # cur_hi - heat index (°C)
}

# wind data
my $windDir = getFormatted('%.0f', $results, 'winddir');
$cur->{wind} = {
    direction  => $windDir,                                                    # cur_w_dir    - wind direction (degree)
    cardinal   => getWindDirCardinal($windDir),                                # to calculate cur_w_dirdes - wind direction description from (N, NE, E, SE, S, SW, W, NW)
    speed      => getFormatted('%.2f', $results, 'windspeedkmh'),              # cur_w_sp     - wind speed (km/h)
    gust       => getFormatted('%.2f', $results, 'windgustkmh'),               # cur_w_gu     - wind gust (km/h)
};

# other weather data
$cur->{humidity}        = getFormatted('%.1f', $results, 'humidity');          # cur_hu  - humidity (%)
$cur->{pressure}        = getFormatted('%.0f', $results, 'baromrelhpa');       # cur_pr  - air pressure (hPa)
$cur->{dewpoint}        = getFormatted('%.1f', $results, 'dewptc');            # cur_dp  - dew point (°C)

# Solar radiation: FOSHKplugin >= V0.06 uses lowercase, older uses camelCase
$cur->{solarRadiation}  = getFormatted('%.0f', $results, 'solarradiation');    # cur_sr  - solar radiation (W/m²)

# UV index: FOSHKplugin >= V0.05 uses uppercase, older uses lowercase
$cur->{uvIndex}         = getFormatted('%.1f', $results, 'uv');                # cur_uvi - UV index

# precipitation
my %precipitation = %{ $cur->{precipitation} // {} };
$precipitation{rainToday} = getFormatted('%.2f', $results, 'drain_piezomm');   # cur_prec_today - today precipitation (mm)
$precipitation{rain1hr}   = getFormatted('%.2f', $results, 'hrain_piezomm');    # cur_prec_1hr   - 1h precipitation rate (mm)
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
	LOGEND;
}
