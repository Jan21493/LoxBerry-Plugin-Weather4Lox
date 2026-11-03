#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use Encode qw(encode_utf8);

open(my $sourceFile, '<', "$FindBin::Bin/../bin/datatoloxone.pl") or die $!;
my $source = do { local $/; <$sourceFile> };
close($sourceFile) or die $!;

our ($mqttsep, $sendUDP, $sendUDPqueue, $sendMQTT, $mqtt, $topic, %tmpl_vars);
my ($weatherDataHandle, $weatherDataTemp);
my (@published, @logs);

sub LOGINF ($) { push @logs, $_[0] }
sub LOGERR ($) { die $_[0] }
sub weatherDataError { die $_[0] }

{
    package NameTestMQTT;
    sub retain {
        my (undef, $name, $value) = @_;
        push @published, [$name, $value];
    }
}

for my $function (qw(sendToLox sendMQTT)) {
    my ($body) = $source =~ /^(sub $function \{.*?^\})/ms;
    die "Cannot extract $function" unless defined $body;
    eval $body;
    die $@ if $@;
}

my @cases = (
    [20.5, 'cur', 'tt_fl'],
    ["M\x{fc}nchen & <Nord>/West", 'cur', 'loc', 'n'],
    [1, 'cur', 'primaryStale'],
    [8, 'dfc0', 'tt_h'],
    [10, 'hfc1', 'w_sp'],
    [2.4, 'nxh4', 'prec'],
    [undef, 'cur', 'ozone'],
);

for my $sep ('/', '_') {
    for my $toMS (0, 1) {
        subtest "MQTT separator $sep, toMS $toMS" => sub {
            $mqttsep = $sep;
            $sendUDP = $sendMQTT = 1;
            $sendUDPqueue = '';
            $topic = 'test-weather';
            $mqtt = bless {}, 'NameTestMQTT';
            %tmpl_vars = ();
            @published = @logs = ();
            my $html = '';
            open($weatherDataHandle, '>:encoding(UTF-8)', \$html) or die $!;
            my ($expectedHTML, $expectedUDP) = ('', '');
            my @expectedMQTT;
            for my $case (@cases) {
                my ($value, @parts) = @$case;
                my $name = join('_', @parts);
                my $expected = defined($value) ? $value : 0;
                sendToLox($toMS, 1, $value, @parts);
                is($tmpl_vars{$name}, encode_utf8($expected), "$name is available to classic themes");
                my $escaped = $expected;
                $escaped =~ s/&/&amp;/g;
                $escaped =~ s/</&lt;/g;
                $escaped =~ s/>/&gt;/g;
                $expectedHTML .= "$name\@$escaped<br>\n";
                $expectedUDP .= "$name\@$expected; " if $toMS;
                push @expectedMQTT, ["$topic/" . join($sep, @parts), encode_utf8($expected)] if $toMS;
                ok(grep($_ eq "Adding value to weatherdata.html      $name\@" . encode_utf8($expected), @logs),
                    "$name is logged with the HTML name");
            }
            close($weatherDataHandle) or die $!;
            is($html, encode_utf8($expectedHTML), 'HTML always has underscore names and escaped UTF-8 values');
            is($sendUDPqueue, $expectedUDP, 'UDP uses underscore names and unescaped values only for toMS');
            is_deeply(\@published, \@expectedMQTT, 'only MQTT uses the configured separator, only for toMS');
            is_deeply([sort keys %tmpl_vars], [sort map { join('_', @$_[1 .. $#$_]) } @cases],
                'no slash-separated theme variables are registered');
        };
    }
}

my ($cur, $dfcEntry) = map { { sunrise => '07:15', sunset => '17:30' } } 1 .. 2;
my ($per, $iconName, $iconMapping) = (0, 'cloudy', { format => 'svg' });
my @overrides = $source =~ /^ *(\$tmpl_vars\{(?:cur_\w+|"[dh]fc\$\{per\}_\w+")\} = encode_utf8\([^\n]+);/mg;
is(scalar @overrides, 7, 'all classic sunrise, sunset and icon overrides are covered');
eval join(";\n", @overrides);
die $@ if $@;
is($tmpl_vars{cur_sun_r}, '07:15', 'current sunrise is a theme time, not an epoch');
is($tmpl_vars{cur_sun_s}, '17:30', 'current sunset is a theme time, not an epoch');
is($tmpl_vars{dfc0_sun_r}, '07:15', 'daily sunrise is a theme time, not an epoch');
is($tmpl_vars{dfc0_sun_s}, '17:30', 'daily sunset is a theme time, not an epoch');
is($tmpl_vars{$_}, 'cloudy.svg', "$_ contains the icon filename")
    for qw(cur_we_icon dfc0_we_icon hfc0_we_icon);

done_testing();
