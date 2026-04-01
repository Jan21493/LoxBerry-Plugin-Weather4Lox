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
#use JSON qw(encode_json decode_json);
use JSON::PP;
use Encode qw(decode_utf8);
use HTML::Entities qw(decode_entities);
use IO::Handle ();
use Scalar::Util qw(looks_like_number);
use LWP::UserAgent;
use Config::Simple '-strict';
use LoxBerry::System;
use LoxBerry::Web;

my $cgi = CGI->new;

# Load language strings (no template required for JSON API)
my %L = LoxBerry::System::readlanguage("language.ini");

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

sub valid_token {
    my ($t) = @_;
    return defined $t && $t =~ /^[0-9A-Za-z._-]{8,64}$/;
}

sub log_paths {
    my ($token) = @_;
    return (
        "/tmp/weather4lox_save_${token}.log",
        "/tmp/weather4lox_save_${token}.done",
        "/tmp/weather4lox_save_${token}.err",
        "/tmp/weather4lox_save_${token}.json",
    );
}

# ---------- STATUS ----------
if (defined $cgi->param('status')) {
    my $token = $cgi->param('status');

    if (!valid_token($token)) {
        json_out({ done => 1, log => "Invalid token\n" });
    }

    my ($logfile, $donefile, $errfile, $jsonfile) = log_paths($token);

    my $log = "";
    $log = decode_utf8(LoxBerry::System::read_file($logfile)) if -e $logfile;

    # Limit output size (last 10k chars)
    if (length($log) > 10000) {
        $log = substr($log, -10000);
    }

    my $done = (-e $donefile) ? 1 : 0;
    my $has_error = 0;

    if (-e $errfile) {
        my $err = decode_utf8(LoxBerry::System::read_file($errfile));
        $err = substr($err, -5000) if length($err) > 5000;
        $log .= "\nERROR:\n$err\n";
        $done = 1;
        $has_error = 1;
    }

    json_out({ done => $done, log => $log, has_error => $has_error });
}

# ---------- START ----------
if (defined $cgi->param('start')) {
    my $token = $cgi->param('token') // '';
    my $form  = $cgi->param('form')  // '';

    if (!valid_token($token)) {
        json_out({ ok => 0, error => "Invalid token" });
    }
    if ($form ne '1') {
        json_out({ ok => 0, error => "Only form=1 supported" });
    }

    my ($logfile, $donefile, $errfile, $jsonfile) = log_paths($token);
    unlink $logfile; unlink $donefile; unlink $errfile;

    # Params must have been saved as JSON by index.cgi
    if (!-e $jsonfile) {
        json_out({ ok => 0, error => "Missing params file $jsonfile (index.cgi must create it)" });
    }

    my $pid = fork();
    if (!defined $pid) {
        json_out({ ok => 0, error => "fork failed" });
    }

    if ($pid == 0) {
        # child / worker
        eval {
        run_worker($token);
        1;
        } or do {
        my $e = $@ || "unknown error";
        LoxBerry::System::write_file($errfile, $e);
        LoxBerry::System::write_file($donefile, "1\n");
        };
        exit 0;
    }

    # parent returns immediately
    json_out({ ok => 1 });
}

json_out({ ok => 0, error => "Invalid request" });

