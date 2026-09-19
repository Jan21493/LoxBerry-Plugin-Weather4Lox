package Math::Function::Interpolator;

# Minimal fallback re-implementation of the CPAN module
# Math::Function::Interpolator, bundled with the Weather4Lox plugin.
#
# Background: like Astro::MoonPhase (see bin/lib/Astro/MoonPhase.pm),
# Math::Function::Interpolator has no Debian package and is therefore
# installed via "cpanm Math::Function::Interpolator" in postroot.sh, together
# with its dependency Number::Closest::XS (a compiled/XS module). cpanm
# installs those below Perl-version-specific paths, which silently disappear
# from @INC after a Perl upgrade (e.g. during a Debian release upgrade) until
# the plugin is reinstalled - even though nothing about the plugin changed.
# This used to silently freeze grabber_wetteronline.pl and grabber_wttrin.pl,
# the two grabbers that interpolate hourly values (see issue #63).
#
# grabber_utils.pl adds this bin/lib directory to the end of @INC as a
# last-resort fallback; a system-wide installation (if present and loadable)
# still takes precedence.
#
# Unlike Astro::MoonPhase, this is not a verbatim vendored copy of the
# upstream module: this plugin only ever uses linear interpolation via
# Math::Function::Interpolator::Linear, so only that subset (a handful of
# lines of pure-Perl arithmetic) is re-implemented here, without depending on
# the XS module Number::Closest::XS or Math::Cephes::Matrix (used upstream
# for quadratic/cubic interpolation, which this plugin does not use).
#
# Upstream: https://metacpan.org/pod/Math::Function::Interpolator

use strict;
use warnings;
use Carp qw(confess);

our $VERSION = '0.01';

sub new {    ## no critic (RequireArgUnpacking)
    my $class = shift;
    my %params = ref($_[0]) ? %{$_[0]} : @_;

    confess "points are required to do interpolation"
        unless $params{points};

    # We can't interpolate properly on undef values so make sure we know
    # they are missing by removing them entirely.
    my $points = $params{points};
    my %clean_points = map { $_ => $points->{$_} }
        grep { defined $points->{$_} } keys %$points;

    return bless { _points => \%clean_points }, $class;
}

sub points {
    my ($self) = @_;
    return $self->{_points};
}

1;
