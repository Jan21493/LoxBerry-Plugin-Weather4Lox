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
use JSON::PP;
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
my $maskKeys     = $pcfg->param("SERVER.MASKKEYS");

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
GetOptions ('verbose' => \$verbose,
            'interval=i' => \$refresh,
            'quiet'   => sub { $verbose = 0 },
            'current' => \$current,
            'daily' => \$daily,
            'hourly' => \$hourly,
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
LOGDEB "Using timezone: $timezone, current local system time is " . _epochToIso(time(), $timezone);

# Get forecast data from Weatherflow Server
# API: https://weatherflow.github.io/Tempest/api/swagger/#/forecast
# Note: the forecast data also contains current conditions, but these are not as accurate as the station observations, 
# e.g. temperatures and wind are rounded to integers.
# For that reason, we also query the station observations (see below)
my $results = apiCall(
	url => "$url/better_forecast?station_id=$stationid&api_key=$apikey",
	maskkeys => $maskKeys,
	keyparam => 'api_key',
	info => "for location $stationid (current, daily, and hourly weather data)",
);

my $i;

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
    $weather =~ s/cc-//;                      # remove cc- (prefix used for current conditions)
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

my $lat             = $results->{latitude};
my $lon             = $results->{longitude};
my $timezoneFromApi = $results->{timezone};
if ($timezone ne $timezoneFromApi) {
    LOGWARN "Timezone for location '$city' ($timezoneFromApi) does not match the system timezone of your LoxBerry ($timezone). Time differences may occur!";
}
# Derive timezone short name and offset from current epoch
my $currentEpoch = $results->{current_conditions}->{time};

my $generatedAt = _epochToIso(time(), $timezone);

# Timezone short and offset via POSIX
my ($tzShort, $tzOffset);
{
    local $ENV{TZ} = $timezoneFromApi;
    POSIX::tzset();     # change to timezone from API
    $tzShort  = POSIX::strftime('%Z', localtime($currentEpoch));
    $tzOffset = POSIX::strftime('%z', localtime($currentEpoch));
}
POSIX::tzset();     # change back to system timezone

$city    = Encode::decode("UTF-8", $city)    if defined $city;
$country = Encode::decode("UTF-8", $country) if defined $country;

my $location = {
    city        => $city,
    country     => $country,
    countryCode => undef,                 # not available from WeatherFlow API
    elevation   => undef,                 # will be filled from observation if available
    latitude    => defined $lat ? $lat + 0 : undef,
    longitude   => defined $lon ? $lon + 0 : undef,
    timezone    => $timezoneFromApi,
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
    my $resCurrent = apiCall(
        url => "$url/observations/location?api_key=$apikey&build=175&location_id=$stationid&units_temp=c&units_wind=kph&units_pressure=mb&units_distance=km&units_precip=mm&units_other=metric&units_direction=cardinal",
        maskkeys => $maskKeys,
        keyparam => 'api_key',
        info => "for location $stationid (accurate current observation data)",
    );

    my $cur = $resCurrent->{obs}->[0];
    my $cc  = $results->{current_conditions};

    # Update location elevation from observation data
    if (defined $resCurrent->{elevation}) {
        $location->{elevation} = $resCurrent->{elevation} + 0;
    }

    my $currentEpoch = $cc->{time};
    my $dtCurrent = _epochToIso($currentEpoch, $timezone);
    LOGINF "Reading current weather data from API response into W4L structure. Observation time was $dtCurrent.";

    # time
    my %time;
    $time{datetime}  = $dtCurrent;                                                                 # cur_date_des - is always in local time of Loxberry
    $time{epoch}     = $currentEpoch;                                                              # cur_date     - is always in UNIX epoch time

    # cur_date_tz_des (e.g. Europe/Berlin), cur_date_tz_des_sh (e.g. "CET"), cur_date_tz (e.g. "+0100") are send in location section 

    # sunrise / sunset
    my ($sunrise, $sunset);
    if (defined $results->{forecast}->{daily}->[0]->{sunrise}) {
        my $t_sr = localtime($results->{forecast}->{daily}->[0]->{sunrise});
        $sunrise = sprintf("%02d:%02d", $t_sr->hour, $t_sr->min);
    }
    if (defined $results->{forecast}->{daily}->[0]->{sunset}) {
        my $t_ss = localtime($results->{forecast}->{daily}->[0]->{sunset});
        $sunset = sprintf("%02d:%02d", $t_ss->hour, $t_ss->min);
    }

    # temperature
    my %temperature;
    $temperature{air}       = defined $cur->{air_temperature} ? sprintf("%.1f", $cur->{air_temperature}) + 0 : undef;
    $temperature{feelsLike} = defined $cur->{feels_like}      ? sprintf("%.1f", $cur->{feels_like}) + 0      : undef;
    $temperature{windChill} = defined $cur->{wind_chill}      ? sprintf("%.1f", $cur->{wind_chill}) + 0      : undef;
    $temperature{heatIndex} = defined $cur->{heat_index}      ? sprintf("%.1f", $cur->{heat_index}) + 0      : undef;

    # wind - WeatherFlow provides km/h, unit is called kph (km per hour)
    my %wind;
    my $wdeg = $cur->{wind_direction};
    $wind{direction} = defined $wdeg ? $wdeg + 0 : undef;
    $wind{cardinal}  = getWindDirCardinal($wdeg);
    $wind{speed}     = defined $cur->{wind_avg}  ? sprintf("%.1f", $cur->{wind_avg}) + 0  : undef;
    $wind{gust}      = defined $cur->{wind_gust} ? sprintf("%.1f", $cur->{wind_gust}) + 0 : undef;

    # precipitation
    my %precipitation;
    $precipitation{rainToday}    = defined $cur->{precip_accum_local_day} ? sprintf("%.2f", $cur->{precip_accum_local_day}) + 0 : undef;
    $precipitation{rain1hr}      = defined $cur->{precip_accum_last_1hr} ? sprintf("%.2f", $cur->{precip_accum_last_1hr}) + 0 : undef;
    $precipitation{probability}  = defined $results->{forecast}->{daily}->[0]->{precip_probability} ? sprintf("%.0f", $results->{forecast}->{daily}->[0]->{precip_probability}) + 0 : undef;
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
        pressure       => defined $cur->{station_pressure}   ? sprintf("%.0f", $cur->{station_pressure}) + 0   : undef,
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

    for my $resDay ( @{$results->{forecast}->{daily}} ) {

        # time
        my %time;
        $time{datetime} = _epochToIso($resDay->{day_start_local}, $timezone);
        $time{epoch}    = $resDay->{day_start_local};

        # sunrise / sunset
        my ($sunrise, $sunset);
        if (defined $resDay->{sunrise}) {
            my $t_sr = localtime($resDay->{sunrise});
            $sunrise = sprintf("%02d:%02d", $t_sr->hour, $t_sr->min);
        }
        if (defined $resDay->{sunset}) {
            my $t_ss = localtime($resDay->{sunset});
            $sunset = sprintf("%02d:%02d", $t_ss->hour, $t_ss->min);
        }

        # temperature
        my %tempMax;
        $tempMax{air}       = defined $resDay->{air_temp_high} ? sprintf("%.1f", $resDay->{air_temp_high}) + 0 : undef;
        $tempMax{feelsLike} = undef;  # not available from WeatherFlow daily
        $tempMax{heatIndex} = undef;  # not available from WeatherFlow daily

        my %tempMin;
        $tempMin{air}       = defined $resDay->{air_temp_low} ? sprintf("%.1f", $resDay->{air_temp_low}) + 0 : undef;
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
        $precipitation{probability} = defined $resDay->{precip_probability} ? sprintf("%.0f", $resDay->{precip_probability}) + 0 : undef;
        $precipitation{rainHigh}    = undef;  # not available from WeatherFlow daily
        $precipitation{rainLow}     = undef;  # not available from WeatherFlow daily
        $precipitation{snowHigh}    = undef;  # not available from WeatherFlow daily
        $precipitation{snowLow}     = undef;  # not available from WeatherFlow daily
        $precipitation{duration}    = undef;  # not available from WeatherFlow daily
        $precipitation{type}        = defined $resDay->{precip_type} ? $resDay->{precip_type} : undef;

        # weather codes
        my %weatherCode;
        my ($loxoneCode, $w4lCode) = weatherflow_to_lox($resDay->{icon});
        $weatherCode{loxone}      = $loxoneCode;
        $weatherCode{weather4lox} = $w4lCode;
        $weatherCode{description} = $resDay->{conditions};
        $weatherCode{image}       = undef;
        $weatherCode{metar}       = getMetarCode($w4lCode);

        # moon
        my %moon;
        my ($moonphase, $moonillum, $moonage) = (Astro::MoonPhase::phase($resDay->{day_start_local}))[0,1,2];
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

    for my $resHour ( @{$results->{forecast}->{hourly}} ) {

        # time
        my %time;
        $time{datetime} = _epochToIso($resHour->{time}, $timezone);
        $time{epoch}    = $resHour->{time};

        # temperature
        my %temperature;
        $temperature{air}       = defined $resHour->{air_temperature} ? sprintf("%.1f", $resHour->{air_temperature}) + 0 : undef;
        $temperature{feelsLike} = defined $resHour->{feels_like}      ? sprintf("%.1f", $resHour->{feels_like}) + 0      : undef;
        $temperature{heatIndex} = undef;  # not available from WeatherFlow hourly
        $temperature{windChill} = undef;  # not available from WeatherFlow hourly

        # wind - WeatherFlow provides km/h, unit is called kph (km per hour)
        my %wind;
        my $wdeg = $resHour->{wind_direction};
        $wind{direction} = defined $wdeg ? $wdeg + 0 : undef;
        $wind{cardinal}  = getWindDirCardinal($wdeg);
        $wind{speed}     = defined $resHour->{wind_avg} ? sprintf("%.1f", $resHour->{wind_avg}) + 0 : undef;
        $wind{gust}      = undef;  # not available from WeatherFlow hourly

        # precipitation
        my %precipitation;
        $precipitation{probability} = defined $resHour->{precip_probability} ? sprintf("%.0f", $resHour->{precip_probability}) + 0 : undef;
        $precipitation{rainHigh}    = defined $resHour->{precip} && $resHour->{precip} > 0 ? sprintf("%.2f", $resHour->{precip}) + 0 : undef;
        $precipitation{rainLow}     = undef;
        $precipitation{snowHigh}    = undef;  # not available from WeatherFlow hourly
        $precipitation{snowLow}     = undef;
        $precipitation{duration}    = undef;
        $precipitation{type}        = defined $resHour->{precip_type} ? $resHour->{precip_type} : undef;

        # weather codes
        my %weatherCode;
        my ($loxoneCode, $w4lCode) = weatherflow_to_lox($resHour->{icon});
        $weatherCode{loxone}       = $loxoneCode;
        $weatherCode{weather4lox}  = $w4lCode;
        $weatherCode{description}  = $resHour->{conditions};
        $weatherCode{metar}        = getMetarCode($w4lCode);

        # moon
        my %moon;
        my ($moonphase, $moonillum, $moonage) = (Astro::MoonPhase::phase($resHour->{time}))[0,1,2];
        $moon{age}       = sprintf("%.2f", $moonage) + 0;
        $moon{percent}   = sprintf("%.2f", $moonillum * 100) + 0;
        $moon{phase}     = sprintf("%.2f", $moonphase * 100) + 0;
        $moon{direction} = getMoonDirection($moonage);

        push @hourlyData, {
            hour           => $hour,
            time           => \%time,
            temperature    => \%temperature,
            humidity       => defined $resHour->{relative_humidity} ? $resHour->{relative_humidity} + 0 : undef,
            wind           => \%wind,
            pressure       => defined $resHour->{station_pressure} ? sprintf("%.0f", $resHour->{station_pressure}) + 0 : undef,
            dewpoint       => undef,       # not available from WeatherFlow hourly
            visibility     => undef,       # not available from WeatherFlow hourly
            solarRadiation => undef,       # not available from WeatherFlow hourly
            uvIndex        => defined $resHour->{uv} ? sprintf("%.1f", $resHour->{uv}) + 0 : undef,
            precipitation  => \%precipitation,
            weatherCode    => \%weatherCode,
            cloudCover     => undef,       # not available from WeatherFlow hourly
            moon           => \%moon,
            isNight        => wfIsNight($resHour->{icon}),
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
