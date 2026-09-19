package Astro::MoonPhase;

# Vendored copy of the CPAN module Astro::MoonPhase (public domain), bundled
# with the Weather4Lox plugin as a fallback.
#
# Background: Astro::MoonPhase is not available as a Debian package and is
# therefore installed via "cpanm Astro::MoonPhase" in postroot.sh. cpanm
# installs it below a Perl-version-specific path
# (/usr/local/share/perl/<version>/). When the system Perl is upgraded (e.g.
# during a Debian release upgrade), that path disappears from @INC and the
# module can no longer be found until the plugin is reinstalled - even though
# nothing about the plugin itself changed. This silently breaks every grabber
# that needs moon phase data (see grabber_utils.pl's requireOrLogdie).
#
# To make the plugin resilient against this class of failure, grabber_utils.pl
# adds this bin/lib directory to the end of @INC. A system-wide installation
# (if present and loadable) still takes precedence; this bundled copy is only
# used as a fallback so a Perl upgrade can no longer freeze the weather data.
#
# Upstream: https://metacpan.org/pod/Astro::MoonPhase (version 0.60)
# License: public domain ("Do what thou wilt shall be the whole of the law").

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(phase phasehunt phaselist);
$VERSION = '0.60';

use vars qw (
			$Epoch
			$Elonge $Elongp $Eccent	$Sunsmax $Sunangsiz
			$Mmlong $Mmlongp $Mlnode $Minc $Mecc $Mangsiz $Msmax $Mparallax $Synmonth
			$Pi
			);

# Astronomical constants.

$Epoch					= 2444238.5;		# 1980 January 0.0

# Constants defining the Sun's apparent orbit.

$Elonge					= 278.833540;		# ecliptic longitude of the Sun at epoch 1980.0
$Elongp					= 282.596403;		# ecliptic longitude of the Sun at perigee
$Eccent					= 0.016718;		# eccentricity of Earth's orbit
$Sunsmax				= 1.495985e8;		# semi-major axis of Earth's orbit, km
$Sunangsiz				= 0.533128;		# sun's angular size, degrees, at semi-major axis distance

# Elements of the Moon's orbit, epoch 1980.0.

$Mmlong					= 64.975464;		# moon's mean longitude at the epoch
$Mmlongp				= 349.383063;		# mean longitude of the perigee at the epoch
$Mlnode					= 151.950429;		# mean longitude of the node at the epoch
$Minc					= 5.145396;		# inclination of the Moon's orbit
$Mecc					= 0.054900;		# eccentricity of the Moon's orbit
$Mangsiz				= 0.5181;		# moon's angular size at distance a from Earth
$Msmax					= 384401.0;		# semi-major axis of Moon's orbit in km
$Mparallax				= 0.9507;		# parallax at distance a from Earth
$Synmonth				= 29.53058868;		# synodic month (new Moon to new Moon)

# Properties of the Earth.

$Pi					= 3.14159265358979323846;	# assume not near black hole nor in Tennessee

# Handy mathematical functions.

sub sgn		{ return (($_[0] < 0) ? -1 : ($_[0] > 0 ? 1 : 0)); } 	# extract sign
sub fixangle	{ return ($_[0] - 360.0 * (floor($_[0] / 360.0))); }	# fix angle
sub torad	{ return ($_[0] * ($Pi / 180.0)); }						# deg->rad
sub todeg	{ return ($_[0] * (180.0 / $Pi)); }						# rad->deg
sub dsin	{ return (sin(torad($_[0]))); }						# sin from deg
sub dcos	{ return (cos(torad($_[0]))); }						# cos from deg

sub tan		{ return sin($_[0])/cos($_[0]); }
sub asin	{ return ($_[0]<-1 or $_[0]>1) ? undef : atan2($_[0],sqrt(1-$_[0]*$_[0])); }
sub atan {
    if		($_[0]==0)	{ return 0; }
	elsif	($_[0]>0)	{ return atan2(sqrt(1+$_[0]*$_[0]),sqrt(1+1/($_[0]*$_[0]))); }
	else 				{ return -atan2(sqrt(1+$_[0]*$_[0]),sqrt(1+1/($_[0]*$_[0]))); }
}

