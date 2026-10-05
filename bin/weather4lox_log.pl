#!/usr/bin/perl

use strict;
use warnings;
use LoxBerry::System;
use LoxBerry::Log;
use Fcntl qw(:flock SEEK_SET);
use File::Path qw(make_path);
use POSIX qw(strftime);

sub weatherLogObject {
    my (%options) = @_;
    my $log = LoxBerry::Log->new(%options)
        or die "Cannot initialize Weather4Lox log $options{filename}\n";

    # Preserve the worst severity across all runs in the same log file.
    if ($log->dbkey) {
        my ($status) = $log->{dbh}->selectrow_array(
            "SELECT value FROM logs_attr WHERE keyref = ? AND attrib = 'STATUS'",
            undef, $log->dbkey
        );
        $log->{STATUS} = $status if defined $status;
    }
    return $log;
}

sub startWeatherLog {
    my (%options) = @_;
    my $name = $options{name};
    my $logdir = $options{logdir};
    my $package = $options{package} // 'weather4lox';
    my $now = $options{now} // time();
    my $plugin = LoxBerry::System::plugindata($package);
    my $level = $options{verbose} ? 7 : ($plugin->{PLUGINDB_LOGLEVEL} // 7);
    my $period = strftime(
        !$options{daily} && $level == 7 ? '%Y-%m-%d_%H' : '%Y-%m-%d',
        localtime($now)
    );
    my $filename = "$logdir/${period}_${name}.log";

    make_path($logdir) unless -d $logdir;
    # Serialize initialization so overlapping runs cannot truncate or restart a log.
    open(my $lock, '+>>', "$logdir/.weather4lox_${name}.lock")
        or die "Cannot open log rotation lock for $name: $!\n";
    flock($lock, LOCK_EX) or die "Cannot lock log rotation for $name: $!\n";
    seek($lock, 0, SEEK_SET) or die "Cannot read log rotation state for $name: $!\n";
    my $previous = <$lock>;
    chomp $previous if defined $previous;

    my $exists = -e $filename;
    if (!$exists) {
        # On the first run after an upgrade, also consider the legacy log filename.
        if (!defined($previous) || !-f $previous) {
            opendir(my $dir, $logdir) or die "Cannot read log directory $logdir: $!\n";
            my @files = map { "$logdir/$_" } grep {
                /^(?:\d{4}-\d{2}-\d{2}(?:_\d{2})?|\d{8}_\d{6}_\d+)_\Q$name\E\.log$/
                    && -f "$logdir/$_" && "$logdir/$_" ne $filename
            } readdir($dir);
            closedir($dir);
            ($previous) = sort { (stat($b))[9] <=> (stat($a))[9] || $b cmp $a } @files;
        }
        if (defined($previous) && $previous ne $filename && -f $previous) {
            my $old = weatherLogObject(
                package => $package, name => $name, filename => $previous, append => 1
            );
            $old->LOGEND;
        }
    }

    my %args = (
        package => $package, name => $name, filename => $filename,
        append => $exists ? 1 : 0, addtime => 1
    );
    if ($options{verbose}) {
        $args{stdout} = 1;
        $args{loglevel} = 7;
    }
    my $log = weatherLogObject(%args);
    $log->default;
    if (!$exists) {
        $log->LOGSTART($options{message} . ', starting from ' .
            strftime('%Y-%m-%d %H:%M:%S', localtime($now)));
    }

    seek($lock, 0, SEEK_SET) or die "Cannot update log rotation state for $name: $!\n";
    truncate($lock, 0) or die "Cannot truncate log rotation state for $name: $!\n";
    print {$lock} "$filename\n" or die "Cannot save log rotation state for $name: $!\n";
    close($lock) or die "Cannot close log rotation state for $name: $!\n";
    return $log;
}

1;
