#!/usr/bin/perl

# Shared helpers for Weather4Lox grabbers
#
# Intended usage in a grabber:
#   require "$lbpbindir/grabber_utils.pl";

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
#

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
use File::Copy;
use JSON::PP;
use Encode qw(encode_utf8);
use POSIX qw(strftime);
my $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36";

##########################################################################
# Helper: convert snake_case to camelCase
sub snakeToCamel {
    my ($s) = @_;
    return $s unless defined $s;
    # convert snake_case -> camelCase: example my_key_name -> myKeyName
    $s =~ s/_([a-z])/\U$1\E/g;
    return $s;
}

##########################################################################
# Special Modules (with error handling in case of missing modules)
# 
# These modules should have been installed during installation of plugin
# by commands in /dpkg/apt

sub requireOrLogdie {
    my ($module) = @_;

    eval "require $module; 1;" or do {
        my $err = $@ || "Unknown error while loading $module";
        chomp $err;

        LOGCRIT "Missing Perl module $module - cannot continue.";
        LOGCRIT $err;
        warn "CRIT: $err\n";   # falls fetch.pl STDERR mitsammelt

        exit 2;
    };

    return 1;
}


##########################################################################
# mask of key in URL (used for logging to keep keys secret)

sub sanitizeUrl {
    my ($url, $keyparam) = @_;
    return $url if !defined $url;

    $keyparam ||= 'key';
    my $kp = quotemeta($keyparam);

    # Mask only the requested query parameter name
    $url =~ s/([?&]$kp=)[^&\s]*/$1***MASKED***/gi;
    return $url;
}


##########################################################################
# mask of key in API response (used for logging to keep keys secret)

sub sanitizeDump {
    my ($text, $apikey, $keyparam) = @_;
    return $text if !defined $text;

    $keyparam ||= 'key';
    my $kp = quotemeta($keyparam);

    # Mask keyparam=... in URLs/strings
    $text =~ s/([?&]$kp=)[^&\s]*/$1***MASKED***/gi;

    # Mask literal key value if it appears elsewhere
    if (defined $apikey && length $apikey) {
        my $q = quotemeta($apikey);
        $text =~ s/$q/***MASKED***/g;
    }

    return $text;
}


##########################################################################
# Make an API call with error handling, Logging incl. masking of keys,
# return matched part only, and do JSON decoding

sub apiCall {
    my (%p) = @_;

    my $url      = $p{url}       // '';
    my $maskkeys  = $p{maskkeys} // 1;           # optional, default: 1 (mask keyparam in URLs and literal key value in dumps)
    my $keyparam = $p{keyparam}  // 'key';       # optional, default: 'key' (the query parameter name to mask in URLs, e.g. 'appid' for OpenWeatherMap)
    my $apikey   = $p{apikey}    // '';          # optional, used to mask the key if it appears in the URL path or the response 
    my $info     = $p{info}      // 'API call';  # optional, used for logging message to specify what data is being fetched (e.g. "current weather", "daily forecast", etc.)
    my $match    = $p{match}     // '';          # optional, return matched part of response only

    # mask key in URL to avoid leaking it in the dump if requested by the grabber (default)
    my $urlmasked;
    if ($maskkeys) {
        # Mask keyparam in URL, e.g. ?key=abc123 -> ?key=***MASKED***
        $urlmasked = sanitizeUrl($url, $keyparam);
        # Mask literal key value (if provided!) in case the key appears elsewhere in the URL (e.g. in path segments)
        $urlmasked = sanitizeDump($urlmasked, $apikey, $keyparam);
    } else {
        $urlmasked = $url;
    }
    LOGINF "Fetching  weather data $info";
    LOGDEB("URL for API call: $urlmasked");

    # Perform the API call
    my $ua  = LWP::UserAgent->new( agent => $userAgent );
    my $res = $ua->get($url);
    my $content = $res->decoded_content();

    # Check status of request
    my $urlstatus = $res->status_line;
    my $urlstatuscode = substr($urlstatus,0,3);

    if ($urlstatuscode ne "200") {
        LOGCRIT "Failed to fetch data for $info!";
        LOGCRIT "Status: $urlstatus. Please check your API key and the service availability!";
        exit 2;
    } else {
        LOGOK "Data fetched successfully.";
    }

    # do regular expression match (if match is defined) and return matched part only, used e.g. by WetterOnline to retrieve API keys, station ID and geo coordinates
    if (defined $match && length $match) {
        if ($content =~ $match) {
            $content = $1; # return only the matched part of the response
            LOGDEB("Extracted data using match pattern: $match");

            return $content;
        } else {
            LOGCRIT "Failed to extract data for $info using match pattern: $match. Check Station name.";
            die "Quit fetching data.";
        }
    } 
    # JSON response is expected, so check if it can be decoded

    # Decode JSON response from server
    my $decodedJson = decode_json( "$content" );

    my $body    = '';
    # my $json_obj = JSON->new->pretty->canonical;
    my $jsonObj = JSON->new->canonical;
    $body = $jsonObj->encode($decodedJson);

    my $respEntry = '';
    $respEntry = "HTTP body (JSON):\n$body" if $body ne '';
    $respEntry = sanitizeDump($respEntry, $apikey, $keyparam) if $respEntry ne '';
    $respEntry = encode_utf8($respEntry) if $respEntry ne '';
    LOGDEB($respEntry) if $respEntry ne '';
    LOGDEB("-" x 80);

    return $decodedJson;
}

