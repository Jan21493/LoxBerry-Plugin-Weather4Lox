#!/usr/bin/perl

# weather4lox_minutecron.pl
# Called every minute from cron.01min and runs local grabbers sequentially.

# Copyright 2016-2026 Michael Schlenstedt, michael@loxberry.de
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

use LoxBerry::System;
use LoxBerry::Log;
use Getopt::Long;

my $version = LoxBerry::System::pluginversion();
my $pcfg = new Config::Simple("$lbpconfigdir/weather4lox.cfg");

my $verbose = '';
GetOptions(
    'verbose' => \$verbose,
    'quiet'   => sub { $verbose = 0 },
);

my $log = LoxBerry::Log->new(
    package => 'weather4lox',
    name    => 'minutecron',
    logdir  => "$lbplogdir",
);

if ($verbose) {
    $log->stdout(1);
    $log->loglevel(7);
}

LOGSTART 'Weather4Lox MINUTECRON process';
LOGDEB "This is $0 Version $version";

my $verboseOpt = $verbose ? '--verbose' : '';

if ($pcfg->param('SERVER.FOSHKGRABBER')) {
    LOGINF 'Starting grabber_foshk.pl';
    $log->close;
    system("$lbpbindir/grabber_foshk.pl $verboseOpt");
    $log->open;
} else {
    LOGDEB 'FOSHKplugin grabber is disabled. Skipping.';
}

if ($pcfg->param('SERVER.PWSCATCHUPLOADGRABBER')) {
    LOGINF 'Starting grabber_pwscatchupload.pl';
    $log->close;
    system("$lbpbindir/grabber_pwscatchupload.pl $verboseOpt");
    $log->open;
} else {
    LOGDEB 'PWSCatchUpload grabber is disabled. Skipping.';
}

if ($pcfg->param('SERVER.LOXGRABBER')) {
    LOGINF 'Starting grabber_loxone.pl';
    $log->close;
    system("$lbpbindir/grabber_loxone.pl $verboseOpt");
    $log->open;
} else {
    LOGDEB 'Loxone grabber is disabled. Skipping.';
}

exit;

END
{
    LOGOK 'Done';
    LOGEND;
}
