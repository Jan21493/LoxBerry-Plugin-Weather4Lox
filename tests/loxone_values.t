use strict;
use warnings;
use Test::More;
use Config::Simple '-strict';
use File::Path qw(make_path);
use File::Copy qw(copy);
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open2;
use JSON::PP qw(decode_json);

my $root = "$FindBin::Bin/..";
my $dir = tempdir(CLEANUP => 1);
my $config = "$dir/weather4lox.cfg";
my $current = "$dir/current.json";
my $previous = '{"current":{"temperature":{"air":15},"humidity":40},"refresh":60}';
make_path("$dir/sdk/LoxBerry", "$dir/bin");
symlink("$root/bin/lib", "$dir/bin/lib") or die $!;
symlink("$root/bin/grabber_utils.pl", "$dir/bin/grabber_utils.pl") or die $!;

sub fixture {
    my ($path, $contents) = @_;
    open my $fh, '>:raw', $path or die "$path: $!";
    print {$fh} $contents;
    close $fh or die "$path: $!";
}

sub contents {
    open my $fh, '<:raw', $_[0] or die "$_[0]: $!";
    local $/;
    return <$fh>;
}

fixture("$dir/sdk/LoxBerry/System.pm", <<'PERL');
package LoxBerry::System;
use Config::Simple;
use Exporter 'import';
our @EXPORT = qw($lbhomedir $lbpconfigdir $lbphtmldir $lbplogdir $lbpbindir $lbpplugindir $lbptemplatedir);
our $lbhomedir = our $lbpconfigdir = our $lbphtmldir = our $lbplogdir = $ENV{LOX_TEST_HOME};
our $lbpbindir = "$lbhomedir/bin";
our $lbpplugindir = 'weather4lox';
our $lbptemplatedir = $ENV{LOX_TEST_TEMPLATES};
sub pluginversion { 'test' }
sub lbversion { '4.0.0' }
sub get_miniservers { () }
sub readlanguage {
    my %lang;
    open my $fh, '<:raw', "$lbptemplatedir/lang/language_en.ini" or die $!;
    my $section;
    while (<$fh>) {
        $section = $1 if /^\[(.+)\]/;
        $lang{"$section.$1"} = $2 if /^(\w+)="(.*)"$/;
    }
    $_[0]->param(%lang) if ref $_[0];
    return %lang;
}
1;
PERL
fixture("$dir/sdk/LoxBerry/Web.pm", <<'PERL');
package LoxBerry::Web;
use HTML::Template;
sub lbheader {}
sub lbfooter {}
1;
PERL
fixture("$dir/sdk/LoxBerry/Log.pm", <<'PERL');
package LoxBerry::Log;
use Exporter 'import';
our @EXPORT = qw(LOGOK LOGINF LOGDEB LOGWARN LOGCRIT);
sub LOGOK ($) {}
sub LOGINF ($) {}
sub LOGDEB ($) {}
sub LOGWARN ($) {}
sub LOGCRIT ($) {}
1;
PERL
fixture("$dir/bin/weather4lox_log.pl", 'sub startWeatherLog { 1 } 1;');
fixture("$dir/sdk/LoxBerry/IO.pm", <<'PERL');
package LoxBerry::IO;
sub mshttp_get {
    my ($ms, @names) = @_;
    print join(' ', $ms, @names);
    my %response = map {
        $_ => /_cur_tt$/ ? $ENV{LOX_TEST_TEMP} : /_cur_hu$/ ? 65 : undef
    } @names;
    return $response{$names[0]} if @names == 1;
    return %response;
}
1;
PERL

local $ENV{LOX_TEST_HOME} = $dir;
local $ENV{LOX_TEST_TEMPLATES} = "$root/templates";
local $ENV{PERL5LIB} = "$dir/sdk";
local $ENV{TZ} = 'UTC';
local $ENV{LOX_TEST_TEMP} = '0';

