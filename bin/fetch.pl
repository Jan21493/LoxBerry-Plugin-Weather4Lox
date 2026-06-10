#!/usr/bin/perl

# fetch.pl
# fetches weather data (current and forecast) from Weather Services

# Copyright 2016-2023 Michael Schlenstedt, michael@loxberry.de
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
my $service = $pcfg->param("SERVER.WEATHERSERVICE");
my $servicedfc;
my $servicehfc;
my $serviceobs;
if ( $pcfg->param("SERVER.USEALTERNATEDFC") ) {
    $servicedfc = $pcfg->param("SERVER.WEATHERSERVICEDFC");
}
if ( $pcfg->param("SERVER.USEALTERNATEHFC") ) {
    $servicehfc = $pcfg->param("SERVER.WEATHERSERVICEHFC");
}
if ( $pcfg->param("SERVER.USEWEATHEROBS") ) {
    $serviceobs = $pcfg->param("SERVER.WEATHERSERVICEOBS");
}

# Commandline options
my $verbose = '';
my $cronjob = '';
my $default = '';
my $alternate = '';
my $airquality = '';
my $local = '';
my $interval = 60; # default interval for refresh in minutes
my $includeObs = '';

# optional, default: 1, used to mask keyparam in URLs and literal key value in dumps
my $maskkeys = $pcfg->param('SERVER.MASKKEYS');
$maskkeys = 1 if !defined($maskkeys) || $maskkeys eq '';

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 },
            'cronjob' => \$cronjob,
            'default' => \$default,
            'alternate' => \$alternate,
            'airquality' => \$airquality,
            'local' => \$local,
            'maskkeys' => \$maskkeys,
            'interval=i' => \$interval,
            'includeobs' => \$includeObs,
            );

# Create a logging object
my $log = LoxBerry::Log->new (
    package => 'weather4lox',
    name => 'fetch',
    logdir => "$lbplogdir",
#   filename => "$lbplogdir/weather4lox.log",
#   append => 1,
);

# Due to a bug in the Logging routine, set the loglevel fix to 3
#$log->loglevel(3);
my $verbose_opt = '';
if ($verbose) {
    $log->stdout(1);
    $log->loglevel(7);
    $verbose_opt = "--verbose";
}

LOGSTART "Weather4Lox FETCH process";
LOGDEB "This is $0 Version $version";

my $maskkeys_opt = '';
if ($maskkeys) {
    $maskkeys_opt = "--maskkeys";
} 
LOGINF "Weather4Lox Fetch - masking API keys is " . ($maskkeys ? "enabled" : "disabled") . ", include observations is " . ($includeObs ? "enabled" : "disabled") . ".";

# execute when fetch.pl is called directly or with cronjob and default flag
if( !$cronjob || ( $cronjob && $default ) ){
    LOGINF "Fetch default weather data ...";
    # Which grabber should grab which weather data?
    my $service_opt = "--current";

    if ( ($servicedfc && $servicedfc eq $service) || !$servicedfc ) {
        $service_opt .= " --daily";
    }
    if ( ($servicehfc && $servicehfc eq $service) || !$servicehfc ) {
        $service_opt .= " --hourly";
    }
    $interval = $pcfg->param("SERVER.CRON") || $interval;
    $service_opt .= " --interval $interval";

    if (-e "$lbpbindir/grabber_$service.pl") {
        LOGINF "Starting Grabber grabber_$service.pl $service_opt $verbose_opt $maskkeys_opt";
        $log->close;
        system ("$lbpbindir/grabber_$service.pl $service_opt $verbose_opt $maskkeys_opt");
    } else {
        LOGCRIT "Cannot find grabber script for service $service.";
        exit (1);
    }
    $log->open;
}

