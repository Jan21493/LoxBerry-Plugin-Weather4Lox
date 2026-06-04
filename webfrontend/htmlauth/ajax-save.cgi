#!/usr/bin/perl

# Copyright 2016-2023 Michael Schlenstedt, michael@loxberry.de
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

use CGI;
use JSON::PP;
use Encode;
use HTML::Entities qw(decode_entities);
use Scalar::Util qw(looks_like_number);
use LWP::UserAgent;
use Config::Simple '-strict';
use LoxBerry::System;
use LoxBerry::Web;

my $cgi = CGI->new;

# Load language strings and decode UTF-8 bytes to Perl character strings
# (readlanguage returns raw UTF-8 bytes; encode_json would double-encode them)
my %L = LoxBerry::System::readlanguage("language.ini");
for my $k (keys %L) {
    $L{$k} = Encode::decode('UTF-8', $L{$k}) unless Encode::is_utf8($L{$k});
}

sub no_cache_json_header {
    return $cgi->header(
        -type => "application/json",
        -charset => "utf-8",
        -Cache_Control => "no-store, no-cache, must-revalidate, max-age=0",
        -Pragma => "no-cache"
    );
}

sub json_out {
    my ($obj) = @_;
    print no_cache_json_header();
    print encode_json($obj);
    exit;
}

sub atomic_save_config {
    my ($cfg, $path) = @_;
    my $tmp = "$path.$$".time.".tmp";
    $cfg->write($tmp) or die "Could not write temp config: $!";
    rename($tmp, $path) or die "Could not rename temp config: $!";
}

# ---------- Only accept POST with form=1 ----------
my $form = $cgi->param('form') // '';
if ($form ne '1') {
    json_out({ ok => 0, error => "Only form=1 supported" });
}

# ---------- Run save synchronously ----------
my @checks;
my $has_error = 0;

