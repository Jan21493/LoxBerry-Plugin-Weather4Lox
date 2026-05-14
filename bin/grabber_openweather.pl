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
# Standard Modules (no error handling in case of missing modules)
##########################################################################

use LoxBerry::System;
use LoxBerry::Log;
use LWP::UserAgent;
use JSON::PP;
use File::Copy;
use File::Basename qw(basename);
use Getopt::Long;
use Time::Piece;
use HTTP::Request;
use DateTime;
#use Astro::MoonPhase;
use utf8;
use Encode qw(encode_utf8);
use HTML::Entities;
require "$lbpbindir/grabber_utils.pl";

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

# params from config
my $pcfg            = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $url             = $pcfg->param("OPENWEATHER.URL");
my $apikey          = $pcfg->param("OPENWEATHER.APIKEY");
my $lang            = $pcfg->param("SERVER.LANG");
my $stationid       = "lat=" . $pcfg->param("SERVER.COORDLAT") . "&lon=" . $pcfg->param("SERVER.COORDLONG");
my $city            = $pcfg->param("SERVER.CITY");
my $country         = $pcfg->param("SERVER.COUNTRY");
my $refresh         = $pcfg->param("SERVER.CRON") // 60;    # default to 60 if not set in config, otherwise to default weather service refresh time, normally set by command line option --interval from fetch.pl

# names for JSON
my $grabberFile     = basename(__FILE__);
my $grabberLabel    = "OpenWeather";
my $grabberKey      = "openweather";          # name in JSONs

my $weatherKey;

# params for API calls
my $oneCallURL       = "$url/3.0/onecall?appid=$apikey&$stationid&lang=$lang&units=metric";
my $fc3hrURL         = "$url/2.5/forecast?appid=$apikey&$stationid&lang=$lang&units=metric&cnt=40";
my $userAgentLocal   = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36";

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
    name => "$grabberLabel",
    logdir => "$lbplogdir",
    #filename => "$lbplogdir/weather4lox.log",
    #append => 1,
);

# Commandline options
my $verbose = '';
my $current = '';
my $daily = '';
my $hourly = '';
my $maskKeys = 1;
GetOptions ('verbose'  => \$verbose,
            'interval=i' => \$refresh,
            'quiet'    => sub { $verbose = 0 },
            'current'  => \$current,
            'daily'    => \$daily,
            'hourly'   => \$hourly,
            'maskkeys' => \$maskKeys,
            );

if ($verbose) {
    $log->stdout(1);
    $log->loglevel(7);
}

LOGSTART "Weather4Lox $grabberLabel GRABBER process started";
LOGDEB "This is $0 Version $version";

requireOrLogdie('DateTime::Format::ISO8601');
requireOrLogdie('Astro::MoonPhase');

# all values in current, daily, and hourly JSONs are in local time, so proper time zone information is important
my $timezone = _systemTimezone();
LOGDEB "Using timezone: $timezone, current local system time is " . DateTime->now( time_zone => $timezone )->iso8601();

