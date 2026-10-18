#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

sub read_file {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "Cannot read $path: $!";
    local $/;
    return <$fh>;
}

my $index = read_file("$FindBin::Bin/../webfrontend/htmlauth/index.cgi");
my $settings = read_file("$FindBin::Bin/../templates/settings.html");

like(
    $index,
    qr/\$template->param\(\s*WTTRIN_STATIONID\s*=>\s*scalar\s+\$cfg->param\('WTTRIN\.STATIONID'\)\s*\)/,
    'WTTRIN station ID is passed as a scalar template parameter'
);
like($settings, qr/<TMPL_VAR WTTRIN_STATIONID>/, 'settings use the scalar station ID parameter');
unlike($settings, qr/<TMPL_VAR WTTRIN\.STATIONID>/, 'settings avoid dotted station ID lookup');

done_testing();
