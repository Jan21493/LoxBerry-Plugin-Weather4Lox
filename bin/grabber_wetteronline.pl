#!/usr/bin/perl

# grabber for fetching data from wetteronline.de
# fetches weather data (current and forecast) from wetteronline.de

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

##########################################################################
# Standard Modules (no error handling in case of missing modules)
##########################################################################

use LoxBerry::System;
use LoxBerry::Log;
use LWP::UserAgent;
use JSON::PP;
use File::Copy;
use File::Basename qw(basename);
use Getopt::Long;
use Time::Piece;
use HTTP::Request;
use utf8;
use Encode qw(encode_utf8);
use HTML::Entities;

require "$lbpbindir/grabber_utils.pl";

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

# params from config
my $pcfg             = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $city             = $pcfg->param("WETTERONLINE.STATIONID");

# names for JSON 
my $grabberFile     = basename(__FILE__);
my $grabberLabel    = "Wetter Online";
my $grabberKey      = "wetteronline";          # name in JSONs
my $refresh         = $pcfg->param("SERVER.CRON") // 60;

my $weatherKey;

# params for API calls
my $apiKey           = "av=2&mv=13&c=d2ViOmFxcnhwWDR3ZWJDSlRuWeb=";
my $apiKeyCurrent    = "c=d293ZWI6QzhMNFRINmVUbkRoVWFqYg==";
my $userAgentLocal   = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36";
my $urlGeoRaw        = "https://www.wetteronline.de/wetter/";
my $uriUvRaw         = "?prefpar=sun";
my $urlCurrentRaw    = "https://api-web.wo-cloud.com/weather/nowcast/v10?";
my $urlDailyRaw      = "https://api-app.wetteronline.de/app/weather/forecast?";
my $urlHourlyRaw     = "https://api-app.wetteronline.de/app/weather/hourcast?";

my $error = 0;

my $json = JSON::PP->new->relaxed;
$json = $json->utf8(1);
$json = $json->relaxed(1);
$json = $json->allow_barekey(1);

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
    package => 'weather4lox',
    name => "$grabberLabel",
    logdir => "$lbplogdir",
    #filename => "$lbplogdir/weather4lox.log",
    #append => 1,
);

# Commandline options
my $verbose = '';
my $current = '';
my $daily = '';
my $hourly = '';
my $maskKeys = 1;
GetOptions ('verbose'  => \$verbose,
            'interval=i' => \$refresh,
            'quiet'    => sub { $verbose = 0 },
            'current'  => \$current,
            'daily'    => \$daily,
            'hourly'   => \$hourly,
            'maskkeys' => \$maskKeys,
            );

if ($verbose) {
    $log->stdout(1);
    $log->loglevel(7);
}

LOGSTART "Weather4Lox $grabberLabel GRABBER process started";
LOGDEB "This is $0 Version $version";

requireOrLogdie('Astro::MoonPhase');

# all values in current, daily, and hourly JSONs are in local time, so proper time zone information is important
my $timezone = _systemTimezone();
LOGDEB "Using timezone: $timezone, current local system time is " . localtime->datetime;

if ($hourly) {
    #require_or_logdie('Lexical::Sub');
    requireOrLogdie('Math::Function::Interpolator');
    requireOrLogdie('Math::Function::Interpolator::Linear');
}

##########################################################################
# Searching for GID for selected city
sub findGid {
    my ($city, $body) = @_;
    
    if ($body =~ /gid : "([^"]+)"/s) {
        my $gid = $1;
        LOGDEB "The GID of city $city is $gid.";
        return $gid;
    } else {
        LOGCRIT "Failed to fetch GID for $city";
        die "Quit fetching GID.";
    }
}

#########################################################################
# Getting GEO data first to get lat and long for the API call for weather data

