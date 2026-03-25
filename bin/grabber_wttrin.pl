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

# Grabber metadata for JSON envelope
my $grabberKey   = "wttrin";
my $grabberLabel = "wttr.in";
my $grabberFile  = "grabber_wttrin.pl";
my $cronMinutes  = $pcfg->param("SERVER.CRON") // 15;
my $refresh      = $cronMinutes * 60;

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => "$grabberLabel",
	logdir => "$lbplogdir",
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

LOGSTART "Weather4Lox $grabberLabel GRABBER process started";
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
my $decoded_json = apiCall(
	url => "$url/$stationid?lang=$lang&M&3&format=j1",
	info => "for Location $stationid (Current, Daily, and Hourly Weather Data)",
);

##########################################################################
# Common data
##########################################################################

my $timezone = _systemTimezone();
my $lat      = $decoded_json->{nearest_area}[0]->{latitude};
my $lon      = $decoded_json->{nearest_area}[0]->{longitude};

# Derive generatedAt from current observation time
my $obs_t = Time::Piece->strptime($decoded_json->{current_condition}[0]->{localObsDateTime}, "%Y-%m-%d %R %p");
my $currentEpoch = $obs_t->epoch;
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

my $city    = Encode::decode("UTF-8", $decoded_json->{nearest_area}[0]->{areaName}[0]->{value});
my $country = Encode::decode("UTF-8", $decoded_json->{nearest_area}[0]->{country}[0]->{value});

