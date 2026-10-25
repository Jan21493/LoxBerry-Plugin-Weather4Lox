package Weather4Lox::ConfigBackup;

use strict;
use warnings;
use Exporter 'import';
use Archive::Zip qw(AZ_OK COMPRESSION_DEFLATED);
use IO::Uncompress::Unzip;
use Config::Simple;
use Digest::SHA qw(sha256_hex);
use Compress::Raw::Zlib qw(crc32);
use JSON::PP qw(encode_json decode_json);
use File::Temp qw(tempfile);
use Encode qw(decode FB_CROAK);

our @EXPORT_OK = qw(create_backup read_backup restore_files read_file custom_targets shipped_files MAX_ARCHIVE);
use constant MAX_SIZE => 1024 * 1024;
use constant MAX_ARCHIVE => 8 * 1024 * 1024;
use constant MAX_ENTRIES => 64;

# Files supplied by the plugin release are never exported or overwritten.
my %SHIPPED = map { $_ => 1 } qw(
    airquality.theme.html arctic.theme.html coastal.theme.html desert.theme.html
    graphite.theme.html ocean.theme.html
    lang-cs.json lang-de.json lang-en.json lang-es.json lang-nl.json lang-pl.json lang-sk.json
    language_cs.ini language_de.ini language_en.ini language_es.ini language_nl.ini
    language_pl.ini language_sk.ini
);
my %CUSTOM = (
    'themes' => { dir => 'html', pattern => qr/^[A-Za-z0-9][A-Za-z0-9_-]*\.theme\.html$/,
        validate => \&validate_theme },
    'theme-languages' => { dir => 'html', pattern => qr/^lang-[a-z]{2,3}(?:[-_][A-Za-z0-9]+)*\.json$/,
        validate => \&validate_theme_language },
    'ui-languages' => { dir => 'lang', pattern => qr/^language_[a-z]{2,3}(?:[-_][A-Za-z0-9]+)*\.ini$/,
        validate => \&validate_ui_language },
);
my @BASE_FILES = qw(weather4lox.cfg w4l-settings.json);

sub shipped_files { return sort keys %SHIPPED }

sub custom_entry {
    my ($name) = @_;
    my ($folder, $file) = $name =~ m{^([a-z-]+)/([^/]+)$} or return;
    my $type = $CUSTOM{$folder} or return;
    return if $file !~ $type->{pattern} || $SHIPPED{$file};
    return ($type, $file);
}

sub read_file {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "Cannot read $path: $!\n";
    die "File exceeds 1 MiB: $path\n" if -s $fh > MAX_SIZE;
    my $data = do { local $/; <$fh> };
    close $fh or die "Cannot close $path: $!\n";
    return $data;
}

