#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../bin/lib";
use Weather4Lox::ConfigBackup qw(create_backup read_backup restore_files read_file custom_targets shipped_files);
use Archive::Zip qw(AZ_OK COMPRESSION_DEFLATED);
use File::Temp qw(tempdir tempfile);
use JSON::PP qw(encode_json decode_json);
use Digest::SHA qw(sha256_hex);
use HTML::Template;
use File::Path qw(make_path);
use IPC::Open3;
use Symbol qw(gensym);

my $dir = tempdir(CLEANUP => 1);
my $default = read_file("$FindBin::Bin/../config/weather4lox.cfg");
my $settings = encode_json({pollen => {alder => 0, birch => 1, grass => 7, mugwort => 2, olive => 3, ragweed => 4}});
my $config_path = "$dir/weather4lox.cfg";
my $settings_path = "$dir/w4l-settings.json";
restore_files({$config_path => $default, $settings_path => $settings});
chmod 0600, $config_path;
my $backup = create_backup($config_path, $settings_path, '4.20.1');
like($backup, qr/^PK\x03\x04/, 'export is a ZIP archive');
my ($files, $cfg) = read_backup($backup, '4.21.0');
is($files->{'weather4lox.cfg'}, $default, 'full configuration survives round trip');
is($files->{'w4l-settings.json'}, $settings, 'pollen settings survive round trip');
is($cfg->param('WEB.THEME'), 'ocean', 'import returns parsed configuration');
{
    my $saved_path = "$dir/saved.cfg";
    my $saved = Config::Simple->new($config_path);
    $saved->param('SERVER.CITY', 'Los Angeles, CA');
    $saved->write($saved_path) or die "Cannot write saved configuration";
    my ($saved_files, $parsed) = read_backup(create_backup($saved_path, $settings_path, '4.20.1'), '4.20.1');
    is($saved_files->{'weather4lox.cfg'}, read_file($saved_path), 'preserves Config::Simple serialization and quoted commas');
    is(join(',', $parsed->param('SERVER.CITY')), 'Los Angeles,CA', 'accepts saved text represented as a list');
}

my ($fallback) = read_backup(create_backup($config_path, "$dir/absent.json", '4.20.1'), '4.20.1');
is_deeply(decode_json($fallback->{'w4l-settings.json'})->{pollen},
    {map {$_ => 0} qw(alder birch grass mugwort olive ragweed)}, 'missing pollen settings use UI defaults');

sub zip_files {
    my ($entries, $options) = @_;
    my $archive = Archive::Zip->new;
    for my $entry (@$entries) {
        my $member = $archive->addString($entry->[1], $entry->[0]);
        $member->desiredCompressionMethod(COMPRESSION_DEFLATED);
    }
    my ($fh, $path) = tempfile(DIR => $dir, UNLINK => 1);
    binmode $fh;
    die 'Cannot create test ZIP' unless $archive->writeToFileHandle($fh) == AZ_OK;
    close $fh;
    my $data = read_file($path);
    if ($options && $options->{symlink}) {
        my $offset = index($data, "PK\x01\x02");
        substr($data, $offset + 5, 1) = "\x03";
        substr($data, $offset + 38, 4) = pack('V', 0120777 << 16);
    }
    return $data;
}

sub with_content {
    my ($config, $json, $manifest_change, $extras) = @_;
    my @entries = (['weather4lox.cfg', $config], ['w4l-settings.json', $json], @{ $extras || [] });
    my $manifest = {
        format => $extras ? 2 : 1, plugin => 'weather4lox', version => '4.20.1',
        files => {map { $_->[0] => sha256_hex($_->[1]) } @entries},
    };
    $manifest_change->($manifest) if $manifest_change;
    return zip_files([['manifest.json', encode_json($manifest)], @entries]);
}

sub rejects {
    my ($data, $pattern, $label) = @_;
    my $ok = eval { read_backup($data, '4.20.1'); 1 };
    ok(!$ok, $label);
    like($@, $pattern, "$label: explicit error");
    is(read_file($config_path), $default, "$label: configuration untouched");
}

rejects('plain text', qr/Not a ZIP/, 'rejects non-ZIP upload');
rejects("PK\x03\x04" . ('x' x (8 * 1024 * 1024)), qr/exceeds/, 'rejects upload larger than 8 MiB');
{
    local $SIG{__WARN__} = sub {};
    rejects(substr($backup, 0, length($backup) - 22), qr/Invalid or incomplete/, 'rejects missing ZIP directory');
}
rejects(zip_files([['../weather4lox.cfg', $default], ['manifest.json', '{}'], ['w4l-settings.json', $settings]]),
    qr/Unsafe/, 'rejects directory traversal');
