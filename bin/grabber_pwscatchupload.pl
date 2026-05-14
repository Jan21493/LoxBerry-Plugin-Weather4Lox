#!/usr/bin/perl

# Grabber for overwriting data by PWSCatchUpload data

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
my $pcfg = new Config::Simple("$lbpconfigdir/weather4lox.cfg");

my $file = "/dev/shm/pwscatchupload_w4l.json";

# names for JSON
my $grabberFile     = basename(__FILE__);
my $grabberLabel    = "PWS WU Upload Catcher";
my $grabberKey      = "pwscatchupload";
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

LOGINF "Reading data from $file";
my $json = LoxBerry::System::read_file("$file");
if (!$json) {
  LOGCRIT "Failed to read data from $file";
  exit 2;
} else {
  LOGOK "Data read successfully.";
}

# Decode JSON response
my $resCurrent = JSON::PP->new->utf8->decode($json);

# Read existing current.json envelope
my $weatherKey = "current";
my $envelope = readJsonFile($lbplogdir, $weatherKey);
my $cur = $envelope->{$weatherKey} // {};

LOGDEB "Adding $grabberLabel data to $weatherKey weather data (existing values for same keys will be overwritten).";

my $t = localtime($resCurrent->{cur_date});
LOGINF "Saving new Data for Timestamp $t to database.";

# Temperature
my $temp = getFormatted('%.1f', $resCurrent, 'cur_tt');
$cur->{temperature}{air} = $temp if defined $temp;                           # cur_tt - air temperature (C)

# Wind chill
my $windChill = getFormatted('%.1f', $resCurrent, 'cur_w_ch');
if (defined $windChill && defined $temp && abs($windChill - $temp) > 0.1 || !defined $cur->{temperature}{windChill}) {
    $cur->{temperature}{windChill} = $windChill;                             # cur_w_ch - wind chill (C)
}

# Wind data
my $windDir = getFormatted('%.0f', $resCurrent, 'cur_w_dir');
if (defined $windDir) {
    $cur->{wind} = {
        direction  => $windDir,                                                     # cur_w_dir    - wind direction (degree)
        cardinal   => getWindDirCardinal($windDir),                                 # to calculate cur_w_dirdes - wind direction description
        speed      => getFormatted('%.2f', $resCurrent, 'cur_w_sp'),                # cur_w_sp - wind speed (km/h)
        gust       => getFormatted('%.2f', $resCurrent, 'cur_w_gu'),                # cur_w_gu - wind gust (km/h)
    };
}

# Other weather data
$cur->{humidity}        = getFormatted('%.1f', $resCurrent, 'cur_hu');              # cur_hu - humidity (%)
$cur->{pressure}        = getFormatted('%.0f', $resCurrent, 'cur_pr');              # cur_pr - air pressure (hPa)
$cur->{dewpoint}        = getFormatted('%.1f', $resCurrent, 'cur_dp');              # cur_dp - dew point (C)
$cur->{solarRadiation}  = getFormatted('%.0f', $resCurrent, 'cur_sr');              # cur_sr - solar radiation (W/m2)

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
