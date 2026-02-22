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
# Modules
##########################################################################

use LoxBerry::System;
use LoxBerry::Log;
use LWP::UserAgent;
use JSON::PP;
#use JSON qw( decode_json );
use File::Copy;
use Getopt::Long;
use Time::Piece;
use HTTP::Request;
use DateTime;
#use DateTime::TimeZone;
use DateTime::Format::ISO8601;
use Astro::MoonPhase;
use utf8;
use Encode qw(encode_utf8);
use HTML::Entities;
use Data::Dumper;

require "$lbpbindir/grabber_utils.pl";

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

my $pcfg             = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $city             = $pcfg->param("WETTERONLINE.STATIONID");

my $apikey           = "av=2&mv=13&c=d2ViOmFxcnhwWDR3ZWJDSlRuWeb=";
my $apikey_current   = "c=d293ZWI6QzhMNFRINmVUbkRoVWFqYg==";
my $useragent        = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36";
my $urlGEO_raw       = "https://www.wetteronline.de/wetter/";
my $uriUV_raw        = "?prefpar=sun";
my $urlCurrent_raw   = "https://api-web.wo-cloud.com/weather/nowcast/v10?";
my $urlDaily_raw     = "https://api-app.wetteronline.de/app/weather/forecast?";
my $urlHourly_raw    = "https://api-app.wetteronline.de/app/weather/hourcast?";

my $timezone         = qx(cat /etc/timezone);
chomp ($timezone);

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
	name => 'grabber_wetteronline',
	logdir => "$lbplogdir",
	#filename => "$lbplogdir/weather4lox.log",
	#append => 1,
);

# Commandline options
my $verbose = '';
my $current = '';
my $daily = '';
my $hourly = '';
my $maskkeys = 1;
GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 },
            'current' => \$current,
            'daily' => \$daily,
            'hourly' => \$hourly,
            'maskkeys' => \$maskkeys,
			);

if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGSTART "Weather4Lox GRABBER_WETTERONLINE process started";
LOGDEB "This is $0 Version $version";

# Get HTML data from wetteronline.de (HTTP Body request)
sub getUrl {
    my ($myUrl, $useragent) = @_;
    LOGDEB("URL: " . $myUrl);
    
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(GET => $myUrl);
    $request->header('User-Agent' => $useragent);
    
    my $response = $ua->request($request);
    
    if ($response->is_success) {
        LOGDEB("Status: " . $response->status_line);
        my $content = $response->decoded_content;
        #LOGDEB("HTTP response:\n$content") if $content ne '';
        #LOGDEB("-" x 80);

        #print Dumper $content;
        return $content;
    } else {
        LOGCRIT("Failed to fetch data for $city. Status: " . $response->status_line);
        die "Quit fetching data.";
    }
}

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