sub run_script {
    my ($path, $body) = @_;
    local $ENV{REQUEST_METHOD} = 'POST';
    local $ENV{CONTENT_TYPE} = 'application/x-www-form-urlencoded';
    local $ENV{CONTENT_LENGTH} = length($body // '');
    my $pid = open2(my $out, my $in, $^X, "$root/$path");
    print {$in} $body if defined $body;
    close $in;
    my $output = do { local $/; <$out> } // '';
    close $out;
    waitpid($pid, 0);
    is($?, 0, "$path exited cleanly");
    return $output;
}

sub grab { run_script('bin/grabber_loxone.pl') }
sub save {
    my ($form) = @_;
    my (undef, $json) = split /\r?\n\r?\n/, run_script('webfrontend/htmlauth/ajax-save.cgi', $form), 2;
    ok(decode_json($json)->{ok}, 'settings saved');
    return Config::Simple->new($config)->param('LOX.VALUES');
}

my $all_names = join ' ', map { "w4l_cur_$_" } qw(tt tt_fl hu w_dir w_sp w_gu w_ch pr dp sr we_code);
for my $setting ('', "VALUES=\n", "VALUES=\"   \"\n") {
    fixture($config, "[SERVER]\nMSNO=2\n[LOX]\n$setting");
    fixture($current, $previous);
    is(grab(), "2 $all_names", 'missing or blank selection queries all eleven default names');
}

is(scalar save('form=1&loxgrabber=1&loxprefix=station&loxvalues=cur_tt'), 'cur_tt', 'single selection persisted');
fixture($current, $previous);
is(grab(), '2 station_cur_tt', 'only the selected name is queried with the configured prefix');
my $weather = decode_json(contents($current))->{current};
is($weather->{temperature}{air}, 0, 'scalar zero is written as a valid temperature');
is($weather->{humidity}, 40, 'an unselected field is left unchanged');

is(scalar save('form=1&loxgrabber=0&loxprefix=station&loxvalues=cur_hu+bad+cur_tt+cur_tt'),
    'cur_tt cur_hu', 'saving while disabled preserves the supplied selection and filters unknown names and duplicates');
is(scalar save('form=1&loxgrabber=1&loxprefix=station'), 'cur_tt cur_hu', 'older forms do not overwrite the selection');
is(grab(), '2 station_cur_tt station_cur_hu', 'multiple selections use the hash-returning call');
is(decode_json(contents($current))->{current}{humidity}, 65, 'the selected humidity is written');

is(scalar save('form=1&loxgrabber=1&loxprefix=station&loxvalues=-'), '-', 'explicit empty selection persisted');
fixture($current, $previous);
is(grab(), '', 'no selection makes no Miniserver calls');
is(contents($current), $previous, 'no selection leaves current weather untouched');

is(scalar save('form=1&loxgrabber=1&loxprefix=station&loxvalues=cur_tt'), 'cur_tt', 'single selection restored');
delete $ENV{LOX_TEST_TEMP};
is(grab(), '2 station_cur_tt', 'single request can return no data');
is(contents($current), $previous, 'failed single request leaves current weather untouched');

copy("$root/config/weather4lox.cfg", $config) or die $!;
for my $case (
    [0, undef, 11],
    [1, undef, 11],
    [1, 'cur_tt', 1],
    [0, 'cur_tt', 1],
    [1, '-', 0],
) {
    my ($enabled, $selection, $checked) = @$case;
    my $cfg = Config::Simple->new($config);
    $cfg->param('SERVER.LOXGRABBER', $enabled);
    $cfg->param('LOX.VALUES', $selection) if defined $selection;
    $cfg->write($config) or die $!;
    my $html = run_script('webfrontend/htmlauth/index.cgi', 'form=1');
    my ($fieldset) = $html =~ /(<fieldset id="loxvalues".*?<\/fieldset>)/s;
    ok(defined $fieldset, 'Loxone values fieldset rendered') or next;
    my @checkboxes = $fieldset =~ /<input type="checkbox"[^>]+>/g;
    is(scalar @checkboxes, 11, 'settings render all eleven choices');
    is(scalar(grep { /\bchecked\b/ } @checkboxes), $checked, 'saved or default choices are checked');
    is($fieldset =~ /^<fieldset[^>]+\bdisabled\b/ ? 0 : 1, $enabled, 'fieldset follows grabber switch');
    like($fieldset, qr/data-hint="Virtual output: \$prefix\/cur_tt"/, 'translated hint template is present');
}

done_testing();