# Get weather data from openweathermap.org (API request) for current conditions
my $results = apiCall(
    url => $oneCallURL,
    maskkeys => $maskKeys,
    keyparam => 'appid',
    # apikey => $apiKey,      # Key is not included in output JSON, so no masking needed here
    info => "for Location $city (current, daily and hourly weather data)",
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

# Mapping: OpenWeatherMap weather codes => [Loxone Code, Weather4Lox code] 
# Weather codes with meaning: https://openweathermap.org/weather-conditions
# --> Using https://wiki.loxberry.de/plugins/weather4loxone/start#wetter-codes

# Mapping table for conversion of OpenWeatherMap weather codes to Loxone weather Picto-Codes and Weather4Lox short names for weather symbols
my %owmToLox = (
    # OWM => [Picto-Code, Weather4Lox-Symbol] # Beschreibung (alte Beschreibung) -> neue Weather4Lox-Symbolbeschreibung
    200 => [18, "overcast_thunderstorm_1"],   # thunderstorm with light rain -> Gewitter mit leichtem Regen
    201 => [19, "overcast_thunderstorm_2"],   # thunderstorm with rain -> Kräftiges Gewitter mit Regen
    202 => [19, "overcast_thunderstorm_3"],   # thunderstorm with heavy rain -> Kräftiges Gewitter mit Starkregen
    210 => [18, "overcast_thunderstorm_1"],   # light thunderstorm -> Leichtes Gewitter
    211 => [18, "overcast_thunderstorm_2"],   # thunderstorm -> Gewitter
    212 => [19, "overcast_thunderstorm_3"],   # heavy thunderstorm -> Kräftiges Gewitter
    221 => [19, "overcast_thunderstorm_3"],   # ragged thunderstorm -> Kräftiges Gewitter (unbeständig)
    230 => [18, "overcast_thunderstorm_1"],   # thunderstorm with light drizzle -> Gewitter mit leichtem Nieseln
    231 => [18, "overcast_thunderstorm_2"],   # thunderstorm with drizzle -> Gewitter mit Nieseln
    232 => [19, "overcast_thunderstorm_3"],   # thunderstorm with heavy drizzle -> Kräftiges Gewitter mit Starknieseln

    300 => [13, "overcast_rain_1"],           # light intensity drizzle -> Leichter Nieselregen
    301 => [13, "overcast_rain_2"],           # drizzle -> Nieselregen
    302 => [13, "overcast_rain_3"],           # heavy intensity drizzle -> Kräftiger Nieselregen
    310 => [10, "overcast_rain_1"],           # light intensity drizzle rain -> Leichter Regen
    311 => [11, "overcast_rain_2"],           # drizzle rain -> Regen
    312 => [12, "overcast_rain_3"],           # heavy intensity drizzle rain -> Kräftiger Regen
    313 => [16, "cloudy_shower_1"],           # shower rain and drizzle -> Regenschauer mit Nieseln
    314 => [17, "cloudy_shower_2"],           # heavy shower rain and drizzle -> Kräftige Regenschauer mit Nieseln
    321 => [13, "cloudy_shower_1"],           # shower drizzle -> Nieselschauer

    500 => [10, "overcast_rain_1"],           # light rain -> Leichter Regen
    501 => [11, "overcast_rain_2"],           # moderate rain -> Regen
    502 => [12, "overcast_rain_3"],           # heavy intensity rain -> Kräftiger Regen
    503 => [12, "overcast_rain_3"],           # very heavy rain -> Sehr starker Regen
    504 => [12, "overcast_rain_3"],           # extreme rain -> Extrem starker Regen
    511 => [15, "overcast_freezingrain_2"],   # freezing rain -> Gefrierender Regen
    520 => [16, "cloudy_shower_1"],           # light intensity shower rain -> Leichter Regenschauer
    521 => [17, "cloudy_shower_2"],           # shower rain -> Kräftiger Regenschauer
    522 => [17, "overcast_shower_3"],         # heavy intensity shower rain -> Sehr kräftiger Regenschauer
    531 => [17, "overcast_shower_3"],         # ragged shower rain -> Unbeständiger kräftiger Regenschauer

    600 => [20, "overcast_snow_1"],           # light snow -> Leichter Schneefall
    601 => [21, "overcast_snow_2"],           # snow -> Schneefall
    602 => [22, "overcast_snow_3"],           # heavy snow -> Starker Schneefall
    611 => [26, "overcast_sleet_2"],          # sleet -> Schneeregen
    612 => [28, "cloudy_sleet_1"],            # light shower sleet -> Leichter Schneeregenschauer
    613 => [29, "cloudy_sleet_2"],            # shower sleet -> Kräftiger Schneeregenschauer
    615 => [25, "overcast_sleet_1"],          # light rain and snow -> Leichter Schneeregen
    616 => [27, "overcast_sleet_2"],          # rain and snow -> Kräftiger Schneeregen
    620 => [23, "cloudy_snow_1"],             # light shower snow -> Leichter Schneeschauer
    621 => [23, "cloudy_snow_2"],             # shower snow -> Schneeschauer
    622 => [24, "overcast_snow_3"],           # heavy shower snow -> Starker Schneeschauer

    701 => [6,  "mist"],                      # mist -> Nebel (leicht)
    711 => [6,  "smoke"],                     # smoke -> Rauch
    721 => [7,  "haze"],                      # haze -> Dunst / Hochnebel
    731 => [5,  "dust_whirls"],               # sand/dust whirls -> Staubwirbel
    741 => [6,  "fog"],                       # fog -> Nebel
    751 => [5,  "sand"],                      # sand -> Sandsturm
    761 => [5,  "dust"],                      # dust -> Staub
    762 => [5,  "volcanic_ash"],              # volcanic ash -> Vulkanasche
    771 => [12, "squalls"],                   # squalls -> Starke Windböen mit Regen
    781 => [19, "tornado"],                   # tornado -> Tornados

    800 => [1,  "clear"],                     # clear sky -> Klar, wolkenlos
    801 => [2,  "fair"],                      # few clouds: 11-25% -> Heiter
    802 => [3,  "partly_cloudy"],             # scattered clouds: 25-50% -> Wolkig
    803 => [4,  "cloudy"],                    # broken clouds: 51-84% -> Stark bewölkt
    804 => [5,  "overcast"],                  # overcast clouds: 85-100% -> Bedeckt
);

# Anmerkungen zur Mapping-Tabelle:
# - Drizzle (3xx): Weather4Lox unterscheidet nicht zwischen Nieselregen und normalem Regen, daher wurden alle Drizzle-Codes in die Regenkategorien (10-17) eingestuft, je nach Intensität.
# - Besonderheit 27: OWM hat keinen expliziten Code für "starken Schneeregen" (nur Schauer oder normal).
# - Nebel vs. Hochnebel (6 & 7): Mist und Fog sind klassischer Nebel (6). Haze (Dunst) mappt am besten auf Hochnebel (7), da es eine diffuse Trübung beschreibt, die oft nicht direkt am Boden als "Nässe" wahrgenommen wird.
# - Staub, Sand & Asche (711–762): Da diese in der Liste von Loxone nicht vorkommen, ist ID 5 (bedeckt) die beste Wahl, da die Lichtdurchlässigkeit massiv reduziert ist, ähnlich einer geschlossenen Wolkendecke.
# - Extreme (771 & 781): Squalls treten fast immer mit massivem Regen auf (12), ein Tornado ist das extremste Wettereignis und passt daher am ehesten in die Kategorie des kräftigen Gewitters (19), da er meist aus solchen Zellen entsteht.


sub owmToLox {
    my ($owmId) = @_;
    my $data = $owmToLox{$owmId} // [99, "No data"];  # Default fallback for unknown codes
    
    if (!exists $owmToLox{$owmId}) {
        LOGWARN "Unknown ID from OpenWeatherMap: $owmId. Please check! Using fallback 'No data'.";
    }
    return @$data; # Returns (Loxone-Picto code, Weather4Lox symbol)
}

# Mapping of Weather4Lox codes to sky coverage (in percentages)

# TODO: table is not used yet
my %skyConditionByW4lCode = (
    # Klarer Himmel oder wolkenlos
    'clear'                      => [   0 ],   # klar/sonnig

    # Leicht bewölkt/heiter
    'fair'                       => [  15 ],   # heiter, wenige Wolken

    # Teilweise bewölkt
    'partly_cloudy'              => [  40 ],   # wechselnd bewölkt, ca. 25-50%

    # Mäßig bis stark bewölkt
    'cloudy'                     => [  65 ],   # meist bewölkt, 50-80% 

    # Bedeckt
    'overcast'                   => [  95 ],   # bedeckt, >85%

    # Verschiedene Schauer/Starkregencodes – meist stark bewölkt bis bedeckt
    'cloudy_shower_1'            => [  75 ],   # Regenschauer, eher stark bewölkt
    'cloudy_shower_2'            => [  80 ],   # kräftiger Regenschauer, stark bewölkt
    'overcast_shower_1'          => [  95 ],   # Schauer bei bedecktem Himmel
    'overcast_shower_2'          => [  98 ],   # starker Schauer bei bedecktem Himmel
    'overcast_shower_3'          => [ 100 ],   # extremer Schauer, vollständig bedeckt

    # Regen
    'cloudy_rain_1'              => [  70 ],   # leichter Regen, stark bewölkt
    'cloudy_rain_2'              => [  80 ],   # kräftiger Regen, stark bewölkt
    'overcast_rain_1'            => [  95 ],   # Regen bei bedeckt
    'overcast_rain_2'            => [  98 ],   # starker Regen, bedeckt
    'overcast_rain_3'            => [ 100 ],   # sehr starker/extremer Regen

    # Schneeregen/Sleet
    'cloudy_sleet_1'             => [  70 ],
    'cloudy_sleet_2'             => [  80 ],
    'overcast_sleet_1'           => [  95 ],
    'overcast_sleet_2'           => [  98 ],
    'overcast_sleet_3'           => [ 100 ],

    # Schnee
    'cloudy_snow_1'              => [  75 ],
    'cloudy_snow_2'              => [  85 ],
    'overcast_snow_1'            => [  95 ],
    'overcast_snow_2'            => [  98 ],
    'overcast_snow_3'            => [ 100 ],

    # Gefrierender Regen (Freezing Rain)
    'cloudy_freezingrain_1'      => [  70 ],
    'cloudy_freezingrain_2'      => [  80 ],
    'overcast_freezingrain_1'    => [  95 ],
    'overcast_freezingrain_2'    => [  98 ],
    'overcast_freezingrain_3'    => [ 100 ],

    # Gewitter (Thunderstorm)
    'cloudy_thunderstorm_1'      => [  80 ],
    'cloudy_thunderstorm_2'      => [  90 ],
    'overcast_thunderstorm_1'    => [  98 ],
    'overcast_thunderstorm_2'    => [ 100 ],
    'overcast_thunderstorm_3'    => [ 100 ],

    # Schneegewitter (Snow-Thunderstorm)
    'cloudy_snowthunderstorm_1'  => [  90 ],
    'cloudy_snowthunderstorm_2'  => [  95 ],
    'overcast_snowthunderstorm_1'=> [  98 ],
    'overcast_snowthunderstorm_2'=> [ 100 ],
    'overcast_snowthunderstorm_3'=> [ 100 ],

    # Hagel/Graupel
    'overcast_graupel'           => [ 100 ],
    'overcast_hail_1'            => [  98 ],
    'overcast_hail_2'            => [ 100 ],

    # Eisregen (Ice) – keine eigene Wolkenbelegung, aber immer bedeckt
    'overcast_ice'               => [ 100 ],

    # Nebel, Dunst, andere Sichtminimierungen – meist sehr hohe Luftfeuchtigkeit, oft mit dichter Decke
    'cloudy_fog'                 => [  80 ],  # Dunst/Nebel, meist viele Wolken aber manchmal auch Lücken
    'overcast_fog'               => [  98 ],  # dichter/bodennaher Nebel, fast immer bedeckt

    'mist'                       => [  80 ],  # leichter Nebel (Synonym)
    'smoke'                      => [  80 ],  # Rauch, wie Dunst
    'haze'                       => [  75 ],  # Dunst
    'dust_whirls'                => [  70 ],  # Staub – meist trüb, aber nicht immer voll bedeckt
    'fog'                        => [  98 ],  # starker Nebel
    'sand'                       => [  98 ],  # Sand
    'dust'                       => [  98 ],  # Staub
    'volcanic_ash'               => [ 100 ],  # Vulkanasche

    # Squalls, tornado – Extremwetter, immer voll bedeckt
    'squalls'                    => [ 100 ],  
    'tornado'                    => [ 100 ],  

    # Wenn keine Daten verfügbar, sicherheitshalber voll bedeckt („error fallback“)
    'no_data'                    => [ 100 ],
);

# Mapping of OpenWeatherMap weather codes to sky coverage (in percentages)

sub skyConditionFromOwmCode {
    my ($owmCode) = @_;

    my %skyCoverageByOwmCode = (
        # Thunderstorm codes
        200 => 90,   # thunderstorm with light rain
        201 => 95,   # thunderstorm with rain
        202 => 100,  # thunderstorm with heavy rain
        210 => 80,   # light thunderstorm
        211 => 90,   # thunderstorm
        212 => 100,  # heavy thunderstorm
        221 => 100,  # ragged thunderstorm
        230 => 90,   # thunderstorm with light drizzle
        231 => 90,   # thunderstorm with drizzle
        232 => 100,  # thunderstorm with heavy drizzle

        # Drizzle codes
        300 => 75,   # light intensity drizzle
        301 => 80,   # drizzle
        302 => 85,   # heavy intensity drizzle
        310 => 80,   # light intensity drizzle rain
        311 => 85,   # drizzle rain
        312 => 90,   # heavy intensity drizzle rain
        313 => 85,   # shower rain and drizzle
        314 => 90,   # heavy shower rain and drizzle
        321 => 80,   # shower drizzle

        # Rain codes
        500 => 80,   # light rain
        501 => 85,   # moderate rain
        502 => 90,   # heavy intensity rain
        503 => 95,   # very heavy rain
        504 => 100,  # extreme rain
        511 => 90,   # freezing rain
        520 => 85,   # light intensity shower rain
        521 => 90,   # shower rain
        522 => 95,   # heavy intensity shower rain
        531 => 100,  # ragged shower rain

        # Snow codes
        600 => 70,   # light snow
        601 => 80,   # snow
        602 => 90,   # heavy snow
        611 => 85,   # sleet
        612 => 80,   # light shower sleet
        613 => 85,   # shower sleet
        615 => 75,   # light rain and snow
        616 => 85,   # rain and snow
        620 => 80,   # light shower snow
        621 => 85,   # shower snow
        622 => 95,   # heavy shower snow

        # Atmosphere codes
        701 => 60,   # mist
        711 => 60,   # smoke
        721 => 40,   # haze
        731 => 65,   # sand/dust whirls
        741 => 90,   # fog
        751 => 80,   # sand
        761 => 80,   # dust
        762 => 100,  # volcanic ash
        771 => 95,   # squalls
        781 => 100,  # tornado

        # Clear, clouds
        800 => 0,    # clear sky
        801 => 20,   # few clouds: 11-25%
        802 => 40,   # scattered clouds: 25-50%
        803 => 65,   # broken clouds: 51-84%
        804 => 100,  # overcast clouds: 85-100%
);

    # Check for empty/undefined values
    if (defined $owmCode) {
        my $entry  = $skyCoverageByOwmCode{$owmCode};

        if ($entry) {
            return ($entry);
        }
    }

    LOGWARN "Unknown OpenWeatherMap code '$owmCode' for sky condition.";
    return (undef);
}


# Determine if it's currently nighttime based on current time, sunrise/sunset times (all epoch times on the same day) and $timezone
sub isNighttime {
    my ($time, $timezone, $sunrise, $sunset) = @_;
    my $isNighttime = undef; # default to day (undef)

    if ($time < $sunrise || $time > $sunset) {
        $isNighttime = 1;
    }
    return ($isNighttime);
}

# Determine if it's currently nighttime for a given hour from houry data, based on sunrise/sunset times from daily data
sub isNighttimeForCurrentHour {
    my ($dtEpoch, $timezone, $results) = @_;

    my $isNighttime = undef; # default to day (undef)

    # Get sunrise and sunset time from daily data, needed for isNighttime calculation (used for selecting day or night symbol)
    for my $dailyresults (@{$results->{daily} // []}) {
        if (_epochToIsoDate(getValue($dailyresults, 'dt'), $timezone) eq _epochToIsoDate($dtEpoch, $timezone)) {
            # we found the matching day in daily data for the current hour

            if (isNighttime($dtEpoch, $timezone, getValue($dailyresults, 'sunrise'), getValue($dailyresults, 'sunset'))) {
                $isNighttime = 1;
                last; # break loop if we found the matching day and determined it is nighttime
            }
        }
    }
    return ($isNighttime);
}

sub getCountryCode {
    my $name = shift;

    # location information
    my %countryNameToCode = (
        # Germany
        "Germany"      => "DE",
        "Deutschland"  => "DE",

        # Spain
        "Spain"        => "ES",
        "Spanien"      => "ES",
        "España"       => "ES",

        # Slovakia
        "Slovakia"     => "SK",
        "Slovensko"    => "SK",

        # Netherlands
        "Netherlands"  => "NL",
        "Nederland"    => "NL",

        # Austria
        "Austria"      => "AT",
        "Österreich"   => "AT",
    );

    return $countryNameToCode{$name} // undef;
}

##########################################################################
# Fetch common data
##########################################################################

######### To be verified: Timezone from API response ?
my $timezoneFromApi = getValue($results, 'timezone');
if ($timezone ne $timezoneFromApi) {
    LOGWARN "Timezone for location '$city' ($timezoneFromApi) does not match the system timezone of your LoxBerry ($timezone). Time differences may occur!";
}

# date/time from API response
my $currentEpoch = getValue($results, 'current', 'dt');
my $dtCurrent = DateTime->from_epoch( epoch => $currentEpoch, time_zone => $timezoneFromApi );

# add location information once
my $location = {
    city         => $city,                                                               # cur_loc_n, e.g. "Schwarzenbek"
    country      => $country,                                                            # country name, e.g. Deutschland
    countryCode  => getCountryCode($country),                                            # country code
    elevation    => undef,                                                               # altitude in meters
    latitude     => getFormatted('%.3f', $results, 'lat'),                               # latitude
    longitude    => getFormatted('%.3f', $results, 'lon'),                               # longitude
    timezone     => $timezoneFromApi,                                                    # timezone string (e.g. "Europe/Berlin"), from API response
    tzShort      => $dtCurrent->strftime('%Z'),                                          # timezone abbreviation (e.g. "CET")
    tzOffset     => $dtCurrent->strftime('%z'),                                          # timezone offset (e.g. "+0100")
};


##########################################################################
# Fetch current data
##########################################################################

if ( $current ) {

    # Build clean record
    my %currentData;

    LOGINF "Reading current weather data from API response into W4L structure at $dtCurrent.";

    my %time;
    $time{datetime}  = _epochToIso($currentEpoch, $timezoneFromApi);                                                          # cur_date_des
    $time{epoch}     = $currentEpoch;                                                                                         # cur_date

    # cur_date_tz_des (e.g. Europe/Berlin), cur_date_tz_des_sh (e.g. "CET"), cur_date_tz (e.g. "+0100") are send in location section 

    $currentData{time} = \%time;

    # sunrise and sunset are in local time, e.g. 05:47 and 17:39, they are provided as epoch times in the API response
    my $sunriseEpoch = getValue($results, 'current', 'sunrise');
    my $sunsetEpoch  = getValue($results, 'current', 'sunset');
    $currentData{sunrise} = getTimeFromEpochFormatted('%H:%M', $timezone, $sunriseEpoch);                                     # cur_sun_r 
    $currentData{sunset}  = getTimeFromEpochFormatted('%H:%M', $timezone, $sunsetEpoch);                                      # cur_sun_s

    # temperatures
    my %temperature;

    $temperature{air}        = getFormatted('%.1f', $results, 'current', 'temp');                                              # cur_tt     - air temperature in °C
    $temperature{feelsLike}  = getFormatted('%.1f', $results, 'current', 'feels_like');                                        # cur_tt_fl  - feels like temperature in °C
    $temperature{windChill}  = undef;                                                                                          # cur_w_ch   - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
    $temperature{heatIndex}  = undef;                                                                                          # cur_hi     - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures

    $currentData{temperature} = \%temperature;

    # humidity
    $currentData{humidity} = getFormatted('%.1f', $results, 'current', 'humidity');                                            # cur_hu     -  in percentage
    
    # wind
    my %wind;

    my $windDirection = getValue($results, 'current', 'wind_deg');

    $wind{direction}      = $windDirection;                                                                                    # cur_w_dir  - wind direction in degrees
    $wind{cardinal}       = getWindDirCardinal($windDirection);                                                                #            - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
    $wind{speed}          = getFormattedMultiplied('%.1f', 3.6, $results, 'current', 'wind_speed');                            # cur_w_sp   - wind speed converted from m/s to km/h
    $wind{gust}           = getFormattedMultiplied('%.1f', 3.6, $results, 'current', 'wind_gust');                             # cur_w_gu   - gust speed converted from m/s to km/h

    $currentData{wind} = \%wind;

    # air pressure
    $currentData{pressure} = getFormatted('%.0f', $results, 'current', 'pressure');                                           # cur_pr, air pressure in hPa

    # dew point
    $currentData{dewpoint} = getFormatted('%.1f', $results, 'current', 'dew_point');                                           # cur_dp, dew point in °C

    # visibility - not provided by API
    $currentData{visibility} = getFormattedMultiplied('%.2f', 0.001, $results, 'current', 'visibility');                       # cur_vis, visibility in km (API provides in meters)

    # solar radiation
    $currentData{solarRadiation} = undef;                                                                                      # cur_sr, solar radiation in W/m² (not provided by API)

    $currentData{uvIndex} = getFormatted('%.0f', $results, 'current', 'uvi');                                                  # cur_uvi

    # precipitation
    my %precipitation;

    ##### TO be verified: all rain parameters ?
    $precipitation{rain1hr} = getFormatted('%.1f', $results, 'current', 'rain', '1h');                                         # cur_prec_1h, 1-hour precipitation in mm
    $precipitation{snow1hr} = getFormattedMultiplied('%.1f', 0.1, $results, 'current', 'snow', '1h');                          # cur_snow_1h, 1-hour snow in cm (conversion from mm, API provides mm)
    $precipitation{type} = getValue($results, 'current', 'weather', 0, 'main');                                                # type of precipitation (rain, snow), undef, if it is currently not raining/snowing

    $precipitation{probability} = getPercentage('%.1f', $results, 'hourly', 0, 'pop');                                         # cur_pop, probability in percent, API provides as decimal (e.g. 0.25 for 25%)

    # $precipitation{rainToday} = getFormatted('%.1f', $results, 
    #    'daily', 0, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end');                             # cur_prec_today, today precipitation in mm

     # $precipitation{snowToday} = getFormatted('%.1f', $results, 
    #     'trend', 'items', 0, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end');                       # cur_snow_today, today snow in cm

    $currentData{precipitation} = \%precipitation;

    # weather codes
    my %weatherCode;

    # Mapping: OWM Symbol => [Loxone code, Weather4Lox code]
    my ($loxoneCode, $w4lCode, $description);
    my $symbol = getValue($results, 'current', 'weather', 0, 'id');
    if (!defined $symbol) {
        LOGWARN "OpenWeatherMap symbol for current weather is undefined!";
        ($loxoneCode, $w4lCode) = (5, 'no_data');  # Default fallback
        $description = 'No description for weather symbol';
    } else {
        ($loxoneCode, $w4lCode) = owmToLox($symbol);
        $description = getValue($results, 'current', 'weather', 0, 'description') // 'No description for weather symbol';
    }

    $weatherCode{loxone}      = $loxoneCode;                                                                                  # cur_code
    $weatherCode{weather4lox} = $w4lCode;                                                                                     # cur_icon
    $weatherCode{description} = $description;                                                                                 # cur_des
    $weatherCode{image}       = undef;                                                                                        # future use, e.g. as background image
    $weatherCode{metar}       = getMetarCode($w4lCode);                                                                       # future use, e.g. scientific theme

    $currentData{weatherCode} = \%weatherCode;

    # ozone (cur_ozone) is not provided by API
    
    # sky condition / cloud cover
    $currentData{cloudCover} = getValue($results, 'current', 'clouds');                                                        # cur_sky           - cloud cover in percentage from API response

    # astro data
    my %moon;

    my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = Astro::MoonPhase::phase();
    # age is delivered by API, , but makes no sense as phase() delivers all values
    $moon{age} = sprintf("%.1f",$moonage) + 0;                                                                                 # cur_moon_a        - moon age in days
    $moon{percent} = sprintf("%.1f",$moonillum * 100) + 0;                                                                     # cur_moon_p        - moon illumination in percent
    $moon{phase} = sprintf("%.1f",$moonphase * 100) + 0;                                                                       # cur_moon_ph       - moon phase in percent (0% = new moon, 50% = half moon, 100% = full moon)
    $moon{direction} = getMoonDirection($moonage);                                                                             #                   - moon direction (waxing, waning)

    $currentData{moon} = \%moon;
    
    # night time - used for selecting day or night symbol (eighter night time or undef)
    $currentData{isNight} = isNighttime($currentEpoch, $timezone, $sunriseEpoch, $sunsetEpoch);

    # Build envelope and write JSON to file
    $weatherKey = "current";
    my $generatedAt = DateTime->now( time_zone => $timezone );
    my $envelope = {
        location => $location,
        refresh  => $refresh,
        generatedAt => $generatedAt->iso8601(),
        $grabberKey => {
            filename        => "$lbplogdir/$weatherKey.json",
            generatedAt     => $generatedAt->iso8601(),
            grabberLabel    => $grabberLabel,
            grabberScript   => $grabberFile,
            schemaVersion   => "v1.0",
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

    LOGINF "Reading daily weather data from API response into W4L structure at $dtCurrent.";

    # it is assumed, that the elements are ordered by time (ascending)
    for my $resDay (@{$results->{daily} // []}) {

        # values with additional calculations needs to be done before hash is assigned

        my $dtEpoch = getValue($resDay, 'dt');

        # wind
        my $windDirAvg = getFormatted('%.0f', $resDay, 'wind_deg');                                                             # dfc<X>_w_dir_a   -  average wind direction in degrees

        # Mapping: OWM Symbol => [Loxone code, Weather4Lox code, description]
        my ($loxoneCode, $w4lCode, $description);
        my $symbol = getValue($resDay, 'weather', 0, 'id');
        if (!defined $symbol) {
            LOGWARN "OpenWeatherMap symbol for daily weather is undefined!";
            ($loxoneCode, $w4lCode) = (5, 'no_data'); # Default fallback
            $description = 'No description for weather symbol';
        } else {
            ($loxoneCode, $w4lCode) = owmToLox($symbol);
            $description = getValue($resDay, 'weather', 0, 'description') // 'No description for weather symbol';
        }

        # astro data - get moon infos for specific time of data set (translated to epoch time)
        my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = Astro::MoonPhase::phase($dtEpoch);

        push @dailyData, {

            day            => $day,                                                                                            # dfc<X>_per        - counter of day
            time => {
                datetime     => _epochToIso($dtEpoch, $timezone),                                                              #                   - ISO 8601 date string in local time (e.g. "2026-03-13T02:00:00+01:00")
                epoch        => $dtEpoch,                                                                                      # dfc<X>_date       - UNIX timestamp
            },
            temperature => {
                min => {
                    air         => getFormatted('%.1f', $resDay, 'temp', 'min'),                                               # dfc<X>_tt_l      - daily min temperature (°C)
                    feelsLike   => getFormatted('%.1f', $resDay, 'feels_like', 'min'),                                         # dfc<X>_tt_fl_l   - min feels-like temperature
                    windChill   => undef,                                                                                      # dfc<X>_w_ch      - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
                },
                max => {
                    air         => getFormatted('%.1f', $resDay, 'temp', 'max'),                                               # dfc<X>_tt_h      - daily max temperature (°C)
                    feelsLike   => getFormatted('%.1f', $resDay, 'feels_like', 'max'),                                         # dfc<X>_tt_fl_h   - max feels-like temperature
                    heatIndex   => undef,                                                                                      # dfc<X>_hi        - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures
                },
            },
            wind => {
                avg => {
                    direction       => $windDirAvg,                                                                            # dfc<X>_w_dir_a   - wind direction (degree, average)
                    cardinal        => getWindDirCardinal($windDirAvg),                                                        #                  - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
                    speed           => getFormattedMultiplied('%.1f', 3.6, $resDay, 'wind_speed'),                             # dfc<X>_w_sp_a    - wind speed average (km/h)
                    gust            => getFormattedMultiplied('%.1f', 3.6, $resDay, 'wind_gust'),                              # dfc<X>_w_gu_a    - wind gust average (km/h)
                },
                max => {
                    direction       => undef,                                                                                  # dfc<X>_w_dir_h   - wind direction (degree, max)
                    cardinal        => undef,                                                                                  #                  - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
                    speed           => undef,                                                                                  # dfc<X>_w_sp_h    - wind speed max (km/h)
                    gust            => undef,                                                                                  # dfc<X>_w_gu_h    - wind gust max (km/h)
                }
            },
            precipitation => {
                probability   => getPercentage('%.1f', $resDay, 'pop'),                                                        # dfc<X>_pop       - probability of precipitation (%)
                duration      => undef,                                                                                        #                  - duration of precipitation
                rainHigh      => getFormatted('%.1f', $resDay, 'rain'),                                                        # dfc<X>_prec      - precipitation (mm)
                type          => getValue($resDay, 'weather', 0, 'main'),                                                      #                  - precipitation type
                snowHigh      => getFormattedMultiplied('%.1f', 0.1, $resDay, 'snow'),                                         # dfc<X>_snow      - snow height (cm)
            },
            weatherCode => {
                loxone        => $loxoneCode,                                                                                  # dfc<X>_we_code   - Loxone code
                weather4lox   => $w4lCode,                                                                                     # dfc<X>_we_icon   - Weather4Lox icon code
                description   => $description,                                                                                 # dfc<X>_we_des    - description
                image         => undef,                                                                                        #                  - future use., e.g. as background image
                metar         => getMetarCode($w4lCode),                                                                       #                  - METAR code
            },
            moon => {
                age        => sprintf("%.1f", $moonage) + 0,                                                                   # dfc<X>_moon_a    - moon age in days
                rise       => getTimeFromEpochFormatted('%H:%M', $timezone, $resDay, 'moonrise'),                              #                  - moon rise in HH:MM in local time (API provides in Unix epoch time)
                set        => getTimeFromEpochFormatted('%H:%M', $timezone, $resDay, 'moonset'),                               #                  - moon set in HH:MM in local time (API provides in Unix epoch time)
                percent    => sprintf("%.1f", $moonillum * 100) + 0,                                                           # dfc<X>_moon_p    - moon percent
                phase      => sprintf("%.1f", $moonphase * 100) + 0,                                                           # dfc<X>_moon_ph   - moon phase
                direction  => getMoonDirection($moonage),                                                                      #                  - moon direction (waxing, waning)
            },
            humidity       => {
                avg        =>  getFormatted('%.1f', $resDay, 'humidity'),                                                      # dfc<X>_hu_a      - average humidity
                min        =>  undef,	                                                                                       # dfc<X>_hu_l      - minimum humidity
                max        =>  undef,                                                                                          # dfc<X>_hu_h      - maximum humidity
            },
            pressure         => getFormatted('%.0f', $resDay, 'pressure'),                                                     # dfc<X>_pr        - air pressure (hPa)
            dewpoint         => getFormatted('%.1f', $resDay, 'dew_point'),                                                    # dfc<X>_dp        - average dew point (°C)
            uvIndex          => getFormatted('%.1f', $resDay, 'uvi'),                                                          # dfc<X>_uvi       - UV index, maximum value for the day
            sunrise          => getTimeFromEpochFormatted('%H:%M', $timezone, $resDay, 'sunrise'),                             # dfc<X>_sun_r     - sunrise time (HH:MM) from Unix epoch time
            sunset           => getTimeFromEpochFormatted('%H:%M', $timezone, $resDay, 'sunset'),                              # dfc<X>_sun_s     - sunset time (HH:MM) from Unix epoch time
                                                                                                                               # dfc<X>_vis       - visibility (m/km as needed)
                                                                                                                               # dfc<X>_sr        - solar radiation (not present)
                                                                                                                               # dfc<X>_hi        - heat index (not present)
                                                                                                                               # dfc<X>_ozone     - ozone (not present)
            cloudCover       => getFormatted('%.0f', $resDay, 'clouds'),                                                       # dfc<X>_sky       - cloud/sky cover (percentage from 0 to 100)
        };
        $day++;
    }
 
    # Build envelope and write JSON to file
    $weatherKey = "dailyforecast";
    my $generatedAt = DateTime->now( time_zone => $timezone );
    my $envelope = {
        location => $location,
        refresh  => $refresh,
        generatedAt => $generatedAt->iso8601(),
        $grabberKey => {
            filename        => "$lbplogdir/$weatherKey.json",
            generatedAt     => $generatedAt->iso8601(),
            grabberLabel    => $grabberLabel,
            grabberScript   => $grabberFile,
            schemaVersion   => "v1.0",
        },
        $weatherKey => \@dailyData,
    };
    writeJsonFile($lbplogdir, $weatherKey, $envelope);

} # End daily

##########################################################################
# Fetch hourly data
##########################################################################

if ( $hourly ) {

    my @hourlyArray;
    my $hourlyData;
    my $hour = 1;                # used for hours, starts with 1 for first forecasted hour, 2 for next hour, etc.

    LOGINF "Reading hourly weather data from API response into W4L structure at $dtCurrent.";

    # it is assumed, that the elements are ordered by time (ascending)
    for my $resHour (@{$results->{hourly} // []}) {

        # values with additional calculations needs to be done before hash is assigned

        # time
        my $dtEpoch = getValue($resHour, 'dt');

        # wind
        my $windDir     = getFormatted('%.0f', $resHour, 'wind_deg');

        # Mapping: OWM Symbol => [Loxone code, Weather4Lox code, description]
        my ($loxoneCode, $w4lCode, $description);
        my $symbol = getValue($resHour, 'weather', 0, 'id');
        if (!defined $symbol) {
            LOGWARN "OpenWeatherMap symbol for hourly weather is undefined!";
            ($loxoneCode, $w4lCode) = (5, 'no_data');
            $description = 'No description for weather symbol';
        } else {
            ($loxoneCode, $w4lCode) = owmToLox($symbol);
            $description = getValue($resHour, 'weather', 0, 'description') // 'No description for weather symbol';
        }

        # astro data - get moon infos for specific time of data set (translated to epoch time)
        my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = Astro::MoonPhase::phase($dtEpoch);

        $hourlyData = {
            hour           => $hour,                                                               # hfc<X>_per        -  counter of day
            time => {
                datetime     => _epochToIso($dtEpoch, $timezone),                                  #                   - ISO 8601 date string in local time (e.g. "2026-03-13T02:00:00+01:00")
                epoch        => $dtEpoch,                                                          # hfc<X>_date       - UNIX timestamp
            },
            temperature => {
                air            => getFormatted('%.1f', $resHour, 'temp'),                          # hfc<X>_tt         - hourly max temperature (°C)
                feelsLike      => getFormatted('%.1f', $resHour, 'feels_like'),                    # hfc<X>_tt_fl      - min feels-like temperature
                heatIndex      => undef,                                                           # hfc<X>_hi         - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures
                windChill      => undef,                                                           # hfc<X>_w_ch       - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
            },
            wind => {
                direction     => $windDir,                                                         # hfc<X>_w_dir     - wind direction (degree)
                cardinal      => getWindDirCardinal($windDir),                                     #                  - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
                speed         => getFormattedMultiplied('%.1f', 3.6, $resHour, 'wind_speed'),      # hfc<X>_w_sp      - wind speed (km/h)
                gust          => getFormattedMultiplied('%.1f', 3.6, $resHour, 'wind_gust'),       # hfc<X>_w_gu      - wind gust (km/h)
            },
            precipitation => {
                probability   => getPercentage('%.1f', $resHour, 'pop'),                           # hfc<X>_pop       - probability of precipitation (%)
                rainHigh      => getFormatted('%.1f', $resHour, 'rain', '1h'),                     # hfc<X>_prec      - precipitation (mm)
                type          => getValue($resHour, 'weather', 0, 'main'),                         #                  - precipitation type
                snowHigh      => getFormattedMultiplied('%.1f', 0.1, $resHour, 'snow'),            # hfc<X>_snow      - snow height (cm)
            },
            weatherCode => {
                loxone       => $loxoneCode,                                                       # hfc<X>_we_code   - Loxone code
                weather4lox  => $w4lCode,                                                          # hfc<X>_we_icon   - Weather4Lox icon code
                description  => $description,                                                      # hfc<X>_we_des    - description
                metar        => getMetarCode($w4lCode),                                            #                  - METAR code
            },
            moon => {
                age          => sprintf("%.1f", $moonage) + 0,                                     # hfc<X>_moon_a    - moon age in days
                percent      => sprintf("%.1f", $moonillum * 100) + 0,                             # hfc<X>_moon_p    - moon percentage illumination
                phase        => sprintf("%.1f", $moonphase * 100) + 0,                             # hfc<X>_moon_ph   - moon phase
                direction    => getMoonDirection($moonage),                                        #                  - moon direction (waxing, waning)
            },
            humidity         => getFormatted('%.1f', $resHour, 'humidity'),                        # hfc<X>_hu        - humidity
            pressure         => getFormatted('%.0f', $resHour, 'pressure'),                        # hfc<X>_pr        - air pressure (hPa)
            dewpoint         => getFormatted('%.1f', $resHour, 'dew_point'),                       # hfc<X>_dp        - dew point (°C)
            uvIndex          => getFormatted('%.1f', $resHour, 'uvi'),                             # hfc<X>_uvi       - UV index
            visibility       => getFormattedMultiplied('%.0f', 0.001, $resHour, 'visibility'),     # hfc<X>_vis       - visibility (m/km as needed)
                                                                                                   # hfc<X>_sr        - solar radiation (not present)
                                                                                                   # hfc<X>_ozone     - ozone (not present)
            cloudCover       => getFormatted('%.0f', $resHour, 'clouds'),                          # hfc<X>_sky       - cloud/sky cover (percentage from 0 to 100)
            isNight          => isNighttimeForCurrentHour($dtEpoch, $timezone, $results),          #                  - get nighttime information from sunrise / sunset
        };
        push @hourlyArray, $hourlyData;
        $hour++;
    }

    # OpenWeatherMap only offers 48h of hourly forecasts in the free account. Interpolate with 3-hours data to have more entries for the weather emulator
    if ($hour < 168) {

        LOGINF "Fetching additional 3-hourly forecast data to interpolate hourly data (only 48h of hourly data available via OneCall API).";

        # Get data from openweathermap.org (API request) for 3-hourly forecasts via free 5 day / 3 hour forecast data
        my $res3Hourly = apiCall(
            url => $fc3hrURL,
            maskkeys => $maskKeys,
            keyparam => 'appid',
            # apikey => $apikey,	# not needed here as the URL is already masked and the key won't appear elsewhere in the response
            info => "for location $stationid (3-hourly weather forecast data)",
        );
        my $lastHourlyData = $hourlyData; # to keep track of the last hourly data for interpolation

        # it is assumed, that the elements are ordered by time (ascending)
        for my $res3Hour (@{$res3Hourly->{list} // []}) {

            # skip already existing hourly data, only interpolate for missing hours (normally every 3 hours)
			if ($lastHourlyData->{time}{epoch} >= getValue($res3Hour, 'dt')) {
				next;
			}

            # wind
            my $windDir3h     = getFormatted('%.0f', $res3Hour, 'wind', 'deg') // 0; # default to 0 if wind direction is missing, to avoid issues with interpolation

            # Mapping: OWM Symbol => [Loxone code, Weather4Lox code, description]
            my ($loxoneCode, $w4lCode, $description);
            my $symbol = getValue($res3Hour, 'weather', 0, 'id');
            if (!defined $symbol) {
                LOGWARN "OpenWeatherMap symbol for hourly weather is undefined!";
                ($loxoneCode, $w4lCode) = (5, 'no_data');
                $description = 'No description for weather symbol';
            } else {
                ($loxoneCode, $w4lCode) = owmToLox($symbol);
                $description = getValue($res3Hour, 'weather', 0, 'description') // 'No description for weather symbol';
            }

			# Step to last entry (normally 3 hours)
			my $delta = (getValue($res3Hour, 'dt') - $lastHourlyData->{time}{epoch}) / 3600;

			# Create new interpolated entries
			for (my $step=1; $step <= $delta; $step++) {

                # values with additional calculations needs to be done before hash is assigned

                # time
                my $dtEpoch = $lastHourlyData->{time}{epoch} + ($step * 3600); # add hours in seconds to last known hourly data timestamp

                # astro data - get moon infos for specific time of data set (translated to epoch time)
                my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = Astro::MoonPhase::phase($dtEpoch);

                sub interpolate {
                    my ($lastValue, $nextValue, $step, $delta) = @_;
                    if (defined $lastValue && defined $nextValue) {
                        return $lastValue + (($nextValue - $lastValue) / $delta * $step);
                    } elsif (defined $lastValue) {
                        return $lastValue;
                    } elsif (defined $nextValue) {
                        return $nextValue;
                    } else {
                        return undef;
                    }
                }

                # Interpolate wind direction with special handling for circular nature of wind direction (0° and 360° are the same) 
                my $lastWindDir = $lastHourlyData->{wind}{direction};
                my $windDirDiff = $windDir3h - $lastWindDir;

                # Get shortest path over the 360° jump
                if ($windDirDiff > 180) {
                    $windDirDiff -= 360;
                } elsif ($windDirDiff < -180) {
                    $windDirDiff += 360;
                }
                # Interpolate wind direction
                my $interpolatedWindDir = ($lastWindDir + ($windDirDiff / $delta * $step) + 360) % 360; # add 360 before modulo to avoid negative values

                $hourlyData = {
                    hour           => $hour,                                                               # hfc<X>_per.       -  counter of day
                    time => {
                        datetime     => _epochToIso($dtEpoch, $timezone),                                  #                   - ISO 8601 date string in local time (e.g. "2026-03-13T02:00:00+01:00")
                        epoch        => $dtEpoch,                                                          # hfc<X>_date       - UNIX timestamp
                    },
                    temperature => {
                        air            => interpolate($lastHourlyData->{temperature}{air},
                                            getFormatted('%.1f', $res3Hour, 'temp'),
                                            $step, $delta),                                                # hfc<X>_tt         - hourly max temperature (°C)
                        feelsLike      => interpolate($lastHourlyData->{temperature}{feelsLike},
                                            getFormatted('%.1f', $res3Hour, 'feels_like'),
                                            $step, $delta),                                                # hfc<X>_tt_fl      - min feels-like temperature
                        heatIndex      => undef,                                                           # hfc<X>_hi         - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures
                        windChill      => undef,                                                           # hfc<X>_w_ch       - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
                    },
                    wind => {
                        direction     => $interpolatedWindDir,                                             # hfc<X>_w_dir      - wind direction (degree)
                        cardinal      => getWindDirCardinal($interpolatedWindDir),                         #                   - cardinal and intercardinal directions, "N", "NE", "E", "SE", "S", "SW", "W", "NW" in english
                        speed         => interpolate($lastHourlyData->{wind}{speed},
                                            getFormattedMultiplied('%.1f', 3.6, $res3Hour, 'wind_speed'),
                                            $step, $delta),                                                # hfc<X>_w_sp       - wind speed (km/h)
                        gust          => interpolate($lastHourlyData->{wind}{gust},
                                            getFormattedMultiplied('%.1f', 3.6, $res3Hour, 'wind_gust'),
                                            $step, $delta),                                                # hfc<X>_w_gu       - wind gust (km/h)
                    },
                    precipitation => {
                        probability   => interpolate($lastHourlyData->{precipitation}{probability},
                                            getPercentage('%.1f', $res3Hour, 'pop'),
                                            $step, $delta),                                                # hfc<X>_pop        - probability of precipitation (%)
                        rainHigh      => interpolate($lastHourlyData->{precipitation}{rainHigh},
                                            getFormatted('%.1f', $res3Hour, 'rain', '1h'),
                                            $step, $delta),                                                # hfc<X>_prec       - precipitation (mm) up to
                        type          => getValue($res3Hour, 'weather', 0, 'main'),                          #                 - precipitation type
                        snowHigh      => interpolate($lastHourlyData->{precipitation}{snowHigh},
                                            getFormattedMultiplied('%.1f', 0.1, $res3Hour, 'snow'),
                                            $step, $delta),                                                # hfc<X>_snow       - snow height (cm) up to
                    },
                    weatherCode => {
                        loxone       => $loxoneCode,                                                        # hfc<X>_we_code   - Loxone code
                        weather4lox  => $w4lCode,                                                           # hfc<X>_we_icon   - Weather4Lox icon code
                        description  => $description,                                                       # hfc<X>_we_des    - description
                        metar        => getMetarCode($w4lCode),                                             #                  - METAR code
                    },
                    moon => {
                        age          => sprintf("%.1f", $moonage) + 0,                                      # hfc<X>_moon_a    - moon age in days
                        percent      => sprintf("%.1f", $moonillum * 100) + 0,                              # hfc<X>_moon_p    - moon percentage
                        phase        => sprintf("%.1f", $moonphase * 100) + 0,                              # hfc<X>_moon_ph   - moon phase
                        direction    => getMoonDirection($moonage),                                         #                  - moon direction (waxing, waning)
                    },
                    humidity         => interpolate($lastHourlyData->{humidity},
                                            getFormatted('%.1f', $res3Hour, 'humidity'),
                                            $step, $delta),                                                 # hfc<X>_hu        - humidity
                    pressure         => interpolate($lastHourlyData->{pressure},
                                            getFormatted('%.0f', $res3Hour, 'pressure'),
                                            $step, $delta),                                                 # hfc<X>_pr        - air pressure (hPa)
                    dewpoint         => interpolate($lastHourlyData->{dewpoint},
                                            getFormatted('%.1f', $res3Hour, 'dew_point'),
                                            $step, $delta),                                                 # hfc<X>_dp        - dew point (°C)
                    uvIndex          => interpolate($lastHourlyData->{uvIndex},
                                            getFormatted('%.1f', $res3Hour, 'uvi'),
                                            $step, $delta),                                                 # hfc<X>_uvi       - UV index
                    visibility       => interpolate($lastHourlyData->{visibility},
                                            getFormattedMultiplied('%.0f', 0.001, $res3Hour, 'visibility'),
                                            $step, $delta),                                                 # hfc<X>_vis       - visibility (m/km as needed)
                                                                                                            # hfc<X>_sr        - solar radiation (not present)
                                                                                                            # hfc<X>_ozone     - ozone (not present)
                    cloudCover       => interpolate($lastHourlyData->{cloudCover},
                                            getFormatted('%.0f', $res3Hour, 'clouds'),
                                            $step, $delta),                                                 # hfc<X>_sky       - cloud/sky cover (percentage from 0 to 100)
                    isNight          => isNighttimeForCurrentHour($dtEpoch, $timezone, $results),           #                  - get nighttime information from sunrise / sunset, alternate solution woudl be from symbol code
                };
                push @hourlyArray, $hourlyData;
                $lastHourlyData = $hourlyData; # update last known hourly data with the current one for next interpolation step
                $hour++;
            }
        }
    }

    # Build envelope and write JSON to file
    $weatherKey = "hourlyforecast";
    my $generatedAt = DateTime->now( time_zone => $timezone );
    my $envelope = {
        location => $location,
        refresh  => $refresh,
        generatedAt => $generatedAt->iso8601(),
        $grabberKey => {
            filename        => "$lbplogdir/$weatherKey.json",
            generatedAt     => $generatedAt->iso8601(),
            grabberLabel    => $grabberLabel,
            grabberScript   => $grabberFile,
            schemaVersion   => "v1.0",
        },
        $weatherKey => \@hourlyArray,
    };
    writeJsonFile($lbplogdir, $weatherKey, $envelope);

} # end hourly


# Give OK status to client.
LOGOK "Current weather data, daily and hourly forecasts are saved successfully.";

# Exit
exit;

END
{
    LOGEND;
}