#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

open(my $fh, '<', "$FindBin::Bin/../webfrontend/htmlauth/show.cgi") or die $!;
my $source = do { local $/; <$fh> };
close($fh) or die $!;
my ($builder) = $source =~ /^(sub build_tmpl_vars \{.*?^\})/ms;
die 'Cannot find build_tmpl_vars' unless defined $builder;

our (%tmpl_vars, $iconset, $webpath, $cur_we_icon, $hfc1_we_icon);
our ($home, $pcfg, $lbpconfigdir, $iconset_private);
($home, $pcfg, $lbpconfigdir, $iconset_private) = ('private') x 4;
eval $builder;
die $@ if $@;

for my $set (qw(naturalistic realistic)) {
    $iconset = $set;
    $webpath = '/plugins/weather4lox';
    $cur_we_icon = $hfc1_we_icon = 'partly_cloudy_day.png';
    build_tmpl_vars();
    is($tmpl_vars{iconset}, $set, "$set is available to preview templates");
    for my $field (qw(cur_we_icon hfc1_we_icon)) {
        my $html = '<img src="<!--$webpath-->/icons/<!--$iconset-->/<!--$' . $field . '-->">';
        $html =~ s/<!--\$(.*?)-->/exists $tmpl_vars{$1} ? $tmpl_vars{$1} : ''/ge;
        is($html, qq{<img src="/plugins/weather4lox/icons/$set/partly_cloudy_day.png">},
            "$field retains the $set subdirectory");
    }
    ok(!exists $tmpl_vars{$_}, "$_ remains excluded")
        for qw(home pcfg lbpconfigdir iconset_private);
}

done_testing();
