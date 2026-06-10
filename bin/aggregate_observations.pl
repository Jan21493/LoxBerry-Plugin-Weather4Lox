#!/usr/bin/perl

# aggregate_observations.pl
# Aggregates local SQLite observations into hourly and daily JSON files.

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

require "$lbpbindir/grabber_utils.pl";
require "$lbpbindir/observation_buffer.pl";

my $version = LoxBerry::System::pluginversion();
my $timezone = _systemTimezone();

my $hourly = 0;
my $daily = 0;
my $verbose = '';

GetOptions(
    'hourly'  => \$hourly,
    'daily'   => \$daily,
    'verbose' => \$verbose,
    'quiet'   => sub { $verbose = 0 },
);

if (!$hourly && !$daily) {
    $hourly = 1;
    $daily = 1;
}

my $log = LoxBerry::Log->new(
    package => 'weather4lox',
    name    => 'aggregate_observations',
    logdir  => "$lbplogdir",
);

if ($verbose) {
    $log->stdout(1);
    $log->loglevel(7);
}

LOGSTART "Weather4Lox AGGREGATE_OBSERVATIONS process";
LOGDEB "This is $0 Version $version";

my $dbPath = "$lbpdatadir/observations.db";
if (!-e $dbPath) {
    LOGWARN "Observation database not found at $dbPath. Skipping aggregation.";
    exit 0;
}

my $dbh = initObsDb($dbPath);
my $hourlyData = aggregateHourly($dbh);
my $dailyData = aggregateDaily($hourlyData, $timezone);

my $generatedAt = _epochToIso(time(), $timezone);
my $currentEnvelope = readJsonFile($lbplogdir, 'current');
my $location = $currentEnvelope ? $currentEnvelope->{location} : undef;

if ($hourly) {
    my @hourlyObs;
    my $hourIndex = 0;

    for my $row (sort { ($b->{time}{epoch} // 0) <=> ($a->{time}{epoch} // 0) } @{$hourlyData // []}) {
        my $windDirection = $row->{windDirAvg};

        push @hourlyObs, {
            hour         => $hourIndex,
            time         => {
                epoch    => $row->{time}{epoch},
                datetime => _epochToIso($row->{time}{epoch}, $timezone),
            },
            temperature  => {
                air => $row->{tempAvg},
                min => $row->{tempMin},
                max => $row->{tempMax},
            },
            humidity     => $row->{humidityAvg},
            pressure     => $row->{pressureAvg},
            wind         => {
                speed     => $row->{windSpeedAvg},
                gust      => defined $row->{windGustMax} ? $row->{windGustMax} : $row->{windGustAvg},
                direction => $windDirection,
                cardinal  => getWindDirCardinal($windDirection),
            },
            precipitation => {
                rain1hr => $row->{precipAvg},
            },
            dewpoint       => $row->{dewpointAvg},
            cloudCover     => $row->{cloudCoverAvg},
            uvIndex        => $row->{uvIndexAvg},
            solarRadiation => $row->{solarRadAvg},
            weatherCode    => {
                weather4lox => $row->{icon},
            },
        };

        $hourIndex++;
    }

    my $envelope = {
        generatedAt           => $generatedAt,
        refresh               => 60,
        location              => $location,
        aggregateObservations => {
            filename      => "$lbplogdir/hourlyobservations.json",
            generatedAt   => $generatedAt,
            grabberLabel  => 'Aggregated local observations',
            grabberScript => 'aggregate_observations.pl',
            schemaVersion => 'v1.0',
        },
        hourlyobservations => \@hourlyObs,
    };

    writeJsonFile($lbplogdir, 'hourlyobservations', $envelope);
    LOGOK 'Hourly observations aggregated successfully.';
}

if ($daily) {
    my @dailyObs;
    my $dayIndex = 0;

    for my $row (sort { ($b->{time}{epoch} // 0) <=> ($a->{time}{epoch} // 0) } @{$dailyData // []}) {
        my $windDirection = $row->{windDirAvg};

        push @dailyObs, {
            day          => $dayIndex,
            time         => {
                epoch    => $row->{time}{epoch},
                datetime => _epochToIsoDate($row->{time}{epoch}, $timezone),
            },
            temperature  => {
                air => $row->{tempAvg},
                min => $row->{tempMin},
                max => $row->{tempMax},
            },
            humidity     => $row->{humidityAvg},
            pressure     => $row->{pressureAvg},
            wind         => {
                speed     => $row->{windSpeedAvg},
                gust      => defined $row->{windGustMax} ? $row->{windGustMax} : $row->{windGustAvg},
                direction => $windDirection,
                cardinal  => getWindDirCardinal($windDirection),
            },
            precipitation => {
                rain1hr => $row->{precipAvg},
            },
            dewpoint       => $row->{dewpointAvg},
            cloudCover     => $row->{cloudCoverAvg},
            uvIndex        => $row->{uvIndexAvg},
            solarRadiation => $row->{solarRadAvg},
            weatherCode    => {
                weather4lox => $row->{icon},
            },
        };

        $dayIndex++;
    }

    my $envelope = {
        generatedAt           => $generatedAt,
        refresh               => 60,
        location              => $location,
        aggregateObservations => {
            filename      => "$lbplogdir/dailyobservations.json",
            generatedAt   => $generatedAt,
            grabberLabel  => 'Aggregated local observations',
            grabberScript => 'aggregate_observations.pl',
            schemaVersion => 'v1.0',
        },
        dailyobservations => \@dailyObs,
    };

    writeJsonFile($lbplogdir, 'dailyobservations', $envelope);
    LOGOK 'Daily observations aggregated successfully.';
}

$dbh->disconnect();

exit;

END
{
    LOGOK 'Done';
    LOGEND;
}