##########################################################################
# JSON export helpers
# Write structured JSON files alongside the legacy pipe-delimited .dat files.
# Called by each grabber after the .dat has been written and validated.
#
# Design principle: The JSON files use ISO 8601 datetime strings instead
# of the localized weekday/month name columns in the .dat files.
# Consumers parse the ISO datetime and format in their own locale.

# ── Normalized weather code mapping (legacy_code → normalized id) ──
# Matches data/weathercodes.json v2.0
my %WEATHER_CODE_TO_ID = (
     1 => "clear",
     2 => "fair",
     3 => "partly-cloudy",
     4 => "mostly-cloudy",
     5 => "overcast",
     6 => "fog",
     7 => "haze",
    10 => "rain-light",
    11 => "rain",
    12 => "rain-heavy",
    13 => "drizzle",
    14 => "freezing-drizzle",
    15 => "freezing-rain",
    16 => "rain-shower-light",
    17 => "rain-shower-heavy",
    18 => "thunderstorm",
    19 => "thunderstorm-heavy",
    20 => "snow-light",
    21 => "snow",
    22 => "snow-heavy",
    23 => "snow-shower-light",
    24 => "snow-shower-heavy",
    25 => "sleet-light",
    26 => "sleet",
    27 => "sleet-heavy",
    28 => "sleet-shower-light",
    29 => "sleet-shower-heavy",
);



##########################################################################
# Helpers to retrieve values from object structure including arrays 
# these function are used to extracts values from API responses (decoded JSONs)
##########################################################################

##########################################################################
# Get a value (string or number from decoded JSON, returns undef if any path 
# segment is missing or invalid.
# Parameters:
#   $root  - root data structure
#   @path  - path elements (tree and param to retrieve)
# Returns:
#   value or undef if missing/invalid
# Note: If the current node is an ARRAYref, only numeric indices are accepted.

sub getValue {
    my ($root, @path) = @_;
    my $cur = $root;

    for my $p (@path) {
        return undef unless defined $cur;

        if (ref $cur eq 'ARRAY') {
            # only accept numeric indices for arrays
            return undef unless defined $p && looks_like_number($p);
            my $idx = int($p);
            return undef if $idx < 0 || $idx > $#$cur;    # out of bounds
            $cur = $cur->[$idx];
        }
        elsif (ref $cur eq 'HASH') {
            return undef unless exists $cur->{$p};
            $cur = $cur->{$p};
        }
        else {
            return undef;
        }
    }
    return $cur;
}


##########################################################################
# Get a formatted value (numbers only) from decoded JSON, used for rounding
# Parameters:
#   $fmt   - sprintf format, e.g. '%.2f', round to two decimal places
#   $root  - root data structure
#   @path  - path elements passed to getValue
# Returns:
#   rounded numeric value (e.g. 4.1) or undef if value missing/invalid

sub getFormatted {
    my ($fmt, $root, @path) = @_;

    my $v = getValue($root, @path);
    return undef unless defined $v;
  
    # Trim leading/trailing whitespace (only scalar strings)
    if (!ref $v) {
        $v =~ s/^\s+|\s+$//g;
    }
    # Only accept numerical values
    return undef unless looks_like_number($v);
    return undef if $v =~ /^(?:nan|inf|infinity)$/i;  # just in case

    my $s = sprintf($fmt, $v) + 0; # numeric result of sprintf
    return $s;
}

