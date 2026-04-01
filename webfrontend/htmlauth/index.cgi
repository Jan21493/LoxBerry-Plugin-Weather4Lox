#!/usr/bin/perl

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

##########################################################################
# Modules
##########################################################################

use Config::Simple '-strict';
use CGI::Carp qw(fatalsToBrowser);
use CGI;
use LWP::UserAgent;
use JSON qw( decode_json encode_json );
use LoxBerry::System;
use LoxBerry::Web;

use strict;
use warnings;

use IO::Handle ();                 # for STDOUT->autoflush
use Scalar::Util qw(looks_like_number);

##########################################################################
# Unbuffered output (important for "saving" progress)
##########################################################################
BEGIN {
    $| = 1;                          # autoflush for currently selected filehandle (STDOUT)
    STDOUT->autoflush(1);
}

##########################################################################
# Variables
##########################################################################

# Read Form
my $cgi = CGI->new;
$cgi->import_names('R');

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

# Settings
my $cfg = new Config::Simple("$lbpconfigdir/weather4lox.cfg");

$cfg->param("OPENWEATHER.URL", "https://api.openweathermap.org/data");
$cfg->param("WUNDERGROUND.URL", "https://api.weather.com/v2/pws/observations/current");
$cfg->param("FOSHK.URL", "observations/current/json/units=m");
$cfg->param("WEATHERFLOW.URL", "https://swd.weatherflow.com/swd/rest");
$cfg->param("VISUALCROSSING.URL", "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline");
$cfg->param("WTTRIN.URL", "https://wttr.in");
$cfg->param("WETTERONLINE.URL-HOURLY", "https://api-app.wetteronline.de/app/weather/hourcast?");
$cfg->param("WETTERONLINE.URL-DAILY", "https://api-app.wetteronline.de/app/weather/forecast?");
$cfg->param("WETTERONLINE.URL-CURRENT", "https://www.wetteronline.de/wetter/");
$cfg->param("OPENMETEOAIRQUALITY.URL", "https://air-quality-api.open-meteo.com/v1/air-quality");

$cfg->save();

# Upgrade fallback: populate SERVER.CITY/COUNTRY from existing per-service values
if (!$cfg->param("SERVER.CITY")) {
    my $fallback_city = $cfg->param("VISUALCROSSING.STATION")
        || $cfg->param("OPENWEATHER.STATION")
        || $cfg->param("WEATHERFLOW.CITY")
        || "";
    my $fallback_country = $cfg->param("VISUALCROSSING.COUNTRY")
        || $cfg->param("OPENWEATHER.COUNTRY")
        || $cfg->param("WEATHERFLOW.COUNTRY")
        || "";
    if ($fallback_city) {
        $cfg->param("SERVER.CITY", $fallback_city);
        $cfg->param("SERVER.COUNTRY", $fallback_country);
        $cfg->save();
    }
}

#########################################################################
# Parameter
#########################################################################

my $error;

##########################################################################
# Main program
##########################################################################

# Template
my $template = HTML::Template->new(
    filename => "$lbptemplatedir/settings.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
    associate => $cfg,
);

# Language
my %L = LoxBerry::Web::readlanguage($template, "language.ini");

##########################################################################
# Save Form 1 (Server Settings)
##########################################################################
if ($R::saveformdata1) {

    # Render only the SAVING page and start the save process in the browser via AJAX.
    $template->param( FORMNO => '1' );

    # Token: short, URL-safe, with enough entropy
    my $token = time() . "-" . int(rand(1000000)) . "-" . $$;
    $template->param( SAVETOKEN => $token );

    # Serialize all POST parameters to a JSON file so that ajax-save.cgi
    # can pick them up later (the SAVING page no longer has the form data).
    my %params = $cgi->Vars();
    my $jsonfile = "/tmp/weather4lox_save_${token}.json";
    LoxBerry::System::write_file($jsonfile, encode_json(\%params));
    chmod(0600, $jsonfile);

    $template->param( "SAVING", 1 );
    $template->param( "SAVE", 0 );
    $template->param( "ERROR", 0 );
    $template->param( "SAVINGMESSAGE", $L{'SETTINGS.SAVING_STARTING'} );

    LoxBerry::Web::lbheader($L{'SETTINGS.LABEL_PLUGINTITLE'} . " V$version",
                            "https://wiki.loxberry.de/plugins/Weather4Loxone/start",
                            "help.html");
    print $template->output();
    LoxBerry::Web::lbfooter();
    exit;
}

