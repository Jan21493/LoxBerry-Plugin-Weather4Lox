#!/usr/bin/perl

# grabber for fetching data from wttr.in
# fetches weather data (current and forecast) from wttr.in

# Copyright 2016-2024 Michael Schlenstedt, michael@loxberry.de
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
use Math::Function::Interpolator;
use Astro::MoonPhase;
#use Data::Dumper;

require "$lbpbindir/grabber_utils.pl";

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

my $pcfg         = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $url          = $pcfg->param("WTTRIN.URL");
my $lang         = $pcfg->param("WTTRIN.LANG");
my $stationid    = $pcfg->param("WTTRIN.STATIONID");

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'grabber_wttr.in',
	logdir => "$lbplogdir",
	#filename => "$lbplogdir/weather4lox.log",
	#append => 1,
);

# Commandline options
my $verbose = '';
my $current = '';
my $daily = '';
my $hourly = '';
GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 },
            'current' => \$current,
            'daily' => \$daily,
            'hourly' => \$hourly);

if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGSTART "Weather4Lox GRABBER_WTTRIN process started";
LOGDEB "This is $0 Version $version";

# Mapping table for conversion of WTTR.in weather codes to Loxone weather Picto-Codes and short names for weather symbols
# Weather codes are based on https://www.worldweatheronline.com/weather-api/api/docs/weather-icons.aspx
my %wttr_to_lox = (
    113 => [ 1,  'sunny' ],         # description: Clear/Sunny
    116 => [ 2,  'partlycloudy' ],  # description: Partly Cloudy
    119 => [ 3,  'cloudy' ],        # description: Cloudy
    122 => [ 5,  'overcast' ],      # description: Overcast
    143 => [ 6,  'fog' ],           # description: Mist
    176 => [ 11, 'rain' ],          # description: Patchy rain nearby
    179 => [ 23, 'snow' ],          # description: Patchy snow nearby
    182 => [ 26, 'sleet' ],         # description: Patchy sleet nearby
    185 => [ 14, 'sleet' ],         # description: Patchy freezing drizzle nearby
    200 => [ 18, 'tstorms' ],       # description: Thundery outbreaks in nearby
    227 => [ 21, 'snow' ],          # description: Blowing snow
    230 => [ 22, 'snow' ],          # description: Blizzard
    248 => [ 6,  'fog' ],           # description: Fog
    260 => [ 6,  'fog' ],           # description: Freezing fog
    263 => [ 13, 'chancerain' ],    # description: Patchy light drizzle
    266 => [ 13, 'chancerain' ],    # description: Light drizzle
    281 => [ 14, 'sleet' ],         # description: Freezing drizzle
    284 => [ 15, 'sleet' ],         # description: Heavy freezing drizzle
    293 => [ 16, 'chancerain' ],    # description: Patchy light rain
    296 => [ 10, 'rain' ],          # description: Light rain
    299 => [ 11, 'rain' ],          # description: Moderate rain at times
    302 => [ 11, 'rain' ],          # description: Moderate rain
    305 => [ 12, 'rain' ],          # description: Heavy rain at times
    308 => [ 12, 'rain' ],          # description: Heavy rain
    311 => [ 14, 'sleet' ],         # description: Light freezing rain
    314 => [ 15, 'sleet' ],         # description: Moderate or Heavy freezing rain
    317 => [ 25, 'sleet' ],         # description: Light sleet
    320 => [ 26, 'sleet' ],         # description: Moderate or heavy sleet
    323 => [ 23, 'snow' ],          # description: Patchy light snow
    326 => [ 20, 'snow' ],          # description: Light snow
    329 => [ 21, 'snow' ],          # description: Patchy moderate snow
    332 => [ 21, 'snow' ],          # description: Moderate snow
    335 => [ 24, 'snow' ],          # description: Patchy heavy snow
    338 => [ 22, 'snow' ],          # description: Heavy snow
    350 => [ 26, 'sleet' ],         # description: Ice pellets
    353 => [ 16, 'rain' ],          # description: Light rain shower
    356 => [ 17, 'rain' ],          # description: Moderate or heavy rain shower
    359 => [ 17, 'rain' ],          # description: Torrential rain shower
    362 => [ 26, 'sleet' ],         # description: Light sleet showers
    365 => [ 26, 'sleet' ],         # description: Moderate or heavy sleet showers
    368 => [ 23, 'snow' ],          # description: Light snow showers
    371 => [ 24, 'snow' ],          # description: Moderate or heavy snow showers
    374 => [ 28, 'sleet' ],         # description: Light showers of ice pellets
    377 => [ 29, 'sleet' ],         # description: Moderate or heavy showers of ice pellets
    386 => [ 18, 'tstorms' ],       # description: Patchy light rain in area with thunder
    389 => [ 19, 'tstorms' ],       # description: Moderate or heavy rain in area with thunder
    392 => [ 18, 'snow' ],          # description: Patchy light snow in area with thunder
    395 => [ 19, 'snow' ],          # description: Moderate or heavy snow in area with thunder
);

