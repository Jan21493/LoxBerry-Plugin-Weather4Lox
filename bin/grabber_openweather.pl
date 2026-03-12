#!/usr/bin/perl

# grabber for fetching data from openweathermap.org
# fetches weather data (current and forecast) from openweathermap.org

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
use JSON qw( decode_json );
use File::Copy;
use Getopt::Long;
use Time::Piece;
use Astro::MoonPhase;

require "$lbpbindir/grabber_utils.pl";

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

my $pcfg         = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $url          = $pcfg->param("OPENWEATHER.URL");
my $apikey       = $pcfg->param("OPENWEATHER.APIKEY");
my $lang         = $pcfg->param("OPENWEATHER.LANG");
my $stationid    = "lat=" . $pcfg->param("OPENWEATHER.COORDLAT") . "&lon=" . $pcfg->param("OPENWEATHER.COORDLONG");
my $city         = $pcfg->param("OPENWEATHER.STATION");
my $country      = $pcfg->param("OPENWEATHER.COUNTRY");

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'grabber_openweather',
	logdir => "$lbplogdir",
	#filename => "$lbplogdir/weather4lox.log",
	#append => 1,
);

# Commandline options
my $verbose = '';
my $current = '';
my $daily = '';
my $hourly = '';
my $maskkeys = 1; # optional
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

LOGSTART "Weather4Lox GRABBER_OPENWEATHER process started";
LOGDEB "This is $0 Version $version";

# Mapping table for conversion of OpenWeatherMap weather codes to Loxone weather Picto-Codes and short names for weather symbols
my %owm_to_lox = (
    # OWM => [Picto-Code, Symbol]   # Beschreibung
    200 => [18, "tstorms"],     # thunderstorm with light rain -> Gewitter
    201 => [19, "tstorms"],     # thunderstorm with rain -> kräftiges Gewitter
    202 => [19, "tstorms"],     # thunderstorm with heavy rain -> kräftiges Gewitter
    210 => [18, "tstorms"],     # light thunderstorm -> Gewitter
    211 => [18, "tstorms"],     # thunderstorm -> Gewitter
    212 => [19, "tstorms"],     # heavy thunderstorm -> kräftiges Gewitter
    221 => [19, "tstorms"],     # ragged thunderstorm -> kräftiges Gewitter
    230 => [18, "tstorms"],     # thunderstorm with light drizzle -> Gewitter
    231 => [18, "tstorms"],     # thunderstorm with drizzle -> Gewitter
    232 => [19, "tstorms"],     # thunderstorm with heavy drizzle -> kräftiges Gewitter
    300 => [13, "chancerain"],  # light intensity drizzle -> Nieseln
    301 => [13, "chancerain"],  # drizzle -> Nieseln
    302 => [13, "chancerain"],  # heavy intensity drizzle -> Nieseln
    310 => [10, "chancerain"],  # light intensity drizzle rain -> leichter Regen
    311 => [11, "rain"],        # drizzle rain -> Regen
    312 => [12, "rain"],        # heavy intensity drizzle rain -> starker Regen
    313 => [16, "rain"],        # shower rain and drizzle -> leichter Regenschauer
    314 => [17, "rain"],        # heavy shower rain and drizzle -> kräftiger Regenschauer
    321 => [13, "rain"],        # shower drizzle -> Nieseln
    500 => [10, "chancerain"],  # light rain -> leichter Regen
    501 => [11, "rain"],        # moderate rain -> Regen
    502 => [12, "rain"],        # heavy intensity rain -> starker Regen
    503 => [12, "rain"],        # very heavy rain -> starker Regen
    504 => [12, "rain"],        # extreme rain -> starker Regen
    511 => [15, "sleet"],       # freezing rain -> starker gefrierender Regen
    520 => [16, "rain"],        # light intensity shower rain -> leichter Regenschauer
    521 => [17, "rain"],        # shower rain -> kräftiger Regenschauer
    522 => [17, "rain"],        # heavy intensity shower rain -> kräftiger Regenschauer
    531 => [17, "rain"],        # ragged shower rain -> kräftiger Regenschauer (heftig/unbeständig)
    600 => [20, "snow"],        # light snow -> leichter Schneefall
    601 => [21, "snow"],        # snow -> Schneefall
    602 => [22, "snow"],        # heavy snow -> starker Schneefall
    611 => [26, "sleet"],       # sleet -> Schneeregen
    612 => [28, "sleet"],       # light shower sleet -> leichter Schneeregenschauer
    613 => [29, "sleet"],       # shower sleet -> kräftiger Schneeregenschauer
    615 => [25, "sleet"],       # light rain and snow -> leichter Schneeregen
    616 => [27, "sleet"],       # rain and snow -> starker Schneeregen
    620 => [23, "snow"],        # light shower snow -> leichter Schneeschauer
    621 => [23, "snow"],        # shower snow -> leichter Schneeschauer
    622 => [24, "snow"],        # heavy shower snow -> starker Schneeschauer
    701 => [6,  "fog"],         # mist -> Nebel (leichte Form)
    711 => [6,  "fog"],         # smoke -> Nebel (Sichteinschränkung ähnlich wie Nebel)
    721 => [7,  "hazy"],        # haze -> Hochnebel (trübe Sicht ohne Bodenkontakt)
    731 => [5,  "overcast"],    # sand/dust whirls -> bedeckt (Sichttrübung, meist unter Wolken)
    741 => [6,  "fog"],         # fog -> Nebel (klassischer Bodennebel)
    751 => [5,  "overcast"],    # sand -> bedeckt (starke Trübung der Atmosphäre)
    761 => [5,  "overcast"],    # dust -> bedeckt (Sichtminderung)
    762 => [5,  "overcast"],    # volcanic ash -> bedeckt (extreme Trübung/Verdunkelung)
    771 => [12, "rain"],        # squalls -> starker Regen (meist mit schweren Böen/Niederschlag)
    781 => [19, "tstorms"],     # tornado -> kräftiges Gewitter (höchste Warnstufe/Extremwetter)
    800 => [1,  "clear"],       # clear sky -> wolkenlos
    801 => [2,  "mostlysunny"], # few clouds: 11-25% -> heiter
    802 => [3,  "mostlycloudy"],# scattered clouds: 25-50% -> wolkig
    803 => [4,  "cloudy"],      # broken clouds: 51-84% -> stark bewölkt
    804 => [5,  "overcast"],    # overcast clouds: 85-100% -> bedeckt
);

