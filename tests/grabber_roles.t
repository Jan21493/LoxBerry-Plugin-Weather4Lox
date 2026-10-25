#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use JSON::PP qw(encode_json decode_json);

sub read_file {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "Cannot read $path: $!";
    local $/;
    return <$fh>;
}

my %expected = (
    foshk                => ['localStation', 1],
    foshk2               => ['localStation', 1],
    loxone               => ['localStation', 1],
    pwscatchupload       => ['localStation', 1],
    wu                   => ['nearbyStation', 1],
    wu_pws               => ['nearbyStation', 1],
    openmeteo_airquality  => ['airQuality', 3],
    openweather          => ['primary', 3],
    weatherflow          => ['primary', 3],
    wetteronline         => ['primary', 3],
    wttrin               => ['primary', 3],
    visualcrossing       => ['primary', 5],
);

my @grabbers = grep { !/\/grabber_utils\.pl$/ }
    glob("$FindBin::Bin/../bin/grabber_*.pl");
is(scalar @grabbers, scalar keys %expected, 'all grabbers have a role expectation');

for my $path (@grabbers) {
    my ($name) = $path =~ /grabber_(\w+)\.pl$/;
    subtest $name => sub {
        ok(exists $expected{$name}, 'grabber has a defined role') or return;
        my ($role, $count) = @{$expected{$name}};
        my $source = read_file($path);
        my @blocks = $source =~
            /(?:\$grabberKey\s*=>|\$\w+->\{(?:\$grabberKey|openmeteoAq)\}\s*=)\s*(\{[^{}]*\})/g;
        is(scalar @blocks, $count, 'all metadata write paths are covered');
        my ($lbplogdir, $generatedAt, $grabberLabel, $grabberFile, $obsTimeLocal, $stationID) =
            ('/weather', '2026-10-25T17:15:00+01:00', $name, "grabber_$name.pl",
             '2026-10-25T17:00:00+01:00', 'TEST');
        for my $weatherKey (qw(current dailyforecast hourlyforecast)) {
            for my $block (@blocks) {
                my $metadata = eval $block;
                is($@, '', "$weatherKey metadata compiles") or next;
                my $decoded = decode_json(encode_json({ $name => $metadata }));
                is($decoded->{$name}{role}, $role, "$weatherKey JSON has the expected role");

                my $previous = $block;
                is($previous =~ s/^\s*role\s*=>\s*"[^"]+",\s*\n//m, 1,
                    'exactly one role is added to the metadata');
                my $original = eval $previous;
                is($@, '', 'previous metadata compiles') or next;
                delete $decoded->{$name}{role};
                is_deeply($decoded->{$name}, $original, 'existing metadata is unchanged');
            }
        }
    };
}

for my $weatherKey (qw(current dailyforecast hourlyforecast)) {
    my $dummy = decode_json(read_file("$FindBin::Bin/../data/dummies/$weatherKey.json"));
    for my $key (sort keys %$dummy) {
        next unless ref($dummy->{$key}) eq 'HASH' && exists $dummy->{$key}{grabberScript};
        my ($name) = $dummy->{$key}{grabberScript} =~ /^grabber_(\w+)\.pl$/;
        ok(defined($name) && exists $expected{$name}, "$weatherKey dummy uses a known grabber")
            or next;
        is($dummy->{$key}{role}, $expected{$name}[0], "$weatherKey dummy $key has the expected role");
    }
}

done_testing();
