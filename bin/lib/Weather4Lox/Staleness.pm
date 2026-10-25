package Weather4Lox::Staleness;

# Detect outdated weather data per grabber role (see data/json-schema.md, "Grabber Roles").
# Every grabber writes "role" and "generatedAt" into its section of the JSON files. A role is
# stale if its last contribution is older than 3x the interval of the service (at least 10 min).

use strict;
use warnings;
use Exporter 'import';
use Time::Local qw(timegm timelocal);
use JSON::PP qw(encode_json decode_json);

our @EXPORT_OK = qw(parse_generated_at role_intervals check_staleness stale_flags read_state write_state);
use constant STALE_FACTOR  => 3;
use constant MIN_THRESHOLD => 10;   # minutes; own stations deliver every minute, but not exactly

# Convert generatedAt to epoch. Without offset the time stamp is local time (localtime->datetime).
sub parse_generated_at {
    my ($text) = @_;
    return undef unless defined $text
        && $text =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:?\d{2})?$/;
    my @time = ($6, $5, $4, $3, $2 - 1, $1);
    my $zone = $7;
    return eval { timelocal(@time) } unless defined $zone;
    my $epoch = eval { timegm(@time) } // return undef;
    return $epoch if $zone eq 'Z';
    my ($sign, $hours, $minutes) = $zone =~ /([+-])(\d{2}):?(\d{2})/;
    return $epoch - ($sign eq '+' ? 1 : -1) * ($hours * 3600 + $minutes * 60);
}

# Fetch intervals in minutes of all configured roles, the same way cronjob.pl and fetch.pl schedule them.
# Keys are "<file>.<role>", except "airQuality", which writes to all files in one run.
sub role_intervals {
    my ($param) = @_;
    my $cron = $param->('SERVER.CRON') || 60;
    my $cronAlternate = $param->('SERVER.CRON_ALTERNATE') || $cron;
    my %intervals = (
        'current.primary'        => $cron,
        'dailyforecast.primary'  => $param->('SERVER.USEALTERNATEDFC') ? $cronAlternate : $cron,
        'hourlyforecast.primary' => $param->('SERVER.USEALTERNATEHFC') ? $cronAlternate : $cron,
    );
    $intervals{'current.nearbyStation'} = $param->('SERVER.CRON_LOCAL') || $cron if $param->('SERVER.WUGRABBER');
    $intervals{'current.localStation'} = 1
        if $param->('SERVER.FOSHKGRABBER') || $param->('SERVER.PWSCATCHUPLOADGRABBER') || $param->('SERVER.LOXGRABBER');
    $intervals{'airQuality'} = $param->('SERVER.CRON_AIRQUALITY') || $cron if $param->('SERVER.OPENMETEOAIRQUALITYGRABBER');
    return \%intervals;
}

# Check the age of each configured role.
# Parameter:
#   files:     { current => envelope, dailyforecast => envelope, hourlyforecast => envelope }
#   intervals: result of role_intervals()
#   state:     last seen epoch per role (updated in place). The primary service rewrites the whole
#              file, so the sections of the stations vanish until they deliver again.
#   now:       current epoch
# Returns { role => { age => minutes, threshold => minutes, stale => 0/1 } }
sub check_staleness {
    my ($files, $intervals, $state, $now) = @_;

    my %seen;
    for my $file (keys %$files) {
        my $envelope = $files->{$file};
        next unless ref($envelope) eq 'HASH';
        for my $section (values %$envelope) {
            next unless ref($section) eq 'HASH' && defined $section->{role};
            my $epoch = parse_generated_at($section->{generatedAt}) // next;
            my $key = $section->{role} eq 'airQuality' ? 'airQuality' : "$file.$section->{role}";
            $seen{$key} = $epoch if !defined($seen{$key}) || $epoch > $seen{$key};
        }
    }

    my %result;
    for my $key (keys %$intervals) {
        my $last = $seen{$key};
        $last = $state->{$key} if defined($state->{$key}) && (!defined($last) || $state->{$key} > $last);
        $last //= $now;   # configured, but never seen: start counting now
        $state->{$key} = $last;
        my $age = int(($now - $last) / 60);
        $age = 0 if $age < 0;
        my $threshold = STALE_FACTOR * $intervals->{$key};
        $threshold = MIN_THRESHOLD if $threshold < MIN_THRESHOLD;
        $result{$key} = { age => $age, threshold => $threshold, stale => $age > $threshold ? 1 : 0 };
    }
    delete $state->{$_} for grep { !exists $intervals->{$_} } keys %$state;
    return \%result;
}

# Flags for Loxone: one per role plus summaries per file and overall.
# A summary is set if any service writing to the file is stale (air quality writes to all files).
sub stale_flags {
    my ($result) = @_;
    my %flags = (
        cur_primaryStale       => _stale($result, 'current.primary'),
        dfc_primaryStale       => _stale($result, 'dailyforecast.primary'),
        hfc_primaryStale       => _stale($result, 'hourlyforecast.primary'),
        cur_nearbyStationStale => _stale($result, 'current.nearbyStation'),
        cur_localStationStale  => _stale($result, 'current.localStation'),
        aq_stale               => _stale($result, 'airQuality'),
    );
    $flags{cur_stale} = ($flags{cur_primaryStale} || $flags{cur_nearbyStationStale}
        || $flags{cur_localStationStale} || $flags{aq_stale}) ? 1 : 0;
    $flags{dfc_stale} = ($flags{dfc_primaryStale} || $flags{aq_stale}) ? 1 : 0;
    $flags{hfc_stale} = ($flags{hfc_primaryStale} || $flags{aq_stale}) ? 1 : 0;
    $flags{any_stale} = ($flags{cur_stale} || $flags{dfc_stale} || $flags{hfc_stale}) ? 1 : 0;
    return \%flags;
}

sub _stale {
    my ($result, $key) = @_;
    return $result->{$key} ? $result->{$key}{stale} : 0;
}

# Last seen time stamps per role. A missing or broken file means: start counting now.
sub read_state {
    my ($path) = @_;
    open(my $fh, '<', $path) or return {};
    local $/;
    my $state = eval { decode_json(<$fh>) };
    close($fh);
    return ref($state) eq 'HASH' ? $state : {};
}

sub write_state {
    my ($path, $state) = @_;
    open(my $fh, '>', "$path.tmp") or return 0;
    print {$fh} encode_json($state);
    close($fh) or return 0;
    return rename("$path.tmp", $path);
}

1;
