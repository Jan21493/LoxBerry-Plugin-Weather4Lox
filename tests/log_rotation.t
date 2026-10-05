#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use FindBin;
use Time::Local qw(timelocal);
use LoxBerry::System;
use LoxBerry::Log;

require "$FindBin::Bin/../bin/weather4lox_log.pl";

# Exercise the installed SDK without touching production logs or their database.
my $root = tempdir(CLEANUP => 1);
my $sdk_home = $LoxBerry::System::lbhomedir;
make_path("$root/log/system_tmpfs", "$root/data", "$root/config");
symlink($LoxBerry::System::lbsdatadir, "$root/data/system") or die $!;
symlink($LoxBerry::System::lbsconfigdir, "$root/config/system") or die $!;
local $LoxBerry::System::lbhomedir = $root;
local $ENV{LBHOMEDIR} = $root;
my $plugin = LoxBerry::System::plugindata('weather4lox');
my $level = 6;
no warnings 'redefine';
local *LoxBerry::System::plugindata = sub {
    return { %$plugin, PLUGINDB_LOGLEVEL => $level };
};
use warnings 'redefine';

my $morning = timelocal(0, 10, 9, 4, 9, 2026);
my $same_hour = $morning + 1200;
my $next_hour = $morning + 3600;
my $next_day = $morning + 86400;
my $message = 'Weather4Lox test process started';

sub start_log {
    my ($name, $now, %extra) = @_;
    return startWeatherLog(
        package => 'weather4lox', name => $name, logdir => "$root/logs",
        message => $message, now => $now, %extra
    );
}

sub finish_run {
    my ($log) = @_;
    $log->OK('END OF: test. We are done. Good bye.');
    $log->DESTROY;
}

sub content {
    my ($file) = @_;
    open(my $fh, '<', $file) or die "Cannot read $file: $!";
    local $/;
    return <$fh>;
}

sub marker_count {
    my ($file, $marker) = @_;
    return scalar(() = content($file) =~ /\Q$marker\E/g);
}

my $log = start_log('Data to Loxone', $morning);
my $daily_file = $log->filename;
my $daily_key = $log->dbkey;
like($daily_file, qr{/2026-10-04_Data to Loxone\.log$}, 'daily filename preserves group');
like(content($daily_file), qr/\Q$message\E, starting from 2026-10-04 09:10:00/,
    'original start message gains a date');
$log->ERR('First run failed');
finish_run($log);
$log = start_log('Data to Loxone', $next_hour);
is($log->filename, $daily_file, 'non-debug runs in different hours share a file');
is($log->dbkey, $daily_key, 'append reuses the database session');
is($log->{STATUS}, 3, 'append preserves earlier errors');
finish_run($log);
is(marker_count($daily_file, 'TASK STARTED'), 1, 'daily file has one header');
is(marker_count($daily_file, 'TASK FINISHED'), 0, 'run completion leaves the file open');
$log = start_log('Data to Loxone', $next_day);
finish_run($log);
is(marker_count($daily_file, 'TASK FINISHED'), 1, 'daily rotation ends the previous file');
$log = start_log('Data to Loxone', $next_day + 60);
finish_run($log);
is(marker_count($daily_file, 'TASK FINISHED'), 1, 'append does not end the previous file again');

for my $configured (0 .. 6) {
    $level = $configured;
    $log = start_log("Level$configured", $morning);
    like($log->filename, qr{/2026-10-04_Level\d\.log$},
        "level $configured selects a daily filename");
    finish_run($log);
}

$level = 7;
$log = start_log('OpenWeather', $morning);
my $hourly_file = $log->filename;
like($hourly_file, qr{/2026-10-04_09_OpenWeather\.log$}, 'debug selects an hourly file');
finish_run($log);
$log = start_log('OpenWeather', $same_hour);
is($log->filename, $hourly_file, 'debug runs within the hour append');
finish_run($log);
is(marker_count($hourly_file, 'TASK STARTED'), 1, 'hourly file has one header');
$log = start_log('OpenWeather', $next_hour);
finish_run($log);
is(marker_count($hourly_file, 'TASK FINISHED'), 1, 'hourly rotation ends the previous file');

$level = 6;
$log = start_log('fetch', $morning, verbose => 1);
like($log->filename, qr{/2026-10-04_09_fetch\.log$}, 'verbose overrides the configured level');
is($log->loglevel, 7, 'verbose logs at debug level');
finish_run($log);

for my $debug (0, 1) {
    $level = $debug ? 7 : 6;
    $log = start_log("Emulator$debug", $morning, daily => 1, verbose => $debug);
    my $file = $log->filename;
    like($file, qr{/2026-10-04_Emulator\d\.log$}, 'emulator uses a daily filename');
    finish_run($log);
    $log = start_log("Emulator$debug", $next_hour, daily => 1, verbose => $debug);
    is($log->filename, $file, 'emulator appends across hours, also in debug');
    finish_run($log);
}

