#!/usr/bin/perl

# grabber for fetching data from visualcrossing.com
# fetches weather data (current and forecast) from visualcrossing.com

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
my $url          = $pcfg->param("VISUALCROSSING.URL");
my $apikey       = $pcfg->param("VISUALCROSSING.APIKEY");
my $lang         = $pcfg->param("SERVER.LANG");
my $stationid    = $pcfg->param("SERVER.COORDLAT") . "," . $pcfg->param("SERVER.COORDLONG");
my $city         = $pcfg->param("SERVER.CITY");
my $country      = $pcfg->param("SERVER.COUNTRY");
my $maskKeys     = $pcfg->param("SERVER.MASKKEYS");

# Grabber metadata for JSON envelope
my $grabberKey   = "visualcrossing";
my $grabberLabel = "Visual Crossing";
my $grabberFile  = "grabber_visualcrossing.pl";
my $refresh         = $pcfg->param("SERVER.CRON") // 60;

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'grabber_visualcrossing',
	logdir => "$lbplogdir",
);

# Commandline options
my $verbose = '';
my $current = '';
my $daily = '';
my $hourly = '';
my $observations = '';
my $incremental = '';

GetOptions ('verbose' => \$verbose,
            'interval=i' => \$refresh,
            'quiet'   => sub { $verbose = 0 },
            'current' => \$current,
            'daily' => \$daily,
            'hourly' => \$hourly,
            'observations' => \$observations,
            'incremental' => \$incremental,
			'maskkeys' => \$maskKeys,
			);

if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGSTART "Weather4Lox GRABBER_VISUALCROSSING process started";
LOGDEB "This is $0 Version $version";

requireOrLogdie('Astro::MoonPhase');

# all values in current, daily, and hourly JSONs are in local time, so proper time zone information is important
my $timezone = _systemTimezone();
LOGDEB "Using timezone: $timezone, current local system time is " . localtime->datetime;

# Get data from www.visualcrossing.com (API request) for current conditions, daily and hourly forecasts
my $results = apiCall(
	url => "$url/$stationid?unitGroup=metric&lang=$lang&iconSet=icons2&include=days,hours,current&key=$apikey&contentType=json",
	maskkeys => $maskKeys,
	keyparam => 'key',
	info => "for location $stationid (current, daily, and hourly weather data)",
);

# API documentation: https://www.visualcrossing.com/resources/documentation/weather-api/timeline-weather-api/

my $i;

# Convert Visual Crossing weather icon string into Loxone picto-code and icon name
# Weather icons: https://www.visualcrossing.com/resources/documentation/weather-api/defining-icon-set-in-the-weather-api/
# Loxone weather codes: https://www.loxone.com/enen/kb/weather-service/
# Weather4lox mapping: https://wiki.loxberry.de/plugins/weather4loxone/start#wetter-codes
# Mapping: Visual Crossing Weather Icon Name => [Loxone Code, Normalized Icon Name]

# NOTE: pre-mapping, see below
my %vc_to_lox = (
    "clear"          => [ 1, "clear"],                   #  1 = Clear / Wolkenlos
    "fair"           => [ 2, "fair"],                    #  2 = Fair / Heiter
    "partlycloudy"   => [ 3, "partly_cloudy"],           #  3 = Partly Cloudy / Teilweise bewölkt
    "cloudy"         => [ 4, "cloudy"],                  #  4 = Cloudy / Bewölkt
    "overcast"       => [ 5, "overcast"],                #  5 = Overcast / Bedeckt
    "snow"           => [21, "overcast_snow_2"],         # 21 = Snow / Schneefall
    "snowshowers"    => [24, "cloudy_snow_2"],           # 24 = Strong Snow Showers / Starker Schneeschauer
    "thunderrain"    => [18, "overcast_thunderstorm_2"], # 18 = Thunderstorms / Gewitter
    "thundershowers" => [18, "cloudy_thunderstorm_2"],   # 18 = Thunderstorms / Gewitter
    "rain"           => [11, "overcast_rain_2"],         # 11 = Rain / Regen
    "showers"        => [17, "cloudy_shower_2"],         # 17 = Heavy Rain Showers / Kräftiger Regenschauer
    "fog"            => [ 6, "fog"],                     #  6 = Fog / Nebel
    "wind"           => [ 5, "wind"],                    #  5 = Overcast / Bedeckt in Loxone, but there is no better match for "wind"
);

sub vc_to_lox {
    my ($weather_raw, $cloudCover) = @_;

    # Normalize the name of the weather icon from Visual Crossing
    my $weather = lc($weather_raw);        # Lowercase
    $weather =~ s/-(?:night|day)//;        # Remove -night and -day
    $weather =~ s/-//g;                    # Remove all hyphens

    # pre-mapping from three grades for cloudiness (clear 0-19%, partly-cloudy 20-89%, cloudy 90-100%) to five grades 
    if (defined $cloudCover && ($weather eq "clear" || $weather eq "partlycloudy" || $weather eq "cloudy")) {
        if ($cloudCover <= 10) {
            $weather = "clear";
        } elsif ($cloudCover <= 25) {
            $weather = "fair";
        } elsif ($cloudCover <= 50) {
            $weather = "partlycloudy";
        } elsif ($cloudCover <= 86) {
            $weather = "cloudy";
        } else {
            $weather = "overcast";
        }
    }

    # Lookup in the hash
    my $result = $vc_to_lox{$weather};

    if ($result) {
        return ($result->[0], $result->[1]);  # (code, icon)
    } else {
        # Fallback
        LOGDEB "Unknown weather icon name from Visual Crossing: '$weather_raw' (normalized: '$weather'). Using fallback 'clear'.";
        return (1, "clear");
    }
}