sub floor {
  my $val   = shift;
  my $neg   = $val < 0;
  my $asint = int($val);
  my $exact = $val == $asint;

  return ($exact ? $asint : $neg ? $asint - 1 : $asint);
}



# jtime - convert internal date and time to astronomical Julian
# time (i.e. Julian date plus day fraction)


sub jtime {

        my $t = shift;
        my ($julian);
        $julian = ($t / 86400) + 2440587.5;	# (seconds /(seconds per day)) + julian date of epoch
        return ($julian);

}


# jdaytosecs - convert Julian date to a UNIX epoch

sub jdaytosecs {
  my $jday = shift;
  my $stamp;

  $stamp = ($jday - 2440587.5)*86400;   # (juliandate - jdate of unix epoch)*(seconds per julian day)
  return($stamp);

}



# jyear - convert Julian date to year, month, day, which are
# returned via integer pointers to integers
sub jyear {

	my ($td, $yy, $mm, $dd) = @_;
	my ($z, $f, $a, $alpha, $b, $c, $d, $e);

	$td += 0.5;				# astronomical to civil
	$z = floor($td);
	$f = $td - $z;

	if ($z < 2299161.0) {
		$a = $z;
	} else {
		$alpha = floor(($z - 1867216.25) / 36524.25);
		$a = $z + 1 + $alpha - floor($alpha / 4);
	}


	$b = $a + 1524;
	$c = floor(($b - 122.1) / 365.25);
	$d = floor(365.25 * $c);
	$e = floor(($b - $d) / 30.6001);

	$$dd = $b - $d - floor(30.6001 * $e) + $f;
	$$mm = $e < 14 ? $e - 1 : $e - 13;
	$$yy = $$mm > 2 ? $c - 4716 : $c - 4715;

}

##  meanphase  --  Calculates  time  of  the mean new Moon for a given
##                 base date.  This argument K to this function is the
##                 precomputed synodic month index, given by:
##
##                        K = (year - 1900) * 12.3685
##
##                 where year is expressed as a year and fractional year.


sub meanphase {
  my ($sdate, $k) = @_;
  my ($t, $t2, $t3, $nt1);

  ## Time in Julian centuries from 1900 January 0.5
  $t = ($sdate - 2415020.0) / 36525;
  $t2 = $t * $t;                       ## Square for frequent use
  $t3 = $t2 * $t;                      ## Cube for frequent use

  $nt1 = 2415020.75933 + $Synmonth * $k
         + 0.0001178 * $t2
         - 0.000000155 * $t3
         + 0.00033 * dsin(166.56 + 132.87 * $t - 0.009173 * $t2);

  return ($nt1);
}


# truephase - given a K value used to determine the mean phase of the
# new moon, and a phase selector (0.0, 0.25, 0.5, 0.75),
# obtain the true, corrected phase time