$level = 6;
$log = start_log('Mode switch', $morning);
my $before_switch = $log->filename;
finish_run($log);
$level = 7;
$log = start_log('Mode switch', $next_hour);
finish_run($log);
is(marker_count($before_switch, 'TASK FINISHED'), 1, 'debug mode change closes the daily log');
$level = 6;
$log = start_log('Mode switch', $next_hour + 60);
is($log->filename, $before_switch, 'switching back reuses the existing daily file');
finish_run($log);
$level = 7;
$log = start_log('Mode switch', $next_hour + 3600);
finish_run($log);
is(marker_count($before_switch, 'TASK FINISHED'), 2,
    'rotation ends the previous file even when it was reused after a mode change');

my $legacy = "$root/logs/20261003_090000_123_Legacy.log";
$log = LoxBerry::Log->new(
    package => 'weather4lox', name => 'Legacy', filename => $legacy
);
$log->LOGSTART('Legacy session');
finish_run($log);
$log = start_log('Legacy', $morning);
finish_run($log);
is(marker_count($legacy, 'TASK FINISHED'), 1, 'upgrade closes an existing legacy log');

# Concurrent startup must create one header and one database session.
$level = 6;
my @children;
for (1 .. 4) {
    my $pid = fork();
    die "Cannot fork: $!" unless defined $pid;
    if (!$pid) {
        my $child_log = start_log('Concurrent', $morning);
        finish_run($child_log);
        exit 0;
    }
    push @children, $pid;
}
for my $pid (@children) {
    waitpid($pid, 0);
    is($?, 0, 'concurrent invocation succeeded');
}
my $concurrent = "$root/logs/2026-10-04_Concurrent.log";
is(marker_count($concurrent, 'TASK STARTED'), 1, 'concurrent runs share a single header');
my $dbh = LoxBerry::Log::log_db_init_database();
my ($sessions) = $dbh->selectrow_array(
    'SELECT COUNT(*) FROM logs WHERE FILENAME = ?', undef, $concurrent
);
is($sessions, 1, 'concurrent runs share a single database session');
$dbh->disconnect;

my $bridge = "$FindBin::Bin/../bin/weather4lox_log_bridge.pl";
for my $verbose (0, 1) {
    open(my $pipe, '-|', $^X, $bridge, 'start', "$root/bridge", 'Cloud emulator test', $verbose)
        or die "Cannot run bridge: $!";
    my @response = <$pipe>;
    close($pipe);
    is($?, 0, 'Bash bridge initializes successfully');
    is(scalar(@response), 1, 'bridge stdout contains only the response, including verbose mode');
    chomp $response[0];
    my ($file, $loglevel, $key, $status, $version) = split /\t/, $response[0];
    like($file, qr{/\d{4}-\d{2}-\d{2}_Emulator\.log$}, 'bridge selects a daily emulator file');
    ok($key =~ /^\d+$/ && defined($version), 'bridge returns session metadata');
    system($^X, $bridge, 'status', $file, 3);
    is($?, 0, 'bridge saves the Bash run status without closing the log');
    is(marker_count($file, 'TASK FINISHED'), 0, 'bridge leaves daily log open');
}

# Run the real Bash logging setup, stopping before network or service changes.
my $cloud_script = "$FindBin::Bin/../bin/cloudemu.sh";
my $setup = content($cloud_script);
$setup =~ s/# Check for WLAN adapter.*//s;
$setup =~ s{\. /etc/environment}{:};
$setup =~ s{\. \$LBHOMEDIR/libs/bashlib/loxberry_log\.sh}
    {. "$sdk_home/libs/bashlib/loxberry_log.sh"};
local $ENV{LBPLOG} = "$root/bash";
my $bash_file;
for my $exit_code (0, 3) {
    my $run = $setup . "\nLOGERR \"Test failure\"\nexit $exit_code\n";
    system('bash', '-c', $run, $cloud_script, '--verbose');
    is($? >> 8, $exit_code, 'Bash exit trap preserves the script exit code');
    opendir(my $dir, "$root/bash/weather4lox") or die $!;
    my @files = grep { /\.log$/ } readdir($dir);
    closedir($dir);
    is(scalar(@files), 1, 'Bash emulator setup reuses one daily log');
    $bash_file = "$root/bash/weather4lox/$files[0]";
}
is(marker_count($bash_file, 'TASK STARTED'), 1, 'Bash emulator file has one header');
is(marker_count($bash_file, 'TASK FINISHED'), 0, 'Bash exit trap does not end the daily session');
is(marker_count($bash_file, 'START OF:'), 2, 'Bash writes a start marker for each run');
is(marker_count($bash_file, 'END OF:'), 2, 'Bash writes an end marker for each run');

done_testing();
