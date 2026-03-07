#!/usr/bin/perl

# Shared dump helpers for Weather4Lox grabbers
#
# Intended usage in a grabber:
#   require "$lbpbindir/grabber_utils.pl";
#   my $decoded_json = api_call(
#   	url => "your_api_url_with_key_param_here",
#   	maskkeys => $maskkeys,  # optional, default: 1, used to mask keyparam in URLs and literal key value in dumps
#   	keyparam => 'key',      # optional, default: 'key' (the query parameter name to mask in URLs, e.g. 'appid' for OpenWeatherMap)
#   	apikey => '',   	    # optional, used to mask the key if it appears in the URL path or the response 
#   	info => "",             # optional, used for logging message to specify what data is being fetched (e.g. "current weather", "daily forecast", etc.)
#   );

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

my $useragent        = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36";

sub sanitize_url {
    my ($url, $keyparam) = @_;
    return $url if !defined $url;

    $keyparam ||= 'key';
    my $kp = quotemeta($keyparam);

    # Mask only the requested query parameter name
    $url =~ s/([?&]$kp=)[^&\s]*/$1***MASKED***/gi;
    return $url;
}

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

# ─── JSON export helpers ───────────────────────────────────────────────
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

# ── Helpers ─────────────────────────────────────────────────────────

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

sub write_current_json {
    my ($logdir) = @_;
    my $dat = "$logdir/current.dat";
    return unless -f $dat;
    my @lines = _read_dat_lines($dat);
    return unless @lines;

    my %raw = _line_to_hash($lines[0], \@CURRENT_RAW);
    my $tz  = $raw{tz_long} || _system_timezone();

    # Build clean record
    my %rec;

    # ISO datetime from epoch + tz
    $rec{datetime} = _epoch_to_iso($raw{epoch}, $tz);
    $rec{epoch}    = _val($raw{epoch});
    $rec{timezone} = $tz;

    # Sunrise / Sunset as "HH:MM"
    $rec{sunrise} = _hhmm($raw{sunrise_hour}, $raw{sunrise_min});
    $rec{sunset}  = _hhmm($raw{sunset_hour},  $raw{sunset_min});

    # Copy remaining fields (skip dropped ones)
    for my $f (@CURRENT_RAW) {
        next if $DROP_CURRENT{$f};
        next if $f eq 'epoch';   # already handled
        $rec{$f} = _val($raw{$f});
    }

    _enrich_weather_id(\%rec);

    my $json_obj = JSON::PP->new->pretty->canonical->utf8;
    my $out = "$logdir/current.json";
    open my $fh, '>:raw', $out or do { LOGWARN "Cannot write $out: $!"; return; };
    print $fh $json_obj->encode(\%rec);
    close $fh;
    LOGOK "Saved current weather data as JSON to $out";
}

# ── write_daily_json ────────────────────────────────────────────────

sub write_daily_json {
    my ($logdir) = @_;
    my $dat = "$logdir/dailyforecast.dat";
    return unless -f $dat;
    my @lines = _read_dat_lines($dat);
    return unless @lines;

    my $tz = _system_timezone();
    my @records;

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

    my $json_obj = JSON::PP->new->pretty->canonical->utf8;
    my $out = "$logdir/dailyforecast.json";
    open my $fh, '>:raw', $out or do { LOGWARN "Cannot write $out: $!"; return; };
    print $fh $json_obj->encode(\@records);
    close $fh;
    LOGOK "Saved daily forecast data as JSON to $out";
}

# ── write_hourly_json ───────────────────────────────────────────────

sub write_hourly_json {
    my ($logdir) = @_;
    my $dat = "$logdir/hourlyforecast.dat";
    return unless -f $dat;
    my @lines = _read_dat_lines($dat);
    return unless @lines;

    my $tz = _system_timezone();
    my @records;

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

    my $json_obj = JSON::PP->new->pretty->canonical->utf8;
    my $out = "$logdir/hourlyforecast.json";
    open my $fh, '>:raw', $out or do { LOGWARN "Cannot write $out: $!"; return; };
    print $fh $json_obj->encode(\@records);
    close $fh;
    LOGOK "Saved hourly forecast data as JSON to $out";
}

1; # end of module