my $geodataMatch = apiCall(
    url => "$urlGeoRaw$city",
    # maskkeys => $maskKeys,    # no masking needed here as there are no secret API keys
    # keyparam => 'appid',
    # apikey => $apiKey, 
    info => "for Location $city (GEO data only)",
    match => qr/WO\.geo = (\{(?:[^{}"]|"(?:[^"\\]|\\.)*"|(?1))*\});/s,
);

$geodataMatch = decode_entities($geodataMatch);
$geodataMatch = encode_utf8($geodataMatch);
my $resGeodata = $json->decode($geodataMatch);
my $lat = $resGeodata->{lat};
my $long = $resGeodata->{lon};
my $altitude = $resGeodata->{alt};

if ($geodataMatch) {
    LOGDEB("Extracted GEO data:\n$geodataMatch");
    LOGDEB("-" x 80);
}
# my $gid = findGid($city, $geodataMatch); 
my $gid = $resGeodata->{gid}; 
if ($gid) {
    LOGDEB "The GID of city $city is $gid.";
} else {
    LOGCRIT "Failed to fetch GID for $city";
    die "Quit fetching GID.";
}

# Get weather data from wetteronline.de (API request) for current conditions
my $resCurrent = apiCall(
    url => "$urlCurrentRaw$apiKeyCurrent&grid_longitude=$long&grid_latitude=$lat&location_id=$gid&astro_longitude=$long" .
        "&astro_latitude=$lat&latitude=$lat&longitude=$long&timezone=$timezone&language=de-DE&timeformat=HH:mm&windunit=kmh" .
        "&system_of_measurement=metric&altitude=$altitude",
    # maskkeys => $maskKeys,    # no masking needed here as there are no secret API keys
    # keyparam => 'appid',
    # apikey => $apiKey,
    info => "for Location $city (Current Weather Data)",
);

# Get weather data from wetteronline.de (API request) for daily conditions
my $resDaily = apiCall(
    url => "$urlDailyRaw$apiKey&location_id=$gid&timezone=$timezone",
    # maskkeys => $maskKeys,    # no masking needed here as there are no secret API keys
    # keyparam => 'appid',
    # apikey => $apiKey,
    info => "for Location $city (Daily Weather Data)",
);

# Get weather data from wetteronline.de (API request) for hourly conditions
my $resHourly = apiCall(
    url => "$urlHourlyRaw$apiKey&location_id=$gid&timezone=$timezone",
    # maskkeys => $maskKeys,    # no masking needed here as there are no secret API keys
    # keyparam => 'appid',
    # apikey => $apiKey,
    info => "for Location $city (Hourly Weather Data)",
);

my $t;
my $weather;
my $code;
my $icon;
my $description;
my $wdir;
my $wdirdes;
my @filecontent;
my $i;

# Mapping: Wetteronline codes => [Loxone code, Weather4Lox code] # Description
# Weather codes with meaning: https://www.wetteronline.de/symbole
# --> Using https://wiki.loxberry.de/plugins/weather4loxone/start#wetter-codes
        

# Position: 1 2 3 4 5 6
# Beispiel: m d s n 1 _

# Position 1-2: Tageszeit + Bewölkung

# Code    Bedeutung
# so      Sonnig (Tag)
# mo      Klar (Nacht)

# wb      Leicht bewölkt (Tag)
# mb      Leicht bewölkt (Nacht)

# bw      Bewölkt (Tag)
# mw      Bewölkt (Nacht)

# bd      Bedeckt (Tag)
# md      Bedeckt (Nacht)

# ns      Nebel (Tag)
# nm      Nebel (Nacht)
# nb      Nebel

# Position 3-6: Niederschlagsart, aufgefüllt mit Unterstrichen, wenn kein Niederschlag oder Code kürzer ist

# Code    Bedeutung
# ____    Kein Niederschlag

# für alle Bewölkungsarten:
#   wb, mb - leicht bewölkt mit Symbol für Tag und Nacht (Wolken sind keiner als Sonne/Mond)
#   bw, mw - bewölkt mit Symbol für Tag und Nacht (Wolken sind größer als Sonne/Mond)
#   bd, md - bedeckt, haben gleiches Symbol für Tag und Nacht (nur Woklen, keine Sonne/Mond)

# gibt es die Kombination mit Niederschlag in unterschiedlichen Intensitäten/Varianten
#  s1-s3       Schauer (Intensität 1-3 - Leicht, Mittel, Stark), Intensität 1-3 wird durch Anzahl der Tropfen im Symbol dargestellt
#  r1-r3       Regen (Intensität 1-3 - Leicht, Mittel, Stark), Symbole wie s1-s3
#  g1-g3       Gewitter (Intensität 1-3 - Leicht, Mittel, Stark), Symbol mit einem Blitz, Intensität 1-2 wird durch Anzahl der Tropfen im Symbol dargestellt, bei 3 zusätzlich Warndreieck
#  sn1-sn3     Schneefall (Intensität 1-3 - Leicht, Mittel, Stark), Intensität 1-3 wird durch Anzahl der Schneeflocken im Symbol dargestellt
#  sr1-sr3     Schneeregen (Intensität 1-3 - Leicht, Mittel, Stark), bei allen Intensitäten immer ein Tropfen und eine Schneeflocke im Symbol
#  snr1-snr3   Schneeregen, siehe sr1-sr3
#  srs1-srs3   Schneeregenschauer, Symbole wie sr

#  gr1-gr2     Gefrierender Regen (Intensität 1-2 - Leicht, Stark)
#  gs1-gs2     Graupelschauer (Intensität 1-2 - Leicht, Stark)
#  hs1-hs2     Hagelschauer (Intensität 1-2 - Leicht, Stark)

#  ek    Eiskörner
#  sg    Schneegestöber (Schneegewitter), Symbol mit Schneeflocke und Blitz

# mapping is created from https://www.wetteronline.de/symbole
# additional symbols that are not listed in the overview but are used in practice were added after verifying symbol, e.g. "bw___", "mw___"
my %wetteronlineToLox = (

    # in Farbe: https://st.wetteronline.de/dr/1.1.617/city/prozess/graphiken/symbole/standard/farbe/png/50x35/so____.png
    # in SW:    https://st.wetteronline.de/dr/1.1.617/city/prozess/graphiken/symbole/wom/standard/sw/gif/so____.gif
    # aktuelles Wetter in Farbe: https://st.wetteronline.de/dr/1.1.617/aktuell/prozess/graphiken/symbole/standard/farbe/gif/so____.gif

    # clouds in steps from clear to overcast, each with code for day and night (kept in mapping for clarity)
    "so____" => [ 1, "clear", "Sonnig"],                                                   # sonnig bzw. klar / wolkenlos (Tag)
    "mo____" => [ 1, "clear", "Klar"],                                                     # sonnig bzw. klar / wolkenlos (Nacht)
    "wb____" => [ 2, "partly_cloudy", "Teilweise bewölkt"],                                # leicht bewölkt (Tag)
  # "mb____" => [ 2, "partly_cloudy", "Teilweise bewölkt"],                                # leicht bewölkt (Nacht)
    "bw____" => [ 3, "cloudy", "Bewölkt"],                                                 # Bewölkt (Tag)
  # "mw____" => [ 3, "cloudy", "Bewölkt"],                                                 # Bewölkt (Nacht)
    "bd____" => [ 5, "overcast", "Bedeckt"],                                               # bedeckt (Tag)
  # "md____" => [ 5, "overcast", "Bedeckt"],                                               # Bedeckt (Nacht)

    # fog/haze
    "ns____" => [ 6, "mist", "Teils neblig"],                                              # teils neblig (Tag)
  # "nm____" => [ 6, "mist", "Teils neblig"],                                              # teils neblig (Nacht)
    "nb____" => [ 6, "fog", "Nebelig"],                                                    # neblig / Nebel

	# Schauer

    # Schauer (mit Tag und Nacht) bei leicht bewölkt
    "wbs1__" => [16, "cloudy_shower_1", "Leicht bewölkt mit vereinzelten Regenschauern"],  # leicht bewölkt und vereinzelt Schauer
    "wbs2__" => [16, "cloudy_shower_1", "Leicht bewölkt mit Regenschauern"],               # leicht bewölkt und Schauer
    "wbs3__" => [12, "cloudy_shower_2", "Leicht bewölkt mit starken Regenschauern"],       # leicht bewölkt und Starke Regenschauer 

    # Schauer (mit Tag und Nacht) bei bewölkt
    "bws1__" => [16, "cloudy_shower_1", "Bewölkt mit vereinzelten Regenschauern"],         # bewölkt und vereinzelt Schauer
    "bws2__" => [16, "cloudy_shower_2", "Bewölkt mit Regenschauern"],                      # bewölkt und Schauer
    "bws3__" => [12, "cloudy_shower_3", "Bewölkt mit starken Regenschauern"],              # bewölkt und Starke Regenschauer

    # Schauer (mit Tag und Nacht) bei bedeckt
    "bds1__" => [10, "overcast_shower_1", "Bedeckt mit vereinzelten Regenschauern"],       # Leichter Regenschauer
    "bds2__" => [11, "overcast_shower_2", "Bedeckt mit Regenschauern"],                    # Regenschauer
    "bds3__" => [12, "overcast_shower_3", "Bedeckt mit starken Regenschauern"],            # Starker Regenschauer

	# Regen

    # Regen (Tag und Nacht) bei leicht bewölkt
    "wbr1__" => [16, "cloudy_rain_1", "Leicht bewölkt mit leichtem Regen"],                # leicht bewölkt und leichter Regen
    "wbr2__" => [11, "cloudy_rain_1", "Leicht bewölkt mit Regen"],                         # leicht bewölkt und Regen
    "wbr3__" => [12, "cloudy_rain_2", "Leicht bewölkt mit starker Regen"],                 # leicht bewölkt und Starker Regen

    # Regen (Tag und Nacht) bei bewölkt
    "bwr1__" => [16, "cloudy_rain_1", "Bewölkt mit leichtem Regen"],                       # bewölkt und leichter Regen
    "bwr2__" => [11, "cloudy_rain_2", "Bewölkt mit Regen"],                                # bewölkt und Regen
    "bwr3__" => [12, "cloudy_rain_2", "Bewölkt mit starker Regen"],                        # bewölkt und Starker Regen

    # Regen (Tag und Nacht) bei bedeckt
    "bdr1__" => [16, "overcast_rain_1", "Bedeckt mit Regenschauern"],                      # bedeckt, etwas Regen oder vereinzelt Schauer
    "bdr2__" => [11, "overcast_rain_2", "Bedeckt mit Regen"],                              # bedeckt, Regen oder Schauer
    "bdr3__" => [12, "overcast_rain_3", "Bedeckt mit ergiebigem Regen"],                   # bedeckt und ergiebiger Regen

	# Schneeregenschauer

    # Schneeregenschauer (Tag und Nacht) bei leicht bewölkt
    "wbsrs1" => [28, "cloudy_sleet_1", "Leicht bewölkt mit vereinzelten Schneeregenschauern"],         # leicht bewölkt und vereinzelt Schneeregenschauer
    "wbsrs2" => [28, "cloudy_sleet_1", "Leicht bewölkt mit Schneeregenschauern"],                      # leicht bewölkt und Schneeregenschauer
    "wbsrs3" => [29, "cloudy_sleet_2", "Leicht bewölkt mit starken Schneeregenschauern"],              # leicht bewölkt und Schneeregenschauer

    # Schneeregenschauer (Tag und Nacht) bei bewölkt
    "bwsrs1" => [28, "cloudy_sleet_1", "Bewölkt mit vereinzelten Schneeregenschauern"],                # bewölkt und vereinzelt Schneeregenschauer
    "bwsrs2" => [28, "cloudy_sleet_2", "Bewölkt mit Schneeregenschauern"],                             # bewölkt und Schneeregenschauer
    "bwsrs3" => [29, "cloudy_sleet_2", "Bewölkt mit starken Schneeregenschauern"],                     # bewölkt und Schneeregenschauer

    # Schneeregenschauer (Tag und Nacht) bei bedeckt
    "bdsrs1" => [25, "overcast_sleet_1", "Bedeckt mit Leichten Schneeregenschauern"],                  # bedeckt, leichter Schneeregen oder vereinzelt Schneeregenschauer
    "bdsrs2" => [26, "overcast_sleet_2", "Bedeckt mit Schneeregenschauern"],                           # bedeckt, Schneeregen oder Schneeregenschauer
    "bdsrs3" => [27, "overcast_sleet_3", "Bedeckt mit ergiebigen Schneeregenschauern"],                # bedeckt und ergiebiger Schneeregen

    # Schneeregen

    # leicht bewölkt und Schneeregen (Tag und Nacht)
    "wbsr1_" => [25, "cloudy_sleet_1", "Leicht bewölkt mit leichtem Schneeregen"],                     # leicht bewölkt und vereinzelt Schneeregen (Tag)
    "wbsr2_" => [26, "cloudy_sleet_2", "Leicht bewölkt mit Schneeregen"],                              # leicht bewölkt und Schneeregen (Tag)
    "wbsr3_" => [27, "cloudy_sleet_2", "Leicht bewölkt mit starkem Schneeregen"],                      # leicht bewölkt und ergiebiger Schneeregen (Tag)

    # bewölkt und Schneeregen (Tag und Nacht)
    "bwsr1_" => [25, "cloudy_sleet_1", "Bewölkt mit leichtem Schneeregen"],                            # bewölkt und vereinzelt Schneeregen (Tag)
    "bwsr2_" => [26, "cloudy_sleet_2", "Bewölkt mit Schneeregen"],                                     # bewölkt und Schneeregen (Tag)
    "bwsr3_" => [27, "cloudy_sleet_2", "Bewölkt mit starkem Schneeregen"],                             # bewölkt und ergiebiger Schneeregen (Tag)

    # bedeckt und Schneeregen (Tag und Nacht)
    "bdsr1_" => [25, "overcast_sleet_1", "Bedeckt mit leichtem Schneeregen"],                          # bedeckt, leichter Schneeregen oder vereinzelt Schneeregenschauer
    "bdsr2_" => [26, "overcast_sleet_2", "Bedeckt mit Schneeregen"],                                   # bedeckt, Schneeregen oder Schneeregenschauer
    "bdsr3_" => [27, "overcast_sleet_3", "Bedeckt mit ergiebigem Schneeregen"],                        # bedeckt und ergiebiger Schneeregen

    # Schneeschauer

    # leicht bewölkt und Schneeschauer
    "wbsns1" => [23, "cloudy_snow_1", "Leicht bewölkt mit leichten Schneeschauern"],                   # leicht bewölkt und vereinzelt Schneeschauer (Tag)
    "wbsns2" => [24, "cloudy_snow_1", "Leicht bewölkt mit Schneeschauern"],                            # leicht bewölkt und Schneeschauer (Tag)
    "wbsns3" => [24, "cloudy_snow_2", "Leicht bewölkt mit starken Schneeschauern"],                    # leicht bewölkt und starke Schneeschauer (Tag)

    # bewölkt und Schneeschauer
    "bwsns1" => [23, "cloudy_snow_1", "Bewölkt mit leichten Schneeschauern"],                          # bewölkt und vereinzelt Schneeschauer (Tag)
    "bwsns2" => [24, "cloudy_snow_2", "Bewölkt mit Schneeschauern"],                                   # bewölkt und Schneeschauer (Tag)
    "bwsns3" => [24, "cloudy_snow_2", "Bewölkt mit starken Schneeschauern"],                           # bewölkt und starke Schneeschauer (Tag)

    # bedeckt und Schneeschauer
    "bdsns1" => [23, "overcast_snow_1", "Bedeckt mit leichten Schneeschauern"],                        # bedeckt, leichter Schneefall oder vereinzelt Schneeschauer
    "bdsns2" => [24, "overcast_snow_2", "Bedeckt mit Schneeschauern"],                                 # bedeckt, Schneefall oder Schneeschauer
    "bdsns3" => [24, "overcast_snow_3", "Bedeckt mit starken Schneeschauern"],                         # bedeckt und ergiebiger Schneefall

    # Schneefall

    # leicht bewölkt und Schneefall
    "wbsn1_" => [20, "cloudy_snow_1", "Leicht bewölkt mit leichtem Schneefall"],                        # leicht bewölkt und vereinzelt Schneefall (Tag)
    "wbsn2_" => [21, "cloudy_snow_2", "Leicht bewölkt mit Schneefall"],                                 # leicht bewölkt und Schneefall (Tag)
    "wbsn3_" => [22, "cloudy_snow_2", "Leicht bewölkt mit starkem Schneefall"],                         # leicht bewölkt und starker Schneefall (Tag)

    # bewölkt und Schneefall
    "bwsn1_" => [20, "cloudy_snow_1", "Bewölkt mit leichtem Schneefall"],                               # bewölkt und vereinzelt Schneefall (Tag)
    "bwsn2_" => [21, "cloudy_snow_2", "Bewölkt mit Schneefall"],                                        # bewölkt und Schneefall (Tag)
    "bwsn3_" => [22, "cloudy_snow_2", "Bewölkt mit starkem Schneefall"],                                # bewölkt und starker Schneefall (Tag)

    # bedeckt und Schneefall
    "bdsn1_" => [20, "overcast_snow_1", "Bedeckt mit leichtem Schneefall"],                             # bedeckt, leichter Schneefall oder vereinzelt Schneeschauer (Tag)
    "bdsn2_" => [21, "overcast_snow_2", "Bedeckt mit Schneefall"],                                      # bedeckt, Schneefall oder Schneeschauer (Tag)
    "bdsn3_" => [22, "overcast_snow_3", "Bedeckt mit ergiebigem Schneefall"],                           # bedeckt und ergiebiger Schneefall (Tag)

    # Schnegewitter

    # leicht bewölkt und Schneegewitter
    "wbsg__" => [24, "cloudy_snowthunderstorm_1", "Leicht bewölkt mit vereinzelten Wintergewittern"],   # leicht bewölkt und Schneegewitter (Tag)

    # bewölkt und Schneegewitter
    "bwsg__" => [24, "cloudy_snowthunderstorm_2", "Bewölkt mit Wintergewittern"],                       # bewölkt und Schneegewitter (Tag)

    # bedeckt und Schneegewitter
    "bdsg__" => [24, "cloudy_snowthunderstorm_2", "Bedeckt mit Wintergewittern"],                       # bedeckt und Schneegewitter (Tag)

    # Gewitter

    # leicht bewölkt mit Gewitter (Tag und Nacht)
    "wbg1__" => [18, "cloudy_thunderstorm_1", "Leicht bewölkt mit vereinzelten Gewittern"],             # leicht bewölkt, vereinzelt Schauer und Gewitter (Tag)
    "wbg2__" => [18, "cloudy_thunderstorm_2", "Leicht bewölkt mit Gewittern"],                          # leicht bewölkt, Schauer und Gewitter (Tag)
    "wbg3__" => [19, "cloudy_thunderstorm_3", "Leicht bewölkt mit kräftigen Gewittern"],                # leicht bewölkt, Schauer und Gewitter (Tag)

    # Bewölkt mit Gewitter (Tag und Nacht)
    "bwg1__" => [18, "cloudy_thunderstorm_1", "Bewölkt mit vereinzelten Gewittern"],                    # bewölkt, vereinzelt Schauer und Gewitter (Tag)
    "bwg2__" => [18, "cloudy_thunderstorm_2", "Bewölkt mit Gewittern"],                                 # Gewitter (Tag)
    "bwg3__" => [19, "cloudy_thunderstorm_3", "Bewölkt mit kräftigen Gewittern"],                       # starke Gewitter (Tag)

    # Bedeckt mit Gewitter (Tag und Nacht)
    "bdg1__" => [18, "overcast_thunderstorm_1", "Bedeckt mit vereinzelten Gewittern"],                  # bedeckt, vereinzelt Schauer und Gewitter
    "bdg2__" => [18, "overcast_thunderstorm_2", "Bedeckt mit Gewittern"],                               # bedeckt, Gewitter (Tag)
    "bdg3__" => [18, "overcast_thunderstorm_3", "Bedeckt mit schweren Gewittern"],                      # bedeckt, schwere Gewitter (Tag)

    # gefrierender Regen

    # leicht Bewölkt mit gefrierendem Regen (Tag und Nacht)
    "wbgr1_" => [14, "cloudy_freezingrain_1", "Leicht bewölkt mit gefrierendem Sprühregen"],            # bewölkt und gefrierender Sprühregen (Tag)
    "wbgr2_" => [14, "cloudy_freezingrain_2", "Leicht bewölkt mit gefrierendem Regen"],                 # bewölkt und gefrierender Regen (Tag)

    # Bewölkt mit gefrierendem Regen (Tag und Nacht)
    "bwgr1_" => [14, "cloudy_freezingrain_1", "Bewölkt mit gefrierendem Sprühregen"],                   # bewölkt und gefrierender Sprühregen (Tag)
    "bwgr2_" => [14, "cloudy_freezingrain_2", "Bewölkt mit gefrierendem Regen"],                        # bewölkt und gefrierender Regen (Tag)

    # Bedeckt mit gefrierendem Regen (Tag und Nacht)
    "bdgr1_" => [14, "overcast_freezingrain_1", "Bedeckt mit gefrierendem Sprühregen"],                 # bedeckt und gefrierender Sprühregen (Tag)
    "bdgr2_" => [14, "overcast_freezingrain_2", "Bedeckt mit gefrierendem Regen"],                      # bedeckt und gefrierender Regen (Tag)

    # Graupel, Hagel und Eiskörner (Tag und Nacht)
    "bwgs1_" => [28, "overcast_graupel", "Leichte Graupelschauer"],                                     # leichte Graupelschauer
    "bwgs2_" => [26, "overcast_graupel", "Graupelschauer"],                                             # Graupelschauer

    "bwhs1_" => [28, "overcast_hail_1", "Leichte Hagelschauer"],                                        # leichte Hagelschauer
    "bwhs2_" => [26, "overcast_hail_2", "Hagelschauer"],                                                # Hagelschauer

    "bwek__" => [26, "overcast_icepellets", "Eiskörner"],                                               # Eiskörner
);

# Convert night symbols with clouds to day symbols to reduce the lookup table
my %nightToDayPrefix = (
    'mb' => 'wb',  # lightly cloudy night -> lightly cloudy day
    'mw' => 'bw',  # cloudy night -> cloudy day
    'md' => 'bd',  # overcast night -> overcast day
    'nm' => 'ns',  # partly foggy night -> partly foggy day
);

# TODO: second value is not used anymore
my %skyConditionByPrefix = (
  # Clear / (mostly) sunny
  'so' => [  0, 'clear' ],          # sunny
  'mo' => [  0, 'clear' ],          # clear

  # cloudy - wetteronline does not provide 5 codes for cloudiness as METAR
  'wb' => [ 33, 'fair' ],           # mostly sunny to partly cloudy
  'bw' => [ 66, 'cloudy' ],         # partly cloudy to cloudy

  # overcast
  'bd' => [100, 'overcast' ],       # overcast

  # Fog / haze (treat as overcast-like sky condition)
  'ns' => [100, 'fog' ],            # partly foggy
  'nb' => [100, 'fog' ],            # fog
);

sub skyConditionFromWoCode {
    my ($woCode) = @_;

    # Check for empty/undefined values
    if (!defined $woCode || length($woCode) < 2) {
        LOGWARN "Wetteronline symbol '$woCode' (to calculate sky condition) is undefined!";
        return (undef);
    }
    # only the first two characters are relevant for sky condition
    my $prefix = substr($woCode, 0, 2);
    # Convert night symbols to day symbols for sky condition calculation
    if (exists $nightToDayPrefix{$prefix}) {
        $prefix = $nightToDayPrefix{$prefix};
    }
    my $entry  = $skyConditionByPrefix{$prefix};

    if ($entry && ref($entry) eq 'ARRAY' && @$entry >= 2) {
        return ($entry->[0]);
    }

    LOGWARN "Unknown Wetteronline symbol prefix '$prefix' for sky condition, using 'Unknown' as fallback.";
    return (undef);
}

sub wetteronlineToLox {
    my ($woCode) = @_;
    
    # Check for empty/undefined values
    if (!defined $woCode || $woCode eq "") {
        LOGWARN "Wetteronline symbol is empty or was not found in data set!";
        return (1, "clear", "No data");  # Default fallback
    }

    if (defined $woCode && length($woCode) >= 2) {
        $woCode =~ s/^(.{2})snr(.)$/${1}sr${2}_/;  # Convert "snr" to "sr" for Schneeregen
        my $prefix = substr($woCode, 0, 2);
        if (exists $nightToDayPrefix{$prefix}) {
            substr($woCode, 0, 2, $nightToDayPrefix{$prefix});
        }
    }
    
    # Lookup in the table
    my $result = $wetteronlineToLox{$woCode};
    
    if ($result) {
        return @$result;  # Returns (code, icon, description)
    } else {
        LOGWARN "Unknown weather symbol from Wetteronline: '$woCode', using 'clear' as fallback.";
        return (1, "clear", "No data");  # Default fallback
    }
}

my %nightSymbol = map { $_ => 1 } qw(mo mb mw md nm);  # Define night symbols for quick lookup

sub isNighttime {
    my ($symbol) = @_;

    return ($nightSymbol{ substr($symbol, 0, 2) });  # Return 1 if it's a night symbol
}


##########################################################################
# Fetch common data
##########################################################################

# date/time in different ways for different use cases in W4L (e.g. epoch for calculations, ISO format for display, timezone info for reference)
my $dtCurrent = _parseIso8601($resCurrent->{current}->{date});   # returns epoch

my ($tzShort, $tzOffset);
{
    local $ENV{TZ} = $timezone;
    POSIX::tzset();
    $tzShort  = POSIX::strftime('%Z', localtime($dtCurrent));
    $tzOffset = POSIX::strftime('%z', localtime($dtCurrent));
}
POSIX::tzset();

# location information
my $cityName = getValue($resGeodata, 'locationname');
if (defined getValue($resGeodata, 'sublocationname') && 
    getValue($resGeodata, 'sublocationname') ne "") {
        $cityName .= ", " . getValue($resGeodata, 'sublocationname');
}
my $path = getValue($resGeodata, 'path');                  
my @locpath = $path ? split(/;/, $path) : ();
my $country = $locpath[5] // undef; 

# add location information once
my $location = {
    city         => $cityName,                                                           # cur_loc_n, e.g. "Schwarzenbek"
    country      => $country,                                                            # country name, e.g. Deutschland
    countryCode  => getValue($resGeodata, 'location_info', 'geoObject', 'iso-3166-1'),   # country code
    elevation    => getFormatted('%.0f', $resGeodata, 'alt'),                            # altitude in meters
    latitude     => getFormatted('%.3f', $resGeodata, 'lat'),                            # latitude
    longitude    => getFormatted('%.3f', $resGeodata, 'lon'),                            # longitude
    timezone     => $timezone,                                                           # timezone string (e.g. "Europe/Berlin")
    tzShort      => $tzShort,                                                            # timezone abbreviation (e.g. "CET")
    tzOffset     => $tzOffset,                                                           # timezone offset (e.g. "+0100")
};


##########################################################################
# Fetch current data
##########################################################################

if ( $current ) {

    # Build clean record
    my %currentData;

    LOGINF "Reading current weather data from API response into W4L structure at " . _epochToIso($dtCurrent, $timezone) . ".";

    my %time;
    # $time{date}      = getValue($resCurrent, 'current', 'date');
    $time{datetime}  = _epochToIso($dtCurrent, $timezone);                                                                     # cur_date_des
    $time{epoch}     = $dtCurrent;                                                                                              # cur_date

    # cur_date_tz_des (e.g. Europe/Berlin), cur_date_tz_des_sh (e.g. "CET"), cur_date_tz (e.g. "+0100") are send in location section 

    $currentData{time} = \%time;

    # sunrise and set in local time, e.g. 05:47 and 17:39
    $currentData{sunrise} = getTimeFormatted('%H:%M', $timezone, $resCurrent, 'current', 'sun', 'rise');                       # cur_sun_r 
    $currentData{sunset}  = getTimeFormatted('%H:%M', $timezone, $resCurrent, 'current', 'sun', 'set');                        # cur_sun_s

    # temperatures
    my %temperature;

    $temperature{air}        = getFormatted('%.1f', $resCurrent, 'current', 'temperature', 'air');                             # cur_tt.    - air temperature in °C
    $temperature{feelsLike}  = getFormatted('%.1f', $resCurrent, 'current', 'temperature', 'apparent');                        # cur_tt_fl  - feels like temperature in °C
    $temperature{windChill}  = undef;                                                                                          # cur_w_ch   - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
    $temperature{heatIndex}  = undef;                                                                                          # cur_hi.    - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures

    $currentData{temperature} = \%temperature;

    # humidity
    $currentData{humidity} = getPercentage('%.2f', $resCurrent, 'current', 'humidity');                                        # cur_hu, in percentage
    
    # wind
    my %wind;

    my $windDirection = getValue($resCurrent, 'current', 'wind', 'direction');

    $wind{direction}      = $windDirection;                                                                                    # cur_w_dir, wind direction in degrees
    $wind{cardinal}       = getWindDirCardinal($windDirection);                                                                # to calculate cur_w_dirdes, wind direction description, e.g. "Süden",
    $wind{speed}          = getFormatted('%.1f', $resCurrent, 'current', 'wind', 'speed', 'kilometer_per_hour', 'value');      # cur_w_sp, wind speed in km/h
    $wind{gust}           = getFormatted('%.1f', $resCurrent, 'current', 'wind', 'speed', 'kilometer_per_hour', 'max_gust');   # cur_w_gu, gust speed in km/h

    $currentData{wind} = \%wind;

    # air pressure
    $currentData{pressure} = getFormatted('%.0f', $resCurrent, 'current', 'air_pressure', 'hpa');                              # cur_pr, air pressure in hPa

    # dew point
    $currentData{dewpoint} = getFormatted('%.1f', $resCurrent, 'current', 'dew_point', 'celsius');                             # cur_dp, dew point in °C

    # visibility
    $currentData{visibility} = getFormattedMultiplied('%.2f', 0.001, $resCurrent, 'hours', 0, 'visibility');                   # cur_vis, visibility in km (API provides meters)

    # solar radiation
    $currentData{solarRadiation} = undef;                                                                                      # cur_sr, solar radiation in W/m²

    # there is no UV index in the API response for current weather data, nor on the web page itself or 
    # hourly forecast data, but there is one for daily forecast
    # not sure if this should be the UV index for the current time or the day (maximum)
    $currentData{uvIndex} = do {
        my $v = eval { $resDaily->[0]{uv_index}{value} };
        defined $v ? ( sprintf("%.0f", $v ) + 0 ) : undef;
    };                                                                                                                         # cur_uvi, UV index

    # precipitation
    my %precipitation;

    $precipitation{rainToday} = getFormatted('%.2f', $resCurrent, 
        'trend', 'items', 0, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end');                     # cur_prec_today, today precipitation in mm

    $precipitation{rain1hr} = getFormatted('%.2f', $resCurrent, 
        'hours', 'items', 0, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end');                     # cur_prec_1h, 1-hour precipitation in mm
    $precipitation{probability} = getPercentage('%.2f', $resCurrent, 'current', 'precipitation', 'probability');               # cur_pop, probability in percent
    $precipitation{type} = getValue($resCurrent, 'current', 'precipitation', 'type');                                          # type of precipitation (rain, snow), undef, if it is currently not raining/snowing
    $precipitation{snowToday} = getFormatted('%.2f', $resCurrent, 
        'trend', 'items', 0, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end');                         # cur_snow_today, today snow in cm
    $precipitation{snow1hr} = getFormatted('%.2f', $resCurrent, 
        'hours', 'items', 0, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end');                         # cur_snow_1h, 1-hour snow in cm

    $currentData{precipitation} = \%precipitation;

    # weather codes
    my %weatherCode;

    # Mapping: Wetteronline Symbol => [Loxone code, Weather4Lox code, description]
    my ($loxoneCode, $w4lCode, $desc);
    my $symbol = getValue($resCurrent, 'current', 'symbol');
    if (!defined $symbol) {
        LOGWARN "Wetteronline symbol for current weather is undefined!";
        ($loxoneCode, $w4lCode, $desc) = (5, 'no_data', 'No description for weather symbol');  # Default fallback
    } else {
        ($loxoneCode, $w4lCode, $desc) = wetteronlineToLox($symbol);
    }

    $weatherCode{loxone}      = $loxoneCode;                                                                                  # cur_code
    $weatherCode{weather4lox} = $w4lCode;                                                                                     # cur_icon
    $weatherCode{description} = $desc;                                                                                        # cur_des
    $weatherCode{image}       = getValue($resCurrent, 'current', 'weather_condition_image');                                  # future use, e.g. as background image
    $weatherCode{metar}       = getMetarCode($w4lCode);                                                                       # future use, e.g. scientific theme

    $currentData{weatherCode} = \%weatherCode;

    # ozone (cur_ozone) - API does not provide ozone values
    
    # sky condition - calculate from symbol code
    $currentData{cloudCover} = skyConditionFromWoCode($symbol);                                                                # cur_sky

    # astro data
    my %moon;

    my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = Astro::MoonPhase::phase();
    # age is delivered by API, , but makes no sense as phase() delivers all values
    # $moon{age} = getFormatted('%.2f', $resCurrent, 'moon', 0, 'age');
    $moon{age} = sprintf("%.2f",$moonage) + 0;                                                                                 # cur_moon_a, moon age in days
    $moon{percent} = sprintf("%.2f",$moonillum * 100) + 0;                                                                     # cur_moon_p, moon illumination in percent
    $moon{phase} = sprintf("%.2f",$moonphase * 100) + 0;                                                                       # cur_moon_ph, moon phase in percent (0% = new moon, 50% = half moon, 100% = full moon)
    $moon{direction} = getMoonDirection($moonage);                                                                             #                - moon direction (waxing, waning)

    $currentData{moon} = \%moon;
    
    # night time - used for selecting day or night symbol (eighter night time or undef)
    $currentData{isNight} = isNighttime($symbol);

    # Build envelope and write JSON to file
    $weatherKey = "current";
    my $generatedAt = localtime->datetime;
    my $envelope = {
        refresh  => $refresh,
        generatedAt     => $generatedAt,
        location => $location,
        $grabberKey => {
            filename        => "$lbplogdir/$weatherKey.json",
            generatedAt     => $generatedAt,
            grabberLabel    => $grabberLabel,
            grabberScript   => $grabberFile,
            schemaVersion   => "v1.0",
        },
        $weatherKey => \%currentData, 
    };
    writeJsonFile($lbplogdir, $weatherKey, $envelope);

} # End current

##########################################################################
# Fetch daily data
##########################################################################

if ( $daily ) {
  
    my @dailyData;
    my $dtResult;
    my $results;
    my $day = 0;               # used for days, starts with 0 for current day, 1 for next day, etc.

    LOGINF "Reading daily weather data from API response into W4L structure at $dtCurrent.";

    # it is assumed, that the elements are ordered by time (ascending)
    for my $results (@{$resDaily}) {

        # values with additional calculations needs to be done before hash is assigned

        # time
        $dtResult = _parseIso8601(getValue($results, 'date'));   # ISO date from API in UTC, e.g. 2026-03-13T23:00:00+00:00
        
        # wind
        my $windDirAvg = getFormatted('%.0f', $results, 'wind', 'direction'); 

        # Mapping: Wetteronline Symbol => [Loxone code, Weather4Lox code, description]
        my ($loxoneCode, $w4lCode, $description);
        my $symbol = getValue($results, 'symbol');
        if (!defined $symbol) {
            LOGWARN "Wetteronline symbol for daily weather is undefined!";
            ($loxoneCode, $w4lCode, $description) = (5, 'no_data', 'No description for weather symbol'); # Default fallback
        } else {
            ($loxoneCode, $w4lCode, $description) = wetteronlineToLox($symbol);
        }

        # astro data - get moon infos for specific time of data set (translated to epoch time)
        my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = Astro::MoonPhase::phase($dtResult);

        # Calculating min, max values from dayparts
        # humidity (min, max)
        # wind (max) for speed, gust, and direction

        my $humidityMin  = 100; # 100%
        my $humidityMax  = 0;   # 0%

        my $windSpeedMax = -1;
        my $windGustMax  = -1;
        my $windDirMax   = 0;

        # get values for all four dayparts and calculate min and max for the day
        my @dayParts = @{ getValue($results, 'dayparts') // undef };
        if (!@dayParts) {
            LOGWARN "No dayparts found for daily data on date " . getValue($results, 'date') . ", min/max values will be set to null.";
            $humidityMin = undef;
            $humidityMax = undef;

            $windSpeedMax = undef;
            $windGustMax = undef;
            $windDirMax = undef;
        } else {
            foreach my $dayPart (@dayParts) {
                my $humidity = getPercentage('%.1f', $dayPart, 'humidity');

                if (defined $humidity){
                    if ($humidity < $humidityMin) {
                        $humidityMin = $humidity;
                    }
                    if ($humidity > $humidityMax) {
                        $humidityMax = $humidity;
                    }
                }

                my $windSpeed = getFormatted('%.1f', $dayPart, 'wind', 'speed', 'kilometer_per_hour', 'value') // 0;
                my $windGust = getFormatted('%.1f', $dayPart, 'wind', 'speed', 'kilometer_per_hour', 'max_gust') // 0;
                my $windDir = getFormatted('%.0f', $dayPart, 'wind', 'direction') // 0;

                if ($windSpeed > $windSpeedMax) {
                    $windSpeedMax = $windSpeed;
                    $windDirMax = $windDir;
                }
                # if gust is present, it has preference for direction
                if ($windGust > $windGustMax) {
                    $windGustMax = $windGust;
                    $windDirMax = $windDir;
                }
            }
        }

        # dewpoint calculation
        my $dewpointAvg;
        @dayParts = @{ getValue($results, 'dayparts') // undef };
        my $sum = 0; 
        my $cnt = 0;
        for my $dayPart (@dayParts) {
            my $dewpoint = getFormatted('%.1f', $dayPart, 'dew_point', 'celsius');
            $sum += $dewpoint if defined $dewpoint;
            $cnt++ if defined $dewpoint;
        }
        $dewpointAvg = $cnt ? sprintf("%.1f", $sum / $cnt) + 0 : undef;

        push @dailyData, {

            day            => $day,                                              # dfc<X>_per, counter of day
            time => {
                # date       => getValue($results, 'date'),                      # original timestamp from API
                datetime     => _epochToIso($dtResult, $timezone),        # ISO 8601 date string in local time (e.g. "2026-03-13T02:00:00+01:00")
                epoch        => $dtResult,                                # dfc<X>_date       - UNIX timestamp
                # wdayName   => $wdayname,                                       # name of day of week, e.g. Saturday  - TODO: verify if useful, client may calculate name as well
                # wdayShort  => $wdayshort,                                      # short name of day of week, e.g. Sa (two chars)
                # monthName  => $monthname,                                      # name of month, e.g. March
                # monthShort => $monthshort,                                     # name of month, e.g. Mar (three chars
            },
            temperature => {
                min => {
                    air         => getFormatted('%.1f', $results, 'temperature', 'min', 'air'),         # dfc<X>_tt_l      - daily min temperature (°C)
                    feelsLike   => getFormatted('%.1f', $results, 'temperature', 'min', 'apparent'),    # dfc<X>_tt_fl_l   - min feels-like temperature
                    windChill   => undef,                                                               # hfc<X>_w_ch      - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
                },
                max => {
                    air         => getFormatted('%.1f', $results, 'temperature', 'max', 'air'),         # dfc<X>_tt_h      - daily max temperature (°C)
                    feelsLike   => getFormatted('%.1f', $results, 'temperature', 'max', 'apparent'),    # dfc<X>_tt_fl_h   - max feels-like temperature
                    heatIndex   => undef,                                                               # hfc<X>_hi        - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures
                },
            },
            wind => {
                avg => {
                    direction       => $windDirAvg,                                                                            # dfc<X>_w_dir_a     - wind direction (degree, average)
                    cardinal        => getWindDirCardinal($windDirAvg),                                                        # to calculate dfc<X>_w_dirdes_a  - wind direction description (average)
                    speed           => getFormatted('%.2f', $results, 'wind', 'speed', 'kilometer_per_hour', 'value'),         # dfc<X>_w_sp_a      - wind speed average (km/h)
                    gust            => getFormatted('%.2f', $results, 'wind', 'speed', 'kilometer_per_hour', 'max_gust'),      # dfc<X>_w_gu_a      - wind gust average (km/h)
                },
                max => {
                    direction       => $windDirMax,                                                                            # dfc<X>_w_dir_h     - wind direction (degree, max)
                    cardinal        => getWindDirCardinal($windDirMax),                                                        # to calculate dfc<X>_w_dirdes_h  - wind direction description (max)
                    speed           => $windSpeedMax,                                                                          # dfc<X>_w_sp_h      - wind speed max (km/h)
                    gust            => $windGustMax,                                                                           # dfc<X>_w_gu_h      - wind gust max (km/h)
                }
            },
            precipitation => {
                probability   => getPercentage('%.2f', $results, 'precipitation', 'probability'),                                                # dfc<X>_pop        - probability of precipitation (%)
                duration      => getFormatted('%.2f', $results, 'precipitation', 'duration', 'hours'),                                           #                   - duration of precipitation
                rainLow       => getFormatted('%.2f', $results, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_begin'),  #                   - precipitation (mm) from
                rainHigh      => getFormatted('%.2f', $results, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end'),    # dfc<X>_prec       - precipitation (mm) up to
                type          => getValue($results, 'precipitation', 'type'),                                                                    #                   - precipitation type
                snowLow       => getFormatted('%.2f', $results, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_begin'),      #                   - snow height (cm) from
                snowHigh      => getFormatted('%.2f', $results, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end'),        # dfc<X>_snow       - snow height (cm) up to
            },
            weatherCode => {
                loxone        => $loxoneCode,                                                   # dfc<X>_we_code   - Loxone code
                weather4lox   => $w4lCode,                                                      # dfc<X>_we_icon   - Weather4Lox icon code
                description   => $description,                                                  # dfc<X>_we_des    - description
                image         => getValue($results, 'weather_condition_image'),                 #                  - future use., e.g. as background image
                metar         => getMetarCode($w4lCode),                                        #                  - METAR code
            },
            moon => {
                age        => getFormatted('%.2f', $results, 'moon', 'age'),                    # dfc<X>_moon_a    - moon age in days
                rise       => getTimeFormatted('%H:%M', $timezone, $results, 'moon', 'rise'),   #                  - moon rise in ISO time
                set        => getTimeFormatted('%H:%M', $timezone, $results, 'moon', 'set'),    #                  - moon set in ISO time
                percent    => sprintf("%.2f", $moonillum * 100) + 0,                            # dfc<X>_moon_p.   - moon percent
                phase      => sprintf("%.2f", $moonphase * 100) + 0,                            # dfc<X>_moon_ph.  - moon phase
                direction  => getMoonDirection($moonage),                                       #                  - moon direction (waxing, waning)
            },
            humidity       => {
                avg        =>  getPercentage('%.1f', $results, 'humidity'),                     # dfc<X>_hu_a      - average humidity
                min        =>  $humidityMin,	                                                # dfc0_hu_l        - minimum humidity
                max        =>  $humidityMax,                                                    # dfc<X>_hu_h.     - maximum humidity
            },
            pressure         => getFormatted('%.0f', $results, 'air_pressure', 'hpa'),          # dfc<X>_pr        - air pressure (hPa)
            dewpoint         => $dewpointAvg,                                                   # dfc<X>_dp        - average dew point (°C)
            uvIndex          => getFormatted('%.1f', $results, 'uv_index', 'value'),            # dfc<X>_uvi       - UV index
            sunrise          => getTimeFormatted('%H:%M', $timezone, $results, 'sun', 'rise'),  # dfc<X>_sun_r     - sunrise time (HH:MM)
            sunset           => getTimeFormatted('%H:%M', $timezone, $results, 'sun', 'set'),   # dfc<X>_sun_s     - sunset time (HH:MM)
                                                                                                # dfc<X>_vis       - visibility (m/km as needed)
                                                                                                # dfc<X>_sr        - solar radiation (not present)
                                                                                                # dfc<X>_hi        - heat index (not present)
                                                                                                # dfc<X>_ozone     - ozone (not present)
            cloudCover       => skyConditionFromWoCode($symbol),                                # dfc<X>_sky       - cloud/sky cover (percentage from 0 to 100)
        };
        $day++;
    }
 
    # Build envelope and write JSON to file
    $weatherKey = "dailyforecast";
    my $generatedAt = localtime->datetime;
    my $envelope = {
        refresh  => $refresh,
        generatedAt     => $generatedAt,
        location => $location,
        $grabberKey => {
            filename        => "$lbplogdir/$weatherKey.json",
            generatedAt     => $generatedAt,
            grabberLabel    => $grabberLabel,
            grabberScript   => $grabberFile,
            schemaVersion   => "v1.0",
        },
        $weatherKey => \@dailyData, 
    };
    writeJsonFile($lbplogdir, $weatherKey, $envelope);

} # End daily

##########################################################################
# Fetch hourly data
##########################################################################

if ( $hourly ) {

    my @hourlyData;
    my $dtResult;
    my $results;
    my $hour = 1;                # used for hours, starts with 1 for first forecasted hour, 2 for next hour, etc.

    LOGINF "Reading hourly weather data from API response into W4L structure at $dtCurrent.";

    # it is assumed, that the elements are ordered by time (ascending)
    for my $results (@{$resHourly->{hours}}) {

        # values with additional calculations needs to be done before hash is assigned

        # time
        $dtResult = DateTime::Format::ISO8601->parse_datetime(getValue($results, 'date'));   # ISO date from API in UTC, e.g. 2026-03-13T23:00:00+00:00
        $dtResult->set_time_zone($timezone);

        # wind
        my $windDir     = getFormatted('%.0f', $results, 'wind', 'direction'); 

        # Mapping: Wetteronline Symbol => [Loxone code, Weather4Lox code, description]
        my ($loxoneCode, $w4lCode, $description);
        my $symbol = getValue($results, 'symbol');
        if (!defined $symbol) {
            LOGWARN "Wetteronline symbol for hourly weather is undefined!";
            ($loxoneCode, $w4lCode, $description) = (5, 'no_data', 'No description for weather symbol');
        } else {
            ($loxoneCode, $w4lCode, $description) = wetteronlineToLox($symbol);
        }

        # astro data - get moon infos for specific time of data set (translated to epoch time)
        my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = Astro::MoonPhase::phase($dtResult);

        # Get sunrise and sunset time from daily data, needed for isNighttime calculation
        my $isNighttime = undef; # default to day (undef)

        for my $dailyresults (@{$resDaily}) {
            if (substr(getValue($dailyresults, 'date'), 0, 10) eq substr(getValue($results, 'date'), 0, 10)) {
                # we found the matching daily data for the current hourly data, now we can check the dayparts for precipitation type

                if ($dtResult->strftime('%H:%M') lt getTimeFormatted('%H:%M', $timezone, $dailyresults, 'sun', 'rise') || 
                    $dtResult->strftime('%H:%M') gt getTimeFormatted('%H:%M', $timezone, $dailyresults, 'sun', 'set')) {
                    $isNighttime = 1;
                    last; # break loop if we found the matching day and determined it is nighttime
                }
            }
        }

        push @hourlyData, {
            hour           => $hour,                                             # hfc<X>_per, counter of day
            time => {
                # date       => getValue($results, 'date'),                      # original timestamp from API
                datetime     => _epochToIso($dtResult, $timezone),        # ISO 8601 date string in local time (e.g. "2026-03-13T02:00:00+01:00")
                epoch        => $dtResult,                                # hfc<X>_date       - UNIX timestamp
            },
            temperature => {
                air            => getFormatted('%.1f', $results, 'temperature', 'air'),         # hfc<X>_tt        - hourly max temperature (°C)
                feelsLike      => getFormatted('%.1f', $results, 'temperature', 'apparent'),    # hfc<X>_tt_fl     - min feels-like temperature
                                                                                                # hfc<X>_hi        - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures
                                                                                                # hfc<X>_w_ch      - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
            },
            wind => {
                direction     => $windDir,                                                                                   # hfc<X>_w_dir     - wind direction (degree)
                cardinal      => getWindDirCardinal($windDir),                                                               # to calculate hfc<X>_w_dirdes  - wind direction description
                speed         => getFormatted('%.2f', $results, 'wind', 'speed', 'kilometer_per_hour', 'value'),             # hfc<X>_w_sp      - wind speed (km/h)
                gust          => getFormatted('%.2f', $results, 'wind', 'speed', 'kilometer_per_hour', 'max_gust'),          # hfc<X>_w_gu      - wind gust (km/h)
            },
            precipitation => {
                probability   => getPercentage('%.2f', $results, 'precipitation', 'probability'),                                                # hfc<X>_pop         - probability of precipitation (%)
                duration      => getValue($results, 'precipitation', 'duration', 'hours'),                                                       #                    - duration of precipitation
                rainLow       => getFormatted('%.2f', $results, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_begin'),  #                    - precipitation (mm) from
                rainHigh      => getFormatted('%.2f', $results, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end'),    # hfc<X>_prec        - precipitation (mm) up to
                type          => getValue($results, 'precipitation', 'type'),                                                                    #                    - precipitation type
                snowLow       => getFormatted('%.2f', $results, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_begin'),      #                    - snow height (cm) from
                snowHigh      => getFormatted('%.2f', $results, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end'),        # hfc<X>_snow        - snow height (cm) up to
            },
            weatherCode => {
                loxone       => $loxoneCode,                                                       # hfc<X>_we_code   - Loxone code
                weather4lox  => $w4lCode,                                                          # hfc<X>_we_icon   - Weather4Lox icon code
                description  => $description,                                                      # hfc<X>_we_des    - description
                metar        => getMetarCode($w4lCode),                                            #                  - METAR code
            },
            moon => {
                age          => sprintf("%.2f", $moonage) + 0,                                     # hfc<X>_moon_a    - moon age in days
                percent      => sprintf("%.2f", $moonillum * 100) + 0,                             # hfc<X>_moon_p    - moon percentage
                phase        => sprintf("%.2f", $moonphase * 100) + 0,                             # hfc<X>_moon_ph   - moon phase
                direction    => getMoonDirection($moonage),                                        #                  - moon direction (waxing, waning)

            },
            humidity         => getPercentage('%.1f', $results, 'humidity'),                       # hfc<X>_hu        - humidity
            pressure         => getFormatted('%.0f', $results, 'air_pressure', 'hpa'),             # hfc<X>_pr        - air pressure (hPa)
            dewpoint         => getFormatted('%.1f', $results, 'dew_point', 'celsius'),            # hfc<X>_dp        - dew point (°C)
            uvIndex          => getFormatted('%.1f', $results, 'uv_index', 'value'),               # hfc<X>_uvi       - UV index
            visibility       => getFormattedMultiplied('%.0f', 0.001, $results, 'visibility'),     # hfc<X>_vis       - visibility (m/km as needed), API provides meters
                                                                                                   # hfc<X>_sr        - solar radiation (not present)
                                                                                                   # hfc<X>_ozone     - ozone (not present)
            cloudCover       => skyConditionFromWoCode($symbol),                                   # hfc<X>_sky       - cloud/sky cover (percentage from 0 to 100)
            isNight          => $isNighttime,                                                      # get nighttime information from sunrise / sunset, alternate solution woudl be from symbol code
        };
        $hour++;
    }

	# WetterOnline only offers 32h hourly forecast, the rest is retriveved by interpolating the daily forecast data.

	# 1. Step: Collect all support points from $resDaily by crawling through all available 'dayparts'. Each day has an
    #          array with 4 "dayparts" (at 05:00, 11:00, 17:00, 23:00) containing weather data for the corresponding time interval

    # create hashes for different parameters
	my (%t_air,             # temperatur air 
       %t_app,              # temperatur feels like
       %hum,                # humidity
       %w_dir,              # wind direction
       %w_sp_kmh,           # wind speed
       %w_gu_kmh,           # wind gust
       %pr_hpa,             # pressure
       %dp_c,               # dew point
       %uvidx,              # uv index
       %prec_dur,           # precipitation duration
       %prec_mm_low,        # precipitation (rain in mm)
       %prec_mm_high,       # precipitation (rain in mm)
       %snow_cm_low,        # precipitation (snow in cm)
       %snow_cm_high,       # precipitation (snow in cm)
       %pop_pct,            # precipitation (propability, percentage)
    );
    my (%symbol,            # symbol - do not interpolate
        %c_img,             # weather image - do not interpolate
        %prec_type,         # precipitation type
    );
    my @dpEpochs;
	
    # Collect support points for all days, each with 4 dayparts
	for my $dailyResults (@{$resDaily}) {
		my @dayParts = @{$dailyResults->{dayparts}};

		for my $dayPart (@dayParts) {
			# Convert daypart timestamp to epoch seconds
			my $ep = DateTime::Format::ISO8601->parse_datetime(getValue($dayPart, 'date'))->epoch;   # ISO date from API is in UTC, e.g. 2026-03-13T23:00:00+00:00

			push @dpEpochs, $ep;

			# Temperatures
			$t_air{$ep} = getFormatted('%.1f', $dayPart, 'temperature', 'air') // 0;
			$t_app{$ep} = getFormatted('%.1f', $dayPart, 'temperature', 'apparent') // 0;

			# Humidity (0..1) -> store as percent (0..100) and interpolate in that domain
			$hum{$ep} = getPercentage('%.2f', $dayPart, 'humidity');

			# Wind direction (deg) and speed (km/h)
			$w_dir{$ep}    = getFormatted('%.0f', $dayPart, 'wind', 'direction') // 0;
			$w_sp_kmh{$ep} = getFormatted('%.2f', $dayPart, 'wind', 'speed', 'kilometer_per_hour', 'value') // 0;
			$w_gu_kmh{$ep} = getFormatted('%.2f', $dayPart, 'wind', 'speed', 'kilometer_per_hour', 'max_gust') // 0;

			# Pressure / dew point
			$pr_hpa{$ep} = getFormatted('%.0f', $dayPart, 'air_pressure', 'hpa') // 0;
			$dp_c{$ep}   = getFormatted('%.1f', $dayPart, 'dew_point', 'celsius') // 0;

			# Rain amount: mean of interval begin/end (if present)
			if ($dayPart->{precipitation}{details}{rainfall_amount}{millimeter}) {
				$prec_mm_low{$ep} = getFormatted('%.2f', $dayPart, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_begin') // 0;
                $prec_mm_high{$ep} = getFormatted('%.2f', $dayPart, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end') // 0;
			} else {
				$prec_mm_low{$ep} = 0;  
                $prec_mm_high{$ep} = 0;              
            }

			# Snow height (cm)
			if ($dayPart->{precipitation}{details}{snow_height}{centimeter}) {
				$snow_cm_low{$ep} = getFormatted('%.2f', $dayPart, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_begin') // 0;
                $snow_cm_high{$ep} = getFormatted('%.2f', $dayPart, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end') // 0;
			}  else {
                $snow_cm_low{$ep} = 0;
                $snow_cm_high{$ep} = 0;
            }

			# precipitation duration in minutes.  TODO: verify if daypart include duration and units
			$prec_dur{$ep} = getFormatted('%.2f', $dayPart, 'precipitation', 'duration', 'minutes') // 0;

			# precipitation probability (0..1) -> percent (0..100)
			$pop_pct{$ep} = getPercentage('%.2f', $dayPart, 'precipitation', 'probability') // 0;

            # uv index
            $uvidx{$ep} = getFormatted('%.1f', $dayPart, 'uv_index', 'value') // 0;

			# Symbol is categorical data -> keep as step/hold value
			$symbol{$ep} = getValue($dayPart, 'symbol');
			$c_img{$ep} = getValue($dayPart, 'weather_condition_image');
		}
	}

	# 2. Step: Sort and de-duplicate epochs
    my $skipInterpolation = 0;

	@dpEpochs = sort { $a <=> $b } @dpEpochs;
	{
		my %seen;
		@dpEpochs = grep { !$seen{$_}++ } @dpEpochs;
	}
    if (!@dpEpochs) {
        LOGWARN "No dayparts to interpolate. Errors are likely, e.g. the Loxone weather emulator may show a black screen";
        $skipInterpolation = 1;
    }

    if (scalar(@dpEpochs) < 2) {
        LOGWARN("Not enough time points for interpolation: " . scalar(@dpEpochs));
        $skipInterpolation = 1;
    }

    for my $hashref (\%t_air, \%t_app, \%hum, \%w_dir, \%w_sp_kmh, \%pr_hpa, \%dp_c, \%prec_mm_low, \%prec_mm_high, \%snow_cm_low, \%snow_cm_high, \%pop_pct, \%uvidx, \%prec_dur) {
        my @defined_vals = grep { defined $_ } values %$hashref;
        if (scalar(@defined_vals) < 2) {
            LOGWARN("Not enough defined values for interpolator (" . $hashref . ")");
             $skipInterpolation = 1;
        }
    }

	# 3. Step: Create interpolators for all parameters

	# Create interpolators (once)
	my $t_air_i     = Math::Function::Interpolator::Linear->new(points => \%t_air);
	my $t_app_i     = Math::Function::Interpolator::Linear->new(points => \%t_app);
	my $hum_i       = Math::Function::Interpolator::Linear->new(points => \%hum);
	my $w_dir_i     = Math::Function::Interpolator::Linear->new(points => \%w_dir);
	my $w_sp_i      = Math::Function::Interpolator::Linear->new(points => \%w_sp_kmh);
	my $w_gu_i      = Math::Function::Interpolator::Linear->new(points => \%w_gu_kmh);
	my $pr_i        = Math::Function::Interpolator::Linear->new(points => \%pr_hpa);
	my $dp_i        = Math::Function::Interpolator::Linear->new(points => \%dp_c);
	my $uvidx_i     = Math::Function::Interpolator::Linear->new(points => \%uvidx);
	my $prec_low_i  = Math::Function::Interpolator::Linear->new(points => \%prec_mm_low);
    my $prec_high_i = Math::Function::Interpolator::Linear->new(points => \%prec_mm_high);
	my $prec_dur_i  = Math::Function::Interpolator::Linear->new(points => \%prec_dur);
	my $snow_low_i  = Math::Function::Interpolator::Linear->new(points => \%snow_cm_low);
    my $snow_high_i = Math::Function::Interpolator::Linear->new(points => \%snow_cm_high);
	my $pop_i       = Math::Function::Interpolator::Linear->new(points => \%pop_pct);

	# 4. Step: Create hourly data for all hours starting from '$dtResult' (time stamp from the last hourly entry) + 1h
    #          up to last available entry in dpEpochs, '$hour' still counts the entry

	# Get latest time stamp 
	my $end_epoch_time = $dpEpochs[-1];

	# increase time '$dtResult' by 1 hour for next entry
	$dtResult += 3600;
	my $epochTime = $dtResult;

    # only save 5 days of hourly data to reduce loading times
	while ($epochTime <= $end_epoch_time && !$skipInterpolation && $hour < 121) {

        # values with additional calculations needs to be done before hash is assigned

		# For step/hold fields (symbol -> icon/code/description and wind direction text),
		# select the field from last daypart epoch <= current hourly epoch
		my $stepEp = $dpEpochs[0];
		for my $e (@dpEpochs) {
			last if $e > $epochTime;
			$stepEp = $e;
		}

        # calculate epoch time from last entry + 1h
		$epochTime = $dtResult;

        # Mapping: Wetteronline Symbol => [Loxone code, Weather4Lox code, description]
        my ($loxoneCode, $w4lCode, $description);
        my $sym = $symbol{$stepEp};
        if (!defined $sym) {
            LOGWARN "Wetteronline symbol for hourly weather is undefined!";
            ($loxoneCode, $w4lCode, $description) = (5, 'no_data', 'Keine Beschreibung zu Wettersymbol');
        } else {
            ($loxoneCode, $w4lCode, $description) = wetteronlineToLox($sym);
        }

        # astro data

        # get moon infos for specific time of data set (translated to epoch time)
        my ($moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang) = Astro::MoonPhase::phase($epochTime);

        # Get sunrise and sunset time from daily data, needed for isNighttime calculation
        my $isNighttime = undef; # default to day (undef)

        for my $dailyResults (@{$resDaily}) {
            if (substr(getValue($dailyResults, 'date'), 0, 10) eq $dtResult->strftime('%Y-%m-%d')) {
                # we found the matching daily data for the current hourly data, now we can check the dayparts for precipitation type

                if ($dtResult->strftime('%H:%M') lt getTimeFormatted('%H:%M', $timezone, $dailyResults, 'sun', 'rise') || 
                    $dtResult->strftime('%H:%M') gt getTimeFormatted('%H:%M', $timezone, $dailyResults, 'sun', 'set')) {
                    $isNighttime = 1;
                    last; # break loop if we found the matching day and determined it is nighttime
                }
            }
        }

        push @hourlyData, {

            hour              => $hour,                                                 # hfc<X>_per, counter of day
            time => {
                datetime      => _epochToIso($epochTime, $timezone),                    # ISO 8601 date string in local time (e.g. "2026-03-13T02:00:00+01:00")
                epoch         => $epochTime,                                            # hfc<X>_date       - UNIX timestamp
            },
            temperature => {
                air           => sprintf("%.1f", $t_air_i->linear($epochTime)) + 0,     # hfc<X>_tt        - hourly temperature (°C)
                feelsLike     => sprintf("%.1f", $t_app_i->linear($epochTime)) + 0,     # hfc<X>_tt_fl     - min feels-like temperature
                heatIndex     => undef,                                                 # hfc<X>_hi        - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures
                windChill     => undef,                                                 # hfc<X>_w_ch      - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
            },
            wind => {
                direction     => $w_dir{$stepEp},                                       # hfc<X>_w_dir     - wind direction (degree)
                cardinal      => getWindDirCardinal($w_dir{$stepEp}),                   # hfc<X>_w_dirdes  - wind direction description
                speed         => sprintf("%.2f", $w_sp_i->linear($epochTime)) + 0,      # hfc<X>_w_sp      - wind speed (km/h)
                gust          => sprintf("%.2f", $w_gu_i->linear($epochTime)) + 0,      # hfc<X>_w_gu      - wind gust (km/h)
            },
            precipitation => {
                probability   => sprintf("%.0f", $pop_i->linear($epochTime)) + 0,       # hfc<X>_pop         - probability of precipitation (%)
                duration      => sprintf("%.0f", $prec_dur_i->linear($epochTime)) + 0,  #                    - duration of precipitation
                rainLow       => sprintf("%.2f", $prec_low_i->linear($epochTime)) + 0,  #                    - precipitation (mm) from
                rainHigh      => sprintf("%.2f", $prec_high_i->linear($epochTime)) + 0, # hfc<X>_prec        - precipitation (mm) up to
                type          => $prec_type{$stepEp},                                   #                    - precipitation type
                snowLow       => sprintf("%.2f", $snow_low_i->linear($epochTime)) + 0,  #                    - snow height (cm) from
                snowHigh      => sprintf("%.2f", $snow_high_i->linear($epochTime)) + 0, # hfc<X>_snow        - snow height (cm) up to
            },
            weatherCode => {
                loxone        => $loxoneCode,                                           # hfc<X>_we_code   - Loxone code
                weather4lox   => $w4lCode,                                              # hfc<X>_we_icon   - Weather4Lox icon code
                description   => $description,                                          # hfc<X>_we_des    - description
                image         => $c_img{$stepEp},                                       #                  - future use, e.g. as background image
                metar         => getMetarCode($w4lCode),                                #                  - METAR code
            },
            moon => {
                age        => sprintf("%.2f", $moonage) + 0,                            # hfc<X>_moon_a    - moon age in days
                percent    => sprintf("%.2f", $moonillum * 100) + 0,                    # hfc<X>_moon_p    - moon percentage
                phase      => sprintf("%.2f", $moonphase * 100) + 0,                    # hfc<X>_moon_ph   - moon phase
                direction  => getMoonDirection($moonage),                               #                  - moon direction (waxing, waning)
            },
            humidity         => sprintf("%.1f", $hum_i->linear($epochTime)) + 0,        # hfc<X>_hu        - humidity
            pressure         => sprintf("%.0f", $pr_i->linear($epochTime)) + 0,         # hfc<X>_pr        - air pressure (hPa)
            dewpoint         => sprintf("%.1f", $dp_i->linear($epochTime)) + 0,         # hfc<X>_dp        - dew point (°C)
            uvIndex          => sprintf("%.1f", $uvidx_i->linear($epochTime)) + 0,      # hfc<X>_uvi       - UV index
            visibility       => undef,                                                  # hfc<X>_vis       - visibility (m/km), not available in dayparts!
                                                                                        # hfc<X>_sr        - solar radiation (not present)
                                                                                        # hfc<X>_ozone     - ozone (not present)
            cloudCover       => skyConditionFromWoCode($sym),                           # hfc<X>_sky       - cloud/sky cover (percentage from 0 to 100)
            isNight          => $isNighttime,                                           # get nighttime information from sunrise / sunset
        };
        $dtResult += 3600;
        $hour++;
    }

    # Build envelope and write JSON to file
    $weatherKey = "hourlyforecast";
    my $generatedAt = DateTime->now( time_zone => $timezone );
    my $envelope = {
        refresh  => $refresh,
        generatedAt     => $generatedAt->iso8601(),
        location => $location,
        $grabberKey => {
            filename        => "$lbplogdir/$weatherKey.json",
            generatedAt     => $generatedAt->iso8601(),
            grabberLabel    => $grabberLabel,
            grabberScript   => $grabberFile,
            schemaVersion   => "v1.0",
        },
        $weatherKey => \@hourlyData, 
    };
    writeJsonFile($lbplogdir, $weatherKey, $envelope);

} # end hourly


# Give OK status to client.
LOGOK "Current weather data, daily and hourly forecasts are saved successfully.";

# Exit
exit;

END
{
    LOGEND;
}