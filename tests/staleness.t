#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../bin/lib";
use File::Temp qw(tempdir);
use Time::Local qw(timegm timelocal);
use Weather4Lox::Staleness qw(parse_generated_at role_intervals check_staleness stale_flags read_state write_state);

# generatedAt is written with offset (localtime with %z) or without offset (local time)
is(parse_generated_at('2026-10-25T17:58:01+01:00'), timegm(1, 58, 16, 25, 9, 2026), 'offset with colon');
is(parse_generated_at('2026-10-25T17:58:01+0100'), timegm(1, 58, 16, 25, 9, 2026), 'offset without colon');
is(parse_generated_at('2026-10-25T16:58:01Z'), timegm(1, 58, 16, 25, 9, 2026), 'UTC');
is(parse_generated_at('2026-10-25T17:56:34'), timelocal(34, 56, 17, 25, 9, 2026), 'without offset means local time');
is(parse_generated_at($_), undef, "invalid value '" . ($_ // 'undef') . "'") for (undef, '', 'yesterday', '2026-13-45T99:00:00');

sub params {
    my %cfg = @_;
    return sub { $cfg{$_[0]} };
}

is_deeply(role_intervals(params()), {
    'current.primary' => 60, 'dailyforecast.primary' => 60, 'hourlyforecast.primary' => 60,
}, 'only the primary services are checked by default, CRON defaults to 60');

is_deeply(role_intervals(params(
    'SERVER.CRON' => 15, 'SERVER.CRON_ALTERNATE' => 60, 'SERVER.USEALTERNATEDFC' => 1, 'SERVER.USEALTERNATEHFC' => 0,
    'SERVER.WUGRABBER' => 1, 'SERVER.CRON_LOCAL' => 30,
    'SERVER.LOXGRABBER' => 1,
    'SERVER.OPENMETEOAIRQUALITYGRABBER' => 1, 'SERVER.CRON_AIRQUALITY' => 0,
)), {
    'current.primary' => 15, 'dailyforecast.primary' => 60, 'hourlyforecast.primary' => 15,
    'current.nearbyStation' => 30, 'current.localStation' => 1, 'airQuality' => 15,
}, 'each role uses the interval of the service writing it (0 = interval of the default service)');

is(role_intervals(params('SERVER.CRON' => 15, 'SERVER.USEALTERNATEDFC' => 1))->{'dailyforecast.primary'}, 15,
    'alternate service without own interval uses the default interval');
is(role_intervals(params('SERVER.PWSCATCHUPLOADGRABBER' => 1))->{'current.localStation'}, 1, 'WU upload catcher is a local station');
is(role_intervals(params('SERVER.FOSHKGRABBER' => 1))->{'current.localStation'}, 1, 'FOSHK is a local station');

my $now = timegm(0, 0, 18, 25, 9, 2026);
sub at {
    my ($minutesAgo) = @_;
    my @t = gmtime($now - $minutesAgo * 60);
    return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', $t[5] + 1900, $t[4] + 1, @t[3, 2, 1, 0]);
}
sub section {
    my ($role, $minutesAgo) = @_;
    return { role => $role, generatedAt => at($minutesAgo), grabberScript => "grabber_$role.pl" };
}

my $intervals = {
    'current.primary' => 15, 'dailyforecast.primary' => 60, 'hourlyforecast.primary' => 15,
    'current.nearbyStation' => 30, 'current.localStation' => 1, 'airQuality' => 15,
};
my $files = {
    current => {
        generatedAt   => at(0),
        wetteronline  => section('primary', 50),
        wunderground  => section('nearbyStation', 5),
        foshk         => section('localStation', 0),
        openmeteoAq   => section('airQuality', 5),
    },
    dailyforecast  => { visualcrossing => section('primary', 170), openmeteoAq => section('airQuality', 5) },
    hourlyforecast => { openweather => section('primary', 5), openmeteoAq => section('airQuality', 5) },
};
my $state = {};
my $result = check_staleness($files, $intervals, $state, $now);
is($result->{'current.primary'}{age}, 50, 'age is taken from generatedAt of the primary section, not from the top level');
is($result->{'current.primary'}{threshold}, 45, 'threshold is 3x the interval');
is($result->{'current.primary'}{stale}, 1, 'primary of current is stale after more than 3x its interval');
is($result->{'dailyforecast.primary'}{stale},0, 'alternate daily service is checked against its own interval');
is($result->{'hourlyforecast.primary'}{stale}, 0, 'fresh hourly forecast is not stale');
is($result->{'current.localStation'}{threshold}, 10, 'local stations use a minimum threshold of 10 minutes');
is($state->{'current.primary'}, $now - 50 * 60, 'last seen time stamps are kept in the state');

my $flags = stale_flags($result);
is_deeply($flags, {
    cur_primaryStale => 1, dfc_primaryStale => 0, hfc_primaryStale => 0,
    cur_nearbyStationStale => 0, cur_localStationStale => 0, aq_stale => 0,
    cur_stale => 1, dfc_stale => 0, hfc_stale => 0, any_stale => 1,
}, 'flags per role and summaries');

# The primary service rewrites the whole file, so station sections vanish until the station runs again
my $later = $now + 20 * 60;
$files->{current} = { wetteronline => { role => 'primary', generatedAt => at(-20) } };
$result = check_staleness($files, $intervals, $state, $later);
is($result->{'current.nearbyStation'}{age}, 25, 'missing station section falls back to the last seen time stamp');
is($result->{'current.nearbyStation'}{stale}, 0, 'missing section within the threshold is not stale');
is($result->{'current.localStation'}{age}, 20, 'local station age continues from the state');
is($result->{'current.localStation'}{stale}, 1, 'local station missing for 20 minutes is stale');
is($result->{'current.primary'}{stale}, 0, 'new primary data clears the flag');
is(stale_flags($result)->{cur_stale}, 1, 'cur_stale is set if any service writing current is stale');
is(stale_flags($result)->{hfc_stale}, 0, 'station problems do not affect the forecast summaries');

# A role that was never seen starts counting when it is configured
$state = {};
$result = check_staleness({ current => {}, dailyforecast => {}, hourlyforecast => {} }, $intervals, $state, $now);
is($result->{'current.primary'}{age}, 0, 'never seen role starts with age 0');
is($state->{'airQuality'}, $now, 'never seen role is remembered from now on');
$result = check_staleness({ current => {}, dailyforecast => {}, hourlyforecast => {} }, $intervals, $state, $now + 50 * 60);
is($result->{'current.primary'}{stale}, 1, 'role that never delivers becomes stale');

# Air quality is stale only if no file contains a recent section
$files = {
    current        => { openmeteoAq => section('airQuality', 60) },
    dailyforecast  => { openmeteoAq => section('airQuality', 10) },
    hourlyforecast => {},
};
$result = check_staleness($files, { airQuality => 15 }, {}, $now);
is($result->{airQuality}{age}, 10, 'air quality uses its most recent section in any file');
is_deeply(stale_flags($result), {
    cur_primaryStale => 0, dfc_primaryStale => 0, hfc_primaryStale => 0,
    cur_nearbyStationStale => 0, cur_localStationStale => 0, aq_stale => 0,
    cur_stale => 0, dfc_stale => 0, hfc_stale => 0, any_stale => 0,
}, 'roles that are not configured are never stale');
$result = check_staleness($files, { airQuality => 1 }, {}, $now + 5 * 60);
is_deeply([ @{ stale_flags($result) }{qw(aq_stale cur_stale dfc_stale hfc_stale any_stale)} ], [1, 1, 1, 1, 1],
    'air quality is part of all summaries, as it writes to all files');

# Deactivated roles are removed from the state
$state = { 'current.localStation' => $now - 3600, 'current.primary' => $now };
check_staleness({ current => {} }, { 'current.primary' => 15 }, $state, $now);
is_deeply([ sort keys %$state ], ['current.primary'], 'state of deactivated roles is removed');

# Unknown roles and invalid time stamps are ignored
$result = check_staleness({ current => {
    other => { role => 'somethingNew', generatedAt => at(500) },
    bad   => { role => 'primary', generatedAt => 'invalid' },
    good  => { role => 'primary', generatedAt => at(3) },
} }, { 'current.primary' => 15 }, {}, $now);
is($result->{'current.primary'}{age}, 3, 'invalid time stamps and unknown roles are ignored');

# State file
my $dir = tempdir(CLEANUP => 1);
is_deeply(read_state("$dir/missing.json"), {}, 'missing state file means empty state');
write_state("$dir/state.json", { 'current.primary' => 123 });
is_deeply(read_state("$dir/state.json"), { 'current.primary' => 123 }, 'state survives round trip');
ok(!-e "$dir/state.json.tmp", 'state file is replaced atomically');
open(my $fh, '>', "$dir/broken.json") or die $!;
print {$fh} '{broken';
close($fh);
is_deeply(read_state("$dir/broken.json"), {}, 'broken state file means empty state');

done_testing();
