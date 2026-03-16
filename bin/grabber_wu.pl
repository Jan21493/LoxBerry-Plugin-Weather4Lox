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
my $pcfg		= new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $wuurl		= $pcfg->param("WUNDERGROUND.URL");
my $stationid		= $pcfg->param("WUNDERGROUND.STATIONID");

# names for JSON 
my $grabber_file     = basename(__FILE__);
my $grabber_label    = "Weather Underground ";
my $grabber_key      = "wunderground";          # name in JSONs

# Get the public API key from the WU website
# curl -Ss https://www.wunderground.com/dashboard/pws/ISACHSEN347 | grep apiKey | sed -r 's/.*apiKey=([0-9a-z]*)\&.*/\1/g'
# $content = qx(curl -Ss https://www.wunderground.com/dashboard/pws/ISACHSEN347 | grep apiKey);
my $urlGetKey_raw = "https://www.wunderground.com/dashboard/pws/$stationid";

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

require_or_logdie('DateTime::Format::ISO8601');

# all values in current, daily, and hourly JSONs are in local time, so proper time zone information is important
my $timezone         = qx(cat /etc/timezone);
chomp ($timezone);

my $apikey = api_call(
	url => "$urlGetKey_raw",
	# maskkeys => $maskkeys,    # no masking needed here as there are no secret API keys
	# keyparam => 'appid',
	# apikey => $apikey, 
	info => "for station ID $stationid (getting API key only)",
    match => qr/.*apiKey=([0-9a-z]*)\&.*/s,
);

# Get data from Wunderground Server (API request) for current conditions
my $resCurrent = api_call(
	url => "$wuurl?apiKey=$apikey&stationId=$stationid&format=json&units=m&numericPrecision=decimal",
	#maskkeys => $maskkeys, # not needed here 
	#keyparam => 'appid',
	# apikey => $apikey,
	info => "for Location $stationid (Current Weather Data)",
);

# read JSON file for current conditions get basic weather data
my $weather_key = "current";
my $envelope = read_json_file($lbplogdir, $weather_key);
my %current_data = %{ $envelope->{$weather_key} // {} };

LOGDEB "Adding/overwriting WU data to $weather_key weather data.";

# temperature and feels-like temperature (wind chill)
$current_data{temperature} = {
    air             => get_formatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'temp'),           # cur_tt        - hourly max temperature (°C)
    feelslike       => get_formatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'windChill'),      # cur_tt_fl     - min feels-like temperature, same as cur_w_ch  - wind chill (feel)
};

# wind data
my $wind_dir = get_formatted('%.0f', $resCurrent, 'observations', 0, 'winddir'); 
$current_data{wind} = {
    direction       => $wind_dir,                                                                         # cur_w_dir     - wind direction (degree)
    dir_label       => get_wind_direction_label($wind_dir, \%L),                                          # cur_w_dirdes  - wind direction description
    speed           => get_formatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'windSpeed'),      # cur_w_sp      - wind speed (km/h)
    gust            => get_formatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'windGust'),       # cur_w_gu      - wind gust (km/h)
};

# other weather data
$current_data{humidity} = get_formatted('%.1f', $resCurrent, 'observations', 0, 'humidity');              # cur_hu        - humidity
$current_data{pressure} = get_formatted('%.0f', $resCurrent, 'observations', 0, 'metric', 'pressure');    # cur_pr        - air pressure (hPa)
$current_data{dewpoint} = get_formatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'dewpt');       # cur_dp        - dew point (°C)
$current_data{uv_index} = get_formatted('%.1f', $resCurrent, 'observations', 0, 'uv');                    # cur_uvi       - UV index
$current_data{visibility} = get_percentage('%.0f', $resCurrent, 'observations', 0, 'visibility');         # cur_vis       - visibility (m/km as needed)
$current_data{solar_radiation} = get_formatted('%.1f', $resCurrent, 'observations', 0, 'solarRadiation'); # cur_sr        - solar radiation (W/m²)
$current_data{heat_index} = get_formatted('%.1f', $resCurrent, 'observations', 0, 'metric', 'heatIndex'); # cur_hi        - heat index (°C)

# precipitation
my %precipitation = %{ $current_data{precipitation} // {} };

$precipitation{rain_today_mm} = get_formatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'precipTotal' );      # cur_prec_today, today precipitation in mm
$precipitation{rain_1hr_mm} = get_formatted('%.2f', $resCurrent, 'observations', 0, 'metric', 'precipRate' );        # cur_prec_1hr, 1h precipitation in mm

$current_data{precipitation} = \%precipitation;

# Add station information and metadata

my $station_id = get_formatted('', $resCurrent, 'observations', 0, 'stationID'); # station ID from WU data, e.g. ISCHLESW69
my $obs_time_local = get_formatted('', $resCurrent, 'observations', 0, 'obsTimeLocal'); # observation time in local time, e.g. 2026-03-16 00:44:29

my $dt_current = DateTime->now( time_zone => $timezone );

$envelope->{$grabber_key} = {
	filename        => "$lbplogdir/$weather_key.json",
	generated_at    => $dt_current->iso8601(),
	observed_at     => $obs_time_local,
	grabber_label   => $grabber_label,
	grabber_script  => $grabber_file,
	station_id      => $station_id,
	schema_version  => "v1.0",
};
$envelope->{$weather_key} = \%current_data;

# Write JSON back to file
write_json_file($lbplogdir, $weather_key, $envelope);

# Give OK status to client.
LOGOK "Current weather data is saved successfully.";


# Exit
exit;

END
{
	LOGEND;
}