##########################################################################
# Get a formatted time value (numbers only) from decoded JSON, used for rounding
# Parameters:
#   $fmt      - sprintf format, e.g. '%H:%M'
#   $root     - root data structure
#   @path     - path elements passed to getValue
# Returns:
#   time information (e.g. 23:10) or undef if value missing/invalid

sub getTimeFormatted {
    my ($fmt, $timezone, $root, @path) = @_;

    # Get value and verify if it is not empty
    my $iso_time = getValue($root, @path);
    return undef unless defined $iso_time && $iso_time ne '';

    my $dt = eval { DateTime::Format::ISO8601->parse_datetime($iso_time) };
    return undef unless $dt;

    # all times are local times, so global variable must be set in grabber
    if ($timezone eq '') {
        $timezone = 'UTC';
    }
    $dt->set_time_zone($timezone);

    return $dt->strftime('%H:%M');
}

##########################################################################
# Get a percentage value by calling getFormatted and multiplying the result by 100.
# Parameters:
#   $fmt   - sprintf format used by getFormatted (e.g. '%.2f')
#   $root  - root data structure (same as for getFormatted)
#   @path  - path elements passed to getFormatted
# Returns:
#   numeric percentage (e.g. 46) or undef if value missing/invalid

sub getPercentage {
    my ($fmt, $root, @path) = @_;

    my $v = getFormatted($fmt, $root, @path);
    return undef unless defined $v;

    return $v * 100;
}

##########################################################################
# Get label for a wind direction in degrees
# Parameters:
#   $deg  - wind direction in degrees (number from 0 to 360 expected)
#   $Lref - optional hashref to localization hash (e.g. \%L)
# Return:
#   $label or (undef, undef) on invalid input

sub getWindDirectionLabel {
    my ($deg, $Lref) = @_;

    # validate/normalize input
    return (undef, undef) unless defined $deg;
    $deg =~ s/^\s+|\s+$//g if !ref $deg;
    return (undef, undef) unless $deg =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/;

    $deg += 0;                              # numericify
    $deg = ($deg % 360 + 360) % 360;        # 0..359.999...

    # wind direction labels for eight‑point compass rose
    my @dirs = qw(N NE E SE S SW W NW);

    # calculate section on eight‑point compass rose
    my $wdir = $dirs[int((($deg + 22.5) / 45)) % 8];

    # take localized labels (either from provided hashref or from global %L)
    my $L = $Lref // \%main::L;
    $L = {} unless defined $L && ref $L eq 'HASH';
    
    my %dirLabels = (
        N  => $L->{'GRABBER.LABEL_N'}  // 'North',
        NE => $L->{'GRABBER.LABEL_NE'} // 'North-East',
        E  => $L->{'GRABBER.LABEL_E'}  // 'East',
        SE => $L->{'GRABBER.LABEL_SE'} // 'South-East',
        S  => $L->{'GRABBER.LABEL_S'}  // 'South',
        SW => $L->{'GRABBER.LABEL_SW'} // 'South-West',
        W  => $L->{'GRABBER.LABEL_W'}  // 'West',
        NW => $L->{'GRABBER.LABEL_NW'} // 'North-West',
    );

    # cur_w_dirdes, wind direction description, e.g. "South",
    my $label = $dirLabels{$wdir};
    $label = defined $label ? Encode::decode("UTF-8", $label) : undef;

    return $label;
}

##########################################################################
# Calculate short name for wind direction from long name
sub getWindDirectionShort {
    my ($windDescr) = @_;
    
    # calculate short name from description
    my $short = join('', $windDescr =~ /([A-Z]+)/g);

    return $short;
}

##########################################################################
# Get short and full label for a wind direction in degrees
# Parameters:
#   $deg  - wind direction in degrees (number from 0 to 360 expected)
#   $Lref - optional hashref to localization hash (e.g. \%L)
# Return:
#   ($label, $short) or (undef, undef) on invalid input

sub getWindDirectionInfo {
    my ($deg, $Lref) = @_;

    my $label = getWindDirectionLabel($deg, $Lref);
    my $short = getWindDirectionShort($label);

    return ($label, $short);
}

##########################################################################
# getCoverage($w4l_code) -> returns estimated sky cover percentage (0..100) or undef
# getMetarCode($w4l_code) -> returns METAR cloud code ('SKC','FEW','SCT','OVC') or undef
#
# Both functions normalize the icon name (trim, lowercase) and strip intensity suffixes
# like "_1", "_2", "_3" before lookup. If the icon is not found in the compact mapping,
# a small pattern-based fallback is applied.