##########################################################################
# Save Form 2 (Miniserver)
##########################################################################
if ($R::saveformdata2) {

    $template->param( FORMNO => '2' );

    my $dfc;
    for (my $i=1;$i<=8;$i++) {
        if ( $cgi->param("dfc$i") ) {
            $dfc = $dfc ? "$dfc;$i" : $i;
        }
    }

    my $hfc;
    for (my $i=1;$i<=48;$i++) {
        if ( $cgi->param("hfc$i") ) {
            $hfc = $hfc ? "$hfc;$i" : $i;
        }
    }

    # Write configuration file(s)
    $cfg->param("SERVER.SENDDFC", "$dfc");
    $cfg->param("SERVER.SENDHFC", "$hfc");
    $cfg->param("SERVER.SENDUDP", "$R::sendudp");
    $cfg->param("SERVER.UDPPORT", "$R::udpport");
    $cfg->param("SERVER.MSNO", "$R::msno");
    $cfg->param("SERVER.TOPIC", "$R::mqtttopic");

    $cfg->save();

    save();
    exit;
}

##########################################################################
# Save Form 3 (Website)
##########################################################################
if ($R::saveformdata3) {

    $template->param( FORMNO => '3' );

    # Write configuration file(s)
    $cfg->param("SERVER.EMU", "$R::emu");
    $cfg->param("WEB.THEME", "$R::theme");
    $cfg->param("WEB.ICONSET", "$R::iconset");
    $cfg->param("WEB.LANG", "$R::themelang");

    $cfg->save();

    # Enable/Disable CloudEmu
    if ( $R::emu ) {
        system("sudo $lbpbindir/cloudemu enable > /dev/null 2>&1");
    } else {
        system("sudo $lbpbindir/cloudemu disable > /dev/null 2>&1");
    }

    save();
    exit;
}

##########################################################################
# Normal page rendering (menus)
##########################################################################

# Navbar
our %navbar;
$navbar{1}{Name} = "$L{'SETTINGS.LABEL_SERVER_SETTINGS'}";
$navbar{1}{URL} = 'index.cgi?form=1';

$navbar{2}{Name} = "$L{'SETTINGS.LABEL_MINISERVERCONNECTION'}";
$navbar{2}{URL} = 'index.cgi?form=2';

$navbar{3}{Name} = "$L{'SETTINGS.LABEL_WEBSITE'} / $L{'SETTINGS.LABEL_CLOUDEMU'}";
$navbar{3}{URL} = 'index.cgi?form=3';

$navbar{99}{Name} = "$L{'SETTINGS.LABEL_LOG'}";
$navbar{99}{URL} = 'index.cgi?form=99';

