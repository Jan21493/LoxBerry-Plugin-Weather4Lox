#!/usr/bin/perl

# Grabber for overwriting data by Loxone data

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
use LoxBerry::IO;
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

my $pcfg         = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $prefix       = $pcfg->param("LOX.PREFIX") || "w4l";         # prefix of VI/VO names to request from Miniserver, default is "w4l" 

# names for JSON
my $grabberFile     = basename(__FILE__);
my $grabberLabel    = "Loxone MS Weather Data";
my $grabberKey      = "loxone";                                 # name in JSONs
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

requireOrLogdie('DateTime::Format::ISO8601');

# all values in current, daily, and hourly JSONs are in local time, so proper time zone information is important
my $timezone = _systemTimezone();
LOGDEB "Using timezone: $timezone, current local system time is " . DateTime->now( time_zone => $timezone )->iso8601();

LOGINF "Fetching weather data from Loxone Miniserver";

my %lox_response;
my @lox_weather_arr;
my $response_success;

# VI/VO names to request from Miniserver
# NOTE: If these names are used with MQTT, values may be written and read back causing loops!
my @lox_vi_names = map { "$prefix\_$_" } qw(
	cur_tt
	cur_tt_fl
	cur_hu
	cur_w_dir
	cur_w_sp
	cur_w_gu
	cur_w_ch
	cur_pr
	cur_dp
	cur_sr
	cur_we_code
);

LOGDEB "VI's/VO's to request via HTTP call from Loxone Config: " . join(', ', @lox_vi_names);

# Fetching data from Miniserver
my $msno = defined $pcfg->param("SERVER.MSNO") ? $pcfg->param("SERVER.MSNO") : 1;
LOGINF "Using Miniserver no. $msno";
%lox_response = LoxBerry::IO::mshttp_get($msno, @lox_vi_names);

# Checking the response - if nothing is OK, no patching required
foreach my $resp (keys %lox_response) {
	if($lox_response{$resp}) {
		$response_success = 1;
		last;
	}
}

if( !$response_success ) {
	LOGINF "No Miniserver VI responded with data. Quitting.";
	exit 0;
};

# Read existing current.json envelope
my $weatherKey = "current";
my $envelope = readJsonFile($lbplogdir, $weatherKey);
my $cur = $envelope->{$weatherKey} // {};

LOGDEB "Adding $grabberLabel data to $weatherKey weather data (existing values for same keys will be overwritten).";

# Helper: extract numeric value from Loxone response, skip -9999 sentinel
sub loxVal {
	my ($key, $fmt) = @_;
	my $v = $lox_response{$key};
	return undef unless defined $v && $v ne "-9999";
	$v =~ s/^([-\d\.]+).*/$1/g;                                 # strip trailing non-numeric
	return undef unless Scalar::Util::looks_like_number($v);
	if (defined $fmt) {
		# Apply formatting and convert back to number to avoid locale issues with decimal separator
		my $formatted = sprintf($fmt, $v);
		LOGDEB "Found Loxone parameter $key with format '$fmt', raw value '$v', formatted value '$formatted'";
		return $formatted + 0;
	}
	LOGDEB "Found Loxone parameter $key, value '$v'";
	return $v + 0;
}

# temperature
my $tempAir = loxVal("${prefix}_cur_tt", '%.1f');               # cur_tt  - air temperature (°C)
if (defined $tempAir && $tempAir != -9999) {
	LOGDEB "Adding/overwriting temperature/air with $tempAir degC.";
	$cur->{temperature}{air}       = $tempAir;                  # cur_tt  - air temperature (°C)
}
my $tempFeelsLike = loxVal("${prefix}_cur_tt_fl", '%.1f');      # cur_tt_fl - feels like (°C)
if (defined $tempFeelsLike && $tempFeelsLike != -9999) {
	LOGDEB "Adding/overwriting temperature/feelsLike with $tempFeelsLike degC.";
	$cur->{temperature}{feelsLike} = $tempFeelsLike;            # cur_tt_fl - feels like (°C)
}
my $tempWindChill = loxVal("${prefix}_cur_w_ch", '%.1f');       # cur_w_ch  - wind chill (°C)
if (defined $tempWindChill && $tempWindChill != -9999) {
	LOGDEB "Adding/overwriting temperature/windChill with $tempWindChill degC.";
	$cur->{temperature}{windChill} = $tempWindChill;            # cur_w_ch  - wind chill (°C)
}

