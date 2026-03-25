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
my $url          = $pcfg->param("OPENWEATHER.URL");
my $apikey       = $pcfg->param("OPENWEATHER.APIKEY");
my $lang         = $pcfg->param("OPENWEATHER.LANG");
my $stationid    = "lat=" . $pcfg->param("OPENWEATHER.COORDLAT") . "&lon=" . $pcfg->param("OPENWEATHER.COORDLONG");
my $city         = $pcfg->param("OPENWEATHER.STATION");
my $country      = $pcfg->param("OPENWEATHER.COUNTRY");

# refresh interval in seconds (from CRON config, default 15 minutes)
my $cronMinutes  = $pcfg->param("SERVER.CRON") // 15;
my $refresh      = $cronMinutes * 60;

# names for JSON
my $grabberFile     = basename(__FILE__);
my $grabberLabel    = "OpenWeather";
my $grabberKey      = "openweather";          # name in JSONs

my $weatherKey;

# params for API calls
my $oneCallURI       = "$url/3.0/onecall?appid=$apikey&$stationid&lang=$lang&units=metric";
my $fc3hrURI.        = "$url/2.5/forecast?appid=$apikey&$stationid&lang=$lang&units=metric&cnt=40";
my $userAgentLocal   = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36";

# all values in current, daily, and hourly JSONs are in local time, so proper time zone information is important

# Determine system timezone (Debian / DietPi)
my $timezone = $ENV{TZ} // '';

if (!$timezone) {
    if (open my $tzfh, '<:encoding(UTF-8)', '/etc/timezone') {
        $timezone = <$tzfh>;
        chomp $timezone if defined $timezone;
        close $tzfh;
    }
}

# Validate that zoneinfo exists (avoid invalid names)
if (!$timezone || !-f "/usr/share/zoneinfo/$timezone") {
    # Fallback to UTC if not found
    $timezone = 'UTC';
}

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

if ($hourly) {
    #require_or_logdie('Lexical::Sub');
    requireOrLogdie('Math::Function::Interpolator');
    requireOrLogdie('Math::Function::Interpolator::Linear');
}