eval {
    my $cfg = new Config::Simple("$lbpconfigdir/weather4lox.cfg");

    # Ensure URLs exist
    $cfg->param("OPENWEATHER.URL", "https://api.openweathermap.org/data");
    $cfg->param("WUNDERGROUND.URL", "https://api.weather.com/v2/pws/observations/current");
    $cfg->param("FOSHK.URL", "observations/current/json/units=m");
    $cfg->param("WEATHERFLOW.URL", "https://swd.weatherflow.com/swd/rest");
    $cfg->param("VISUALCROSSING.URL", "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline");
    $cfg->param("WTTRIN.URL", "https://wttr.in");
    $cfg->param("WETTERONLINE.URL-HOURLY", "https://api-app.wetteronline.de/app/weather/hourcast?");
    $cfg->param("WETTERONLINE.URL-DAILY", "https://api-app.wetteronline.de/app/weather/forecast?");
    $cfg->param("WETTERONLINE.URL-CURRENT", "https://www.wetteronline.de/wetter/");
    $cfg->param("OPENMETEOAIRQUALITY.URL", "https://air-quality-api.open-meteo.com/v1/air-quality");

    push @checks, $L{'SETTINGS.SAVING_SETTINGS'};

    # Read form parameters directly from POST
    my $R = {};
    for my $name ($cgi->param()) {
        $R->{$name} = $cgi->param($name);
    }

    # normalize coordinates
    for my $k (qw(coordlat coordlong)) {
        next unless defined $R->{$k};
        $R->{$k} =~ tr/,/./;
    }

    my $central_lat  = $R->{coordlat};
    my $central_long = $R->{coordlong};

    my $response;
    my $apicheck_error;

    if ( ( ($R->{getdata})         && ($R->{weatherservice}    // '') eq "openweather") ||
         ( ($R->{usealternatedfc}) && ($R->{weatherservicedfc} // '') eq "openweather") ||
         ( ($R->{usealternatehfc}) && ($R->{weatherservicehfc} // '') eq "openweather") ) {
        push @checks, "\n" . $L{'SETTINGS.SAVING_CHECK_OPENWEATHER'};
        my $url        = $cfg->param("OPENWEATHER.URL");
        my $apikey     = $R->{openweatherapikey} // '';
        my $stationid  = "lat=" . ($central_lat // '') . "&lon=" . ($central_long // '');
        my $oneCallURL = "$url/3.0/onecall?appid=$apikey&$stationid";
        push @checks, " - Checking One Call API: $oneCallURL";

        # Verify API call and check if response contains expected 'lat' element
        ($response, $apicheck_error) = verifyApiCall(url => $oneCallURL, path => ['lat']);
    }

    if (!$apicheck_error && ( ( ($R->{getdata})         && ($R->{weatherservice}    // '') eq "weatherflow") ||
                              ( ($R->{usealternatedfc}) && ($R->{weatherservicedfc} // '') eq "weatherflow") ||
                              ( ($R->{usealternatehfc}) && ($R->{weatherservicehfc} // '') eq "weatherflow") ) ) {
        push @checks, "\n" . $L{'SETTINGS.SAVING_CHECK_WEATHERFLOW'};
        my $url       = $cfg->param("WEATHERFLOW.URL");
        my $apikey    = $R->{weatherflowapikey} // '';
        my $stationid = $R->{weatherflowstationid} // '';
        my $queryURL  = "$url/observations/station/$stationid?token=$apikey";
        push @checks, " - Checking WeatherFlow API: $queryURL";

        # Verify API call and check if response contains expected 'station_id' element
        ($response, $apicheck_error) = verifyApiCall(url => $queryURL, path => ['station_id']);
    }

    if (!$apicheck_error && ( ( ($R->{getdata})         && ($R->{weatherservice}    // '') eq "visualcrossing") ||
                              ( ($R->{useweatherobs})      && ($R->{weatherserviceobs} // '') eq "visualcrossing") ||
                              ( ($R->{usealternatedfc}) && ($R->{weatherservicedfc} // '') eq "visualcrossing") ||
                              ( ($R->{usealternatehfc}) && ($R->{weatherservicehfc} // '') eq "visualcrossing") ) ) {
        push @checks, "\n" . $L{'SETTINGS.SAVING_CHECK_VISUALCROSSING'};
        my $url       = $cfg->param("VISUALCROSSING.URL");
        my $apikey    = $R->{visualcrossingapikey} // '';
        my $stationid = ($central_lat // '') . "," . ($central_long // '');
        my $queryURL  = "$url/$stationid?unitGroup=metric&include=current&key=$apikey&contentType=json";
        push @checks, " - Checking Visual Crossing API: $queryURL";

        # Verify API call and check if response contains expected 'latitude' element
        ($response, $apicheck_error) = verifyApiCall(url => $queryURL, path => ['latitude']);
    }

    if (!$apicheck_error && ( ( ($R->{getdata})         && ($R->{weatherservice}    // '') eq "wttrin") ||
                              ( ($R->{usealternatedfc}) && ($R->{weatherservicedfc} // '') eq "wttrin") ||
                              ( ($R->{usealternatehfc}) && ($R->{weatherservicehfc} // '') eq "wttrin") ) ) {
        push @checks, "\n" . $L{'SETTINGS.SAVING_CHECK_WTTRIN'};
        my $url       = $cfg->param("WTTRIN.URL");
        my $stationid = $R->{wttrinstationid} // '';
        my $queryURL  = "$url/$stationid?format=j1";
        push @checks, " - Checking WTTR.in API: $queryURL";

        # Verify API call and check if response contains expected 'weatherCode' element
        ($response, $apicheck_error) = verifyApiCall(url => $queryURL, path => ['current_condition', 0, 'weatherCode']);
    }

    if (!$apicheck_error && ( ( ($R->{getdata})         && ($R->{weatherservice}    // '') eq "wetteronline") ||
                              ( ($R->{usealternatedfc}) && ($R->{weatherservicedfc} // '') eq "wetteronline") ||
                              ( ($R->{usealternatehfc}) && ($R->{weatherservicehfc} // '') eq "wetteronline") ) ) {
        push @checks, "\n" . $L{'SETTINGS.SAVING_CHECK_WETTERONLINE'};
        my $url       = $cfg->param("WETTERONLINE.URL-CURRENT");
        my $stationid = $R->{wetteronlinestationid} // '';
        my $queryURL  = "$url$stationid";
        push @checks, " - Checking WetterOnline API: $queryURL";

        # Verify API call and check if response contains expected 'gid' element
        ($response, $apicheck_error) = verifyApiCall(
            url   => $queryURL,
            match => qr/WO\.geo = (\{(?:[^{}"]|"(?:[^"\\]|\\.)*"|(?1))*\});/s,
            path => ['gid']
        );
    }

    if (!$apicheck_error && ($R->{wugrabber} // '') ne '' && ($R->{wugrabber} // '') ne '0') {
        push @checks, "\n" . $L{'SETTINGS.SAVING_CHECK_WUNDERGROUND'};
        my $url       = $cfg->param("WUNDERGROUND.URL");
        my $stationid = $R->{wustationid} // '';
        my $dashURL   = "https://www.wunderground.com/dashboard/pws/$stationid";
        push @checks, " - 1. Checking Wunderground Dashboard: $dashURL";

        my ($apikey, $wu_err) = verifyApiCall(
            url   => $dashURL,
            match => qr/.*apiKey=([0-9a-z]*)\&.*/s
        );

        if ($wu_err) {
            $apicheck_error = $wu_err;
        } elsif ($apikey) {
            push @checks, " - Found API key for Wunderground: $apikey.";
            my $queryURL = "$url?apiKey=$apikey&stationId=$stationid&format=json&units=m";
            push @checks, " - 2. Checking if it works with API URL: $queryURL";

            # Verify API call and check if response contains expected 'obsTime' element
            ($response, $apicheck_error) = verifyApiCall(url => $queryURL, path => ['observations', 0, 'stationID']);
        } else {
            $apicheck_error = $L{'SETTINGS.SAVING_NO_DATA'};
        }
    }

    if ($apicheck_error) {
        $has_error = 1;
        push @checks, "\nERROR: $apicheck_error";
        json_out({ ok => 0, checks => \@checks, error => $apicheck_error });
    }

    push @checks, "\n" . $L{'SETTINGS.SAVING_WRITE_CONFIG'};

    # Write configuration file(s)
    $cfg->param("WUNDERGROUND.STATIONID", $R->{wustationid} // "");

    $cfg->param("OPENWEATHER.APIKEY", $R->{openweatherapikey} // "");

    $cfg->param("WEATHERFLOW.APIKEY", $R->{weatherflowapikey} // "");
    $cfg->param("WEATHERFLOW.STATIONID", $R->{weatherflowstationid} // "");

    $cfg->param("VISUALCROSSING.APIKEY", $R->{visualcrossingapikey} // "");

    $cfg->param("WTTRIN.STATIONID", $R->{wttrinstationid} // "");

    $cfg->param("WETTERONLINE.STATIONID", $R->{wetteronlinestationid} // "");
    $cfg->param("WETTERONLINE.APIKEY", "av=2&mv=13&c=d2ViOmFxcnhwWDR3ZWJDSlRuWeb=");

    $cfg->param("FOSHK.SERVER", $R->{foshkserver} // "");
    $cfg->param("FOSHK.PORT", $R->{foshkport} // "");

    $cfg->param("LOX.PREFIX", $R->{loxprefix} // "");

    $cfg->param("SERVER.PWSCATCHUPLOADGRABBER", $R->{pwscatchuploadgrabber} // "");
    $cfg->param("SERVER.WUGRABBER", $R->{wugrabber} // "");
    $cfg->param("SERVER.LOXGRABBER", $R->{loxgrabber} // "");
    $cfg->param("SERVER.FOSHKGRABBER", $R->{foshkgrabber} // "");
    $cfg->param("SERVER.OPENMETEOAIRQUALITYGRABBER", $R->{openmeteoairqualitygrabber} // "");

    $cfg->param("SERVER.USEALTERNATEDFC", $R->{usealternatedfc} // "");
    $cfg->param("SERVER.USEALTERNATEHFC", $R->{usealternatehfc} // "");
    $cfg->param("SERVER.USEWEATHEROBS", $R->{useweatherobs} // "");
    $cfg->param("SERVER.GETDATA", $R->{getdata} // "");
    $cfg->param("SERVER.CRON", $R->{cron} // "");
    $cfg->param("SERVER.CRON_ALTERNATE", $R->{cron_alternate} // "");
    $cfg->param("SERVER.CRON_LOCAL", $R->{cron_local} // "");
    $cfg->param("SERVER.CRON_OBS", $R->{cron_obs} // "");
    $cfg->param("SERVER.CRON_AIRQUALITY", $R->{cron_airquality} // "");
    $cfg->param("SERVER.METRIC", $R->{metric} // "");
    $cfg->param("SERVER.COORDLAT", $central_lat // "");
    $cfg->param("SERVER.COORDLONG", $central_long // "");
    $cfg->param("SERVER.LANG", $R->{serverlang} // "");
    $cfg->param("SERVER.WEATHERSERVICE", $R->{weatherservice} // "");
    $cfg->param("SERVER.WEATHERSERVICEDFC", $R->{weatherservicedfc} // "");
    $cfg->param("SERVER.WEATHERSERVICEHFC", $R->{weatherservicehfc} // "");
    $cfg->param("SERVER.WEATHERSERVICEOBS", $R->{weatherserviceobs} // "");
    $cfg->param("SERVER.MASKKEYS", $R->{maskkeys} // "");
    $cfg->param("SERVER.CITY", $R->{city} // "");
    $cfg->param("SERVER.COUNTRY", $R->{country} // "");

    push @checks, $L{'SETTINGS.SAVING_POLLEN'};

    $cfg->param("POLLEN.ALDER",   ( $R->{pollen_alder}   // 0 ) + 0);
    $cfg->param("POLLEN.BIRCH",   ( $R->{pollen_birch}   // 0 ) + 0);
    $cfg->param("POLLEN.GRASS",   ( $R->{pollen_grasses} // 0 ) + 0);
    $cfg->param("POLLEN.MUGWORT", ( $R->{pollen_mugwort} // 0 ) + 0);
    $cfg->param("POLLEN.OLIVE",   ( $R->{pollen_olive}   // 0 ) + 0);
    $cfg->param("POLLEN.RAGWEED", ( $R->{pollen_ragweed} // 0 ) + 0);
    
    atomic_save_config($cfg, "$lbpconfigdir/weather4lox.cfg");

    # Mirror pollen sensitivity into w4l-settings.json so the web client can read it
    {
        my %w4lSettings = (
            pollen => {
                alder   => ( $R->{pollen_alder}   // 0 ) + 0,
                birch   => ( $R->{pollen_birch}   // 0 ) + 0,
                grass   => ( $R->{pollen_grasses} // 0 ) + 0,
                mugwort => ( $R->{pollen_mugwort} // 0 ) + 0,
                olive   => ( $R->{pollen_olive}   // 0 ) + 0,
                ragweed => ( $R->{pollen_ragweed} // 0 ) + 0,
            }
        );
        my $settingsFile = "$lbphtmldir/w4l-settings.json";
        if (open my $fh, '>:utf8', $settingsFile) {
            print $fh JSON::PP->new->utf8->pretty->canonical->encode(\%w4lSettings);
            close $fh;
        }
    }

    push @checks, $L{'SETTINGS.SAVING_CRONJOB'};

    my $cronlink = "$lbhomedir/system/cron/cron.01min/$lbpplugindir";
    my $cronjob  = "$lbpbindir/cronjob.pl";

    if (($R->{getdata} // "") eq "1") {
        unlink $cronlink if -e $cronlink || -l $cronlink;
        symlink($cronjob, $cronlink)
            or die "Could not create symlink $cronlink -> $cronjob: $!";
    } else {
        unlink $cronlink if -e $cronlink || -l $cronlink;
    }

    push @checks, $L{'SETTINGS.SAVING_DONE'};
    1;
} or do {
    my $e = $@ || "unknown error";
    $has_error = 1;
    push @checks, "\nERROR: $e";
    json_out({ ok => 0, checks => \@checks, error => "$e" });
};

json_out({ ok => 1, checks => \@checks });

##########################################################################
# Verify API call for different weather services
# Parameters:
# - url: API URL to call
# - match: regular expression to extract specific part of response
# - path: path elements from API response, used to check if response contains this element
# Returns:
# - decoded JSON response, matched part, or value of path element
# - error message if API call fails

sub verifyApiCall {
    my (%p)          = @_;
    my $url          = $p{url}   // '';
    my $matchPattern = $p{match} // '';
    my @path         = @{ $p{path} // [] };

    my $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36";

    # Perform the API call
    my $ua  = LWP::UserAgent->new( agent => $userAgent );
    my $res = $ua->get($url);
    my $content = $res->decoded_content(charset => 'utf-8');

    # Check status of request
    my $urlstatus = $res->status_line;
    my $urlstatuscode = substr($urlstatus, 0, 3);
    push @checks, " - HTTP status: $urlstatus";

    # return error if API call fails
    if ($urlstatuscode eq "401") {
        return (undef, $L{'SETTINGS.SAVING_ERR_API_KEY'} . " URL: $url");
    } elsif ($urlstatuscode eq "440") {
        return (undef, $L{'SETTINGS.SAVING_ERR_NO_STATION'} . " URL: $url");
    } elsif ($urlstatuscode ne "200") {
        return (undef, sprintf($L{'SETTINGS.SAVING_ERR_NO_DATA'}, $urlstatuscode) . " URL: $url");
    }
    my $decodedJson;
    my $match;
    my $json = JSON::PP->new->relaxed->allow_barekey(1);

    # do regular expression match (if match is defined)
    if (defined $matchPattern && length $matchPattern) {
        push @checks, " - Searching for pattern match in response: $matchPattern";
        if ($content =~ $matchPattern) {
            $match = $1;
            # fix unquoted keys in JSON-like string (used by WetterOnline)
            $match =~ s/([{,]\s*)"?(\w+)"?\s*:/$1"$2":/g;

            my $is_json = 0;
            eval {
                $decodedJson = $json->decode($match);
                $is_json = 1;
            };
            if ($is_json) {
                push @checks, " - Found match in response (JSON), continuing...";
            } else {
                push @checks, " - Found match in response (no JSON), returning matched part directly.";
                # if match is found but not JSON, return matched part directly without trying to decode JSON, used e.g. by Wunderground to retrieve API key from public dashboard page
                return ($match, undef);
            }
        } else {
            return (undef, "Match NOT found in response for regex. URL: $url");
        }
    } else {
        $decodedJson = $json->decode("$content");
    }

    # if path is not defined, return whole decoded JSON response
    if (@path == 0) {
        push @checks, " - Returning JSON response, done!";
        return ($decodedJson, undef);
    }

    # check if decoded JSON contains expected path element
    my $cur = $decodedJson;
    push @checks, " - Looking for path element(s) in JSON response: " . join(" -> ", @path);
    for my $p (@path) {
        return (undef, "Path element(s) NOT found: Missing expected path element") unless defined $cur;

        if (ref $cur eq 'ARRAY') {
            return (undef, "Path element(s) NOT found: Invalid array index") unless defined $p && looks_like_number($p);
            my $idx = int($p);
            return (undef, "Path element(s) NOT found: Array index out of bounds") if $idx < 0 || $idx > $#$cur;
            $cur = $cur->[$idx];
        } elsif (ref $cur eq 'HASH') {
            return (undef, "Path element(s) NOT found: Missing key $p") unless exists $cur->{$p};
            $cur = $cur->{$p};
        } else {
            return (undef, "Path element(s) NOT found: Unexpected JSON structure");
        }
    }
    push @checks, " - Found value for path element(s): $cur, done with this check!";
    return ($cur, undef);
}
