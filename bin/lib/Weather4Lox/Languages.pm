package Weather4Lox::Languages;

use strict;
use warnings;
use Exporter 'import';
use JSON::PP qw(decode_json);

our @EXPORT_OK = qw(discover_languages);

sub discover_languages {
    my ($directory) = @_;
    opendir my $dh, $directory or die "Cannot read language directory $directory: $!";
    my @files = sort readdir $dh;
    closedir $dh;
    my @languages;
    for my $file (@files) {
        my ($code) = $file =~ /^lang-([a-z]{2,3}(?:[-_][A-Za-z0-9]+)*)\.json$/;
        next unless defined $code && -f "$directory/$file";
        my $path = "$directory/$file";
        open my $fh, '<:raw', $path or die "Cannot read $path: $!";
        my $contents = do { local $/; <$fh> };
        close $fh;
        my $strings = eval { decode_json($contents) };
        if ($@) {
            warn "Invalid theme language file $path: $@";
            next;
        }
        if (ref($strings) ne 'HASH' || !defined $strings->{language}
            || ref($strings->{language}) || $strings->{language} !~ /\S/) {
            warn "Missing language name in $path\n";
            next;
        }
        push @languages, { code => $code, language => $strings->{language} };
    }
    return \@languages;
}

1;