# execute when fetch.pl is called directly or with cronjob and alternate flag
if( !$cronjob || ( $cronjob && $alternate ) ){
    LOGINF "Fetch alternate weather data ...";

    # get interval for alternate weather service, if not set, use default interval, 0 means to use default weather service interval
    $interval = $pcfg->param("SERVER.CRON_ALTERNATE") || $interval;
    if ($interval == 0) {
        $interval = $pcfg->param("SERVER.CRON");
    } 

    # Grab alternate DFC / HFC
    if ( $servicedfc && $servicedfc eq $servicehfc ) {
        if (-e "$lbpbindir/grabber_$servicedfc.pl") {
            LOGINF "Starting Grabber grabber_$servicedfc.pl --daily --hourly $verbose_opt $maskkeys_opt --interval $interval";
            $log->close;
            system ("$lbpbindir/grabber_$servicedfc.pl --daily --hourly $verbose_opt $maskkeys_opt --interval $interval");
        } else {
            LOGCRIT "Cannot find grabber script for service $servicedfc.";
            exit (1);
        }
    } elsif ( $servicedfc && $servicedfc ne $servicehfc ) {
        if (-e "$lbpbindir/grabber_$servicedfc.pl") {
            LOGINF "Starting Grabber grabber_$servicedfc.pl --daily $verbose_opt $maskkeys_opt --interval $interval";
            $log->close;
            system ("$lbpbindir/grabber_$servicedfc.pl --daily $verbose_opt $maskkeys_opt --interval $interval");
        } else {
            LOGCRIT "Cannot find grabber script for service $servicedfc.";
            exit (1);
        }
    }
    $log->open;

    if ( $servicehfc && $servicehfc ne $servicedfc ) {
        if (-e "$lbpbindir/grabber_$servicehfc.pl") {
            LOGINF "Starting Grabber grabber_$servicehfc.pl --hourly $verbose_opt $maskkeys_opt --interval $interval";
            $log->close;
            system ("$lbpbindir/grabber_$servicehfc.pl --hourly $verbose_opt $maskkeys_opt --interval $interval");
        } else {
            LOGCRIT "Cannot find grabber script for service $servicehfc.";
            exit (1);
        }
    }
    $log->open;
}
# execute when fetch.pl is called directly or with cronjob and default or alternate flag
if( !$cronjob || ( $cronjob && $airquality) ) {
    LOGINF "Fetch air quality and pollen data ...";

    # get interval for air quality, if not set, use default interval, 0 means to use default weather service interval
    $interval = $pcfg->param("SERVER.CRON_AIRQUALITY") || $interval;
    if ($interval == 0) {
        $interval = $pcfg->param("SERVER.CRON");
    } 

    # Grab air quality / pollen data from Open-Meteo
    if ( $pcfg->param("SERVER.OPENMETEOAIRQUALITYGRABBER") ) {
        LOGINF "Starting Grabber grabber_openmeteo_airquality.pl $verbose_opt --interval $interval";
        $log->close;
        system ("$lbpbindir/grabber_openmeteo_airquality.pl $verbose_opt --interval $interval");
        $log->open;
    }
}

# execute when fetch.pl is called directly or with cronjob and local flag
if( !$cronjob || ( $cronjob && $local ) ) {
    LOGINF "Fetch current weather data from local Weather Underground PWS ...";

    $interval = $pcfg->param("SERVER.CRON_LOCAL") || $interval;

    # Grab data from Weather Underground PWS
    if ( $pcfg->param("SERVER.WUGRABBER") ) {
        LOGINF "Starting Grabber grabber_wu_pws.pl $verbose_opt --interval $interval";
        $log->close;
        system ("$lbpbindir/grabber_wu_pws.pl $verbose_opt --interval $interval");
        $log->open;
    }
}

# only execute when fetch.pl is called with includeObs flag, either directly or with cronjob
# reason: observations are quite expensive, so flag is needed to avoid running it with every manual fetch
if( $includeObs ) {
    if ( $pcfg->param("SERVER.OBS_AGGREGATE") ) {
        LOGINF "Aggregating hourly and daily observations from local buffer ...";
        $log->close;
        system ("$lbpbindir/aggregate_observations.pl --hourly --daily $verbose_opt");
        $log->open;
    }

    LOGINF "Fetch weather observations ...";
    # Add option for observations grabber
    my $service_opt = "--observations";

    if (-e "$lbpbindir/grabber_$serviceobs.pl") {
        LOGINF "Starting Grabber grabber_$serviceobs.pl $service_opt $verbose_opt $maskkeys_opt";
        $log->close;
        system ("$lbpbindir/grabber_$serviceobs.pl $service_opt $verbose_opt $maskkeys_opt");
    } else {
        LOGCRIT "Cannot find grabber script for service $serviceobs.";
        exit (1);
    }
    $log->open;
}

# Data to Loxone
LOGINF "Starting script datatoloxone.pl $verbose_opt $maskkeys_opt";
$log->close;
system ("$lbpbindir/datatoloxone.pl $verbose_opt  $maskkeys_opt");
$log->open;

exit;

END
{
    LOGOK "Done";
    LOGEND;
}