rejects(zip_files([['weather4lox.cfg', $default], ['weather4lox.cfg', $default], ['manifest.json', '{}']]),
    qr/Unsafe/, 'rejects duplicate entries');
rejects(zip_files([['weather4lox.cfg', $default], ['manifest.json', '{}']]),
    qr/number/, 'rejects missing entries');
rejects(zip_files([['manifest.json', '{}'], map {[$_, $files->{$_}]} sort keys %$files], {symlink => 1}),
    qr/regular file/, 'rejects symbolic links');
rejects(with_content($default, $settings, sub {$_[0]{plugin} = 'another-plugin'}),
    qr/manifest/, 'rejects foreign plugin archive');
rejects(with_content($default, $settings, sub {$_[0]{format} = 3}),
    qr/manifest/, 'rejects unsupported format');
rejects(with_content($default, $settings, sub {$_[0]{version} = '5.0.0'}),
    qr/version/, 'rejects incompatible plugin version');
rejects(with_content($default, $settings, sub {$_[0]{files}{'weather4lox.cfg'} = '0' x 64}),
    qr/checksum/, 'rejects modified configuration');
rejects(with_content("[SERVER]\nGETDATA=1\n", $settings),
    qr/Missing configuration key/, 'rejects incomplete configuration');
rejects(with_content($default . "\ninvalid line\n", $settings),
    qr/Invalid INI/, 'rejects invalid INI');
rejects(with_content($default . "\n[SERVER]\nGETDATA=1\n", $settings),
    qr/Duplicate/, 'rejects duplicate INI sections');
for my $case (
    ['CRON=15', 'CRON=never', qr/interval/, 'invalid cron interval'],
    ['GETDATA=0', 'GETDATA=3', qr/switch/, 'invalid switch'],
    ['UDPPORT=7000', 'UDPPORT=99999', qr/port/, 'invalid UDP port'],
    ['THEME=ocean', 'THEME=../ocean', qr/website setting/, 'unsafe theme path'],
    ['COORDLAT=""', 'COORDLAT=100', qr/coordinates/, 'invalid latitude'],
    ['THEME=ocean', 'THEME="<script>alert(1)</script>"', qr/Unsafe/, 'HTML payload'],
) {
    my ($from, $to, $error, $label) = @$case;
    my $invalid = $default;
    $invalid =~ s/\Q$from\E/$to/ or die "Missing fixture value: $from";
    rejects(with_content($invalid, $settings), $error, "rejects $label");
}
rejects(with_content($default, 'not JSON'), qr/pollen settings JSON/, 'rejects invalid JSON');
rejects(with_content($default, '{"pollen":{"grass":9}}'), qr/sensitivity/, 'rejects invalid pollen values');
{
    my $large = $default . "\n;" . ('x' x (1024 * 1024));
    my $data = with_content($large, $settings);
    rejects($data, qr/too large/, 'rejects oversized decompressed entry');
    my $theme = '<html>' . ('x' x 1000000);
    rejects(with_content($default, $settings, undef, [map { ["themes/big$_.theme.html", $theme] } 1 .. 9]),
        qr/Uncompressed.*exceeds/, 'rejects oversized decompressed total');
}
{
    my $corrupt = $backup;
    substr($corrupt, 14, 4) = "\x00\x00\x00\x00";
    rejects($corrupt, qr/Damaged/, 'rejects local CRC corruption');
    $corrupt = $backup;
    my $central = index($corrupt, "PK\x01\x02");
    substr($corrupt, $central + 16, 4) = "\x00\x00\x00\x00";
    rejects($corrupt, qr/ZIP directory/, 'rejects central CRC corruption');
    $corrupt = $backup;
    substr($corrupt, 6, 2) = pack('v', unpack('v', substr($corrupt, 6, 2)) | 1);
    substr($corrupt, $central + 8, 2) = pack('v', unpack('v', substr($corrupt, $central + 8, 2)) | 1);
    rejects($corrupt, qr/Encrypted/, 'rejects encrypted ZIP entries');
}
for my $station ('"50.84", "7.01"', '"50.84,7.01"', '"New York"') {
    my $config = $default;
    $config =~ s/\[WTTRIN\]\nLANG=en\nSTATIONID=/[WTTRIN]\nLANG=en\nSTATIONID=$station/;
    my $ok = eval { read_backup(with_content($config, $settings), '4.20.1'); 1 };
    ok($ok, "accepts station format $station") or diag $@;
}