# Anmerkungen zur Mapping-Tabelle:
# - Drizzle (3xx): Wurde primär als Nieseln (13) gemappt, außer es ist eine Kombination mit Regen (310-312), dann folgt es der Regen-Intensität.
# - Thunderstorm (2xx): Alles mit "heavy" oder "rain" (außer "light rain") wurde als kräftiges Gewitter (19) eingestuft.
# - Besonderheit 27: OWM hat keinen expliziten Code für "starken Schneeregen" (nur Schauer oder normal).
# - Nebel vs. Hochnebel (6 & 7): Mist und Fog sind klassischer Nebel (6). Haze (Dunst) mappt am besten auf Hochnebel (7), da es eine diffuse Trübung beschreibt, die oft nicht direkt am Boden als "Nässe" wahrgenommen wird.
# - Staub, Sand & Asche (711–762): Da diese in der Liste von Loxone nicht vorkommen, ist ID 5 (bedeckt) die sicherste Wahl, da die Lichtdurchlässigkeit massiv reduziert ist, ähnlich einer geschlossenen Wolkendecke.
# - Extreme (771 & 781): Squalls treten fast immer mit massivem Regen auf (12), ein Tornado ist das extremste Wettereignis und passt daher am ehesten in die Kategorie des kräftigen Gewitters (19), da er meist aus solchen Zellen entsteht.


sub owm_to_lox {
    my ($owm_id) = @_;
    my $data = $owm_to_lox{$owm_id} // [1, "clear"];
    
    if (!exists $owm_to_lox{$owm_id}) {
        LOGWARN "Unknown ID from OpenWeatherMap: $owm_id. Please check! Using fallback 'clear'.";
    }
    return @$data; # Returns (Code, Icon)
}