sub truephase {
	my ($k, $phase) = @_;
	my ($t, $t2, $t3, $pt, $m, $mprime, $f);
	my $apcor = 0;

	$k += $phase;				# add phase to new moon time
	$t = $k / 1236.85;			# time in Julian centuries from
								# 1900 January 0.5
	$t2 = $t * $t;				# square for frequent use
	$t3 = $t2 * $t;				# cube for frequent use

	# mean time of phase */
	$pt = 2415020.75933
	 + $Synmonth * $k
	 + 0.0001178 * $t2
	 - 0.000000155 * $t3
	 + 0.00033 * dsin(166.56 + 132.87 * $t - 0.009173 * $t2);

	# Sun's mean anomaly
	$m = 359.2242
	+ 29.10535608 * $k
	- 0.0000333 * $t2
	- 0.00000347 * $t3;

	# Moon's mean anomaly
	$mprime = 306.0253
	+ 385.81691806 * $k
	+ 0.0107306 * $t2
	+ 0.00001236 * $t3;

	# Moon's argument of latitude
	$f = 21.2964
	+ 390.67050646 * $k
	- 0.0016528 * $t2
	- 0.00000239 * $t3;

	if (($phase < 0.01) || (abs($phase - 0.5) < 0.01)) {
		# Corrections for New and Full Moon.

		$pt += (0.1734 - 0.000393 * $t) * dsin($m)
		 + 0.0021 * dsin(2 * $m)
		 - 0.4068 * dsin($mprime)
		 + 0.0161 * dsin(2 * $mprime)
		 - 0.0004 * dsin(3 * $mprime)
		 + 0.0104 * dsin(2 * $f)
		 - 0.0051 * dsin($m + $mprime)
		 - 0.0074 * dsin($m - $mprime)
		 + 0.0004 * dsin(2 * $f + $m)
		 - 0.0004 * dsin(2 * $f - $m)
		 - 0.0006 * dsin(2 * $f + $mprime)
		 + 0.0010 * dsin(2 * $f - $mprime)
		 + 0.0005 * dsin($m + 2 * $mprime);
	$apcor = 1;
	}
	elsif ((abs($phase - 0.25) < 0.01 || (abs($phase - 0.75) < 0.01))) {
		$pt += (0.1721 - 0.0004 * $t) * dsin($m)
		 + 0.0021 * dsin(2 * $m)
		 - 0.6280 * dsin($mprime)
		 + 0.0089 * dsin(2 * $mprime)
		 - 0.0004 * dsin(3 * $mprime)
		 + 0.0079 * dsin(2 * $f)
		 - 0.0119 * dsin($m + $mprime)
		 - 0.0047 * dsin($m - $mprime)
		 + 0.0003 * dsin(2 * $f + $m)
		 - 0.0004 * dsin(2 * $f - $m)
		 - 0.0006 * dsin(2 * $f + $mprime)
		 + 0.0021 * dsin(2 * $f - $mprime)
		 + 0.0003 * dsin($m + 2 * $mprime)
		 + 0.0004 * dsin($m - 2 * $mprime)
		 - 0.0003 * dsin(2 * $m + $mprime);
		if ($phase < 0.5) {
			# First quarter correction.
			$pt += 0.0028 - 0.0004 * dcos($m) + 0.0003 * dcos($mprime);
		}
		else {
			# Last quarter correction.
			$pt += -0.0028 + 0.0004 * dcos($m) - 0.0003 * dcos($mprime);
		}
		$apcor = 1;
	}
	if (!$apcor) {
		die "truephase() called with invalid phase selector ($phase).\n";
	}
	return ($pt);
}

# phasehunt - find time of phases of the moon which surround the current
# date.  Five phases are found, starting and ending with the
# new moons which bound the current lunation

sub phasehunt {
        my $sdate = jtime(shift || time());
        my ($adate, $k1, $k2, $nt1, $nt2);
        my ($yy, $mm, $dd);

        $adate = $sdate - 45;

	jyear($adate, \$yy, \$mm, \$dd);
	$k1 = floor(($yy + (($mm - 1) * (1.0 / 12.0)) - 1900) * 12.3685);

	$adate = $nt1 = meanphase($adate,  $k1);

        while (1) {
                $adate += $Synmonth;
		$k2 = $k1 + 1;
                $nt2 = meanphase($adate, $k2);
                if (($nt1 <= $sdate) && ($nt2 > $sdate)) {
                        last;
                }
                $nt1 = $nt2;
                $k1 = $k2;

        }



        return  (
                        jdaytosecs(truephase($k1, 0.0)),
                        jdaytosecs(truephase($k1, 0.25)),
                        jdaytosecs(truephase($k1, 0.5)),
                        jdaytosecs(truephase($k1, 0.75)),
                        jdaytosecs(truephase($k2, 0.0))
                        );
}