{
    my %dirs = (html => "$dir/custom-html", lang => "$dir/custom-lang");
    make_path(values %dirs);
    my %custom = (
        "$dirs{html}/mytheme.theme.html" => "<!DOCTYPE html>\n<html><body>Mein Theme \xC3\xA4</body></html>\n",
        "$dirs{html}/lang-fr.json" => qq({"language":"Fran\xC3\xA7ais","title":"M\xC3\xA9t\xC3\xA9o"}\n),
        "$dirs{lang}/language_fr.ini" => "[SETTINGS]\nLABEL_PLUGINTITLE=\"Weather4Loxone\"\n",
        "$dirs{html}/ocean.theme.html" => "<html>shipped</html>",
        "$dirs{html}/lang-de.json" => '{"language":"Deutsch"}',
        "$dirs{lang}/language_de.ini" => "[SETTINGS]\nA=1\n",
        "$dirs{html}/notes.txt" => 'ignored',
    );
    restore_files(\%custom);
    symlink("$dirs{html}/mytheme.theme.html", "$dirs{html}/linked.theme.html") or die "Cannot link: $!";
    my ($custom_files) = read_backup(create_backup($config_path, $settings_path, '4.20.1', \%dirs), '4.20.1');
    is_deeply([sort keys %$custom_files], [qw(theme-languages/lang-fr.json themes/mytheme.theme.html
        ui-languages/language_fr.ini w4l-settings.json weather4lox.cfg)], 'exports only custom themes and languages');
    is($custom_files->{'themes/mytheme.theme.html'}, $custom{"$dirs{html}/mytheme.theme.html"}, 'custom theme survives round trip');
    is_deeply(custom_targets($custom_files, \%dirs), {
        "$dirs{html}/mytheme.theme.html" => $custom{"$dirs{html}/mytheme.theme.html"},
        "$dirs{html}/lang-fr.json" => $custom{"$dirs{html}/lang-fr.json"},
        "$dirs{lang}/language_fr.ini" => $custom{"$dirs{lang}/language_fr.ini"},
    }, 'custom files map to plugin directories');
    my @valid = (['themes/mine.theme.html', '<html></html>']);
    ok(eval { read_backup(with_content($default, $settings, undef, \@valid), '4.20.1'); 1 }, 'accepts format 2 custom theme')
        or diag $@;
    for my $case (
        ['themes/ocean.theme.html', '<html></html>', qr/Unsafe/, 'shipped theme'],
        ['ui-languages/language_en.ini', "[S]\nA=1\n", qr/Unsafe/, 'shipped UI language'],
        ['themes/../mine.theme.html', '<html></html>', qr/Unsafe/, 'theme path traversal'],
        ['themes/sub/mine.theme.html', '<html></html>', qr/Unsafe/, 'theme subdirectory'],
        ['themes/mine.html', '<html></html>', qr/Unsafe/, 'wrong theme extension'],
        ['ui-languages/lang-fr.json', '{"language":"x"}', qr/Unsafe/, 'misplaced language file'],
        ['themes/mine.theme.html', 'no markup', qr/Invalid theme/, 'theme without HTML'],
        ['themes/mine.theme.html', "<html>\xFF</html>", qr/UTF-8/, 'non-UTF-8 theme'],
        ['theme-languages/lang-fr.json', 'not JSON', qr/theme language JSON/, 'invalid theme language JSON'],
        ['theme-languages/lang-fr.json', '{"title":"x"}', qr/theme language JSON/, 'theme language without name'],
        ['ui-languages/language_fr.ini', "KEY=1\n", qr/Invalid language file/, 'UI language without section'],
        ['ui-languages/language_fr.ini', "[SETTINGS]\nnot a key\n", qr/Invalid language file/, 'invalid UI language line'],
        ['ui-languages/language_fr.ini', "[SETTINGS]\r\nA=1\r\n", qr/encoding/, 'UI language with CRLF'],
    ) {
        my ($name, $data, $error, $label) = @$case;
        rejects(with_content($default, $settings, undef, [[$name, $data]]), $error, "rejects $label");
    }
    rejects(with_content($default, $settings, sub {$_[0]{format} = 1}, \@valid),
        qr/format 1/, 'rejects custom files in format 1 archive');
    rejects(with_content($default, $settings, sub {delete $_[0]{files}{'themes/mine.theme.html'}}, \@valid),
        qr/manifest does not match/, 'rejects custom file missing from manifest');
    rejects(with_content($default, $settings, sub {$_[0]{files}{'themes/mine.theme.html'} = '0' x 64}, \@valid),
        qr/checksum/, 'rejects modified custom file');
}