# Determine if it's currently nighttime based on current time, sunrise/sunset times (all epoch times on the same day)
sub isNighttime {
    my ($time, $sunrise, $sunset) = @_;
    my $isNighttime = undef; # default to day (undef)

    if ($time < $sunrise || $time > $sunset) {
        $isNighttime = 1;
    }
    return ($isNighttime);
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
my $weatherKey;
my $envelope;

# Derive timezone short name and offset from current epoch
my $currentEpoch = $results->{currentConditions}->{datetimeEpoch};

# Use local time for generatedAt timestamp
my $generatedAt = localtime->datetime;

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
    countryCode => undef,                 # not available from VC API
    elevation   => undef,                 # not available from VC API
    latitude    => defined $lat ? $lat + 0 : undef,
    longitude   => defined $lon ? $lon + 0 : undef,
    timezone    => $timezoneFromApi,
    tzOffset    => $tzOffset,
    tzShort     => $tzShort,
};

##########################################################################
# Fetch current data
##########################################################################

my %currentData;

# observations for last hours and days need current hour
if ($observations) {
    $current = 1;
}

if ( $current ) {

    my $cur = $results->{currentConditions};

    my $currentEpoch = $cur->{datetimeEpoch};
    my $dtCurrent = _epochToIso($currentEpoch, $timezone);
    LOGINF "Reading current weather data from API response into W4L structure. Observation time was $dtCurrent.";

    # time
    my %time;
    $time{datetime}  = $dtCurrent;                                                                 # cur_date_des - is always in local time of Loxberry
    $time{epoch}     = $currentEpoch;                                                              # cur_date     - is always in UNIX epoch time

    # cur_date_tz_des (e.g. Europe/Berlin), cur_date_tz_des_sh (e.g. "CET"), cur_date_tz (e.g. "+0100") are send in location section 

    # sunrise / sunset in epoch time, convert to local time of location and format as HH:MM
    my $sunriseEpoch = getValue($cur, 'sunriseEpoch');
    my $sunsetEpoch  = getValue($cur, 'sunsetEpoch');

    # temperature
    my %temperature;
    $temperature{air}       = getFormatted('%.1f', $cur, 'temp');                                  # cur_tt     - air temperature in °C
    $temperature{feelsLike} = getFormatted('%.1f', $cur, 'feelslike');                             # cur_tt_fl  - feels like temperature in °C
    # Wind chill is not provided separately by VC, but if feels like is lower than actual temp, it can be used as wind chill
    $temperature{windChill} =  $temperature{feelsLike} && $temperature{feelsLike} < $temperature{air} ? $temperature{feelsLike} : undef;      # cur_w_ch - wind chill in °C
    # Heat index is not provided separately by VC, but if feels like is higher than actual temp, it can be used as heat index
    $temperature{heatIndex} =  $temperature{feelsLike} && $temperature{feelsLike} > $temperature{air} ? $temperature{feelsLike} : undef;      # cur_hi     - heat index 

    # wind
    my %wind;
    my $wdeg = getFormatted('%.0f', $cur, 'winddir');
    $wind{direction} = $wdeg;                                                                      # cur_w_dir   - wind direction in degrees
    $wind{cardinal}  = getWindDirCardinal($wdeg);                                                  #             - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
    $wind{speed}     = getFormatted('%.1f', $cur, 'windspeed');                                    # cur_w_sp.   - wind speed in km/h
    $wind{gust}      = getFormatted('%.1f', $cur, 'windgust');                                     # cur_w_gu.   - gust speed in km/h

    # precipitation
    my %precipitation;
    $precipitation{rain1hr}      = getFormatted('%.1f', $cur, 'precip');                           # cur_prec_1h, 1-hour precipitation in mm
    $precipitation{probability}  = getFormatted('%.0f', $cur, 'precipprob');                       # cur_pop, probability in percent, API provides as decimal (e.g. 0.25 for 25%)
    $precipitation{type}         = getValue($cur, 'preciptype', 0);                                # type of precipitation (rain, snow), undef, if it is currently not raining/snowing
    $precipitation{snow1hr}      = getFormattedMultiplied('%.1f', 0.1, $cur, 'snow');               # cur_snow_1h, 1-hour snow in cm, API provides as mm

    $precipitation{rainToday} = 0;                                                                 # cur_prec_today, available from VC via past hours and observations
    $precipitation{snowToday} = 0;                                                                 # cur_snow_today, available from VC via past hours and observations
    my $todayDay = $results->{days}[0];
    for my $resHour ( @{$todayDay->{hours}} ) {

        # Add precipitation of past hours of the current day to rainToday and snowToday (source is "obs" = observations for past hours, "fcst" = forecast for future hours in VC API)
        my $hourEpoch = getValue($resHour, 'datetimeEpoch');
        my $hfctime = localtime($hourEpoch);
        my $source = getValue($resHour, 'source');
        if ($source eq "obs") {
            $precipitation{rainToday} += getFormatted('%.1f', $resHour, 'precip');
            $precipitation{snowToday} += getFormattedMultiplied('%.1f', 0.1, $resHour, 'snow');
        }
    }

    # weather codes
    my $iconRaw = $cur->{icon};
    my $cloudCover = getFormatted('%.1f', $cur, 'cloudcover');
    my %weatherCode;
    my ($loxoneCode, $w4lCode) = vc_to_lox($iconRaw, $cloudCover);
    $weatherCode{loxone}      = $loxoneCode;                                                       # cur_code
    $weatherCode{weather4lox} = $w4lCode;                                                          # cur_icon
    $weatherCode{description} = getValue($cur, 'conditions');                                      # cur_des
    $weatherCode{image}       = $iconRaw;                                                          # future use, e.g. as background image
    $weatherCode{metar}       = getMetarCode($w4lCode);                                            # future use, e.g. scientific theme

    # moon
    my %moon;
    my ($moonphase, $moonillum, $moonage) = (Astro::MoonPhase::phase())[0,1,2];
    $moon{age}       = sprintf("%.2f", $moonage) + 0;                                              # cur_moon_a, moon age in days
    $moon{percent}   = sprintf("%.2f", $moonillum * 100) + 0;                                      # cur_moon_p, moon illumination in percent
    $moon{phase}     = sprintf("%.2f", $moonphase * 100) + 0;                                      # cur_moon_ph, moon phase in percent (0% = new moon, 50% = half moon, 100% = full moon)
    $moon{direction} = getMoonDirection($moonage);                                                 #                - moon direction (waxing, waning)

    # Build current data hash
    %currentData = (
        time           => \%time,
        sunrise        => getTimeFromEpochFormatted('%H:%M', $timezoneFromApi, $sunriseEpoch),     # cur_sun_r
        sunset         => getTimeFromEpochFormatted('%H:%M', $timezoneFromApi, $sunsetEpoch),      # cur_sun_s
        temperature    => \%temperature,
        humidity       => getFormatted('%.0f', $cur, 'humidity'),                                  # cur_hu, in percentage
        wind           => \%wind,
        pressure       => getFormatted('%.0f', $cur, 'pressure'),                                  # cur_pr, air pressure in hPa
        dewpoint       => getFormatted('%.1f', $cur, 'dew'),                                       # cur_dp, dew point in °C
        visibility     => getFormatted('%.2f', $cur, 'visibility'),                                # cur_vis, visibility in km

        solarRadiation => getFormatted('%.1f', $cur, 'solarradiation'),                            # cur_sr, solar radiation in W/m²
        uvIndex        => getFormatted('%.0f', $cur, 'uvindex'),                                   # cur_uvi, UV index
        precipitation  => \%precipitation,
        weatherCode    => \%weatherCode,
                                                                                                   # cur_oz, ozone in DU, not available from VC API
        cloudCover     => $cloudCover,                                                             # cloud cover in percentage     
        moon           => \%moon,
        isNight        => isNighttime($time{epoch}, $sunriseEpoch, $sunsetEpoch),                  # to use day or night icon for icon sets that have this feature
    );

    # Build envelope and write JSON to file
    $weatherKey = "current";
    $envelope = {
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

    for my $resDay ( @{$results->{days}} ) {

        # time
        my $dayEpoch = $resDay->{datetimeEpoch};
        my $dtDay = _epochToIso($dayEpoch, $timezone);           # ISO 8601 date string in local time, e.g. 2026-03-13T02:00:00+01:00

        my %time;
        $time{datetime} = $dtDay;
        $time{epoch}    = $dayEpoch;

        if ($day < 3) {
            LOGDEB "Adding daily forecast (dfc${day}_...) for $dtDay (epoch: $dayEpoch).";
        } 

        # sunrise / sunset in epoch time, convert to local time of location and format as HH:MM
        my $sunriseEpoch = getValue($resDay, 'sunriseEpoch');
        my $sunsetEpoch = getValue($resDay, 'sunsetEpoch');

        # temperature
        my %tempMax;
        $tempMax{air}       = getFormatted('%.1f', $resDay, 'tempmax');                            # dfc<X>_tt_h      - daily max temperature (°C)
        $tempMax{feelsLike} = getFormatted('%.1f', $resDay, 'feelslikemax');                       # dfc<X>_tt_fl_h   - max feels-like temperature
        $tempMax{heatIndex} = undef;                                                               # dfc<X>_hi_h      - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures

        my %tempMin;
        $tempMin{air}       = getFormatted('%.1f', $resDay, 'tempmin');                            # dfc<X>_tt_l      - daily min temperature (°C)
        $tempMin{feelsLike} = getFormatted('%.1f', $resDay, 'feelslikemin');                       # dfc<X>_tt_fl_l   - min feels-like temperature
        $tempMin{windChill} = undef;  #                                                            # dfc<X>_hi_l      - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures

        # wind - VC provides only one set of wind data per day, use for both avg and max
        my $windDir = getFormatted('%.0f', $resDay, 'winddir');
        my %windAvg;
        $windAvg{direction} = $windDir;                                                            # dfc<X>_w_dir_a   - wind direction (degree)
        $windAvg{cardinal}  = getWindDirCardinal($windDir);                                        #                  - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
        $windAvg{speed}     = getFormatted('%.1f', $resDay, 'windspeed');                          # dfc<X>_w_sp_a    - average wind speed in km/h
        $windAvg{gust}      = getFormatted('%.1f', $resDay, 'windgust');                           # dfc<X>_w_gu_a    - average gust speed in km/h, not ideal but VC provides only one gust value per day, use for avg

        # VC has no separate max wind data, duplicate avg
        my %windMax = %windAvg;

        # humidity - VC provides only one humidity value per day
        my %humidity;
        $humidity{avg} = getFormatted('%.1f', $resDay, 'humidity');                                # dfc<X>_hu_a      - average humidity
        $humidity{max} = undef;  	                                                               # dfc<X>_hu_l      - minimum humidity, not available from VC
        $humidity{min} = undef;                                                                    # dfc<X>_hu_h      - maximum humidity, not available from VC

        # precipitation
        my %precipitation;
        $precipitation{probability} = getFormatted('%.0f', $resDay, 'precipprob');                 # dfc<X>_pop        - probability of precipitation (%)
        $precipitation{rainHigh}    = getFormatted('%.1f', $resDay, 'precip');                     # dfc<X>_prec       - precipitation (mm)
        $precipitation{snowHigh}    = getFormatted('%.1f', $resDay, 'snow');                       # dfc<X>_snow       - snow height (cm)
        $precipitation{duration}    = undef;                                                       #                   - duration of precipitation, not available from VC
        $precipitation{type}        = getValue($resDay, 'preciptype', 0 );                         #                   - precipitation type

        # weather codes
        my $iconRaw = getValue($resDay, 'icon');
        my $cloudCover = getFormatted('%.1f',$resDay, 'cloudcover');
        my %weatherCode;
        my ($loxoneCode, $w4lCode) = vc_to_lox($iconRaw, $cloudCover);
        $weatherCode{loxone}      = $loxoneCode;                                                   # dfc<X>_we_code   - Loxone code
        $weatherCode{weather4lox} = $w4lCode;                                                      # dfc<X>_we_icon   - Weather4Lox icon code
        $weatherCode{description} = getValue($resDay, 'description');                              # dfc<X>_we_des    - description
        $weatherCode{image}       = undef;                                                         #                  - future use., e.g. as background image
        $weatherCode{metar}       = getMetarCode($w4lCode);                                        #                  - METAR code

        # moon
        my %moon;
        my ($moonphase, $moonillum, $moonage) = (Astro::MoonPhase::phase($resDay->{datetimeEpoch}))[0,1,2];
        $moon{age}       = sprintf("%.1f", $moonage) + 0;                                          # dfc<X>_moon_a    - moon age in days
        $moon{percent}   = sprintf("%.1f", $moonillum * 100) + 0;                                  # dfc<X>_moon_p    - moon percent illumination
        $moon{phase}     = sprintf("%.1f", $moonphase * 100) + 0;                                  # dfc<X>_moon_ph   - moon phase
        $moon{direction} = getMoonDirection($moonage);                                             #                  - moon direction (waxing, waning)
        $moon{rise}      = undef;                                                                  #                  - moon rise in HH:MM in local time, not available from VC
        $moon{set}       = undef;                                                                  #                  - moon set in HH:MM in local time, not available from VC

        push @dailyData, {
            day            => $day,
            time           => \%time,
            sunrise        => getTimeFromEpochFormatted('%H:%M', $timezoneFromApi, $resDay, 'sunriseEpoch'),         # dfc<X>_sun_r     - sunrise time (HH:MM) from Unix epoch time
            sunset         => getTimeFromEpochFormatted('%H:%M', $timezoneFromApi, $resDay, 'sunsetEpoch'),          # dfc<X>_sun_s     - sunset time (HH:MM) from Unix epoch time
            temperature    => { max => \%tempMax, min => \%tempMin },
            wind           => { avg => \%windAvg, max => \%windMax },
            humidity       => \%humidity,
            pressure       => getFormatted('%.0f', $resDay, 'pressure'),                           # dfc<X>_pr        - air pressure (hPa)
            dewpoint       => getFormatted('%.1f', $resDay, 'dew'),                                # dfc<X>_dp        - average dew point (°C)
            precipitation  => \%precipitation,
            weatherCode    => \%weatherCode,
            moon           => \%moon,
            uvIndex        => getFormatted('%.1f', $resDay, 'uvindex'),                            # dfc<X>_uvi       - UV index, maximum value for the day
            visibility     => getFormatted('%.2f', $resDay, 'visibility'),                         # cur_vis, visibility in km
            cloudCover     => $cloudCover,                                                         # cloud cover in percentage     
        };
        $day++;
    }

    LOGDEB "Adding additional daily forecasts without detailed logging ... " . $day . " daily forecasts were added.";

    # Build envelope and write JSON to file
    $weatherKey = "dailyforecast";
    $envelope = {
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

    my $nowEpoch = time();

    LOGINF "Reading hourly weather data from API response into W4L structure. Starting from current time " . _epochToIso($nowEpoch, $timezone) . " (epoch: $nowEpoch).";

    for my $resDay ( @{$results->{days}} ) {

        # sunrise / sunset in epoch time, convert to local time of location and format as HH:MM
        my $sunriseEpoch = getValue($resDay, 'sunriseEpoch');
        my $sunsetEpoch = getValue($resDay, 'sunsetEpoch');

        for my $resHour ( @{$resDay->{hours}} ) {

            # Skip observations (hourly data also contains weather observations for current day in addition to forecast hours)
            my $source = getValue($resHour, 'source');
            next if $source eq "obs";

            # Skip past hours (based on epoch time of the forecast hour and current epoch time)
            my $hourEpoch = getValue($resHour, 'datetimeEpoch');
            next if $hourEpoch <= $nowEpoch;
            my $dtHour = _epochToIso($hourEpoch, $timezone);

            if ($hour < 10) {
                LOGDEB "Adding hourly forecast (hfc${hour}_...) for $dtHour (epoch: $hourEpoch).";
            } 
 
            # time
            my %time;
            $time{datetime} = $dtHour;
            $time{epoch}    = $hourEpoch;

            # temperature
            my %temperature;
            $temperature{air}       = getFormatted('%.1f', $resHour, 'temp');                      # hfc<X>_tt        - daily max temperature (°C)
            $temperature{feelsLike} = getFormatted('%.1f', $resHour, 'feelslike');                 # hfc<X>_tt_fl     - min feels-like temperature
            $temperature{heatIndex} = undef;
            $temperature{windChill} = undef;

            # wind
            my %wind;
            my $windDir = getFormatted('%.0f', $resHour, 'winddir');
            $wind{direction} = $windDir;                                                           # hfc<X>_w_dir     - wind direction (degree)
            $wind{cardinal}  = getWindDirCardinal($windDir);                                       #                  - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
            $wind{speed}     = getFormatted('%.1f', $resHour, 'windspeed');                        # hfc<X>_w_sp      - wind speed (km/h)
            $wind{gust}      = getFormatted('%.1f', $resHour, 'windgust');                         # hfc<X>_w_sp      - wind gust (km/h)

            # precipitation
            my %precipitation;
            $precipitation{probability} = getFormatted('%.0f', $resHour, 'precipprob');            # hfc<X>_pop         - probability of precipitation (%)
            $precipitation{rainHigh}    = getFormatted('%.1f', $resHour, 'precip');                # hfc<X>_prec        - precipitation (mm)
            $precipitation{snowHigh}    = getFormattedMultiplied('%.1f', 0.1, $resHour, 'snow');   # hfc<X>_snow        - snow height (cm)
            $precipitation{duration}    = undef;
            $precipitation{type}        = getValue($resHour, 'preciptype');                        #                    - precipitation type

            # weather codes
            my $iconRaw = getValue($resHour, 'icon');
            my $cloudCover = getFormatted('%.1f',$resHour, 'cloudcover');
            my %weatherCode;
            my ($loxoneCode, $w4lCode) = vc_to_lox($iconRaw, $cloudCover);
            $weatherCode{loxone}      = $loxoneCode;                                               # hfc<X>_we_code   - Loxone code
            $weatherCode{weather4lox} = $w4lCode;                                                  # hfc<X>_we_icon   - Weather4Lox icon code
            $weatherCode{description} = getValue($resHour, 'conditions');                          # hfc<X>_we_des    - description
            $weatherCode{metar}       = getMetarCode($w4lCode);                                    #                  - METAR code

            # moon
            my %moon;
            my ($moonphase, $moonillum, $moonage) = (Astro::MoonPhase::phase($hourEpoch))[0,1,2];
            $moon{age}       = sprintf("%.2f", $moonage) + 0;                                      # hfc<X>_moon_a    - moon age in days
            $moon{percent}   = sprintf("%.2f", $moonillum * 100) + 0;                              # hfc<X>_moon_p    - moon percentage illumination
            $moon{phase}     = sprintf("%.2f", $moonphase * 100) + 0;                              # hfc<X>_moon_ph   - moon phase
            $moon{direction} = getMoonDirection($moonage);                                         #                  - moon direction (waxing, waning)

            push @hourlyData, {
                hour           => $hour,
                time           => \%time,
                temperature    => \%temperature,
                humidity       => getFormatted('%.1f', $resHour, 'humidity'),                      # hfc<X>_hu        - humidity in percentage
                wind           => \%wind,
                pressure       => getFormatted('%.0f', $resHour, 'pressure'),                      # hfc<X>_pr        - air pressure (hPa)
                dewpoint       => getFormatted('%.1f', $resHour, 'dew'),                           # hfc<X>_dp        - dew point (°C)
                visibility     => getFormatted('%.0f', $resHour, 'visibility'),                    # hfc<X>_vis       - visibility (m/km as needed)
                solarRadiation => getFormatted('%.1f', $resHour, 'solarradiation'),                # hfc<X>_sr        - solar radiation in W/m²
                uvIndex        => getFormatted('%.1f', $resHour, 'uvindex'),                       # hfc<X>_uvi       - UV index
                precipitation  => \%precipitation,
                weatherCode    => \%weatherCode,
                                                                                                   # hfc<X>_oz        - ozone in DU, not available from VC API
                cloudCover     => $cloudCover,                                                     # hfc<X>_sky       - cloud/sky cover (percentage from 0 to 100)
                moon           => \%moon,
                isNight        => isNighttime($hourEpoch, $sunriseEpoch, $sunsetEpoch),            # to use day or night icon for icon sets that have this feature
            };
            $hour++;
        }
    }
    $hour--;
    LOGDEB "Adding additional hourly forecasts without detailed logging ... $hour hourly forecasts were added.";

    # Build envelope and write JSON to file
    $weatherKey = "hourlyforecast";
    $envelope = {
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

##########################################################################
# Fetch observation data for the last hours and days
##########################################################################

if ( $observations ) {

    # Get data from www.visualcrossing.com (API request) for observations
    my $results = apiCall(
        url => "$url/$stationid/last3days?unitGroup=metric&lang=$lang&iconSet=icons2&include=obs,days,hours,current&key=$apikey&contentType=json",
        maskkeys => $maskKeys,
        keyparam => 'key',
        info => "for Location $stationid (Observations for the last 3 days)",
    );

    my @dailyData;
    my $day = 0;               # used for days, starts with 0 for current day, 1 for yesterday, etc.

    LOGINF "Reading daily weather observations from API response into W4L structure.";

    # Refresh time for observations, use local time for generatedAt timestamp
    $generatedAt = localtime->datetime;

    for my $resDay ( reverse @{$results->{days}} ) {

        # time
        my %time;
        $time{datetime} = _epochToIso($resDay->{datetimeEpoch}, $timezoneFromApi);
        $time{epoch}    = $resDay->{datetimeEpoch};

        # sunrise / sunset in epoch time, convert to local time of location and format as HH:MM
        my $sunriseEpoch = getValue($resDay, 'sunriseEpoch');
        my $sunsetEpoch = getValue($resDay, 'sunsetEpoch');

        # temperature
        my %tempMax;
        $tempMax{air}       = getFormatted('%.1f', $resDay, 'tempmax');                            # dob<X>_tt_h      - daily max temperature (°C)
        $tempMax{feelsLike} = getFormatted('%.1f', $resDay, 'feelslikemax');                       # dob<X>_tt_fl_h   - max feels-like temperature
        $tempMax{heatIndex} = undef;                                                               # dob<X>_hi_h      - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures

        my %tempMin;
        $tempMin{air}       = getFormatted('%.1f', $resDay, 'tempmin');                            # dob<X>_tt_l      - daily min temperature (°C)
        $tempMin{feelsLike} = getFormatted('%.1f', $resDay, 'feelslikemin');                       # dob<X>_tt_fl_l   - min feels-like temperature
        $tempMin{windChill} = undef;                                                               # dob<X>_hi_l      - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures

        # wind - VC provides only one set of wind data per day, use for both avg and max
        my $windDir = getFormatted('%.0f', $resDay, 'winddir');
        my %windAvg;
        $windAvg{direction} = $windDir;                                                            # dob<X>_w_dir_a   - wind direction (degree)
        $windAvg{cardinal}  = getWindDirCardinal($windDir);                                        #                  - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
        $windAvg{speed}     = getFormatted('%.1f', $resDay, 'windspeed');                          # dob<X>_w_sp_a    - average wind speed in km/h
        $windAvg{gust}      = getFormatted('%.1f', $resDay, 'windgust');                           # dob<X>_w_gu_a    - average gust speed in km/h, not ideal but VC provides only one gust value per day, use for avg

        # VC has no separate max wind data, duplicate avg
        my %windMax = %windAvg;

        # humidity - VC provides only one humidity value per day
        my %humidity;
        $humidity{avg} = getFormatted('%.1f', $resDay, 'humidity');                                # dob<X>_hu_a      - average humidity
        $humidity{max} = undef;  	                                                               # dob<X>_hu_l      - minimum humidity, not available from VC
        $humidity{min} = undef;                                                                    # dob<X>_hu_h      - maximum humidity, not available from VC

        # precipitation
        my %precipitation;
        $precipitation{probability} = getFormatted('%.0f', $resDay, 'precipprob');                 # dob<X>_pop        - probability of precipitation (%)
        $precipitation{rainHigh}    = getFormatted('%.1f', $resDay, 'precip');                     # dob<X>_prec       - precipitation (mm)
        $precipitation{snowHigh}    = getFormatted('%.1f', $resDay, 'snow');                       # dob<X>_snow       - snow height (cm)
        $precipitation{duration}    = undef;                                                       #                   - duration of precipitation, not available from VC
        $precipitation{type}        = getValue($resDay, 'preciptype', 0 );                         #                   - precipitation type

        # weather codes
        my $iconRaw = getValue($resDay, 'icon');
        my $cloudCover = getFormatted('%.1f',$resDay, 'cloudcover');
        my %weatherCode;
        my ($loxoneCode, $w4lCode) = vc_to_lox($iconRaw, $cloudCover);
        $weatherCode{loxone}      = $loxoneCode;                                                   # dob<X>_we_code   - Loxone code
        $weatherCode{weather4lox} = $w4lCode;                                                      # dob<X>_we_icon   - Weather4Lox icon code
        $weatherCode{description} = getValue($resDay, 'description');                              # dob<X>_we_des    - description
        $weatherCode{image}       = undef;                                                         #                  - future use., e.g. as background image
        $weatherCode{metar}       = getMetarCode($w4lCode);                                        #                  - METAR code

        # moon
        my %moon;
        my ($moonphase, $moonillum, $moonage) = (Astro::MoonPhase::phase($resDay->{datetimeEpoch}))[0,1,2];
        $moon{age}       = sprintf("%.1f", $moonage) + 0;                                          # dob<X>_moon_a    - moon age in days
        $moon{percent}   = sprintf("%.1f", $moonillum * 100) + 0;                                  # dob<X>_moon_p    - moon percent illumination
        $moon{phase}     = sprintf("%.1f", $moonphase * 100) + 0;                                  # dob<X>_moon_ph   - moon phase
        $moon{direction} = getMoonDirection($moonage);                                             #                  - moon direction (waxing, waning)
        $moon{rise}      = undef;                                                                  #                  - moon rise in HH:MM in local time, not available from VC
        $moon{set}       = undef;                                                                  #                  - moon set in HH:MM in local time, not available from VC

        push @dailyData, {
            day            => $day,
            time           => \%time,
            sunrise        => getTimeFromEpochFormatted('%H:%M', $timezoneFromApi, $resDay, 'sunriseEpoch'),         # dob<X>_sun_r     - sunrise time (HH:MM) from Unix epoch time
            sunset         => getTimeFromEpochFormatted('%H:%M', $timezoneFromApi, $resDay, 'sunsetEpoch'),          # dob<X>_sun_s     - sunset time (HH:MM) from Unix epoch time
            temperature    => { max => \%tempMax, min => \%tempMin },
            wind           => { avg => \%windAvg, max => \%windMax },
            humidity       => \%humidity,
            pressure       => getFormatted('%.0f', $resDay, 'pressure'),                           # dob<X>_pr        - air pressure (hPa)
            dewpoint       => getFormatted('%.1f', $resDay, 'dew'),                                # dob<X>_dp        - average dew point (°C)
            precipitation  => \%precipitation,
            weatherCode    => \%weatherCode,
            moon           => \%moon,
            solarRadiation => getFormatted('%.1f', $resDay, 'solarradiation'),                     # dob<X>_sr        - solar radiation in W/m²
            solarEnergy    => getFormattedMultiplied('%.1f', 0.277778, $resDay, 'solarenergy'),    # dob<X>_se        - solar energy in MJ/m² → kWh/m² with multiplication factor 0.277778
            uvIndex        => getFormatted('%.1f', $resDay, 'uvindex'),                            # dob<X>_uvi       - UV index, maximum value for the day
            visibility     => getFormatted('%.2f', $resDay, 'visibility'),                         # dob<X>_vis       - visibility in km
            cloudCover     => $cloudCover,                                                         # dob<X>_cc        - cloud cover in percentage     
        };
        $day++;
    }

    # Build envelope and write JSON to file
    $weatherKey = "dailyobservations";
    $envelope = {
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

    my @hourlyData;
    # For observations, we use the same structure as for hourly forecast, but with different meaning of the hour index:
    # hour 1 is the first completed hour, hour 2 is the hour before, etc.
    # 0 is current hour which is not completed yet, but included in 'current' only and not in hourly observations
    my $hour = 1;               # used for hours, starts with 1 for first completed hour, 2 for hour before, etc. 

    # add current hours as first entry in hourly data, with hour index 0
    $currentData{hour} = 0;
    push @hourlyData, \%currentData;

    LOGINF "Reading hourly weather observations from API response into W4L structure.";

    for my $resDay ( reverse @{$results->{days}} ) {

        # sunrise / sunset in epoch time, convert to local time of location and format as HH:MM
        my $sunriseEpoch = getValue($resDay, 'sunriseEpoch');
        my $sunsetEpoch = getValue($resDay, 'sunsetEpoch');

        for my $resHour ( reverse @{$resDay->{hours}} ) {

            my $hourEpoch = getValue($resHour, 'datetimeEpoch');
 
            # time
            my %time;
            $time{datetime} = _epochToIso($hourEpoch, $timezoneFromApi);
            $time{epoch}    = $hourEpoch;

            # temperature
            my %temperature;
            $temperature{air}       = getFormatted('%.1f', $resHour, 'temp');                      # hob<X>_tt        - daily max temperature (°C)
            $temperature{feelsLike} = getFormatted('%.1f', $resHour, 'feelslike');                 # hob<X>_tt_fl     - min feels-like temperature
            $temperature{heatIndex} = undef;
            $temperature{windChill} = undef;

            # wind
            my %wind;
            my $windDir = getFormatted('%.0f', $resHour, 'winddir');
            $wind{direction} = $windDir;                                                           # hob<X>_w_dir     - wind direction (degree)
            $wind{cardinal}  = getWindDirCardinal($windDir);                                       #                  - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
            $wind{speed}     = getFormatted('%.1f', $resHour, 'windspeed');                        # hob<X>_w_sp      - wind speed (km/h)
            $wind{gust}      = getFormatted('%.1f', $resHour, 'windgust');                         # hob<X>_w_sp      - wind gust (km/h)

            # precipitation
            my %precipitation;
            $precipitation{probability} = getFormatted('%.0f', $resHour, 'precipprob');            # hob<X>_pop         - probability of precipitation (%)
            $precipitation{rainHigh}    = getFormatted('%.1f', $resHour, 'precip');                # hob<X>_prec        - precipitation (mm)
            $precipitation{snowHigh}    = getFormattedMultiplied('%.1f', 0.1, $resHour, 'snow');   # hob<X>_snow        - snow height (cm)
            $precipitation{duration}    = undef;
            $precipitation{type}        = getValue($resHour, 'preciptype');                        #                    - precipitation type

            # weather codes
            my $iconRaw = getValue($resHour, 'icon');
            my $cloudCover = getFormatted('%.1f',$resHour, 'cloudcover');
            my %weatherCode;
            my ($loxoneCode, $w4lCode) = vc_to_lox($iconRaw, $cloudCover);
            $weatherCode{loxone}      = $loxoneCode;                                               # hob<X>_we_code   - Loxone code
            $weatherCode{weather4lox} = $w4lCode;                                                  # hob<X>_we_icon   - Weather4Lox icon code
            $weatherCode{description} = getValue($resHour, 'conditions');                          # hob<X>_we_des    - description
            $weatherCode{metar}       = getMetarCode($w4lCode);                                    #                  - METAR code

            # moon
            my %moon;
            my ($moonphase, $moonillum, $moonage) = (Astro::MoonPhase::phase($hourEpoch))[0,1,2];
            $moon{age}       = sprintf("%.2f", $moonage) + 0;                                      # hob<X>_moon_a    - moon age in days
            $moon{percent}   = sprintf("%.2f", $moonillum * 100) + 0;                              # hob<X>_moon_p    - moon percentage illumination
            $moon{phase}     = sprintf("%.2f", $moonphase * 100) + 0;                              # hob<X>_moon_ph   - moon phase
            $moon{direction} = getMoonDirection($moonage);                                         #                  - moon direction (waxing, waning)

            push @hourlyData, {
                hour           => $hour,
                time           => \%time,
                temperature    => \%temperature,
                humidity       => getFormatted('%.1f', $resHour, 'humidity'),                      # hob<X>_hu        - humidity in percentage
                wind           => \%wind,
                pressure       => getFormatted('%.0f', $resHour, 'pressure'),                      # hob<X>_pr        - air pressure (hPa)
                dewpoint       => getFormatted('%.1f', $resHour, 'dew'),                           # hob<X>_dp        - dew point (°C)
                visibility     => getFormatted('%.0f', $resHour, 'visibility'),                    # hob<X>_vis       - visibility (m/km as needed)
                solarRadiation => getFormatted('%.1f', $resHour, 'solarradiation'),                # hob<X>_sr        - solar radiation in W/m²
                solarEnergy    => getFormattedMultiplied('%.1f', 0.277778, $resHour, 'solarenergy'),    # hob<X>_se        - solar energy in MJ/m² → kWh/m² with multiplication factor 0.277778
                uvIndex        => getFormatted('%.1f', $resHour, 'uvindex'),                       # hob<X>_uvi       - UV index
                precipitation  => \%precipitation,
                weatherCode    => \%weatherCode,
                                                                                                   # hob<X>_oz        - ozone in DU, not available from VC API
                cloudCover     => $cloudCover,                                                     # hob<X>_sky       - cloud/sky cover (percentage from 0 to 100)
                moon           => \%moon,
                isNight        => isNighttime($hourEpoch, $sunriseEpoch, $sunsetEpoch),            # to use day or night icon for icon sets that have this feature
            };
            $hour++;
        }
    }

    # Build envelope and write JSON to file
    $weatherKey = "hourlyobservations";
    $envelope = {
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

    # Give OK status to client.
    LOGOK "Current data, forecasts, and observations saved successfully.";

} else {

    # Give OK status to client.
    LOGOK "Current data and forecasts saved successfully.";

}# End observations


# Exit
exit;

END
{
	LOGEND;
}
