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
#use JSON qw( decode_json );
use File::Copy;
use File::Basename qw(basename);
use Getopt::Long;
use Time::Piece;
#use Math::Function::Interpolator;
use HTTP::Request;
use DateTime;
#use DateTime::TimeZone;
#use DateTime::Format::ISO8601;
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

# params from config
my $pcfg             = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $city             = $pcfg->param("WETTERONLINE.STATIONID");

# names for JSON 
my $grabber_file     = basename(__FILE__);
my $grabber_label    = "Wetter Online";
my $grabber_key      = "wetteronline";          # name in JSONs

my $weather_key;

# params for API calls
my $apikey           = "av=2&mv=13&c=d2ViOmFxcnhwWDR3ZWJDSlRuWeb=";
my $apikey_current   = "c=d293ZWI6QzhMNFRINmVUbkRoVWFqYg==";
my $useragent        = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36";
my $urlGEO_raw       = "https://www.wetteronline.de/wetter/";
my $uriUV_raw        = "?prefpar=sun";
my $urlCurrent_raw   = "https://api-web.wo-cloud.com/weather/nowcast/v10?";
my $urlDaily_raw     = "https://api-app.wetteronline.de/app/weather/forecast?";
my $urlHourly_raw    = "https://api-app.wetteronline.de/app/weather/hourcast?";

# all values in current, daily, and hourly JSONs are in local time, so proper time zone information is important
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
GetOptions ('verbose'  => \$verbose,
            'quiet'    => sub { $verbose = 0 },
            'current'  => \$current,
            'daily'    => \$daily,
            'hourly'   => \$hourly,
            'maskkeys' => \$maskkeys,
			);

if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGSTART "Weather4Lox GRABBER_WETTERONLINE process started";
LOGDEB "This is $0 Version $version";

require_or_logdie('DateTime::Format::ISO8601');