{
    my $root = "$FindBin::Bin/..";
    my @release = map { m{([^/]+)$} } (glob("$root/webfrontend/html/*.theme.html"),
        glob("$root/webfrontend/html/lang-*.json"), glob("$root/templates/lang/language_*.ini"));
    is_deeply([shipped_files()], [sort @release], 'shipped file list matches release files');
}

my $activated = 0;
restore_files({$config_path => $default, $settings_path => $settings}, sub {$activated++});
is($activated, 1, 'activates restored settings');
is((stat $config_path)[2] & 0777, 0600, 'preserves private file permissions');
my $ok = eval {
    restore_files({$config_path => 'replacement', "$dir/new.json" => '{}'}, sub {die "Activation failed\n"});
    1;
};
ok(!$ok, 'activation failure is reported');
like($@, qr/Activation failed/, 'activation error is preserved');
is(read_file($config_path), $default, 'activation failure restores original file');
ok(!-e "$dir/new.json", 'activation failure removes newly created file');
{
    my $ok = eval { restore_files({$config_path => 'replacement', "$dir/z-missing/file" => 'data'}); 1 };
    ok(!$ok, 'write failure is reported');
    is(read_file($config_path), $default, 'write failure restores earlier files');
}

my $template = HTML::Template->new(filename => "$FindBin::Bin/../templates/settings.html",
    die_on_bad_params => 0, global_vars => 1);
$template->param(FORM1 => 1);
my $html = $template->output;
like($html, qr/id="main_form".*?<\/form>.*?id="config-backup"/s, 'backup UI follows server settings form');
like($html, qr/id="config-import-file"[^>]*accept="\.zip,application\/zip"/, 'file picker accepts ZIP archives');
like($html, qr/<input type="file" id="config-import-file"[^>]*\bhidden\b[^>]*display:none/, 'file picker is hidden');
like($html, qr/<div id="config-backup-buttons">\s*<button[^>]*id="config-export".*?<\/button>\s*<button[^>]*id="config-import"/s,
    'import button is next to export button');
