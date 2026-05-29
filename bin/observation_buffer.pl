#!/usr/bin/perl

# observation_buffer.pl
# Shared helper functions for storing and aggregating local observations.

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

use DBI;
use DateTime;

sub initObsDb {
    my ($dbPath) = @_;

    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=$dbPath",
        '',
        '',
        {
            RaiseError => 1,
            PrintError => 0,
            AutoCommit => 1,
        }
    );

    $dbh->do('PRAGMA journal_mode = WAL');
    $dbh->do('PRAGMA synchronous = NORMAL');

    $dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS observations (
    epoch       INTEGER NOT NULL,
    source      TEXT    NOT NULL,
    temp        REAL,
    feelsLike   REAL,
    humidity    REAL,
    pressure    REAL,
    windSpeed   REAL,
    windGust    REAL,
    windDir     REAL,
    precip      REAL,
    snow        REAL,
    dewpoint    REAL,
    cloudCover  REAL,
    uvIndex     REAL,
    solarRad    REAL,
    icon        TEXT,
    PRIMARY KEY (epoch, source)
)
SQL

    return $dbh;
}

sub storeObservation {
    my ($dbh, $retentionHours, %data) = @_;

    $retentionHours = 72 if (!defined $retentionHours || $retentionHours !~ /^\d+$/ || $retentionHours <= 0);

    my $epoch = defined $data{epoch} ? int($data{epoch}) : time();
    my $source = defined $data{source} ? $data{source} : 'unknown';

    my $insertSql = <<'SQL';
INSERT OR REPLACE INTO observations (
    epoch, source, temp, feelsLike, humidity, pressure,
    windSpeed, windGust, windDir, precip, snow, dewpoint,
    cloudCover, uvIndex, solarRad, icon
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
SQL

    $dbh->do(
        $insertSql,
        undef,
        $epoch,
        $source,
        $data{temp},
        $data{feelsLike},
        $data{humidity},
        $data{pressure},
        $data{windSpeed},
        $data{windGust},
        $data{windDir},
        $data{precip},
        $data{snow},
        $data{dewpoint},
        $data{cloudCover},
        $data{uvIndex},
        $data{solarRad},
        $data{icon},
    );

    my $minEpoch = time() - ($retentionHours * 3600);
    $dbh->do('DELETE FROM observations WHERE epoch < ?', undef, $minEpoch);
}

sub aggregateHourly {
    my ($dbh) = @_;

    my %sourcePriority = (
        foshk         => 1,
        loxone        => 1,
        wu_pws        => 2,
        wunderground  => 2,
        pwscatchupload => 2,
        visualcrossing => 3,
    );

    my $rows = $dbh->selectall_arrayref(
        'SELECT * FROM observations ORDER BY epoch ASC',
        { Slice => {} },
    );

    my %hoursBySource;
    for my $row (@$rows) {
        my $hourEpoch = int($row->{epoch} / 3600) * 3600;
        push @{ $hoursBySource{$hourEpoch}{ $row->{source} } }, $row;
    }

    my @numericFields = qw(temp feelsLike humidity pressure windSpeed windGust windDir precip snow dewpoint cloudCover uvIndex solarRad);
    my @hourlyData;

    for my $hourEpoch (sort { $a <=> $b } keys %hoursBySource) {
        my @sources = sort {
            ($sourcePriority{$a} // 99) <=> ($sourcePriority{$b} // 99)
            || $a cmp $b
        } keys %{ $hoursBySource{$hourEpoch} };

        next if !@sources;

        my $selectedSource = $sources[0];
        my $sourceRows = $hoursBySource{$hourEpoch}{$selectedSource};
        my %hour;

        $hour{time}{epoch} = $hourEpoch;
        $hour{source} = $selectedSource;

        for my $field (@numericFields) {
            my @values = map { $_->{$field} } grep { defined $_->{$field} } @$sourceRows;
            next if !@values;

            my $sum = 0;
            $sum += $_ for @values;

            my $prefix = $field;
            $hour{"${prefix}Min"} = (sort { $a <=> $b } @values)[0] + 0;
            $hour{"${prefix}Max"} = (sort { $b <=> $a } @values)[0] + 0;
            $hour{"${prefix}Avg"} = $sum / scalar(@values);
        }

        my ($latestRow) = sort { ($b->{epoch} // 0) <=> ($a->{epoch} // 0) } @$sourceRows;
        $hour{icon} = $latestRow->{icon};

        push @hourlyData, \%hour;
    }

    return \@hourlyData;
}

sub aggregateDaily {
    my ($hourlyData, $timezone) = @_;

    $timezone = 'local' if !$timezone;

    my %days;
    for my $hour (@{$hourlyData // []}) {
        my $epoch = $hour->{time}{epoch};
        next if !defined $epoch;

        my $dt = DateTime->from_epoch(
            epoch     => $epoch,
            time_zone => $timezone,
        );

        my $dayStart = DateTime->new(
            year      => $dt->year,
            month     => $dt->month,
            day       => $dt->day,
            hour      => 0,
            minute    => 0,
            second    => 0,
            time_zone => $timezone,
        );

        my $dayEpoch = $dayStart->epoch;
        push @{ $days{$dayEpoch} }, $hour;
    }

    my @baseFields = qw(temp feelsLike humidity pressure windSpeed windGust windDir precip snow dewpoint cloudCover uvIndex solarRad);
    my @dailyData;

    for my $dayEpoch (sort { $a <=> $b } keys %days) {
        my $hours = $days{$dayEpoch};
        my %day;

        $day{time}{epoch} = $dayEpoch;

        for my $field (@baseFields) {
            my @mins = map { $_->{"${field}Min"} } grep { defined $_->{"${field}Min"} } @$hours;
            my @maxs = map { $_->{"${field}Max"} } grep { defined $_->{"${field}Max"} } @$hours;
            my @avgs = map { $_->{"${field}Avg"} } grep { defined $_->{"${field}Avg"} } @$hours;

            if (@mins) {
                $day{"${field}Min"} = (sort { $a <=> $b } @mins)[0] + 0;
            }
            if (@maxs) {
                $day{"${field}Max"} = (sort { $b <=> $a } @maxs)[0] + 0;
            }
            if (@avgs) {
                my $sum = 0;
                $sum += $_ for @avgs;
                $day{"${field}Avg"} = $sum / scalar(@avgs);
            }
        }

        my ($latestHour) = sort {
            ($b->{time}{epoch} // 0) <=> ($a->{time}{epoch} // 0)
        } @$hours;
        $day{icon} = $latestHour->{icon};

        push @dailyData, \%day;
    }

    return \@dailyData;
}

1;