# wind data
my $windDir = loxVal("${prefix}_cur_w_dir", '%.0f');
my $windSpeed = loxVal("${prefix}_cur_w_sp", '%.2f');
if (defined $windDir && defined $windSpeed && $windDir != -9999 && $windSpeed != -9999) {
	LOGDEB "Adding/overwriting wind/direction with $windDir (deg), wind/speed with $windSpeed km/h.";
	$cur->{wind}{direction}  = $windDir;                        # cur_w_dir    - wind direction (degree)
	$cur->{wind}{cardinal}   = getWindDirCardinal($windDir);    # to calculate cur_w_dirdes - wind direction description from (N, NE, E, SE, S, SW, W, NW)
	$cur->{wind}{speed}      = $windSpeed;                      # cur_w_sp     - wind speed (km/h)

	# Only set gust if it is defined, otherwise we might overwrite existing valid data with undefined values
	my $windGust = loxVal("${prefix}_cur_w_gu", '%.2f');
	if (defined $windGust && $windGust != -9999) {
		LOGDEB "Adding/overwriting wind/gust with $windGust km/h.";
		$cur->{wind}{gust}   = $windGust;                       # cur_w_gu     - wind gust (km/h)
	}	
} 

# other weather data
my $humidity = loxVal("${prefix}_cur_hu", '%.1f');
if (defined $humidity && $humidity != -9999) {
	LOGDEB "Adding/overwriting humidity with $humidity %.";
	$cur->{humidity}        = $humidity;                        # cur_hu  - humidity (%)
}
my $pressure = loxVal("${prefix}_cur_pr", '%.0f');
if (defined $pressure && $pressure != -9999) {
	LOGDEB "Adding/overwriting pressure with $pressure hPa.";
	$cur->{pressure}        = $pressure;                        # cur_pr  - air pressure (hPa)
}
my $dewPoint = loxVal("${prefix}_cur_dp", '%.1f');
if (defined $dewPoint && $dewPoint != -9999) {
	LOGDEB "Adding/overwriting dewpoint with $dewPoint degC.";
	$cur->{dewpoint}        = $dewPoint;                        # cur_dp  - dew point (°C)
}
my $solarRadiation = loxVal("${prefix}_cur_sr", '%.0f');
if (defined $solarRadiation && $solarRadiation != -9999) {
	LOGDEB "Adding/overwriting solarRadiation with $solarRadiation W/m2.";
	$cur->{solarRadiation}  = $solarRadiation;                  # cur_sr  - solar radiation (W/m²)
}
my $weatherCode = loxVal("${prefix}_cur_we_code", '%.0f');
if (defined $weatherCode && $weatherCode != -9999) {
	LOGDEB "Adding/overwriting weatherCode with $weatherCode.";
	$cur->{weatherCode}{weather4lox} = oldW4lCode_to_w4l($weatherCode);    # cur_we_code - weather code
}

# Add grabber metadata
my $generatedAt = DateTime->now( time_zone => $timezone );
$envelope->{$grabberKey} = {
	filename        => "$lbplogdir/$weatherKey.json",
	generatedAt     => $generatedAt->iso8601(),
	grabberLabel    => $grabberLabel,
	grabberScript   => $grabberFile,
	schemaVersion   => "v1.0",
};
$envelope->{$weatherKey} = $cur;

if ($refresh < $envelope->{refresh}) {
    LOGINF "Reducing refresh interval for $weatherKey weather data from $envelope->{refresh} to $refresh minutes.";
    $envelope->{refresh} = $refresh;
}
$envelope->{generatedAt} = $generatedAt->iso8601();

# Store current conditions in local SQLite observation buffer for offline aggregation
if ( $pcfg->param("SERVER.OBS_BUFFER") ) {
	require "$lbpbindir/observation_buffer.pl";
	my $obsDbh = initObsDb("$lbpdatadir/observations.db");
	my $retentionHours = $pcfg->param("SERVER.OBS_RETENTION") || 72;
	storeObservation($obsDbh, $retentionHours,
		epoch      => $cur->{time}{epoch} // time(),
		source     => $grabberKey,
		temp       => $cur->{temperature}{air},
		feelsLike  => $cur->{temperature}{feelsLike},
		humidity   => $cur->{humidity},
		pressure   => $cur->{pressure},
		windSpeed  => $cur->{wind}{speed},
		windGust   => $cur->{wind}{gust},
		windDir    => $cur->{wind}{direction},
		precip     => $cur->{precipitation}{rain1hr},
		dewpoint   => $cur->{dewpoint},
		cloudCover => $cur->{cloudCover},
		uvIndex    => $cur->{uvIndex},
		solarRad   => $cur->{solarRadiation},
		icon       => $cur->{weatherCode}{weather4lox},
	);
	$obsDbh->disconnect();
	LOGDEB "Stored current conditions in local observation buffer (source: $grabberKey).";
}

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
