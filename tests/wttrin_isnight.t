#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use JSON::PP;
use Time::Local qw(timegm);
use POSIX qw(strftime);
use LoxBerry::System;
use LoxBerry::Log;
use LWP::UserAgent;
use HTTP::Response;
use Config::Simple;

sub read_file {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or die "Cannot read $path: $!";
    local $/;
    return <$fh>;
}

my $source = read_file("$FindBin::Bin/../bin/grabber_wttrin.pl");
my ($helpers) = $source =~ /(# wttr\.in astronomy times.*?)(?=# Get weather data from WTTR.in)/s;
die 'Cannot find wttr.in day/night helpers' unless $helpers;
{
    package WttrinNightTest;
    our @warnings;
    sub LOGWARN { push @warnings, $_[0] }
}
eval "package WttrinNightTest; $helpers";
die $@ if $@;

for my $case (
    ['12:00 AM', '00:00'], ['12:00 PM', '12:00'],
    ['07:03 AM', '07:03'], ['07:45 PM', '19:45'], ['1:05 PM', '13:05'],
) {
    is(WttrinNightTest::sunTime($case->[0], '2026-10-24', 'sunrise'),
        $case->[1], "parses $case->[0]");
}
for my $value (undef, '', 'No sunrise', '00:30 AM', '13:30 PM', '07:60 AM') {
    my $before = @WttrinNightTest::warnings;
    is(WttrinNightTest::sunTime($value, '2026-10-24', 'sunrise'), undef,
        'missing/invalid sun time stays unknown');
    is(scalar @WttrinNightTest::warnings, $before + 1, 'invalid sun time logs a warning');
}

my %sunTimes = (
    '2026-10-24' => { sunrise => '07:00', sunset => '18:30' },
    '2026-10-25' => { sunrise => '07:05', sunset => '18:25' },
    '2026-10-26' => { sunrise => '23:00', sunset => '01:00' },
    '2026-10-27' => { sunrise => undef, sunset => '18:00' },
    '2026-10-28' => { sunrise => '00:00', sunset => '00:00' },
);
for my $case (
    ['2026-10-24T00:00:00+02:00', 1],
    ['2026-10-24T06:59:59+02:00', 1],
    ['2026-10-24T07:00:00+02:00', undef],
    ['2026-10-24T12:00:00+02:00', undef],
    ['2026-10-24T18:30:00+02:00', undef],
    ['2026-10-24T18:30:01+02:00', 1],
    ['2026-10-24T23:59:59+02:00', 1],
    ['2026-10-25T07:00:00+01:00', 1],
    ['2026-10-25T07:05:00+01:00', undef],
    ['2026-10-26T00:30:00+01:00', undef],
    ['2026-10-26T12:00:00+01:00', 1],
    ['2026-10-26T23:00:00+01:00', undef],
) {
    is(WttrinNightTest::isNighttime($case->[0], \%sunTimes), $case->[1],
        "day/night at $case->[0]");
}
for my $date (qw(2026-10-27 2026-10-28 2026-10-29)) {
    my $before = @WttrinNightTest::warnings;
    is(WttrinNightTest::isNighttime("${date}T12:00:00+01:00", \%sunTimes), undef,
        'missing day or ambiguous astronomy stays unknown');
    is(scalar @WttrinNightTest::warnings, $before + 1, 'unknown day/night logs a warning');
}

# Run the complete grabber with real SDK/helpers, but no live API or production writes.
my $root = tempdir(CLEANUP => 1);
my $installedHome = $LoxBerry::System::lbhomedir;
make_path("$root/log/system_tmpfs", "$root/config", "$root/data");
symlink("$installedHome/config/system", "$root/config/system") or die $!;
symlink("$installedHome/data/system", "$root/data/system") or die $!;
my $json = JSON::PP->new->utf8;
my @days;
for my $day (24 .. 26) {
    my @hours;
    for (my $hour = 0; $hour < 24; $hour += 3) {
        push @hours, {
            time => $hour * 100, tempC => 12, FeelsLikeC => 11,
            humidity => 70, winddirDegree => 180, windspeedKmph => 10,
            WindGustKmph => 15, pressure => 1015, DewPointC => 8,
            cloudcover => 20, uvIndex => 1, HeatIndexC => 12,
            precipMM => 0, chanceofrain => 0, weatherCode => 113,
            weatherDesc => [{ value => 'Clear' }], visibility => 10,
        };
    }
    push @days, {
        date => "2026-10-$day", hourly => \@hours,
        maxtempC => 15, mintempC => 8, totalSnow_cm => 0, uvIndex => 1,
        astronomy => [{
            sunrise => $day == 24 ? '07:00 AM' : '08:00 AM',
            sunset => $day == 24 ? '06:30 PM' : '05:30 PM',
            moonrise => '08:00 PM', moonset => '06:00 AM',
        }],
    };
}

for my $scenario (qw(night day)) {
    my $dir = "$root/$scenario";
    make_path($dir);
    my $fixture = {
        nearest_area => [{
            latitude => 52, longitude => 13,
            areaName => [{ value => 'Test' }], country => [{ value => 'Germany' }],
        }],
        current_condition => [{
            %{$days[0]{hourly}[0]}, temp_C => 12, FeelsLikeC => 11,
            observation_time => $scenario eq 'night' ? '04:59 AM' : '10:00 AM',
        }],
        weather => \@days,
    };
    my $pid = fork();
    die "Cannot fork: $!" unless defined $pid;
    if (!$pid) {
        $ENV{TZ} = 'Europe/Berlin';
        POSIX::tzset();
        $ENV{LBHOMEDIR} = $root;
        $LoxBerry::System::lbhomedir = $root;
        $LoxBerry::System::lbplogdir = $dir;
        $LoxBerry::System::lbpbindir = "$FindBin::Bin/../bin";
        $LoxBerry::System::lbpconfigdir = "$installedHome/config/plugins/weather4lox";
        {
            no warnings 'redefine';
            *LWP::UserAgent::get = sub {
                return HTTP::Response->new(200, 'OK', [], $json->encode($fixture));
            };
        }
        @ARGV = qw(--current --daily --hourly);
        my $script = $source;
        my $now = timegm(0, 30, 22, 23, 9, 2026); # Oct 24, 00:30 in Berlin
        $script =~ s/\btime\(\)/$now/g;
        eval $script;
        die $@ if $@;
        exit 1;
    }
    waitpid($pid, 0);
    is($?, 0, "$scenario: complete grabber run succeeds");
    my $current = $json->decode(read_file("$dir/current.json"))->{current};
    is($current->{isNight}, $scenario eq 'night' ? 1 : undef,
        "$scenario: current isNight uses observation time");
    is($current->{sunrise}, '07:00', "$scenario: current sunrise preserved");
    is($current->{sunset}, '18:30', "$scenario: current sunset preserved");
    my $daily = $json->decode(read_file("$dir/dailyforecast.json"))->{dailyforecast};
    my %byDate = map { substr($_->{time}{datetime}, 0, 10) => $_ } @$daily;
    my $hourly = $json->decode(read_file("$dir/hourlyforecast.json"))->{hourlyforecast};
    ok(@$hourly > 48, "$scenario: includes interpolated hours over multiple dates and DST");
    my %seen;
    for my $entry (@$hourly) {
        my $datetime = $entry->{time}{datetime};
        my $date = substr($datetime, 0, 10);
        my $day = $byDate{$date};
        my $clock = substr($datetime, 11, 8);
        my $expected = $clock lt "$day->{sunrise}:00" || $clock gt "$day->{sunset}:00" ? 1 : undef;
        is($entry->{isNight}, $expected, "$scenario: hourly $datetime uses its own day's sun times");
        $seen{defined $entry->{isNight} ? 'night' : 'day'}++;
        $seen{substr($datetime, -6)}++;
    }
    ok($seen{day} && $seen{night}, "$scenario: hourly output contains both day and night");
    ok($seen{'+02:00'} && $seen{'+01:00'}, "$scenario: handles both DST offsets");
}

done_testing();