# phaselist - find time of phases of the moon between two dates
# times (in & out) are seconds_since_1970

sub phaselist
{
  my ($sdate, $edate) = map { jtime($_) } @_;

  my (@phases, $d, $k, $yy, $mm);

  jyear($sdate, \$yy, \$mm, \$d);
  $k = floor(($yy + (($mm - 1) * (1.0 / 12.0)) - 1900) * 12.3685) - 2;

  while (1) {
    ++$k;
    for my $phase (0.0, 0.25, 0.5, 0.75) {
      $d = truephase($k, $phase);

      return @phases if $d >= $edate;

      if ($d >= $sdate) {
        push @phases, int(4 * $phase) unless @phases;
        push @phases, jdaytosecs($d);
      } # end if date should be listed
    } # end for each $phase
  } # end while 1
} # end phaselist



# kepler - solve the equation of Kepler

sub kepler {
	my ($m, $ecc) = @_;
	my ($e, $delta);
	my $EPSILON = 1e-6;

	$m = torad($m);
	$e = $m;
	do {
		$delta = $e - $ecc * sin($e) - $m;
		$e -= $delta / (1 - $ecc * cos($e));
	} while (abs($delta) > $EPSILON);
	return ($e);
}



# phase - calculate phase of moon as a fraction:
#
# The argument is the time for which the phase is requested,
# expressed as a Julian date and fraction.  Returns the terminator
# phase angle as a percentage of a full circle (i.e., 0 to 1),
# and stores into pointer arguments the illuminated fraction of
# the Moon's disc, the Moon's age in days and fraction, the
# distance of the Moon from the centre of the Earth, and the
# angular diameter subtended by the Moon as seen by an observer
# at the centre of the Earth.

