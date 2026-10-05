#!/usr/bin/perl

use strict;
use warnings;
use LoxBerry::System;
use LoxBerry::Log;
use FindBin;

require "$FindBin::Bin/weather4lox_log.pl";

my ($action, @args) = @ARGV;
if (defined($action) && $action eq 'start') {
    my ($logdir, $message, $verbose) = @args;
    my $log;
    {
        # Keep verbose headers out of the tab-separated response consumed by Bash.
        local *STDOUT = *STDERR;
        $log = startWeatherLog(
            package => 'weather4lox', name => 'Emulator', logdir => $logdir,
            message => $message, verbose => $verbose, daily => 1
        );
    }
    print join("\t", $log->filename, $log->loglevel, $log->dbkey // '',
        $log->{STATUS} // 99, LoxBerry::System::pluginversion('weather4lox')), "\n";
} elsif (defined($action) && $action eq 'status') {
    my ($filename, $status) = @args;
    die "Invalid emulator log status\n" unless defined($status) && $status =~ /^(?:[0-7]|99)$/;
    my $log = weatherLogObject(
        package => 'weather4lox', name => 'Emulator', filename => $filename, append => 1
    );
    $log->{STATUS} = $status if !defined($log->{STATUS}) || $status < $log->{STATUS};
} else {
    die "Usage: $0 start LOGDIR MESSAGE VERBOSE | status FILENAME STATUS\n";
}
