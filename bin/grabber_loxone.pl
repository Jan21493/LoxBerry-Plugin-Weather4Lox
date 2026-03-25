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

# names for JSON
my $grabberFile     = basename(__FILE__);
my $grabberLabel    = "Loxone";
my $grabberKey      = "loxone";              # name in JSONs

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
            'quiet'   => sub { $verbose = 0 });

if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGSTART "Weather4Lox $grabberLabel GRABBER process started";
LOGDEB "This is $0 Version $version";


LOGINF "Fetching weather data from Loxone Miniserver";

my %lox_response;
my @lox_weather_arr;
my $response_success;

# VI names to request from Miniserver
my @lox_vi_names = qw(
	w4l_cur_tt
	w4l_cur_tt_fl
	w4l_cur_hu
	w4l_cur_w_dir
	w4l_cur_w_sp
	w4l_cur_w_gu
	w4l_cur_w_ch
	w4l_cur_pr
	w4l_cur_dp
	w4l_cur_sr
	w4l_cur_we_code
);

LOGDEB "VI's to request: " . join(', ', @lox_vi_names);

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
	$v =~ s/^([-\d\.]+).*/$1/g;                   # strip trailing non-numeric
	return undef unless Scalar::Util::looks_like_number($v);
	return sprintf($fmt, $v) + 0 if defined $fmt;
	return $v + 0;
}

# temperature
$cur->{temperature}{air}       = loxVal('w4l_cur_tt',    '%.1f');   # cur_tt  - air temperature (°C)
$cur->{temperature}{windChill} = loxVal('w4l_cur_tt_fl', '%.1f')    # cur_tt_fl - feels like (°C)
                              // loxVal('w4l_cur_w_ch',  '%.1f');   # cur_w_ch  - wind chill fallback

# wind data
my $windDir = loxVal('w4l_cur_w_dir', '%.0f');
$cur->{wind} = {
	direction  => $windDir,                                                   # cur_w_dir    - wind direction (degree)
	cardinal   => getWindDirCardinal($windDir),                               # to calculate cur_w_dirdes - wind direction description from (N, NE, E, SE, S, SW, W, NW)
	speed      => loxVal('w4l_cur_w_sp', '%.2f'),                             # cur_w_sp     - wind speed (km/h)
	gust       => loxVal('w4l_cur_w_gu', '%.2f'),                             # cur_w_gu     - wind gust (km/h)
};

# other weather data
$cur->{humidity}        = loxVal('w4l_cur_hu',      '%.1f');        # cur_hu  - humidity (%)
$cur->{pressure}        = loxVal('w4l_cur_pr',      '%.0f');        # cur_pr  - air pressure (hPa)
$cur->{dewpoint}        = loxVal('w4l_cur_dp',      '%.1f');        # cur_dp  - dew point (°C)
$cur->{solarRadiation}  = loxVal('w4l_cur_sr',      '%.0f');        # cur_sr  - solar radiation (W/m²)
$cur->{weatherCode}     = loxVal('w4l_cur_we_code', '%.0f');        # cur_we_code - weather code

# Enrich with normalized weatherId from legacy code
_enrichWeatherId($cur);

# Add grabber metadata
my $dtCurrent = localtime;
$envelope->{$grabberKey} = {
	filename        => "$lbplogdir/$weatherKey.json",
	generatedAt     => $dtCurrent->datetime(),
	grabberLabel    => $grabberLabel,
	grabberScript   => $grabberFile,
	schemaVersion   => "v1.0",
};
$envelope->{$weatherKey} = $cur;

# Add refresh interval from CRON_PATCH config
my $cronMinutes = $pcfg->param("SERVER.CRON_PATCH") // 1;
$envelope->{refresh} = $cronMinutes * 60;

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