my %W4L_COVERAGE_MAP = (
    clear                      => [  0, 'SKC' ],
    fair                       => [ 10, 'FEW' ],
    partly_cloudy              => [ 40, 'SCT' ],
    cloudy                     => [ 70, 'BKN' ],
    overcast                   => [100, 'OVC' ],

    cloudy_shower              => [ 70, 'BKN' ],
    overcast_shower            => [100, 'OVC' ],

    cloudy_rain                => [ 75, 'BKN' ],
    overcast_rain              => [100, 'OVC' ],

    cloudy_sleet               => [ 75, 'BKN' ],
    overcast_sleet             => [100, 'OVC' ],

    cloudy_snow                => [ 75, 'BKN' ],
    overcast_snow              => [100, 'OVC' ],

    cloudy_freezingrain        => [ 80, 'BKN' ],
    overcast_freezingrain      => [100, 'OVC' ],

    cloudy_thunderstorm        => [ 85, 'OVC' ],
    overcast_thunderstorm      => [100, 'OVC' ],

    cloudy_snowthunderstorm    => [ 85, 'OVC' ],
    overcast_snowthunderstorm  => [100, 'OVC' ],

    cloudy_fog                 => [ 90, 'OVC' ],
    overcast_fog               => [100, 'OVC' ],

    overcast_hail              => [100, 'OVC' ],

    no_data                    => [ undef, undef ],
);

sub _normalizeIcon {
    my ($w4l_code) = @_;
    return undef unless defined $w4l_code;
    $w4l_code =~ s/^\s+|\s+$//g;
    $w4l_code = lc $w4l_code;
    $w4l_code =~ s/_[1-3]$//;    # strip intensity suffix like _1, _2, _3
    return $w4l_code;
}

sub _fallbackMap {
    my ($w4l_code) = @_;
    return (100, 'OVC') if $w4l_code =~ /overcast|ovc|overcast_/;
    return (90,  'OVC') if $w4l_code =~ /thunder|storm/;
    return (90,  'OVC') if $w4l_code =~ /fog|mist|smog|haze/;
    return (80,  'BKN') if $w4l_code =~ /snow|sleet|graupel/;
    return (85,  'OVC') if $w4l_code =~ /freezingrain|freezing/;
    return (75,  'BKN') if $w4l_code =~ /rain|shower|drizzle/;
    return (40,  'SCT') if $w4l_code =~ /partly|partly_cloudy/;
    return (70,  'BKN') if $w4l_code =~ /cloudy|cloud/;
    return (10,  'FEW') if $w4l_code =~ /fair/;
    return (0,   'SKC') if $w4l_code =~ /clear|sun/;
    return (undef, undef);
}

##########################################################################
# Public: returns sky cover percentage (0..100) or undef
sub getCoverage {
    my ($w4l_code) = @_;
    my $w4l_short_code = _normalizeIcon($w4l_code);
    return undef unless defined $w4l_short_code;

    if (exists $W4L_COVERAGE_MAP{$w4l_short_code}) {
        return $W4L_COVERAGE_MAP{$w4l_short_code}[0];
    }

    my ($pct, $metar) = _fallbackMap($w4l_short_code);
    return $pct;
}

##########################################################################
# Public: returns METAR cloud code (SKC, FEW, SCT, BKN, OVC) or undef
sub getMetarCode {
    my ($w4l_code) = @_;
    my $w4l_short_code = _normalizeIcon($w4l_code);
    return undef unless defined $w4l_short_code;

    if (exists $W4L_COVERAGE_MAP{$w4l_short_code}) {
        return $W4L_COVERAGE_MAP{$w4l_short_code}[1];
    }

    my ($pct, $metar) = _fallbackMap($w4l_short_code);
    return $metar;
}

# Example usage:
# my $cover = getCoverage('cloudy_rain_1');   # -> e.g. 75
# my $metar = getMetarCode('cloudy_rain_1'); # -> e.g. 'BKN'

##########################################################################
# Returns the moon waxing/waning state
sub getMoonDirection {
    my $age = shift;                 # moon age in days (0..29.53)
    my $synodicMonth = 29.53;

    $age = $age % $synodicMonth; # normalize age

    # Determine direction: waxing (<full moon), waning (>full moon)
    if ($age < ($synodicMonth / 2)) {
        return 'waxing';
    } else {
        return 'waning';
    }
}

##########################################################################
# Returns the moon phase part, either quarter (0q, 1q, 2q, 3q, 4q) or half (0h, 1h, 2h)
# Parameters:
#   $age:         moon age in days (0..29.53)
#   $resolution:  5 for 'quarter' or 3 for 'half' (default: 'quarter')

