#!/usr/bin/perl

use strict;
use warnings;
use LoxBerry::System;
use lib "$lbpbindir/lib";
use Weather4Lox::Languages qw(discover_languages);
use JSON::PP qw(encode_json);

my $languages = eval { discover_languages($lbphtmldir) };
if ($@) {
    warn "Cannot list theme languages: $@";
    print "Status: 500 Internal Server Error\r\n";
    print "Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n";
    print encode_json({ error => 'Cannot list theme languages' });
    exit;
}

print "Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n";
print encode_json($languages);
