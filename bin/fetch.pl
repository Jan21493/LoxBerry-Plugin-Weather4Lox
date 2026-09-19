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
my $own = '';
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
            'own' => \$own,
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

##########################################################################
# Run a grabber (or datatoloxone.pl) as an external process and log a clear
# error if it failed. Without this check, a grabber crash (e.g. exit code 2
# from requireOrLogdie because of a missing Perl module after a Perl
# upgrade) went unnoticed: the fetch log just ended with "TASK FINISHED"
# while Loxone kept receiving stale weather data for weeks - see
# https://github.com/Jan21493/LoxBerry-Plugin-Weather4Lox/issues/63
##########################################################################
sub run_grabber {
    my ($cmd, $label) = @_;

    $log->close;
    system ($cmd);
    my $rc = $?;
    $log->open;

    if ($rc == -1) {
        LOGCRIT "Failed to execute $label: $!";
        return 0;
    } elsif ($rc & 127) {
        LOGCRIT "$label was terminated by signal " . ($rc & 127) . ".";
        return 0;
    } elsif (($rc >> 8) != 0) {
        LOGCRIT "$label exited with error code " . ($rc >> 8) . " - weather data may not have been updated. Check the $label log for details.";
        return 0;
    }
    return 1;
}

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
        run_grabber("$lbpbindir/grabber_$service.pl $service_opt $verbose_opt $maskkeys_opt", "grabber_$service.pl");
    } else {
        LOGCRIT "Cannot find grabber script for service $service.";
        exit (1);
    }
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
            run_grabber("$lbpbindir/grabber_$servicedfc.pl --daily --hourly $verbose_opt $maskkeys_opt --interval $interval", "grabber_$servicedfc.pl");
        } else {
            LOGCRIT "Cannot find grabber script for service $servicedfc.";
            exit (1);
        }
    } elsif ( $servicedfc && $servicedfc ne $servicehfc ) {
        if (-e "$lbpbindir/grabber_$servicedfc.pl") {
            LOGINF "Starting Grabber grabber_$servicedfc.pl --daily $verbose_opt $maskkeys_opt --interval $interval";
            run_grabber("$lbpbindir/grabber_$servicedfc.pl --daily $verbose_opt $maskkeys_opt --interval $interval", "grabber_$servicedfc.pl");
        } else {
            LOGCRIT "Cannot find grabber script for service $servicedfc.";
            exit (1);
        }
    }

    if ( $servicehfc && $servicehfc ne $servicedfc ) {
        if (-e "$lbpbindir/grabber_$servicehfc.pl") {
            LOGINF "Starting Grabber grabber_$servicehfc.pl --hourly $verbose_opt $maskkeys_opt --interval $interval";
            run_grabber("$lbpbindir/grabber_$servicehfc.pl --hourly $verbose_opt $maskkeys_opt --interval $interval", "grabber_$servicehfc.pl");
        } else {
            LOGCRIT "Cannot find grabber script for service $servicehfc.";
            exit (1);
        }
    }
}
# only execute when fetch.pl is called with includeObs flag, either directly or with cronjob
# reason: observations are quite expensive, so flag is needed to avoid running it with every manual fetch
if( $includeObs ) {
    LOGINF "Fetch  weather observations ...";
    # Add option for observations grabber
    my $service_opt = "--observations";

    if (-e "$lbpbindir/grabber_$serviceobs.pl") {
        LOGINF "Starting Grabber grabber_$serviceobs.pl $service_opt $verbose_opt $maskkeys_opt";
        run_grabber("$lbpbindir/grabber_$serviceobs.pl $service_opt $verbose_opt $maskkeys_opt", "grabber_$serviceobs.pl");
    } else {
        LOGCRIT "Cannot find grabber script for service $serviceobs.";
        exit (1);
    }
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
        run_grabber("$lbpbindir/grabber_openmeteo_airquality.pl $verbose_opt --interval $interval", "grabber_openmeteo_airquality.pl");
    }
}

# execute when fetch.pl is called directly or with cronjob and local flag
if( !$cronjob || ( $cronjob && $local ) ) {
    LOGINF "Fetch current weather data from local weather stations ...";

    $interval = $pcfg->param("SERVER.CRON_LOCAL") || $interval;

    # Grab some data from Wunderground
    if ( $pcfg->param("SERVER.WUGRABBER") ) {
        LOGINF "Starting Grabber grabber_wu_pws.pl $verbose_opt --interval $interval";
        run_grabber("$lbpbindir/grabber_wu_pws.pl $verbose_opt --interval $interval", "grabber_wu_pws.pl");
    }
}

# execute when fetch.pl is called directly or with cronjob and own flag
if( !$cronjob || ( $cronjob && $own ) ) {
    LOGINF "Fetch current weather data from own weather stations ...";

    $interval = 1; # own weather stations are updated once per minute, so no interval calculation is needed

    # Grab some data from FOSHKplugin
    if ( $pcfg->param("SERVER.FOSHKGRABBER") ) {
        my $foshknewapi = $pcfg->param("SERVER.FOSHKNEWAPI");
        if ($foshknewapi) {
            LOGINF "Starting Grabber grabber_foshk2.pl (NEW API!) $verbose_opt --interval $interval";
            run_grabber("$lbpbindir/grabber_foshk2.pl $verbose_opt --interval $interval", "grabber_foshk2.pl");
        } else {
            LOGINF "Starting Grabber grabber_foshk.pl (OLD API) $verbose_opt --interval $interval";
            run_grabber("$lbpbindir/grabber_foshk.pl $verbose_opt --interval $interval", "grabber_foshk.pl");
        }
    }

    # Grab some data from PWSCatchUpload
    if ( $pcfg->param("SERVER.PWSCATCHUPLOADGRABBER") ) {
        LOGINF "Starting Grabber grabber_pwscatchupload.pl $verbose_opt --interval $interval";
        run_grabber("$lbpbindir/grabber_pwscatchupload.pl $verbose_opt --interval $interval", "grabber_pwscatchupload.pl");
    }

    # Grab some data from Loxone Miniserver
    if ( $pcfg->param("SERVER.LOXGRABBER") ) {
        LOGINF "Starting Grabber grabber_loxone.pl $verbose_opt --interval $interval";
        run_grabber("$lbpbindir/grabber_loxone.pl $verbose_opt --interval $interval", "grabber_loxone.pl");
    }
}

# Data to Loxone
LOGINF "Starting script datatoloxone.pl $verbose_opt $maskkeys_opt";
run_grabber("$lbpbindir/datatoloxone.pl $verbose_opt  $maskkeys_opt", "datatoloxone.pl");

exit;

END
{
    LOGOK "Done";
    LOGEND;
}
