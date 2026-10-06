#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Copy qw(copy);
use FindBin;
use JSON::PP ();
use JSON::XS ();
use LoxBerry::System;
use LoxBerry::Log;
use Config::Simple;

my $root = tempdir(CLEANUP => 1);
my $source = "$FindBin::Bin/../bin/datatoloxone.pl";
my $installedLog = $LoxBerry::System::lbplogdir;
$installedLog = '/opt/loxberry/log/plugins/weather4lox' unless $installedLog;
my $installedHome = $LoxBerry::System::lbhomedir;
make_path("$root/log/system_tmpfs", "$root/config", "$root/data", "$root/input");
symlink("$installedHome/config/system", "$root/config/system") or die $!;
symlink("$installedHome/data/system", "$root/data/system") or die $!;

sub read_file {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or die "Cannot read $path: $!";
    local $/;
    return <$fh>;
}

my $fixture = '{"true":true,"false":false,"null":null,"text":"Gr\u00fc\u00dfe","number":12.5,"large":9007199254740993}';
my $pp = JSON::PP->new->utf8;
my $xs = JSON::XS->new->utf8->boolean_values(JSON::PP::false, JSON::PP::true);
is_deeply($xs->decode($fixture), $pp->decode($fixture), 'XS preserves scalar and boolean semantics');
for my $name (qw(current dailyforecast hourlyforecast)) {
    copy("$installedLog/$name.json", "$root/input/$name.json") or die $!;
    my $text = read_file("$root/input/$name.json");
    is_deeply($xs->decode($text), $pp->decode($text), "$name decodes identically");
}

my @decoders = qw(xs pp failure);
push @decoders, 'legacy' if $ENV{WEATHER4LOX_BASELINE};
for my $decoder (@decoders) {
    my $dir = "$root/$decoder";
    make_path($dir);
    copy("$root/input/$_.json", "$dir/$_.json") or die $! for qw(current dailyforecast hourlyforecast);
    open(my $previous, '>', "$dir/weatherdata.html") or die $!;
    print {$previous} 'previous complete page';
    close($previous);
    mkdir("$dir/weatherdata.html.tmp") or die $! if $decoder eq 'failure';
    my $pid = fork();
    die "Cannot fork: $!" unless defined $pid;
    if (!$pid) {
        $LoxBerry::System::lbplogdir = $dir;
        $LoxBerry::System::lbpplugindir = 'weather4lox';
        $LoxBerry::System::lbpbindir = "$FindBin::Bin/../bin";
        $LoxBerry::System::lbpconfigdir = "$installedHome/config/plugins/weather4lox";
        $LoxBerry::System::lbphtmldir = "$installedHome/webfrontend/html/plugins/weather4lox";
        $LoxBerry::System::lbptemplatedir = "$installedHome/templates/plugins/weather4lox";
        $LoxBerry::System::lbhomedir = $root;
        open(my $messages, '>:raw', "$dir/mqtt.jsonl") or die $!;
        my $json = JSON::PP->new->canonical;
        {
            no warnings qw(redefine once);
            require LoxBerry::IO;
            require Net::MQTT::Simple;
            *LoxBerry::IO::mqtt_connectiondetails = sub {
                return { brokerhost => 'test.invalid', brokerport => 1883 };
            };
            *Net::MQTT::Simple::new = sub { return bless {}, 'Net::MQTT::Simple' };
            *Net::MQTT::Simple::retain = sub {
                my (undef, $topic, $value) = @_;
                die "Published partial HTML\n" if $decoder ne 'legacy'
                    && read_file("$dir/weatherdata.html") ne 'previous complete page';
                print {$messages} $json->encode([$topic, $value]), "\n" or die $!;
            };
            my $param = \&Config::Simple::param;
            *Config::Simple::param = sub {
                return 0 if defined($_[1]) && $_[1] eq 'SERVER.SENDUDP';
                return $param->(@_);
            };
        }
        my $script = read_file($decoder eq 'legacy' ? $ENV{WEATHER4LOX_BASELINE} : $source);
        # Use the same inputs and fixed time in both decoder runs.
        $script =~ s/\btime\(\)/1791310000/g;
        $script =~ s{my \$langData = readJsonFile\("\$lbhomedir/}
            {my \$langData = readJsonFile("$installedHome/};
        if ($decoder eq 'pp') {
            $script =~ s/JSON::XS->new->utf8->boolean_values\(JSON::PP::false, JSON::PP::true\)/JSON::PP->new->utf8/;
        }
        eval $script;
        die $@ if $@;
        exit 1;
    }
    waitpid($pid, 0);
    if ($decoder eq 'failure') {
        isnt($?, 0, 'temporary file open failure aborts the script');
        is(read_file("$dir/weatherdata.html"), 'previous complete page', 'write failure preserves previous HTML');
        is(read_file("$dir/mqtt.jsonl"), '', 'write failure does not continue publishing values');
        next;
    }
    is($?, 0, "$decoder full script run succeeds without publishing partial HTML");
    my $html = read_file("$dir/weatherdata.html");
    like($html, qr/^<!DOCTYPE HTML>.*<\/body>\n<\/html>$/s, "$decoder publishes complete HTML");
    ok(!-e "$dir/weatherdata.html.tmp", "$decoder removes temporary file by rename");
}
is(read_file("$root/xs/weatherdata.html"), read_file("$root/pp/weatherdata.html"), 'HTML is byte-identical with XS and PP');
is(read_file("$root/xs/index.txt"), read_file("$root/pp/index.txt"), 'emulator output is byte-identical with XS and PP');
is(read_file("$root/xs/webpage.html"), read_file("$root/pp/webpage.html"), 'theme output is byte-identical with XS and PP');
is(read_file("$root/xs/mqtt.jsonl"), read_file("$root/pp/mqtt.jsonl"), 'MQTT values are identical with XS and PP');
if ($ENV{WEATHER4LOX_BASELINE}) {
    for my $file (qw(weatherdata.html index.txt webpage.html mqtt.jsonl)) {
        is(read_file("$root/xs/$file"), read_file("$root/legacy/$file"), "$file is unchanged from the production baseline");
    }
}

done_testing();
