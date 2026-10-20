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
use Encode qw(encode_utf8 decode FB_CROAK);
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

my $city = "M\x{fc}nchen & <Nord> \x{6771}\x{4eac} \x{1f326}";
my $description = "Bew\x{f6}lkt";
my $wind = "S\x{fc}d-West";
my $month = "M\x{e4}rz";
make_path("$root/webfrontend/html/plugins/weather4lox", "$root/templates/themes/de");
symlink("$installedHome/templates/plugins/weather4lox/lang", "$root/templates/lang") or die $!;
copy("$FindBin::Bin/../webfrontend/html/lang-de.json",
    "$root/webfrontend/html/plugins/weather4lox/lang-de.json") or die $!;
for my $view (qw(main map dfc hfc)) {
    open(my $template, '>:raw', "$root/templates/themes/de/encoding-test.$view.html") or die $!;
    print {$template} "<html><body><!--\$cur/we_des--> <!--\$cur/w_dirdes--> <!--\$dfc0/monthn--> " .
        encode_utf8("Gr\x{fc}\x{df}e") . "</body></html>";
    close($template) or die $!;
}

my @decoders = qw(xs pp unicode failure);
push @decoders, 'legacy' if $ENV{WEATHER4LOX_BASELINE};
for my $decoder (@decoders) {
    my $dir = "$root/$decoder";
    make_path($dir);
    copy("$root/input/$_.json", "$dir/$_.json") or die $! for qw(current dailyforecast hourlyforecast);
    if ($decoder eq 'unicode') {
        for my $name (qw(current dailyforecast hourlyforecast)) {
            my $data = $xs->decode(read_file("$dir/$name.json"));
            $data->{location}{city} = $city if $name eq 'current';
            my $entry = $name eq 'current' ? $data->{$name} : $data->{$name}[0];
            $entry->{weatherCode}{weather4lox} = 'cloudy';
            $entry->{time}{epoch} = 1773576000; # March, to exercise the localized month name.
            if ($name eq 'dailyforecast') {
                $entry->{wind}{$_}{direction} = 225 for qw(avg max);
            } else {
                $entry->{wind}{direction} = 225;
            }
            open(my $fh, '>:raw', "$dir/$name.json") or die $!;
            print {$fh} $xs->encode($data) or die $!;
            close($fh) or die $!;
        }
    }
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
        $LoxBerry::System::lbptemplatedir = $decoder eq 'unicode'
            ? "$root/templates" : "$installedHome/templates/plugins/weather4lox";
        $LoxBerry::System::lbhomedir = $root;
        open(my $messages, '>:raw', "$dir/mqtt.jsonl") or die $!;
        my $json = JSON::PP->new->canonical;
        {
            no warnings qw(redefine once);
            require LoxBerry::IO;
            require Net::MQTT::Simple;
            require IO::Socket::INET;
            *LoxBerry::IO::mqtt_connectiondetails = sub {
                return { brokerhost => 'test.invalid', brokerport => 1883 };
            };
            *Net::MQTT::Simple::new = sub { return bless {}, 'Net::MQTT::Simple' };
            *Net::MQTT::Simple::retain = sub {
                my (undef, $topic, $value) = @_;
                die "Published partial HTML\n" if $decoder ne 'legacy'
                    && read_file("$dir/weatherdata.html") ne 'previous complete page';
                die "MQTT payload must be UTF-8 bytes\n" if $decoder eq 'unicode' && utf8::is_utf8($value);
                print {$messages} $json->encode([$topic, "$value"]), "\n" or die $!;
            };
            if ($decoder eq 'unicode') {
                *LoxBerry::System::get_miniservers = sub {
                    return (1 => { IPAddress => 'test.invalid', Name => 'Test' });
                };
                *IO::Socket::INET::new = sub { return bless {}, 'EncodingTestSocket' };
                *EncodingTestSocket::send = sub {
                    my (undef, $bytes) = @_;
                    die "UDP payload must be UTF-8 bytes\n" if utf8::is_utf8($bytes);
                    open(my $udp, '>:raw', "$dir/udp.txt") or die $!;
                    print {$udp} $bytes or die $!;
                    close($udp) or die $!;
                    return length($bytes);
                };
            }
            my $param = \&Config::Simple::param;
            *Config::Simple::param = sub {
                if ($decoder eq 'unicode' && defined($_[1])) {
                    my %settings = (
                        'WEB.LANG' => 'de', 'WEB.THEME' => 'encoding-test',
                        'SERVER.SENDUDP' => 1, 'SERVER.UDPPORT' => 12345,
                        'SERVER.MSNO' => 1, 'SERVER.MQTTSTRUCTURED' => 1,
                        'SERVER.EMU' => 1,
                        'SERVER.TOPIC' => 'encoding-test',
                        'SERVER.SENDDFC' => '1', 'SERVER.SENDHFC' => '1',
                    );
                    return $settings{$_[1]} if exists $settings{$_[1]};
                }
                return 0 if defined($_[1]) && $_[1] eq 'SERVER.SENDUDP';
                return $param->(@_);
            };
        }
        my $script = read_file($decoder eq 'legacy' ? $ENV{WEATHER4LOX_BASELINE} : $source);
        # Use the same inputs and fixed time in both decoder runs.
        $script =~ s/\btime\(\)/1791310000/g;
        my $languageHome = $decoder eq 'unicode' ? $root : $installedHome;
        $script =~ s{my \$langData = readJsonFile\("\$lbhomedir/}
            {my \$langData = readJsonFile("$languageHome/};
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
    if ($decoder eq 'unicode') {
        my $text = decode('UTF-8', $html, FB_CROAK);
        like($text, qr/<meta charset="utf-8">/, 'HTML declares UTF-8');
        like($text, qr/<title>[^<]+<\/title>/, 'HTML has a required document title');
        for my $key (qw(cur/we_des dfc0/we_des hfc1/we_des hfc1/sky_des)) {
            like($text, qr/\Q$key\E\@\Q$description\E<br>/, "$key is encoded exactly once");
        }
        for my $key (qw(cur/w_dirdes dfc0/w_dirdes_h dfc0/w_dirdes_a hfc1/w_dirdes)) {
            like($text, qr/\Q$key\E\@\Q$wind\E<br>/, "$key preserves umlauts");
        }
        like($text, qr/dfc0\/monthn\@\Q$month\E<br>/, 'daily month name preserves umlauts');
        like($text, qr/hfc1\/monthn\@\Q$month\E<br>/, 'hourly month name preserves umlauts');
        my $escapedCity = $city;
        $escapedCity =~ s/&/&amp;/g;
        $escapedCity =~ s/</&lt;/g;
        $escapedCity =~ s/>/&gt;/g;
        like($text, qr/cur\/loc\/n\@\Q$escapedCity\E<br>/, 'HTML escapes markup and preserves all Unicode characters');
        unlike($text, qr/<Nord>/, 'location text cannot become an HTML element');
        my %mqtt = map { @{ JSON::PP->new->decode($_) } } split /\n/, read_file("$dir/mqtt.jsonl");
        is($mqtt{'encoding-test/cur/loc/n'}, encode_utf8($city), 'MQTT location is UTF-8 without HTML escaping');
        is($mqtt{'encoding-test/cur/we_des'}, encode_utf8($description), 'MQTT description remains UTF-8');
        is($mqtt{'encoding-test/dfc0/we_des'}, encode_utf8($description), 'MQTT daily description remains UTF-8');
        is($mqtt{'encoding-test/hfc1/we_des'}, encode_utf8($description), 'MQTT hourly description remains UTF-8');
        my $udp = decode('UTF-8', read_file("$dir/udp.txt"), FB_CROAK);
        like($udp, qr/cur_loc_n\@\Q$city\E; /, 'UDP location is UTF-8 without HTML escaping');
        like($udp, qr/cur_we_des\@\Q$description\E; /, 'UDP description remains UTF-8');
        like(decode('UTF-8', read_file("$dir/index.txt"), FB_CROAK),
            qr/;\Q$city\E;/, 'emulator location is UTF-8 without HTML escaping');
        for my $view (qw(main map dfc hfc)) {
            my $file = $view eq 'main' ? 'webpage.html' : "webpage.$view.html";
            is(decode('UTF-8', read_file("$dir/$file"), FB_CROAK),
                "<html><body>$description $wind $month Gr\x{fc}\x{df}e</body></html>",
                "$view classic template keeps UTF-8 text and substitutions");
        }
    }
}
is(read_file("$root/xs/weatherdata.html"), read_file("$root/pp/weatherdata.html"), 'HTML is byte-identical with XS and PP');
is(read_file("$root/xs/index.txt"), read_file("$root/pp/index.txt"), 'emulator output is byte-identical with XS and PP');
is(read_file("$root/xs/webpage.html"), read_file("$root/pp/webpage.html"), 'theme output is byte-identical with XS and PP');
is(read_file("$root/xs/mqtt.jsonl"), read_file("$root/pp/mqtt.jsonl"), 'MQTT values are identical with XS and PP');
if ($ENV{WEATHER4LOX_BASELINE}) {
    # HTML intentionally gains correct encoding, escaping, and a document title.
    for my $file (qw(index.txt webpage.html mqtt.jsonl)) {
        is(read_file("$root/xs/$file"), read_file("$root/legacy/$file"), "$file is unchanged from the production baseline");
    }
}

done_testing();