sub getMoonPhasePart {
    my ($age, $resolution) = @_;
    my $synodicMonth = 29.53;

    # normalize age to 0..29.53
    $age = $age % $synodicMonth;

    # full moon is at half of the synodic month
    my $fullSize = $synodicMonth / 2;
    
    # For the second half (full to new), the quarter is proportional to the remaining time.
    $age = $synodicMonth - $age if ($age > $fullSize);

    return int($age / $fullSize * ($resolution - 1) + 0.5); # round to nearest integer
}

##########################################################################
# Converts time to seconds since midnight
# Parameter:
#   time:      time to convert (e.g. "01:30" or "01:30:45")

sub timeToSec {
    my ($time) = @_;

    my ($hour, $minute, $second) = split /:/, $time;
    $second //= 0;  # Setze $second auf 0, falls nicht vorhanden
    $hour   = 0 + ($hour   // 0);
    $minute = 0 + ($minute // 0);
    $second = 0 + ($second // 0);
    my $seconds = $hour * 3600 + $minute * 60 + $second;
    return $seconds;
}

##########################################################################
# Converts time to Loxone epoch time (seconds since 01.01.1970)
# Parameter:
#   time:      time to convert - datetime object or unix epoch timestamp

sub toLoxEpoch {
    my ($dtInput) = @_;

    my $date;
    # Check, if $dtInput is a DateTime object
    if (ref($dtInput) eq 'DateTime') {
        $date = $dtInput;
    }
    # Check, if $dtInput is numeric (Epoch)
    elsif (defined $dtInput && $dtInput =~ /^\d+$/) {
        $date = DateTime->from_epoch(epoch => $dtInput);
    }
    # Otherwise: Try to parse ISO8601 string
    else {
        $date = DateTime::Format::ISO8601->parse_datetime($dtInput);
    }

    my $loxone_ref = 1230764400;                        # time reference is Kollerschlag time (MEZ/UTC+1) according to findings, not UTC!
    my $loxone_epoch = $date->epoch - $loxone_ref;

    return $loxone_epoch;
}

##########################################################################
# Get timezone offset in seconds from tz_offset (perl or ISO), e.g. "+0100" => 3600,
# "-02:30" => -9000, "2026-03-16T20:00:04+02:00" => 7200
# Note: The tz_offset string can be in the format "+HHMM" or "-HHMM", 
#       optionally preceded by a datetime string, e.g. "2026-03-16T20:00:04+0200"

sub tzOffsetSeconds {
    my ($dtInput) = @_;

    my $tzseconds = 0;
    if (defined($dtInput) && $dtInput =~ /([+-])(\d{2}):?(\d{2})$/) {
        my $sign = ($1 eq '+') ? 1 : -1;
        $tzseconds = $sign * ($2 * 3600 + $3 * 60);
    }
    return $tzseconds;
}

##########################################################################
# Get timezone offset in seconds from DateTime object, e.g. "+01:00"

sub isoTzOffset {
    my ($dt) = @_;

    my $tz = $dt->strftime('%z');
    # add colon to get ISO format, e.g. "+0100" -> "+01:00"
    return substr($tz,0,3) . ":" . substr($tz,3);
}

##########################################################################
# Calculate average / mean of a list of numbers

sub mean {
  my (@data) = @_;

  my $sum = 0;
  foreach (@data) {
    $sum += $_;
  }
  if (@data == 0) {
    return undef; # Avoid division by zero
  }
  return ( $sum / @data );
}

##########################################################################
# TODO: cleanup - private helper name conversions
sub _readDatLines {
    my ($datFile) = @_;
    my @lines;
    open my $fh, '<:encoding(UTF-8)', $datFile or do {
        LOGWARN "Cannot open $datFile for JSON conversion: $!";
        return ();
    };
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^\s*#/ || $line =~ /^\s*$/;
        $line =~ s/\|$//;
        push @lines, $line;
    }
    close $fh;
    return @lines;
}

sub _val {
    my ($v) = @_;
    return undef if !defined $v || $v eq '';
    $v =~ s/^\s+|\s+$//g;  # trim whitespace
    return undef if $v eq '';
    return $v + 0 if $v =~ /^-?\d+(?:\.\d+)?$/;
    return $v;
}

# Build a raw key=>value hash from one pipe-delimited line
sub _lineToHash {
    my ($line, $fieldsRef) = @_;
    my @vals = split /\|/, $line, -1;
    my %h;
    for my $i (0 .. $#$fieldsRef) {
        $h{ $fieldsRef->[$i] } = $vals[$i] // '';
    }
    return %h;
}

# epoch -> ISO 8601 with timezone from tz_long (or UTC fallback)
sub _epochToIso {
    my ($epoch, $tzLong) = @_;
    return undef unless defined $epoch && $epoch =~ /^\d+$/;

    # Try POSIX localtime with TZ override
    if (defined $tzLong && $tzLong ne '') {
        local $ENV{TZ} = $tzLong;
        POSIX::tzset();
        my $iso = strftime("%Y-%m-%dT%H:%M:%S%z", localtime($epoch));
        # Insert colon in offset: +0200 -> +02:00
        $iso =~ s/(\d{2})(\d{2})$/$1:$2/;
        POSIX::tzset();   # restore
        return $iso;
    }
    # Fallback: UTC
    return strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($epoch));
}

# Read system timezone once
my $_systemTz;
sub _systemTimezone {
    return $_systemTz if defined $_systemTz;
    if (open my $fh, '<', '/etc/timezone') {
        $_systemTz = <$fh>;
        chomp $_systemTz if defined $_systemTz;
        close $fh;
    }
    $_systemTz //= 'UTC';
    return $_systemTz;
}

# "HH|MM" -> "HH:MM" (from two separate fields)
sub _hhmm {
    my ($h, $m) = @_;
    return undef if !defined $h || $h eq '' || $h eq '-9999';
    return sprintf("%02d:%02d", $h, $m // 0);
}

# Add normalized weatherId from legacy weather_code
# NOTE: this function now writes camelCase key 'weatherId' and reads either weather_code or weatherCode
sub _enrichWeatherId {
    my ($rec) = @_;
    return $rec unless defined $rec && ref $rec eq 'HASH';

    my $code = undef;
    if (exists $rec->{weatherCode}) {
        $code = $rec->{weatherCode};
    } elsif (exists $rec->{weather_code}) {
        $code = $rec->{weather_code};
    }

    if (defined $code && exists $WEATHER_CODE_TO_ID{ $code }) {
        $rec->{weatherId} = $WEATHER_CODE_TO_ID{ $code };
    }
    return $rec;
}



##########################################################################
# Generalized JSON file writer for any weather type (current, daily, hourly).
# Parameter:
#   filepath:           directory for file
#   filename:           e.g. 'current' | 'dailyforecast' | 'hourlyforecast'
#   jsonData:           hashref or arrayref

sub writeJsonFile {
    my ($filepath, $filename, $jsonData) = @_;

    $filepath    = $filepath // '.';
    my $out      = "$filepath/$filename.json";
    my $tmp      = "$out.tmp";

    LOGINF "Saving $filename weather data as JSON to $out ...";
 
    my $jsonObj = JSON::PP->new->pretty->canonical->utf8;

    eval {
       open my $fh, '>:raw', $tmp or die "Cannot open $tmp: $!";
        print $fh $jsonObj->encode($jsonData);
        close $fh;
        File::Copy::move($tmp, $out) or die "Cannot rename $tmp to $out: $!";
    };
    if ($@) {
        LOGWARN "JSON write failed for $out: $@";
        return;
    };
    LOGOK "Saved $filename weather data as JSON finished.";
}

##########################################################################
# Generalized JSON file reader for any weather type (current, daily, hourly).
# Parameter:
#   weatherKey:        'current' | 'dailyforecast' | 'hourlyforecast'
#   filepath:           directory for file

sub readJsonFile {
    my ($filepath, $weatherKey) = @_;

    my $filename = "$filepath/$weatherKey.json";

    # Existenz prüfen
    unless (-f $filename) {
        LOGWARN "File not found: $filename";
        return undef;
    }

    # Datei lesen und parsen
    my $jsonText;
    eval {
        open my $fh, '<:raw', $filename or die "Cannot open $filename: $!";
        local $/;
        flock($fh, 1);  # LOCK_SH — shared read lock
        $jsonText = <$fh>;
        flock($fh, 8);  # LOCK_UN
        close $fh;
    };
    if ($@) {
        LOGWARN "Failed to read $filename: $@";
        return undef;
    }

    # JSON-Deserialisierung    
    my $data;
    eval {
        $data = JSON::PP->new->utf8->decode($jsonText);
    };
    if ($@) {
        LOGWARN "Failed to decode JSON from $filename: $@";
        return undef;
    }
    LOGOK "Read $filename weather data as JSON from $filename";

    return $data;
}


1; # end of module