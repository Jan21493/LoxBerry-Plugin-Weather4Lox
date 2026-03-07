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

use LoxBerry::System;
use LoxBerry::Web;
use CGI::Carp qw(fatalsToBrowser);
use CGI;
use LWP::UserAgent;
use JSON qw( decode_json );
use utf8;
use Encode qw(encode_utf8);
use URI::Escape;
use warnings;
use strict;

##########################################################################
# Variables
##########################################################################

our $cfg;
our $pphrase;
our $lang;
our $template_title;
our $installdir;
our $planguagefile;
our $table;
our $version;
our $search;
our $queryurl;
our $res;
our $ua;
our $json;
our $decoded_json;
our $urlstatus;
our $urlstatuscode;
our $i;
our $results;
our $decoded_json;
our $lat;
our $long;
our $numrestotal;
our $template;
our $city;
our $country;
our $addon;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
$version = "4.7.0.0";

# Language
our $lang = lblanguage();

#########################################################################
# Parameter
#########################################################################

my $cgi = CGI->new;
$cgi->import_names('R');

$search = $R::search;

# Template
my $template = HTML::Template->new(
    filename => "$lbptemplatedir/addresslist.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
    #associate => $cfg,
);

my $service = $R::service;
$template->param( "SERVICE", $service);

##########################################################################
# Language Settings
##########################################################################

# Read translations
my %L = LoxBerry::Web::readlanguage($template, "language.ini");

##########################################################################
# Main program
##########################################################################

if ($search) {

  my $lang = lblanguage();
  $search = uri_escape($search);
  $queryurl = "https://nominatim.openstreetmap.org/search?q=$search&format=json&addressdetails=1&accept-language=$lang";

  # If we received a query, send it to Google API
  $ua = new LWP::UserAgent;
  $ua->agent("Weather4Lox-LoxBerry/4.15 (LoxBerry Plugin; contact: loxberry.de)");
  $ua->default_header('Accept' => 'application/json');
  $res = $ua->get($queryurl);

  $json=$res->decoded_content();
  $json = encode_utf8( $json );

  # JSON Answer - with error handling for non-JSON responses
  eval {
    $decoded_json = decode_json( $json );
  };
  if ($@) {
    my $http_status = $res->status_line;
    my $preview = substr($json, 0, 200);
    $preview =~ s/</&lt;/g;
    $preview =~ s/>/&gt;/g;
    $table = "<tr><td>Error parsing API response (HTTP $http_status).<br>Response: <code>$preview</code></td></tr>\n";
    $template->param( "TABLE", $table);
    LoxBerry::Web::head();
    print $template->output();
    LoxBerry::Web::foot();
    exit;
  }

  $urlstatus = $res->status_line;
  $urlstatuscode = substr($urlstatus,0,3);

  # Count results
  $numrestotal = 0;
  for my $results( @{$decoded_json} ){
    $numrestotal++;
  }

  if (!$numrestotal) {
    $table = "<tr><td align=\"center\">" . $L{'SETTINGS.HINT_NO_SEARCH_RESULTS'} . "</td></tr>\n";
  } else { 
    $i = 1;
      for $results( @{$decoded_json} ){
	$city = $results->{address}->{city};
	$country = $results->{address}->{country};
	$lat = sprintf "%.6f", $results->{lat};
	$long = sprintf "%.6f", $results->{lon};
	# Build field ID prefix: for "server" service, coord fields have no prefix
	my $coord_prefix = ($service eq "server") ? "" : $service;
	# Add City and Country update (skip for "server" which has no city/country fields)
	  $addon = "";
	  if ($service ne "server") {
	    $addon = ";window.opener.document.getElementById('" . $service . "city').value = '$city'";
	    $addon = $addon . ";window.opener.document.getElementById('" . $service . "country').value = '$country'";
	  }
        $table = $table . "<tr><td align=\"right\">$i\.</td><td>$results->{display_name}</td>\n";
        $table = "$table" ."<td style=\"vertical-align: middle; text-align: center\"><button type=\"button\" data-role=\"button\" data-inline=\"true\" data-mini=\"true\" onClick=\"window.opener.document.getElementById('" . $coord_prefix . "coordlat').value = '$lat';window.opener.document.getElementById('" . $coord_prefix . "coordlong').value = '$long'$addon;window.close()\"> <font size=\"-1\">" . $L{'SETTINGS.BUTTON_APPLY'} .  "</font></button></td></tr>\n";
        $i++;
      };
  }

  $template->param( "TABLE", $table);
}

LoxBerry::Web::head();
print $template->output();
LoxBerry::Web::foot();

exit;
