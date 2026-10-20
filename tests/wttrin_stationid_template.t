#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use Config::Simple;
use HTML::Template;
use File::Temp qw(tempdir);

sub read_file {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "Cannot read $path: $!";
    local $/;
    return <$fh>;
}

my $index = read_file("$FindBin::Bin/../webfrontend/htmlauth/index.cgi");
my $settings = read_file("$FindBin::Bin/../templates/settings.html");
my $grabber = read_file("$FindBin::Bin/../bin/grabber_wttrin.pl");

my ($template_param) = $index =~ /(\$template->param\(\s*WTTRIN_STATIONID\s*=>[^\n]+)/;
my ($station_assignment) = $grabber =~ /(my \$stationid\s*=[^\n]+)/;
my ($api_call) = $grabber =~ /(my \$results = apiCall\(.*?\n\);)/s;
die 'Cannot find wttr.in station ID handling' unless $template_param && $station_assignment && $api_call;

my $requested_url;
sub apiCall {
    my (%args) = @_;
    $requested_url = $args{url};
    return {};
}

my $dir = tempdir(CLEANUP => 1);
for my $case (
    ['"50.84", "7.01"', '50.84,7.01'],
    ['50.84,7.01', '50.84,7.01'],
    ['"50.84,7.01"', '50.84,7.01'],
    ['"-33.86", "-151.21"', '-33.86,-151.21'],
    ['"0", "0"', '0,0'],
    ['"Bonn"', 'Bonn'],
    ['"New York"', 'New York'],
    ['""', ''],
) {
    my ($input, $expected) = @$case;
    my $path = "$dir/weather4lox.cfg";
    open(my $fh, '>', $path) or die "Cannot write $path: $!";
    print {$fh} "[WTTRIN]\nSTATIONID=$input\n";
    close($fh) or die "Cannot close $path: $!";
    my $cfg = Config::Simple->new($path);
    my $pcfg = $cfg;
    my $template = HTML::Template->new(
        scalarref => \'<input value="<TMPL_VAR WTTRIN_STATIONID>">',
        associate => $cfg,
    );
    eval $template_param;
    is($@, '', "template accepts STATIONID=$input");
    is($template->output, qq(<input value="$expected">), 'GUI displays a comma-separated scalar');

    my $url = 'https://wttr.in';
    my $lang = 'de';
    eval "$station_assignment\n$api_call";
    is($@, '', "grabber accepts STATIONID=$input");
    is($requested_url, "$url/$expected?lang=de&M&3&format=j1", 'grabber requests the correct location URL');

    # The settings page saves the configuration before rendering it.
    $cfg->save;
    $cfg = Config::Simple->new($path);
    eval $template_param;
    is($@, '', 'saved configuration still renders without an array-reference error');
    is($template->output, qq(<input value="$expected">), 'location survives configuration save/reload');
}

like($settings, qr/<TMPL_VAR WTTRIN_STATIONID>/, 'settings use the scalar station ID parameter');
unlike($settings, qr/<TMPL_VAR WTTRIN\.STATIONID>/, 'settings avoid dotted station ID lookup');

done_testing();