if ($hourly) {
    #require_or_logdie('Lexical::Sub');
    require_or_logdie('Math::Function::Interpolator');
    require_or_logdie('Math::Function::Interpolator::Linear');
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
my $resCurrent = api_call(
	url => "$urlCurrent_raw$apikey_current&grid_longitude=$long&grid_latitude=$lat&location_id=$gid&astro_longitude=$long&astro_latitude=$lat&latitude=$lat&longitude=$long&timezone=$timezone&language=de-DE&timeformat=HH:mm&windunit=kmh&system_of_measurement=metric&altitude=$altitude",
	# maskkeys => $maskkeys,    # no masking needed here as there are no secret API keys
	# keyparam => 'appid',
	# apikey => $apikey,
	info => "for Location $city (Current Weather Data)",
);

# Get weather data from wetteronline.de (API request) for daily conditions
my $resDaily = api_call(
	url => "$urlDaily_raw$apikey&location_id=$gid&timezone=$timezone",
	# maskkeys => $maskkeys,    # no masking needed here as there are no secret API keys
	# keyparam => 'appid',
	# apikey => $apikey,
	info => "for Location $city (Daily Weather Data)",
);

# Get weather data from wetteronline.de (API request) for hourly conditions
my $resHourly = api_call(
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

    # clouds in steps from clear to overcast, each with code for day and night (kept in mapping for clarity)
    "so____" => ["1", "clear", "Sonnig"],                                        # sonnig bzw. klar / wolkenlos (Tag)
    "mo____" => ["1", "clear", "Klar"],                                          # sonnig bzw. klar / wolkenlos (Nacht)
    "wb____" => ["2", "partly_cloudy", "Teilweise bewölkt"],                     # leicht bewölkt (Tag)
  # "mb____" => ["2", "partly_cloudy", "Teilweise bewölkt"],                     # leicht bewölkt (Nacht)
    "bw____" => ["3", "cloudy", "Bewölkt"],                                      # Bewölkt (Tag)
  # "mw____" => ["3", "cloudy", "Bewölkt"],                                      # Bewölkt (Nacht)
    "bd____" => ["5", "overcast", "Bedeckt"],                                    # bedeckt (Tag)
  # "md____" => ["5", "overcast", "Bedeckt"],                                    # Bedeckt (Nacht)

    # fog/haze
    "ns____" => ["6", "cloudy_fog", "Teils neblig"],                             # teils neblig (Tag)
  # "nm____" => ["6", "cloudy_fog", "Teils neblig"],                             # teils neblig (Nacht)
    "nb____" => ["6", "overcast_fog", "Nebelig"],                                # neblig / Nebel

	# Schauer

    # Schauer (mit Tag und Nacht) bei leicht bewölkt
    "wbs1__" => ["16", "cloudy_shower_1", "Leicht bewölkt mit vereinzelten Regenschauern"],  # leicht bewölkt und vereinzelt Schauer
    "wbs2__" => ["16", "cloudy_shower_1", "Leicht bewölkt mit Regenschauern"],               # leicht bewölkt und Schauer
    "wbs3__" => ["12", "cloudy_shower_2", "Leicht bewölkt mit starken Regenschauern"],       # leicht bewölkt und Starke Regenschauer 

    # Schauer (mit Tag und Nacht) bei bewölkt
    "bws1__" => ["16", "cloudy_shower_1", "Bewölkt mit vereinzelten Regenschauern"],         # bewölkt und vereinzelt Schauer
    "bws2__" => ["16", "cloudy_shower_2", "Bewölkt mit Regenschauern"],                      # bewölkt und Schauer
    "bws3__" => ["12", "cloudy_shower_3", "Bewölkt mit starken Regenschauern"],              # bewölkt und Starke Regenschauer

    # Schauer (mit Tag und Nacht) bei bedeckt
    "bds1__" => ["10", "overcast_shower_1", "Bedeckt mit vereinzelten Regenschauern"],       # Leichter Regenschauer
    "bds2__" => ["11", "overcast_shower_2", "Bedeckt mit Regenschauern"],                    # Regenschauer
    "bds3__" => ["12", "overcast_shower_3", "Bedeckt mit starken Regenschauern"],            # Starker Regenschauer

	# Regen

    # Regen (Tag und Nacht) bei leicht bewölkt
    "wbr1__" => ["16", "cloudy_rain_1", "Leicht bewölkt mit leichtem Regen"],                # leicht bewölkt und leichter Regen
    "wbr2__" => ["11", "cloudy_rain_1", "Leicht bewölkt mit Regen"],                         # leicht bewölkt und Regen
    "wbr3__" => ["12", "cloudy_rain_2", "Leicht bewölkt mit starker Regen"],                 # leicht bewölkt und Starker Regen

    # Regen (Tag und Nacht) bei bewölkt
    "bwr1__" => ["16", "cloudy_rain_1", "Bewölkt mit leichtem Regen"],                       # bewölkt und leichter Regen
    "bwr2__" => ["11", "cloudy_rain_2", "Bewölkt mit Regen"],                                # bewölkt und Regen
    "bwr3__" => ["12", "cloudy_rain_2", "Bewölkt mit starker Regen"],                        # bewölkt und Starker Regen

    # Regen (Tag und Nacht) bei bedeckt
    "bdr1__" => ["16", "overcast_rain_1", "Bedeckt mit Regenschauern"],                      # bedeckt, etwas Regen oder vereinzelt Schauer
    "bdr2__" => ["11", "overcast_rain_2", "Bedeckt mit Regen"],                              # bedeckt, Regen oder Schauer
    "bdr3__" => ["12", "overcast_rain_3", "Bedeckt mit ergiebigem Regen"],                   # bedeckt und ergiebiger Regen

	# Schneeregenschauer

    # Schneeregenschauer (Tag und Nacht) bei leicht bewölkt
    "wbsrs1" => ["28", "cloudy_sleet_1", "Leicht bewölkt mit vereinzelten Schneeregenschauern"],                  # leicht bewölkt und vereinzelt Schneeregenschauer
    "wbsrs2" => ["28", "cloudy_sleet_1", "Leicht bewölkt mit Schneeregenschauern"],                              # leicht bewölkt und Schneeregenschauer
    "wbsrs3" => ["29", "cloudy_sleet_2", "Leicht bewölkt mit starken Schneeregenschauern"],                       # leicht bewölkt und Schneeregenschauer

    # Schneeregenschauer (Tag und Nacht) bei bewölkt
    "bwsrs1" => ["28", "cloudy_sleet_1", "Bewölkt mit vereinzelten Schneeregenschauern"],                  # bewölkt und vereinzelt Schneeregenschauer
    "bwsrs2" => ["28", "cloudy_sleet_2", "Bewölkt mit Schneeregenschauern"],                              # bewölkt und Schneeregenschauer
    "bwsrs3" => ["29", "cloudy_sleet_2", "Bewölkt mit starken Schneeregenschauern"],                       # bewölkt und Schneeregenschauer

    # Schneeregenschauer (Tag und Nacht) bei bedeckt
    "bdsrs1" => ["25", "overcast_sleet_1", "Bedeckt mit Leichten Schneeregenschauern"],                    # bedeckt, leichter Schneeregen oder vereinzelt Schneeregenschauer
    "bdsrs2" => ["26", "overcast_sleet_2", "Bedeckt mit Schneeregenschauern"],                            # bedeckt, Schneeregen oder Schneeregenschauer
    "bdsrs3" => ["27", "overcast_sleet_3", "Bedeckt mit ergiebigen Schneeregenschauern"],                  # bedeckt und ergiebiger Schneeregen

    # Schneeregen

    # leicht bewölkt und Schneeregen (Tag und Nacht)
    "wbsr1_" => ["25", "cloudy_sleet_1", "Leicht bewölkt mit leichtem Schneeregen"],                            # leicht bewölkt und vereinzelt Schneeregen (Tag)
    "wbsr2_" => ["26", "cloudy_sleet_2", "Leicht bewölkt mit Schneeregen"],                                     # leicht bewölkt und Schneeregen (Tag)
    "wbsr3_" => ["27", "cloudy_sleet_2", "Leicht bewölkt mit starkem Schneeregen"],                             # leicht bewölkt und ergiebiger Schneeregen (Tag)

    # bewölkt und Schneeregen (Tag und Nacht)
    "bwsr1_" => ["25", "cloudy_sleet_1", "Bewölkt mit leichtem Schneeregen"],                            # bewölkt und vereinzelt Schneeregen (Tag)
    "bwsr2_" => ["26", "cloudy_sleet_2", "Bewölkt mit Schneeregen"],                                     # bewölkt und Schneeregen (Tag)
    "bwsr3_" => ["27", "cloudy_sleet_2", "Bewölkt mit starkem Schneeregen"],                             # bewölkt und ergiebiger Schneeregen (Tag)

    # bedeckt und Schneeregen (Tag und Nacht)
    "bdsr1_" => ["25", "overcast_sleet_1", "Bedeckt mit leichtem Schneeregen"],                          # bedeckt, leichter Schneeregen oder vereinzelt Schneeregenschauer
    "bdsr2_" => ["26", "overcast_sleet_2", "Bedeckt mit Schneeregen"],                                   # bedeckt, Schneeregen oder Schneeregenschauer
    "bdsr3_" => ["27", "overcast_sleet_3", "Bedeckt mit ergiebigem Schneeregen"],                        # bedeckt und ergiebiger Schneeregen

    # Schneeschauer

    # leicht bewölkt und Schneeschauer
    "wbsns1" => ["23", "cloudy_snow_1", "Leicht bewölkt mit leichten Schneeschauern"],                        # leicht bewölkt und vereinzelt Schneeschauer (Tag)
    "wbsns2" => ["24", "cloudy_snow_1", "Leicht bewölkt mit Schneeschauern"],                                 # leicht bewölkt und Schneeschauer (Tag)
    "wbsns3" => ["24", "cloudy_snow_2", "Leicht bewölkt mit starken Schneeschauern"],                         # leicht bewölkt und starke Schneeschauer (Tag)

    # bewölkt und Schneeschauer
    "bwsns1" => ["23", "cloudy_snow_1", "Bewölkt mit leichten Schneeschauern"],                        # bewölkt und vereinzelt Schneeschauer (Tag)
    "bwsns2" => ["24", "cloudy_snow_2", "Bewölkt mit Schneeschauern"],                                 # bewölkt und Schneeschauer (Tag)
    "bwsns3" => ["24", "cloudy_snow_2", "Bewölkt mit starken Schneeschauern"],                         # bewölkt und starke Schneeschauer (Tag)

    # bedeckt und Schneeschauer
    "bdsns1" => ["23", "overcast_snow_1", "Bedeckt mit leichten Schneeschauern"],                        # bedeckt, leichter Schneefall oder vereinzelt Schneeschauer
    "bdsns2" => ["24", "overcast_snow_2", "Bedeckt mit Schneeschauern"],                                 # bedeckt, Schneefall oder Schneeschauer
    "bdsns3" => ["24", "overcast_snow_3", "Bedeckt mit starken Schneeschauern"],                         # bedeckt und ergiebiger Schneefall

    # Schneefall

    # leicht bewölkt und Schneefall
    "wbsn1_" => ["20", "cloudy_snow_1", "Leicht bewölkt mit leichtem Schneefall"],                           # leicht bewölkt und vereinzelt Schneefall (Tag)
    "wbsn2_" => ["21", "cloudy_snow_2", "Leicht bewölkt mit Schneefall"],                                    # leicht bewölkt und Schneefall (Tag)
    "wbsn3_" => ["22", "cloudy_snow_2", "Leicht bewölkt mit starkem Schneefall"],                            # leicht bewölkt und starker Schneefall (Tag)

    # bewölkt und Schneefall
    "bwsn1_" => ["20", "cloudy_snow_1", "Bewölkt mit leichtem Schneefall"],                           # bewölkt und vereinzelt Schneefall (Tag)
    "bwsn2_" => ["21", "cloudy_snow_2", "Bewölkt mit Schneefall"],                                    # bewölkt und Schneefall (Tag)
    "bwsn3_" => ["22", "cloudy_snow_2", "Bewölkt mit starkem Schneefall"],                            # bewölkt und starker Schneefall (Tag)

    # bedeckt und Schneefall
    "bdsn1_" => ["20", "overcast_snow_1", "Bedeckt mit leichtem Schneefall"],                           # bedeckt, leichter Schneefall oder vereinzelt Schneeschauer (Tag)
    "bdsn2_" => ["21", "overcast_snow_2", "Bedeckt mit Schneefall"],                                    # bedeckt, Schneefall oder Schneeschauer (Tag)
    "bdsn3_" => ["22", "overcast_snow_3", "Bedeckt mit ergiebigem Schneefall"],                         # bedeckt und ergiebiger Schneefall (Tag)

    # Schnegewitter

    # leicht bewölkt und Schneegewitter
    "wbsg__" => ["24", "cloudy_snowthunderstorm_1", "Leicht bewölkt mit vereinzelten Wintergewittern"],                     # leicht bewölkt und Schneegewitter (Tag)

    # bewölkt und Schneegewitter
    "bwsg__" => ["24", "cloudy_snowthunderstorm_2", "Bewölkt mit Wintergewittern"],                                # bewölkt und Schneegewitter (Tag)

    # bedeckt und Schneegewitter
    "bdsg__" => ["24", "cloudy_snowthunderstorm_2", "Bedeckt mit Wintergewittern"],                                # bedeckt und Schneegewitter (Tag)

    # Gewitter

    # leicht bewölkt mit Gewitter (Tag und Nacht)
    "wbg1__" => ["18", "cloudy_thunderstorm_1", "Leicht bewölkt mit vereinzelten Gewittern"],                        # leicht bewölkt, vereinzelt Schauer und Gewitter (Tag)
    "wbg2__" => ["18", "cloudy_thunderstorm_2", "Leicht bewölkt mit Gewittern"],                                   # leicht bewölkt, Schauer und Gewitter (Tag)
    "wbg3__" => ["19", "cloudy_thunderstorm_3", "Leicht bewölkt mit kräftigen Gewittern"],                         # leicht bewölkt, Schauer und Gewitter (Tag)

    # Bewölkt mit Gewitter (Tag und Nacht)
    "bwg1__" => ["18", "cloudy_thunderstorm_1", "Bewölkt mit vereinzelten Gewittern"],                        # bewölkt, vereinzelt Schauer und Gewitter (Tag)
    "bwg2__" => ["18", "cloudy_thunderstorm_2", "Bewölkt mit Gewittern"],                                   # Gewitter (Tag)
    "bwg3__" => ["19", "cloudy_thunderstorm_3", "Bewölkt mit kräftigen Gewittern"],                         # starke Gewitter (Tag)

    # Bedeckt mit Gewitter (Tag und Nacht)
    "bdg1__" => ["18", "overcast_thunderstorm_1", "Bedeckt mit vereinzelten Gewittern"],                                   # bedeckt, vereinzelt Schauer und Gewitter
    "bdg2__" => ["18", "overcast_thunderstorm_2", "Bedeckt mit Gewittern"],                                   # bedeckt, Schauer und Gewitter (Tag)

    # gefrierender Regen

    # leicht Bewölkt mit gefrierendem Regen (Tag und Nacht)
    "wbgr1_" => ["14", "cloudy_freezingrain_1", "Leicht bewölkt mit gefrierendem Sprühregen"],                      # bewölkt und gefrierender Sprühregen (Tag)
    "wbgr2_" => ["14", "cloudy_freezingrain_2", "Leicht bewölkt mit gefrierendem Regen"],                           # bewölkt und gefrierender Regen (Tag)

    # Bewölkt mit gefrierendem Regen (Tag und Nacht)
    "bwgr1_" => ["14", "cloudy_freezingrain_1", "Bewölkt mit gefrierendem Sprühregen"],                      # bewölkt und gefrierender Sprühregen (Tag)
    "bwgr2_" => ["14", "cloudy_freezingrain_2", "Bewölkt mit gefrierendem Regen"],                           # bewölkt und gefrierender Regen (Tag)

    # Bedeckt mit gefrierendem Regen (Tag und Nacht)
    "bdgr1_" => ["14", "overcast_freezingrain_1", "Bedeckt mit gefrierendem Sprühregen"],                      # bedeckt und gefrierender Sprühregen (Tag)
    "bdgr2_" => ["14", "overcast_freezingrain_2", "Bedeckt mit gefrierendem Regen"],                           # bedeckt und gefrierender Regen (Tag)

    # Graupel, Hagel und Eiskörner (Tag und Nacht)
    "bwgs1_" => ["28", "overcast_sleet_1", "Leichte Graupelschauer"],                        # leichte Graupelschauer
    "bwgs2_" => ["26", "overcast_sleet_2", "Graupelschauer"],                                 # Graupelschauer

    "bwhs1_" => ["28", "overcast_hail_1", "Leichte Hagelschauer"],                           # leichte Hagelschauer
    "bwhs2_" => ["26", "overcast_hail_2", "Hagelschauer"],                                   # Hagelschauer

    "bwek__" => ["26", "overcast_hail_3", "Eiskörner"],                                      # Eiskörner
);

# Convert night symbols with clouds to day symbols to reduce the lookup table
my %night_to_day_prefix = (
	'mb' => 'wb',  # lightly cloudy night -> lightly cloudy day
	'mw' => 'bw',  # cloudy night -> cloudy day
	'md' => 'bd',  # overcast night -> overcast day
	'nm' => 'ns',  # partly foggy night -> partly foggy day
);

# TODO: second value is not used anymore
my %skycondition_by_prefix = (
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

sub skycondition_from_wocode {
	my ($wocode) = @_;

	# Check for empty/undefined values
	if (!defined $wocode || length($wocode) < 2) {
		LOGWARN "Wetteronline symbol '$wocode' (to calculate sky condition) is undefined!";
		return (undef);
	}
	# only the first two characters are relevant for sky condition
	my $prefix = substr($wocode, 0, 2);
	# Convert night symbols to day symbols for sky condition calculation
	if (exists $night_to_day_prefix{$prefix}) {
		$prefix = $night_to_day_prefix{$prefix};
	}
	my $entry  = $skycondition_by_prefix{$prefix};

	if ($entry && ref($entry) eq 'ARRAY' && @$entry >= 2) {
		return ($entry->[0]);
	}

	LOGWARN "Unknown Wetteronline symbol prefix '$prefix' for sky condition, using 'Unknown' as fallback.";
	return (undef);
}

sub wetteronline_to_lox {
    my ($wocode) = @_;
    
    # Check for empty/undefined values
    if (!defined $wocode || $wocode eq "") {
        LOGWARN "Wetteronline symbol is empty or was not found in data set!";
        return ("1", "clear", "No data");  # Default fallback
    }

	if (defined $wocode && length($wocode) >= 2) {
		$wocode =~ s/^(.{2})snr(.)$/${1}sr${2}_/;  # Convert "snr" to "sr" for Schneeregen
		my $prefix = substr($wocode, 0, 2);
		if (exists $night_to_day_prefix{$prefix}) {
			substr($wocode, 0, 2, $night_to_day_prefix{$prefix});
		}
	}
    
    # Lookup in the table
    my $result = $wetteronline_to_lox{$wocode};
    
    if ($result) {
        return @$result;  # Returns (code, icon, description)
    } else {
        LOGWARN "Unknown weather symbol from Wetteronline: '$wocode', using 'clear' as fallback.";
        return ("1", "clear", "No data");  # Default fallback
    }
}

my %nightsymbol = map { $_ => 1 } qw(mo mb mw md nm);  # Define night symbols for quick lookup

sub is_nighttime {
    my ($symbol) = @_;

    return ($nightsymbol{ substr($symbol, 0, 2) });  # Return 1 if it's a night symbol
}


##########################################################################
# Fetch common data
##########################################################################

# date/time in different ways for different use cases in W4L (e.g. epoch for calculations, ISO format for display, timezone info for reference)
my $dt_current = DateTime::Format::ISO8601->parse_datetime($resCurrent->{current}->{date});
$dt_current->set_time_zone($timezone);

# location information
my $city_name = get_value($resGeodata, 'locationname');
if (defined get_value($resGeodata, 'sublocationname') && 
    get_value($resGeodata, 'sublocationname') ne "") {
        $city_name .= ", " . get_value($resGeodata, 'sublocationname');
}
my $path = get_value($resGeodata, 'path');                  
my @locpath = $path ? split(/;/, $path) : ();
my $country = $locpath[5] // undef; 

# add location information once
my $location = {
    city         => $city_name,                                                          # cur_loc_n, e.g. "Schwarzenbek"
    country      => $country,                                                            # country name, e.g. Deutschlang
    country_code => get_value($resGeodata, 'location_info', 'geoObject', 'iso-3166-1'),  # country code
    elevation    => get_formatted('%.0f', $resGeodata, 'alt'),                           # altitude in meters
    latitude     => get_formatted('%.3f', $resGeodata, 'lat'),                           # latitude
    longitude    => get_formatted('%.3f', $resGeodata, 'lon'),                           # longitude
    timezone     => $timezone,                                                           # timezone string (e.g. "Europe/Berlin")
    tz_short     => $dt_current->strftime('%Z'),                                          # timezone abbreviation (e.g. "CET")
    tz_offset    => $dt_current->strftime('%z'),                                          # timezone offset (e.g. "+0100")
};


##########################################################################
# Fetch current data
##########################################################################

if ( $current ) {

    # Build clean record
    my %current_data;

    LOGINF "Reading current weather data from API response into W4L structure at $dt_current.";

    my %time;
    # $time{date}      = get_value($resCurrent, 'current', 'date');
    $time{datetime}  = _epoch_to_iso($dt_current->epoch, $timezone);                                                           # cur_date_des
    $time{epoch}     = $dt_current->epoch;                                                                                     # cur_date
    $time{timezone}  = $timezone;                                                                                              # cur_date_tz_des
    $time{tz_short}  = $dt_current->strftime('%Z');                                                                            # cur_date_tz_des_sh, e.g. "CET"
    $time{tz_offset} = $dt_current->strftime('%z');                                                                            # cur_date_tz, e.g. "+0100"

    $current_data{time} = \%time;

    # sunrise and set in local time, e.g. 05:47 and 17:39
    $current_data{sunrise} = get_time_formatted('%H:%M', $timezone, $resCurrent, 'current', 'sun', 'rise');                    # cur_sun_r 
    $current_data{sunset} = get_time_formatted('%H:%M', $timezone, $resCurrent, 'current', 'sun', 'set');                      # cur_sun_s

    # temperatures
    my %temperature;

    $temperature{air}        = get_formatted('%.1f', $resCurrent, 'current', 'temperature', 'air');                            # cur_tt.    - air temperature in °C
    $temperature{feels_like} = get_formatted('%.1f', $resCurrent, 'current', 'temperature', 'apparent');                       # cur_tt_fl  - feels like temperature in °C
    $temperature{wind_chill} = undef;                                                                                          # cur_w_ch   - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
    $temperature{heat_index} = undef;                                                                                          # cur_hi.    - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures

    $current_data{temperature} = \%temperature;

    # humidity
    $current_data{humidity} = get_percentage('%.2f', $resCurrent, 'current', 'humidity');                                      # cur_hu, in percentage
    
    # wind
    my %wind;

    my $wind_direction = get_value($resCurrent, 'current', 'wind', 'direction');

    $wind{direction}      = $wind_direction;                                                                                   # cur_w_dir, wind direction in degrees
    $wind{dir_label}      = get_wind_direction_label($wind_direction, \%L);                                                    # cur_w_dirdes, wind direction description, e.g. "Süden",
    $wind{speed}          = get_formatted('%.1f', $resCurrent, 'current', 'wind', 'speed', 'kilometer_per_hour', 'value');     # cur_w_sp, wind speed in km/h
    $wind{gust}           = get_formatted('%.1f', $resCurrent, 'current', 'wind', 'speed', 'kilometer_per_hour', 'max_gust');  # cur_w_gu, gust speed in km/h

    $current_data{wind} = \%wind;

    # air pressure
    $current_data{pressure} = get_formatted('%.0f', $resCurrent, 'current', 'air_pressure', 'hpa');                            # cur_pr, air pressure in hPa

    # dew point
    $current_data{dewpoint} = get_formatted('%.1f', $resCurrent, 'current', 'dew_point', 'celsius');                           # cur_dp, dew point in °C

    # visibility - not provided by API
    $current_data{visibility} = get_formatted('%.0f', $resCurrent, 'hours', 0, 'visibility');                                  # cur_vis, visibility in meters

    # solar radiation
    $current_data{solar_radiation} = undef;                                                                                    # cur_sr 

    # there is no UV index in the API response for current weather data, nor on the web page itself or 
    # hourly forecast data, but there is one for daily forecast
    # not sure if this should be the UV index for the current time or the day (maximum)
    $current_data{uv_index} = do {
        my $v = eval { $resDaily->[0]{uv_index}{value} };
        defined $v ? ( sprintf("%.0f", $v ) + 0 ) : undef;
    };                                                                                                                         # cur_uvi

    # precipitation
    my %precipitation;

    ####### TODO: API may not provide amount anymore - to be tested!
    $precipitation{rain_today_mm} = get_formatted(
        '%.2f',
        $resCurrent,
        'trend', 'items', 0, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end'
    );                                                                                                                         # cur_prec_today, today precipitation in mm

    $precipitation{rain_1hr_mm} = get_formatted(
        '%.2f',
        $resCurrent,
        'hours', 'items', 0, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end'
    );                                                                                                                         # cur_prec_1hr, 1h precipitation in mm

    $precipitation{probability} = get_percentage('%.2f', $resCurrent, 'current', 'precipitation', 'probability');              # cur_pop, probability in percent
    $precipitation{type} = get_value($resCurrent, 'current', 'precipitation', 'type');                                         # type of precipitation (rain, snow), undef, if it is currently not raining/snowing
    $precipitation{snow_today_cm} = get_formatted(
        '%.2f',
        $resCurrent,
        'trend', 'items', 0, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end'
    );                                                                                                                         # today height in cm
    $precipitation{snow_1h_cm} = get_formatted(
        '%.2f',
        $resCurrent,
        'hours', 'items', 0, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end'
    );                                                                                                                         # cur_snow, 1h height in cm

    $current_data{precipitation} = \%precipitation;

    # weather codes
    my %weather_codes;

    # Mapping: Wetteronline Symbol => [Loxone code, Weather4Lox code, description]
    my ($loxone_code, $w4l_code, $description);
    my $symbol = get_value($resCurrent, 'current', 'symbol');
    if (!defined $symbol) {
        LOGWARN "Wetteronline symbol for current weather is undefined!";
        ($loxone_code, $w4l_code, $description) = (5, 'no_data', 'Keine Beschreibung zu Wettersymbol');
    } else {
        ($loxone_code, $w4l_code, $description) = wetteronline_to_lox($symbol);
    }

    $weather_codes{loxone} = $loxone_code;                                                                                     # cur_code
    $weather_codes{weather4lox} = $w4l_code;                                                                                   # cur_icon
    $weather_codes{description} = $description;                                                                                # cur_des
    $weather_codes{image} = get_value($resCurrent, 'current', 'weather_condition_image');                                      # future use, e.g. as background image
    $weather_codes{metar} = get_metar_code($w4l_code);                                                                         # future use, e.g. scientific theme

    $current_data{weather_codes} = \%weather_codes;

    # ozone
    $current_data{ozone} = undef;                                                                                              # cur_ozone
    
    # sky condition - calculate from symbol code, API does not provide a separate value for sky condition
    $current_data{cloud_cover} = skycondition_from_wocode($symbol);                                                            # cur_sky

    # astro data
    my %moon;

    my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = phase();
    # age is delivered by API, , but makes no sense as phase() delivers all values
    # $moon{age} = get_formatted('%.2f', $resCurrent, 'moon', 0, 'age');
    $moon{age} = sprintf("%.2f",$moonage) + 0;                                                                                 # cur_moon_a
    $moon{percent} = sprintf("%.2f",$moonillum*100) + 0;                                                                       # cur_moon_p
    $moon{phase} = sprintf("%.2f",$moonphase*100) + 0;                                                                         # cur_moon_ph

    $current_data{moon} = \%moon;
    
    # night time - used for selecting day or night symbol
    $current_data{is_nighttime} = is_nighttime($symbol);                                                                       # is night time or undefined

    # Build envelope and write JSON to file
    $weather_key = "current";
    my $envelope = { 
        location => $location,
        $grabber_key => {
            filename        => "$lbplogdir/$weather_key.json",
            generated_at    => $dt_current->iso8601(),
            grabber_label   => $grabber_label,
            grabber_script  => $grabber_file,
            schema_version  => "v1.0",
        },
        $weather_key => \%current_data, 
    };
    write_json_file($lbplogdir, $weather_key, $envelope);

} # End current

##########################################################################
# Fetch daily data
##########################################################################

if ( $daily ) {
  
    my @daily_data;
    my $dt_result;
    my $results;
    my $i = 1;

    LOGINF "Reading daily weather data from API response into W4L structure at $dt_current.";

    # it is assumed, that the elements are ordered by time (ascending)
    for my $results (@{$resDaily}) {

        # values with additional calculations needs to be done before hash is assigned

        # time
        $dt_result = DateTime::Format::ISO8601->parse_datetime(get_value($results, 'date'));   # ISO date from API in UTC, e.g. 2026-03-13T23:00:00+00:00
        $dt_result->set_time_zone($timezone);

        # my @label_month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
        # my $monthname  = $label_month[$dt_result->month - 1];
        # my @label_month_sh = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
        # my $monthshort = $label_month_sh[$dt_result->month - 1];
        # my @label_days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
        # my $wdayname   = $label_days[$dt_result->day_of_week % 7];
        # my @label_days_sh = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
        # my $wdayshort  = $label_days_sh[$dt_result->day_of_week % 7];

        # wind
        my $wind_dir_avg = get_formatted('%.0f', $results, 'wind', 'direction'); 

        # Mapping: Wetteronline Symbol => [Loxone code, Weather4Lox code, description]
        my ($loxone_code, $w4l_code, $description);
        my $symbol = get_value($results, 'symbol');
        if (!defined $symbol) {
            LOGWARN "Wetteronline symbol for daily weather is undefined!";
            ($loxone_code, $w4l_code, $description) = (5, 'no_data', 'Keine Beschreibung zu Wettersymbol');
        } else {
            ($loxone_code, $w4l_code, $description) = wetteronline_to_lox($symbol);
        }

        # astro data - get moon infos for specific time of data set (translated to epoch time)
        my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = phase($dt_result->epoch);

        # Calculating min, max values from dayparts
        # humidity (min, max)
        # wind (max) for speed, gust, and direction

		my $humidity_min = 100; # 100%
		my $humidity_max = 0; # 0%

        my $wind_speed_max = -1;
        my $wind_gust_max = -1;
        my $wind_dir_max = 0;

        # get values for all four dayparts and calculate min and max for the day
		my @dayparts = @{ get_value($results, 'dayparts') // undef };
        if (!@dayparts) {
            LOGWARN "No dayparts found for daily data on date " . get_value($results, 'date') . ", min/max values will be set to null.";
            $humidity_min = undef;
            $humidity_max = undef;

            $wind_speed_max = undef;
            $wind_gust_max = undef;
            $wind_dir_max = undef;
        } else {
            foreach my $daypart (@dayparts) {
                my $humidity = get_percentage('%.2f', $daypart, 'humidity');

                if (defined $humidity){
                    if ($humidity < $humidity_min) {
                        $humidity_min = $humidity;
                    }
                    if ($humidity > $humidity_max) {
                        $humidity_max = $humidity;
                    }
                }

                my $wind_speed = get_formatted('%.0f', $daypart, 'wind', 'speed', 'kilometer_per_hour', 'value') // 0;
                my $wind_gust = get_formatted('%.0f', $daypart, 'wind', 'speed', 'kilometer_per_hour', 'max_gust') // 0;
                my $wind_dir = get_formatted('%.0f', $daypart, 'wind', 'direction') // 0;

                if ($wind_speed > $wind_speed_max) {
                    $wind_speed_max = $wind_speed;
                    $wind_dir_max = $wind_dir;
                }
                # if gust is present, it has preference for direction
                if ($wind_gust > $wind_gust_max) {
                    $wind_gust_max = $wind_gust;
                    $wind_dir_max = $wind_dir;
                }
            }
        }

        # dewpoint calculation
        my $dewpoint_avg;
        @dayparts = @{ get_value($results, 'dayparts') // undef };
        my $sum = 0; 
        my $cnt = 0;
        for my $daypart (@dayparts) {
            my $dewpoint = get_formatted('%.1f', $daypart, 'dew_point', 'celsius');
            $sum += $dewpoint if defined $dewpoint;
            $cnt++ if defined $dewpoint;
        }
        $dewpoint_avg = $cnt ? sprintf("%.1f", $sum/$cnt) : undef;

        push @daily_data, {

            day            => $i,                                                # dfc<X>_per, counter of day
            time => {
                # date       => get_value($results, 'date'),                       # original timestamp from API
                datetime     => _epoch_to_iso($dt_result->epoch, $timezone),     # ISO 8601 date string in local time (e.g. "2026-03-13T02:00:00+01:00")
                epoch        => $dt_result->epoch,                               # dfc<X>_date       - UNIX timestamp
                # wdayname   => $wdayname,                                       # name of day of week, e.g. Saturday  - TODO: verify if useful, client may calculate name as well
                # wdayshort  => $wdayshort,                                      # short name of day of week, e.g. Sa (two chars)
                # monthname  => $monthname,                                      # name of month, e.g. March
                # monthshort => $monthshort,                                     # name of month, e.g. Mar (three chars
            },
            temperature => {
                min => {
                    air         => get_formatted('%.1f', $results, 'temperature', 'min', 'air'),         # dfc<X>_tt_l      - daily min temperature (°C)
                    feels_like  => get_formatted('%.1f', $results, 'temperature', 'min', 'apparent'),    # dfc<X>_tt_fl_l   - min feels-like temperature
                    wind_chill  => undef,                                                                # hfc<X>_w_ch      - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
                },
                max => {
                    air         => get_formatted('%.1f', $results, 'temperature', 'max', 'air'),         # dfc<X>_tt_h      - daily max temperature (°C)
                    feels_like  => get_formatted('%.1f', $results, 'temperature', 'max', 'apparent'),    # dfc<X>_tt_fl_h   - max feels-like temperature
                    heat_index  => undef,                                                                # hfc<X>_hi        - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures
                },
            },
            wind => {
                avg => {
                    direction       => $wind_dir_avg,                                                                              # dfc<X>_w_dir_a     - wind direction (deg, max)
                    dir_label       => get_wind_direction_label($wind_dir_avg, \%L),                                               # dfc<X>_w_dirdes_a  - wind direction description (max)
                    speed           => get_formatted('%.2f', $results, 'wind', 'speed', 'kilometer_per_hour', 'value'),            # dfc<X>_w_sp_a      - wind speed max (km/h)
                    gust            => get_formatted('%.2f', $results, 'wind', 'speed', 'kilometer_per_hour', 'max_gust'),         # dfc<X>_w_gu_a      - wind gust max (km/h)
                },
                max => {
                    direction       => $wind_dir_max,                                                                              # dfc<X>_w_dir_h     - wind direction (deg, max)
                    dir_label       => get_wind_direction_label($wind_dir_max, \%L),                                               # dfc<X>_w_dirdes_h  - wind direction description (max)
                    speed           => $wind_speed_max,                                                                            # dfc<X>_w_sp_h      - wind speed max (km/h)
                    gust            => $wind_gust_max,                                                                             # dfc<X>_w_gu_h      - wind gust max (km/h)
                }
            },
            precipitation => {
                probability   => get_percentage('%.2f', $results, 'precipitation', 'probability'),                                                # dfc<X>_pop        - probability of precipitation (%)
                duration      => get_formatted('%.2f', $results, 'precipitation', 'duration', 'hours'),                                           #                   - duration of precipitation
                rain_mm_low   => get_formatted('%.2f', $results, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_begin'),  #                   - precipitation (mm) from
                rain_mm_high  => get_formatted('%.2f', $results, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end'),    # dfc<X>_prec       - precipitation (mm) up to
                type          => get_value($results, 'precipitation', 'type'),                                                                    #                   - precipitation type
                snow_cm_low   => get_formatted('%.2f', $results, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_begin'),      #                   - snow height (cm) from
                snow_cm_high  => get_formatted('%.2f', $results, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end'),        # dfc<X>_snow       - snow height (cm) up to
            },
            weather_codes => {
                loxone        => $loxone_code,                                               # dfc<X>_we_code   - Loxone code
                weather4lox   => $w4l_code,                                                  # dfc<X>_we_icon   - Weather4Lox icon code
                description   => $description,                                               # dfc<X>_we_des    - description
                image         => get_value($results, 'weather_condition_image'),             #                  - future use., e.g. as background image
                metar         => get_metar_code($w4l_code),                                  #                  - METAR code
            },
            moon => {
                age        => get_formatted('%.2f', $results, 'moon', 'age'),                    # dfc<X>_moon_a    - moon age in days
                rise       => get_time_formatted('%H:%M', $timezone, $results, 'moon', 'rise'),  #                  - moon rise in ISO time
                set        => get_time_formatted('%H:%M', $timezone, $results, 'moon', 'set'),   #                  - moon set in ISO time
                percent    => sprintf("%.2f", $moonillum*100) + 0,                               # dfc<X>_moon_p.   - moon percent
                phase      => sprintf("%.2f", $moonphase*100) + 0,                               # dfc<X>_moon_ph.  - moon phase
            },
            humidity       => {
                avg        =>  get_percentage('%.2f', $results, 'humidity'),                     # dfc<X>_hu_a      - average humidity
                min        =>  $humidity_min,	                                                 # dfc0_hu_l        - minimum humidity
                max        =>  $humidity_max,                                                    # dfc<X>_hu_h.     - maximum humidity
            },
            pressure         => get_formatted('%.0f', $results, 'air_pressure', 'hpa'),          # dfc<X>_pr        - air pressure (hPa)
            dewpoint         => $dewpoint_avg,                                                   # dfc<X>_dp        - average dew point (°C)
            uv_index         => get_formatted('%.1f', $results, 'uv_index', 'value'),            # dfc<X>_uvi       - UV index
            sunrise          => get_time_formatted('%H:%M', $timezone, $results, 'sun', 'rise'), # dfc<X>_sun_r     - sunrise time (HH:MM)
            sunset           => get_time_formatted('%H:%M', $timezone, $results, 'sun', 'set'),  # dfc<X>_sun_s     - sunset time (HH:MM)
            visibility       => undef,                                                           # dfc<X>_vis       - visibility (m/km as needed)
            solar_radiation  => undef,                                                           # dfc<X>_sr        - solar radiation (not present)
            heat_index       => undef,                                                           # dfc<X>_hi        - heat index (not present)
            ozone            => undef,                                                           # dfc<X>_ozone     - ozone (not present)
            cloud_cover      => skycondition_from_wocode($symbol),                               # dfc<X>_sky       - cloud/sky cover (percentage from 0 to 100)
        };
        $i++;
    }
 
    # Build envelope and write JSON to file
    $weather_key = "dailyforecast";
    my $envelope = { 
        location => $location,
        $grabber_key => {
            filename        => "$lbplogdir/$weather_key.json",
            generated_at    => $dt_current->iso8601(),
            grabber_label   => $grabber_label,
            grabber_script  => $grabber_file,
            schema_version  => "v1.0",
        },
        $weather_key => \@daily_data, 
    };
    write_json_file($lbplogdir, $weather_key, $envelope);

} # End daily

##########################################################################
# Fetch hourly data
##########################################################################

if ( $hourly ) {

    my @hourly_data;
    my $dt_result;
    my $results;
    my $i = 1;

    LOGINF "Reading hourly weather data from API response into W4L structure at $dt_current.";

    # it is assumed, that the elements are ordered by time (ascending)
    for my $results (@{$resHourly->{hours}}) {

        # values with additional calculations needs to be done before hash is assigned

        # time
        $dt_result = DateTime::Format::ISO8601->parse_datetime(get_value($results, 'date'));   # ISO date from API in UTC, e.g. 2026-03-13T23:00:00+00:00
        $dt_result->set_time_zone($timezone);

        # my @label_month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
        # my $monthname  = $label_month[$dt_result->month - 1];
        # my @label_month_sh = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
        # my $monthshort = $label_month_sh[$dt_result->month - 1];
        # my @label_days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
        # my $wdayname   = $label_days[$dt_result->day_of_week % 7];
        # my @label_days_sh = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
        # my $wdayshort  = $label_days_sh[$dt_result->day_of_week % 7];

        # wind
        my $wind_dir     = get_formatted('%.0f', $results, 'wind', 'direction'); 

        # Mapping: Wetteronline Symbol => [Loxone code, Weather4Lox code, description]
        my ($loxone_code, $w4l_code, $description);
        my $symbol = get_value($results, 'symbol');
        if (!defined $symbol) {
            LOGWARN "Wetteronline symbol for hourly weather is undefined!";
            ($loxone_code, $w4l_code, $description) = (5, 'no_data', 'Keine Beschreibung zu Wettersymbol');
        } else {
            ($loxone_code, $w4l_code, $description) = wetteronline_to_lox($symbol);
        }

        # astro data - get moon infos for specific time of data set (translated to epoch time)
        my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = phase($dt_result->epoch);

        # Get sunrise and sunset time from daily data, needed for is_nighttime calculation
        my $is_nighttime = undef; # default to day (undef)
        for my $dailyresults (@{$resDaily}) {
            if (substr(get_value($dailyresults, 'date'), 0, 10) eq substr(get_value($results, 'date'), 0, 10)) {
                # we found the matching daily data for the current hourly data, now we can check the dayparts for precipitation type

                if ($dt_result->strftime('%H:%M') lt get_time_formatted('%H:%M', $timezone, $dailyresults, 'sun', 'rise') || 
                    $dt_result->strftime('%H:%M') gt get_time_formatted('%H:%M', $timezone, $dailyresults, 'sun', 'set')) {
                    $is_nighttime = 1;
                    last; # break loop if we found the matching day and determined it is nighttime
                }
            }
        }

        push @hourly_data, {

            hour           => $i,                                                # hfc<X>_per, counter of day
            time => {
                # date       => get_value($results, 'date'),                       # original timestamp from API
                datetime   => _epoch_to_iso($dt_result->epoch, $timezone),       # ISO 8601 date string in local time (e.g. "2026-03-13T02:00:00+01:00")
                epoch      => $dt_result->epoch,                                 # hfc<X>_date       - UNIX timestamp
                # wdayname   => $wdayname,                                       # name of day of week, e.g. Saturday  - TODO: verify if useful, client may calculate name as well
                # wdayshort  => $wdayshort,                                      # short name of day of week, e.g. Sa (two chars)
                # monthname  => $monthname,                                      # name of month, e.g. March
                # monthshort => $monthshort,                                     # name of month, e.g. Mar (three chars
            },
            temperature => {
                air             => get_formatted('%.1f', $results, 'temperature', 'air'),         # hfc<X>_tt        - hourly max temperature (°C)
                feels_like      => get_formatted('%.1f', $results, 'temperature', 'apparent'),    # hfc<X>_tt_fl     - min feels-like temperature
                heat_index      => undef,                                                         # hfc<X>_hi        - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures
                wind_chill      => undef,                                                         # hfc<X>_w_ch      - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
            },
            wind => {
                direction       => $wind_dir,                                                                                  # hfc<X>_w_dir     - wind direction (degree)
                dir_label       => get_wind_direction_label($wind_dir, \%L),                                                   # hfc<X>_w_dirdes  - wind direction description
                speed           => get_formatted('%.2f', $results, 'wind', 'speed', 'kilometer_per_hour', 'value'),            # hfc<X>_w_sp      - wind speed (km/h)
                gust            => get_formatted('%.2f', $results, 'wind', 'speed', 'kilometer_per_hour', 'max_gust'),         # hfc<X>_w_gu      - wind gust (km/h)
            },
            precipitation => {
                probability   => get_percentage('%.2f', $results, 'precipitation', 'probability'),                                                # hfc<X>_pop         - probability of precipitation (%)
                duration      => get_value($results, 'precipitation', 'duration', 'hours'),                                                       #                    - duration of precipitation
                rain_mm_low   => get_formatted('%.2f', $results, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_begin'),  #                    - precipitation (mm) from
                rain_mm_high  => get_formatted('%.2f', $results, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end'),    # hfc<X>_prec        - precipitation (mm) up to
                type          => get_value($results, 'precipitation', 'type'),                                                                    #                    - precipitation type
                snow_cm_low   => get_formatted('%.2f', $results, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_begin'),      #                    - snow height (cm) from
                snow_cm_high  => get_formatted('%.2f', $results, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end'),        # hfc<X>_snow        - snow height (cm) up to
            },
            weather_codes => {
                loxone        => $loxone_code,                                               # hfc<X>_we_code   - Loxone code
                weather4lox   => $w4l_code,                                                  # hfc<X>_we_icon   - Weather4Lox icon code
                description   => $description,                                               # hfc<X>_we_des    - description
                metar         => get_metar_code($w4l_code),                                  #                  - METAR code
            },
            moon => {
                age        => sprintf("%.2f", $moonage),                                     # hfc<X>_moon_a    - moon age in days
                percent    => sprintf("%.2f", $moonillum*100),                               # hfc<X>_moon_p    - moon percentage
                phase      => sprintf("%.2f", $moonphase*100),                               # hfc<X>_moon_ph   - moon phase
            },
            humidity         => get_percentage('%.2f', $results, 'humidity'),                # hfc<X>_hu        - humidity
            pressure         => get_formatted('%.0f', $results, 'air_pressure', 'hpa'),      # hfc<X>_pr        - air pressure (hPa)
            dewpoint         => get_formatted('%.1f', $results, 'dew_point', 'celsius'),     # hfc<X>_dp        - dew point (°C)
            uv_index         => get_formatted('%.1f', $results, 'uv_index', 'value'),        # hfc<X>_uvi       - UV index
            visibility       => get_percentage('%.0f', $results, 'visibility'),              # hfc<X>_vis       - visibility (m/km as needed)
            solar_radiation  => undef,                                                       # hfc<X>_sr        - solar radiation (not present)
            ozone            => undef,                                                       # hfc<X>_ozone     - ozone (not present)
            cloud_cover      => skycondition_from_wocode($symbol),                           # hfc<X>_sky       - cloud/sky cover (percentage from 0 to 100)
            is_nighttime     => $is_nighttime,                                               # get nighttime information from sunrise / sunset, alternate solution woudl be from symbol code
        };
        $i++;
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
       %prec_mm,            # precipitation (rain in mm)
       %snow_cm,            # precipitation (snow in cm)
       %pop_pct,            # precipitation (propability, percentage)
    );
    my (%symbol,            # symbol - do not interpolate
        %c_img,             # weather image - do not interpolate
        %prec_type,         # precipitation type
    );
    my @dp_epochs;
	
    # Collect support points for all days, each with 4 dayparts
	for my $dailyResults (@{$resDaily}) {
		my @dayparts = @{$dailyResults->{dayparts}};

		for my $daypart (@dayparts) {
			# Convert daypart timestamp to epoch seconds
			my $ep = DateTime::Format::ISO8601->parse_datetime(get_value($daypart, 'date'))->epoch;   # ISO date from API is in UTC, e.g. 2026-03-13T23:00:00+00:00

			push @dp_epochs, $ep;

			# Temperatures
			$t_air{$ep} = get_formatted('%.1f', $daypart, 'temperature', 'air');
			$t_app{$ep} = get_formatted('%.1f', $daypart, 'temperature', 'apparent');

			# Humidity (0..1) -> store as percent (0..100) and interpolate in that domain
			$hum{$ep} = get_percentage('%.2f', $daypart, 'humidity');

			# Wind direction (deg) and speed (km/h)
			$w_dir{$ep}    = get_formatted('%.0f', $daypart, 'wind', 'direction');
			$w_sp_kmh{$ep} = get_formatted('%.2f', $daypart, 'wind', 'speed', 'kilometer_per_hour', 'value');
			$w_gu_kmh{$ep} = get_formatted('%.2f', $daypart, 'wind', 'speed', 'kilometer_per_hour', 'max_gust');

			# Pressure / dew point
			$pr_hpa{$ep} = get_formatted('%.0f', $daypart, 'air_pressure', 'hpa');
			$dp_c{$ep}   = get_formatted('%.1f', $daypart, 'dew_point', 'celsius');

			# Rain amount: mean of interval begin/end (if present)
			if ($daypart->{precipitation}{details}{rainfall_amount}{millimeter}) {
				my $rf = (get_formatted('%.2f', $daypart, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_begin') +
						  get_formatted('%.2f', $daypart, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end')) / 2;
				$prec_mm{$ep} = $rf;
			} else {
				$prec_mm{$ep} = 0;                
            }

			# Snow height (cm)
			if ($daypart->{precipitation}{details}{snow_height}{centimeter}) {
				$snow_cm{$ep} = (get_formatted('%.2f', $daypart, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_begin') +
						         get_formatted('%.2f', $daypart, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end')) / 2;
			}  else {
                $snow_cm{$ep} = 0;
            }

			# precipitation duration in minutes.  TODO: verify if daypart include duration and units
			$prec_dur{$ep} = get_formatted('%.2f', $daypart, 'precipitation', 'duration', 'minutes') // 0;

			# precipitation probability (0..1) -> percent (0..100)
			$pop_pct{$ep} = get_percentage('%.2f', $daypart, 'precipitation', 'probability') // 0;

            # uv index
            $uvidx{$ep} = get_formatted('%.1f', $daypart, 'uv_index', 'value') // 0;

			# Symbol is categorical data -> keep as step/hold value
			$symbol{$ep} = get_value($daypart, 'symbol');
			$c_img{$ep} = get_value($daypart, 'weather_condition_image');
		}
	}

	# 2. Step: Sort and de-duplicate epochs
    my $skip_interpolation = 0;

	@dp_epochs = sort { $a <=> $b } @dp_epochs;
	{
		my %seen;
		@dp_epochs = grep { !$seen{$_}++ } @dp_epochs;
	}
    if (!@dp_epochs) {
        LOGWARN "No dayparts to interpolate. Errors are likely, e.g. the Loxone weather emulator may show a black screen";
        $skip_interpolation = 1;
    }

    if (scalar(@dp_epochs) < 2) {
        LOGWARN("Not enough time points for interpolation: " . scalar(@dp_epochs));
        $skip_interpolation = 1;
    }

    for my $hashref (\%t_air, \%t_app, \%hum, \%w_dir, \%w_sp_kmh, \%pr_hpa, \%dp_c, \%prec_mm, \%snow_cm, \%pop_pct, \%uvidx, \%prec_dur) {
        my @defined_vals = grep { defined $_ } values %$hashref;
        if (scalar(@defined_vals) < 2) {
            LOGWARN("Not enough defined values for interpolator (" . $hashref . ")");
             $skip_interpolation = 1;
        }
    }

	# 3. Step: Create interpolators for all parameters

	# Create interpolators (once)
	my $t_air_i    = Math::Function::Interpolator::Linear->new(points => \%t_air);
	my $t_app_i    = Math::Function::Interpolator::Linear->new(points => \%t_app);
	my $hum_i      = Math::Function::Interpolator::Linear->new(points => \%hum);
	my $w_dir_i    = Math::Function::Interpolator::Linear->new(points => \%w_dir);
	my $w_sp_i     = Math::Function::Interpolator::Linear->new(points => \%w_sp_kmh);
	my $w_gu_i     = Math::Function::Interpolator::Linear->new(points => \%w_gu_kmh);
	my $pr_i       = Math::Function::Interpolator::Linear->new(points => \%pr_hpa);
	my $dp_i       = Math::Function::Interpolator::Linear->new(points => \%dp_c);
	my $uvidx_i    = Math::Function::Interpolator::Linear->new(points => \%uvidx);
	my $prec_i     = Math::Function::Interpolator::Linear->new(points => \%prec_mm);
	my $prec_dur_i = Math::Function::Interpolator::Linear->new(points => \%prec_dur);
	my $snow_i     = Math::Function::Interpolator::Linear->new(points => \%snow_cm);
	my $pop_i      = Math::Function::Interpolator::Linear->new(points => \%pop_pct);

	# 4. Step: Create hourly data for all hours starting from '$dt_result' (time stamp from the last hourly entry) + 1h
    #          up to last available entry in dp_epochs, '$i' still counts the entry

	# Get latest time stamp 
	my $end_epoch_time = $dp_epochs[-1];

	# increase time '$dt_result' by 1 hour for next entry
	$dt_result->add(hours => 1);
	my $epoch_time = $dt_result->epoch;

    # only save 5 days of hourly data to reduce loading times
	while ($epoch_time <= $end_epoch_time && !$skip_interpolation && $i < 121) {

        # values with additional calculations needs to be done before hash is assigned

		# For step/hold fields (symbol -> icon/code/description and wind direction text),
		# select the field from last daypart epoch <= current hourly epoch
		my $step_ep = $dp_epochs[0];
		for my $e (@dp_epochs) {
			last if $e > $epoch_time;
			$step_ep = $e;
		}

        # calculate epoch time from last entry + 1h
		$epoch_time = $dt_result->epoch;

        # Mapping: Wetteronline Symbol => [Loxone code, Weather4Lox code, description]
        my ($loxone_code, $w4l_code, $description);
        my $sym = $symbol{$step_ep};
        if (!defined $sym) {
            LOGWARN "Wetteronline symbol for hourly weather is undefined!";
            ($loxone_code, $w4l_code, $description) = (5, 'no_data', 'Keine Beschreibung zu Wettersymbol');
        } else {
            ($loxone_code, $w4l_code, $description) = wetteronline_to_lox($sym);
        }

        # astro data

        # get moon infos for specific time of data set (translated to epoch time)
        my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = phase($epoch_time);

        # Get sunrise and sunset time from daily data, needed for is_nighttime calculation
        my $is_nighttime = undef; # default to day (undef)
        for my $dailyresults (@{$resDaily}) {
            if (substr(get_value($dailyresults, 'date'), 0, 10) eq $dt_result->strftime('%Y-%m-%d')) {
                # we found the matching daily data for the current hourly data, now we can check the dayparts for precipitation type

                if ($dt_result->strftime('%H:%M') lt get_time_formatted('%H:%M', $timezone, $dailyresults, 'sun', 'rise') || 
                    $dt_result->strftime('%H:%M') gt get_time_formatted('%H:%M', $timezone, $dailyresults, 'sun', 'set')) {
                    $is_nighttime = 1;
                    last; # break loop if we found the matching day and determined it is nighttime
                }
            }
        }

        push @hourly_data, {

            hour           => $i,                                                # hfc<X>_per, counter of day
            time => {
                date       => _epoch_to_iso($epoch_time, 'UTC'),           # original timestamp from API
                datetime   => _epoch_to_iso($epoch_time, $timezone),       # ISO 8601 date string in local time (e.g. "2026-03-13T02:00:00+01:00")
                epoch      => $epoch_time,                                 # hfc<X>_date       - UNIX timestamp
            },
            temperature => {
                air             => sprintf("%.1f", $t_air_i->linear($epoch_time)),         # hfc<X>_tt        - hourly temperature (°C)
                feels_like      => sprintf("%.1f", $t_app_i->linear($epoch_time)),         # hfc<X>_tt_fl     - min feels-like temperature
                heat_index      => undef,                                                  # hfc<X>_hi        - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures
                wind_chill      => undef,                                                  # hfc<X>_w_ch      - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
            },
            wind => {
                direction       => $w_dir{$step_ep},                                       # hfc<X>_w_dir     - wind direction (degree)
                dir_label       => get_wind_direction_label($w_dir{$step_ep}, \%L),        # hfc<X>_w_dirdes  - wind direction description
                speed           => sprintf("%.2f", $w_sp_i->linear($epoch_time)),          # hfc<X>_w_sp      - wind speed (km/h)
                gust            => sprintf("%.2f", $w_gu_i->linear($epoch_time)),          # hfc<X>_w_gu      - wind gust (km/h)
            },
            precipitation => {
                probability   => sprintf("%.0f", $pop_i->linear($epoch_time)),             # hfc<X>_pop         - probability of precipitation (%)
                duration      => sprintf("%.0f", $prec_dur_i->linear($epoch_time)),        #                    - duration of precipitation
                rain_mm_low   => sprintf("%.0f", $prec_i->linear($epoch_time)),            #                    - precipitation (mm) from
                rain_mm_high  => sprintf("%.0f", $prec_i->linear($epoch_time)),            # hfc<X>_prec        - precipitation (mm) up to
                type          => $prec_type{$step_ep},                                     #                    - precipitation type
                snow_cm_low   => sprintf("%.0f", $snow_i->linear($epoch_time)),            #                    - snow height (cm) from
                snow_cm_high  => sprintf("%.0f", $snow_i->linear($epoch_time)),            # hfc<X>_snow        - snow height (cm) up to
            },
            weather_codes => {
                loxone        => $loxone_code,                                             # hfc<X>_we_code   - Loxone code
                weather4lox   => $w4l_code,                                                # hfc<X>_we_icon   - Weather4Lox icon code
                description   => $description,                                             # hfc<X>_we_des    - description
                image         => $c_img{$step_ep},                                         #                  - future use, e.g. as background image
                metar         => get_metar_code($w4l_code),                                #                  - METAR code
            },
            moon => {
                age        => sprintf("%.2f", $moonage),                                   # hfc<X>_moon_a    - moon age in days
                percent    => sprintf("%.2f", $moonillum*100),                             # hfc<X>_moon_p    - moon percentage
                phase      => sprintf("%.2f", $moonphase*100),                             # hfc<X>_moon_ph   - moon phase
            },
            humidity         => sprintf("%.0f", $hum_i->linear($epoch_time)),              # hfc<X>_hu        - humidity
            pressure         => sprintf("%.0f", $pr_i->linear($epoch_time)),               # hfc<X>_pr        - air pressure (hPa)
            dewpoint         => sprintf("%.1f", $dp_i->linear($epoch_time)),               # hfc<X>_dp        - dew point (°C)
            uv_index         => sprintf("%.1f", $uvidx_i->linear($epoch_time)),            # hfc<X>_uvi       - UV index
            visibility       => undef,                                                     # hfc<X>_vis       - visibility (m/km), not available in dayparts!
            solar_radiation  => undef,                                                     # hfc<X>_sr        - solar radiation (not present)
            ozone            => undef,                                                     # hfc<X>_ozone     - ozone (not present)
            cloud_cover      => skycondition_from_wocode($sym),                            # hfc<X>_sky       - cloud/sky cover (percentage from 0 to 100)
            is_nighttime     => $is_nighttime,                                             # get nighttime information from sunrise / sunset
        };
        $dt_result->add(hours => 1);
        $i++;
    }

    # Build envelope and write JSON to file
    $weather_key = "hourlyforecast";
    my $envelope = { 
        location => $location,
        $grabber_key => {
            filename        => "$lbplogdir/$weather_key.json",
            generated_at    => $dt_current->iso8601(),
            grabber_label   => $grabber_label,
            grabber_script  => $grabber_file,
            schema_version  => "v1.0",
        },
        $weather_key => \@hourly_data, 
    };
    write_json_file($lbplogdir, $weather_key, $envelope);

} # end hourly


# Give OK status to client.
LOGOK "Current weather data, daily and hourly forecasts are saved successfully.";

# Exit
exit;

END
{
	LOGEND;
}
