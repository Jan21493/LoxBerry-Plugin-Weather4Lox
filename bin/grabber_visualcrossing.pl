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
use Time::Seconds;
use DateTime;
#use Astro::MoonPhase;

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

LOGSTART "Weather4Lox GRABBER_VISUALCROSSING process started";
LOGDEB "This is $0 Version $version";

requireOrLogdie('Astro::MoonPhase');

# all values in current, daily, and hourly JSONs are in local time, so proper time zone information is important
my $timezone = _systemTimezone();
LOGDEB "Using timezone: $timezone";

# Get data from www.visualcrossing.com (API request) for current conditions, daily and hourly forecasts
my $results = apiCall(
	url => "$url/$stationid?unitGroup=metric&lang=$lang&iconSet=icons2&include=days,hours,current&key=$apikey&contentType=json",
	maskkeys => $maskkeys,
	keyparam => 'key',
	info => "for Location $stationid (Current, Daily, and Hourly Weather Data)",
);

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
my $generatedAt = DateTime->now( time_zone => $timezone );

# Timezone short and offset via POSIX
my ($tzShort, $tzOffset);
{
    local $ENV{TZ} = $timezoneFromApi;
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

if ( $current ) {

    my $cur = $results->{currentConditions};

    LOGINF "Reading current weather data from API response into W4L structure.";

    # time
    my %time;
    $time{datetime} = _epochToIso($cur->{datetimeEpoch}, $timezoneFromApi);
    $time{epoch}    = $cur->{datetimeEpoch};

    # cur_date_tz_des (e.g. Europe/Berlin), cur_date_tz_des_sh (e.g. "CET"), cur_date_tz (e.g. "+0100") are send in location section 

    # sunrise / sunset in epoch time, convert to local time of location and format as HH:MM
    my $sunriseEpoch = getValue($cur, 'sunriseEpoch');
    my $sunsetEpoch = getValue($cur, 'sunsetEpoch');

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
    $precipitation{rainToday}    = undef;                                                          # not available from VC current data
    $precipitation{rain1hr}      = getFormatted('%.1f', $cur, 'precip');                           # cur_prec_1h, 1-hour precipitation in mm
    $precipitation{probability}  = getFormatted('%.0f', $cur, 'precipprob');                       # cur_pop, probability in percent, API provides as decimal (e.g. 0.25 for 25%)
    $precipitation{type}         = getValue($cur, 'preciptype', 0);                                # type of precipitation (rain, snow), undef, if it is currently not raining/snowing
    $precipitation{snowToday}    = undef;                                                          # not available from VC current data
    $precipitation{snow1hr}      = getFormatted('%.1f', $cur, 'snow');

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
    my ($moonphase, $moonillum, $moonage) = (phase())[0,1,2];
    $moon{age}       = sprintf("%.2f", $moonage) + 0;                                              # cur_moon_a, moon age in days
    $moon{percent}   = sprintf("%.2f", $moonillum * 100) + 0;                                      # cur_moon_p, moon illumination in percent
    $moon{phase}     = sprintf("%.2f", $moonphase * 100) + 0;                                      # cur_moon_ph, moon phase in percent (0% = new moon, 50% = half moon, 100% = full moon)
    $moon{direction} = getMoonDirection($moonage);                                                 #                - moon direction (waxing, waning)

    # Build current data hash
    my %currentData = (
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
        generatedAt => $generatedAt->iso8601(),
        location    => $location,
        $grabberKey => {
            filename      => "$lbplogdir/$weatherKey.json",
            generatedAt   => $generatedAt->iso8601(),
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
        my %time;
        $time{datetime} = _epochToIso($resDay->{datetimeEpoch}, $timezoneFromApi);
        $time{epoch}    = $resDay->{datetimeEpoch};

        # sunrise / sunset in epoch time, convert to local time of location and format as HH:MM
        my $sunriseEpoch = getValue($resDay, 'sunriseEpoch');
        my $sunsetEpoch = getValue($resDay, 'sunsetEpoch');

        # temperature
        my %tempMax;
        $tempMax{air}       = getFormatted('%.1f', $resDay, 'tempmax');                            # dfc<X>_tt_h      - daily max temperature (°C)
        $tempMax{feelsLike} = getFormatted('%.1f', $resDay, 'feelslikemax'),                       # dfc<X>_tt_fl_h   - max feels-like temperature
        $tempMax{heatIndex} = undef;                                                               # dfc<X>_hi_h      - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures

        my %tempMin;
        $tempMin{air}       = getFormatted('%.1f', $resDay, 'tempmin');                            # dfc<X>_tt_l      - daily min temperature (°C)
        $tempMin{feelsLike} = getFormatted('%.1f', $resDay, 'feelslikemin'),                       # dfc<X>_tt_fl_l   - min feels-like temperature
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
        $humidity{avg} = getFormatted('%.1f', $resDay, 'humidity'),                                # dfc<X>_hu_a      - average humidity
        $humidity{max} = undef;  	                                                               # dfc<X>_hu_l      - minimum humidity, not available from VC
        $humidity{min} = undef;                                                                    # dfc<X>_hu_h      - maximum humidity, not available from VC

        # precipitation
        my %precipitation;
        $precipitation{probability} = getFormatted('%.0f', $resDay, 'precipprob'),                 # dfc<X>_pop        - probability of precipitation (%)
        $precipitation{rainHigh}    = getFormatted('%.1f', $resDay, 'precip'),                     # dfc<X>_prec       - precipitation (mm)
        $precipitation{snowHigh}    = getFormatted('%.1f', $resDay, 'snow'),                       # dfc<X>_snow       - snow height (cm)
        $precipitation{duration}    = undef;                                                       #                   - duration of precipitation, not available from VC
        $precipitation{type}        = getValue($resDay, 'preciptype', 0 ),                         #                   - precipitation type

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
        my ($moonphase, $moonillum, $moonage) = (phase($resDay->{datetimeEpoch}))[0,1,2];
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

    # Build envelope and write JSON to file
    $weatherKey = "dailyforecast";
    $envelope = {
        refresh     => $refresh,
        generatedAt => $generatedAt->iso8601(),
        location    => $location,
        $grabberKey => {
            filename      => "$lbplogdir/$weatherKey.json",
            generatedAt   => $generatedAt->iso8601(),
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

    for my $resDay ( @{$results->{days}} ) {

        # sunrise / sunset in epoch time, convert to local time of location and format as HH:MM
        my $sunriseEpoch = getValue($resDay, 'sunriseEpoch');
        my $sunsetEpoch = getValue($resDay, 'sunsetEpoch');

        for my $resHour ( @{$resDay->{hours}} ) {

            # Skip past hours (hourly forecast contains also data for current day, subtract one hour margin)
            my $now = localtime - ONE_HOUR;
            my $hourEpoch = getValue($resHour, 'datetimeEpoch');
            my $hfctime = localtime($hourEpoch);
            next if $now->epoch > $hfctime->epoch;
 
            # time
            my %time;
            $time{datetime} = _epochToIso($hourEpoch, $timezoneFromApi);
            $time{epoch}    = $hourEpoch;

            # temperature
            my %temperature;
            $temperature{air}       = getFormatted('%.1f', $resHour, 'temp');                      # hfc<X>_tt.       - daily max temperature (°C)
            $temperature{feelsLike} = getFormatted('%.1f', $resHour, 'feelslike'),                 # hfc<X>_tt_fl     - min feels-like temperature
            $temperature{heatIndex} = undef;
            $temperature{windChill} = undef;

            # wind
            my %wind;
            my $windDir = getFormatted('%.0f', $resHour, 'winddir');
            $wind{direction} = $windDir;                                                           # hfc<X>_w_dir     - wind direction (degree)
            $wind{cardinal}  = getWindDirCardinal($windDir);                                       #                  - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
            $wind{speed}     = getFormatted('%.1f', $resHour, 'windspeed'),                        # hfc<X>_w_sp      - wind speed (km/h)
            $wind{gust}      = getFormatted('%.1f', $resHour, 'windgust'),                         # hfc<X>_w_sp      - wind gust (km/h)

            # precipitation
            my %precipitation;
            $precipitation{probability} = getFormatted('%.0f', $resHour, 'precipprob'),            # hfc<X>_pop         - probability of precipitation (%)
            $precipitation{rainHigh}    = getFormatted('%.1f', $resHour, 'precip'),                # hfc<X>_prec        - precipitation (mm)
            $precipitation{snowHigh}    = getFormattedMultiplied('%.1f', 0.1, $resHour, 'snow'),   # hfc<X>_snow        - snow height (cm)
            $precipitation{duration}    = undef;
            $precipitation{type}        = getValue($resHour, 'preciptype'),                        #                    - precipitation type

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
            my ($moonphase, $moonillum, $moonage) = (phase($hourEpoch))[0,1,2];
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
                isNight        => isNighttime($hourEpoch, $sunriseEpoch, $sunsetEpoch),  # to use day or night icon for icon sets that have this feature
            };
            $hour++;
        }
    }

    # Build envelope and write JSON to file
    $weatherKey = "hourlyforecast";
    $envelope = {
        refresh     => $refresh,
        generatedAt => $generatedAt->iso8601(),
        location    => $location,
        $grabberKey => {
            filename      => "$lbplogdir/$weatherKey.json",
            generatedAt   => $generatedAt->iso8601(),
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