sub phase {
	my $pdate = jtime(shift || time());

	my $pphase;				# illuminated fraction
	my $mage;				# age of moon in days
	my $dist;				# distance in kilometres
	my $angdia;				# angular diameter in degrees
	my $sudist;				# distance to Sun
	my $suangdia;				# sun's angular diameter

	my ($Day, $N, $M, $Ec, $Lambdasun, $ml, $MM, $MN, $Ev, $Ae, $A3, $MmP,
	   $mEc, $A4, $lP, $V, $lPP, $NP, $y, $x, $Lambdamoon, $BetaM,
	   $MoonAge, $MoonPhase,
	   $MoonDist, $MoonDFrac, $MoonAng, $MoonPar,
	   $F, $SunDist, $SunAng,
	   $mpfrac);

	# Calculation of the Sun's position.

	$Day = $pdate - $Epoch;						# date within epoch
	$N = fixangle((360 / 365.2422) * $Day);				# mean anomaly of the Sun
	$M = fixangle($N + $Elonge - $Elongp);				# convert from perigee
									# co-ordinates to epoch 1980.0
	$Ec = kepler($M, $Eccent);					# solve equation of Kepler
	$Ec = sqrt((1 + $Eccent) / (1 - $Eccent)) * tan($Ec / 2);
	$Ec = 2 * todeg(atan($Ec));					# true anomaly
	$Lambdasun = fixangle($Ec + $Elongp);				# Sun's geocentric ecliptic
									# longitude
	# Orbital distance factor.
	$F = ((1 + $Eccent * cos(torad($Ec))) / (1 - $Eccent * $Eccent));
	$SunDist = $Sunsmax / $F;					# distance to Sun in km
	$SunAng = $F * $Sunangsiz;					# Sun's angular size in degrees


	# Calculation of the Moon's position.

	# Moon's mean longitude.
	$ml = fixangle(13.1763966 * $Day + $Mmlong);

	# Moon's mean anomaly.
	$MM = fixangle($ml - 0.1114041 * $Day - $Mmlongp);

	# Moon's ascending node mean longitude.
	$MN = fixangle($Mlnode - 0.0529539 * $Day);

	# Evection.
	$Ev = 1.2739 * sin(torad(2 * ($ml - $Lambdasun) - $MM));

	# Annual equation.
	$Ae = 0.1858 * sin(torad($M));

	# Correction term.
	$A3 = 0.37 * sin(torad($M));

	# Corrected anomaly.
	$MmP = $MM + $Ev - $Ae - $A3;

	# Correction for the equation of the centre.
	$mEc = 6.2886 * sin(torad($MmP));

	# Another correction term.
	$A4 = 0.214 * sin(torad(2 * $MmP));

	# Corrected longitude.
	$lP = $ml + $Ev + $mEc - $Ae + $A4;

	# Variation.
	$V = 0.6583 * sin(torad(2 * ($lP - $Lambdasun)));

	# True longitude.
	$lPP = $lP + $V;

	# Corrected longitude of the node.
	$NP = $MN - 0.16 * sin(torad($M));

	# Y inclination coordinate.
	$y = sin(torad($lPP - $NP)) * cos(torad($Minc));

	# X inclination coordinate.
	$x = cos(torad($lPP - $NP));

	# Ecliptic longitude.
	$Lambdamoon = todeg(atan2($y, $x));
	$Lambdamoon += $NP;

	# Ecliptic latitude.
	$BetaM = todeg(asin(sin(torad($lPP - $NP)) * sin(torad($Minc))));

	# Calculation of the phase of the Moon.

	# Age of the Moon in degrees.
	$MoonAge = $lPP - $Lambdasun;

	# Phase of the Moon.
	$MoonPhase = (1 - cos(torad($MoonAge))) / 2;

	# Calculate distance of moon from the centre of the Earth.

	$MoonDist = ($Msmax * (1 - $Mecc * $Mecc)) /
		(1 + $Mecc * cos(torad($MmP + $mEc)));

	# Calculate Moon's angular diameter.

	$MoonDFrac = $MoonDist / $Msmax;
	$MoonAng = $Mangsiz / $MoonDFrac;

	# Calculate Moon's parallax.

	$MoonPar = $Mparallax / $MoonDFrac;

	$pphase = $MoonPhase;
	$mage = $Synmonth * (fixangle($MoonAge) / 360.0);
	$dist = $MoonDist;
	$angdia = $MoonAng;
	$sudist = $SunDist;
	$suangdia = $SunAng;
	$mpfrac = fixangle($MoonAge) / 360.0;
	return wantarray ? ( $mpfrac, $pphase, $mage, $dist, $angdia, $sudist,$suangdia ) : $mpfrac;
}

1;
__END__

=head1 NAME

Astro::MoonPhase - Information about the phase of the Moon

=head1 SYNOPSIS

use Astro::MoonPhase;

	( $MoonPhase,
	  $MoonIllum,
	  $MoonAge,
	  $MoonDist,
	  $MoonAng,
	  $SunDist,
	  $SunAng ) = phase($seconds_since_1970);

	@phases  = phasehunt($seconds_since_1970);

	($phase, @times) = phaselist($start, $stop);

=head1 DESCRIPTION

MoonPhase calculates information about the phase of the moon
at a given time.

=head1 LICENCE

This program is in the public domain: "Do what thou wilt shall be the
whole of the law".

=head1 AUTHORS

The moontool.c Release 2.0:

    A Moon for the Sun
    Designed and implemented by John Walker in December 1987,
    revised and updated in February of 1988.

Initial Perl transcription:

    Raino Pikkarainen, 1998
    raino.pikkarainen@saunalahti.fi

The moontool.c Release 2.4:

    Major enhancements by Ron Hitchens, 1989

Revisions:

    Brett Hamilton  http://simple.be/
    Bug fix, 2003
    Second transcription and bugfixes, 2004

    Christopher J. Madsen  http://www.cjmweb.net/
    Added phaselist function, March 2007

=cut
