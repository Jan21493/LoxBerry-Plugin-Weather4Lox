#!/usr/bin/perl

use strict;
use warnings;
use CGI;
use JSON::PP qw(encode_json);
use POSIX qw(strftime);
use Fcntl qw(:flock);
use LoxBerry::System;
use lib "$lbpbindir/lib";
use Weather4Lox::ConfigBackup qw(create_backup read_backup restore_files read_file custom_targets MAX_ARCHIVE);

$CGI::POST_MAX = MAX_ARCHIVE + 64 * 1024;
my $cgi = CGI->new;
my $version = LoxBerry::System::pluginversion();
my $config_path = "$lbpconfigdir/weather4lox.cfg";
my $settings_path = "$lbphtmldir/w4l-settings.json";
my %custom_dirs = (html => $lbphtmldir, lang => "$lbptemplatedir/lang");

sub json_response {
    my ($status, $payload) = @_;
    print $cgi->header(-status => $status, -type => 'application/json',
        -charset => 'UTF-8', -Cache_Control => 'no-store');
    print encode_json($payload);
}

sub apply_runtime {
    my ($cfg, $previous_cfg) = @_;
    my $cronlink = "$lbhomedir/system/cron/cron.01min/$lbpplugindir";
    if (-e $cronlink || -l $cronlink) {
        unlink($cronlink) or die "Cannot remove cron link: $!\n";
    }
    if ($cfg->param('SERVER.GETDATA')) {
        symlink("$lbpbindir/cronjob.pl", $cronlink) or die "Cannot create cron link: $!\n";
    }
    if (($cfg->param('SERVER.EMU') || 0) != ($previous_cfg->param('SERVER.EMU') || 0)) {
        open my $process, '-|', 'sudo', "$lbpbindir/cloudemu.sh",
            $cfg->param('SERVER.EMU') ? 'enable' : 'disable'
            or die "Cannot start cloud emulator configuration: $!\n";
        while (my $line = <$process>) {
            warn "Cloud emulator: $line";
        }
        close $process or die "Cannot apply cloud emulator settings (status $?)\n";
    }
}

my ($download, $filename);
my $ok = eval {
    die "POST required\n" unless $cgi->request_method eq 'POST';
    # Cross-origin HTML forms cannot supply this header; no CORS is enabled.
    die "Same-origin request required\n" unless ($ENV{HTTP_X_WEATHER4LOX_BACKUP} // '') eq '1';
    die "Upload failed or exceeds 8 MiB\n" if $cgi->cgi_error;
    open my $lock, '>>', "$lbpconfigdir/.config-backup.lock" or die "Cannot open backup lock: $!\n";
    flock($lock, LOCK_EX) or die "Cannot lock configuration backup: $!\n";
    my $action = $cgi->param('action') // '';
    if ($action eq 'export') {
        $download = create_backup($config_path, $settings_path, $version, \%custom_dirs);
        $filename = 'weather4lox-' . strftime('%Y-%m-%d_%H-%M-%S', localtime) . '.zip';
    } elsif ($action eq 'import') {
        my $upload = $cgi->upload('backup') or die "Select a ZIP archive\n";
        die "Select a .zip file\n" unless ($cgi->param('backup') // '') =~ /\.zip$/i;
        binmode $upload;
        my $count = read($upload, my $data, MAX_ARCHIVE + 1);
        die "Cannot read uploaded archive\n" unless defined $count;
        my ($files, $cfg) = read_backup($data, $version);
        my $old_cfg = Config::Simple->new($config_path) or die "Cannot read current configuration\n";
        my $theme = $cfg->param('WEB.THEME');
        my $mode = $cfg->param('WEB.MODE') || 'system';
        my $iconset = $cfg->param('WEB.ICONSET');
        my $lang = $cfg->param('WEB.LANG');
        my $themeurl = "./$theme.theme.html?mode=$mode&iconset=$iconset&lang=$lang";
        my $webpage = read_file("$lbptemplatedir/themes/new-style.theme.html");
        $webpage =~ s/<!--\$(.*?)-->/$1 eq 'themeurl' ? $themeurl : die "Unknown webpage template variable\n"/ge;
        eval {
            restore_files({
                $config_path => $files->{'weather4lox.cfg'},
                $settings_path => $files->{'w4l-settings.json'},
                "$lbplogdir/webpage.html" => $webpage,
                %{ custom_targets($files, \%custom_dirs) },
            }, sub { apply_runtime($cfg, $old_cfg) });
            1;
        } or do {
            my $error = $@;
            eval { apply_runtime($old_cfg, $cfg); 1 } or $error .= "Runtime rollback failed: $@";
            die $error;
        };
    } else {
        die "Unknown backup action\n";
    }
    1;
};

if (!$ok) {
    my $error = $@ || "Unknown backup error\n";
    warn "Configuration backup: $error";
    json_response('400 Bad Request', { ok => 0, error => $error });
} elsif (defined $download) {
    binmode STDOUT;
    print $cgi->header(-type => 'application/zip', -attachment => $filename,
        -Content_Length => length($download), -Cache_Control => 'no-store',
        -X_Content_Type_Options => 'nosniff');
    print $download;
} else {
    json_response('200 OK', { ok => 1 });
}