like($html, qr/importButton\.addEventListener\("click".*?fileInput\.click\(\)/s, 'import button opens file picker');
like($html, qr/fileInput\.addEventListener\("change".*?transfer\("import", file\)/s, 'file selection starts import');
unlike($html, qr/config-import-form|LABEL_CONFIG_FILE|config-backup-reload|BUTTON_CONFIG_RELOAD/, 'no visible import file form or reload button');
like($html, qr/window\.location\.replace\("\.\/index\.cgi\?form=1&imported=1#config-backup"\)/, 'import reloads settings automatically');
like($html, qr/if \(imported\) \{\s*status\.textContent = message\("config-imported"\)/, 'import result is shown after reload');
like($html, qr/\$\("#main_form"\)\.on\("submit".*?\$\("#config-backup"\)\.hide\(\).*?\$\("#save-overlay"\)\.show\(\)/s,
    'backup UI is hidden while saving');
unlike($html, qr/<form\b[^>]*>(?:(?!<\/form>).)*<form\b/s, 'import does not nest forms');
$template->param(FORM1 => 0, FORM2 => 1);
unlike($template->output, qr/id="config-backup"/, 'backup UI only appears on server tab');

my $runtime = "$dir/runtime";
make_path("$runtime/lib/LoxBerry", "$runtime/config", "$runtime/html", "$runtime/log",
    "$runtime/system/cron/cron.01min", "$runtime/bin", "$runtime/templates/lang");
symlink("$FindBin::Bin/../templates/themes", "$runtime/templates/themes") or die "Cannot link test themes: $!";
sub fixture {
    my ($path, $content) = @_;
    open my $fh, '>:raw', $path or die "Cannot write fixture: $!";
    print {$fh} $content;
    close $fh or die "Cannot close fixture: $!";
}
fixture("$runtime/lib/LoxBerry/System.pm", <<'PERL');
package LoxBerry::System;
use Exporter 'import';
our @EXPORT = qw($lbhomedir $lbpconfigdir $lbphtmldir $lbplogdir $lbpbindir $lbptemplatedir $lbpplugindir);
our $lbhomedir = $ENV{BACKUP_TEST_HOME};
our $lbpconfigdir = "$lbhomedir/config";
our $lbphtmldir = "$lbhomedir/html";
our $lbplogdir = "$lbhomedir/log";
our $lbpbindir = $ENV{BACKUP_TEST_BINDIR};
our $lbptemplatedir = $ENV{BACKUP_TEST_TEMPLATES};
our $lbpplugindir = 'weather4lox';
sub pluginversion { '4.20.1' }
1;
PERL
fixture("$runtime/config/weather4lox.cfg", $default);
fixture("$runtime/html/w4l-settings.json", $settings);
fixture("$runtime/log/webpage.html", 'old webpage');
fixture("$runtime/html/ocean.theme.html", '<html>shipped ocean</html>');
fixture("$runtime/templates/lang/language_en.ini", "[SETTINGS]\nSHIPPED=1\n");
fixture("$runtime/html/old.theme.html", '<html>old custom</html>');
fixture("$runtime/bin/sudo", "#!/bin/sh\nexec \"\$@\"\n");
fixture("$runtime/bin/cloudemu.sh", <<'SH');
#!/bin/sh
echo "$1" >> "$BACKUP_TEST_HOME/actions"
echo "Emulator output must not enter the HTTP response"
if [ -e "$BACKUP_TEST_HOME/fail-enable" ] && [ "$1" = enable ]; then exit 1; fi
SH
chmod 0755, "$runtime/bin/sudo", "$runtime/bin/cloudemu.sh";
symlink("$FindBin::Bin/../bin/lib", "$runtime/bin/lib") or die "Cannot link test library: $!";
symlink("$FindBin::Bin/../bin/cronjob.pl", "$runtime/bin/cronjob.pl") or die "Cannot link test cron: $!";
my $script = "$FindBin::Bin/../webfrontend/htmlauth/config-backup.cgi";

sub request {
    my (%options) = @_;
    local %ENV = %ENV;
    $ENV{PERL5LIB} = "$runtime/lib:" . ($ENV{PERL5LIB} // '');
    $ENV{BACKUP_TEST_HOME} = $runtime;
    $ENV{BACKUP_TEST_BINDIR} = "$runtime/bin";
    $ENV{BACKUP_TEST_TEMPLATES} = "$runtime/templates";
    $ENV{PATH} = "$runtime/bin:$ENV{PATH}";
    $ENV{REQUEST_METHOD} = $options{method} || 'POST';
    $ENV{HTTP_X_WEATHER4LOX_BACKUP} = $options{no_header} ? '' : '1';
    $ENV{CONTENT_TYPE} = $options{type} || 'application/x-www-form-urlencoded';
    my $body = $options{body} // '';
    $ENV{CONTENT_LENGTH} = length $body;
    $ENV{QUERY_STRING} = '';
    my $stderr = gensym;
    my $pid = open3(my $input, my $output, $stderr, $^X, $script);
    binmode $input;
    print {$input} $body;
    close $input;
    binmode $output;
    my $result = do {local $/; <$output>};
    my $errors = do {local $/; <$stderr>};
    waitpid $pid, 0;
    is($?, 0, 'CGI exits normally') or diag $errors;
    my ($headers, $payload) = split /\r?\n\r?\n/, $result, 2;
    return ($headers, $payload, $errors);
}

sub import_request {
    my ($data) = @_;
    my $boundary = 'Weather4LoxTestBoundary';
    my $body = "--$boundary\r\nContent-Disposition: form-data; name=\"action\"\r\n\r\nimport\r\n"
        . "--$boundary\r\nContent-Disposition: form-data; name=\"backup\"; filename=\"backup.zip\"\r\n"
        . "Content-Type: application/zip\r\n\r\n$data\r\n--$boundary--\r\n";
    return request(body => $body, type => "multipart/form-data; boundary=$boundary");
}

{
    my ($headers, $payload) = request(method => 'GET');
    like($headers, qr/400 Bad Request/, 'GET is rejected');
    like(decode_json($payload)->{error}, qr/POST required/, 'GET has explicit error');
    ($headers, $payload) = request(body => 'action=import', no_header => 1);
    like($headers, qr/400 Bad Request/, 'cross-origin form without custom header is rejected');
    ($headers, $payload) = request(body => 'action=export');
    like($headers, qr{Content-Type: application/zip}i, 'export sends ZIP content type');
    like($headers, qr{filename="?weather4lox-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.zip"?}i,
        'download filename contains plugin name and date');
    like($headers, qr/Cache-Control: no-store/i, 'sensitive export is not cached');
    my ($exported) = read_backup($payload, '4.20.1');
    is($exported->{'weather4lox.cfg'}, $default, 'CGI exports saved configuration');
    ($headers, $payload) = import_request('invalid ZIP data');
    like($headers, qr/400 Bad Request/, 'invalid upload returns HTTP error');
    is(read_file("$runtime/config/weather4lox.cfg"), $default, 'invalid upload preserves config');
    ok(!-e "$runtime/actions", 'invalid upload does not activate services');

    my $changed = $default;
    $changed =~ s/GETDATA=0/GETDATA=1/;
    $changed =~ s/EMU=0/EMU=1/;
    my @custom = (['themes/old.theme.html', '<html>new custom</html>'],
        ['theme-languages/lang-fr.json', '{"language":"Francais"}'],
        ['ui-languages/language_fr.ini', "[SETTINGS]\nA=1\n"]);
    my $import = with_content($changed, $settings, undef, \@custom);
    ($headers, $payload) = import_request($import);
    ok(decode_json($payload)->{ok}, 'valid CGI upload succeeds without command output in JSON');
    is(read_file("$runtime/html/old.theme.html"), '<html>new custom</html>', 'CGI replaces custom theme');
    is(read_file("$runtime/html/lang-fr.json"), '{"language":"Francais"}', 'CGI imports theme language');
    is(read_file("$runtime/templates/lang/language_fr.ini"), "[SETTINGS]\nA=1\n", 'CGI imports UI language');
    is(read_file("$runtime/html/ocean.theme.html"), '<html>shipped ocean</html>', 'CGI keeps shipped theme');
    ($headers, $payload) = request(body => 'action=export');
    my ($reexported) = read_backup($payload, '4.20.1');
    is_deeply([sort grep { m{/} } keys %$reexported], [qw(theme-languages/lang-fr.json themes/old.theme.html
        ui-languages/language_fr.ini)], 'CGI exports custom themes and languages');
    is(read_file("$runtime/config/weather4lox.cfg"), $changed, 'CGI imports full configuration');
    is(read_file("$runtime/html/w4l-settings.json"), $settings, 'CGI imports pollen settings');
    ok(-l "$runtime/system/cron/cron.01min/weather4lox", 'CGI activates data retrieval cron');
    is(read_file("$runtime/actions"), "enable\n", 'CGI applies emulator configuration');
    like(read_file("$runtime/log/webpage.html"), qr{\./ocean\.theme\.html\?mode=system&iconset=naturalistic&lang=en},
        'CGI regenerates website redirect');

    ($headers, $payload) = import_request($backup);
    ok(decode_json($payload)->{ok}, 'disabled configuration imports successfully');
    ok(!-l "$runtime/system/cron/cron.01min/weather4lox", 'CGI disables data retrieval cron');
    is(read_file("$runtime/actions"), "enable\ndisable\n", 'CGI disables emulator');

    fixture("$runtime/fail-enable", '');
    my $previous_webpage = read_file("$runtime/log/webpage.html");
    ($headers, $payload) = import_request($import);
    like($headers, qr/400 Bad Request/, 'activation failure returns HTTP error');
    like(decode_json($payload)->{error}, qr/emulator/, 'activation failure has explicit error');
    is(read_file("$runtime/config/weather4lox.cfg"), $default, 'CGI failure restores configuration');
    unlink "$runtime/html/lang-fr.json";
    fixture("$runtime/html/old.theme.html", '<html>before failure</html>');
    fixture("$runtime/actions", "enable\ndisable\n");
    ($headers, $payload) = import_request($import);
    like($headers, qr/400 Bad Request/, 'repeated activation failure returns HTTP error');
    is(read_file("$runtime/html/old.theme.html"), '<html>before failure</html>', 'CGI failure restores custom theme');
    ok(!-e "$runtime/html/lang-fr.json", 'CGI failure removes newly imported language');
    is(read_file("$runtime/log/webpage.html"), $previous_webpage, 'CGI failure restores website redirect');
    ok(!-l "$runtime/system/cron/cron.01min/weather4lox", 'CGI failure restores cron state');
    like(read_file("$runtime/actions"), qr/enable\ndisable\n$/, 'CGI failure reapplies old emulator state');
}

done_testing();