# ---------------- WORKER ----------------
sub run_worker {
    my ($token) = @_;

    my ($logfile, $donefile, $errfile, $jsonfile) = log_paths($token);

    # load original POST params saved by index.cgi
    my $raw = LoxBerry::System::read_file($jsonfile);
    my $R = decode_json($raw);

    # Load language strings (available via LoxBerry::System in the forked worker)
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
    $cfg->save();

    my $error;

    sub logline {
        my ($m) = @_;
        my $old = (-e $logfile) ? LoxBerry::System::read_file($logfile) : "";
        $old .= $m . "\n";
        # prevent runaway growth
        $old = substr($old, -200000) if length($old) > 200000;
        LoxBerry::System::write_file($logfile, $old);
    }

    logline($L{'SETTINGS.SAVING_SETTINGS'});

    # normalize coordinates
    for my $k (qw(wucoordlat wucoordlong coordlat coordlong)) {
        next unless defined $R->{$k};
        $R->{$k} =~ tr/,/./;
    }

    my $central_lat  = $R->{coordlat};
    my $central_long = $R->{coordlong};

    my $response;
    my $apicheck_error;

    if ( ( ($R->{weatherservice}    // '') eq "openweather") || 
         ( ($R->{weatherservicedfc} // '') eq "openweather") || 
         ( ($R->{weatherservicehfc} // '') eq "openweather") ) {
        logline("\n" . $L{'SETTINGS.SAVING_CHECK_OPENWEATHER'});
        my $url        = $cfg->param("OPENWEATHER.URL");
        my $apikey     = $R->{openweatherapikey} // '';
        my $stationid  = "lat=" . ($central_lat // '') . "&lon=" . ($central_long // '');
        my $oneCallURL = "$url/3.0/onecall?appid=$apikey&$stationid";
        logline(" - Checking API call to OpenWeather One Call API with URL: $oneCallURL");

        # Verify API call and check if response contains expected 'lat' element
        ($response, $apicheck_error) = verifyApiCall(url => $oneCallURL, path => ['lat']);
    }

    if (!$apicheck_error && ( ( ($R->{weatherservice}    // '') eq "weatherflow") || 
                              ( ($R->{weatherservicedfc} // '') eq "weatherflow") || 
                              ( ($R->{weatherservicehfc} // '') eq "weatherflow") ) ) {
        logline("\n" . $L{'SETTINGS.SAVING_CHECK_WEATHERFLOW'});
        my $url       = $cfg->param("WEATHERFLOW.URL");
        my $apikey    = $R->{weatherflowapikey} // '';
        my $stationid = $R->{weatherflowstationid} // '';
        my $queryURL  = "$url/observations/station/$stationid?token=$apikey";
        ($response, $apicheck_error) = verifyApiCall(url => $queryURL, path => ['station_id']);
    }

    if (!$apicheck_error && ( ( ($R->{weatherservice}    // '') eq "visualcrossing") || 
                              ( ($R->{weatherservicedfc} // '') eq "visualcrossing") || 
                              ( ($R->{weatherservicehfc} // '') eq "visualcrossing") ) ) {
        logline("\n" . $L{'SETTINGS.SAVING_CHECK_VISUALCROSSING'});
        my $url       = $cfg->param("VISUALCROSSING.URL");
        my $apikey    = $R->{visualcrossingapikey} // '';
        my $stationid = ($central_lat // '') . "," . ($central_long // '');
        my $queryURL  = "$url/$stationid?unitGroup=metric&include=current&key=$apikey&contentType=json";
        ($response, $apicheck_error) = verifyApiCall(url => $queryURL, path => ['latitude']);
    }

    if (!$apicheck_error && ( ( ($R->{weatherservice}    // '') eq "wttrin") || 
                              ( ($R->{weatherservicedfc} // '') eq "wttrin") || 
                              ( ($R->{weatherservicehfc} // '') eq "wttrin") ) ) {
        logline("\n" . $L{'SETTINGS.SAVING_CHECK_WTTRIN'});
        my $url       = $cfg->param("WTTRIN.URL");
        my $stationid = $R->{wttrinstationid} // '';
        my $queryURL  = "$url/$stationid?format=j1";
        ($response, $apicheck_error) = verifyApiCall(url => $queryURL, path => ['current_condition', 0, 'weatherCode']);
    }

    if (!$apicheck_error && ( ( ($R->{weatherservice}    // '') eq "wetteronline") || 
                              ( ($R->{weatherservicedfc} // '') eq "wetteronline") || 
                              ( ($R->{weatherservicehfc} // '') eq "wetteronline") ) ) {
        logline("\n" . $L{'SETTINGS.SAVING_CHECK_WETTERONLINE'});
        my $url       = $cfg->param("WETTERONLINE.URL-CURRENT");
        my $stationid = $R->{wetteronlinestationid} // '';
        my $queryURL  = "$url$stationid";
        ($response, $apicheck_error) = verifyApiCall(
        url   => $queryURL,
        match => qr/WO\.geo = (\{(?:[^{}"]|"(?:[^"\\]|\\.)*"|(?1))*\});/s,
        path => ['gid']
        );
    }

    if (!$apicheck_error && ($R->{wugrabber} // '') ne '' && ($R->{wugrabber} // '') ne '0') {
        logline("\n" . $L{'SETTINGS.SAVING_CHECK_WUNDERGROUND'});
        my $url       = $cfg->param("WUNDERGROUND.URL");
        my $stationid = $R->{wustationid} // '';
        my $dashURL   = "https://www.wunderground.com/dashboard/pws/$stationid";

        my ($apikey, $wu_err) = verifyApiCall(
        url   => $dashURL,
        match => qr/.*apiKey=([0-9a-z]*)\&.*/s
        );

        if ($wu_err) {
            $apicheck_error = $wu_err;
        } elsif ($apikey) {
            logline(" - Found API key for Wunderground: $apikey, checking if it works with API URL...");
            my $queryURL = "$url?apiKey=$apikey&stationId=$stationid&format=json&units=m";
            ($response, $apicheck_error) = verifyApiCall(url => $queryURL, path => ['observations', 0, 'stationID']);
        } else {
            $apicheck_error = $L{'SETTINGS.SAVING_NO_DATA'};
        }
    }

    if ($apicheck_error) {
        die $apicheck_error;
    }

    logline("\n" . $L{'SETTINGS.SAVING_WRITE_CONFIG'});

    # Write configuration file(s)
    $cfg->param("WUNDERGROUND.APIKEY", $R->{wuapikey} // "");
    $cfg->param("WUNDERGROUND.STATIONTYP", $R->{wustationtyp} // "");
    $cfg->param("WUNDERGROUND.STATIONID", $R->{wustationid} // "");
    $cfg->param("WUNDERGROUND.COORDLAT", $R->{wucoordlat} // "");
    $cfg->param("WUNDERGROUND.COORDLONG", $R->{wucoordlong} // "");
    $cfg->param("WUNDERGROUND.LANG", $R->{wulang} // "");

    $cfg->param("OPENWEATHER.APIKEY", $R->{openweatherapikey} // "");
    $cfg->param("OPENWEATHER.COORDLAT", $central_lat // "");
    $cfg->param("OPENWEATHER.COORDLONG", $central_long // "");
    $cfg->param("OPENWEATHER.LANG", $R->{serverlang} // "");

    $cfg->param("WEATHERFLOW.APIKEY", $R->{weatherflowapikey} // "");
    $cfg->param("WEATHERFLOW.LANG", $R->{serverlang} // "");
    $cfg->param("WEATHERFLOW.STATIONID", $R->{weatherflowstationid} // "");

    $cfg->param("VISUALCROSSING.APIKEY", $R->{visualcrossingapikey} // "");
    $cfg->param("VISUALCROSSING.COORDLAT", $central_lat // "");
    $cfg->param("VISUALCROSSING.COORDLONG", $central_long // "");
    $cfg->param("VISUALCROSSING.LANG", $R->{serverlang} // "");

    $cfg->param("WTTRIN.LANG", $R->{serverlang} // "");
    $cfg->param("WTTRIN.STATIONID", $R->{wttrinstationid} // "");

    $cfg->param("WETTERONLINE.STATIONID", $R->{wetteronlinestationid} // "");
    $cfg->param("WETTERONLINE.APIKEY", "av=2&mv=13&c=d2ViOmFxcnhwWDR3ZWJDSlRuWeb=");
    $cfg->param("WETTERONLINE.USERAGENT", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36");

    $cfg->param("FOSHK.SERVER", $R->{foshkserver} // "");
    $cfg->param("FOSHK.PORT", $R->{foshkport} // "");

    $cfg->param("SERVER.PWSCATCHUPLOADGRABBER", $R->{pwscatchuploadgrabber} // "");
    $cfg->param("SERVER.WUGRABBER", $R->{wugrabber} // "");
    $cfg->param("SERVER.LOXGRABBER", $R->{loxgrabber} // "");
    $cfg->param("SERVER.FOSHKGRABBER", $R->{foshkgrabber} // "");
    $cfg->param("SERVER.OPENMETEOAIRQUALITYGRABBER", $R->{openmeteoairqualitygrabber} // "");
    $cfg->param("OPENMETEOAIRQUALITY.COORDLAT", $central_lat // "");
    $cfg->param("OPENMETEOAIRQUALITY.COORDLONG", $central_long // "");

    $cfg->param("SERVER.USEALTERNATEDFC", $R->{usealternatedfc} // "");
    $cfg->param("SERVER.USEALTERNATEHFC", $R->{usealternatehfc} // "");
    $cfg->param("SERVER.GETDATA", $R->{getdata} // "");
    $cfg->param("SERVER.CRON", $R->{cron} // "");
    $cfg->param("SERVER.CRON_ALTERNATE", $R->{cron_alternate} // "");
    $cfg->param("SERVER.METRIC", $R->{metric} // "");
    $cfg->param("SERVER.COORDLAT", $central_lat // "");
    $cfg->param("SERVER.COORDLONG", $central_long // "");
    $cfg->param("SERVER.LANG", $R->{serverlang} // "");
    $cfg->param("SERVER.WEATHERSERVICE", $R->{weatherservice} // "");
    $cfg->param("SERVER.WEATHERSERVICEDFC", $R->{weatherservicedfc} // "");
    $cfg->param("SERVER.WEATHERSERVICEHFC", $R->{weatherservicehfc} // "");
    $cfg->param("SERVER.MASKKEYS", $R->{maskkeys} // "");

    $cfg->param("SERVER.CITY", $R->{city} // "");
    $cfg->param("SERVER.COUNTRY", $R->{country} // "");
    $cfg->param("VISUALCROSSING.STATION", $R->{city} // "");
    $cfg->param("VISUALCROSSING.COUNTRY", $R->{country} // "");
    $cfg->param("OPENWEATHER.STATION", $R->{city} // "");
    $cfg->param("OPENWEATHER.COUNTRY", $R->{country} // "");
    $cfg->param("WEATHERFLOW.CITY", $R->{city} // "");
    $cfg->param("WEATHERFLOW.COUNTRY", $R->{country} // "");

    $cfg->save();

    logline($L{'SETTINGS.SAVING_POLLEN'});

    $cfg->param("POLLEN.ALDER",   ( $R->{pollen_alder}   // 0 ) + 0);
    $cfg->param("POLLEN.BIRCH",   ( $R->{pollen_birch}   // 0 ) + 0);
    $cfg->param("POLLEN.GRASS",   ( $R->{pollen_grasses} // 0 ) + 0);
    $cfg->param("POLLEN.MUGWORT", ( $R->{pollen_mugwort} // 0 ) + 0);
    $cfg->param("POLLEN.OLIVE",   ( $R->{pollen_olive}   // 0 ) + 0);
    $cfg->param("POLLEN.RAGWEED", ( $R->{pollen_ragweed} // 0 ) + 0);
    $cfg->save();

    logline($L{'SETTINGS.SAVING_CRONJOB'});

    if (($R->{getdata} // "") eq "1") {
        system("ln -sf $lbpbindir/cronjob.pl $lbhomedir/system/cron/cron.01min/$lbpplugindir");
    } else {
        unlink("$lbhomedir/system/cron/cron.01min/$lbpplugindir");
    }

    logline($L{'SETTINGS.SAVING_DONE'});
    LoxBerry::System::write_file($donefile, "1\n");
}

##########################################################################
# Verify API call for different weather services
# Parameters:
# - url: API URL to call
# - match: regular expression to extract specific part of response (e.g. API key, station ID, geo coordinates, etc.) or '' to skip match
# - path: path elements (tree and param to retrieve) from API response, used to check if response contains this element
# Returns:
# - decoded JSON response from API call, matched part of response (if match is defined), or value of path element (if path is defined and match is not defined)
# - error message: if API call fails, match is defined but not found in response, or if decoded JSON does not contain expected path element

sub verifyApiCall {
    my (%p)          = @_;
    my $url          = $p{url}   // '';
    my $matchPattern = $p{match} // '';
    my @path         = @{ $p{path} // [] };

    my $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36";

    # Perform the API call
    my $ua  = LWP::UserAgent->new( agent => $userAgent );
    my $res = $ua->get($url);
    my $content = $res->decoded_content();

    # Check status of request
    my $urlstatus = $res->status_line;
    my $urlstatuscode = substr($urlstatus, 0, 3);
    logline(" - HTTP status: $urlstatus");

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
    my $json = JSON::PP->new->relaxed;
    $json = $json->utf8(1);
    $json = $json->relaxed(1);
    $json = $json->allow_barekey(1);

    # do regular expression match (if match is defined) and return matched part only, used e.g. by WetterOnline to retrieve API keys, station ID and geo coordinates
    if (defined $matchPattern && length $matchPattern) {
        logline(" - Searching for pattern match in response: $matchPattern");
        if ($content =~ $matchPattern) {
            $match = decode_entities($1);
            $match = decode_utf8($match);
            my $is_json = 0;
            eval {
                $decodedJson = $json->decode($match);
                $is_json = 1;
            };
            if ($is_json) {
                logline(" - Found match in response (JSON), continuing...");
            } else {
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
        logline(" - Returning JSON response, done!");
        return ($decodedJson, undef);
    }

    # check if decoded JSON contains expected path element and return its value
    my $cur = $decodedJson;
    logline(" - Looking for path element(s) in JSON response: " . join(" -> ", @path));
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
    logline(" - Found value for path element(s): $cur, done with this check!");
    return ($cur, undef);
}