# Get data from openweathermap.org (API request) for current conditions, daily and hourly forecasts via OneCall API
my $decoded_json = api_call(
	url => "$url/3.0/onecall?appid=$apikey&$stationid&lang=$lang&units=metric",
	maskkeys => $maskkeys,
	keyparam => 'appid',
	# apikey => $apikey,	# not needed here as the URL is already masked and the key won't appear elsewhere in the response
	info => "for Location $stationid (Current, Daily, and Hourly Weather Data)",
);

my $t;
my $owmid;
my $code;
my $icon;
my $wdir;
my $wdirdes;
my @filecontent;
my $i;
my $error = 0;

#
# Fetch current data
#

if ( $current ) { # Start current

# Write location data into database
$t = localtime($decoded_json->{current}->{dt});
LOGINF "Saving new Data for Timestamp $t to database.";

# Saving new current data...
my $error = 0;
open(F,">$lbplogdir/current.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbpconfigdir/current.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	print F "$decoded_json->{current}->{dt}|";
	my $date = qx(date -R -d "\@$decoded_json->{current}->{dt}");
	chomp ($date);
	print F "$date|";
	my $tz_short = qx(TZ='$decoded_json->{timezone}' date +%Z);
	chomp ($tz_short);
	print F "$tz_short|";
	print F "$decoded_json->{timezone}|";
	my $tz_offset = qx(TZ="$decoded_json->{timezone}" date +%z);
	chomp ($tz_offset);
	print F "$tz_offset|";
	$city = Encode::decode("UTF-8", $city);
	print F "$city|";
	$country = Encode::decode("UTF-8", $country);
	print F "$country|";
	print F "-9999|";
	print F "$decoded_json->{lat}|";
	print F "$decoded_json->{lon}|";
	print F "-9999|";
	print F sprintf("%.1f",$decoded_json->{current}->{temp}), "|";
	print F sprintf("%.1f",$decoded_json->{current}->{feels_like}), "|";
	print F "$decoded_json->{current}->{humidity}|";
	$wdir = $decoded_json->{current}->{wind_deg};
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
	print F "$decoded_json->{current}->{wind_deg}|";
	print F sprintf("%.1f",$decoded_json->{current}->{wind_speed} * 3.6), "|";
	print F sprintf("%.1f",$decoded_json->{current}->{wind_speed} * 3.6), "|";
	print F sprintf("%.1f",$decoded_json->{current}->{feels_like}), "|";
	print F sprintf("%.0f",$decoded_json->{current}->{pressure}), "|";
	print F "$decoded_json->{current}->{dew_point}|";
	print F sprintf("%.0f",$decoded_json->{current}->{visibility} / 1000), "|";
	print F "-9999|";
	print F "-9999|";
	print F sprintf("%.2f",$decoded_json->{current}->{uvi}),"|";
	print F "-9999|";
	if ( $decoded_json->{current}->{rain}->{'1h'} ) {
		print F sprintf("%.2f",$decoded_json->{current}->{rain}->{'1h'}), "|";
	} else {
		print F "0|";
	}
	# Convert Weather string into Weather Code and normalized icon name
    # Weather conditions: https://openweathermap.org/weather-conditions
	$owmid = $decoded_json->{current}->{weather}->[0]->{id};
	($code, $icon) = owm_to_lox($owmid);
	print F "$icon|";
	print F "$code|";
	print F "$decoded_json->{current}->{weather}->[0]->{description}|";
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
	print F "-9999|";
#	my $moonphase = $decoded_json->{daily}[0]->{moon_phase};
#	my $moonpercent = 0;
#	if ($moonphase le "0.5") {
#		$moonpercent = $moonphase * 2 * 100;
#	} else {
#		$moonpercent = (1 - $moonphase) * 2 * 100;
#	}
#	print F "$moonpercent|";
#	print F "-9999|";
#	print F sprintf("%.0f",$moonphase*100), "|";
	$t = localtime($decoded_json->{current}->{sunrise});
	print F sprintf("%02d", $t->hour), "|";
	print F sprintf("%02d", $t->min), "|";
	$t = localtime($decoded_json->{current}->{sunset});
	print F sprintf("%02d", $t->hour), "|";
	print F sprintf("%02d", $t->min), "|";
	print F "-9999|";
	print F "$decoded_json->{current}->{clouds}|";
	if ($decoded_json->{hourly}->[0]->{pop}) {
                print F sprintf("%.0f",$decoded_json->{hourly}->[0]->{pop} * 100), "|";
        } else {
                print F "0|";
        }
	if ($decoded_json->{current}->{snow}->{'1h'}) {
		print F sprintf("%.2f",$decoded_json->{current}->{snow}->{'1h'} / 10), "|";
	} else {
		print F "0|";
	}
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
	for my $results( @{$decoded_json->{daily}} ){
		print F "$i|";
		$i++;
		print F $results->{dt}, "|";

		$t = localtime($results->{dt});
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
		print F sprintf("%.1f",$results->{temp}->{max}), "|";
		print F sprintf("%.1f",$results->{temp}->{min}), "|";
		if ($results->{pop}) {
                        print F sprintf("%.0f",$results->{pop} * 100), "|";
                } else {
                        print F "0|";
                }
		if ($results->{rain}) {
			print F sprintf("%.2f",$results->{rain}), "|";
		} else {
			print F "0|";
		}
		if ($results->{snow}) {
			print F sprintf("%.2f",$results->{snow} / 10), "|";
		} else {
			print F "0|";
		}
		print F "-9999|";
		print F "-9999|";
		print F "-9999|";
		print F sprintf("%.1f",$results->{wind_speed} * 3.6), "|";
		$wdir = $results->{wind_deg};
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
		print F "$results->{wind_deg}|";
		print F "$results->{humidity}|";
		print F "-9999|";
		print F "-9999|";
		# Convert Weather string into Weather Code and normalized icon name
		$owmid = $results->{weather}->[0]->{id};
		($code, $icon) = owm_to_lox($owmid);	
		print F "$icon|";
		print F "$code|";
		print F "$results->{weather}->[0]->{description}|";
		print F "-9999|";
		my ( $moonphase,
		  $moonillum,
		  $moonage,
		  $moondist,
		  $moonang,
		  $sundist,
		  $sunang ) = phase($results->{dt});
		print F sprintf("%.2f",$moonillum*100), "|";
		print F sprintf("%.1f",$results->{dew_point}), "|";
		print F sprintf("%.0f",$results->{pressure}), "|";
		print F sprintf("%.1f",$results->{uvi}),"|";
		$t = localtime($results->{sunrise});
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		$t = localtime($results->{sunset});
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		print F "-9999|";
		print F sprintf("%.2f",$moonage), "|";
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
open(F,">$lbplogdir/hourlyforecast.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/hourlyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	$i = 1;
	my $n = 0;
	for my $results( @{$decoded_json->{hourly}} ){
		# Skip first dataset (eq to current) - keep the first dataset (it's the forecast for the current hour and used as "now" in the Emulator)
		#if ($n eq "0") {
		#	$n++;
		#	next;
		#}
		print F "$i|";
		$i++;
		print F $results->{dt}, "|";
		$t = localtime($results->{dt});
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
		print F sprintf("%.1f",$results->{temp}), "|";
		print F sprintf("%.1f",$results->{feels_like}), "|";
		print F "-9999|";
		print F "$results->{humidity}|";
		$wdir = $results->{wind_deg};
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
		print F "$results->{wind_deg}|";
		print F sprintf("%.1f",$results->{wind_speed} * 3.6), "|";
		print F sprintf("%.1f",$results->{feels_like}), "|";
		print F sprintf("%.0f",$results->{pressure}), "|";
		print F sprintf("%.1f",$results->{dew_point}), "|";
		print F "$results->{clouds}|";
		print F "-9999|";
		print F "-9999|";
		if ($results->{rain}->{'1h'}) {
			print F sprintf("%.2f",$results->{rain}->{'1h'}), "|";
		} else {
			print F "0|";
		}
		if ($results->{snow}->{'1h'}) {
			print F sprintf("%.2f",$results->{snow}->{'1h'}), "|";
		} else {
			print F "0|";
		}
		if ($results->{pop}) {
                        print F sprintf("%.0f",$results->{pop} * 100), "|";
                } else {
                        print F "0|";
                }
		# Convert Weather string into Weather Code and normalized icon name
		$owmid = $results->{weather}->[0]->{id};
		($code, $icon) = owm_to_lox($owmid);	
		print F "$icon|";
		print F "$code|";
		print F "$results->{weather}->[0]->{description}|";
		print F "-9999|";
		print F "-9999|";
		print F "-9999|";
		my ( $moonphase,
		  $moonillum,
		  $moonage,
		  $moondist,
		  $moonang,
		  $sundist,
		  $sunang ) = phase($results->{dt});
		print F sprintf("%.2f",$moonillum*100), "|";
		print F sprintf("%.2f",$moonage), "|";
		print F sprintf("%.2f",$moonphase*100), "|";
		print F "\n";
	}
  flock(F,8);
close(F);

# OpenWeatherMap only offers 48h in the free account. Interpolate with 3-hours data to have more entries for the weather emulator
if ($i < 168) {

	LOGINF "Fetching additional 3-Hourly Forecat Data to interpolite hourly data (only 48h of hourly data available via OneCall API).";

	# Get data from openweathermap.org (API request) for 3-hourly forecasts via free 5 day / 3 hour forecast data
	$decoded_json = api_call(
		url => "$url/2.5/forecast?appid=$apikey&$stationid&lang=$lang&units=metric&cnt=40",
		maskkeys => $maskkeys,
		keyparam => 'appid',
		# apikey => $apikey,	# not needed here as the URL is already masked and the key won't appear elsewhere in the response
		info => "for Location $stationid (3-Hourly Weather Forecast Data)",
	);

	$error = 0;
	open(F,"+<$lbplogdir/hourlyforecast.dat.tmp") or $error = 1;;
	  if ($error) {
		LOGCRIT "Cannot open $lbplogdir/hourlyforecast.dat.tmp";
		exit 2;
	  }
	  flock(F,2);
	  binmode F, ':encoding(UTF-8)';

		my @olddata = <F>;
		#  seek(F,0,0);
		#  truncate(F,0);
		# Last entry in hourly database
		my $lastline;
		my $newline;
		foreach (@olddata){
			$lastline = $_;
			#print "Lastline is: $_\n";
		}
		for my $results( @{$decoded_json->{list}} ){
			my @oldfields = split(/\|/,$lastline);
			my $i = $oldfields[0] + 1;
			if ($oldfields[1] >= $results->{dt}) {
				next;
			}

			# Step to last entry (normally 3 hours)
			my $delta = ($results->{dt} - $oldfields[1]) / 3600;

			# Create new interpolated entry
			for (my $step=1; $step <= $delta; $step++) {
				$newline = $i + $step - 1;
				$newline .= "|";
				$newline .= $oldfields[1] + ($step * 3600);
				$newline .= "|";
				$t = localtime($oldfields[1] + ($step * 3600));
				$newline .= sprintf("%02d", $t->mday);
				$newline .= "|";
				$newline .= sprintf("%02d", $t->mon);
				$newline .= "|";
				my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
				$t->mon_list(@month);
				$newline .= $t->monname;
				$newline .= "|";
				@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
				$t->mon_list(@month);
				$newline .=  $t->monname;
				$newline .= "|";
				$newline .= $t->year;
				$newline .= "|";
				$newline .= sprintf("%02d", $t->hour);
				$newline .= "|";
				$newline .= sprintf("%02d", $t->min);
				$newline .= "|";
				my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
				$t->day_list(@days);
				$newline .= $t->wdayname;
				$newline .= "|";
				@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
				$t->day_list(@days);
				$newline .= $t->wdayname;
				$newline .= "|";
				$newline .= sprintf( "%.1f", $oldfields[11] + ( $step * ( ($results->{main}->{temp} - $oldfields[11]) / $delta ) ) );
				$newline .= "|";
				$newline .= sprintf( "%.1f", $oldfields[12] + ( $step * ( ($results->{main}->{feels_like} - $oldfields[12]) / $delta ) ) );
				$newline .= "|";
				$newline .= "-9999|";
				$newline .= sprintf( "%.0f", $oldfields[14] + ( $step * ( ($results->{main}->{humidity} - $oldfields[14]) / $delta ) ) );
				$newline .= "|";
				$wdir = sprintf( "%.0f", $oldfields[16] + ( $step * ( ($results->{wind}->{deg} - $oldfields[16]) / $delta ) ) );
				if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
				if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
				if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
				if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
				if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
				if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
				if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
				if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
				if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
				$newline .= "$wdirdes|";
				$newline .= sprintf( "%.0f", $wdir );
				$newline .= "|";
				$newline .= sprintf( "%.1f", $oldfields[17] + ( $step * ( ( (3.6 * $results->{wind}->{speed}) - $oldfields[17]) / $delta ) ) );
				$newline .= "|";
				$newline .= sprintf( "%.1f", $oldfields[12] + ( $step * ( ($results->{main}->{feels_like} - $oldfields[12]) / $delta ) ) );
				$newline .= "|";
				$newline .= sprintf( "%.0f", $oldfields[19] + ( $step * ( ($results->{main}->{pressure} - $oldfields[19]) / $delta ) ) );
				$newline .= "|";
				$newline .= "-9999|";
				$newline .= sprintf( "%.0f", $oldfields[21] + ( $step * ( ($results->{clouds}->{all} - $oldfields[21]) / $delta ) ) );
				$newline .= "|";
				$newline .= "-9999|";
				$newline .= "-9999|";
				if ($results->{rain}->{'3h'}) {
					$newline .= sprintf( "%.2f", $oldfields[24] + ( $step * ( ($results->{rain}->{'3h'} - $oldfields[24]) / $delta ) ) );
				} else {
					$newline .= "0";
				}
				$newline .= "|";
				if ($results->{snow}->{'3h'}) {
					$newline .= sprintf( "%.2f", $oldfields[25] + ( $step * ( ($results->{snow}->{'3h'} - $oldfields[25]) / $delta ) ) );
				} else {
					$newline .= "0";
				}
				$newline .= "|";
                                if ($results->{pop}) {
                                        $newline .= sprintf( "%.0f", $oldfields[26] + ( $step * ( (100 * $results->{pop} - $oldfields[26]) / $delta ) ) );
                                } else {
                                        $newline .= "0";
                                }
                                $newline .= "|";
				if ($step eq "1") {
					$newline .= $oldfields[27];
					$newline .= "|";
					$newline .= $oldfields[28];
					$newline .= "|";
					$newline .= $oldfields[29];
					$newline .= "|";
				} else {
					# Convert Weather string into Weather Code and normalized icon name
					$owmid = $results->{weather}->[0]->{id};
					($code, $icon) = owm_to_lox($owmid);	
					$newline .= "$icon|";
					$newline .= "$code|";
					$newline .= $results->{weather}->[0]->{description};
					$newline .= "|";
				}
				$newline .= "-9999|";
				$newline .= "-9999|";
				$newline .= "-9999|";
				$newline .= "-9999|";
				$newline .= "-9999|";
				$newline .= "-9999|";
				#$newline .= "Schritt: $step Vor: $oldfields[11] Ziel: $results->{temp} Schrittweite: ";
				#$newline .= ( ($results->{temp} - $oldfields[11]) / $delta );
				#$newline .= "|";
				# Save new data
				print F "$newline\n";
				$lastline = $newline;
			}
		}
	  flock(F,8);
	close (F);
}

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

# Write JSON files from the .dat files
if ($current) {
    eval { write_current_json($lbplogdir, source => "OpenWeatherMap", grabber => "grabber_openweather.pl") };
    LOGWARN "JSON write failed: $@" if $@;
}
if ($daily) {
    eval { write_daily_json($lbplogdir, source => "OpenWeatherMap", grabber => "grabber_openweather.pl") };
    LOGWARN "JSON write failed: $@" if $@;
}
if ($hourly) {
    eval { write_hourly_json($lbplogdir, source => "OpenWeatherMap", grabber => "grabber_openweather.pl") };
    LOGWARN "JSON write failed: $@" if $@;
}

# Give OK status to client.
LOGOK "Current Data and Forecasts saved successfully.";

# Exit
exit;

END
{
	LOGEND;
}
