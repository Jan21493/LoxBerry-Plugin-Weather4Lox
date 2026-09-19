package Math::Function::Interpolator::Linear;

# Minimal fallback re-implementation of the linear interpolation part of the
# CPAN module Math::Function::Interpolator. See
# bin/lib/Math/Function/Interpolator.pm for background on why this fallback
# exists and why only linear interpolation is re-implemented here.

use strict;
use warnings;
use Carp qw(confess);
use Scalar::Util qw(looks_like_number);

require Math::Function::Interpolator;
our @ISA = qw(Math::Function::Interpolator);

# Solves for point_y linearly given point_x and an array of points.
sub linear {
    my ($self, $x) = @_;

    confess "sought_point[$x] must be a number" unless looks_like_number($x);
    my $ap = $self->points;
    return $ap->{$x} if defined $ap->{$x};    # no need to interpolate

    my @Xs = keys %$ap;
    confess "cannot interpolate with fewer than 2 data points"
        if scalar @Xs < 2;

    my ($first_x, $second_x) = _closest_pair($x, \@Xs);
    my ($first_y, $second_y) = ($ap->{$first_x}, $ap->{$second_x});

    my $m = ($second_y - $first_y) / ($second_x - $first_x);
    my $c = $first_y - ($first_x * $m);

    return $m * $x + $c;
}

# Re-implementation of Number::Closest::XS::find_closest_numbers_around($x,
# \@list, 2) without the XS dependency: picks the closest point below and the
# closest point above $x, falling back to the two closest points on a single
# side when $x is outside the data range. Returns them ascending (smaller,
# larger), matching the upstream contract used by linear() above.
sub _closest_pair {
    my ($x, $list) = @_;

    my @below = sort { $b <=> $a } grep { $_ < $x } @$list;
    my @above = sort { $a <=> $b } grep { $_ > $x } @$list;

    my ($first, $second);
    if (@below && @above) {
        ($first, $second) = ($below[0], $above[0]);
    } elsif (@below) {
        ($first, $second) = @below[1, 0];
    } else {
        ($first, $second) = @above[0, 1];
    }

    return sort { $a <=> $b } ($first, $second);
}

1;
