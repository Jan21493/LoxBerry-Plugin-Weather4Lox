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
my $useragent        = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36";

##########################################################################
# Special Modules (with error handling in case of missing modules)
# 
# These modules should have been installed during installation of plugin
# by commands in /dpkg/apt

sub require_or_logdie {
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

sub sanitize_url {
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

sub sanitize_dump {
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

sub api_call {
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
        $urlmasked = sanitize_url($url, $keyparam);
        # Mask literal key value (if provided!) in case the key appears elsewhere in the URL (e.g. in path segments)
        $urlmasked = sanitize_dump($urlmasked, $apikey, $keyparam);
    } else {
        $urlmasked = $url;
    }
    LOGINF "Fetching  weather data $info";
    LOGDEB("URL for API call: $urlmasked");

    # Perform the API call
    my $ua  = LWP::UserAgent->new( agent => $useragent );
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
    my $decoded_json = decode_json( "$content" );

    my $body    = '';
    # my $json_obj = JSON->new->pretty->canonical;
    my $json_obj = JSON->new->canonical;
    $body = $json_obj->encode($decoded_json);

    my $resp_entry = '';
    $resp_entry = "HTTP body (JSON):\n$body" if $body ne '';
    $resp_entry = sanitize_dump($resp_entry, $apikey, $keyparam) if $resp_entry ne '';
    $resp_entry = encode_utf8($resp_entry) if $resp_entry ne '';
    LOGDEB($resp_entry) if $resp_entry ne '';
    LOGDEB("-" x 80);

    return $decoded_json;
}

##########################################################################
# JSON export helpers
# Write structured JSON files alongside the legacy pipe-delimited .dat files.
# Called by each grabber after the .dat has been written and validated.
#
# Design principle: The JSON files use ISO 8601 datetime strings instead
# of the localized weekday/month name columns in the .dat files.
# Consumers parse the ISO datetime and format in their own locale.

use JSON::PP ();
use POSIX     qw(strftime);

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

# ── Raw field lists (positional match to .dat columns) ──────────────
# TODO: may be removed later

my @CURRENT_RAW = qw(
    epoch date_rfc822 tz_short tz_long tz_offset
    city country country_code latitude longitude elevation
    temperature feelslike humidity
    wind_direction_desc wind_direction_deg wind_speed wind_gust windchill
    pressure dewpoint visibility solar_radiation heat_index uv_index
    precip_today_mm precip_1hr_mm
    weather_icon weather_code weather_description
    moon_percent moon_age moon_phase moon_hemisphere
    sunrise_hour sunrise_min sunset_hour sunset_min
    ozone cloud_cover precip_probability snow
);

my @DAILY_RAW = qw(
    period epoch day month month_name month_name_short year hour minutes
    weekday weekday_short
    high_temp low_temp precip_probability precip_mm snow_cm
    wind_speed_max wind_dir_max_desc wind_dir_max_deg
    wind_speed_avg wind_dir_avg_desc wind_dir_avg_deg
    humidity_avg humidity_max humidity_min
    weather_icon weather_code weather_description
    ozone moon_percent dewpoint pressure uv_index
    sunrise_hour sunrise_min sunset_hour sunset_min
    visibility moon_age moon_phase
);

my @HOURLY_RAW = qw(
    period epoch day month month_name month_name_short year hour minutes
    weekday weekday_short
    temperature feelslike heat_index humidity
    wind_direction_desc wind_direction_deg wind_speed windchill
    pressure dewpoint sky_percent sky_description uv_index
    precip_mm snow_cm precip_probability
    weather_code weather_icon weather_description
    ozone solar_radiation visibility
    moon_percent moon_age moon_phase
);

# ── Fields to DROP from JSON (replaced by "datetime" / "sunrise" / "sunset") ──

my %DROP_CURRENT = map { $_ => 1 } qw(
    date_rfc822 tz_short tz_long tz_offset
    sunrise_hour sunrise_min sunset_hour sunset_min
);

my %DROP_FORECAST = map { $_ => 1 } qw(
    day month month_name month_name_short year hour minutes
    weekday weekday_short
    sunrise_hour sunrise_min sunset_hour sunset_min
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
#   rounded numeric value (e.g. 4.1) or undef if value missing/invalid
# Note: If the current node is an ARRAYref, only numeric indices are accepted.

sub get_value {
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
#   @path  - path elements passed to get_value
# Returns:
#   rounded numeric value (e.g. 4.1) or undef if value missing/invalid

sub get_formatted {
    my ($fmt, $root, @path) = @_;

    my $v = get_value($root, @path);
    return undef unless defined $v;
  
    # Trim leading/trailing whitespace (only scalar strings)
    if (!ref $v) {
        $v =~ s/^\s+|\s+$//g;
    }
    # Only accept numerical values
    return undef unless looks_like_number($v);
    return undef if $v =~ /^(?:nan|inf|infinity)$/i;  # just in case

    my $s = sprintf($fmt, $v);
    return $s + 0; # return as number
}

##########################################################################
# Get a formatted value (numbers only) from decoded JSON, used for rounding
# Parameters:
#   $fmt      - sprintf format, e.g. '%H:%M'
#   $root     - root data structure
#   @path     - path elements passed to get_value
# Returns:
#   time information (e.g. 23:10) or undef if value missing/invalid

sub get_time_formatted {
    my ($fmt, $timezone, $root, @path) = @_;

    # Get value and verify if it is not empty
    my $iso_time = get_value($root, @path);
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
# Get a percentage value by calling get_formatted and multiplying the result by 100.
# Parameters:
#   $fmt   - sprintf format used by get_formatted (e.g. '%.2f')
#   $root  - root data structure (same as for get_formatted)
#   @path  - path elements passed to get_formatted
# Returns:
#   numeric percentage (e.g. 46) or undef if value missing/invalid

sub get_percentage {
    my ($fmt, $root, @path) = @_;

    my $v = get_formatted($fmt, $root, @path);
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

sub get_wind_direction_label {
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
    
    my %dir_labels = (
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
    my $label = $dir_labels{$wdir};
    $label = defined $label ? Encode::decode("UTF-8", $label) : undef;

    return $label;
}

# Calculate short name for wind direction from long name
sub get_wind_direction_short {
    my ($wind_descr) = @_;
    
    # calculate short name from description
    my $short = join('', $wind_descr =~ /([A-Z]+)/g);

    return $short;
}

# Get short and full label for a wind direction in degrees
# Parameters:
#   $deg  - wind direction in degrees (number from 0 to 360 expected)
#   $Lref - optional hashref to localization hash (e.g. \%L)
# Return:
#   ($label, $short) or (undef, undef) on invalid input

sub get_wind_direction_info {
    my ($deg, $Lref) = @_;

    my $label = get_wind_direction_label($deg, $Lref);
    my $short = get_wind_direction_short($label);

    return ($label, $short);

}

##########################################################################
# get_coverage($w4l_code) -> returns estimated sky cover percentage (0..100) or undef
# get_metar_code($w4l_code) -> returns METAR cloud code ('SKC','FEW','SCT','BKN','OVC') or undef
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

sub _normalize_icon {
    my ($w4l_code) = @_;
    return undef unless defined $w4l_code;
    $w4l_code =~ s/^\s+|\s+$//g;
    $w4l_code = lc $w4l_code;
    $w4l_code =~ s/_[1-3]$//;    # strip intensity suffix like _1, _2, _3
    return $w4l_code;
}

sub _fallback_map {
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

# Public: returns sky cover percentage (0..100) or undef
sub get_coverage {
    my ($w4l_code) = @_;
    my $w4l_short_code = _normalize_icon($w4l_code);
    return undef unless defined $w4l_short_code;

    if (exists $W4L_COVERAGE_MAP{$w4l_short_code}) {
        return $W4L_COVERAGE_MAP{$w4l_short_code}[0];
    }

    my ($pct, $metar) = _fallback_map($w4l_short_code);
    return $pct;
}

# Public: returns METAR cloud code (SKC, FEW, SCT, BKN, OVC) or undef
sub get_metar_code {
    my ($w4l_code) = @_;
    my $w4l_short_code = _normalize_icon($w4l_code);
    return undef unless defined $w4l_short_code;

    if (exists $W4L_COVERAGE_MAP{$w4l_short_code}) {
        return $W4L_COVERAGE_MAP{$w4l_short_code}[1];
    }

    my ($pct, $metar) = _fallback_map($w4l_short_code);
    return $metar;
}

# Example usage:
# my $cover = get_coverage('cloudy_rain_1');   # -> e.g. 75
# my $metar = get_metar_code('cloudy_rain_1');# -> e.g. 'BKN'

sub _read_dat_lines {
    my ($dat_file) = @_;
    my @lines;
    open my $fh, '<:encoding(UTF-8)', $dat_file or do {
        LOGWARN "Cannot open $dat_file for JSON conversion: $!";
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
sub _line_to_hash {
    my ($line, $fields_ref) = @_;
    my @vals = split /\|/, $line, -1;
    my %h;
    for my $i (0 .. $#$fields_ref) {
        $h{ $fields_ref->[$i] } = $vals[$i] // '';
    }
    return %h;
}

# epoch -> ISO 8601 with timezone from tz_long (or UTC fallback)
sub _epoch_to_iso {
    my ($epoch, $tz_long) = @_;
    return undef unless defined $epoch && $epoch =~ /^\d+$/;

    # Try POSIX localtime with TZ override
    if (defined $tz_long && $tz_long ne '') {
        local $ENV{TZ} = $tz_long;
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
my $_system_tz;
sub _system_timezone {
    return $_system_tz if defined $_system_tz;
    if (open my $fh, '<', '/etc/timezone') {
        $_system_tz = <$fh>;
        chomp $_system_tz if defined $_system_tz;
        close $fh;
    }
    $_system_tz //= 'UTC';
    return $_system_tz;
}

# "HH|MM" -> "HH:MM" (from two separate fields)
sub _hhmm {
    my ($h, $m) = @_;
    return undef if !defined $h || $h eq '' || $h eq '-9999';
    return sprintf("%02d:%02d", $h, $m // 0);
}

# Add normalized weather_id from legacy weather_code
sub _enrich_weather_id {
    my ($rec) = @_;
    if (defined $rec->{weather_code} && exists $WEATHER_CODE_TO_ID{ $rec->{weather_code} }) {
        $rec->{weather_id} = $WEATHER_CODE_TO_ID{ $rec->{weather_code} };
    }
    return $rec;
}


# ── write_current_json ──────────────────────────────────────────────
# Accepts either:
#   write_current_json($logdir, source => ..., grabber => ...)           # legacy: reads current.dat
#   write_current_json($logdir, data => \%hash, source => ..., grabber => ...)  # direct: hash with JSON field names

sub write_current_json {
    my ($logdir, %opts) = @_;
    my $source  = $opts{source}  // '';
    my $grabber = $opts{grabber} // '';
    my $data    = $opts{data};     # optional hashref with pre-formatted fields

    my %rec;
    if ($data) {
        # Direct path: caller provides hash with final JSON field names/values
        for my $k (keys %$data) {
            $rec{$k} = _val($data->{$k});
        }
    } else {
        # Legacy path: read from .dat file
        my $dat = "$logdir/current.dat";
        return unless -f $dat;
        my @lines = _read_dat_lines($dat);
        return unless @lines;

        my %raw = _line_to_hash($lines[0], \@CURRENT_RAW);
        my $tz  = $raw{tz_long} || _system_timezone();

        $rec{datetime} = _epoch_to_iso($raw{epoch}, $tz);
        $rec{epoch}    = _val($raw{epoch});
        $rec{timezone} = $tz;
        $rec{sunrise} = _hhmm($raw{sunrise_hour}, $raw{sunrise_min});
        $rec{sunset}  = _hhmm($raw{sunset_hour},  $raw{sunset_min});

        for my $f (@CURRENT_RAW) {
            next if $DROP_CURRENT{$f};
            next if $f eq 'epoch';
            $rec{$f} = _val($raw{$f});
        }
    }

    _enrich_weather_id(\%rec);

    my $generated_at = strftime("%Y-%m-%dT%H:%M:%S%z", localtime(time));
    $generated_at =~ s/(\d{2})(\d{2})$/$1:$2/;

    my %envelope = (
        meta => {
            schema_version => "1.0",
            source         => $source,
            grabber        => $grabber,
            generated_at   => $generated_at,
        },
        data => \%rec,
    );

    my $json_obj = JSON::PP->new->pretty->canonical->utf8;
    my $out = "$logdir/current.json";
    my $tmp = "$out.tmp";
    eval {
        open my $fh, '>:raw', $tmp or die "Cannot open $tmp: $!";
        print $fh $json_obj->encode(\%envelope);
        close $fh;
        File::Copy::move($tmp, $out) or die "Cannot rename $tmp to $out: $!";
    };
    if ($@) {
        LOGWARN "JSON write failed for $out: $@";
        return;
    }
    LOGOK "Saved current weather data as JSON to $out";
}

# ── write_current_json_aq ────────────────────────────────────────────
# For the OpenMeteo AQ grabber: reads current.dat, merges AQ values,
# writes current.json with the full schema including AQ fields populated.

sub write_current_json_aq {
    my ($logdir, %opts) = @_;
    my $source  = $opts{source}  // '';
    my $grabber = $opts{grabber} // '';
    my %aq_data = %{ $opts{aq_data} // {} };

    my $dat = "$logdir/current.dat";
    return unless -f $dat;
    my @lines = _read_dat_lines($dat);
    return unless @lines;

    # Build same record as write_current_json
    my %raw = _line_to_hash($lines[0], \@CURRENT_RAW);
    my $tz  = $raw{tz_long} || _system_timezone();
    my %rec;
    $rec{datetime} = _epoch_to_iso($raw{epoch}, $tz);
    $rec{epoch}    = _val($raw{epoch});
    $rec{timezone} = $tz;
    $rec{sunrise}  = _hhmm($raw{sunrise_hour}, $raw{sunrise_min});
    $rec{sunset}   = _hhmm($raw{sunset_hour},  $raw{sunset_min});
    for my $f (@CURRENT_RAW) {
        next if $DROP_CURRENT{$f};
        next if $f eq 'epoch';
        $rec{$f} = _val($raw{$f});
    }

    # AQ fields: defaults to null, override with provided data
    for my $aqf (qw(aqi_eu aqi_us pm10 pm25
                    pollen_alder pollen_birch pollen_grass pollen_mugwort
                    pollen_olive pollen_ragweed
                    pollen_overall_today pollen_overall_tomorrow)) {
        $rec{$aqf} = exists $aq_data{$aqf} ? _val($aq_data{$aqf}) : undef;
    }

    _enrich_weather_id(\%rec);

    my $generated_at = strftime("%Y-%m-%dT%H:%M:%S%z", localtime(time));
    $generated_at =~ s/(\d{2})(\d{2})$/$1:$2/;
    my %envelope = (
        meta => { schema_version => "1.0", source => $source,
                  grabber => $grabber, generated_at => $generated_at },
        data => \%rec,
    );

    my $json_obj = JSON::PP->new->pretty->canonical->utf8;
    my $out = "$logdir/current.json";
    my $tmp = "$out.tmp";
    eval {
        open my $fh, '>:raw', $tmp or die "Cannot open $tmp: $!";
        print $fh $json_obj->encode(\%envelope);
        close $fh;
        File::Copy::move($tmp, $out) or die "Cannot rename $tmp to $out: $!";
    };
    if ($@) {
        LOGWARN "JSON write failed for $out: $@";
        return;
    }
    LOGOK "Saved current weather data (with AQ) as JSON to $out";
}


##########################################################################
# Generalized JSON file writer for any weather type (current, daily, hourly).
# Parameter:
#   filepath:           directory for file
#   filename:           e.g. 'current' | 'dailyforecast' | 'hourlyforecast'
#   json_data:          hashref or arrayref

sub write_json_file {
    my ($filepath, $filename, $json_data) = @_;

    $filepath    = $filepath // '.';
    my $out      = "$filepath/$filename.json";
    my $tmp      = "$out.tmp";

    my $json_obj = JSON::PP->new->pretty->canonical->utf8;

    eval {
        open my $fh, '>:raw', $tmp or die "Cannot open $tmp: $!";
        print $fh $json_obj->encode($json_data);
        close $fh;
        File::Copy::move($tmp, $out) or die "Cannot rename $tmp to $out: $!";
    };
    if ($@) {
        LOGWARN "JSON write failed for $out: $@";
        return;
    };
    LOGOK "Saved $filename weather data as JSON to $out";
}


##########################################################################
# Generalized JSON file reader for any weather type (current, daily, hourly).
# Parameter:
#   weather_key:        'current' | 'dailyforecast' | 'hourlyforecast'
#   filepath:           directory for file

sub read_json_file {
    my ($filepath, $weather_key) = @_;

    my $filename = "$filepath/$weather_key.json";

    # Existenz prüfen
    unless (-f $filename) {
        LOGWARN "File not found: $filename";
        return undef;
    }

    # Datei lesen und parsen
    my $json_text;
    eval {
        open my $fh, '<:raw', $filename or die "Cannot open $filename: $!";
        local $/;
        $json_text = <$fh>;
        close $fh;
    };
    if ($@) {
        LOGWARN "Failed to read $filename: $@";
        return undef;
    }

    # JSON-Deserialisierung    
    my $data;
    eval {
        $data = JSON::PP->new->utf8->decode($json_text);
    };
    if ($@) {
        LOGWARN "Failed to decode JSON from $filename: $@";
        return undef;
    }
    LOGOK "Read $filename weather data as JSON from $filename";

    return $data;
}


# ── write_daily_json ────────────────────────────────────────────────
# Accepts either:
#   write_daily_json($logdir, source => ..., grabber => ...)           # legacy: reads dailyforecast.dat
#   write_daily_json($logdir, data => \@records, source => ..., grabber => ...)  # direct: array of hashes

sub write_daily_json {
    my ($logdir, %opts) = @_;
    my $source  = $opts{source}  // '';
    my $grabber = $opts{grabber} // '';
    my $data    = $opts{data};     # optional arrayref of hashrefs

    my @records;
    if ($data) {
        # Direct path: caller provides array of record hashes
        for my $entry (@$data) {
            my %rec;
            for my $k (keys %$entry) {
                $rec{$k} = _val($entry->{$k});
            }
            _enrich_weather_id(\%rec);
            push @records, \%rec;
        }
    } else {
        # Legacy path: read from .dat file
        my $dat = "$logdir/dailyforecast.dat";
        return unless -f $dat;
        my @lines = _read_dat_lines($dat);
        return unless @lines;

        my $tz = _system_timezone();
        for my $line (@lines) {
            my %raw = _line_to_hash($line, \@DAILY_RAW);
            my %rec;
            $rec{period}   = _val($raw{period});
            $rec{datetime} = _epoch_to_iso($raw{epoch}, $tz);
            $rec{epoch}    = _val($raw{epoch});
            $rec{sunrise}  = _hhmm($raw{sunrise_hour}, $raw{sunrise_min});
            $rec{sunset}   = _hhmm($raw{sunset_hour},  $raw{sunset_min});

            for my $f (@DAILY_RAW) {
                next if $DROP_FORECAST{$f};
                next if $f eq 'epoch' || $f eq 'period';
                $rec{$f} = _val($raw{$f});
            }
            _enrich_weather_id(\%rec);
            push @records, \%rec;
        }
    }

    my $generated_at = strftime("%Y-%m-%dT%H:%M:%S%z", localtime(time));
    $generated_at =~ s/(\d{2})(\d{2})$/$1:$2/;

    my %envelope = (
        meta => {
            schema_version => "1.0",
            source         => $source,
            grabber        => $grabber,
            generated_at   => $generated_at,
        },
        data => \@records,
    );

    my $json_obj = JSON::PP->new->pretty->canonical->utf8;
    my $out = "$logdir/dailyforecast.json";
    my $tmp = "$out.tmp";
    eval {
        open my $fh, '>:raw', $tmp or die "Cannot open $tmp: $!";
        print $fh $json_obj->encode(\%envelope);
        close $fh;
        File::Copy::move($tmp, $out) or die "Cannot rename $tmp to $out: $!";
    };
    if ($@) {
        LOGWARN "JSON write failed for $out: $@";
        return;
    }
    LOGOK "Saved daily forecast data as JSON to $out";
}

# ── write_hourly_json ───────────────────────────────────────────────
# Accepts either:
#   write_hourly_json($logdir, source => ..., grabber => ...)           # legacy: reads hourlyforecast.dat
#   write_hourly_json($logdir, data => \@records, source => ..., grabber => ...)  # direct: array of hashes

sub write_hourly_json {
    my ($logdir, %opts) = @_;
    my $source  = $opts{source}  // '';
    my $grabber = $opts{grabber} // '';
    my $data    = $opts{data};     # optional arrayref of hashrefs

    my @records;
    if ($data) {
        # Direct path: caller provides array of record hashes
        for my $entry (@$data) {
            my %rec;
            for my $k (keys %$entry) {
                $rec{$k} = _val($entry->{$k});
            }
            _enrich_weather_id(\%rec);
            push @records, \%rec;
        }
    } else {
        # Legacy path: read from .dat file
        my $dat = "$logdir/hourlyforecast.dat";
        return unless -f $dat;
        my @lines = _read_dat_lines($dat);
        return unless @lines;

        my $tz = _system_timezone();
        for my $line (@lines) {
            my %raw = _line_to_hash($line, \@HOURLY_RAW);
            my %rec;
            $rec{period}   = _val($raw{period});
            $rec{datetime} = _epoch_to_iso($raw{epoch}, $tz);
            $rec{epoch}    = _val($raw{epoch});

            for my $f (@HOURLY_RAW) {
                next if $DROP_FORECAST{$f};
                next if $f eq 'epoch' || $f eq 'period';
                $rec{$f} = _val($raw{$f});
            }
            _enrich_weather_id(\%rec);
            push @records, \%rec;
        }
    }

    my $generated_at = strftime("%Y-%m-%dT%H:%M:%S%z", localtime(time));
    $generated_at =~ s/(\d{2})(\d{2})$/$1:$2/;

    my %envelope = (
        meta => {
            schema_version => "1.0",
            source         => $source,
            grabber        => $grabber,
            generated_at   => $generated_at,
        },
        data => \@records,
    );

    my $json_obj = JSON::PP->new->pretty->canonical->utf8;
    my $out = "$logdir/hourlyforecast.json";
    my $tmp = "$out.tmp";
    eval {
        open my $fh, '>:raw', $tmp or die "Cannot open $tmp: $!";
        print $fh $json_obj->encode(\%envelope);
        close $fh;
        File::Copy::move($tmp, $out) or die "Cannot rename $tmp to $out: $!";
    };
    if ($@) {
        LOGWARN "JSON write failed for $out: $@";
        return;
    }
    LOGOK "Saved hourly forecast data as JSON to $out";
}

1; # end of module