sub validate_config {
    my ($data) = @_;
    die "Invalid configuration size or encoding\n"
        if !length($data) || length($data) > MAX_SIZE || $data =~ /[\x00-\x08\x0b\x0c\x0e-\x1f]/;
    my (%seen, $section);
    for my $line (split /\r?\n/, $data) {
        next if $line =~ /^\s*(?:[;#].*)?$/;
        if ($line =~ /^\[([A-Z][A-Z0-9_]*)\]\s*$/) {
            $section = $1;
            die "Duplicate configuration section\n" if $seen{"[$section]"}++;
        } elsif (defined $section && $line =~ /^([A-Z][A-Z0-9_-]*)\s*=(.*)$/) {
            die "Duplicate configuration key\n" if $seen{"$section.$1"}++;
        } else {
            die "Invalid INI configuration\n";
        }
    }
    for my $key (qw(SERVER.GETDATA SERVER.CRON SERVER.EMU WEB.THEME WEB.ICONSET WEB.LANG)) {
        die "Missing configuration key: $key\n" unless $seen{$key};
    }
    my ($fh, $path) = tempfile(UNLINK => 1);
    binmode $fh;
    print {$fh} $data or die "Cannot stage configuration: $!\n";
    close $fh or die "Cannot close configuration: $!\n";
    my $cfg = Config::Simple->new($path) or die "Invalid INI configuration\n";
    my $values = $cfg->vars;
    for my $key (keys %$values) {
        my $value = $values->{$key};
        if (ref $value) {
            die "Invalid list value: $key\n" unless ref($value) eq 'ARRAY';
            # Config::Simple also serializes text containing commas as lists.
            $value = join(',', @$value);
        }
        $value //= '';
        die "Unsafe configuration value: $key\n" if $value =~ /[<>"`\x00-\x1f]/;
        if ($key =~ /^SERVER\.(?:GETDATA|EMU|SENDUDP|MQTTSTRUCTURED|METRIC|MASKKEYS|.*GRABBER|FOSHKNEWAPI|USEALTERNATEHFC|USEALTERNATEDFC|USEWEATHEROBS|FETCHOBS)$/) {
            die "Invalid switch: $key\n" unless $value =~ /^(?:0|1)?$/;
        } elsif ($key =~ /^SERVER\.CRON(?:_[A-Z]+)?$/ && $key ne 'SERVER.CRON_PATCH') {
            die "Invalid interval: $key\n" unless $value eq '' || ($value =~ /^\d{1,4}$/ && $value <= 1440);
        } elsif ($key eq 'SERVER.UDPPORT' || $key eq 'FOSHK.PORT') {
            die "Invalid port: $key\n" unless $value eq '' || ($value =~ /^\d{1,5}$/ && $value >= 1 && $value <= 65535);
        } elsif ($key eq 'SERVER.MSNO') {
            die "Invalid Miniserver number\n" unless $value =~ /^\d{1,5}$/;
        } elsif ($key =~ /^SERVER\.WEATHERSERVICE(?:HFC|DFC|OBS)?$/) {
            die "Invalid weather service\n" unless $value =~ /^(?:visualcrossing|openweather|wttrin|wetteronline|weatherflow)?$/;
        } elsif ($key =~ /^(?:SERVER|OPENMETEOAIRQUALITY|WEATHERFLOW)\.COORD(LAT|LONG)$/) {
            my $limit = $1 eq 'LAT' ? 90 : 180;
            die "Invalid coordinates: $key\n" unless $value eq ''
                || ($value =~ /^-?\d+(?:\.\d+)?$/ && abs($value) <= $limit);
        } elsif ($key =~ /^WEB\.(?:THEME|ICONSET|LANG)$/) {
            die "Invalid website setting: $key\n" unless $value =~ /^[A-Za-z0-9][A-Za-z0-9_-]*$/;
        } elsif ($key eq 'WEB.MODE') {
            die "Invalid website mode\n" unless $value =~ /^(?:auto|system|dark|light)$/;
        } elsif ($key =~ /^SERVER\.SEND(?:DFC|HFC|NXH)$/) {
            die "Invalid forecast selection\n" unless $value =~ /^(?:\d+(?:;\d+)*)?$/;
            my $maximum = $key eq 'SERVER.SENDDFC' ? 8 : 48;
            for my $period (split /;/, $value) {
                die "Invalid forecast period\n" unless $period >= 1 && $period <= $maximum;
                die "Invalid aggregated forecast period\n" if $key eq 'SERVER.SENDNXH'
                    && $period !~ /^(?:4|8|12|16|24|32|40|48)$/;
            }
        }
    }
    return $cfg;
}

sub validate_settings {
    my ($data) = @_;
    my $settings = eval { decode_json($data) };
    die "Invalid pollen settings JSON\n" if $@ || ref($settings) ne 'HASH'
        || ref($settings->{pollen}) ne 'HASH';
    for my $key (qw(alder birch grass mugwort olive ragweed)) {
        my $value = $settings->{pollen}{$key};
        die "Invalid pollen sensitivity: $key\n"
            unless defined $value && !ref($value) && $value =~ /^[0-7]$/;
    }
}

sub validate_text {
    my ($data, $name) = @_;
    die "Invalid custom file size: $name\n" if !length($data) || length($data) > MAX_SIZE;
    die "Custom file is not valid UTF-8: $name\n"
        unless eval { decode('UTF-8', my $copy = $data, FB_CROAK); 1 };
    die "Custom file contains control characters: $name\n" if $data =~ /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/;
}

sub validate_theme {
    my ($data, $name) = @_;
    validate_text($data, $name);
    die "Invalid theme file: $name\n" unless $data =~ /<html\b/i;
}

sub validate_theme_language {
    my ($data, $name) = @_;
    validate_text($data, $name);
    my $language = eval { decode_json($data) };
    die "Invalid theme language JSON: $name\n" if $@ || ref($language) ne 'HASH'
        || !defined $language->{language} || ref($language->{language}) || $language->{language} eq '';
}

sub validate_ui_language {
    my ($data, $name) = @_;
    validate_text($data, $name);
    die "Invalid language file encoding: $name\n" if $data =~ /^\xEF\xBB\xBF/ || $data =~ /\r/;
    my $sections = 0;
    for my $line (split /\n/, $data) {
        next if $line =~ /^\s*(?:[;#].*)?$/;
        if ($line =~ /^\[[A-Za-z0-9_ .-]+\]$/) {
            $sections++;
        } elsif (!$sections || $line !~ /^[A-Za-z0-9_.-]+\s*=/) {
            die "Invalid language file: $name\n";
        }
    }
    die "Invalid language file: $name\n" unless $sections;
}

sub custom_files {
    my ($dirs) = @_;
    my %files;
    return \%files unless $dirs;
    for my $folder (sort keys %CUSTOM) {
        my $type = $CUSTOM{$folder};
        my $dir = $dirs->{$type->{dir}};
        next unless defined $dir && -d $dir;
        opendir(my $dh, $dir) or die "Cannot read $dir: $!\n";
        for my $file (sort readdir $dh) {
            next if $file !~ $type->{pattern} || $SHIPPED{$file};
            next if -l "$dir/$file" || !-f _;
            my $data = read_file("$dir/$file");
            $type->{validate}->($data, $file);
            $files{"$folder/$file"} = $data;
        }
        closedir $dh;
    }
    return \%files;
}

sub custom_targets {
    my ($files, $dirs) = @_;
    my %targets;
    for my $name (keys %$files) {
        my ($type, $file) = custom_entry($name) or next;
        my $dir = $dirs->{$type->{dir}} // die "Missing target directory for $name\n";
        $targets{"$dir/$file"} = $files->{$name};
    }
    return \%targets;
}

sub create_backup {
    my ($config_path, $settings_path, $version, $dirs) = @_;
    my %files = ('weather4lox.cfg' => read_file($config_path));
    # Missing JSON means the UI uses zero sensitivity for every pollen type.
    $files{'w4l-settings.json'} = -e $settings_path ? read_file($settings_path)
        : encode_json({ pollen => { map { $_ => 0 } qw(alder birch grass mugwort olive ragweed) } });
    validate_config($files{'weather4lox.cfg'});
    validate_settings($files{'w4l-settings.json'});
    %files = (%files, %{ custom_files($dirs) });
    $files{'manifest.json'} = encode_json({
        format => 2, plugin => 'weather4lox', version => $version,
        files => { map { $_ => sha256_hex($files{$_}) } keys %files },
    });
    my $total = 0;
    $total += length($_) for values %files;
    die "Uncompressed backup exceeds 8 MiB\n" if $total > MAX_ARCHIVE;
    my $zip = Archive::Zip->new;
    for my $name (sort keys %files) {
        $zip->addString($files{$name}, $name)->desiredCompressionMethod(COMPRESSION_DEFLATED);
    }
    my ($fh, $path) = tempfile(UNLINK => 1);
    binmode $fh;
    $zip->writeToFileHandle($fh) == AZ_OK or die "Cannot create ZIP archive\n";
    close $fh or die "Cannot close ZIP archive: $!\n";
    open my $zipfh, '<:raw', $path or die "Cannot read ZIP archive: $!\n";
    my $archive = do { local $/; <$zipfh> };
    close $zipfh or die "Cannot close ZIP archive: $!\n";
    die "ZIP archive exceeds 8 MiB\n" if length($archive) > MAX_ARCHIVE;
    return $archive;
}

sub allowed_entry {
    my ($name) = @_;
    return 1 if grep { $_ eq $name } 'manifest.json', @BASE_FILES;
    return defined((custom_entry($name))[0]);
}

sub read_backup {
    my ($data, $version) = @_;
    die "ZIP archive exceeds 8 MiB\n" if length($data) > MAX_ARCHIVE;
    die "Not a ZIP archive\n" unless substr($data, 0, 4) eq "PK\x03\x04";
    my ($fh, $path) = tempfile(UNLINK => 1);
    binmode $fh;
    print {$fh} $data or die "Cannot stage ZIP archive: $!\n";
    close $fh or die "Cannot close ZIP archive: $!\n";
    my $archive = Archive::Zip->new;
    $archive->read($path) == AZ_OK or die "Invalid or incomplete ZIP archive\n";
    my @members = $archive->members;
    die "Unexpected number of ZIP entries\n" unless @members >= 3 && @members <= MAX_ENTRIES;
    my %metadata;
    for my $member (@members) {
        my $name = $member->fileName;
        die "Unsafe, duplicate or unknown ZIP entry\n" if !allowed_entry($name) || $metadata{$name};
        die "Encrypted ZIP entries are not supported\n" if $member->isEncrypted;
        die "ZIP entry is too large\n" if $member->uncompressedSize > MAX_SIZE;
        die "ZIP entry is not a regular file\n" if $member->isDirectory
            || (($member->unixFileAttributes & 0170000) != 0
                && ($member->unixFileAttributes & 0170000) != 0100000);
        $metadata{$member->fileName} = $member;
    }
    # Stream with a hard limit as sizes in the ZIP directory are untrusted.
    my $zip = IO::Uncompress::Unzip->new(\$data, Strict => 1)
        or die "Cannot decompress ZIP archive\n";
    my (%files, $total);
    $total = 0;
    while (1) {
        my $name = $zip->getHeaderInfo->{Name};
        die "Unexpected ZIP stream\n" unless defined $name && $metadata{$name};
        die "Duplicate ZIP stream\n" if exists $files{$name};
        $files{$name} = '';
        while (1) {
            my $count = $zip->read(my $chunk, 8192);
            die "Damaged ZIP entry\n" if $count < 0;
            last if $count == 0;
            $total += $count;
            die "ZIP entry is too large\n" if length($files{$name}) + $count > MAX_SIZE;
            die "Uncompressed ZIP archive exceeds 8 MiB\n" if $total > MAX_ARCHIVE;
            $files{$name} .= $chunk;
        }
        my $next = $zip->nextStream;
        die "Damaged ZIP archive\n" if $next < 0;
        last if $next == 0;
    }
    die "Missing ZIP entries\n" unless keys(%files) == keys(%metadata)
        && !grep { !exists $files{$_} } 'manifest.json', @BASE_FILES;
    for my $name (keys %files) {
        die "ZIP directory does not match entry: $name\n"
            unless $metadata{$name}->uncompressedSize == length($files{$name})
                && $metadata{$name}->crc32 == crc32($files{$name});
    }
    my $manifest = eval { decode_json($files{'manifest.json'}) };
    die "Invalid backup manifest\n" if $@ || ref($manifest) ne 'HASH'
        || ($manifest->{plugin} // '') ne 'weather4lox'
        || ($manifest->{format} // '') !~ /^[12]$/
        || ref($manifest->{files}) ne 'HASH';
    my @content = sort grep { $_ ne 'manifest.json' } keys %files;
    die "Backup format 1 cannot contain custom files\n"
        if $manifest->{format} eq '1' && @content != @BASE_FILES;
    die "Backup manifest does not match ZIP entries\n"
        unless join("\0", sort keys %{ $manifest->{files} }) eq join("\0", @content);
    my ($major) = $version =~ /^(\d+)\./;
    die "Incompatible plugin version\n" unless defined $major
        && ($manifest->{version} // '') =~ /^\Q$major\E\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$/;
    for my $name (@content) {
        die "Backup checksum mismatch: $name\n"
            unless ($manifest->{files}{$name} // '') eq sha256_hex($files{$name});
    }
    my $cfg = validate_config($files{'weather4lox.cfg'});
    validate_settings($files{'w4l-settings.json'});
    for my $name (@content) {
        my ($type, $file) = custom_entry($name) or next;
        $type->{validate}->($files{$name}, $file);
    }
    delete $files{'manifest.json'};
    return (\%files, $cfg);
}

sub write_atomic {
    my ($path, $data, $mode) = @_;
    my ($directory) = $path =~ m{^(.*)/[^/]+$};
    my ($fh, $temporary) = tempfile('.weather4lox-import-XXXXXX', DIR => $directory, UNLINK => 1);
    binmode $fh;
    print {$fh} $data or die "Cannot write $path: $!\n";
    close $fh or die "Cannot close $path: $!\n";
    chmod($mode, $temporary) or die "Cannot set permissions for $path: $!\n";
    rename($temporary, $path) or die "Cannot replace $path: $!\n";
}

sub restore_files {
    my ($files, $activate) = @_;
    my (%previous, %modes);
    for my $path (keys %$files) {
        $previous{$path} = -e $path ? read_file($path) : undef;
        $modes{$path} = -e $path ? ((stat $path)[2] & 0777) : 0644;
    }
    my @written;
    eval {
        for my $path (sort keys %$files) {
            write_atomic($path, $files->{$path}, $modes{$path});
            push @written, $path;
        }
        $activate->() if $activate;
        1;
    } or do {
        my $error = $@ || "Import failed\n";
        for my $path (reverse @written) {
            eval {
                if (defined $previous{$path}) {
                    write_atomic($path, $previous{$path}, $modes{$path});
                } else {
                    unlink($path) or die "Cannot remove $path: $!\n";
                }
                1;
            } or $error .= "Rollback failed: $@";
        }
        die $error;
    };
}

1;