# Get weather data from wetteronline.de (API request) for current conditions
my $results = apiCall(
    url => $oneCallURI,
    maskkeys => $maskKeys,
    keyparam => 'appid',
    # apikey => $apiKey,      # Key is not included in output JSON, so no masking needed here
    info => "for Location $city (Current Weather Data)",
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

# Mapping: OpenWeatherMap weather codes => [Loxone Code, Weather4Lox code] # Description
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


sub skyConditionFromOwmCode {
    my ($owmCode) = @_;

    # Check for empty/undefined values
    if (defined $owmCode) {
        my $entry  = $skyCoverageByOwmCode{$owmCode};

        if ($entry) {
            return ($entry);
    }

    LOGWARN "Unknown OpenWeatherMap code '$owmCode' for sky condition.";
    return (undef);
}


# Determine if it's currently nighttime based on current time and sunrise/sunset times, all in HH:MM format
sub isNighttime {
    my ($time, $timezone, $sunrise, $sunset) = @_;
    my $isNighttime = 0;

    if ($time lt $sunrise || $time gt $sunset) {
        $isNighttime = 1;
    }
    return ($isNighttime);

}


##########################################################################
# Fetch common data
##########################################################################

my $timezoneFromApi = getValue($results, 'timezone');
if ($timezone ne $timezoneFromApi) {
    LOGWARN "Timezone for location '$city' ($timezoneFromApi) does not match the system timezone of your LoxBerry ($timezone). Time differences may occur!";
}

# date/time from API response
my $dtCurrent = DateTime->from_epoch( epoch => $results->{current}{dt}, time_zone => $timezoneFromApi );



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

sub getCountryCode {
    my $name = shift;
    return $countryNameToCode{$name} // undef;
}


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
    $time{datetime}  = _epochToIso($dtCurrent->epoch, $timezoneFromApi);;                                                      # cur_date_des
    $time{epoch}     = $dtCurrent->epoch;                                                                                      # cur_date
    $time{timezone}  = $timezoneFromApi;                                                                                       # cur_date_tz_des
    $time{tzShort}  = $dtCurrent->strftime('%Z');                                                                              # cur_date_tz_des_sh, e.g. "CET"
    $time{tzOffset} = $dtCurrent->strftime('%z');                                                                              # cur_date_tz, e.g. "+0100"

    $currentData{time} = \%time;

    # sunrise and set in local time, e.g. 05:47 and 17:39
    $currentData{sunrise} = getTimeFromEpochFormatted('%H:%M', $timezone, $results, 'current', 'sunrise');                     # cur_sun_r 
    $currentData{sunset}  = getTimeFromEpochFormatted('%H:%M', $timezone, $results, 'current', 'sunset');                      # cur_sun_s

    # temperatures
    my %temperature;

    $temperature{air}        = getFormatted('%.1f', $results, 'current', 'temp');                                              # cur_tt.    - air temperature in °C
    $temperature{feelsLike}  = getFormatted('%.1f', $results, 'current', 'feels_like');                                        # cur_tt_fl  - feels like temperature in °C
    $temperature{windChill}  = undef;                                                                                          # cur_w_ch   - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
    $temperature{heatIndex}  = undef;                                                                                          # cur_hi.    - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures

    $currentData{temperature} = \%temperature;

    # humidity
    $currentData{humidity} = getPercentage('%.2f', $results, 'current', 'humidity');                                           # cur_hu, in percentage
    
    # wind
    my %wind;

    my $windDirection = getValue($results, 'current', 'wind_deg');

    $wind{direction}      = $windDirection;                                                                                    # cur_w_dir, wind direction in degrees
    $wind{cardinal}       = getWindDirCardinal($windDirection);                                                                # to calculate cur_w_dirdes, wind direction description, e.g. "Süden",
    $wind{speed}          = getFormatted('%.1f', $results, 'current', 'wind_speed');                                           # cur_w_sp, wind speed in km/h
    $wind{gust}           = getFormatted('%.1f', $results, 'current', 'wind_gust');                                            # cur_w_gu, gust speed in km/h

    $currentData{wind} = \%wind;

    # air pressure
    $currentData{pressure} = getFormatted('%.0f', $results, 'current', '_pressure');                                           # cur_pr, air pressure in hPa

    # dew point
    $currentData{dewpoint} = getFormatted('%.1f', $results, 'current', 'dew_point');                                           # cur_dp, dew point in °C

    # visibility - not provided by API
    $currentData{visibility} = getFormatted('%.0f', $results, 'current', 'visibility');                                        # cur_vis, visibility in meters

    # solar radiation
    $currentData{solarRadiation} = undef;                                                                                      # cur_sr 

    $currentData{uvIndex} = getFormatted('%.0f', $results, 'current', 'uvi');                                                  # cur_uvi

    # precipitation
    my %precipitation;

    $precipitation{rainToday} = getFormatted('%.2f', $results, 
        'daily', 0, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end');                     # cur_prec_today, today precipitation in mm

    $precipitation{rain1hr} = getFormatted('%.2f', $results, 'rain', '1h');                                                    # cur_prec_1h, 1-hour precipitation in mm
    $precipitation{probability} = getPercentage('%.2f', $results, 'current', 'precipitation', 'probability');               # cur_pop, probability in percent
    $precipitation{type} = getValue($results, 'current', 'precipitation', 'type');                                          # type of precipitation (rain, snow), undef, if it is currently not raining/snowing
    $precipitation{snowToday} = getFormatted('%.2f', $results, 
        'trend', 'items', 0, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end');                         # cur_snow_today, today snow in cm
    $precipitation{snow1h} = getFormatted('%.2f', $results, 
        'hours', 'items', 0, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end');                         # cur_snow_1h, 1-hour snow in cm

    $currentData{precipitation} = \%precipitation;

    # weather codes
    my %weatherCode;

    # Mapping: Wetteronline Symbol => [Loxone code, Weather4Lox code, description]
    my ($loxoneCode, $w4lCode, $desc);
    my $symbol = getValue($results, 'current', 'symbol');
    if (!defined $symbol) {
        LOGWARN "Wetteronline symbol for current weather is undefined!";
        ($loxoneCode, $w4lCode, $desc) = (5, 'no_data', 'No description for weather symbol');  # Default fallback
    } else {
        ($loxoneCode, $w4lCode, $desc) = wetteronlineToLox($symbol);
    }

    $weatherCode{loxone}      = $loxoneCode;                                                                                  # cur_code
    $weatherCode{weather4lox} = $w4lCode;                                                                                     # cur_icon
    $weatherCode{description} = $desc;                                                                                        # cur_des
    $weatherCode{image}       = getValue($results, 'current', 'weather_condition_image');                                  # future use, e.g. as background image
    $weatherCode{metar}       = getMetarCode($w4lCode);                                                                       # future use, e.g. scientific theme

    $currentData{weatherCode} = \%weatherCode;

    # ozone
    $currentData{ozone} = undef;                                                                                               # cur_ozone
    
    # sky condition - calculate from symbol code
    $currentData{cloudCover} = skyConditionFromWoCode($symbol);                                                                # cur_sky

    # astro data
    my %moon;

    my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = phase();
    # age is delivered by API, , but makes no sense as phase() delivers all values
    # $moon{age} = getFormatted('%.2f', $results, 'moon', 0, 'age');
    $moon{age} = sprintf("%.2f",$moonage) + 0;                                                                                 # cur_moon_a, moon age in days
    $moon{percent} = sprintf("%.2f",$moonillum * 100) + 0;                                                                     # cur_moon_p, moon illumination in percent
    $moon{phase} = sprintf("%.2f",$moonphase * 100) + 0;                                                                       # cur_moon_ph, moon phase in percent (0% = new moon, 50% = half moon, 100% = full moon)
    $moon{direction} = getMoonDirection($moonphase);                                                                           #                - moon direction (waxing, waning)

    $currentData{moon} = \%moon;
    
    # night time - used for selecting day or night symbol (eighter night time or undef)
    $currentData{isNight} = isNighttime($symbol);

    # Build envelope and write JSON to file
    $weatherKey = "current";
    my $envelope = {
        location => $location,
        refresh  => $refresh,
        $grabberKey => {
            filename        => "$lbplogdir/$weatherKey.json",
            generatedAt     => $dtCurrent->iso8601(),
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
    my $dtResult;
    my $results;
    $i = 0;               # used for days, starts with 0 for current day, 1 for next day, etc.

    LOGINF "Reading daily weather data from API response into W4L structure at $dtCurrent.";

    # it is assumed, that the elements are ordered by time (ascending)
    for my $results (@{$resDaily}) {

        # values with additional calculations needs to be done before hash is assigned

        # time
        $dtResult = DateTime::Format::ISO8601->parse_datetime(getValue($results, 'date'));   # ISO date from API in UTC, e.g. 2026-03-13T23:00:00+00:00
        $dtResult->set_time_zone($timezone);
        
        # no longer needed, TODO: verify and clean up
        # my @label_month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
        # my $monthname  = $label_month[$dtResult->month - 1];
        # my @label_month_sh = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
        # my $monthshort = $label_month_sh[$dtResult->month - 1];
        # my @label_days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
        # my $wdayname   = $label_days[$dtResult->day_of_week % 7];
        # my @label_days_sh = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
        # my $wdayshort  = $label_days_sh[$dtResult->day_of_week % 7];

        # wind
        my $windDirAvg = getFormatted('%.0f', $results, 'wind', 'direction'); 

        # Mapping: Wetteronline Symbol => [Loxone code, Weather4Lox code, description]
        my ($loxoneCode, $w4lCode, $description);
        my $symbol = getValue($results, 'symbol');
        if (!defined $symbol) {
            LOGWARN "Wetteronline symbol for daily weather is undefined!";
            ($loxoneCode, $w4lCode, $description) = (5, 'no_data', 'No description for weather symbol'); # Default fallback
        } else {
            ($loxoneCode, $w4lCode, $description) = wetteronlineToLox($symbol);
        }

        # astro data - get moon infos for specific time of data set (translated to epoch time)
        my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = phase($dtResult->epoch);

        # Calculating min, max values from dayparts
        # humidity (min, max)
        # wind (max) for speed, gust, and direction

        my $humidityMin  = 100; # 100%
        my $humidityMax  = 0;   # 0%

        my $windSpeedMax = -1;
        my $windGustMax  = -1;
        my $windDirMax   = 0;

        # get values for all four dayparts and calculate min and max for the day
        my @dayParts = @{ getValue($results, 'dayparts') // undef };
        if (!@dayParts) {
            LOGWARN "No dayparts found for daily data on date " . getValue($results, 'date') . ", min/max values will be set to null.";
            $humidityMin = undef;
            $humidityMax = undef;

            $windSpeedMax = undef;
            $windGustMax = undef;
            $windDirMax = undef;
        } else {
            foreach my $dayPart (@dayParts) {
                my $humidity = getPercentage('%.2f', $dayPart, 'humidity');

                if (defined $humidity){
                    if ($humidity < $humidityMin) {
                        $humidityMin = $humidity;
                    }
                    if ($humidity > $humidityMax) {
                        $humidityMax = $humidity;
                    }
                }

                my $windSpeed = getFormatted('%.0f', $dayPart, 'wind', 'speed', 'kilometer_per_hour', 'value') // 0;
                my $windGust = getFormatted('%.0f', $dayPart, 'wind', 'speed', 'kilometer_per_hour', 'max_gust') // 0;
                my $windDir = getFormatted('%.0f', $dayPart, 'wind', 'direction') // 0;

                if ($windSpeed > $windSpeedMax) {
                    $windSpeedMax = $windSpeed;
                    $windDirMax = $windDir;
                }
                # if gust is present, it has preference for direction
                if ($windGust > $windGustMax) {
                    $windGustMax = $windGust;
                    $windDirMax = $windDir;
                }
            }
        }

        # dewpoint calculation
        my $dewpointAvg;
        @dayParts = @{ getValue($results, 'dayparts') // undef };
        my $sum = 0; 
        my $cnt = 0;
        for my $dayPart (@dayParts) {
            my $dewpoint = getFormatted('%.1f', $dayPart, 'dew_point', 'celsius');
            $sum += $dewpoint if defined $dewpoint;
            $cnt++ if defined $dewpoint;
        }
        $dewpointAvg = $cnt ? sprintf("%.1f", $sum / $cnt) + 0 : undef;

        push @dailyData, {

            day            => $i,                                                # dfc<X>_per, counter of day
            time => {
                # date       => getValue($results, 'date'),                      # original timestamp from API
                datetime     => _epochToIso($dtResult->epoch, $timezone),        # ISO 8601 date string in local time (e.g. "2026-03-13T02:00:00+01:00")
                epoch        => $dtResult->epoch,                                # dfc<X>_date       - UNIX timestamp
                # wdayName   => $wdayname,                                       # name of day of week, e.g. Saturday  - TODO: verify if useful, client may calculate name as well
                # wdayShort  => $wdayshort,                                      # short name of day of week, e.g. Sa (two chars)
                # monthName  => $monthname,                                      # name of month, e.g. March
                # monthShort => $monthshort,                                     # name of month, e.g. Mar (three chars
            },
            temperature => {
                min => {
                    air         => getFormatted('%.1f', $results, 'temperature', 'min', 'air'),         # dfc<X>_tt_l      - daily min temperature (°C)
                    feelsLike   => getFormatted('%.1f', $results, 'temperature', 'min', 'apparent'),    # dfc<X>_tt_fl_l   - min feels-like temperature
                    windChill   => undef,                                                               # hfc<X>_w_ch      - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
                },
                max => {
                    air         => getFormatted('%.1f', $results, 'temperature', 'max', 'air'),         # dfc<X>_tt_h      - daily max temperature (°C)
                    feelsLike   => getFormatted('%.1f', $results, 'temperature', 'max', 'apparent'),    # dfc<X>_tt_fl_h   - max feels-like temperature
                    heatIndex   => undef,                                                               # hfc<X>_hi        - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures
                },
            },
            wind => {
                avg => {
                    direction       => $windDirAvg,                                                                            # dfc<X>_w_dir_a     - wind direction (degree, average)
                    cardinal        => getWindDirCardinal($windDirAvg),                                                        # to calculate dfc<X>_w_dirdes_a  - wind direction description (average)
                    speed           => getFormatted('%.2f', $results, 'wind', 'speed', 'kilometer_per_hour', 'value'),         # dfc<X>_w_sp_a      - wind speed average (km/h)
                    gust            => getFormatted('%.2f', $results, 'wind', 'speed', 'kilometer_per_hour', 'max_gust'),      # dfc<X>_w_gu_a      - wind gust average (km/h)
                },
                max => {
                    direction       => $windDirMax,                                                                            # dfc<X>_w_dir_h     - wind direction (degree, max)
                    cardinal        => getWindDirCardinal($windDirMax),                                                        # to calculate dfc<X>_w_dirdes_h  - wind direction description (max)
                    speed           => $windSpeedMax,                                                                          # dfc<X>_w_sp_h      - wind speed max (km/h)
                    gust            => $windGustMax,                                                                           # dfc<X>_w_gu_h      - wind gust max (km/h)
                }
            },
            precipitation => {
                probability   => getPercentage('%.2f', $results, 'precipitation', 'probability'),                                                # dfc<X>_pop        - probability of precipitation (%)
                duration      => getFormatted('%.2f', $results, 'precipitation', 'duration', 'hours'),                                           #                   - duration of precipitation
                rainLow       => getFormatted('%.2f', $results, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_begin'),  #                   - precipitation (mm) from
                rainHigh      => getFormatted('%.2f', $results, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end'),    # dfc<X>_prec       - precipitation (mm) up to
                type          => getValue($results, 'precipitation', 'type'),                                                                    #                   - precipitation type
                snowLow       => getFormatted('%.2f', $results, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_begin'),      #                   - snow height (cm) from
                snowHigh      => getFormatted('%.2f', $results, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end'),        # dfc<X>_snow       - snow height (cm) up to
            },
            weatherCode => {
                loxone        => $loxoneCode,                                                   # dfc<X>_we_code   - Loxone code
                weather4lox   => $w4lCode,                                                      # dfc<X>_we_icon   - Weather4Lox icon code
                description   => $description,                                                  # dfc<X>_we_des    - description
                image         => getValue($results, 'weather_condition_image'),                 #                  - future use., e.g. as background image
                metar         => getMetarCode($w4lCode),                                        #                  - METAR cod
            },
            moon => {
                age        => getFormatted('%.2f', $results, 'moon', 'age'),                    # dfc<X>_moon_a    - moon age in days
                rise       => getTimeFormatted('%H:%M', $timezone, $results, 'moon', 'rise'),   #                  - moon rise in ISO time
                set        => getTimeFormatted('%H:%M', $timezone, $results, 'moon', 'set'),    #                  - moon set in ISO time
                percent    => sprintf("%.2f", $moonillum * 100) + 0,                              # dfc<X>_moon_p.   - moon percent
                phase      => sprintf("%.2f", $moonphase * 100) + 0,                              # dfc<X>_moon_ph.  - moon phase
                direction  => getMoonDirection($moonphase),                                     #                  - moon direction (waxing, waning)
            },
            humidity       => {
                avg        =>  getPercentage('%.2f', $results, 'humidity'),                     # dfc<X>_hu_a      - average humidity
                min        =>  $humidityMin,	                                                # dfc0_hu_l        - minimum humidity
                max        =>  $humidityMax,                                                    # dfc<X>_hu_h.     - maximum humidity
            },
            pressure         => getFormatted('%.0f', $results, 'air_pressure', 'hpa'),          # dfc<X>_pr        - air pressure (hPa)
            dewpoint         => $dewpointAvg,                                                   # dfc<X>_dp        - average dew point (°C)
            uvIndex          => getFormatted('%.1f', $results, 'uv_index', 'value'),            # dfc<X>_uvi       - UV index
            sunrise          => getTimeFormatted('%H:%M', $timezone, $results, 'sun', 'rise'),  # dfc<X>_sun_r     - sunrise time (HH:MM)
            sunset           => getTimeFormatted('%H:%M', $timezone, $results, 'sun', 'set'),   # dfc<X>_sun_s     - sunset time (HH:MM)
            visibility       => undef,                                                          # dfc<X>_vis       - visibility (m/km as needed)
            solarRadiation   => undef,                                                          # dfc<X>_sr        - solar radiation (not present)
            heatIndex        => undef,                                                          # dfc<X>_hi        - heat index (not present)
            ozone            => undef,                                                          # dfc<X>_ozone     - ozone (not present)
            cloudCover       => skyConditionFromWoCode($symbol),                                # dfc<X>_sky       - cloud/sky cover (percentage from 0 to 100)
        };
        $i++;
    }
 
    # Build envelope and write JSON to file
    $weatherKey = "dailyforecast";
    my $envelope = {
        location => $location,
        refresh  => $refresh,
        $grabberKey => {
            filename        => "$lbplogdir/$weatherKey.json",
            generatedAt     => $dtCurrent->iso8601(),
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

    my @hourlyData;
    my $dtResult;
    my $results;
    $i = 0;               # used for hours, starts with 0 for current hour, 1 for next hour, etc.

    LOGINF "Reading hourly weather data from API response into W4L structure at $dtCurrent.";

    # it is assumed, that the elements are ordered by time (ascending)
    for my $results (@{$resHourly->{hours}}) {

        # values with additional calculations needs to be done before hash is assigned

        # time
        $dtResult = DateTime::Format::ISO8601->parse_datetime(getValue($results, 'date'));   # ISO date from API in UTC, e.g. 2026-03-13T23:00:00+00:00
        $dtResult->set_time_zone($timezone);

        # wind
        my $windDir     = getFormatted('%.0f', $results, 'wind', 'direction'); 

        # Mapping: Wetteronline Symbol => [Loxone code, Weather4Lox code, description]
        my ($loxoneCode, $w4lCode, $description);
        my $symbol = getValue($results, 'symbol');
        if (!defined $symbol) {
            LOGWARN "Wetteronline symbol for hourly weather is undefined!";
            ($loxoneCode, $w4lCode, $description) = (5, 'no_data', 'No description for weather symbol');
        } else {
            ($loxoneCode, $w4lCode, $description) = wetteronlineToLox($symbol);
        }

        # astro data - get moon infos for specific time of data set (translated to epoch time)
        my ( $moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang ) = phase($dtResult->epoch);

        # Get sunrise and sunset time from daily data, needed for isNighttime calculation
        my $isNighttime = undef; # default to day (undef)

        for my $dailyresults (@{$resDaily}) {
            if (substr(getValue($dailyresults, 'date'), 0, 10) eq substr(getValue($results, 'date'), 0, 10)) {
                # we found the matching daily data for the current hourly data, now we can check the dayparts for precipitation type

                if ($dtResult->strftime('%H:%M') lt getTimeFormatted('%H:%M', $timezone, $dailyresults, 'sun', 'rise') || 
                    $dtResult->strftime('%H:%M') gt getTimeFormatted('%H:%M', $timezone, $dailyresults, 'sun', 'set')) {
                    $isNighttime = 1;
                    last; # break loop if we found the matching day and determined it is nighttime
                }
            }
        }

        push @hourlyData, {
            hour           => $i,                                                # hfc<X>_per, counter of day
            time => {
                # date       => getValue($results, 'date'),                      # original timestamp from API
                datetime     => _epochToIso($dtResult->epoch, $timezone),        # ISO 8601 date string in local time (e.g. "2026-03-13T02:00:00+01:00")
                epoch        => $dtResult->epoch,                                # hfc<X>_date       - UNIX timestamp
            },
            temperature => {
                air            => getFormatted('%.1f', $results, 'temperature', 'air'),         # hfc<X>_tt        - hourly max temperature (°C)
                feelsLike      => getFormatted('%.1f', $results, 'temperature', 'apparent'),    # hfc<X>_tt_fl     - min feels-like temperature
                heatIndex      => undef,                                                        # hfc<X>_hi        - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures
                windChill      => undef,                                                        # hfc<X>_w_ch      - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
            },
            wind => {
                direction     => $windDir,                                                                                   # hfc<X>_w_dir     - wind direction (degree)
                cardinal      => getWindDirCardinal($windDir),                                                               # to calculate hfc<X>_w_dirdes  - wind direction description
                speed         => getFormatted('%.2f', $results, 'wind', 'speed', 'kilometer_per_hour', 'value'),             # hfc<X>_w_sp      - wind speed (km/h)
                gust          => getFormatted('%.2f', $results, 'wind', 'speed', 'kilometer_per_hour', 'max_gust'),          # hfc<X>_w_gu      - wind gust (km/h)
            },
            precipitation => {
                probability   => getPercentage('%.2f', $results, 'precipitation', 'probability'),                                                # hfc<X>_pop         - probability of precipitation (%)
                duration      => getValue($results, 'precipitation', 'duration', 'hours'),                                                       #                    - duration of precipitation
                rainLow       => getFormatted('%.2f', $results, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_begin'),  #                    - precipitation (mm) from
                rainHigh      => getFormatted('%.2f', $results, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end'),    # hfc<X>_prec        - precipitation (mm) up to
                type          => getValue($results, 'precipitation', 'type'),                                                                    #                    - precipitation type
                snowLow       => getFormatted('%.2f', $results, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_begin'),      #                    - snow height (cm) from
                snowHigh      => getFormatted('%.2f', $results, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end'),        # hfc<X>_snow        - snow height (cm) up to
            },
            weatherCode => {
                loxone       => $loxoneCode,                                              # hfc<X>_we_code   - Loxone code
                weather4lox  => $w4lCode,                                                 # hfc<X>_we_icon   - Weather4Lox icon code
                description  => $description,                                             # hfc<X>_we_des    - description
                metar        => getMetarCode($w4lCode),                                   #                  - METAR code
            },
            moon => {
                age          => sprintf("%.2f", $moonage) + 0,                            # hfc<X>_moon_a    - moon age in days
                percent      => sprintf("%.2f", $moonillum * 100) + 0,                    # hfc<X>_moon_p    - moon percentage
                phase        => sprintf("%.2f", $moonphase * 100) + 0,                    # hfc<X>_moon_ph   - moon phase
                direction    => getMoonDirection($moonphase),                             #                  - moon direction (waxing, waning)

            },
            humidity         => getPercentage('%.2f', $results, 'humidity'),              # hfc<X>_hu        - humidity
            pressure         => getFormatted('%.0f', $results, 'air_pressure', 'hpa'),    # hfc<X>_pr        - air pressure (hPa)
            dewpoint         => getFormatted('%.1f', $results, 'dew_point', 'celsius'),   # hfc<X>_dp        - dew point (°C)
            uvIndex          => getFormatted('%.1f', $results, 'uv_index', 'value'),      # hfc<X>_uvi       - UV index
            visibility       => getFormatted('%.0f', $results, 'visibility'),             # hfc<X>_vis       - visibility (m/km as needed)
            solarRadiation   => undef,                                                    # hfc<X>_sr        - solar radiation (not present)
            ozone            => undef,                                                    # hfc<X>_ozone     - ozone (not present)
            cloudCover       => skyConditionFromWoCode($symbol),                          # hfc<X>_sky       - cloud/sky cover (percentage from 0 to 100)
            isNight          => $isNighttime,                                             # get nighttime information from sunrise / sunset, alternate solution woudl be from symbol code
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
    my @dpEpochs;
	
    # Collect support points for all days, each with 4 dayparts
	for my $dailyResults (@{$resDaily}) {
		my @dayParts = @{$dailyResults->{dayparts}};

		for my $dayPart (@dayParts) {
			# Convert daypart timestamp to epoch seconds
			my $ep = DateTime::Format::ISO8601->parse_datetime(getValue($dayPart, 'date'))->epoch;   # ISO date from API is in UTC, e.g. 2026-03-13T23:00:00+00:00

			push @dpEpochs, $ep;

			# Temperatures
			$t_air{$ep} = getFormatted('%.1f', $dayPart, 'temperature', 'air') + 0;
			$t_app{$ep} = getFormatted('%.1f', $dayPart, 'temperature', 'apparent') + 0;

			# Humidity (0..1) -> store as percent (0..100) and interpolate in that domain
			$hum{$ep} = getPercentage('%.2f', $dayPart, 'humidity');

			# Wind direction (deg) and speed (km/h)
			$w_dir{$ep}    = getFormatted('%.0f', $dayPart, 'wind', 'direction');
			$w_sp_kmh{$ep} = getFormatted('%.2f', $dayPart, 'wind', 'speed', 'kilometer_per_hour', 'value') + 0;
			$w_gu_kmh{$ep} = getFormatted('%.2f', $dayPart, 'wind', 'speed', 'kilometer_per_hour', 'max_gust') + 0;

			# Pressure / dew point
			$pr_hpa{$ep} = getFormatted('%.0f', $dayPart, 'air_pressure', 'hpa') + 0;
			$dp_c{$ep}   = getFormatted('%.1f', $dayPart, 'dew_point', 'celsius') + 0;

			# Rain amount: mean of interval begin/end (if present)
			if ($dayPart->{precipitation}{details}{rainfall_amount}{millimeter}) {
				my $rf = (getFormatted('%.2f', $dayPart, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_begin') +
						  getFormatted('%.2f', $dayPart, 'precipitation', 'details', 'rainfall_amount', 'millimeter', 'interval_end')) / 2;
				$prec_mm{$ep} = $rf;
			} else {
				$prec_mm{$ep} = 0;                
            }

			# Snow height (cm)
			if ($dayPart->{precipitation}{details}{snow_height}{centimeter}) {
				$snow_cm{$ep} = (getFormatted('%.2f', $dayPart, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_begin') +
						         getFormatted('%.2f', $dayPart, 'precipitation', 'details', 'snow_height', 'centimeter', 'interval_end')) / 2;
			}  else {
                $snow_cm{$ep} = 0;
            }

			# precipitation duration in minutes.  TODO: verify if daypart include duration and units
			$prec_dur{$ep} = getFormatted('%.2f', $dayPart, 'precipitation', 'duration', 'minutes')  + 0 // 0;

			# precipitation probability (0..1) -> percent (0..100)
			$pop_pct{$ep} = getPercentage('%.2f', $dayPart, 'precipitation', 'probability') + 0 // 0;

            # uv index
            $uvidx{$ep} = getFormatted('%.1f', $dayPart, 'uv_index', 'value') // 0;

			# Symbol is categorical data -> keep as step/hold value
			$symbol{$ep} = getValue($dayPart, 'symbol');
			$c_img{$ep} = getValue($dayPart, 'weather_condition_image');
		}
	}

	# 2. Step: Sort and de-duplicate epochs
    my $skipInterpolation = 0;

	@dpEpochs = sort { $a <=> $b } @dpEpochs;
	{
		my %seen;
		@dpEpochs = grep { !$seen{$_}++ } @dpEpochs;
	}
    if (!@dpEpochs) {
        LOGWARN "No dayparts to interpolate. Errors are likely, e.g. the Loxone weather emulator may show a black screen";
        $skipInterpolation = 1;
    }

    if (scalar(@dpEpochs) < 2) {
        LOGWARN("Not enough time points for interpolation: " . scalar(@dpEpochs));
        $skipInterpolation = 1;
    }

    for my $hashref (\%t_air, \%t_app, \%hum, \%w_dir, \%w_sp_kmh, \%pr_hpa, \%dp_c, \%prec_mm, \%snow_cm, \%pop_pct, \%uvidx, \%prec_dur) {
        my @defined_vals = grep { defined $_ } values %$hashref;
        if (scalar(@defined_vals) < 2) {
            LOGWARN("Not enough defined values for interpolator (" . $hashref . ")");
             $skipInterpolation = 1;
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

	# 4. Step: Create hourly data for all hours starting from '$dtResult' (time stamp from the last hourly entry) + 1h
    #          up to last available entry in dpEpochs, '$i' still counts the entry

	# Get latest time stamp 
	my $end_epoch_time = $dpEpochs[-1];

	# increase time '$dtResult' by 1 hour for next entry
	$dtResult->add(hours => 1);
	my $epochTime = $dtResult->epoch;

    # only save 5 days of hourly data to reduce loading times
	while ($epochTime <= $end_epoch_time && !$skipInterpolation && $i < 121) {

        # values with additional calculations needs to be done before hash is assigned

		# For step/hold fields (symbol -> icon/code/description and wind direction text),
		# select the field from last daypart epoch <= current hourly epoch
		my $stepEp = $dpEpochs[0];
		for my $e (@dpEpochs) {
			last if $e > $epochTime;
			$stepEp = $e;
		}

        # calculate epoch time from last entry + 1h
		$epochTime = $dtResult->epoch;

        # Mapping: Wetteronline Symbol => [Loxone code, Weather4Lox code, description]
        my ($loxoneCode, $w4lCode, $description);
        my $sym = $symbol{$stepEp};
        if (!defined $sym) {
            LOGWARN "Wetteronline symbol for hourly weather is undefined!";
            ($loxoneCode, $w4lCode, $description) = (5, 'no_data', 'Keine Beschreibung zu Wettersymbol');
        } else {
            ($loxoneCode, $w4lCode, $description) = wetteronlineToLox($sym);
        }

        # astro data

        # get moon infos for specific time of data set (translated to epoch time)
        my ($moonphase, $moonillum, $moonage, $moondist, $moonang, $sundist, $sunang) = phase($epochTime);

        # Get sunrise and sunset time from daily data, needed for isNighttime calculation
        my $isNighttime = undef; # default to day (undef)

        for my $dailyResults (@{$resDaily}) {
            if (substr(getValue($dailyResults, 'date'), 0, 10) eq $dtResult->strftime('%Y-%m-%d')) {
                # we found the matching daily data for the current hourly data, now we can check the dayparts for precipitation type

                if ($dtResult->strftime('%H:%M') lt getTimeFormatted('%H:%M', $timezone, $dailyResults, 'sun', 'rise') || 
                    $dtResult->strftime('%H:%M') gt getTimeFormatted('%H:%M', $timezone, $dailyResults, 'sun', 'set')) {
                    $isNighttime = 1;
                    last; # break loop if we found the matching day and determined it is nighttime
                }
            }
        }

        push @hourlyData, {

            hour              => $i,                                                # hfc<X>_per, counter of day
            time => {
                datetime      => _epochToIso($epochTime, $timezone),                # ISO 8601 date string in local time (e.g. "2026-03-13T02:00:00+01:00")
                epoch         => $epochTime,                                        # hfc<X>_date       - UNIX timestamp
            },
            temperature => {
                air           => sprintf("%.1f", $t_air_i->linear($epochTime)),     # hfc<X>_tt        - hourly temperature (°C)
                feelsLike     => sprintf("%.1f", $t_app_i->linear($epochTime)),     # hfc<X>_tt_fl     - min feels-like temperature
                heatIndex     => undef,                                             # hfc<X>_hi        - heat index (not present), feel-like temperature considering humidity, only relevant for high temperatures
                windChill     => undef,                                             # hfc<X>_w_ch      - wind chill (not present), feel-like temperature considering wind, only relevant for low temperatures
            },
            wind => {
                direction     => $w_dir{$stepEp},                                   # hfc<X>_w_dir     - wind direction (degree)
                cardinal      => getWindDirCardinal($w_dir{$stepEp}),               # to calculate hfc<X>_w_dirdes  - wind direction description
                speed         => sprintf("%.2f", $w_sp_i->linear($epochTime)) + 0,  # hfc<X>_w_sp      - wind speed (km/h)
                gust          => sprintf("%.2f", $w_gu_i->linear($epochTime)) + 0,  # hfc<X>_w_gu      - wind gust (km/h)
            },
            precipitation => {
                probability   => sprintf("%.0f", $pop_i->linear($epochTime)) + 0,   # hfc<X>_pop         - probability of precipitation (%)
                duration      => sprintf("%.0f", $prec_dur_i->linear($epochTime)) + 0,  #                    - duration of precipitation
                rainLow       => sprintf("%.0f", $prec_i->linear($epochTime)) + 0,  #                    - precipitation (mm) from
                rainHigh      => sprintf("%.0f", $prec_i->linear($epochTime)) + 0,  # hfc<X>_prec        - precipitation (mm) up to
                type          => $prec_type{$stepEp},                               #                    - precipitation type
                snowLow       => sprintf("%.0f", $snow_i->linear($epochTime)) + 0,  #                    - snow height (cm) from
                snowHigh      => sprintf("%.0f", $snow_i->linear($epochTime)) + 0,  # hfc<X>_snow        - snow height (cm) up to
            },
            weatherCode => {
                loxone        => $loxoneCode,                                       # hfc<X>_we_code   - Loxone code
                weather4lox   => $w4lCode,                                          # hfc<X>_we_icon   - Weather4Lox icon code
                description   => $description,                                      # hfc<X>_we_des    - description
                image         => $c_img{$stepEp},                                   #                  - future use, e.g. as background image
                metar         => getMetarCode($w4lCode),                            #                  - METAR code
            },
            moon => {
                age        => sprintf("%.2f", $moonage) + 0,                        # hfc<X>_moon_a    - moon age in days
                percent    => sprintf("%.2f", $moonillum * 100) + 0,                # hfc<X>_moon_p    - moon percentage
                phase      => sprintf("%.2f", $moonphase * 100) + 0,                # hfc<X>_moon_ph   - moon phase
                direction  => getMoonDirection($moonphase),                         #                  - moon direction (waxing, waning)
            },
            humidity         => sprintf("%.0f", $hum_i->linear($epochTime)) + 0,    # hfc<X>_hu        - humidity
            pressure         => sprintf("%.0f", $pr_i->linear($epochTime)) + 0,     # hfc<X>_pr        - air pressure (hPa)
            dewpoint         => sprintf("%.1f", $dp_i->linear($epochTime)) + 0,     # hfc<X>_dp        - dew point (°C)
            uvIndex          => sprintf("%.1f", $uvidx_i->linear($epochTime)) + 0,  # hfc<X>_uvi       - UV index
            visibility       => undef,                                              # hfc<X>_vis       - visibility (m/km), not available in dayparts!
            solarRadiation   => undef,                                              # hfc<X>_sr        - solar radiation (not present)
            ozone            => undef,                                              # hfc<X>_ozone     - ozone (not present)
            cloudCover       => skyConditionFromWoCode($sym),                       # hfc<X>_sky       - cloud/sky cover (percentage from 0 to 100)
            isNight          => $isNighttime,                                       # get nighttime information from sunrise / sunset
        };
        $dtResult->add(hours => 1);
        $i++;
    }

    # Build envelope and write JSON to file
    $weatherKey = "hourlyforecast";
    my $envelope = {
        location => $location,
        refresh  => $refresh,
        $grabberKey => {
            filename        => "$lbplogdir/$weatherKey.json",
            generatedAt     => $dtCurrent->iso8601(),
            grabberLabel    => $grabberLabel,
            grabberScript   => $grabberFile,
            schemaVersion   => "v1.0",
        },
        $weatherKey => \@hourlyData,
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