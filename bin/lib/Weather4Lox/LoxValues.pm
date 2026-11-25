package Weather4Lox::LoxValues;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(DEFAULT_LOX_PREFIX lox_value_names selected_lox_values);

use constant DEFAULT_LOX_PREFIX => 'w4l';

my @LOX_VALUES = qw(cur_tt cur_tt_fl cur_hu cur_w_dir cur_w_sp cur_w_gu cur_w_ch
                    cur_pr cur_dp cur_sr cur_we_code);

sub lox_value_names {
    return @LOX_VALUES;
}

sub selected_lox_values {
    my $setting = join ' ', grep { defined } @_;
    return lox_value_names() unless $setting =~ /\S/;
    my %selected = map { $_ => 1 } split ' ', $setting;
    return grep { $selected{$_} } lox_value_names();
}

1;
