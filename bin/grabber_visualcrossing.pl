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
use JSON qw( decode_json );
use File::Copy;
use Getopt::Long;
use Time::Piece;
use Time::Seconds;
use Astro::MoonPhase;

require "$lbpbindir/grabber_utils.pl";

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

my $pcfg         = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $url          = $pcfg->param("VISUALCROSSING.URL");
my $apikey       = $pcfg->param("VISUALCROSSING.APIKEY");
my $lang         = $pcfg->param("VISUALCROSSING.LANG");
my $stationid    = $pcfg->param("VISUALCROSSING.COORDLAT") . "," . $pcfg->param("VISUALCROSSING.COORDLONG");
my $city         = $pcfg->param("VISUALCROSSING.STATION");
my $country      = $pcfg->param("VISUALCROSSING.COUNTRY");

# Grabber metadata for JSON envelope
my $grabberKey   = "visualcrossing";
my $grabberLabel = "Visual Crossing";
my $grabberFile  = "grabber_visualcrossing.pl";
my $cronMinutes  = $pcfg->param("SERVER.CRON") // 15;
my $refresh      = $cronMinutes * 60;

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

# Get data from www.visualcrossing.com (API request) for current conditions, daily and hourly forecasts
my $decoded_json = apiCall(
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
my %vc_to_lox = (
    "clear"          => ["1",  "clear"],    # 1 = Clear / Wolkenlos
    "snow"           => ["21", "snow"],     # 21 = Snow / Schneefall
    "snowshowers"    => ["24", "sleet"],    # 24 = Strong Snow Showers / Starker Schneeschauer
    "thunderrain"    => ["18", "tstorms"],  # 18 = Thunderstorms / Gewitter
    "thundershowers" => ["18", "tstorms"],  # 18 = Thunderstorms / Gewitter
    "rain"           => ["11", "rain"],     # 11 = Rain / Regen
    "showers"        => ["17", "rain"],     # 17 = Heavy Rain Showers / Kräftiger Regenschauer
    "fog"            => ["6",  "fog"],      # 6 = Fog / Nebel
    "wind"           => ["5",  "wind"],     # 5 = Overcast / Bedeckt in Loxone, but there is no better match for "wind"
    "cloudy"         => ["4",  "cloudy"],   # 4 = Very Cloudy / Stark Bewölkt
    "partlycloudy"   => ["3",  "partlycloudy"], # 3 = Cloudy / Wolkig
);

sub vc_to_lox {
    my ($weather_raw) = @_;

    # Normalize the name of the weather icon from Visual Crossing
    my $weather = lc($weather_raw);        # Lowercase
    $weather =~ s/-(?:night|day)//;        # Remove -night and -day
    $weather =~ s/-//g;                    # Remove all hyphens

    # Lookup in the hash
    my $result = $vc_to_lox{$weather};

    if ($result) {
        return ($result->[0], $result->[1]);  # (code, icon)
    } else {
        # Fallback
        LOGDEB "Unknown weather icon name from Visual Crossing: '$weather_raw' (normalized: '$weather'). Using fallback 'clear'.";
        return ("1", "clear");
    }
}

# Detect nighttime from VC icon string (contains "-night" suffix)
sub vcIsNight {
    my ($icon_raw) = @_;
    return undef unless defined $icon_raw;
    return ($icon_raw =~ /-night/) ? 1 : undef;
}

##########################################################################
# Common data
##########################################################################

my $timezone = $decoded_json->{timezone};
my $lat      = $decoded_json->{latitude};
my $lon      = $decoded_json->{longitude};

# Derive timezone short name and offset from current epoch
my $currentEpoch = $decoded_json->{currentConditions}->{datetimeEpoch};
my $generatedAt  = _epochToIso($currentEpoch, $timezone);

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
    countryCode => undef,                 # not available from VC API
    elevation   => undef,                 # not available from VC API
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

    my $cur = $decoded_json->{currentConditions};

    LOGINF "Reading current weather data from API response into W4L structure.";

    # time
    my %time;
    $time{datetime} = _epochToIso($cur->{datetimeEpoch}, $timezone);
    $time{epoch}    = $cur->{datetimeEpoch};
    $time{timezone} = $timezone;
    $time{tzShort}  = $tzShort;
    $time{tzOffset} = $tzOffset;

    # sunrise / sunset in local time HH:MM
    my ($sunrise, $sunset);
    if (defined $cur->{sunriseEpoch}) {
        my $t_sr = localtime($cur->{sunriseEpoch});
        $sunrise = sprintf("%02d:%02d", $t_sr->hour, $t_sr->min);
    }
    if (defined $cur->{sunsetEpoch}) {
        my $t_ss = localtime($cur->{sunsetEpoch});
        $sunset = sprintf("%02d:%02d", $t_ss->hour, $t_ss->min);
    }

    # temperature
    my %temperature;
    $temperature{air}       = defined $cur->{temp}      ? sprintf("%.1f", $cur->{temp}) + 0      : undef;
    $temperature{feelsLike} = defined $cur->{feelslike}  ? sprintf("%.1f", $cur->{feelslike}) + 0 : undef;
    $temperature{windChill} = defined $cur->{feelslike}  ? sprintf("%.1f", $cur->{feelslike}) + 0 : undef;
    $temperature{heatIndex} = defined $cur->{feelslike}  ? sprintf("%.1f", $cur->{feelslike}) + 0 : undef;

    # wind
    my %wind;
    my $wdeg = $cur->{winddir};
    $wind{direction} = defined $wdeg ? $wdeg + 0 : undef;
    $wind{dirLabel}  = getWindDirectionLabel($wdeg, \%L);
    $wind{speed}     = defined $cur->{windspeed} ? sprintf("%.1f", $cur->{windspeed}) + 0 : undef;
    $wind{gust}      = defined $cur->{windgust}  ? sprintf("%.1f", $cur->{windgust}) + 0  : undef;

    # precipitation
    my %precipitation;
    $precipitation{rainToday}    = undef;  # not available from VC current data
    $precipitation{rain1hr}      = defined $cur->{precip}     ? sprintf("%.2f", $cur->{precip}) + 0     : undef;
    $precipitation{probability}  = defined $cur->{precipprob} ? sprintf("%.0f", $cur->{precipprob}) + 0 : undef;
    $precipitation{type}         = $cur->{preciptype} ? $cur->{preciptype}[0] : "none";
    $precipitation{snowToday}    = undef;  # not available from VC current data
    $precipitation{snow1h}       = defined $cur->{snow} ? sprintf("%.2f", $cur->{snow}) + 0 : undef;

    # weather codes
    my %weatherCode;
    my ($loxoneCode, $w4lCode) = vc_to_lox($cur->{icon});
    $weatherCode{loxone}      = $loxoneCode;
    $weatherCode{weather4lox} = $w4lCode;
    $weatherCode{description} = $cur->{conditions};
    $weatherCode{image}       = $cur->{icon};
    $weatherCode{metar}       = getMetarCode($w4lCode);

    # moon
    my %moon;
    my ($moonphase, $moonillum, $moonage) = (phase())[0,1,2];
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
        humidity       => defined $cur->{humidity} ? $cur->{humidity} + 0 : undef,
        wind           => \%wind,
        pressure       => defined $cur->{pressure} ? sprintf("%.0f", $cur->{pressure}) + 0 : undef,
        dewpoint       => defined $cur->{dew}      ? sprintf("%.1f", $cur->{dew}) + 0      : undef,
        visibility     => defined $cur->{visibility}      ? sprintf("%.1f", $cur->{visibility}) + 0      : undef,
        solarRadiation => defined $cur->{solarradiation}  ? sprintf("%.1f", $cur->{solarradiation}) + 0  : undef,
        uvIndex        => defined $cur->{uvindex}         ? sprintf("%.0f", $cur->{uvindex}) + 0          : undef,
        precipitation  => \%precipitation,
        weatherCode    => \%weatherCode,
        ozone          => undef,
        cloudCover     => defined $cur->{cloudcover} ? $cur->{cloudcover} + 0 : undef,
        moon           => \%moon,
        isNight        => vcIsNight($cur->{icon}),
    );

    # Build envelope and write JSON to file
    my $weatherKey = "current";
    my $envelope = {
        refresh     => $refresh,
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
    $i = 0;

    LOGINF "Reading daily weather data from API response into W4L structure.";

    for my $results ( @{$decoded_json->{days}} ) {

        # time
        my %time;
        $time{datetime} = _epochToIso($results->{datetimeEpoch}, $timezone);
        $time{epoch}    = $results->{datetimeEpoch};

        # sunrise / sunset
        my ($sunrise, $sunset);
        if (defined $results->{sunriseEpoch}) {
            my $t_sr = localtime($results->{sunriseEpoch});
            $sunrise = sprintf("%02d:%02d", $t_sr->hour, $t_sr->min);
        }
        if (defined $results->{sunsetEpoch}) {
            my $t_ss = localtime($results->{sunsetEpoch});
            $sunset = sprintf("%02d:%02d", $t_ss->hour, $t_ss->min);
        }

        # temperature
        my %tempMax;
        $tempMax{air}       = defined $results->{tempmax}   ? sprintf("%.1f", $results->{tempmax}) + 0   : undef;
        $tempMax{feelsLike} = defined $results->{feelslikemax} ? sprintf("%.1f", $results->{feelslikemax}) + 0 : undef;
        $tempMax{heatIndex} = undef;  # not available separately from VC

        my %tempMin;
        $tempMin{air}       = defined $results->{tempmin}   ? sprintf("%.1f", $results->{tempmin}) + 0   : undef;
        $tempMin{feelsLike} = defined $results->{feelslikemin} ? sprintf("%.1f", $results->{feelslikemin}) + 0 : undef;
        $tempMin{windChill} = undef;  # not available separately from VC

        # wind - VC provides only one set of wind data per day, use for both avg and max
        my $wdeg = $results->{winddir};
        my %windAvg;
        $windAvg{direction} = defined $wdeg ? $wdeg + 0 : undef;
        $windAvg{dirLabel}  = getWindDirectionLabel($wdeg, \%L);
        $windAvg{speed}     = defined $results->{windspeed} ? sprintf("%.1f", $results->{windspeed}) + 0 : undef;
        $windAvg{gust}      = defined $results->{windgust}  ? sprintf("%.1f", $results->{windgust}) + 0  : undef;

        # VC has no separate max wind data, duplicate avg
        my %windMax = %windAvg;

        # humidity - VC provides only one humidity value per day
        my %humidity;
        $humidity{avg} = defined $results->{humidity} ? $results->{humidity} + 0 : undef;
        $humidity{max} = undef;  # not available from VC
        $humidity{min} = undef;  # not available from VC

        # precipitation
        my %precipitation;
        $precipitation{probability} = defined $results->{precipprob} ? sprintf("%.0f", $results->{precipprob}) + 0 : undef;
        $precipitation{rainHigh}    = defined $results->{precip} && $results->{precip} > 0 ? sprintf("%.1f", $results->{precip}) + 0 : undef;
        $precipitation{rainLow}     = undef;  # not available from VC
        $precipitation{snowHigh}    = defined $results->{snow} && $results->{snow} > 0 ? sprintf("%.1f", $results->{snow}) + 0 : undef;
        $precipitation{snowLow}     = undef;  # not available from VC
        $precipitation{duration}    = undef;  # not available from VC
        $precipitation{type}        = $results->{preciptype} ? $results->{preciptype}[0] : "none";

        # weather codes
        my %weatherCode;
        my ($loxoneCode, $w4lCode) = vc_to_lox($results->{icon});
        $weatherCode{loxone}      = $loxoneCode;
        $weatherCode{weather4lox} = $w4lCode;
        $weatherCode{description} = $results->{description};
        $weatherCode{image}       = undef;
        $weatherCode{metar}       = getMetarCode($w4lCode);

        # moon
        my %moon;
        my ($moonphase, $moonillum, $moonage) = (phase($results->{datetimeEpoch}))[0,1,2];
        $moon{age}       = sprintf("%.2f", $moonage) + 0;
        $moon{percent}   = sprintf("%.2f", $moonillum * 100) + 0;
        $moon{phase}     = sprintf("%.2f", $moonphase * 100) + 0;
        $moon{direction} = getMoonDirection($moonage);
        $moon{rise}      = undef;  # not available from VC
        $moon{set}       = undef;  # not available from VC

        push @dailyData, {
            day            => $i,
            time           => \%time,
            sunrise        => $sunrise,
            sunset         => $sunset,
            temperature    => { max => \%tempMax, min => \%tempMin },
            wind           => { avg => \%windAvg, max => \%windMax },
            humidity       => \%humidity,
            pressure       => defined $results->{pressure} ? sprintf("%.0f", $results->{pressure}) + 0 : undef,
            dewpoint       => defined $results->{dew}      ? sprintf("%.1f", $results->{dew}) + 0      : undef,
            precipitation  => \%precipitation,
            weatherCode    => \%weatherCode,
            moon           => \%moon,
            uvIndex        => defined $results->{uvindex}    ? sprintf("%.0f", $results->{uvindex}) + 0    : undef,
            visibility     => defined $results->{visibility} ? sprintf("%.1f", $results->{visibility}) + 0 : undef,
            solarRadiation => undef,
            heatIndex      => undef,
            ozone          => undef,
            cloudCover     => defined $results->{cloudcover} ? $results->{cloudcover} + 0 : undef,
        };
        $i++;
    }

    # Build envelope and write JSON to file
    my $weatherKey = "dailyforecast";
    my $envelope = {
        refresh     => $refresh,
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
    $i = 0;

    LOGINF "Reading hourly weather data from API response into W4L structure.";

    for my $resultsdays ( @{$decoded_json->{days}} ) {
        for my $h ( @{$resultsdays->{hours}} ) {

            # Skip past hours (hourly forecast contains also data for current day, subtract one hour margin)
            my $now = localtime - ONE_HOUR;
            my $hfctime = localtime($h->{datetimeEpoch});
            next if $now->epoch > $hfctime->epoch;

            # time
            my %time;
            $time{datetime} = _epochToIso($h->{datetimeEpoch}, $timezone);
            $time{epoch}    = $h->{datetimeEpoch};

            # temperature
            my %temperature;
            $temperature{air}       = defined $h->{temp}      ? sprintf("%.1f", $h->{temp}) + 0      : undef;
            $temperature{feelsLike} = defined $h->{feelslike}  ? sprintf("%.1f", $h->{feelslike}) + 0 : undef;
            $temperature{heatIndex} = undef;
            $temperature{windChill} = undef;

            # wind
            my %wind;
            my $wdeg = $h->{winddir};
            $wind{direction} = defined $wdeg ? $wdeg + 0 : undef;
            $wind{dirLabel}  = getWindDirectionLabel($wdeg, \%L);
            $wind{speed}     = defined $h->{windspeed} ? sprintf("%.1f", $h->{windspeed}) + 0 : undef;
            $wind{gust}      = defined $h->{windgust}  ? sprintf("%.1f", $h->{windgust}) + 0  : undef;

            # precipitation
            my %precipitation;
            $precipitation{probability} = defined $h->{precipprob} ? sprintf("%.0f", $h->{precipprob}) + 0 : undef;
            $precipitation{rainHigh}    = defined $h->{precip} && $h->{precip} > 0 ? sprintf("%.2f", $h->{precip}) + 0 : undef;
            $precipitation{rainLow}     = undef;
            $precipitation{snowHigh}    = defined $h->{snow} && $h->{snow} > 0 ? sprintf("%.2f", $h->{snow}) + 0 : undef;
            $precipitation{snowLow}     = undef;
            $precipitation{duration}    = undef;
            $precipitation{type}        = $h->{preciptype} ? $h->{preciptype}[0] : "none";

            # weather codes
            my %weatherCode;
            my ($loxoneCode, $w4lCode) = vc_to_lox($h->{icon});
            $weatherCode{loxone}      = $loxoneCode;
            $weatherCode{weather4lox} = $w4lCode;
            $weatherCode{description} = $h->{conditions};
            $weatherCode{metar}       = getMetarCode($w4lCode);

            # moon
            my %moon;
            my ($moonphase, $moonillum, $moonage) = (phase($h->{datetimeEpoch}))[0,1,2];
            $moon{age}       = sprintf("%.2f", $moonage) + 0;
            $moon{percent}   = sprintf("%.2f", $moonillum * 100) + 0;
            $moon{phase}     = sprintf("%.2f", $moonphase * 100) + 0;
            $moon{direction} = getMoonDirection($moonage);

            push @hourlyData, {
                hour           => $i,
                time           => \%time,
                temperature    => \%temperature,
                humidity       => defined $h->{humidity} ? $h->{humidity} + 0 : undef,
                wind           => \%wind,
                pressure       => defined $h->{pressure} ? sprintf("%.0f", $h->{pressure}) + 0 : undef,
                dewpoint       => defined $h->{dew}      ? sprintf("%.1f", $h->{dew}) + 0      : undef,
                visibility     => defined $h->{visibility}      ? sprintf("%.0f", $h->{visibility}) + 0      : undef,
                solarRadiation => defined $h->{solarradiation}  ? sprintf("%.1f", $h->{solarradiation}) + 0  : undef,
                uvIndex        => defined $h->{uvindex}         ? sprintf("%.1f", $h->{uvindex}) + 0          : undef,
                precipitation  => \%precipitation,
                weatherCode    => \%weatherCode,
                ozone          => undef,
                cloudCover     => defined $h->{cloudcover} ? $h->{cloudcover} + 0 : undef,
                moon           => \%moon,
                isNight        => vcIsNight($h->{icon}),
            };
            $i++;
        }
    }

    # Build envelope and write JSON to file
    my $weatherKey = "hourlyforecast";
    my $envelope = {
        refresh     => $refresh,
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