# Getting GEO data first to get lat and long for the API call for weather data
my $geodataMatch = api_call(
	url => "$urlGEO_raw$city",
	# maskkeys => $maskkeys,    # no masking needed here as there are no secret API keys
	# keyparam => 'appid',
	# apikey => $apikey, 
	info => "for Location $city (GEO data only)",
    match => qr/WO\.geo = (\{(?:[^{}"]|"(?:[^"\\]|\\.)*"|(?1))*\});/s,
);

$geodataMatch = decode_entities($geodataMatch);
$geodataMatch = encode_utf8($geodataMatch);
my $decodedGeodata = $json->decode($geodataMatch);
my $lat = $decodedGeodata->{lat};
my $long = $decodedGeodata->{lon};
my $altitude = $decodedGeodata->{alt};

if ($geodataMatch) {
    LOGDEB("Extracted GEO data:\n$geodataMatch");
    LOGDEB("-" x 80);
}
# my $gid = findGid($city, $geodataMatch); 
my $gid = $decodedGeodata->{gid}; 
if ($gid) {
    LOGDEB "The GID of city $city is $gid.";
} else {
    LOGCRIT "Failed to fetch GID for $city";
    die "Quit fetching GID.";
}

# Get weather data from wetteronline.de (API request) for current conditions
my $decodedCurrent = api_call(
	url => "$urlCurrent_raw$apikey_current&grid_longitude=$long&grid_latitude=$lat&location_id=$gid&astro_longitude=$long&astro_latitude=$lat&latitude=$lat&longitude=$long&timezone=$timezone&language=de-DE&timeformat=HH:mm&windunit=kmh&system_of_measurement=metric&altitude=$altitude",
	# maskkeys => $maskkeys,    # no masking needed here as there are no secret API keys
	# keyparam => 'appid',
	# apikey => $apikey,
	info => "for Location $city (Current Weather Data)",
);

# Get weather data from wetteronline.de (API request) for daily conditions
my $decodedDaily = api_call(
	url => "$urlDaily_raw$apikey&location_id=$gid&timezone=$timezone",
	# maskkeys => $maskkeys,    # no masking needed here as there are no secret API keys
	# keyparam => 'appid',
	# apikey => $apikey,
	info => "for Location $city (Daily Weather Data)",
);

# Get weather data from wetteronline.de (API request) for hourly conditions
my $decodedHourly = api_call(
	url => "$urlHourly_raw$apikey&location_id=$gid&timezone=$timezone",
	# maskkeys => $maskkeys,    # no masking needed here as there are no secret API keys
	# keyparam => 'appid',
	# apikey => $apikey,
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

# Mapping: Wetteronline Symbol => [Loxone Code, Weather4Lox Icon, Description]
# Weather symbols with meaning: https://www.wetteronline.de/symbole
# --> Using https://wiki.loxberry.de/plugins/weather4loxone/start#wetter-codes
		

# Position: 1 2 3 4 5 6
# Beispiel: m d s n 1 _

# Position 1-2: Tageszeit + Bewölkung

# Code	Bedeutung
# so	Sonnig (Tag)
# mo	Klar (Nacht)

# wb	Leicht bewölkt (Tag)
# mb	Leicht bewölkt (Nacht)

# bw	Bewölkt (Tag)
# mw	Bewölkt (Nacht)

# bd	Bedeckt (Tag)
# md	Bedeckt (Nacht)

# ns	Nebel (Tag)
# nm	Nebel (Nacht)
# nb	Nebel

# Position 3-6: Niederschlagsart, aufgefüllt mit Unterstrichen, wenn kein Niederschlag oder Code kürzer ist

# Code	Bedeutung
# ____	Kein Niederschlag

# für alle Bewölkungsarten:
#   wb, mb - leicht bewölkt mit Symbol für Tag und Nacht (Wolken sind keiner als Sonne/Mond)
#   bw, mw - bewölkt mit Symbol für Tag und Nacht (Wolken sind größer als Sonne/Mond)
#   bd, md - bedeckt, haben gleiches Symbol für Tag und Nacht (nur Woklen, keine Sonne/Mond)

# gibt es die Kombination mit Niederschlag in unterschiedlichen Intensitäten/Varianten
#  s1-s3	    Schauer (Intensität 1-3 - Leicht, Mittel, Stark), Intensität 1-3 wird durch Anzahl der Tropfen im Symbol dargestellt
#  r1-r3	    Regen (Intensität 1-3 - Leicht, Mittel, Stark), Symbole wie s1-s3
#  g1-g3	    Gewitter (Intensität 1-3 - Leicht, Mittel, Stark), Symbol mit einem Blitz, Intensität 1-2 wird durch Anzahl der Tropfen im Symbol dargestellt, bei 3 zusätzlich Warndreieck
#  sn1-sn3	    Schneefall (Intensität 1-3 - Leicht, Mittel, Stark), Intensität 1-3 wird durch Anzahl der Schneeflocken im Symbol dargestellt
#  sr1-sr3	    Schneeregen (Intensität 1-3 - Leicht, Mittel, Stark), bei allen Intensitäten immer ein Tropfen und eine Schneeflocke im Symbol
#  snr1-snr3	Schneeregen, siehe sr1-sr3
#  srs1-srs3	Schneeregenschauer, Symbole wie sr

#  gr1-gr2	Gefrierender Regen (Intensität 1-2 - Leicht, Stark)
#  gs1-gs2	Graupelschauer (Intensität 1-2 - Leicht, Stark)
#  hs1-hs2	Hagelschauer (Intensität 1-2 - Leicht, Stark)

#  ek	Eiskörner
#  sg	Schneegestöber (Schneegewitter), Symbol mit Schneeflocke und Blitz

# mapping is created from https://www.wetteronline.de/symbole
# additional symbols that are not listed in the overview but are used in practice were added after verifying symbol, e.g. "bw___", "mw___"
my %wetteronline_to_lox = (

    # in Farbe: https://st.wetteronline.de/dr/1.1.617/city/prozess/graphiken/symbole/standard/farbe/png/50x35/so____.png
    # in SW:    https://st.wetteronline.de/dr/1.1.617/city/prozess/graphiken/symbole/wom/standard/sw/gif/so____.gif
    # aktuelles Wetter in Farbe: https://st.wetteronline.de/dr/1.1.617/aktuell/prozess/graphiken/symbole/standard/farbe/gif/so____.gif

    # Wolken (in Abstufungen von klar bis bedeckt)
    "so____" => ["1", "clear", "Sonnig"],                                        # sonnig bzw. klar / wolkenlos (Tag)
    "mo____" => ["1", "clear", "Klar"],                                          # sonnig bzw. klar / wolkenlos (Nacht)
    "wb____" => ["2", "mostlysunny", "Leicht bewölkt"],                          # leicht bewölkt (Tag)
    "mb____" => ["2", "mostlysunny", "Leicht bewölkt"],                          # leicht bewölkt (Nacht)
    "bw____" => ["3", "cloudy", "Bewölkt"],                                      # Bewölkt (Tag)
    "mw____" => ["3", "cloudy", "Bewölkt"],                                      # Bewölkt (Nacht)
    "bd____" => ["5", "overcast", "Bedeckt"],                                    # bedeckt
    "md____" => ["5", "overcast", "Bedeckt"],                                    # Bedeckt

    # Nebel/Dunst
    "ns____" => ["6", "fog", "Teils neblig"],                                    # teils neblig (Tag)
    "nm____" => ["6", "fog", "Teils neblig"],                                    # teils neblig (Nacht)
    "nb____" => ["6", "fog", "Nebelig"],                                         # neblig / Nebel

    # Schauer

    # leicht Bewölkt und Schauer (Tag und Nacht)
    "wbs1__" => ["16", "chancerain", "Vereinzelt Regenschauer"],                 # leicht bewölkt und vereinzelt Schauer (Tag)
    "wbs2__" => ["16", "rain", "Regenschauer"],                                  # leicht bewölkt und Schauer (Tag)
    "wbs3__" => ["12", "rain", "Starker Regenschauer"],                          # leicht bewölkt und Starke Regenschauer (Tag)

    "mbs1__" => ["16", "chancerain", "Vereinzelt Regenschauer"],                 # leicht bewölkt und vereinzelt Schauer (Nacht)
    "mbs2__" => ["16", "rain", "Regenschauer"],                                  # leicht bewölkt und Schauer (Nacht)
    "mbs3__" => ["12", "rain", "Starker Regenschauer"],                          # leicht bewölkt und Starke Regenschauer (Nacht)

   # Bewölkt und Schauer (Tag und Nacht)
    "bws1__" => ["16", "chancerain", "Vereinzelt Regenschauer"],                 # bewölkt und vereinzelt Schauer (Tag)
    "mws1__" => ["16", "chancerain", "Vereinzelt Regenschauer"],                 # bewölkt und vereinzelt Schauer (Nacht)
    "bws2__" => ["16", "rain", "Regenschauer"],                                  # bewölkt und Schauer (Tag)
    "mws2__" => ["16", "rain", "Regenschauer"],                                  # bewölkt und Schauer (Nacht)
    "bws3__" => ["12", "rain", "Starker Regenschauer"],                          # bewölkt und Starke Regenschauer (Tag)
    "mws3__" => ["12", "rain", "Starker Regenschauer"],                          # bewölkt und Starke Regenschauer (Nacht)

    # Bedeckt und Schauer
    "bds1__" => ["10", "rain", "Leichter Regenschauer"],                         # Leichter Regenschauer
    "bds2__" => ["11", "rain", "Regenschauer"],                                  # Regenschauer
    "bds3__" => ["12", "rain", "Starker Regenschauer"],                          # Starker Regenschauer

    "mds1__" => ["10", "rain", "Leichter Regenschauer"],                         # Leichter Regenschauer
    "mds2__" => ["11", "rain", "Regenschauer"],                                  # Regenschauer
    "mds3__" => ["12", "rain", "Starker Regenschauer"],                          # Starker Regenschauer

    # Regen

    # leicht Bewölkt und Regen (Tag und Nacht)
    "wbr1__" => ["16", "chancerain", "Leichter Regen"],                          # leicht bewölkt und leichter Regen (Tag)
    "wbr2__" => ["11", "rain", "Regen"],                                         # leicht bewölkt und Regen (Tag)
    "wbr3__" => ["12", "rain", "Starker Regen"],                                 # leicht bewölkt und Starker Regen (Tag)

    "mbr1__" => ["16", "chancerain", "Leichter Regen"],                          # leicht bewölkt und leichter Regen (Nacht)
    "mbr2__" => ["11", "rain", "Regen"],                                         # leicht bewölkt und Regen (Nacht)
    "mbr3__" => ["12", "rain", "Starker Regen"],                                 # leicht bewölkt und Starker Regen (Nacht)

    # Bewölkt und Regen (Tag und Nacht)
    "bwr1__" => ["16", "chancerain", "Leichter Regen"],                          # bewölkt und leichter Regen (Tag)
    "mwr1__" => ["16", "chancerain", "Leichter Regen"],                          # bewölkt und leichter Regen (Nacht)
    "bwr2__" => ["11", "rain", "Regen"],                                         # bewölkt und Regen (Tag)
    "mwr2__" => ["11", "rain", "Regen"],                                         # bewölkt und Regen (Nacht)
    "bwr3__" => ["12", "rain", "Starker Regen"],                                 # bewölkt und Starker Regen (Tag)
    "mwr3__" => ["12", "rain", "Starker Regen"],                                 # bewölkt und Starker Regen (Nacht)

    # Bedeckt und Regen
    "bdr1__" => ["16", "chancerain", "Regenschauer"],                            # bedeckt, etwas Regen oder vereinzelt Schauer
    "bdr2__" => ["11", "rain", "Regen"],                                         # bedeckt, Regen oder Schauer
    "bdr3__" => ["12", "rain", "Ergiebiger Regen"],                              # bedeckt und ergiebiger Regen

    "mdr1__" => ["10", "rain", "Leichter Regen"],                                # Leichter Regen
    "mdr2__" => ["11", "rain", "Regen"],                                         # Regen
    "mdr3__" => ["12", "rain", "Starker Regen"],                                 # Starker Regen

    # Schneeregenschauer

    # leicht bewölkt und Schneeregenschauer
    "wbsrs1" => ["28", "sleet", "Vereinzelt Schneeregenschauer"],                # leicht bewölkt und vereinzelt Schneeregenschauer (Tag)
    "wbsrs2" => ["28", "sleet", "Schneeregenschauer"],                           # leicht bewölkt und Schneeregenschauer (Tag)
    "wbsrs3" => ["29", "sleet", "Starke Schneeregenschauer"],                    # leicht bewölkt und Schneeregenschauer (Tag)

    "mbsrs1" => ["28", "sleet", "Vereinzelt Schneeregenschauer"],                # leicht bewölkt und vereinzelt Schneeregenschauer (Nacht)
    "mbsrs2" => ["28", "sleet", "Schneeregenschauer"],                           # leicht bewölkt und Schneeregenschauer (Nacht)
    "mbsrs3" => ["29", "sleet", "Starke Schneeregenschauer"],                    # leicht bewölkt und Schneeregenschauer (Nacht)

    # bewölkt und Schneeregenschauer
    "bwsrs1" => ["28", "sleet", "Vereinzelt Schneeregenschauer"],                # bewölkt und vereinzelt Schneeregenschauer (Tag)
    "bwsrs2" => ["28", "sleet", "Schneeregenschauer"],                           # bewölkt und Schneeregenschauer (Tag)
    "bwsrs3" => ["29", "sleet", "Starke Schneeregenschauer"],                    # bewölkt und Schneeregenschauer (Tag)

    "mwsrs1" => ["28", "sleet", "Vereinzelt Schneeregenschauer"],                # bewölkt und vereinzelt Schneeregenschauer (Nacht)
    "mwsrs2" => ["28", "sleet", "Schneeregenschauer"],                           # bewölkt und Schneeregenschauer (Nacht)
    "mwsrs3" => ["29", "sleet", "Starke Schneeregenschauer"],                    # bewölkt und Schneeregenschauer (Nacht)

    # bedeckt und Schneeregenschauer
    "bdsrs1" => ["25", "sleet", "Leichter Schneeregenschauer"],                  # bedeckt, leichter Schneeregen oder vereinzelt Schneeregenschauer
    "bdsrs2" => ["26", "sleet", "Schneeregenschauer"],                           # bedeckt, Schneeregen oder Schneeregenschauer
    "bdsrs3" => ["27", "sleet", "Ergiebiger Schneeregenschauer"],                # bedeckt und ergiebiger Schneeregen

    "mdsrs1" => ["25", "sleet", "Leichter Schneeregenschauer"],                  # bedeckt, leichter Schneeregen oder vereinzelt Schneeregenschauer
    "mdsrs2" => ["26", "sleet", "Schneeregenschauer"],                           # bedeckt, Schneeregen oder Schneeregenschauer
    "mdsrs3" => ["27", "sleet", "Ergiebiger Schneeregenschauer"],                # bedeckt und ergiebiger Schneeregen

    # Schneeregen ### ToDo: snr in sr umwandeln
    "bwsnr1" => ["28", "sleet", "Leichter Schneeregen"],                         # leichter Schneeregen
    "bwsnr2" => ["26", "sleet", "Schneeregen"],                                  # Schneeregen

    # Schneeregen

    # leicht bewölkt und Schneeregen
    "wbsr1_" => ["25", "sleet", "Leichter Schneeregen"],                         # leicht bewölkt und vereinzelt Schneeregen (Tag)
    "wbsr2_" => ["26", "sleet", "Schneeregen"],                                  # leicht bewölkt und Schneeregen (Tag)
    "wbsr3_" => ["27", "sleet", "Starker Schneeregen"],                          # leicht bewölkt und ergiebiger Schneeregen (Tag)

    "mbsr1_" => ["25", "sleet", "Leichter Schneeregen"],                         # leicht bewölkt und vereinzelt Schneeregen (Nacht)
    "mbsr2_" => ["26", "sleet", "Schneeregen"],                                  # leicht bewölkt und Schneeregen (Nacht)
    "mbsr3_" => ["27", "sleet", "Starker Schneeregen"],                          # leicht bewölkt und ergiebiger Schneeregen (Nacht)

    # bewölkt und Schneeregen
    "bwsr1_" => ["25", "sleet", "Leichter Schneeregen"],                         # bewölkt und vereinzelt Schneeregen (Tag)
    "bwsr2_" => ["26", "sleet", "Schneeregen"],                                  # bewölkt und Schneeregen (Tag)
    "bwsr3_" => ["27", "sleet", "Starker Schneeregen"],                          # bewölkt und ergiebiger Schneeregen (Tag)

    "mwsr1_" => ["25", "sleet", "Leichter Schneeregen"],                         # bewölkt und vereinzelt Schneeregen (Nacht)
    "mwsr2_" => ["26", "sleet", "Schneeregen"],                                  # bewölkt und Schneeregen (Nacht)
    "mwsr3_" => ["27", "sleet", "Starker Schneeregen"],                          # bewölkt und ergiebiger Schneeregen (Nacht)

    # bedeckt und Schneeregen
    "bdsr1_" => ["25", "sleet", "Leichter Schneeregen"],                         # bedeckt, leichter Schneeregen oder vereinzelt Schneeregenschauer
    "bdsr2_" => ["26", "sleet", "Schneeregen"],                                  # bedeckt, Schneeregen oder Schneeregenschauer
    "bdsr3_" => ["27", "sleet", "Ergiebiger Schneeregen"],                       # bedeckt und ergiebiger Schneeregen

    "mdsr1_" => ["25", "sleet", "Leichter Schneeregen"],                         # bedeckt, leichter Schneeregen oder vereinzelt Schneeregenschauer
    "mdsr2_" => ["26", "sleet", "Schneeregen"],                                  # bedeckt, Schneeregen oder Schneeregenschauer
    "mdsr3_" => ["27", "sleet", "Ergiebiger Schneeregen"],                       # bedeckt und ergiebiger Schneeregen

    # Schneeschauer

    # leicht bewölkt und Schneeschauer
    "wbsns1" => ["23", "snow", "Leichter Schneeschauer"],                        # leicht bewölkt und vereinzelt Schneeschauer (Tag)
    "wbsns2" => ["24", "snow", "Schneeschauer"],                                 # leicht bewölkt und Schneeschauer (Tag)
    "wbsns3" => ["24", "snow", "Starker Schneeschauer"],                         # leicht bewölkt und starke Schneeschauer (Tag)

    "mbsns1" => ["23", "snow", "Leichter Schneeschauer"],                        # leicht bewölkt und vereinzelt Schneeschauer (Nacht)
    "mbsns2" => ["24", "snow", "Schneeschauer"],                                 # leicht bewölkt und Schneeschauer (Nacht)
    "mbsns3" => ["24", "snow", "Starker Schneeschauer"],                         # leicht bewölkt und starke Schneeschauer (Nacht)

    # bewölkt und Schneeschauer
    "bwsns1" => ["23", "snow", "Leichter Schneeschauer"],                        # bewölkt und vereinzelt Schneeschauer (Tag)
    "bwsns2" => ["24", "snow", "Schneeschauer"],                                 # bewölkt und Schneeschauer (Tag)
    "bwsns3" => ["24", "snow", "Starker Schneeschauer"],                         # bewölkt und starke Schneeschauer (Tag)

    "mwsns1" => ["23", "snow", "Leichter Schneeschauer"],                        # bewölkt und vereinzelt Schneeschauer (Nacht)
    "mwsns2" => ["24", "snow", "Schneeschauer"],                                 # bewölkt und Schneeschauer (Nacht)
    "mwsns3" => ["24", "snow", "Starker Schneeschauer"],                         # bewölkt und starke Schneeschauer (Nacht)

    # bedeckt und Schneeschauer
    "bdsns1" => ["23", "snow", "Leichter Schneeschauer"],                        # bedeckt, leichter Schneefall oder vereinzelt Schneeschauer
    "bdsns2" => ["24", "snow", "Schneeschauer"],                                 # bedeckt, Schneefall oder Schneeschauer
    "bdsns3" => ["24", "snow", "Starker Schneeschauer"],                         # bedeckt und ergiebiger Schneefall

    "mdsns1" => ["23", "snow", "Leichter Schneeschauer"],                        # bedeckt, leichter Schneefall oder vereinzelt Schneeschauer
    "mdsns2" => ["24", "snow", "Schneeschauer"],                                 # bedeckt, Schneefall oder Schneeschauer
    "mdsns3" => ["24", "snow", "Starker Schneeschauer"],                         # bedeckt und ergiebiger Schneefall

    # Schneefall

    # leicht bewölkt und Schneefall
    "wbsn1_" => ["20", "snow", "Leichter Schneefall"],                           # leicht bewölkt und vereinzelt Schneefall (Tag)
    "wbsn2_" => ["21", "snow", "Schneefall"],                                    # leicht bewölkt und Schneefall (Tag)
    "wbsn3_" => ["22", "snow", "Starker Schneefall"],                            # leicht bewölkt und starker Schneefall (Tag)

    "mbsn1_" => ["20", "snow", "Leichter Schneefall"],                           # leicht bewölkt und vereinzelt Schneefall (Nacht)
    "mbsn2_" => ["21", "snow", "Schneefall"],                                    # leicht bewölkt und Schneefall (Nacht)
    "mbsn3_" => ["22", "snow", "Starker Schneefall"],                            # leicht bewölkt und starker Schneefall (Nacht)

    # bewölkt und Schneefall
    "bwsn1_" => ["20", "snow", "Leichter Schneefall"],                           # bewölkt und vereinzelt Schneefall (Tag)
    "bwsn2_" => ["21", "snow", "Schneefall"],                                    # bewölkt und Schneefall (Tag)
    "bwsn3_" => ["22", "snow", "Starker Schneefall"],                            # bewölkt und starker Schneefall (Tag)

    "mwsn1_" => ["20", "snow", "Leichter Schneefall"],                           # bewölkt und vereinzelt Schneefall (Nacht)
    "mwsn2_" => ["21", "snow", "Schneefall"],                                    # bewölkt und Schneefall (Nacht)
    "mwsn3_" => ["22", "snow", "Starker Schneefall"],                            # bewölkt und starker Schneefall (Nacht)

    # bedeckt und Schneefall
    "bdsn1_" => ["20", "snow", "Leichter Schneefall"],                           # bedeckt, leichter Schneefall oder vereinzelt Schneeschauer (Tag)
    "bdsn2_" => ["21", "snow", "Schneefall"],                                    # bedeckt, Schneefall oder Schneeschauer (Tag)
    "bdsn3_" => ["22", "snow", "Ergiebiger Schneefall"],                         # bedeckt und ergiebiger Schneefall (Tag)

    "mdsn1_" => ["20", "snow", "Leichter Schneefall"],                           # bedeckt, leichter Schneefall oder vereinzelt Schneeschauer (Nacht)
    "mdsn2_" => ["21", "snow", "Schneefall"],                                    # bedeckt, Schneefall oder Schneeschauer (Nacht)
    "mdsn3_" => ["22", "snow", "Ergiebiger Schneefall"],                         # bedeckt und ergiebiger Schneefall (Nacht)

    # Schnegewitter

    # leicht bewölkt und Schneegewitter
    "wbsg__" => ["24", "snow", "Vereinzelt Schneegewitter"],                     # leicht bewölkt und Schneegewitter (Tag)
    "mbsg__" => ["24", "snow", "Vereinzelt Schneegewitter"],                     # leicht bewölkt und Schneegewitter (Nacht)

    # bewölkt und Schneegewitter
    "bwsg__" => ["24", "snow", "Schneegewitter"],                                # bewölkt und Schneegewitter (Tag)
    "mwsg__" => ["24", "snow", "Schneegewitter"],                                # bewölkt und Schneegewitter (Nacht)

    # bedeckt und Schneegewitter
    "bdsg__" => ["24", "snow", "Schneegewitter"],                                # bedeckt und Schneegewitter (Tag)
    "mdsg__" => ["24", "snow", "Schneegewitter"],                                # bedeckt und Schneegewitter (Nacht)

    # Gewitter

    # leicht bewölkt mit Gewitter
    "wbg1__" => ["18", "tstorms", "Vereinzelt Gewitter"],                        # leicht bewölkt, vereinzelt Schauer und Gewitter (Tag)
    "wbg2__" => ["18", "tstorms", "Gewitter"],                                   # leicht bewölkt, Schauer und Gewitter (Tag)
    "wbg3__" => ["19", "tstorms", "Kräftiges Gewitter"],                         # leicht bewölkt, Schauer und Gewitter (Tag)

    "mbg1__" => ["18", "tstorms", "Vereinzelt Gewitter"],                        # leicht bewölkt, vereinzelt Schauer und Gewitter (Nacht)
    "mbg2__" => ["18", "tstorms", "Gewitter"],                                   # leicht bewölkt, Schauer und Gewitter (Nacht)
    "mbg3__" => ["19", "tstorms", "Kräftiges Gewitter"],                         # leicht bewölkt, Schauer und Gewitter (Nacht)

    # Bewölkt mit Gewitter
    "bwg1__" => ["18", "tstorms", "Vereinzelt Gewitter"],                        # bewölkt, vereinzelt Schauer und Gewitter (Tag)
    "bwg2__" => ["18", "tstorms", "Gewitter"],                                   # Gewitter (Tag)
    "bwg3__" => ["19", "tstorms", "Kräftiges Gewitter"],                         # starke Gewitter (Tag)

    "mwg1__" => ["18", "tstorms", "Vereinzelt Gewitter"],                        # leichte Gewitter (Nacht)
    "mwg2__" => ["18", "tstorms", "Gewitter"],                                   # Gewitter (Nacht)
    "mwg3__" => ["19", "tstorms", "Kräftiges Gewitter"],                         # starke Gewitter (Nacht)

    # Bedeckt mit Gewitter
    "bdg1__" => ["18", "tstorms", "Gewitter"],                                   # bedeckt, vereinzelt Schauer und Gewitter
    "bdg2__" => ["18", "tstorms", "Gewitter"],                                   # bedeckt, Schauer und Gewitter (Tag)

    "mdg1__" => ["18", "tstorms", "Gewitter"],                                   # bedeckt, vereinzelt Schauer und Gewitter (Nacht)
    "mdg2__" => ["18", "tstorms", "Gewitter"],                                   # bedeckt, Schauer und Gewitter (Nacht)

    # gefrierender Regen

    # leicht Bewölkt mit gefrierendem Regen
    "wbgr1_" => ["14", "sleet", "Gefrierender Sprühregen"],                      # bewölkt und gefrierender Sprühregen (Tag)
    "wbgr2_" => ["14", "sleet", "Gefrierender Regen"],                           # bewölkt und gefrierender Regen (Tag)

    "mbgr1_" => ["14", "sleet", "Gefrierender Sprühregen"],                      # bewölkt und gefrierender Sprühregen (Nacht)
    "mbgr2_" => ["14", "sleet", "Gefrierender Regen"],                           # bewölkt und gefrierender Regen (Nacht)

    # Bewölkt mit gefrierendem Regen
    "bwgr1_" => ["14", "sleet", "Gefrierender Sprühregen"],                      # bewölkt und gefrierender Sprühregen (Tag)
    "bwgr2_" => ["14", "sleet", "Gefrierender Regen"],                           # bewölkt und gefrierender Regen (Tag)

    "mwgr1_" => ["14", "sleet", "Gefrierender Sprühregen"],                      # bewölkt und gefrierender Sprühregen (Nacht)
    "mwgr2_" => ["14", "sleet", "Gefrierender Regen"],                           # bewölkt und gefrierender Regen (Nacht)

    # Bedeckt mit gefrierendem Regen
    "bdgr1_" => ["14", "sleet", "Gefrierender Sprühregen"],                      # bedeckt und gefrierender Sprühregen (Tag)
    "bdgr2_" => ["14", "sleet", "Gefrierender Regen"],                           # bedeckt und gefrierender Regen (Tag)

    "mdgr1_" => ["14", "sleet", "Gefrierender Sprühregen"],                      # bedeckt und gefrierender Sprühregen (Nacht)
    "mdgr2_" => ["14", "sleet", "Gefrierender Regen"],                           # bedeckt und gefrierender Regen (Nacht)

    # Graupel, Hagel und Eiskörner
    "bwgs1_" => ["28", "sleet", "Leichter Graupelschauer"],                        # leichte Graupelschauer
    "bwgs2_" => ["26", "sleet", "Graupelschauer"],                                 # Graupelschauer

    "bwhs1_" => ["28", "sleet", "Leichte Hagelschauer"],                           # leichte Hagelschauer
    "bwhs2_" => ["26", "sleet", "Hagelschauer"],                                   # Hagelschauer

    "bwek__" => ["26", "sleet", "Eiskörner"],                                      # Eiskörner
);

sub wetteronline_to_lox {
    my ($weather_symbol) = @_;
    
    # Check for empty/undefined values
    if (!defined $weather_symbol || $weather_symbol eq "") {
        LOGWARN "Wetteronline symbol is empty/undefined!";
        return ("1", "clear", "Wolkenlos");
    }
    
    # Lookup in the hash
    my $result = $wetteronline_to_lox{$weather_symbol};
    
    if ($result) {
        return @$result;  # Returns (code, icon, description)
    } else {
        LOGWARN "Unknown weather symbol from Wetteronline: '$weather_symbol', using 'clear' as fallback.";
        return ("1", "clear", "Wolkenlos");  # Default fallback
    }
}

#
# Fetch current data
#

if ( $current ) { # Start current

# Write location data into database
my $dt = DateTime::Format::ISO8601->parse_datetime(
    $decodedCurrent->{current}->{date}
);
$t = DateTime->from_epoch(
	 epoch     => $dt->epoch,
         time_zone => $timezone,
);
LOGINF "Saving new Data for Timestamp $t to database.";

# Saving new current data...
open(F,">$lbplogdir/current.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbpconfigdir/current.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	
	# cur_date
	my $epoch_time = $dt->epoch;
	print F "$epoch_time|";
	
	# cur_date_des
	my $date = qx(TZ='$timezone' date -R -d "\@$epoch_time");
	chomp($date);
	print F "$date|";
	
	# cur_date_tz_des_sh
	my $tz_short = qx(TZ='$timezone' date +%Z);
	chomp ($tz_short);
	print F "$tz_short|";
	
	# cur_date_tz_des
	print F "$timezone|";
	
	# cur_date_tz
	my $tz_offset = qx(TZ='$timezone' date +%z);
	chomp ($tz_offset);
	print F "$tz_offset|";
	
	# cur_loc_n
	my $location = $decodedGeodata->{locationname};
	if (defined $decodedGeodata->{sublocationname} && $decodedGeodata->{sublocationname} ne "") {
		$location .= ", " . $decodedGeodata->{sublocationname};
	}
	print F "$location|";
	
	# cur_loc_c
	my @locs = split(/;/, $decodedGeodata->{path});
	print F "$locs[5]|";
	
	# cur_loc_ccode
	my $iso_code = $decodedGeodata->{location_info}->{geoObject}->{"iso-3166-1"};
	print F "$iso_code|";
	
	# cur_loc_lat
	my $lat = $decodedGeodata->{lat};
	print F "$lat|";
	
	# cur_loc_lon
	my $long = $decodedGeodata->{lon};
	print F "$long|";
	
	# cur_loc_el
	my $altitude = $decodedGeodata->{alt};
	print F "$altitude|";
	
	# cur_tt
	my $temp_aktuell = $decodedCurrent->{current}->{temperature}->{air};
	print F sprintf("%.1f",$temp_aktuell), "|";
	
	# cur_tt_fl
	my $temp_fl = $decodedCurrent->{current}->{temperature}->{apparent};
	print F sprintf("%.1f",$temp_fl), "|";
	
	# cur_hu
	my $humidity = $decodedCurrent->{current}->{humidity}*100;
	print F "$humidity|";
	
	# cur_w_dirdes && cur_w_dir
	my $wind_deg = $decodedCurrent->{current}->{wind}->{direction};
	my @dirs = qw(N NO O SO S SW W NW);                        # Windrichtungen
	my $idx = int((($wind_deg + 22.5) % 360) / 45);            # Sektor errechnen
	my $wdir = $dirs[$idx];
	my %dir_labels = (
		N  => $L{'GRABBER.LABEL_N'},
		NO => $L{'GRABBER.LABEL_NE'},
		O  => $L{'GRABBER.LABEL_E'},
		SO => $L{'GRABBER.LABEL_SE'},
		S  => $L{'GRABBER.LABEL_S'},
		SW => $L{'GRABBER.LABEL_SW'},
		W  => $L{'GRABBER.LABEL_W'},
		NW => $L{'GRABBER.LABEL_NW'},
	);
	my $wdirdes = Encode::decode("UTF-8", $dir_labels{$wdir});
	print F "$wdirdes|";
	print F "$wind_deg|";
	
	# cur_w_sp
	print F sprintf("%.1f",$decodedCurrent->{current}->{wind}->{speed}->{kilometer_per_hour}->{value}), "|";
	
	# cur_w_gu
	print F sprintf("%.1f",$decodedCurrent->{current}->{wind}->{speed}->{kilometer_per_hour}->{value}), "|";
	
	# cur_w_ch
	print F sprintf("%.1f",$temp_fl), "|";
	
	# cur_pr
	print F sprintf("%.0f",$decodedCurrent->{current}->{air_pressure}->{hpa}), "|";
	
	# cur_dp
	my $dew_point = $decodedCurrent->{current}->{dew_point}->{celsius};
	print F sprintf("%.1f",$dew_point), "|";
	
	# cur_vis
	print F "-9999|";
	
	# cur_sr
	print F "-9999|";
	
	# cur_hi
	print F "-9999|";
	
	# cur_uvi

    # there is no UV index in the API response for current weather data, nor on the web page itself or hourly forecast data,
    # but there is one for daily forecast, not sure if this should be the UV index for the current time or the day (maximum)
    my $uvi = -9999;
    if (
        @{$decodedDaily}
        && exists $decodedDaily->[0]->{uv_index}
        && exists $decodedDaily->[0]->{uv_index}->{value}
    ) {
        $uvi = $decodedDaily->[0]->{uv_index}->{value};
    }
	print F sprintf("%.0f",$uvi), "|";
	
	# cur_prec_today
	my $todayPrecipitationAmount = 0;
	if (
		exists $decodedCurrent->{trend}
		&& exists $decodedCurrent->{trend}->{items}->[0]->{precipitation}
		&& exists $decodedCurrent->{trend}->{items}->[0]->{precipitation}->{details}
		&& exists $decodedCurrent->{trend}->{items}->[0]->{precipitation}->{details}->{rainfall_amount}
		&& exists $decodedCurrent->{trend}->{items}->[0]->{precipitation}->{details}->{rainfall_amount}->{millimeter}
		&& exists $decodedCurrent->{trend}->{items}->[0]->{precipitation}->{details}->{rainfall_amount}->{millimeter}->{interval_end}
	) {
		$todayPrecipitationAmount = $decodedCurrent->{trend}->{items}->[0]->{precipitation}->{details}->{rainfall_amount}->{millimeter}->{interval_end};
	}
	print F sprintf("%.2f", $todayPrecipitationAmount), "|";
	
	# cur_prec_1hr
	my $hourlyPrecipitationAmount = 0;
	if (
		exists $decodedCurrent->{hours}
		&& exists $decodedCurrent->{hours}->[0]->{precipitation}
		&& exists $decodedCurrent->{hours}->[0]->{precipitation}->{details}
		&& exists $decodedCurrent->{hours}->[0]->{precipitation}->{details}->{rainfall_amount}
		&& exists $decodedCurrent->{hours}->[0]->{precipitation}->{details}->{rainfall_amount}->{millimeter}
		&& exists $decodedCurrent->{hours}->[0]->{precipitation}->{details}->{rainfall_amount}->{millimeter}->{interval_end}
	) {
		$hourlyPrecipitationAmount = $decodedCurrent->{hours}->[0]->{precipitation}->{details}->{rainfall_amount}->{millimeter}->{interval_end};
	}
	print F sprintf("%.2f", $hourlyPrecipitationAmount), "|";

	# cur_icon, cur_code, cur_des
	# Mapping: Wetteronline Symbol => [Loxone Code, Weather4Lox Icon, Description]
	my ($code, $icon, $description) = wetteronline_to_lox($decodedCurrent->{current}->{symbol});
	print F "$icon|";
	print F "$code|";
	#my $description_current = $decodedCurrent->{current}->{weather_condition_image};
	#print F "$description_current|";
	print F "$description|";
	
	# # Astro Data
	# my $moonageWO = $decodedCurrent->{moon}->[0]->{age};
	# my ( $moonphase,
	#   $moonillum,
	#   $moonage,
	#   $moondist,
	#   $moonang,
	#   $sundist,
	#   $sunang ) = phase();
	# print F sprintf("%.2f",$moonillum*100), "|";
	# print F sprintf("%.0f",$moonageWO), "|";
	# print F sprintf("%.2f",$moonphase*100), "|";
	# print F "-9999|";

	# cur_moon_p
	#my $moonage = $decodedCurrent->{moon}->[0]->{age};
	#my $moonphase = $moonage / 30;
	#my $moonpercent = 0;
	#if ($moonphase le "0.5") {
	#	$moonpercent = $moonphase * 2 * 100;
	#} else {
	#	$moonpercent = (1 - $moonphase) * 2 * 100;
	#}
	#print F sprintf("%.1f",$moonpercent), "|";
	
	## cur_moon_a
	#print F "$moonage|";
	
	## cur_moon_ph

	#print F sprintf("%.0f",$moonphase*100), "|";

	# cur_moon_p
	# cur_moon_a
	# cur_moon_ph
	my ( $moonphase,
	  $moonillum,
	  $moonage,
	  $moondist,
	  $moonang,
	  $sundist,
	  $sunang ) = phase();
	print F sprintf("%.2f",$moonillum*100), "|";
	print F sprintf("%.2f",$moonage), "|";
	print F sprintf("%.2f",$moonphase*100), "|";
	
	# cur_moon_h
	print F "-9999|";
	
	# cur_sun_r && cur_sun_s
	my $dt_rise = DateTime::Format::ISO8601->parse_datetime($decodedCurrent->{current}->{sun}->{rise});
	$dt_rise->set_time_zone($tz_offset);
	my $sunrise_hour   = $dt_rise->hour;
	my $sunrise_minute = $dt_rise->minute;

	my $dt_set = DateTime::Format::ISO8601->parse_datetime($decodedCurrent->{current}->{sun}->{set});
	$dt_set->set_time_zone($tz_offset);
	my $sunset_hour   = $dt_set->hour;
	my $sunset_minute = $dt_set->minute;

	if (defined $sunrise_hour && defined $sunrise_minute && defined $sunset_hour && defined $sunset_minute) {
		print F sprintf("%02d", $sunrise_hour), "|";
		print F sprintf("%02d", $sunrise_minute), "|";
		print F sprintf("%02d", $sunset_hour), "|";
		print F sprintf("%02d", $sunset_minute), "|";
	} else {
		print F "-9999|";
		print F "-9999|";
		print F "-9999|";
		print F "-9999|";
	}

	# cur_ozone
	print F "-9999|";
	
	# cur_sky
	print F "-9999|";
	
	# cur_pop
	my $cur_pop = $decodedCurrent->{current}->{precipitation}->{probability}*100;
	print F sprintf("%.0f",$cur_pop), "|";
		
	# cur_snow
	print F "-9999|";
	
	
	print F "\n";
  flock(F,8);
close(F);

LOGOK "Saving current data to $lbplogdir/current.dat.tmp successfully.";

LOGDEB "Database content:";
open(F,"<$lbplogdir/current.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

} # End current


#
# Fetch daily data
#

if ( $daily ) { # Start daily

# Saving new daily forecast data...

open(F,">$lbplogdir/dailyforecast.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/dailyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	my $i = 1;
	for my $results( @{$decodedDaily} ){
		# dfc0_per
		print F "$i|";
		$i++;
		
		# dfc0_date
		my $date_str = qx( TZ='$timezone' date  -d "$results->{date}" +'%Y-%m-%d' );
		chomp($date_str);
		my $t = Time::Piece->strptime($date_str, "%Y-%m-%d");
		my $epoch_time = $t->epoch;
		print F $epoch_time, "|";
		print F sprintf("%02d", $t->mday), "|";
		print F sprintf("%02d", $t->mon), "|";
		my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";

		# dfc0_tt_h
		print F sprintf("%.1f",$results->{temperature}->{max}->{air}), "|";
		
		# dfc0_tt_l
		print F sprintf("%.1f",$results->{temperature}->{min}->{air}), "|";
		
		# dfc0_pop
		if ($results->{precipitation}{probability}) {
                        print F sprintf("%.0f",$results->{precipitation}{probability} * 100), "|";
                } else {
                        print F "0|";
                }
				
		# dfc0_prec
		if ($results->{precipitation}{details}{rainfall_amount}{millimeter}{interval_end}) {
			print F sprintf("%.2f",$results->{precipitation}{details}{rainfall_amount}{millimeter}{interval_end}), "|";
		} else {
			print F "0|";
		}
		
		# dfc0_snow
		if ($results->{precipitation}{details}{snow_height}{centimeter}{interval_end}) {
			print F sprintf("%.2f",$results->{precipitation}{details}{snow_height}{centimeter}{interval_end}), "|";
		} else {
			print F "0|";
		}
		
		# dfc0_w_sp_h
		print F sprintf("%.2f",$results->{wind}{speed}{kilometer_per_hour}{value}), "|";

		# dfc0_w_dirdes_h
		$wdir = $results->{wind}{direction};
			if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
			if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
			if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
			if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
			if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
			if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
			if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
			if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
			if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		print F "$wdirdes|";

		# dfc0_w_dir_h
		print F "$results->{wind}{direction}|";
		
		# dfc0_w_sp_a
		print F sprintf("%.2f",$results->{wind}{speed}{kilometer_per_hour}{value}), "|";
		
		# dfc0_w_dirdes_a
		print F "$wdirdes|";
		
		# dfc0_w_dir_a
		print F "$results->{wind}{direction}|";
		
		# dfc0_hu_a
		print F sprintf("%.0f",$results->{humidity} * 100), "|";
		
		# dfc0_hu_h && dfc0_hu_l
		my $min_humidity = 1;
		my $max_humidity = 0;
		my @dayparts = @{$results->{dayparts}};
		foreach my $daypart (@dayparts) {
			my $humidity = $daypart->{humidity};
			if ($humidity < $min_humidity) {
				$min_humidity = $humidity;
			}
			if ($humidity > $max_humidity) {
				$max_humidity = $humidity;
			}
		}
		print F sprintf("%.0f",$max_humidity * 100), "|";
		print F sprintf("%.0f",$min_humidity * 100), "|";
		
		# dfc0_we_icon, dfc0_we_code, dfc0_we_des	
		# Mapping: Wetteronline Symbol => [Loxone Code, Weather4Lox Icon, Description]
		my ($code, $icon, $description) = wetteronline_to_lox($results->{symbol});
		print F "$icon|";
		print F "$code|";
		print F "$description|";

		# dfc0_ozone
		print F "-9999|";
		
		# dfc0_moon_p
		my ( $moonphase,
		  $moonillum,
		  $moonage,
		  $moondist,
		  $moonang,
		  $sundist,
		  $sunang ) = phase($epoch_time);
		print F sprintf("%.2f",$moonillum*100), "|";
#		my $moonage = $results->{moon}{age};
#		my $moonphase = $moonage / 30;
#		my $moonpercent = 0;
#		if ($moonphase le "0.5") {
#			$moonpercent = $moonphase * 2 * 100;
#		} else {
#			$moonpercent = (1 - $moonphase) * 2 * 100;
#		}
#		print F "$moonpercent|";

		# dfc0_dp
		my $sum_dew_point = 0;
		my $count = 0;
		foreach my $daypart (@dayparts) {
			my $dew_point = $daypart->{dew_point}{celsius};
			$sum_dew_point += $dew_point;
			$count++;
		}
		my $average_dew_point = $sum_dew_point / $count;
		print F sprintf("%.1f",$average_dew_point), "|";
		
		# dfc0_pr
		print F sprintf("%.0f",$results->{air_pressure}{hpa}), "|";
		
		# dfc0_uvi
		print F sprintf("%.1f",$results->{uv_index}{value}),"|";
		
		# dfc0_sun_r
		my $sunrise_str = qx( TZ='$timezone' date  -d "$results->{sun}{rise}" +'%Y-%m-%d %H:%M' );
		chomp($sunrise_str);
		my $srt = Time::Piece->strptime($sunrise_str, "%Y-%m-%d %H:%M");
		print F sprintf("%02d", $srt->hour), "|";
		print F sprintf("%02d", $srt->minute), "|";
		
		# dfc0_sun_s
		my $sunset_str = qx( TZ='$timezone' date  -d "$results->{sun}{set}" +'%Y-%m-%d %H:%M' );
		chomp($sunset_str);
		$srt = Time::Piece->strptime($sunset_str, "%Y-%m-%d %H:%M");
		print F sprintf("%02d", $srt->hour), "|";
		print F sprintf("%02d", $srt->minute), "|";
		
		#dfc0_vis
		print F "-9999";

		# dfc0_moon_a
		print F sprintf("%.2f",$moonage), "|";
		
		# dfc0_moon_ph
		print F sprintf("%.2f",$moonphase*100), "|";

		print F "\n";
	}
  flock(F,8);
close(F);

LOGOK "Saving daily forecast data to $lbplogdir/dailyforecast.dat.tmp successfully.";

LOGDEB "Database content:";
open(F,"<$lbplogdir/dailyforecast.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

} # End daily

#
# Fetch hourly data
#

if ( $hourly ) { # Start hourly

# Saving new hourly forecast data...

$error = 0;
my $epoch_time = 0;
open(F,">$lbplogdir/hourlyforecast.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/hourlyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	$i = 1;
	my $n = 0;
	for my $results( @{$decodedHourly->{hours}} ){
		# Skip first dataset (eq to current)
		#if ($n eq "0") {
		#	$n++;
		#	next;
		#}
		
		# hfc1_per
		print F "$i|";
		$i++;
		
		# hfc1_date
		my $date_str = qx( TZ='$timezone' date  -d "$results->{date}" +'%Y-%m-%d %H:%M' );
		chomp($date_str);
		my $t = Time::Piece->strptime($date_str, "%Y-%m-%d %H:%M");
		$epoch_time = $t->epoch;
		print F $epoch_time, "|";

		# hfc1_day && hfc1_month && hfc1_monthn && hfc1_monthn_sh && hfc1_year && hfc1_hour &&hfc1_min && hfc1_wday && hfc1_wday_sh
		print F sprintf("%02d", $t->mday), "|";
		print F sprintf("%02d", $t->mon), "|";
		my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";

		# hfc1_tt
		print F sprintf("%.1f",$results->{temperature}{air}), "|";

		# hfc1_tt_fl
		print F sprintf("%.1f",$results->{temperature}{apparent}), "|";
		
		# hfc1_hi
		print F "-9999|";
		
		# hfc1_hu
		print F sprintf("%.0f",$results->{humidity} * 100), "|";
		
		# hfc1_w_dirdes
		$wdir = $results->{wind}{direction};
			if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
			if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
			if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
			if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
			if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
			if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
			if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
			if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
			if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		print F "$wdirdes|";

		# hfc1_w_dir
		print F "$results->{wind}{direction}|";
		
		# hfc1_w_sp
		print F sprintf("%.2f",$results->{wind}{speed}{kilometer_per_hour}{value}), "|";
		
		# hfc1_w_ch
		print F sprintf("%.1f",$results->{temperature}{apparent}), "|";
		
		# hfc1_pr
		print F sprintf("%.0f",$results->{air_pressure}{hpa}), "|";
		
		# hfc1_dp
		print F sprintf("%.1f",$results->{dew_point}{celsius}), "|";
		
		# hfc1_sky
		print F "-9999|";
		
		# hfc1_sky_des
		print F "-9999|";
		
		# hfc1_uvi
		print F "-9999|";
		
		# hfc1_prec
		if ($results->{precipitation}{details}{rainfall_amount}{millimeter}) {
			my $rfamount = ($results->{precipitation}{details}{rainfall_amount}{millimeter}{interval_begin} + $results->{precipitation}{details}{rainfall_amount}{millimeter}{interval_end}) / 2;
			print F sprintf("%.2f",$rfamount), "|";
		} else {
			print F "0|";
		}
		
		# hfc1_snow
		if ($results->{precipitation}{details}{snow_height}{centimeter}) {
			print F sprintf("%.2f",$results->{precipitation}{details}{snow_height}{centimeter}), "|";
		} else {
			print F "0|";
		}
		
		# hfc1_pop
		if ($results->{precipitation}{probability}) {
                        print F sprintf("%.0f",$results->{precipitation}{probability} * 100), "|";
                } else {
                        print F "0|";
                }
				
		# hfc1_we_icon && hfc1_we_code, hfc1_we_des
		# Mapping: Wetteronline Symbol => [Loxone Code, Weather4Lox Icon, Description]
		my ($code, $icon, $description) = wetteronline_to_lox($results->{symbol});
		print F "$icon|";
		print F "$code|";
		print F "$description|";

		# Ozone
		print F "-9999|";
		
		# Solar Radiation
		print F "-9999|";
		
		# Visibility km
		print F sprintf("%.2f",$results->{visibility} / 1000), "|";
		
		# hfc0_moon_p
		my ( $moonphase,
		  $moonillum,
		  $moonage,
		  $moondist,
		  $moonang,
		  $sundist,
		  $sunang ) = phase($epoch_time);
		print F sprintf("%.2f",$moonillum*100), "|";

		# hfc0_moon_a
		print F sprintf("%.2f",$moonage), "|";
		
		# hfc0_moon_ph
		print F sprintf("%.2f",$moonphase*100), "|";
		
		print F "\n";
		}
		
	# WetterOnline only offers 32h hourly forecast. Fill data with "-9999" to have at least 72h of hourly forecast data for the weather emulator - otherwise Loxone app scrambles the webdata.
	while ($i <= 75) {
			
		# hfc1_per
		print F "$i|";
		$i++;

		# hfc1_date
		$epoch_time += 3600;
		print F "$epoch_time|";
		$t = Time::Piece->new ($epoch_time);

		# hfc1_day && hfc1_month && hfc1_monthn && hfc1_monthn_sh && hfc1_year && hfc1_hour &&hfc1_min && hfc1_wday && hfc1_wday_sh
		print F sprintf("%02d", $t->mday), "|";
		print F sprintf("%02d", $t->mon), "|";
		my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";

		# using fixed dummy data for the rest of the hourly forecast dataset, otherwise Loxone app returns black screen due to missing picto-icons
		print F "0.0|0.0|-9999|0|Norden|0|0|0|1024|0.0|-9999|-9999|-9999|0.0|0|0|overcast|5|Keine Daten|-9999|-9999|0.0|0.0|0.0|0.0|\n";
		# writing dummy data dataset is full
		#my $x = 0;
		#while ($x < 25) {
		#	$x++;
		#	print F "-9999|";
		#}
		#print F "\n";
	}


  flock(F,8);
close(F);

LOGOK "Saving hourly forecast data to $lbplogdir/hourlyforecast.dat.tmp successfully.";

LOGDEB "Database content:";
open(F,"<$lbplogdir/hourlyforecast.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

} # end hourly

# Clean Up Databases

if ( $current ) {

LOGINF "Cleaning $lbplogdir/current.dat.tmp";
open(F,"+<$lbplogdir/current.dat.tmp");
  flock(F,2);
	@filecontent = <F>;
	seek(F,0,0);
	truncate(F,0);
	foreach (@filecontent){
		s/[\n\r]//g;
		if($_ =~ /^#/) {
		  print F "$_\n";
		  next;
		}
		LOGDEB "Original: $_";
		s/\|null\|/"|0|"/eg;
		s/\|--\|/"|0|"/eg;
		s/\|na\|/"|-9999.00|"/eg;
		s/\|NA\|/"|-9999.00|"/eg;
		s/\|n\/a\|/"|-9999.00|"/eg;
		s/\|N\/A\|/"|-9999.00|"/eg;
		LOGDEB "Cleaned:  $_";
		print F "$_\n";
	}
  flock(F,8);
close(F);
my $currentname = "$lbplogdir/current.dat.tmp";
my $currentsize = -s ($currentname);
if ($currentsize > 100) {
        move($currentname, "$lbplogdir/current.dat");
}

}

if ( $daily ) {

LOGINF "Cleaning $lbplogdir/dailyforecast.dat.tmp";
open(F,"+<$lbplogdir/dailyforecast.dat.tmp");
  flock(F,2);
	@filecontent = <F>;
	seek(F,0,0);
	truncate(F,0);
	foreach (@filecontent){
		s/[\n\r]//g;
		if($_ =~ /^#/) {
		  print F "$_\n";
		  next;
		}
		LOGDEB "Original: $_";
		s/\|null\|/"|0|"/eg;
		s/\|--\|/"|0|"/eg;
		s/\|na\|/"|-9999.00|"/eg;
		s/\|NA\|/"|-9999.00|"/eg;
		s/\|n\/a\|/"|-9999.00|"/eg;
		s/\|N\/A\|/"|-9999.00|"/eg;
		LOGDEB "Cleaned:  $_";
		print F "$_\n";
	}
  flock(F,8);
close(F);
my $dailyname = "$lbplogdir/dailyforecast.dat.tmp";
my $dailysize = -s ($dailyname);
if ($dailysize > 100) {
        move($dailyname, "$lbplogdir/dailyforecast.dat");
}

}

if ( $hourly ) {

LOGINF "Cleaning $lbplogdir/hourlyforecast.dat.tmp";
open(F,"+<$lbplogdir/hourlyforecast.dat.tmp");
  flock(F,2);
	@filecontent = <F>;
	seek(F,0,0);
	truncate(F,0);
	foreach (@filecontent){
		s/[\n\r]//g;
		if($_ =~ /^#/) {
		  print F "$_\n";
		  next;
		}
		LOGDEB "Original: $_";
		s/\|null\|/"|0|"/eg;
		s/\|--\|/"|0|"/eg;
		s/\|na\|/"|-9999.00|"/eg;
		s/\|NA\|/"|-9999.00|"/eg;
		s/\|n\/a\|/"|-9999.00|"/eg;
		s/\|N\/A\|/"|-9999.00|"/eg;
		LOGDEB "Cleaned:  $_";
		print F "$_\n";
	}
  flock(F,8);
close(F);
my $hourlyname = "$lbplogdir/hourlyforecast.dat.tmp";
my $hourlysize = -s ($hourlyname);
if ($hourlysize > 100) {
        move($hourlyname, "$lbplogdir/hourlyforecast.dat");
}

}

# Give OK status to client.
LOGOK "Current Data and Forecasts saved successfully.";

# Exit
exit;

END
{
	LOGEND;
}
