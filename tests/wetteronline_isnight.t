#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

open(my $fh, '<:raw', "$FindBin::Bin/../bin/grabber_wetteronline.pl")
    or die "Cannot read WetterOnline grabber: $!";
local $/;
my $source = <$fh>;
close $fh or die "Cannot close WetterOnline grabber: $!";

my ($helper) = $source =~ /(my %nightSymbol = .*?^}\n)/ms;
die 'Cannot find WetterOnline nighttime helper' unless $helper;
eval "package WetteronlineNightTest; $helper";
die $@ if $@;

for my $case (
    ['2026-10-30T23:00:00+01:00', 'mist_night', '07:00', '18:00', 'nb____', 1,
        'night image marker handles fog without a night symbol'],
    ['2026-10-30T12:00:00+01:00', 'overcast_night', '07:00', '18:00', 'md____', 1,
        'night image marker takes precedence over daytime clock'],
    ['2026-10-30T23:00:00+01:00', 'clear_day', '07:00', '18:00', 'md____', undef,
        'day image marker takes precedence over nighttime clock'],
    ['2026-10-30T06:59:00+01:00', undef, '07:00', '18:00', 'nb____', 1,
        'sunrise fallback detects nighttime'],
    ['2026-10-30T18:01:00+01:00', undef, '07:00', '18:00', 'nb____', 1,
        'sunset fallback detects nighttime'],
    ['2026-10-30T12:00:00+01:00', undef, '07:00', '18:00', 'nb____', undef,
        'sunrise/sunset fallback detects daytime'],
    ['2026-10-30T12:00:00+01:00', undef, undef, undef, 'md____', 1,
        'night symbol remains the fallback when solar data is missing'],
    ['2026-10-30T12:00:00+01:00', undef, undef, undef, 'nb____', undef,
        'fog symbol without day/night information remains unknown'],
) {
    is(
        WetteronlineNightTest::isNighttime(@{$case}[0 .. 4]),
        $case->[5],
        $case->[6],
    );
}

done_testing();
