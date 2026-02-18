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
my $dump = '';
GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 },
            'current' => \$current,
            'daily' => \$daily,
            'hourly' => \$hourly,
            'dump' => \$dump,
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
        return $response->decoded_content;
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

# Getting GEO data and decoding to perl format
LOGINF "Fetching GEO data for location $city";
my $urlGEO  = "$urlGEO_raw$city";
my $body = getUrl($urlGEO, $useragent);
my $geodataMatch;
if ($body =~ /WO\.geo = (\{(?:[^{}"]|"(?:[^"\\]|\\.)*"|(?1))*\});/s) {
	$geodataMatch = $1;
} else {
        LOGCRIT("Failed to fetch data for $city. No valid data found in the server response. Check Station name.");
        die "Quit fetching data.";
}
my $decodedGeodata;
$geodataMatch = decode_entities($geodataMatch);
$geodataMatch = encode_utf8($geodataMatch);
$decodedGeodata = $json->decode($geodataMatch);
my $lat = $decodedGeodata->{lat};
my $long = $decodedGeodata->{lon};
my $altitude = $decodedGeodata->{alt};

# Getting current data and decoding to perl format
LOGINF "Fetching current data for location $city";
my $gid = findGid($city, $body);
my $urlCurrent = "$urlCurrent_raw$apikey_current&grid_longitude=$long&grid_latitude=$lat&location_id=$gid&astro_longitude=$long&astro_latitude=$lat&latitude=$lat&longitude=$long&timezone=$timezone&language=de-DE&timeformat=HH:mm&windunit=kmh&system_of_measurement=metric&altitude=$altitude";
my $currentData = getUrl($urlCurrent, $useragent);
my $decodedCurrent;
$currentData = encode_utf8($currentData);
$decodedCurrent = $json->decode($currentData);

if ( $dump ) { # Start dump
	# Dumping Content from Wetteronline ...
	LOGINF "Dumping current data from Wetteronline for location $city to $lbplogdir/wetteronline-current.raw";
	open(F,">$lbplogdir/wetteronline-current.raw") or $error = 1;
	flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbpconfigdir/wetteronline-current.raw";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	print F "Request URL: $urlCurrent\n";	
	print F "Decoded JSON response:\n";
	print F $json->pretty->encode($decodedCurrent);
	print F "\n";
	flock(F,8);
	close(F);
}

# Getting daily data and decoding to perl format
LOGINF "Fetching daily data for location $city";
my $urlDaily = "$urlDaily_raw$apikey&location_id=$gid&timezone=$timezone";
my $dailyData = getUrl($urlDaily, $useragent);
my $decodedDaily;
$dailyData = encode_utf8($dailyData);
$decodedDaily = $json->decode($dailyData);

if ( $dump ) { # Start dump
	# Dumping Content from Wetteronline ...
	LOGINF "Dumping daily data from Wetteronline for location $city to $lbplogdir/wetteronline-daily.raw";
	open(F,">$lbplogdir/wetteronline-daily.raw") or $error = 1;
	flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbpconfigdir/wetteronline-daily.raw";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';

	print F "Request URL: $urlDaily\n";	
	print F "Decoded JSON response:\n";
	print F $json->pretty->encode($decodedDaily);
	print F "\n";
	flock(F,8);
	close(F);
}
# Getting hourly data and decoding to perl format
LOGINF "Fetching hourly data for location $city";
my $urlHourly = "$urlHourly_raw$apikey&location_id=$gid&timezone=$timezone";
my $hourlyData = getUrl($urlHourly, $useragent);
my $decodedHourly;
$hourlyData = encode_utf8($hourlyData);
$decodedHourly = $json->decode($hourlyData);

if ( $dump ) { # Start dump
	# Dumping Content from Wetteronline ...
	LOGINF "Dumping hourly data from Wetteronline for location $city to $lbplogdir/wetteronline-hourly.raw";
	open(F,">$lbplogdir/wetteronline-hourly.raw") or $error = 1;
	flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbpconfigdir/wetteronline-hourly.raw";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';

	print F "Request URL: $urlHourly\n";	
	print F "Decoded JSON response:\n";
	print F $json->pretty->encode($decodedHourly);
	print F "\n";
	flock(F,8);
	close(F);
}

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
# --> Using https://wiki.loxberry.de/plugins/weather4loxone/start#wetter-codes
		

# Position: 1 2 3 4 5 6
# Beispiel: m d s n 1 _

# Position 1-2: Tageszeit + Bewölkung

# Code	Bedeutung
# so	Sonne (Tag, wolkenlos)
# mo	Mond (Nacht, wolkenlos)
# wb	Wolke + Basis (Tag, leicht bewölkt)
# mb	Mond + Basis (Nacht, leicht bewölkt)
# mw	Mond + Wolke (Nacht, bewölkt)
# bd	Bedeckt Day (Tag, stark bewölkt)
# bw	Bewölkt + Wetter (mit Niederschlag)
# wd	Wetter Day (Tag mit Niederschlag)
# md	Mond + Dunkel (Nacht mit Niederschlag)
# ns	Nebel/Schnee
# nm	Nebel Mond (Nacht)
# nb	Nebel

# Position 3-4: Niederschlagsart

# Code	Bedeutung
# __	Kein Niederschlag
# sn	Schnee
# sr	Schneeregen
# s1-s3	Schauer (Intensität 1-3)
# r1-r3	Regen (Intensität 1-3)
# g1-g3	Gewitter (Intensität 1-3)
# gr	Gefrierender Regen
# gs	Graupel/Schnee
# hs	Hagel/Schnee
# ek	Eiskörner
# sg	Schneegestöber

# Position 5-6: Intensität/Variante

# Code	Bedeutung
# __	Keine Angabe/Standard
# 1_	Leicht/Schwach
# 2_	Mittel/Mäßig
# 3_	Stark/Kräftig
# r1-r2	Regen-Variante
# s1-s3	Schnee-Variante

my %wetteronline_to_lox = (
    # Gewitter
    "wbg1__" => ["18", "tstorms", "Gewitter"],
    "mbg1__" => ["18", "tstorms", "Gewitter"],
    "bdg1__" => ["18", "tstorms", "Gewitter"],
    "bwg1__" => ["18", "tstorms", "Gewitter"],
    "wbg2__" => ["18", "tstorms", "Gewitter"],
    "mbg2__" => ["18", "tstorms", "Gewitter"],
    "bdg2__" => ["18", "tstorms", "Gewitter"],
    "bwg2__" => ["18", "tstorms", "Gewitter"],
    "bwg3__" => ["19", "tstorms", "Kräftiges Gewitter"],
    
    # Regen
    "wbs1__" => ["10", "chancerain", "Leichter Regen"],
    "mbs1__" => ["10", "chancerain", "Leichter Regen"],
    "mws1__" => ["10", "chancerain", "Leichter Regen"],
    "bwr1__" => ["10", "chancerain", "Leichter Regen"],
    "wbs2__" => ["11", "rain", "Regen"],
    "mbs2__" => ["11", "rain", "Regen"],
    "mws2__" => ["11", "rain", "Regen"],
    "bwr2__" => ["11", "rain", "Regen"],
    "wbs3__" => ["12", "rain", "Starker Regen"],
    "mbs3__" => ["12", "rain", "Starker Regen"],
    "mws3__" => ["12", "rain", "Starker Regen"],
    "bwr3__" => ["12", "rain", "Starker Regen"],
    
    # Gefrierender Regen
    "bdgr1_" => ["14", "sleet", "Gefrierender Regen"],
    "bdgr2_" => ["14", "sleet", "Gefrierender Regen"],
    "bwgr1_" => ["14", "sleet", "Gefrierender Regen"],
    "bwgr2_" => ["14", "sleet", "Gefrierender Regen"],
    
    # Regenschauer
    "bdr1__" => ["16", "rain", "Leichter Regenschauer"],
    "bws1__" => ["16", "rain", "Leichter Regenschauer"],
    "bdr2__" => ["16", "rain", "Regenschauer"],
    "bws2__" => ["16", "rain", "Regenschauer"],
    "bdr3__" => ["17", "rain", "Starker Regenschauer"],
    "bws3__" => ["17", "rain", "Starker Regenschauer"],

    "wdr1__" => ["16", "rain", "Leichter Regenschauer"],
    "mds1__" => ["16", "rain", "Leichter Regenschauer"],
    "wdr2__" => ["16", "rain", "Regenschauer"],
    "mds2__" => ["16", "rain", "Regenschauer"],
    "wdr3__" => ["17", "rain", "Starker Regenschauer"],
    "mds3__" => ["17", "rain", "Starker Regenschauer"],

    # Schnee
    "bdsn1_" => ["20", "snow", "Leichter Schneefall"],
    "bwsn1_" => ["20", "snow", "Leichter Schneefall"],
    "bdsn2_" => ["21", "snow", "Schneefall"],
    "bwsn2_" => ["21", "snow", "Schneefall"],
    "bdsn3_" => ["22", "snow", "Starker Schneefall"],
    "bwsn3_" => ["22", "snow", "Starker Schneefall"],
    "wdsn1_" => ["20", "snow", "Leichter Schneefall"],
    "mdsn1_" => ["20", "snow", "Leichter Schneefall"],
    "wdsn2_" => ["21", "snow", "Schneefall"],
    "mdsn2_" => ["21", "snow", "Schneefall"],
    "wdsn3_" => ["22", "snow", "Starker Schneefall"],
    "mdsn3_" => ["22", "snow", "Starker Schneefall"],

    # Schneeregen/Graupel
    "bwgs2_" => ["26", "sleet", "Graupel"],
    "bwhs2_" => ["26", "sleet", "Graupel"],
    "bwsnr2" => ["26", "sleet", "Schneeregen"],
    "bwek__" => ["26", "sleet", "Eiskörner"],
    "bwgs1_" => ["28", "sleet", "Leichte Graupel"],
    "bwhs1_" => ["28", "sleet", "Leichte Graupel"],
    "bwsnr1" => ["28", "sleet", "Leichter Schneeregen"],
    
    # Schneeregen (gemischt)
    "wbsrs1" => ["25", "sleet", "Leichter Schneeregen"],
    "mbsrs1" => ["25", "sleet", "Leichter Schneeregen"],
    "bdsr1_" => ["25", "sleet", "Leichter Schneeregen"],
    "bwsrs1" => ["25", "sleet", "Leichter Schneeregen"],
    "wbsrs2" => ["26", "snow", "Schneeregen"],
    "mbsrs2" => ["26", "snow", "Schneeregen"],
    "bdsr2_" => ["26", "snow", "Schneeregen"],
    "bdsr3_" => ["27", "snow", "Starker Schneeregen"],
    "bwsrs2" => ["27", "snow", "Starker Schneeregen"],
    
    # Schneeschauer
    "wbsns1" => ["23", "snow", "Leichter Schneeschauer"],
    "mbsns1" => ["23", "snow", "Leichter Schneeschauer"],
    "bwsns1" => ["23", "snow", "Leichter Schneeschauer"],
    "wbsns2" => ["23", "snow", "Schneeschauer"],
    "mbsns2" => ["23", "snow", "Schneeschauer"],
    "bwsns2" => ["23", "snow", "Schneeschauer"],
    "wbsg__" => ["24", "snow", "Schneegestöber"],
    "mbsg__" => ["24", "snow", "Schneegestöber"],
    "bdsg__" => ["24", "snow", "Schneegestöber"],
    "bwsns3" => ["24", "snow", "Starker Schneeschauer"],
    
    # Nebel/Dunst
    "ns____" => ["5", "hazy", "Hochnebel"],
    "nm____" => ["5", "hazy", "Hochnebel"],
    "nb____" => ["6", "fog", "Nebel"],
    
    # Wolken
    "so____" => ["1", "clear", "Sonnig"],
    "mo____" => ["1", "clear", "Klar"],
    "wb____" => ["2", "mostlysunny", "Heiter"],
    "mb____" => ["2", "mostlysunny", "Heiter"],
    "mw____" => ["3", "mostlycloudy", "Wolkig"],
    "bd____" => ["4", "cloudy", "Stark Bewölkt"],
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

#my %translation_table = (
#	'so____'   => 'sonnig bzw. klar',
#	'mo____'   => 'sonnig bzw. klar',
#	'ns____'   => 'teils neblig',
#	'nm____'   => 'teils neblig',
#	'nb____'   => 'neblig',
#	'wb____'   => 'unterschiedlich bewölkt',
#	'mb____'   => 'unterschiedlich bewölkt',
#	'bd____'   => 'bedeckt',
#	'wbs1__'  => 'unterschiedlich bewölkt und vereinzelt Schauer',
#	'mbs1__'  => 'unterschiedlich bewölkt und vereinzelt Schauer',
#	'wbs2__'  => 'unterschiedlich bewölkt und Schauer',
#	'mbs2__'  => 'unterschiedlich bewölkt und Schauer',
#	'bdr1__'  => 'bedeckt, etwas Regen oder vereinzelt Schauer',
#	'bdr2__'  => 'bedeckt, Regen oder Schauer',
#	'bdr3__'  => 'bedeckt und ergiebiger Regen',
#	'wbsrs1'  => 'unterschiedlich bewölkt und vereinzelt Schneeregenschauer',
#	'mbsrs1'  => 'unterschiedlich bewölkt und vereinzelt Schneeregenschauer',
#	'wbsrs2'  => 'unterschiedlich bewölkt und Schneeregenschauer',
#	'mbsrs2'  => 'unterschiedlich bewölkt und Schneeregenschauer',
#	'bdsr1_'  => 'bedeckt, leichter Schneeregen oder vereinzelt Schneeregenschauer',
#	'bdsr2_'  => 'bedeckt, Schneeregen oder Schneeregenschauer',
#	'bdsr3_'  => 'bedeckt und ergiebiger Schneeregen',
#	'wbsns1'  => 'unterschiedlich bewölkt und vereinzelt Schneeschauer',
#	'mbsns1'  => 'unterschiedlich bewölkt und vereinzelt Schneeschauer',
#	'bdsn1_'  => 'bedeckt, leichter Schneefall oder vereinzelt Schneeschauer',
#	'wbsns2'  => 'unterschiedlich bewölkt und Schneeschauer',
#	'mbsns2'  => 'unterschiedlich bewölkt und Schneeschauer',
#	'bdsn1_'  => 'bedeckt, leichter Schneefall oder Schneeschauer',
#	'bdsn2_'  => 'bedeckt, Schneefall oder Schneeschauer',
#	'bdsn3_'  => 'bedeckt und ergiebiger Schneefall',
#	'wbsg__'  => 'unterschiedlich bewölkt und Schneegewitter',
#	'mbsg__'  => 'unterschiedlich bewölkt und Schneegewitter',
#	'bdsg__'  => 'bedeckt und Schneegewitter',
#	'wbg1__'  => 'unterschiedlich bewölkt, vereinzelt Schauer und Gewitter',
#	'mbg1__'  => 'unterschiedlich bewölkt, vereinzelt Schauer und Gewitter',
#	'bdg1__'  => 'bedeckt, vereinzelt Schauer und Gewitter',
#	'wbg2__'  => 'unterschiedlich bewölkt, Schauer und Gewitter',
#	'mbg2__'  => 'unterschiedlich bewölkt, Schauer und Gewitter',
#	'bdg2__'  => 'bedeckt, Schauer und Gewitter',
#	'bdgr1_'  => 'bedeckt und gefrierender Sprühregen',
#	'bdgr2_'  => 'bedeckt und gefrierender Regen',
#);

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
	my $uvi = -9999;
	if ($body =~ m{<span[^>]+label[^>]*>UV-Index</span>.*?<div[^>]+class="text"[^>]*>\s*([\d]+)}si) {
		$uvi = $1;
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

		# writing rubish till dataset is full
		my $x = 0;
		while ($x < 25) {
			$x++;
			print F "-9999|";
		}
		print F "\n";
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
