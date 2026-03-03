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

1; # end of module