#!/usr/bin/perl

# grabber for fetching data from Weatherflow
# fetches weather data (current and forecast) from Weatherflow

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

require "$lbpbindir/grabber_utils.pl";

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

my $pcfg         = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $url          = $pcfg->param("WEATHERFLOW.URL");
my $apikey       = $pcfg->param("WEATHERFLOW.APIKEY");
my $lang         = $pcfg->param("SERVER.LANG");
my $city         = $pcfg->param("SERVER.CITY");
my $country      = $pcfg->param("SERVER.COUNTRY");
my $stationid    = $pcfg->param("WEATHERFLOW.STATIONID");

# Grabber metadata for JSON envelope
my $grabberKey   = "weatherflow";
my $grabberLabel = "WeatherFlow";
my $grabberFile  = "grabber_weatherflow.pl";
my $refresh         = $pcfg->param("SERVER.CRON") // 60;

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'grabber_weatherflow',
	logdir => "$lbplogdir",
);

# Commandline options
my $verbose = '';
my $current = '';
my $daily = '';
my $hourly = '';
my $maskkeys = 1; # optional
GetOptions ('verbose' => \$verbose,
            'interval=i' => \$refresh,
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

LOGSTART "Weather4Lox $grabberLabel GRABBER process started";
LOGDEB "This is $0 Version $version";

requireOrLogdie('Astro::MoonPhase');

# all values in current, daily, and hourly JSONs are in local time, so proper time zone information is important
my $timezone = _systemTimezone();
LOGDEB "Using timezone: $timezone, current local system time is " . _epochToIso(time(), $timezone);

# Get forecast data from Weatherflow Server
# API: https://weatherflow.github.io/Tempest/api/swagger/#/forecast
# Note: the forecast data also contains current conditions, but these are not as accurate as the station observations
# For that reason, we also query the station observations (see below)
my $forecast_json = apiCall(
	url => "$url\/better_forecast?station_id=$stationid&api_key=$apikey",
	maskkeys => $maskkeys,
	keyparam => 'api_key',
	info => "for Location $stationid (Current, Daily, and Hourly Weather Data)",
);

my $i;
my $current_observation_json;

# Mapping: WeatherFlow Icon => [Loxone Code, Weather4Lox Icon Name]
# https://weatherflow.github.io/Tempest/api/swagger/#/forecast/getBetterForecast
# https://www.loxone.com/enen/kb/weather-service/
my %weatherflow_to_lox = (
    "clear"                => [ "1", "clear"],
    "partlycloudy"         => [ "3", "partly_cloudy"],
    "cloudy"               => [ "4", "cloudy"],
    "sleet"                => ["26", "overcast_sleet_2"],
    "chancesleet"          => ["26", "cloudy_sleet_1"],
    "snow"                 => ["21", "overcast_snow_2"],
    "chancesnow"           => ["23", "cloudy_snow_1"],
    "rainy"                => ["11", "overcast_rain_2"],
    "chancerainy"          => ["16", "cloudy_rain_1"],
    "chancethunderstorm"   => ["18", "cloudy_thunderstorm_1"],
    "thunderstorm"         => ["18", "overcast_thunderstorm_2"],
    "foggy"                => [ "6", "fog"],
    "windy"                => [ "5", "wind"],
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

# Detect nighttime from WeatherFlow icon string (contains "-night" suffix)
sub wfIsNight {
    my ($icon_raw) = @_;
    return undef unless defined $icon_raw;
    return ($icon_raw =~ /-night/) ? 1 : undef;
}

##########################################################################
# Common data
##########################################################################

my $lat             = $forecast_json->{latitude};
my $lon             = $forecast_json->{longitude};
my $timezoneFromApi = $forecast_json->{timezone};
if ($timezone ne $timezoneFromApi) {
    LOGWARN "Timezone for location '$city' ($timezoneFromApi) does not match the system timezone of your LoxBerry ($timezone). Time differences may occur!";
}
# Derive timezone short name and offset from current epoch
my $currentEpoch = $forecast_json->{current_conditions}->{time};

my $generatedAt = _epochToIso(time(), $timezone);

# Timezone short and offset via POSIX
my ($tzShort, $tzOffset);
{
    local $ENV{TZ} = $timezone;
    POSIX::tzset();
    $tzShort  = POSIX::strftime('%Z', localtime($currentEpoch));
    $tzOffset = POSIX::strftime('%z', localtime($currentEpoch));
    POSIX::tzset();
}

$city    = Encode::decode("UTF-8", $city)    if defined $city;
$country = Encode::decode("UTF-8", $country) if defined $country;

my $location = {
    city        => $city,
    country     => $country,
    countryCode => undef,                 # not available from WeatherFlow API
    elevation   => undef,                 # will be filled from observation if available
    latitude    => defined $lat ? $lat + 0 : undef,
    longitude   => defined $lon ? $lon + 0 : undef,
    timezone    => $timezone,
    tzOffset    => $tzOffset,
    tzShort     => $tzShort,
};

##########################################################################
# Fetch current data
##########################################################################

if ( $current ) {

    # Get current station observation from Weatherflow Server
    # API : https://weatherflow.github.io/Tempest/api/swagger/#!/observations/getStationObservation
    # Docs: https://apidocs.tempestwx.com/reference/get_better-forecast-1
    $current_observation_json = apiCall(
        url => "$url\/observations/station/$stationid?token=$apikey",
        maskkeys => $maskkeys,
        keyparam => 'token',
        info => "for Location $stationid (Current Observation Data)",
    );

    my $cur = $current_observation_json->{obs}->[0];
    my $cc  = $forecast_json->{current_conditions};

    # Update location elevation from observation data
    if (defined $current_observation_json->{elevation}) {
        $location->{elevation} = $current_observation_json->{elevation} + 0;
    }

    LOGINF "Reading current weather data from API response into W4L structure.";

    # time
    my %time;
    $time{datetime} = _epochToIso($cc->{time}, $timezone);
    $time{epoch}    = $cc->{time};

    # cur_date_tz_des (e.g. Europe/Berlin), cur_date_tz_des_sh (e.g. "CET"), cur_date_tz (e.g. "+0100") are send in location section 

    # sunrise / sunset
    my ($sunrise, $sunset);
    if (defined $forecast_json->{forecast}->{daily}->[0]->{sunrise}) {
        my $t_sr = localtime($forecast_json->{forecast}->{daily}->[0]->{sunrise});
        $sunrise = sprintf("%02d:%02d", $t_sr->hour, $t_sr->min);
    }
    if (defined $forecast_json->{forecast}->{daily}->[0]->{sunset}) {
        my $t_ss = localtime($forecast_json->{forecast}->{daily}->[0]->{sunset});
        $sunset = sprintf("%02d:%02d", $t_ss->hour, $t_ss->min);
    }

    # temperature
    my %temperature;
    $temperature{air}       = defined $cur->{air_temperature} ? sprintf("%.1f", $cur->{air_temperature}) + 0 : undef;
    $temperature{feelsLike} = defined $cur->{feels_like}      ? sprintf("%.1f", $cur->{feels_like}) + 0      : undef;
    $temperature{windChill} = defined $cur->{wind_chill}      ? sprintf("%.1f", $cur->{wind_chill}) + 0      : undef;
    $temperature{heatIndex} = defined $cur->{heat_index}      ? sprintf("%.1f", $cur->{heat_index}) + 0      : undef;

    # wind (WeatherFlow provides m/s, convert to km/h)
    my %wind;
    my $wdeg = $cur->{wind_direction};
    $wind{direction} = defined $wdeg ? $wdeg + 0 : undef;
    $wind{cardinal}  = getWindDirCardinal($wdeg);
    $wind{speed}     = defined $cur->{wind_avg}  ? sprintf("%.1f", $cur->{wind_avg} * 3.6) + 0  : undef;
    $wind{gust}      = defined $cur->{wind_gust} ? sprintf("%.1f", $cur->{wind_gust} * 3.6) + 0 : undef;

    # precipitation
    my %precipitation;
    $precipitation{rainToday}    = defined $cur->{precip_accum_local_day} ? sprintf("%.2f", $cur->{precip_accum_local_day}) + 0 : undef;
    $precipitation{rain1hr}      = defined $forecast_json->{forecast}->{hourly}->[0]->{precip} ? sprintf("%.2f", $forecast_json->{forecast}->{hourly}->[0]->{precip}) + 0 : undef;
    $precipitation{probability}  = defined $forecast_json->{forecast}->{daily}->[0]->{precip_probability} ? sprintf("%.0f", $forecast_json->{forecast}->{daily}->[0]->{precip_probability} * 100) + 0 : undef;
    $precipitation{type}         = "none";  # not available from WeatherFlow observation
    $precipitation{snowToday}    = undef;   # not available from WeatherFlow API
    $precipitation{snow1hr}      = undef;   # not available from WeatherFlow API

    # weather codes
    my %weatherCode;
    my ($loxoneCode, $w4lCode) = weatherflow_to_lox($cc->{icon});
    $weatherCode{loxone}      = $loxoneCode;
    $weatherCode{weather4lox} = $w4lCode;
    $weatherCode{description} = $cc->{conditions};
    $weatherCode{image}       = $cc->{icon};
    $weatherCode{metar}       = getMetarCode($w4lCode);

    # moon
    my %moon;
    my ($moonphase, $moonillum, $moonage) = (Astro::MoonPhase::phase())[0,1,2];
    $moon{age}       = sprintf("%.2f", $moonage) + 0;
    $moon{percent}   = sprintf("%.2f", $moonillum * 100) + 0;
    $moon{phase}     = sprintf("%.2f", $moonphase * 100) + 0;
    $moon{direction} = getMoonDirection($moonage);

    # Build current data hash
    my %currentData = (
        time           => \%time,
        sunrise        => $sunrise,
        sunset         => $sunset,
        temperature    => \%temperature,
        humidity       => defined $cur->{relative_humidity} ? $cur->{relative_humidity} + 0 : undef,
        wind           => \%wind,
        pressure       => defined $cur->{sea_level_pressure} ? sprintf("%.0f", $cur->{sea_level_pressure}) + 0 : undef,
        dewpoint       => defined $cur->{dew_point}          ? sprintf("%.1f", $cur->{dew_point}) + 0          : undef,
        visibility     => undef,  # not available from WeatherFlow API
        solarRadiation => defined $cur->{solar_radiation}    ? sprintf("%.1f", $cur->{solar_radiation}) + 0    : undef,
        uvIndex        => defined $cur->{uv}                 ? sprintf("%.0f", $cur->{uv}) + 0                 : undef,
        precipitation  => \%precipitation,
        weatherCode    => \%weatherCode,
        cloudCover     => undef,  # not available from WeatherFlow API
        moon           => \%moon,
        isNight        => wfIsNight($cc->{icon}),
    );

    # Build envelope and write JSON to file
    my $weatherKey = "current";
    my $envelope = {
        refresh     => $refresh,
        generatedAt => $generatedAt,
        location    => $location,
        $grabberKey => {
            filename      => "$lbplogdir/$weatherKey.json",
            generatedAt   => $generatedAt,
            grabberLabel  => $grabberLabel,
            grabberScript => $grabberFile,
            schemaVersion => "v1.0",
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
    my $day = 0;               # used for days, starts with 0 for current day, 1 for next day, etc.

    LOGINF "Reading daily weather data from API response into W4L structure.";

    for my $results ( @{$forecast_json->{forecast}->{daily}} ) {

        # time
        my %time;
        $time{datetime} = _epochToIso($results->{day_start_local}, $timezone);
        $time{epoch}    = $results->{day_start_local};

        # sunrise / sunset
        my ($sunrise, $sunset);
        if (defined $results->{sunrise}) {
            my $t_sr = localtime($results->{sunrise});
            $sunrise = sprintf("%02d:%02d", $t_sr->hour, $t_sr->min);
        }
        if (defined $results->{sunset}) {
            my $t_ss = localtime($results->{sunset});
            $sunset = sprintf("%02d:%02d", $t_ss->hour, $t_ss->min);
        }

        # temperature
        my %tempMax;
        $tempMax{air}       = defined $results->{air_temp_high} ? sprintf("%.1f", $results->{air_temp_high}) + 0 : undef;
        $tempMax{feelsLike} = undef;  # not available from WeatherFlow daily
        $tempMax{heatIndex} = undef;  # not available from WeatherFlow daily

        my %tempMin;
        $tempMin{air}       = defined $results->{air_temp_low} ? sprintf("%.1f", $results->{air_temp_low}) + 0 : undef;
        $tempMin{feelsLike} = undef;  # not available from WeatherFlow daily
        $tempMin{windChill} = undef;  # not available from WeatherFlow daily

        # wind - not available from WeatherFlow daily forecast
        my %windAvg;
        $windAvg{direction} = undef;
        $windAvg{dirLabel}  = undef;
        $windAvg{speed}     = undef;
        $windAvg{gust}      = undef;

        my %windMax = %windAvg;

        # humidity - not available from WeatherFlow daily forecast
        my %humidity;
        $humidity{avg} = undef;
        $humidity{max} = undef;
        $humidity{min} = undef;

        # precipitation
        my %precipitation;
        $precipitation{probability} = defined $results->{precip_probability} ? sprintf("%.0f", $results->{precip_probability} * 100) + 0 : undef;
        $precipitation{rainHigh}    = undef;  # not available from WeatherFlow daily
        $precipitation{rainLow}     = undef;  # not available from WeatherFlow daily
        $precipitation{snowHigh}    = undef;  # not available from WeatherFlow daily
        $precipitation{snowLow}     = undef;  # not available from WeatherFlow daily
        $precipitation{duration}    = undef;  # not available from WeatherFlow daily
        $precipitation{type}        = "none"; # not available from WeatherFlow daily

        # weather codes
        my %weatherCode;
        my ($loxoneCode, $w4lCode) = weatherflow_to_lox($results->{icon});
        $weatherCode{loxone}      = $loxoneCode;
        $weatherCode{weather4lox} = $w4lCode;
        $weatherCode{description} = $results->{conditions};
        $weatherCode{image}       = undef;
        $weatherCode{metar}       = getMetarCode($w4lCode);

        # moon
        my %moon;
        my ($moonphase, $moonillum, $moonage) = (Astro::MoonPhase::phase($results->{day_start_local}))[0,1,2];
        $moon{age}       = sprintf("%.2f", $moonage) + 0;
        $moon{percent}   = sprintf("%.2f", $moonillum * 100) + 0;
        $moon{phase}     = sprintf("%.2f", $moonphase * 100) + 0;
        $moon{direction} = getMoonDirection($moonage);
        $moon{rise}      = undef;  # not available from WeatherFlow API
        $moon{set}       = undef;  # not available from WeatherFlow API

        push @dailyData, {
            day            => $day,
            time           => \%time,
            sunrise        => $sunrise,
            sunset         => $sunset,
            temperature    => { max => \%tempMax, min => \%tempMin },
            wind           => { avg => \%windAvg, max => \%windMax },
            humidity       => \%humidity,
            pressure       => undef,  # not available from WeatherFlow daily
            dewpoint       => undef,  # not available from WeatherFlow daily
            precipitation  => \%precipitation,
            weatherCode    => \%weatherCode,
            moon           => \%moon,
            uvIndex        => undef,  # not available from WeatherFlow daily
            visibility     => undef,  # not available from WeatherFlow daily
            solarRadiation => undef,  # not available from WeatherFlow daily
            cloudCover     => undef,  # not available from WeatherFlow daily
        };
        $day++;
    }

    # Build envelope and write JSON to file
    my $weatherKey = "dailyforecast";
    my $envelope = {
        refresh     => $refresh,
        generatedAt => $generatedAt,
        location    => $location,
        $grabberKey => {
            filename      => "$lbplogdir/$weatherKey.json",
            generatedAt   => $generatedAt,
            grabberLabel  => $grabberLabel,
            grabberScript => $grabberFile,
            schemaVersion => "v1.0",
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
    my $hour = 1;               # used for hours, starts with 1 for first forecasted hour, 2 for next hour, etc.

    LOGINF "Reading hourly weather data from API response into W4L structure.";

    for my $h ( @{$forecast_json->{forecast}->{hourly}} ) {

        # time
        my %time;
        $time{datetime} = _epochToIso($h->{time}, $timezone);
        $time{epoch}    = $h->{time};

        # temperature
        my %temperature;
        $temperature{air}       = defined $h->{air_temperature} ? sprintf("%.1f", $h->{air_temperature}) + 0 : undef;
        $temperature{feelsLike} = defined $h->{feels_like}      ? sprintf("%.1f", $h->{feels_like}) + 0      : undef;
        $temperature{heatIndex} = undef;  # not available from WeatherFlow hourly
        $temperature{windChill} = undef;  # not available from WeatherFlow hourly

        # wind (WeatherFlow provides m/s, convert to km/h)
        my %wind;
        my $wdeg = $h->{wind_direction};
        $wind{direction} = defined $wdeg ? $wdeg + 0 : undef;
        $wind{cardinal}  = getWindDirCardinal($wdeg);
        $wind{speed}     = defined $h->{wind_avg} ? sprintf("%.1f", $h->{wind_avg} * 3.6) + 0 : undef;
        $wind{gust}      = undef;  # not available from WeatherFlow hourly

        # precipitation
        my %precipitation;
        $precipitation{probability} = defined $h->{precip_probability} ? sprintf("%.0f", $h->{precip_probability} * 100) + 0 : undef;
        $precipitation{rainHigh}    = defined $h->{precip} && $h->{precip} > 0 ? sprintf("%.2f", $h->{precip}) + 0 : undef;
        $precipitation{rainLow}     = undef;
        $precipitation{snowHigh}    = undef;  # not available from WeatherFlow hourly
        $precipitation{snowLow}     = undef;
        $precipitation{duration}    = undef;
        $precipitation{type}        = "none";  # not available from WeatherFlow hourly

        # weather codes
        my %weatherCode;
        my ($loxoneCode, $w4lCode) = weatherflow_to_lox($h->{icon});
        $weatherCode{loxone}      = $loxoneCode;
        $weatherCode{weather4lox} = $w4lCode;
        $weatherCode{description} = $h->{conditions};
        $weatherCode{metar}       = getMetarCode($w4lCode);

        # moon
        my %moon;
        my ($moonphase, $moonillum, $moonage) = (Astro::MoonPhase::phase($h->{time}))[0,1,2];
        $moon{age}       = sprintf("%.2f", $moonage) + 0;
        $moon{percent}   = sprintf("%.2f", $moonillum * 100) + 0;
        $moon{phase}     = sprintf("%.2f", $moonphase * 100) + 0;
        $moon{direction} = getMoonDirection($moonage);

        push @hourlyData, {
            hour           => $hour,
            time           => \%time,
            temperature    => \%temperature,
            humidity       => defined $h->{relative_humidity} ? $h->{relative_humidity} + 0 : undef,
            wind           => \%wind,
            pressure       => defined $h->{sea_level_pressure} ? sprintf("%.0f", $h->{sea_level_pressure}) + 0 : undef,
            dewpoint       => undef,       # not available from WeatherFlow hourly
            visibility     => undef,       # not available from WeatherFlow hourly
            solarRadiation => undef,       # not available from WeatherFlow hourly
            uvIndex        => defined $h->{uv} ? sprintf("%.1f", $h->{uv}) + 0 : undef,
            precipitation  => \%precipitation,
            weatherCode    => \%weatherCode,
            cloudCover     => undef,       # not available from WeatherFlow hourly
            moon           => \%moon,
            isNight        => wfIsNight($h->{icon}),
        };
        $hour++;
    }

    # Build envelope and write JSON to file
    my $weatherKey = "hourlyforecast";
    my $envelope = {
        refresh     => $refresh,
        generatedAt => $generatedAt,
        location    => $location,
        $grabberKey => {
            filename      => "$lbplogdir/$weatherKey.json",
            generatedAt   => $generatedAt,
            grabberLabel  => $grabberLabel,
            grabberScript => $grabberFile,
            schemaVersion => "v1.0",
        },
        $weatherKey => \@hourlyData,
    };
    writeJsonFile($lbplogdir, $weatherKey, $envelope);

} # End hourly

# Give OK status to client.
LOGOK "Current Data and Forecasts saved successfully.";

# Exit
exit;

END
{
	LOGEND;
}