my $location = {
    city        => $city,
    country     => $country,
    countryCode => undef,
    elevation   => undef,
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

    my $cur = $decoded_json->{current_condition}[0];

    LOGINF "Reading current weather data from API response into W4L structure.";

    # time
    my %time;
    $time{datetime} = _epochToIso($currentEpoch, $timezone);
    $time{epoch}    = $currentEpoch;
    $time{timezone} = $timezone;
    $time{tzShort}  = $tzShort;
    $time{tzOffset} = $tzOffset;

    # sunrise / sunset from astronomy data
    my ($sunrise, $sunset);
    eval {
        my $sr_t = Time::Piece->strptime($decoded_json->{weather}[0]->{astronomy}[0]{sunrise}, "%R %p");
        $sunrise = sprintf("%02d:%02d", $sr_t->hour, $sr_t->min);
    };
    eval {
        my $ss_t = Time::Piece->strptime($decoded_json->{weather}[0]->{astronomy}[0]{sunset}, "%R %p");
        $sunset = sprintf("%02d:%02d", $ss_t->hour, $ss_t->min);
    };

    # temperature
    my %temperature;
    $temperature{air}       = defined $cur->{temp_C}     ? sprintf("%.1f", $cur->{temp_C}) + 0     : undef;
    $temperature{feelsLike} = defined $cur->{FeelsLikeC} ? sprintf("%.1f", $cur->{FeelsLikeC}) + 0 : undef;
    $temperature{windChill} = defined $cur->{FeelsLikeC} ? sprintf("%.1f", $cur->{FeelsLikeC}) + 0 : undef;
    $temperature{heatIndex} = undef;  # not available from wttr.in current

    # wind
    my %wind;
    my $wdeg = $cur->{winddirDegree};
    $wind{direction} = defined $wdeg ? $wdeg + 0 : undef;
    $wind{cardinal}  = getWindDirCardinal($wdeg);
    $wind{speed}     = defined $cur->{windspeedKmph} ? sprintf("%.1f", $cur->{windspeedKmph}) + 0 : undef;
    $wind{gust}      = undef;  # wttr.in current has no gust data

    # precipitation
    my %precipitation;
    $precipitation{rainToday}    = undef;  # not available
    $precipitation{rain1hr}      = defined $cur->{precipMM} ? sprintf("%.2f", $cur->{precipMM}) + 0 : undef;
    $precipitation{probability}  = undef;  # not available from current
    $precipitation{type}         = "none";
    $precipitation{snowToday}    = undef;
    $precipitation{snow1h}       = undef;

    # weather codes
    my %weatherCode;
    my $wwo_id = $cur->{weatherCode};
    my ($loxoneCode, $w4lCode) = wttr_to_lox($wwo_id);
    $weatherCode{loxone}      = "$loxoneCode";
    $weatherCode{weather4lox} = $w4lCode;
    my $wdes = $cur->{'lang_' . $lang}[0]{value};
    $wdes = $cur->{weatherDesc}[0]{value} if !$wdes;
    $weatherCode{description} = $wdes;
    $weatherCode{image}       = undef;  # wttr.in has no image field
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
        dewpoint       => undef,  # not available from wttr.in current
        visibility     => defined $cur->{visibility} ? sprintf("%.0f", $cur->{visibility}) + 0 : undef,
        solarRadiation => undef,
        uvIndex        => defined $cur->{uvIndex} ? sprintf("%.0f", $cur->{uvIndex}) + 0 : undef,
        precipitation  => \%precipitation,
        weatherCode    => \%weatherCode,
        ozone          => undef,
        cloudCover     => defined $cur->{cloudcover} ? $cur->{cloudcover} + 0 : undef,
        moon           => \%moon,
        isNight        => undef,  # wttr.in does not provide day/night info
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
    my $i = 0;

    LOGINF "Reading daily weather data from API response into W4L structure.";

    for my $results ( @{$decoded_json->{weather}} ) {

        my $dt = Time::Piece->strptime($results->{date}, "%Y-%m-%d");

        # time
        my %time;
        $time{datetime} = _epochToIso($dt->epoch, $timezone);
        $time{epoch}    = $dt->epoch;

        # sunrise / sunset from astronomy data
        my ($sunrise, $sunset);
        eval {
            my $sr_t = Time::Piece->strptime($results->{astronomy}[0]{sunrise}, "%R %p");
            $sunrise = sprintf("%02d:%02d", $sr_t->hour, $sr_t->min);
        };
        eval {
            my $ss_t = Time::Piece->strptime($results->{astronomy}[0]{sunset}, "%R %p");
            $sunset = sprintf("%02d:%02d", $ss_t->hour, $ss_t->min);
        };

        # Aggregate hourly values for min/max/avg calculations
        my @d_pops;
        my $d_prec = 0;
        my @d_gusts;
        my @d_winds;
        my @d_winddirs;
        my @d_hums;
        my @d_pressures;
        my @d_dewps;
        my @d_viss;
        for my $hr ( @{$results->{hourly}} ) {
            push @d_pops, $hr->{chanceofrain} if $hr->{chanceofrain};
            $d_prec += $hr->{precipMM} * 3 if $hr->{precipMM};  # 3-hourly FC
            push @d_gusts, $hr->{WindGustKmph} if $hr->{WindGustKmph};
            push @d_winds, $hr->{windspeedKmph} if $hr->{windspeedKmph};
            push @d_winddirs, $hr->{winddirDegree} if $hr->{winddirDegree};
            push @d_hums, $hr->{humidity} if $hr->{humidity};
            push @d_pressures, $hr->{pressure} if $hr->{pressure};
            push @d_dewps, $hr->{DewPointC} if $hr->{DewPointC};
            push @d_viss, $hr->{visibility} if $hr->{visibility};
        }
        @d_pops = sort { $a <=> $b } @d_pops;
        @d_gusts = sort { $a <=> $b } @d_gusts;
        @d_winds = sort { $a <=> $b } @d_winds;
        @d_winddirs = sort { $a <=> $b } @d_winddirs;
        @d_hums = sort { $a <=> $b } @d_hums;
        @d_pressures = sort { $a <=> $b } @d_pressures;
        @d_dewps = sort { $a <=> $b } @d_dewps;
        @d_viss = sort { $a <=> $b } @d_viss;

        my $d_windavg = @d_winds ? eval(join("+", @d_winds)) / @d_winds : undef;
        my $d_wdiravg = @d_winddirs ? eval(join("+", @d_winddirs)) / @d_winddirs : undef;
        my $d_humavg = @d_hums ? eval(join("+", @d_hums)) / @d_hums : undef;
        my $d_pressavg = @d_pressures ? eval(join("+", @d_pressures)) / @d_pressures : undef;
        my $d_dewpavg = @d_dewps ? eval(join("+", @d_dewps)) / @d_dewps : undef;
        my $d_visavg = @d_viss ? eval(join("+", @d_viss)) / @d_viss : undef;

        # temperature
        my %tempMax;
        $tempMax{air}       = defined $results->{maxtempC} ? sprintf("%.1f", $results->{maxtempC}) + 0 : undef;
        $tempMax{feelsLike} = undef;  # not available per-day from wttr.in
        $tempMax{heatIndex} = undef;

        my %tempMin;
        $tempMin{air}       = defined $results->{mintempC} ? sprintf("%.1f", $results->{mintempC}) + 0 : undef;
        $tempMin{feelsLike} = undef;
        $tempMin{windChill} = undef;

        # wind avg
        my %windAvg;
        $windAvg{direction} = defined $d_wdiravg ? sprintf("%.0f", $d_wdiravg) + 0 : undef;
        $windAvg{cardinal}  = getWindDirCardinal($d_wdiravg);
        $windAvg{speed}     = defined $d_windavg ? sprintf("%.0f", $d_windavg) + 0 : undef;
        $windAvg{gust}      = undef;

        # wind max (gust-based)
        my %windMax;
        $windMax{direction} = undef;  # no separate max wind direction from wttr.in
        $windMax{cardinal}  = undef;
        $windMax{speed}     = $d_gusts[-1] ? sprintf("%.0f", $d_gusts[-1]) + 0 : undef;
        $windMax{gust}      = undef;

        # humidity
        my %humidity;
        $humidity{avg} = defined $d_humavg ? sprintf("%.0f", $d_humavg) + 0 : undef;
        $humidity{max} = $d_hums[-1] ? sprintf("%.0f", $d_hums[-1]) + 0 : undef;
        $humidity{min} = $d_hums[0]  ? sprintf("%.0f", $d_hums[0]) + 0  : undef;

        # precipitation
        my %precipitation;
        $precipitation{probability} = $d_pops[-1] ? sprintf("%.0f", $d_pops[-1]) + 0 : undef;
        $precipitation{rainHigh}    = $d_prec > 0 ? sprintf("%.2f", $d_prec) + 0 : undef;
        $precipitation{rainLow}     = undef;
        $precipitation{snowHigh}    = defined $results->{totalSnow_cm} && $results->{totalSnow_cm} > 0
                                        ? sprintf("%.1f", $results->{totalSnow_cm}) + 0 : undef;
        $precipitation{snowLow}     = undef;
        $precipitation{duration}    = undef;
        $precipitation{type}        = "none";

        # weather codes - use noon (index 4) hourly data
        my %weatherCode;
        my $d_wwo_id = $results->{hourly}[4]->{weatherCode};
        my ($loxoneCode, $w4lCode) = wttr_to_lox($d_wwo_id);
        $weatherCode{loxone}      = "$loxoneCode";
        $weatherCode{weather4lox} = $w4lCode;
        my $wdes = $results->{hourly}[4]->{'lang_' . $lang}[0]{value};
        $wdes = $results->{hourly}[4]->{weatherDesc}[0]{value} if !$wdes;
        $weatherCode{description} = $wdes;
        $weatherCode{image}       = undef;
        $weatherCode{metar}       = getMetarCode($w4lCode);

        # moon
        my %moon;
        my ($moonphase, $moonillum, $moonage) = (phase($dt->epoch))[0,1,2];
        $moon{age}       = sprintf("%.2f", $moonage) + 0;
        $moon{percent}   = sprintf("%.2f", $moonillum * 100) + 0;
        $moon{phase}     = sprintf("%.2f", $moonphase * 100) + 0;
        $moon{direction} = getMoonDirection($moonage);
        $moon{rise}      = undef;  # not available from wttr.in
        $moon{set}       = undef;

        push @dailyData, {
            day            => $i,
            time           => \%time,
            sunrise        => $sunrise,
            sunset         => $sunset,
            temperature    => { max => \%tempMax, min => \%tempMin },
            wind           => { avg => \%windAvg, max => \%windMax },
            humidity       => \%humidity,
            pressure       => defined $d_pressavg ? sprintf("%.0f", $d_pressavg) + 0 : undef,
            dewpoint       => defined $d_dewpavg  ? sprintf("%.1f", $d_dewpavg) + 0  : undef,
            precipitation  => \%precipitation,
            weatherCode    => \%weatherCode,
            moon           => \%moon,
            uvIndex        => defined $results->{uvIndex} ? sprintf("%.1f", $results->{uvIndex}) + 0 : undef,
            visibility     => defined $d_visavg ? sprintf("%.1f", $d_visavg) + 0 : undef,
            solarRadiation => undef,
            heatIndex      => undef,
            ozone          => undef,
            cloudCover     => undef,
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
    my $i = 0;

    LOGINF "Reading hourly weather data from API response into W4L structure.";

    # Parse 3-hourly data into interpolation hashes
    my %temps;  my $temps;
    my %fltemps; my $fltemps;
    my %hums;   my $hums;
    my %winddirs; my $winddirs;
    my %winds;  my $winds;
    my %gusts;  my $gusts;
    my %pressures; my $pressures;
    my %dewps;  my $dewps;
    my %clouds; my $clouds;
    my %uvis;   my $uvis;
    my %his;    my $his;
    my %precs;  my $precs;
    my %pops;   my $pops;
    my %codes;
    my %weatherdess;
    my %viss;   my $viss;
    my @epoches;

    for my $daily_entry ( @{$decoded_json->{weather}} ) {
        for my $hr ( @{$daily_entry->{hourly}} ) {
            my $datetime = $daily_entry->{date} . " " . $hr->{time}/100 . ":00";
            my $t = Time::Piece->strptime($datetime, "%Y-%m-%d %H:%M");
            my $ep = $t->epoch;
            push ( @epoches, $ep );
            $temps{$ep} = $hr->{tempC};
            $temps = Math::Function::Interpolator::Linear->new( points => \%temps );
            $fltemps{$ep} = $hr->{FeelsLikeC};
            $fltemps = Math::Function::Interpolator::Linear->new( points => \%fltemps );
            $hums{$ep} = $hr->{humidity};
            $hums = Math::Function::Interpolator::Linear->new( points => \%hums );
            $winddirs{$ep} = $hr->{winddirDegree};
            $winddirs = Math::Function::Interpolator::Linear->new( points => \%winddirs );
            $winds{$ep} = $hr->{windspeedKmph};
            $winds = Math::Function::Interpolator::Linear->new( points => \%winds );
            $gusts{$ep} = $hr->{WindGustKmph};
            $gusts = Math::Function::Interpolator::Linear->new( points => \%gusts );
            $pressures{$ep} = $hr->{pressure};
            $pressures = Math::Function::Interpolator::Linear->new( points => \%pressures );
            $dewps{$ep} = $hr->{DewPointC};
            $dewps = Math::Function::Interpolator::Linear->new( points => \%dewps );
            $clouds{$ep} = $hr->{cloudcover};
            $clouds = Math::Function::Interpolator::Linear->new( points => \%clouds );
            $uvis{$ep} = $hr->{uvIndex};
            $uvis = Math::Function::Interpolator::Linear->new( points => \%uvis );
            $his{$ep} = $hr->{HeatIndexC};
            $his = Math::Function::Interpolator::Linear->new( points => \%his );
            $precs{$ep} = $hr->{precipMM};
            $precs = Math::Function::Interpolator::Linear->new( points => \%precs );
            $pops{$ep} = $hr->{chanceofrain};
            $pops = Math::Function::Interpolator::Linear->new( points => \%pops );
            $codes{$ep} = $hr->{weatherCode};
            if ($hr->{'lang_' . $lang}[0]->{value}) {
                $weatherdess{$ep} = $hr->{'lang_' . $lang}[0]->{value};
            } else {
                $weatherdess{$ep} = $hr->{weatherDesc}[0]->{value};
            }
            $viss{$ep} = $hr->{visibility};
            $viss = Math::Function::Interpolator::Linear->new( points => \%viss );
        }
    }

    # Create hourly data set with interpolation from 3-hourly data
    my $now = time();
    @epoches = sort { $a <=> $b } @epoches;
    my $startep = $epoches[0];
    my $endep = $epoches[-1];

    for (my $ep = $startep; $ep <= $endep; $ep += 3600) {
        next if $now >= $ep;  # skip past hours

        # time
        my %time;
        $time{datetime} = _epochToIso($ep, $timezone);
        $time{epoch}    = $ep;

        # temperature
        my %temperature;
        $temperature{air}       = sprintf("%.1f", $temps->linear($ep)) + 0;
        $temperature{feelsLike} = sprintf("%.1f", $fltemps->linear($ep)) + 0;
        $temperature{heatIndex} = undef;
        $temperature{windChill} = undef;

        # wind
        my %wind;
        my $wdeg = $winddirs->linear($ep);
        $wind{direction} = defined $wdeg ? sprintf("%.0f", $wdeg) + 0 : undef;
        $wind{cardinal}  = getWindDirCardinal($wdeg);
        $wind{speed}     = sprintf("%.1f", $winds->linear($ep)) + 0;
        $wind{gust}      = undef;  # wttr.in gust data is unreliable for interpolated hours

        # precipitation
        my %precipitation;
        $precipitation{probability} = sprintf("%.0f", $pops->linear($ep)) + 0;
        $precipitation{rainHigh}    = sprintf("%.2f", $precs->linear($ep)) + 0;
        $precipitation{rainHigh}    = undef if $precipitation{rainHigh} == 0;
        $precipitation{rainLow}     = undef;
        $precipitation{snowHigh}    = undef;
        $precipitation{snowLow}     = undef;
        $precipitation{duration}    = undef;
        $precipitation{type}        = "none";

        # Get nearest weather code (codes are not interpolatable)
        my ($wwo_id, $weatherdes);
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
            $wwo_id = 113;
            $weatherdes = Encode::decode("UTF-8", "Unknown");
        }

        # weather codes
        my %weatherCode;
        my ($loxoneCode, $w4lCode) = wttr_to_lox($wwo_id);
        $weatherCode{loxone}      = "$loxoneCode";
        $weatherCode{weather4lox} = $w4lCode;
        $weatherCode{description} = $weatherdes;
        $weatherCode{metar}       = getMetarCode($w4lCode);

        # moon
        my %moon;
        my ($moonphase, $moonillum, $moonage) = (phase($ep))[0,1,2];
        $moon{age}       = sprintf("%.2f", $moonage) + 0;
        $moon{percent}   = sprintf("%.2f", $moonillum * 100) + 0;
        $moon{phase}     = sprintf("%.2f", $moonphase * 100) + 0;
        $moon{direction} = getMoonDirection($moonage);

        push @hourlyData, {
            hour           => $i,
            time           => \%time,
            temperature    => \%temperature,
            humidity       => sprintf("%.0f", $hums->linear($ep)) + 0,
            wind           => \%wind,
            pressure       => sprintf("%.0f", $pressures->linear($ep)) + 0,
            dewpoint       => sprintf("%.1f", $dewps->linear($ep)) + 0,
            visibility     => sprintf("%.1f", $viss->linear($ep)) + 0,
            solarRadiation => undef,
            uvIndex        => sprintf("%.0f", $uvis->linear($ep)) + 0,
            precipitation  => \%precipitation,
            weatherCode    => \%weatherCode,
            ozone          => undef,
            cloudCover     => sprintf("%.0f", $clouds->linear($ep)) + 0,
            moon           => \%moon,
            isNight        => undef,
        };
        $i++;
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