# Menu: Server
if ($R::form eq "1" || !$R::form) {

    $navbar{1}{active} = 1;
    $template->param( "FORM1", 1);


  my @values;
  my %labels;

  # Weather Service
  $template->param("CURRENT_WEATHERSERVICE", $cfg->param("SERVER.WEATHERSERVICE"));

  @values = ( 'visualcrossing', 'openweather', 'wttrin', 'wetteronline', 'weatherflow', );
  %labels = (
        'visualcrossing' => 'Visual Crossing',
        'openweather' => 'OpenWeatherMap',
        'wttrin' => 'wttr.in',
        'wetteronline' => 'WetterOnline',
        'weatherflow' => 'Weatherflow',
    );
  my $wservice = $cgi->popup_menu(
        -name    => 'weatherservice',
        -id      => 'weatherservice',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.WEATHERSERVICE'),
    );
  $template->param( WEATHERSERVICE => $wservice );

  # DFC Weather Service
  $template->param("CURRENT_WEATHERSERVICEDFC", $cfg->param("SERVER.WEATHERSERVICEDFC"));

  @values = ( 'visualcrossing', 'openweather', 'wttrin', 'wetteronline', 'weatherflow', );
  %labels = (
        'visualcrossing' => 'Visual Crossing',
        'openweather' => 'OpenWeatherMap',
        'wttrin' => 'wttr.in',
        'wetteronline' => 'WetterOnline',
        'weatherflow' => 'Weatherflow',
    );
  my $wservicedfc = $cgi->popup_menu(
        -name    => 'weatherservicedfc',
        -id      => 'weatherservicedfc',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.WEATHERSERVICEDFC'),
    );
  $template->param( WEATHERSERVICEDFC => $wservicedfc );

  # Use alternate DFC Weather Service
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $usealternatedfc = $cgi->popup_menu(
        -name    => 'usealternatedfc',
        -id      => 'usealternatedfc',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.USEALTERNATEDFC'),
    );
  $template->param( USEALTERNATEDFC => $usealternatedfc );

  # HFC Weather Service
  $template->param("CURRENT_WEATHERSERVICEHFC", $cfg->param("SERVER.WEATHERSERVICEHFC"));

  @values = ( 'visualcrossing', 'openweather', 'wttrin', 'wetteronline', 'weatherflow', );
  %labels = (
        'visualcrossing' => 'Visual Crossing',
        'openweather' => 'OpenWeatherMap',
        'wttrin' => 'wttr.in',
        'wetteronline' => 'WetterOnline',
        'weatherflow' => 'Weatherflow',
    );
  my $wservicehfc = $cgi->popup_menu(
        -name    => 'weatherservicehfc',
        -id      => 'weatherservicehfc',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.WEATHERSERVICEHFC'),
    );
  $template->param( WEATHERSERVICEHFC => $wservicehfc );

  # Use alternate HFC Weather Service
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $usealternatehfc = $cgi->popup_menu(
        -name    => 'usealternatehfc',
        -id      => 'usealternatehfc',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.USEALTERNATEHFC'),
    );
  $template->param( USEALTERNATEHFC => $usealternatehfc );

  # Units
  @values = ('1', '0' );
  %labels = (
        '1' => $L{'SETTINGS.LABEL_METRIC'},
        '0' => $L{'SETTINGS.LABEL_IMPERIAL'},
    );
  my $metric = $cgi->popup_menu(
        -name    => 'metric',
        -id      => 'metric',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.METRIC'),
    );
  $template->param( METRIC => $metric );

  # LoxGrabber
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $loxgrabber = $cgi->popup_menu(
        -name    => 'loxgrabber',
        -id      => 'loxgrabber',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.LOXGRABBER'),
    );
  $template->param( LOXGRABBER => $loxgrabber );

  # WUGrabber
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $wugrabber = $cgi->popup_menu(
        -name    => 'wugrabber',
        -id      => 'wugrabber',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.WUGRABBER'),
    );
  $template->param( WUGRABBER => $wugrabber );

  # FOSHKGrabber
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $foshkgrabber = $cgi->popup_menu(
        -name    => 'foshkgrabber',
        -id      => 'foshkgrabber',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.FOSHKGRABBER'),
    );
  $template->param( FOSHKGRABBER => $foshkgrabber );

  # PWSCatchUploadGrabber
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $pwscatchuploadgrabber = $cgi->popup_menu(
        -name    => 'pwscatchuploadgrabber',
        -id      => 'pwscatchuploadgrabber',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.PWSCATCHUPLOADGRABBER'),
    );
  $template->param( PWSCATCHUPLOADGRABBER => $pwscatchuploadgrabber );

  # OpenMeteoAirQualityGrabber
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $openmeteoairqualitygrabber = $cgi->popup_menu(
        -name    => 'openmeteoairqualitygrabber',
        -id      => 'openmeteoairqualitygrabber',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.OPENMETEOAIRQUALITYGRABBER'),
    );
  $template->param( OPENMETEOAIRQUALITYGRABBER => $openmeteoairqualitygrabber );

  # Pollen sensitivity dropdowns (0-7 scale)
  # Read defaults from config
  my %pollen_defaults = (
    grasses => $cfg->param("POLLEN.GRASS")   // 0,
    birch   => $cfg->param("POLLEN.BIRCH")   // 0,
    alder   => $cfg->param("POLLEN.ALDER")   // 0,
    mugwort => $cfg->param("POLLEN.MUGWORT") // 0,
    olive   => $cfg->param("POLLEN.OLIVE")   // 0,
    ragweed => $cfg->param("POLLEN.RAGWEED") // 0,
  );

  @values = ('0', '1', '2', '3', '4', '5', '6', '7');
  %labels = (
        '0' => $L{'SETTINGS.LABEL_POLLEN_LEVEL_0'},
        '1' => $L{'SETTINGS.LABEL_POLLEN_LEVEL_1'},
        '2' => $L{'SETTINGS.LABEL_POLLEN_LEVEL_2'},
        '3' => $L{'SETTINGS.LABEL_POLLEN_LEVEL_3'},
        '4' => $L{'SETTINGS.LABEL_POLLEN_LEVEL_4'},
        '5' => $L{'SETTINGS.LABEL_POLLEN_LEVEL_5'},
        '6' => $L{'SETTINGS.LABEL_POLLEN_LEVEL_6'},
        '7' => $L{'SETTINGS.LABEL_POLLEN_LEVEL_7'},
    );

  my $pollen_grasses = $cgi->popup_menu(
        -name    => 'pollen_grasses',
        -id      => 'pollen_grasses',
        -values  => \@values,
    -labels  => \%labels,
    -default => $pollen_defaults{grasses},
    );
  $template->param( POLLEN_GRASSES => $pollen_grasses );

  my $pollen_birch = $cgi->popup_menu(
        -name    => 'pollen_birch',
        -id      => 'pollen_birch',
        -values  => \@values,
    -labels  => \%labels,
    -default => $pollen_defaults{birch},
    );
  $template->param( POLLEN_BIRCH => $pollen_birch );

  my $pollen_alder = $cgi->popup_menu(
        -name    => 'pollen_alder',
        -id      => 'pollen_alder',
        -values  => \@values,
    -labels  => \%labels,
    -default => $pollen_defaults{alder},
    );
  $template->param( POLLEN_ALDER => $pollen_alder );

  my $pollen_mugwort = $cgi->popup_menu(
        -name    => 'pollen_mugwort',
        -id      => 'pollen_mugwort',
        -values  => \@values,
    -labels  => \%labels,
    -default => $pollen_defaults{mugwort},
    );
  $template->param( POLLEN_MUGWORT => $pollen_mugwort );

  my $pollen_olive = $cgi->popup_menu(
        -name    => 'pollen_olive',
        -id      => 'pollen_olive',
        -values  => \@values,
    -labels  => \%labels,
    -default => $pollen_defaults{olive},
    );
  $template->param( POLLEN_OLIVE => $pollen_olive );

  my $pollen_ragweed = $cgi->popup_menu(
        -name    => 'pollen_ragweed',
        -id      => 'pollen_ragweed',
        -values  => \@values,
    -labels  => \%labels,
    -default => $pollen_defaults{ragweed},
    );
  $template->param( POLLEN_RAGWEED => $pollen_ragweed );


  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $maskkeys = $cgi->popup_menu(
        -name    => 'maskkeys',
        -id      => 'maskkeys',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.MASKKEYS'),
    );
  $template->param( MASKKEYS => $maskkeys );

  # GetData
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $getdata = $cgi->popup_menu(
        -name    => 'getdata',
        -id      => 'getdata',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.GETDATA'),
    );
  $template->param( GETDATA => $getdata );

  # Cron
  @values = ('1', '3', '5', '10', '15', '30', '60' );
  %labels = (
        '1' => $L{'SETTINGS.LABEL_1MINUTE'},
        '3' => $L{'SETTINGS.LABEL_3MINUTE'},
        '5' => $L{'SETTINGS.LABEL_5MINUTE'},
        '10' => $L{'SETTINGS.LABEL_10MINUTE'},
        '15' => $L{'SETTINGS.LABEL_15MINUTE'},
        '30' => $L{'SETTINGS.LABEL_30MINUTE'},
        '60' => $L{'SETTINGS.LABEL_60MINUTE'},
    );
  my $cron = $cgi->popup_menu(
        -name    => 'cron',
        -id      => 'cron',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.CRON'),
    );
  $template->param( CRON => $cron );

  # Cron Forecast
  @values = ('0', '1', '3', '5', '10', '15', '30', '60' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_SAME_AS_DEFAULT'},
        '1' => $L{'SETTINGS.LABEL_1MINUTE'},
        '3' => $L{'SETTINGS.LABEL_3MINUTE'},
        '5' => $L{'SETTINGS.LABEL_5MINUTE'},
        '10' => $L{'SETTINGS.LABEL_10MINUTE'},
        '15' => $L{'SETTINGS.LABEL_15MINUTE'},
        '30' => $L{'SETTINGS.LABEL_30MINUTE'},
        '60' => $L{'SETTINGS.LABEL_60MINUTE'},
    );
  my $cron_alternate = $cgi->popup_menu(
        -name    => 'cron_alternate',
        -id      => 'cron_alternate',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.CRON_ALTERNATE'),
    );
  $template->param( CRON_ALTERNATE => $cron_alternate );

  # OPenweather Language
  @values = ('af', 'ar', 'az', 'bg', 'ca', 'cz', 'da', 'de', 'el', 'en', 'es', 'eu', 'fa', 'fi', 'fr', 'gl', 'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'kr', 'la', 'lt', 'mk', 'no', 'nl', 'pl', 'pt', 'pt_br', 'ro', 'ru', 'se', 'sk', 'sl', 'sr', 'th', 'tr', 'uk', 'vi', 'zh_cn', 'zh_tw', 'zu');

  %labels = (
    'af' => 'Africaans',
    'ar' => 'Arabic',
    'az' => 'Azerbaijani',
    'bg' => 'Bulgarian',
    'ca' => 'Catalan',
    'ca' => 'Catalan',
    'cz' => 'Czech',
    'da' => 'Danish',
    'de' => 'German',
    'el' => 'Greek',
    'en' => 'English',
    'es' => 'Spanish',
    'eu' => 'Basque',
    'fa' => 'Persian (Farsi)',
    'fi' => 'Finnish',
    'fr' => 'French',
    'hr' => 'Croatian',
    'ga' => 'Galician',
    'he' => 'Hebrew',
    'hi' => 'Hindi',
    'hr' => 'Croatian',
    'hu' => 'Hungarian',
    'id' => 'Indonesian',
    'it' => 'Italian',
    'ja' => 'Japanese',
    'kr' => 'Korean',
    'la' => 'Latvian',
    'lt' => 'Lithuanian',
    'mk' => 'Macedonian',
    'no' => 'Norwegian',
    'nl' => 'Dutch',
    'pl' => 'Polish',
    'pt' => 'Portuguese',
    'pt_br' => 'Portuguese Brasil',
    'ro' => 'Romanian',
    'ru' => 'Russian',
    'se' => 'Swedish',
    'sk' => 'Slovak',
    'sl' => 'Slovenian',
    'sr' => 'Serbian',
    'th' => 'Thai',
    'tr' => 'Turkish',
    'uk' => 'Ukrainian',
    'vi' => 'Vietnamese',
    'zh_cn' => 'simplified Chinese',
    'zh_tw' => 'traditional Chinese',
    'zu' => 'Zulu',
    );
  my $openweatherlang = $cgi->popup_menu(
        -name    => 'openweatherlang',
        -id      => 'openweatherlang',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('OPENWEATHER.LANG'),
    );
  $template->param( OPENWEATHERLANG => $openweatherlang );

  # Weatherflow Language
  @values = ('en');

  %labels = (
    'en' => 'English',
    );
  my $weatherflowlang = $cgi->popup_menu(
        -name    => 'weatherflowlang',
        -id      => 'weatherflowlang',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('WEATHERFLOW.LANG'),
    );
  $template->param( WEATHERFLOWLANG => $weatherflowlang );

  # VisualCrossing Language
  @values = ('de', 'en', 'es', 'fi', 'fr', 'it', 'ja', 'ko', 'pt', 'ru', 'nl', 'sr', 'zh');

  %labels = (
    'de' => 'German',
    'en' => 'English',
    'es' => 'Spanish',
    'fi' => 'Finnish',
    'fr' => 'French',
    'it' => 'Italian',
    'ja' => 'Japanese',
    'ko' => 'Korean',
    'nl' => 'Netherlands',
    'pt' => 'Portuguese',
    'ru' => 'Russian',
    'sr' => 'Serbian',
    'zh' => 'simplified Chinese',
    );
  my $visualcrossinglang = $cgi->popup_menu(
        -name    => 'visualcrossinglang',
        -id      => 'visualcrossinglang',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('VISUALCROSSING.LANG'),
    );
  $template->param( VISUALCROSSINGLANG => $visualcrossinglang );

  # wttr.in Language
  @values = ('af', 'am', 'ar', 'be', 'bn', 'ca', 'da', 'de', 'el', 'en', 'et', 'fa', 'fr', 'gl', 'hi', 'hu', 'ia', 'id', 'it', 'lt', 'mg', 'nb', 'nl', 'oc', 'pl', 'pt-br', 'ro', 'ru', 'ta', 'th', 'tr', 'uk', 'vi', 'zh-cn', 'zh-tw');

  %labels = (
    'af' => 'Africaans',
    'am' => 'Amharic',
    'ar' => 'Arabic',
    'be' => 'Belarusian',
    'bn' => 'Bengali',
    'ca' => 'Catalan',
    'da' => 'Danish',
    'de' => 'German',
    'el' => 'Greek',
    'en' => 'English',
    'et' => 'Estonian',
    'fa' => 'Persian (Farsi)',
    'fr' => 'French',
    'gl' => 'Galician',
    'hi' => 'Hindi',
    'ia' => 'Interlingua',
    'id' => 'Indonesian',
    'it' => 'Italian',
    'lt' => 'Lithuanian',
    'mg' => 'Malagasy',
    'nb' => 'Norwegian Bokmal',
    'nl' => 'Dutch',
    'oc' => 'Occitan',
    'pl' => 'Polish',
    'pt-br' => 'Portuguese Brasil',
    'ro' => 'Romanian',
    'ru' => 'Russian',
    'ta' => 'Tamil',
    'th' => 'Thai',
    'tr' => 'Turkish',
    'uk' => 'Ukrainian',
    'vi' => 'Vietnamese',
    'zh-cn' => 'simplified Chinese',
    'zh-tw' => 'traditional Chinese',
    );
  my $wttrinweatherlang = $cgi->popup_menu(
        -name    => 'wttrinlang',
        -id      => 'wttrinlang',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('WTTRIN.LANG'),
    );
  $template->param( WTTRINLANG => $wttrinweatherlang );

  # Central language selector (used by all services)
  @values = ('de', 'en', 'da', 'el', 'es', 'fa', 'fr', 'hi', 'hu', 'id', 'it', 'lt', 'nl', 'pl', 'ro', 'ru', 'th', 'tr', 'uk', 'vi');
  %labels = (
    'da' => 'Danish',
    'de' => 'German',
    'el' => 'Greek',
    'en' => 'English',
    'es' => 'Spanish',
    'fa' => 'Persian',
    'fr' => 'French',
    'hi' => 'Hindi',
    'hu' => 'Hungarian',
    'id' => 'Indonesian',
    'it' => 'Italian',
    'lt' => 'Lithuanian',
    'nl' => 'Dutch',
    'pl' => 'Polish',
    'ro' => 'Romanian',
    'ru' => 'Russian',
    'th' => 'Thai',
    'tr' => 'Turkish',
    'uk' => 'Ukrainian',
    'vi' => 'Vietnamese',
  );
  my $serverlang = $cgi->popup_menu(
        -name    => 'serverlang',
        -id      => 'serverlang',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.LANG') || 'en',
  );
  $template->param( SERVERLANG => $serverlang );


# Menu: Miniserver
} elsif ($R::form eq "2") {
  $navbar{2}{active} = 1;
  $template->param( "FORM2", 1);
  $template->param( "WEBSITE", "http://$ENV{HTTP_HOST}/plugins/$lbpplugindir/weatherdata.html");

  # Miniserver
  my $mshtml = mslist_select_html( FORMID => 'msno', SELECTED => $cfg->param('SERVER.MSNO'), DATA_MINI => 1 );
  $template->param( MINISERVER => $mshtml );

  # SendUDP
  my @values = ('0', '1' );
  my %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $sendudp = $cgi->popup_menu(
        -name    => 'sendudp',
        -id      => 'sendudp',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.SENDUDP'),
    );
  $template->param( SENDUDP => $sendudp );

  # DFC
  my $dfc;
  my $n;
  my $checked;
  my @fields = split(/;/,$cfg->param('SERVER.SENDDFC'));
  for (my $i=1;$i<=8;$i++) {
    $checked = 0;
    foreach ( split( /;/,$cfg->param('SERVER.SENDDFC') ) ) {
      if ($_ eq $i) {
        $checked = 1;
      }
    }
    $n = $i-1;
    $dfc .= $cgi->checkbox(
        -name    => "dfc$i",
        -id      => "dfc$i",
    -checked => $checked,
        -value   => '1',
    -label   => "+$n $L{'SETTINGS.LABEL_DAYS'}",
      );
  }
  $template->param( DFC => $dfc );

  # HFC
  my $hfc;
  @fields = split(/;/,$cfg->param('SERVER.SENDHFC'));
  for (my $i=1;$i<=48;$i++) {
    $checked = 0;
    foreach ( split( /;/,$cfg->param('SERVER.SENDHFC') ) ) {
      if ($_ eq $i) {
        $checked = 1;
      }
    }
    $hfc .= $cgi->checkbox(
        -name    => "hfc$i",
        -id      => "hfc$i",
    -checked => $checked,
        -value   => '1',
    -label   => "+$i $L{'SETTINGS.LABEL_HOURS'}",
      );
  }
  $template->param( HFC => $hfc );

# Menu: Cloudweather / Website
} elsif ($R::form eq "3") {
  $navbar{3}{active} = 1;
  $template->param( "FORM3", 1);
  $template->param( "WEBSITE", "http://$ENV{HTTP_HOST}/plugins/$lbpplugindir/webpage.html");

  # Check for installed DNSMASQ-Plugin
  my $checkdnsmasq = LoxBerry::System::plugindata('DNSmasq');
  if ( $checkdnsmasq->{PLUGINDB_TITLE} ) {
    $template->param( EMUWARNING => $L{'SETTINGS.ERR_DNSMASQ_PLUGIN'} );
  }

  # Cloudweather Emu
  my @values = ('0', '1' );
  my %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $emu = $cgi->popup_menu(
        -name    => 'emu',
        -id      => 'emu',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('SERVER.EMU'),
    );
  $template->param( EMU => $emu );
  $template->param( MYIP => LoxBerry::System::get_localip() );

  # Theme
  my @values = ('dark', 'light', 'fresh', 'arctic', 'ocean', 'custom' );
  my %labels = (
        'dark' => "Dark Theme (Classic)",
        'light' => "Light Theme (Classic)",
        'fresh' => "Fresh Theme (New Style)",
        'arctic' => "Arctic Mist Theme (New Style)",
        'ocean' => "Deep Ocean Theme (New Style)",
        'custom' => "Custom Theme (your own)",
    );
  my $theme = $cgi->popup_menu(
        -name    => 'theme',
        -id      => 'theme',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('WEB.THEME'),
    );
  $template->param( THEME => $theme );

  # Icon Set
  my @values = ('color', 'flat', 'dark', 'light', 'green', 'silver', 'realistic', 'naturalistic', 'custom' );
  my %labels = (
        'color' => "Color Set (42 icons, PNG format, 150x150)",
        'flat' => "Flat Set (42 icons, PNG format, 150x150)",
        'dark' => "Dark Set (42 icons, PNG format, 150x150)",
        'darksvg' => "Dark SVG Set (42 icons, SVG format, scalable)",
        'light' => "Light Set (42 icons, PNG format, 150x150)",
        'green' => "Green Set (42 icons, PNG format, 150x150)",
        'silver' => "Silver Set (42 icons, SVG format, scalable)",
        'realistic' => "Realistic Set (26 icons, PNG format, 150x150)",
        'naturalistic' => "Naturalistic Set (168 icons, PNG format, 600x600)",
        'custom' => "Custom Set",
    );
  my $iconset = $cgi->popup_menu(
        -name    => 'iconset',
        -id      => 'iconset',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('WEB.ICONSET'),
    );
  $template->param( ICONSET => $iconset );

  # Theme LANG
  @values = ('at', 'nl', 'en', 'de', 'es' );
  %labels = (
        'at' => "Austrian",
        'nl' => "Dutch",
        'en' => "English",
        'de' => "German",
        'es' => "Spanish",
    );
  my $themelang = $cgi->popup_menu(
        -name    => 'themelang',
        -id      => 'themelang',
        -values  => \@values,
    -labels  => \%labels,
    -default => $cfg->param('WEB.LANG'),
    );
  $template->param( THEMELANG => $themelang );

# Menu: Logfiles
} elsif ($R::form eq "99") {
  $navbar{99}{active} = 1;
  $template->param( "FORM99", 1 );
  $template->param( "LOGLIST_HTML", LoxBerry::Web::loglist_html() );

}

# Template Vars and Form parts
$template->param( "LBPPLUGINDIR", $lbpplugindir);

# Template
LoxBerry::Web::lbheader($L{'SETTINGS.LABEL_PLUGINTITLE'} . " V$version", "https://wiki.loxberry.de/plugins/Weather4Loxone/start", "help.html");
print $template->output();
LoxBerry::Web::lbfooter();

exit;


# globals:
my $saving_page_started = 0;

##########################################################################
# Error
##########################################################################
sub error {
    my ($err) = @_;
    if ($saving_page_started) {
        my $msg = $err // '';
        $msg =~ s/\\/\\\\/g; $msg =~ s/"/\\"/g; $msg =~ s/\r?\n/\\n/g;
        print qq{
          <script>
            (function(){
              var el = document.getElementById('savinglog');
              if(el){ el.textContent += "\\nERROR: $msg\\n"; }
            })();
          </script>
        };
        STDOUT->flush();
        LoxBerry::Web::lbfooter();
        exit;
    }

    $template->param( "SAVING", 0);
    $template->param( "ERROR", 1);
    $template->param( "ERRORMESSAGE", $err);

    LoxBerry::Web::lbheader($L{'SETTINGS.LABEL_PLUGINTITLE'} . " V$version", "https://wiki.loxberry.de/plugins/Weather4Loxone/start", "help.html");
    print $template->output();
    STDOUT->flush();
    LoxBerry::Web::lbfooter();
    exit;
}

##########################################################################
# Save
##########################################################################
sub save {
    if ($saving_page_started) {
        print qq{<script>window.location.href="./index.cgi?form=$R::form";</script>};
        STDOUT->flush();
        LoxBerry::Web::lbfooter();
        exit;
    }

    $template->param( "SAVING", 0);
    $template->param( "SAVE", 1);

    LoxBerry::Web::lbheader($L{'SETTINGS.LABEL_PLUGINTITLE'} . " V$version", "https://wiki.loxberry.de/plugins/weather4loxone/start", "help.html");
    print $template->output();
    STDOUT->flush();
    LoxBerry::Web::lbfooter();
    exit;
}
