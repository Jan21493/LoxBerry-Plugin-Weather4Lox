#!/usr/bin/perl

# cronjob.pl
# manages cronjob calls and the fetch interval for default and alternate
# weather data

# Copyright 2016-2023 Michael Schlenstedt, michael@loxberry.de
#                     mr-manuel, https://github.com/mr-manuel
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
use Getopt::Long;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

my $pcfg = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $cron = $pcfg->param("SERVER.CRON");
if (!$cron || $cron eq "0") {
	$cron = 60; # Set to 60 if not defined or 0
}
my $cron_alternate = $pcfg->param("SERVER.CRON_ALTERNATE");
if (!$cron_alternate || $cron_alternate eq "0") {
	$cron_alternate = $cron; # Set to default weather service if not defined or 0
}
my $usealternatedfc = $pcfg->param("SERVER.USEALTERNATEDFC");
my $usealternatehfc = $pcfg->param("SERVER.USEALTERNATEHFC");

# Local / own weather station
my $use_local = $pcfg->param('SERVER.WUGRABBER') || 
				$pcfg->param('SERVER.FOSHKGRABBER') || 
				$pcfg->param('SERVER.PWSCATCHUPLOADGRABBER') ||
				$pcfg->param('SERVER.LOXGRABBER');
my $cron_local = $pcfg->param("SERVER.CRON_LOCAL");
if (!$cron_local || $cron_local eq "0") {
	$cron_local = $cron; # Set to default weather service if not defined or 0
}
# Commandline options
my $verbose = '';

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 });

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'cronjob',
	logdir => "$lbplogdir",
#	filename => "$lbplogdir/cronjob.log",
#	append => 1,
);

# Due to a bug in the Logging routine, set the loglevel fix to 3
#$log->loglevel(3);
my $verbose_opt;
if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
	$verbose_opt = "-v";
}

LOGSTART "Weather4Lox CRONJOB process";
LOGDEB "This is $0 Version $version";

# calculate time
my $timestamp = time();
my $timestamp_minute_round_down = int($timestamp / 60);

my $command_opt = '';

LOGDEB "Calculate interval for default weather service: $timestamp_minute_round_down / $cron = " . ($timestamp_minute_round_down / $cron);
if ( $timestamp_minute_round_down % $cron eq 0 ){
	LOGINF "Fetch interval ($cron) for default weather service reached";
	$command_opt .= ' --default'
} else {
	LOGINF "Fetch interval ($cron) for default weather service NOT reached";
}

if ($usealternatedfc || $usealternatehfc) {
	LOGDEB "Calculate interval for alternate weather service: $timestamp_minute_round_down / $cron_alternate = " . ($timestamp_minute_round_down / $cron_alternate);
	if ( $timestamp_minute_round_down % $cron_alternate eq 0 ){
		LOGINF "Fetch interval ($cron_alternate) for alternate weather service reached";
		$command_opt .= ' --alternate'
	} else {
		LOGINF "Fetch interval ($cron_alternate) for alternate weather service NOT reached";
	}
} else {
	LOGDEB "Alternate Weather services are disabled. Skipping.";
}

if ($use_local) {
	LOGDEB "Calculate interval for own weather station / local service: $timestamp_minute_round_down / $cron_local = " . ($timestamp_minute_round_down / $cron_local);
	if ( $timestamp_minute_round_down % $cron_local eq 0 ){
		LOGINF "Fetch interval ($cron_local) for own weather station / local service reached";
		$command_opt .= ' --local'
	} else {
		LOGINF "Fetch interval ($cron_local) for own weather station / local service NOT reached";
	}
} else {
	LOGDEB "Own weather station / local service is disabled. Skipping.";
}

if ( $command_opt ne "" ){
	LOGDEB "Fetch data with following command: $lbpbindir/fetch.pl --cronjob $command_opt";
	system ("$lbpbindir/fetch.pl --cronjob $command_opt");
} else {
	LOGINF "No fetch interval reached. Skipping fetch.";
}

exit;

END
{
	LOGOK "Done";
	LOGEND;
}
