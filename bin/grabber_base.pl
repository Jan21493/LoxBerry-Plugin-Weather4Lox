#!/usr/bin/perl

# grabber_base.pl – shared initialisation helper for Weather4Lox grabbers
#
# Usage in a grabber (after the shebang, use strict/warnings and module imports):
#
#   require "$lbpbindir/grabber_utils.pl";
#   require "$lbpbindir/grabber_base.pl";
#
#   my $g = init_grabber(
#       name         => 'openweather',   # section name in weather4lox.cfg
#       label        => 'OpenWeather',   # human-readable label for log messages
#       version_ref  => \$version,       # ref to version scalar
#       refresh_ref  => \$refresh,       # ref to refresh/interval scalar
#       log          => \$log,           # ref to log object variable
#       verbose_ref  => \$verbose,       # ref to verbose flag
#       maskkeys_ref => \$maskkeys,      # ref to maskkeys flag
#       current_ref  => \$current,       # ref to --current flag  (optional)
#       daily_ref    => \$daily,         # ref to --daily flag    (optional)
#       hourly_ref   => \$hourly,        # ref to --hourly flag   (optional)
#   );
#   # After init_grabber:
#   # - $log     is a ready LoxBerry::Log object (loglevel set per --verbose)
#   # - $verbose / $maskkeys / $current / $daily / $hourly are populated from CLI
#   # - $refresh is set from --interval if provided
#   # - %L (language hash) is populated in the caller's namespace
#   # - $g->{timezone} is the IANA timezone string (from env / /etc/timezone)
#   # - $g->{pcfg}     is the Config::Simple object for weather4lox.cfg

# Copyright 2026 Jan Wachsmuth, janw@email.de
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

# LoxBerry globals provided by `use LoxBerry::System` in the calling grabber.
# Declared here so grabber_base.pl can reference them under `use strict`.
our ($lbpconfigdir, $lbplogdir, $lbpplugindir, $lbphomedir);

##########################################################################
# init_grabber – one-call initialisation for a grabber
#
# Returns a hashref with:
#   {timezone}  IANA timezone string
#   {pcfg}      Config::Simple object for weather4lox.cfg

sub init_grabber {
    my (%p) = @_;

    my $name        = $p{name}         // 'grabber';
    my $label       = $p{label}        // $name;
    my $version_ref = $p{version_ref}  // \(my $_ver = '');
    my $refresh_ref = $p{refresh_ref}  // \(my $_ref = 60);
    my $log_ref     = $p{log}          // \(my $_log);
    my $verbose_ref = $p{verbose_ref}  // \(my $_verbose = 0);
    my $maskkeys_ref= $p{maskkeys_ref} // \(my $_mask = 1);
    my $current_ref = $p{current_ref}  // \(my $_cur  = 0);
    my $daily_ref   = $p{daily_ref}    // \(my $_dfc  = 0);
    my $hourly_ref  = $p{hourly_ref}   // \(my $_hfc  = 0);

    # ── Config ──────────────────────────────────────────────────────────────
    my $pcfg = new Config::Simple("$lbpconfigdir/weather4lox.cfg");

    # ── Logging ─────────────────────────────────────────────────────────────
    $$log_ref = LoxBerry::Log->new(
        package => 'weather4lox',
        name    => "grabber_$name",
        logdir  => "$lbplogdir",
    );

    # ── CLI options ──────────────────────────────────────────────────────────
    Getopt::Long::GetOptions(
        'verbose'    => $verbose_ref,
        'quiet'      => sub { $$verbose_ref = 0 },
        'current'    => $current_ref,
        'daily'      => $daily_ref,
        'hourly'     => $hourly_ref,
        'maskkeys'   => $maskkeys_ref,
        'interval=i' => $refresh_ref,
    );

    if ($$verbose_ref) {
        $$log_ref->stdout(1);
        $$log_ref->loglevel(7);
    }

    LOGSTART "Weather4Lox $label GRABBER process started";
    LOGDEB "This is $0 Version $$version_ref";

    # ── Language ─────────────────────────────────────────────────────────────
    # Populate the caller's %L hash with localized strings.
    # LoxBerry::System::readlanguage returns a hash, so we assign into %main::L.
    %main::L = LoxBerry::System::readlanguage("language.ini");

    # ── System timezone ──────────────────────────────────────────────────────
    my $timezone = $ENV{TZ} // '';
    if (!$timezone) {
        if (open my $tzfh, '<:encoding(UTF-8)', '/etc/timezone') {
            $timezone = <$tzfh>;
            chomp $timezone if defined $timezone;
            close $tzfh;
        }
    }
    if (!$timezone || !-f "/usr/share/zoneinfo/$timezone") {
        $timezone = 'UTC';
    }

    return {
        timezone => $timezone,
        pcfg     => $pcfg,
    };
}


1; # end of module
