#!/usr/bin/perl

# grabber for fetching data from Weatherflow
# fetches weather data (current and forecast) from Weatherflow
#
# Copyright 2016-2023 Michael Schlenstedt, michael@loxberry.de
# Copyright 2020 Martin Barnasconi, nufke@barnasconi.net
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
my $url          = $pcfg->param("WEATHERFLOW.URL");
my $apikey       = $pcfg->param("WEATHERFLOW.APIKEY");
my $lang         = $pcfg->param("WEATHERFLOW.LANG");
#my $coordlat     = $pcfg->param("WEATHERFLOW.COORDLAT");
#my $coordlong    = $pcfg->param("WEATHERFLOW.COORDLONG");
my $city         = $pcfg->param("WEATHERFLOW.CITY");
my $country      = $pcfg->param("WEATHERFLOW.COUNTRY");
my $stationid    = $pcfg->param("WEATHERFLOW.STATIONID");

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'grabber_weatherflow',
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

# Due to a bug in the Logging routine, set the loglevel fix to 3
#$log->loglevel(3);
if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

# Update API key to comply with Wetherflow format
#$apikey =~ s/^(.{8})(.{4})(.{4})(.{4})(.{12})/$1\-$2\-$3\-$4\-$5/;

LOGSTART "Weather4Lox GRABBER_WEATHERFLOW process started";
LOGDEB "This is $0 Version $version";

# Get forecast data from Weatherflow Server
# API: https://weatherflow.github.io/Tempest/api/swagger/#/forecast
# Note: the forecast data also contains current conditions, but these are not as accurate as the station observations
# For that reason, we also query the station observations (see below)
my $forecast_json = api_call(
	url => "$url\/better_forecast?station_id=$stationid&api_key=$apikey",
	maskkeys => $maskkeys,
	keyparam => 'api_key',
	# apikey => $apikey,	# not needed here as the URL is already masked and the key won't appear elsewhere in the response
	info => "for Location $stationid (Current, Daily, and Hourly Weather Data)",
);

my $t;
my $weather;
my $icon;
my $code;
my $wdir;
my $wdirdes;
my @filecontent;
my $i;
my $error;

# Mapping: WeatherFlow Icon => [Loxone Code, Weather4Lox Icon Name]
# https://weatherflow.github.io/Tempest/api/swagger/#/forecast/getBetterForecast
# https://www.loxone.com/enen/kb/weather-service/
my %weatherflow_to_lox = (                            # WeatherFlow Icon Values (originally with -day and -night suffixes)
    "clear"                => ["1",  "clear"],           # was clear-day, clear-night
    "partlycloudy"         => ["3",  "partlycloudy"],    # was partly-cloudy-day, partly-cloudy-night
    "cloudy"               => ["4",  "cloudy"],          # was cloudy
    "sleet"                => ["26", "sleet"],			 # was sleet
    "chancesleet"          => ["26", "chancesleet"],     # was possibly-sleet-day, possibly-sleet-night
    "snow"                 => ["21", "snow"],            # was snow
    "chancesnow"           => ["23", "chancesnow"],      # was possibly-snow-day, possibly-snow-night
    "rainy"                => ["11", "rain"],      # was rainy
    "chancerainy"          => ["16", "chancerain"],      # was possibly-rainy-day, possibly-rainy-night
    "chancethunderstorm"   => ["18", "chancetstorms"],   # was possibly-thunderstorm-day, possibly-thunderstorm-night
    "thunderstorm"         => ["18", "tstorms"],         # was thunderstorm
    "foggy"                => ["6",  "fog"],             # was foggy
    "windy"                => ["5", "wind"],            # was windy
);

sub weatherflow_to_lox {
    my ($weather_raw) = @_;
    
    # Check for empty/undefined values
    if (!defined $weather_raw || $weather_raw eq "") {
        LOGWARN "WeatherFlow icon is empty/undefined!";
        return ("0", "clear");
    }
    
    # Normalization
    my $weather = lc($weather_raw);           # Lowercase
    $weather =~ s/-(?:night|day)//;           # remove -night and -day
    $weather =~ s/cc-//;                      # remove cc- (current Weatherflow API bug)
    $weather =~ s/-//g;                       # remove all hyphens
    $weather =~ s/possibly/chance/;           # replace possibly with chance
    
    # Lookup in the hash
    my $result = $weatherflow_to_lox{$weather};
    
    if ($result) {
        return ($result->[0], $result->[1]);  # (code, icon)
    } else {
        # Fallback
        LOGWARN "Unknown weather icon name from WeatherFlow: '$weather_raw' (normalized: '$weather'). Using fallback code 1 = 'clear'.";
        return ("1", $weather);  # Code 1 = Clear, but keep the icon name
    }
}


