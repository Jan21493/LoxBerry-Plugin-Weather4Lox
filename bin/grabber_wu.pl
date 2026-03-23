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
my $grabberLabel    = "Weather Underground ";
my $grabberKey      = "wunderground";          # name in JSONs

# Get the public API key from the WU website
# curl -Ss https://www.wunderground.com/dashboard/pws/ISACHSEN347 | grep apiKey | sed -r 's/.*apiKey=([0-9a-z]*)\&.*/\1/g'
# $content = qx(curl -Ss https://www.wunderground.com/dashboard/pws/ISACHSEN347 | grep apiKey);
my $urlGetKeyRaw = "https://www.wunderground.com/dashboard/pws/$stationid";

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
    package => 'weather4lox',
    name => 'grabber_wu',
    logdir => "$lbplogdir",
);

# Commandline options
my $verbose = '';

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 });

if ($verbose) {
    $log->stdout(1);
    $log->loglevel(7);
}

LOGSTART "Weather4Lox GRABBER_WUNDERGROUND process started";
LOGDEB "This is $0 Version $version";

requireOrLogdie('DateTime::Format::ISO8601');

# all values in current, daily, and hourly JSONs are in local time, so proper time zone information is important
my $timezone         = qx(cat /etc/timezone);
chomp ($timezone);

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
    #maskkeys => $maskkeys, # not needed here 
    #keyparam => 'appid',
    # apikey => $apikey,
    info => "for PWS station ID $stationid (Current Weather Data)",
);

# read JSON file for current conditions get basic weather data
my $weatherKey = "current";
my $envelope = readJsonFile($lbplogdir, $weatherKey);
my $cur = $envelope->{$weatherKey} // {};

LOGDEB "Adding/overwriting WU data to $weatherKey weather data.";

# real (air) temperature, feels like, wind chill and heat index
my $temp = getFormatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'temp');
my $windChill = getFormatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'windChill');
my $heatIndex = getFormatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'heatIndex');

$cur->{temperature}{air} = $temp;                                                                    # cur_tt        - hourly max temperature (°C)
# Windchill is only relevant if it differs significantly from the actual temperature
if (defined $windChill && defined $temp && abs($windChill - $temp) > 0.1 || !defined $cur->{temperature}{windChill}) {
    $cur->{temperature}{windChill} = $windChill;                                                   # cur_w_ch      - min feels-like temperature, same as cur_w_ch  - wind chill (feel)
}
# Heat index is only relevant if it differs significantly from the actual temperature
if (defined $heatIndex && defined $temp && abs($heatIndex - $temp) > 0.1 || !defined $cur->{temperature}{heatIndex}) {
    $cur->{temperature}{heatIndex} = $heatIndex;                                                   # cur_hi        - heat index (°C)
}

# wind data
my $windDir = getFormatted('%.0f', $resCurrent, 'observations', 0, 'winddir'); 
$cur->{wind} = {
    direction       => $windDir,                                                                    # cur_w_dir     - wind direction (degree)
    dirLabel       => getWindDirectionLabel($windDir, \%L),                                         # cur_w_dirdes  - wind direction description
    speed           => getFormatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'windSpeed'), # cur_w_sp      - wind speed (km/h)
    gust            => getFormatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'windGust'),  # cur_w_gu      - wind gust (km/h)
};

# other weather data
$cur->{humidity} = getFormatted('%.1f', $resCurrent, 'observations', 0, 'humidity');              # cur_hu        - humidity
$cur->{pressure} = getFormatted('%.0f', $resCurrent, 'observations', 0, 'metric', 'pressure');    # cur_pr        - air pressure (hPa)
$cur->{dewpoint} = getFormatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'dewpt');       # cur_dp        - dew point (°C)
$cur->{uvIndex} = getFormatted('%.1f', $resCurrent, 'observations', 0, 'uv');                     # cur_uvi       - UV index
$cur->{visibility} = getPercentage('%.0f', $resCurrent, 'observations', 0, 'visibility');         # cur_vis       - visibility (m/km as needed)
$cur->{solarRadiation} = getFormatted('%.1f', $resCurrent, 'observations', 0, 'solarRadiation');  # cur_sr        - solar radiation (W/m²)

# precipitation
my %precipitation = %{ $cur->{precipitation} // {} };

$precipitation{rainToday} = getFormatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'precipTotal' );      # cur_prec_today, today precipitation in mm
$precipitation{rain1hr} = getFormatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'precipRate' );         # cur_prec_1hr, 1h precipitation in mm

$cur->{precipitation} = \%precipitation;

# Add station information and metadata

my $stationID = getFormatted('', $resCurrent, 'observations', 0, 'stationID'); # station ID from WU data, e.g. ISCHLESW69
my $obsTimeLocal = getFormatted('', $resCurrent, 'observations', 0, 'obsTimeLocal'); # observation time in local time, e.g. 2026-03-16 00:44:29

my $dtCurrent = DateTime->now( time_zone => $timezone );

$envelope->{$grabberKey} = {
    filename        => "$lbplogdir/$weatherKey.json",
    generatedAt     => $dtCurrent->iso8601(),
    observedAt      => $obsTimeLocal,
    grabberLabel    => $grabberLabel,
    grabberScript   => $grabberFile,
    stationID       => $stationID,
    schemaVersion   => "v1.0",
};
$envelope->{$weatherKey} = $cur;

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