sub wttr_to_lox {
    my ($wwo_id) = @_;

    # wttr liefert weatherCode oft als String -> numerisch normalisieren
    $wwo_id = int($wwo_id);

    my $data = $wttr_to_lox{$wwo_id} // [1, "clear"];
    
    if (!exists $wttr_to_lox{$wwo_id}) {
        LOGWARN "Unknown ID from WTTR.in: $wwo_id. Please check! Using fallback 'clear'.";
    }
    return @$data; # Returns (Code, Icon)
}

# Get weather data from WTTR.in (API request)
my $decoded_json = api_call(
	url => "$url/$stationid?lang=$lang&M&3&format=j1",
	# maskkeys => $maskkeys, # not needed here
	# keyparam => 'appid',
	# apikey => $apikey,
	info => "for Location $stationid (Current, Daily, and Hourly Weather Data)",
);

my $t;
my $weather;
my $code;
my $icon;
my $wdir;
my $wdirdes;
my @filecontent;
my $i;
my $wwo_id;
my $error = 0;

#
# Fetch current data
#

if ( $current ) { # Start current

# Write location data into database
my $t = Time::Piece->strptime($decoded_json->{current_condition}[0]->{localObsDateTime}, "%Y-%m-%d %R %p");
LOGINF "Saving new Data for Timestamp $t to database.";
# Saving new current data...
$error = 0;
open(F,">$lbplogdir/current.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbpconfigdir/current.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	print F $t->epoch . "|";
	print F "$t|";
	my $tz_short = qx(date +%Z);
	chomp ($tz_short);
	print F "$tz_short|";
	my $tz_long = qx(cat /etc/timezone);
	chomp ($tz_long);
	print F "$tz_long|";
	my $tz_offset = qx(date +%z);
	chomp ($tz_offset);
	print F "$tz_offset|";
	my $city = Encode::decode("UTF-8", $decoded_json->{nearest_area}[0]->{areaName}[0]->{value});
	print F "$city|";
	my $country = Encode::decode("UTF-8", $decoded_json->{nearest_area}[0]->{country}[0]->{value});
	print F "$country|";
	print F "-9999|";
	print F "$decoded_json->{nearest_area}[0]->{latitude}|";
	print F "$decoded_json->{nearest_area}[0]->{longitude}|";
	print F "-9999|";
	print F sprintf("%.1f",$decoded_json->{current_condition}[0]->{temp_C}), "|";
	print F sprintf("%.1f",$decoded_json->{current_condition}[0]->{FeelsLikeC}), "|";
	print F "$decoded_json->{current_condition}[0]->{humidity}|";
	$wdir = $decoded_json->{current_condition}[0]->{winddirDegree};
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
	print F "$decoded_json->{current_condition}[0]->{winddirDegree}|";
	print F sprintf("%.1f",$decoded_json->{current_condition}[0]->{windspeedKmph}), "|";
	print F sprintf("%.1f",$decoded_json->{current_condition}[0]->{windspeedKmph}), "|";
	print F sprintf("%.1f",$decoded_json->{current_condition}[0]->{FeelsLikeC}), "|";
	print F sprintf("%.0f",$decoded_json->{current_condition}[0]->{pressure}), "|";
	print F "-9999|";
	print F sprintf("%.0f",$decoded_json->{current_condition}[0]->{visibility}), "|";
	print F "-9999|";
	print F "-9999|";
	print F sprintf("%.2f",$decoded_json->{current_condition}[0]->{uvIndex}),"|";
	print F "-9999|";
	print F sprintf("%.2f",$decoded_json->{current_condition}[0]->{precipMM}), "|";
	# Convert WTTR weather code into Loxone Weather Code (picto-code) and weather symbol name
	my $wwo_id = $decoded_json->{current_condition}[0]->{weatherCode};
	($code, $icon) = wttr_to_lox($wwo_id);
	print F "$icon|";
	print F "$code|";
	my $wdes = $decoded_json->{current_condition}[0]->{'lang_' . $lang}[0]{value};
	$wdes = $decoded_json->{current_condition}[0]->{weatherDesc}[0]{value} if !$wdes;
	print F "$wdes|";
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
#	print F "$decoded_json->{weather}[0]->{astronomy}[0]{moon_illumination}|";
#	print F "-9999|";
#	my $moonphasen;
#	my $moonphase = lc( $decoded_json->{weather}[0]->{astronomy}[0]{moon_phase} );
#	if ( $moonphase eq "new moon" ) {
#		$moonphasen = 0;
#	} elsif ( $moonphase eq "waxing crescent" ) {
#		$moonphasen = 0.125;
#	} elsif ( $moonphase eq "first quarter" ) {
#		$moonphasen = 0.25;
#	} elsif ( $moonphase eq "waxing gibbous" ) {
#		$moonphasen = 0.375;
#	} elsif ( $moonphase eq "full moon" ) {
#		$moonphasen = 0.5;
#	} elsif ( $moonphase eq "waning gibbous" ) {
#		$moonphasen = 0.625;
#	} elsif ( $moonphase eq "last quarter" ) {
#		$moonphasen = 0.75;
#	} elsif ( $moonphase eq "waning crescent" ) {
#		$moonphasen = 0.875;
#	} else {
#		$moonphasen = 1;
#	}
#	print F sprintf("%.0f",$moonphasen*100), "|";
#	print F "-9999|";
	$t = Time::Piece->strptime($decoded_json->{weather}[0]->{astronomy}[0]{sunrise}, "%R %p");
	print F sprintf("%02d", $t->hour), "|";
	print F sprintf("%02d", $t->min), "|";
	$t = Time::Piece->strptime($decoded_json->{weather}[0]->{astronomy}[0]{sunset}, "%R %p");
	print F sprintf("%02d", $t->hour), "|";
	print F sprintf("%02d", $t->min), "|";
	print F "-9999|";
	print F "$decoded_json->{current_condition}[0]->{cloudcover}|";
	print F "-9999|";
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
	for my $results( @{$decoded_json->{weather}} ){
		print F "$i|";
		$i++;
		$t = Time::Piece->strptime($results->{date}, "%Y-%m-%d");
		print F $t->epoch, "|";
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
		print F sprintf("%.1f",$results->{maxtempC}), "|";
		print F sprintf("%.1f",$results->{mintempC}), "|";
		# Figure out min/max/sum values for daily forecast from hourly values
		my @pops;
		my $prec = 0;
		my @gusts;
		my @winds;
		my @winddirs;
		my @hums;
		my @pressures;
		my @dewps;
		my @visibilitys;
		for my $hourly ( @{$results->{hourly}} ){
			if ( $hourly->{chanceofrain} ) {
				push ( @pops, $hourly->{chanceofrain} );
			}
			if ( $hourly->{precipMM} ) {
				$prec += $hourly->{precipMM} * 3; # 3 hourly FC
			}
			if ( $hourly->{WindGustKmph} ) {
				push ( @gusts, $hourly->{WindGustKmph} );
			}
			if ( $hourly->{windspeedKmph} ) {
				push ( @winds, $hourly->{windspeedKmph} );
			}
			if ( $hourly->{winddirDegree} ) {
				push ( @winddirs, $hourly->{winddirDegree} );
			}
			if ( $hourly->{humidity} ) {
				push ( @hums, $hourly->{humidity} );
			}
			if ( $hourly->{pressure} ) {
				push ( @pressures, $hourly->{pressure} );
			}
			if ( $hourly->{DewPointC} ) {
				push ( @dewps, $hourly->{DewPointC} );
			}
			if ( $hourly->{visibility} ) {
				push ( @visibilitys, $hourly->{visibility} );
			}
		}
		@pops = sort { $a <=> $b } @pops;
		@gusts = sort { $a <=> $b } @gusts;
		@winds = sort { $a <=> $b } @winds;
		@winddirs = sort { $a <=> $b } @winddirs;
		@hums = sort { $a <=> $b } @hums;
		@pressures = sort { $a <=> $b } @pressures;
		@dewps = sort { $a <=> $b } @dewps;
		@visibilitys = sort { $a <=> $b } @visibilitys;
		if ($pops[-1]) { # Max from sorted array
			print F sprintf("%.0f",$pops[-1]), "|";
		} else {
			print F "0|";
		}
		if ($prec) {
			print F sprintf("%.2f",$prec), "|";
		} else {
			print F "0|";
		}
		print F sprintf("%.1f",$results->{totalSnow_cm}), "|";
		if ($gusts[-1]) { # Max from sorted array
			print F sprintf("%.0f",$gusts[-1]), "|";
		} else {
			print F "0|";
		}
		print F "-9999|";
		print F "-9999|";
		my $windavg = eval(join("+", @winds)) / @winds; # Mean from array
		if ($windavg) {
			print F sprintf("%.0f",$windavg), "|";
		} else {
			print F "0|";
		}
		my $wdir = 0;
		$wdir = eval(join("+", @winddirs)) / @winddirs; # Mean from array
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
		print F "$wdir|";
		my $humidity = eval(join("+", @hums)) / @hums; # Mean from array
		print F sprintf("%.0f",$humidity), "|";
		if ($hums[-1]) { # Max from sorted array
			print F sprintf("%.0f",$hums[-1]), "|";
		} else {
			print F "0|";
		}
		if ($hums[0]) { # Min from sorted array
			print F sprintf("%.0f",$hums[0]), "|";
		} else {
			print F "0|";
		}
        # Convert WTTR weather code into Loxone Weather Code (picto-code) and weather symbol name
        #  We do not have an average, so we take value from 12 o'clock
	    $wwo_id = $results->{hourly}[4]->{weatherCode};
	    ($code, $icon) = wttr_to_lox($wwo_id);
		print F "$icon|";
		print F "$code|";
		my $wdes = "";
		$wdes = $results->{hourly}[4]->{'lang_' . $lang}[0]{value};
		$wdes = $results->{hourly}[4]->{weatherDesc}[0]{value} if !$wdes;
		print F "$wdes|";
		print F "-9999|";
		# dfc0_moon_p
		my ( $moonphase,
		  $moonillum,
		  $moonage,
		  $moondist,
		  $moonang,
		  $sundist,
		  $sunang ) = phase($t->epoch);
		print F sprintf("%.2f",$moonillum*100), "|";
		my $dewp = eval(join("+", @dewps)) / @dewps; # Mean from array
		print F sprintf("%.1f",$dewp), "|";
		my $pressure = eval(join("+", @pressures)) / @pressures; # Mean from array
		print F sprintf("%.1f",$pressure), "|";
		print F sprintf("%.1f",$results->{uvIndex}),"|";
		$t = Time::Piece->strptime($results->{astronomy}[0]{sunrise}, "%R %p");
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		$t = Time::Piece->strptime($results->{astronomy}[0]{sunset}, "%R %p");
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		my $vis = eval(join("+", @visibilitys)) / @visibilitys; # Mean from array
		print F sprintf("%.1f",$vis), "|";
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

# Parse data for hourly data
my %temps;
my $temps;
my %fltemps;
my $fltemps;
my %hums;
my $hums;
my %winddirs;
my $winddirs;
my %winds;
my $winds;
my %gusts;
my $gusts;
my %pressures;
my $pressures;
my %dewps;
my $dewps;
my %clouds;
my $clouds;
my %uvis;
my $uvis;
my %his;
my $his;
my %precs;
my $precs;
my %codes;
my %weatherdess;
my %viss;
my $viss;
my %pops;
my $pops;
my @epoches;
for my $daily( @{$decoded_json->{weather}} ){
	for my $hourly( @{$daily->{hourly}} ){
		my $datetime = $daily->{date} . " " . $hourly->{time}/100 . ":00";
		$t = Time::Piece->strptime($datetime, "%Y-%m-%d %H:%M");
		my $ep = $t->epoch;
		push ( @epoches, $ep );
		$temps{$ep} = $hourly->{tempC};
		$temps = Math::Function::Interpolator::Linear->new( points => \%temps );
		$fltemps{$ep} = $hourly->{FeelsLikeC};
		$fltemps = Math::Function::Interpolator::Linear->new( points => \%fltemps );
		$hums{$ep} = $hourly->{humidity};
		$hums = Math::Function::Interpolator::Linear->new( points => \%hums );
		$winddirs{$ep} = $hourly->{winddirDegree};
		$winddirs = Math::Function::Interpolator::Linear->new( points => \%winddirs );
		$winds{$ep} = $hourly->{windspeedKmph};
		$winds = Math::Function::Interpolator::Linear->new( points => \%winds );
		$gusts{$ep} = $hourly->{WindGustKmph};
		$gusts = Math::Function::Interpolator::Linear->new( points => \%gusts );
		$pressures{$ep} = $hourly->{pressure};
		$pressures = Math::Function::Interpolator::Linear->new( points => \%pressures );
		$dewps{$ep} = $hourly->{DewPointC};
		$dewps = Math::Function::Interpolator::Linear->new( points => \%dewps );
		$clouds{$ep} = $hourly->{cloudcover};
		$clouds = Math::Function::Interpolator::Linear->new( points => \%clouds );
		$uvis{$ep} = $hourly->{uvIndex};
		$uvis = Math::Function::Interpolator::Linear->new( points => \%uvis );
		$his{$ep} = $hourly->{HeatIndexC};
		$his = Math::Function::Interpolator::Linear->new( points => \%his );
		$precs{$ep} = $hourly->{precipMM};
		$precs = Math::Function::Interpolator::Linear->new( points => \%precs );
		$pops{$ep} = $hourly->{chanceofrain};
		$pops = Math::Function::Interpolator::Linear->new( points => \%pops );
		$codes{$ep} = $hourly->{weatherCode};
		if ($hourly->{'lang_' . $lang}[0]->{value}) {
			$weatherdess{$ep} = $hourly->{'lang_' . $lang}[0]->{value};
		} else {
			$weatherdess{$ep} = $hourly->{weatherDesc}[0]->{value};
		}
		$viss{$ep} = $hourly->{visibility};
		$viss = Math::Function::Interpolator::Linear->new( points => \%viss );
	}
}

# Saving new hourly forecast data...
open(F,">$lbplogdir/hourlyforecast.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/hourlyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	# Create hourly data set with interpolation from 3-hourly data
	my $now = time();
	@epoches = sort { $a <=> $b } @epoches;
	my $startep = $epoches[0];
	my $endep = $epoches[-1];
	my $i = 1;
	my $ep;
	my $newline;
	for ($ep = $startep; $ep <= $endep; $ep += 3600 ) { # Step is 3600s
		$newline = "";
		next if $now >= $ep; # data is too old
		$newline = $newline . sprintf("%.1f", $temps->linear($ep)) . "|";
		$newline = $newline . sprintf("%.1f", $fltemps->linear($ep)) . "|";
		$newline = $newline . sprintf("%.1f", $his->linear($ep)) . "|";
		$newline = $newline . sprintf("%.0f", $hums->linear($ep)) . "|";
		my $wdir = 0;
		$wdir = $winddirs->linear($ep);
		if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
		if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
		if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
		if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
		if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
		if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
		if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
		if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		$newline = $newline . $wdirdes . "|";
		$newline = $newline . sprintf("%.1f", $wdir) . "|";
		$newline = $newline . sprintf("%.1f", $winds->linear($ep)) . "|";
		$newline = $newline . sprintf("%.1f", $fltemps->linear($ep)) . "|";
		$newline = $newline . sprintf("%.1f", $pressures->linear($ep)) . "|";
		$newline = $newline . sprintf("%.1f", $dewps->linear($ep)) . "|";
		$newline = $newline . sprintf("%.0f", $clouds->linear($ep)) . "|";
		$newline = $newline . "-9999" . "|";
		$newline = $newline . sprintf("%.0f", $uvis->linear($ep)) . "|";
		$newline = $newline . sprintf("%.2f", $precs->linear($ep)) . "|";
		$newline = $newline . "-9999" . "|";
		$newline = $newline . sprintf("%.0f", $pops->linear($ep)) . "|";
        # Get nearest weather code
		my $weatherdes;
		if ( $codes{$ep} ) {
			$wwo_id = $codes{$ep};
			$weatherdes = $weatherdess{$ep};
		} elsif ( $codes{$ep-3600} ) {
			$wwo_id = $codes{$ep-3600};
			$weatherdes = $weatherdess{$ep-3600};
		} elsif ( $codes{$ep+3600} ) {
			$wwo_id = $codes{$ep+3600};
			$weatherdes = $weatherdess{$ep+3600};
		} elsif ( $codes{$ep-7200} ) {
			$wwo_id = $codes{$ep-7200};
			$weatherdes = $weatherdess{$ep-7200};
		} else {
            $wwo_id = 113; # Default to clear
            $weatherdes = Encode::decode("UTF-8", "Unknown");
        }
        # Convert WTTR weather code into Loxone Weather Code (picto-code) and weather symbol name
	    ($code, $icon) = wttr_to_lox($wwo_id);
		$newline = $newline . "$icon" . "|";
		$newline = $newline . "$code" . "|";
		$newline = $newline . "$weatherdes" . "|";
		$newline = $newline . "-9999" . "|";
		$newline = $newline . "-9999" . "|";
		$newline = $newline . sprintf("%.1f", $viss->linear($ep)) . "|";
		# dfc0_moon_p
		my ( $moonphase,
		  $moonillum,
		  $moonage,
		  $moondist,
		  $moonang,
		  $sundist,
		  $sunang ) = phase($ep);
		$newline = $newline . sprintf("%.2f",$moonillum*100) . "|";
		$newline = $newline . sprintf("%.2f",$moonage) . "|";
		$newline = $newline . sprintf("%.2f",$moonphase*100) . "|";
		# Save new line / dataset
		print F "$i|$ep|";
		$t = Time::Piece->new ($ep);
		print F sprintf("%02d", $t->mday) . "|";
		print F sprintf("%02d", $t->mon) . "|";
		my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour) . "|";
		print F sprintf("%02d", $t->min) . "|";
		my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		print F "$newline\n";
		$i++;
	}
	# Fill data to have at least 72h of forecast data for the weather emulator - otherwise Loxone app
	# scrambles the webdata... :-(
	$i--;
	while ($i < 75) { # Use 75 datasets just to be sure...
		$i++;
		$ep += 3600;
		print F "$i|$ep|";
		$t = Time::Piece->new ($ep);
		print F sprintf("%02d", $t->mday) . "|";
		print F sprintf("%02d", $t->mon) . "|";
		my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour) . "|";
		print F sprintf("%02d", $t->min) . "|";
		my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		print F "$newline\n";
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

# Write JSON files from the .dat files
write_current_json($lbplogdir) if $current;
write_daily_json($lbplogdir) if $daily;
write_hourly_json($lbplogdir) if $hourly;

# Give OK status to client.
LOGOK "Current Data and Forecasts saved successfully.";

# Exit
exit;

END
{
	LOGEND;
}