if ( $current ) { # Start current

	# Get current station observation from Weatherflow Server
	# API : https://weatherflow.github.io/Tempest/api/swagger/#!/observations/getStationObservation
	# Docs: https://apidocs.tempestwx.com/reference/get_better-forecast-1
    my $current_observation_json = api_call(
        url => "$url\/observations/station/$stationid?token=$apikey",
        maskkeys => $maskkeys,
        keyparam => 'token',
        # apikey => $apikey,	# not needed here as the URL is already masked and the key won't appear elsewhere in the response
        info => "for Location $stationid (Current Observation Data)",
    );

	# Write location data into database
	$t = localtime($forecast_json->{current_conditions}->{time});
	LOGINF "Saving new Data for Timestamp $t to database.";

	# Saving new current data...
	$error = 0;
	open(F,">$lbplogdir/current.dat.tmp") or $error = 1;
	if ($error) {
		LOGCRIT "Cannot open $lbpconfigdir/current.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	print F "$forecast_json->{current_conditions}->{time}|"; # Date Epoche
	print F $t, " ", sprintf("+%04d", $forecast_json->{timezone_offset_minutes}/60 * 100), "|"; # Date RFC822
	my $tz_short = qx(TZ='$forecast_json->{timezone}' date +%Z);
	chomp ($tz_short);
	print F "$tz_short|"; # Timezone Short
	print F "$forecast_json->{timezone}|"; # Timezone Long
	print F sprintf("+%04d", $forecast_json->{timezone_offset_minutes}/60 * 100), "|"; # Timezone Offset
	$city = Encode::decode("UTF-8", $city);
	print F "$city|"; # Observation location
	$country = Encode::decode("UTF-8", $country);
	print F "$country|"; # Location Country
	print F "-9999|"; # Location Country Code (not available in Weatherflow API)
	print F "$forecast_json->{latitude}|"; # Location Latitude
	print F "$forecast_json->{longitude}|"; # Location Longitude
	print F "$current_observation_json->{elevation}|"; # Location Elevation (Height in meters above sea level)
	print F sprintf("%.1f",$current_observation_json->{obs}->[0]->{air_temperature}), "|"; # Temperature
	print F sprintf("%.1f",$current_observation_json->{obs}->[0]->{feels_like}), "|"; # Feelslike Temp
	print F "$current_observation_json->{obs}->[0]->{relative_humidity}|"; # Rel. Humidity
	$wdir = $current_observation_json->{obs}->[0]->{wind_direction};
	if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
	if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
	if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
	if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
	if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
	if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
	if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
	if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
	if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
	print F "$wdirdes|"; # Wind Dir Description
	print F "$current_observation_json->{obs}->[0]->{wind_direction}|"; # Wind Dir Degrees
	print F sprintf("%.1f",$current_observation_json->{obs}->[0]->{wind_avg} * 3.6), "|"; # Wind Speed
	print F sprintf("%.1f",$current_observation_json->{obs}->[0]->{wind_gust} * 3.6), "|"; # Wind Gust
	print F sprintf("%.0f",$current_observation_json->{obs}->[0]->{wind_chill}), "|"; # Windchill
	print F "$current_observation_json->{obs}->[0]->{sea_level_pressure}|"; # Pressure
	print F sprintf("%.1f",$current_observation_json->{obs}->[0]->{dew_point}), "|"; # Dew Point
	print F "-9999|"; # Visibility (not available in Weatherflow API)
	print F "$current_observation_json->{obs}->[0]->{solar_radiation}|"; #Solar Radiation
	print F "$current_observation_json->{obs}->[0]->{heat_index}|"; #Heat Index
	print F "$current_observation_json->{obs}->[0]->{uv}|"; # UV Index
	print F sprintf("%.3f",$current_observation_json->{obs}->[0]->{precip_accum_local_day}), "|";  # Precipitation Today
	print F sprintf("%.3f",$forecast_json->{forecast}->{hourly}->[0]->{precip}), "|"; # Precipitation 1hr (note: forecast, to reflect the expected rain in mm/h)

	# Convert Weatherflow weather icon string into normalized icon name and Loxone picto-code
	($code, $icon)= weatherflow_to_lox($forecast_json->{current_conditions}->{icon});
	print F "$icon|"; # Weather4Lox Weather Icon name
	print F "$code|"; # Loxone Weather Code
	print F "$forecast_json->{current_conditions}->{conditions}|"; # Weather Description (note: forecast, since current observation does not have this info)
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
#	print F "-9999|"; # Moon percent Illuminated (not available in Weatherflow API)
#	print F "-9999|"; # Moon: Age of Moon (not available in Weatherflow API)
#	print F "-9999|"; # Moon: Phase of Moon (not available in Weatherflow API)
#	print F "-9999|"; # Moon: Hemisphere (not available in Weatherflow API)
	$t = localtime($forecast_json->{forecast}->{daily}->[0]->{sunrise});
	print F sprintf("%02d", $t->hour), "|"; # Sunrise
	print F sprintf("%02d", $t->min), "|";
	$t = localtime($forecast_json->{forecast}->{daily}->[0]->{sunset});
	print F sprintf("%02d", $t->hour), "|"; # Sunset
	print F sprintf("%02d", $t->min), "|";
	print F "-9999|"; # Density of atmospheric ozone (not available in Weatherflow API)
	print F "-9999|"; # Sky (clouds) % (not available in Weatherflow API)
	print F $forecast_json->{forecast}->{daily}->[0]->{precip_probability}*100, "|"; # % of Precipitation
	print F "-9999|"; # Snow (not available in Weatherflow API)
	close(F);

	LOGOK "Saving current data to $lbplogdir/current.dat.tmp successfully.";

	my @filecontent;
	LOGDEB "Database content:";
	open(F,"<$lbplogdir/current.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		# Convert elevation from feet to meter
		LOGDEB "$_";
	}
	close (F);

} # end current

#
# Fetch daily data
#

if ( $daily ) { # Start daily

	# Saving new daily forecast data...
	$error = 0;
	open(F,">$lbplogdir/dailyforecast.dat.tmp") or $error = 1;
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/dailyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	my $i = 1;
	for my $results( @{$forecast_json->{forecast}->{daily}} ){
		print F "$i|"; # day count
		$i++;
		print F $results->{day_start_local}, "|"; # Date Epoche
		$t = localtime($results->{day_start_local});
		print F sprintf("%02d", $t->mday), "|"; # Date: Day
		print F sprintf("%02d", $t->mon), "|"; # Date: Month
		my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|"; # Date: Month name
		@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|"; # Date: Month name short
		print F $t->year . "|"; # Date: Year
		print F sprintf("%02d", $t->hour), "|"; # Date: Hour
		print F sprintf("%02d", $t->min), "|"; # Date: Minutes
		my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|"; # Date: weekday name
		@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|"; # Date: weekday short name
		print F sprintf("%.1f",$results->{air_temp_high}), "|"; # High temperature
		print F sprintf("%.1f",$results->{air_temp_low}), "|"; # Low temperature
		print F $results->{precip_probability}, "|"; # % of Precipitation
		print F "-9999|"; # Precipitation Forecast (not available in Weatherflow API)
		print F "-9999|"; # Snow Forecast (not available in Weatherflow API)
		print F "-9999|"; # Max. Wind Speed (not available in Weatherflow API)
		print F "-9999|"; # Max. Wind Dir Descript. (not available in Weatherflow API)
		print F "-9999|"; # Max. Wind Dir  (not available in Weatherflow API)
		print F "-9999|"; # Ave. Wind Speed (not available in Weatherflow API)
		print F "-9999|"; # Ave. Wind Dir Descript. (not available in Weatherflow API)
		print F "-9999|"; # Ave. Wind Dir (not available in Weatherflow API)
		print F "-9999|"; # Ave. Humidity (not available in Weatherflow API)
		print F "-9999|"; # Max. Humidity (not available in Weatherflow API)
		print F "-9999|"; # Min. Humidity (not available in Weatherflow API)

		# Convert Weatherflow weather icon string into normalized icon name and Loxone picto-code
		($code, $icon)= weatherflow_to_lox($results->{icon});
		print F "$icon|"; # Weather4Lox Weather Icon name
		print F "$code|"; # Loxone Weather Code
		print F "$results->{conditions}|"; # Weather Description
		print F "-9999|"; # Density of atmospheric ozone (not available in Weatherflow API)
		my ( $moonphase,
		  $moonillum,
		  $moonage,
		  $moondist,
		  $moonang,
		  $sundist,
		  $sunang ) = phase($results->{day_start_local});
		print F sprintf("%.2f",$moonillum*100), "|";
		print F "-9999|"; # Dew Point (not available in Weatherflow API)
		print F "-9999|"; # Pressure (not available in Weatherflow API)
		print F "-9999|"; #UV Index (not available in Weatherflow API)
		$t = localtime($results->{sunrise}); # Sunrise
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		$t = localtime($results->{sunset}); # Sunset
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		print F "-9999|"; # Visibility  (not available in Weatherflow API)
		print F sprintf("%.2f",$moonage), "|";
		print F sprintf("%.2f",$moonphase*100), "|";
		print F "\n";
	}
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

} # end daily

#
# Fetch hourly data
#

if ( $hourly ) { # Start hourly

	# Saving new hourly forecast data...
	$error = 0;
	open(F,">$lbplogdir/hourlyforecast.dat.tmp") or $error = 1;
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/hourlyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	$i = 1;
	my $n = 0;
	for my $results( @{$forecast_json->{forecast}->{hourly}} ){
		print F "$i|"; # Hour count
		$i++;
		print F $results->{time}, "|"; # Date: Epoche
		$t = localtime($results->{time});
		print F sprintf("%02d", $t->mday), "|"; # Date: Day
		print F sprintf("%02d", $t->mon), "|"; # Date: Month
		my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|"; # Date: Month name
		@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|"; # Date: Month short name
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour), "|"; # Date: hour
		print F sprintf("%02d", $t->min), "|"; # Date: minutes
		my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|"; # Date: Weekday name
		@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|"; # Date: Weekday short name
		print F sprintf("%.1f",$results->{air_temperature}), "|"; # Temperature (air)
		print F sprintf("%.1f",$results->{feels_like}), "|"; # Feelslike Temperature
		print F "-9999|"; # Heat Index (not available in Weatherflow API)
		print F $results->{relative_humidity}, "|"; # Humidity
		$wdir = $results->{wind_direction};
		if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
		if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
		if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
		if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
		if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
		if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
		if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
		if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		print F "$wdirdes|"; # Wind Dir. Description
		print F "$results->{wind_direction}|"; # Wind Dir. (grad)
		print F sprintf("%.1f",$results->{wind_avg} * 3.6), "|"; # Wind Speed in Km/h
		print F sprintf("%.1f",$results->{feels_like}), "|"; # TODI Wind Chill same as feels like?
		print F "$results->{sea_level_pressure}|";
		print F "-9999|"; # Dewpoint (not available in Weatherflow API)
		print F "-9999|"; # Sky (clouds) cover (not available in Weatherflow API)
		print F "-9999|"; # Sky Description (not available in Weatherflow API)
		print F "$results->{uv}|"; # UV Index
		print F $results->{precip}, "|";  # Quant. Precipitation FC in mm
		print F "-9999|"; # Snow Forecast (not available in Weatherflow API)
		print F $results->{precip_probability}, "|";

		# Convert Weatherflow weather icon string into normalized icon name and Loxone picto-code
		($code, $icon)= weatherflow_to_lox($results->{icon});
		print F "$icon|"; # Weather4Lox Weather Icon name
		print F "$code|"; # Loxone Weather Code
		print F "$results->{conditions}|"; # Weather description
		print F "-9999|"; # Ozone (not available in Weatherflow API)
		print F "-9999|"; # Solar Radiation (not available in Weatherflow API)
		print F "-9999|"; # Visability (not available in Weatherflow API)
		# dfc0_moon_p
		my ( $moonphase,
		  $moonillum,
		  $moonage,
		  $moondist,
		  $moonang,
		  $sundist,
		  $sunang ) = phase($results->{time});
		print F sprintf("%.2f",$moonillum*100), "|";
		print F sprintf("%.2f",$moonage), "|";
		print F sprintf("%.2f",$moonphase*100), "|";
		print F "\n";
	}
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

if ($current) {

LOGINF "Cleaning $lbplogdir/current.dat.tmp";
open(F,"+<$lbplogdir/current.dat.tmp");
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
close(F);

my $currentname = "$lbplogdir/current.dat.tmp";
my $currentsize = -s ($currentname);
if ($currentsize > 100) {
        move($currentname, "$lbplogdir/current.dat");
}

}

if ($daily) {

LOGINF "Cleaning $lbplogdir/dailyforecast.dat.tmp";
open(F,"+<$lbplogdir/dailyforecast.dat.tmp");
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
close(F);

my $dailyname = "$lbplogdir/dailyforecast.dat.tmp";
my $dailysize = -s ($dailyname);
if ($dailysize > 100) {
        move($dailyname, "$lbplogdir/dailyforecast.dat");
}

}

if ($hourly) {

LOGINF "Cleaning $lbplogdir/hourlyforecast.dat.tmp";
open(F,"+<$lbplogdir/hourlyforecast.dat.tmp");
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
