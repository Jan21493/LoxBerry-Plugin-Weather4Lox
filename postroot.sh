#!/bin/sh

# <OK> This was ok!"
# <INFO> This is just for your information."
# <WARNING> This is a warning!"
# <ERROR> This is an error!"
# <FAIL> This is a fail!"

# To use important variables from command line use the following code:
ARGV0=$0 # Zero argument is shell command
ARGV1=$1 # First argument is temp folder during install
ARGV2=$2 # Second argument is Plugin-Name for scipts etc.
ARGV3=$3 # Third argument is Plugin installation folder
ARGV4=$4 # Forth argument is Plugin version
ARGV5=$5 # Fifth argument is Base folder of LoxBerry

# Helper to run a command, log it, and handle failures consistently.
# NOTE: we do not exit the script if the command / module installation fails,
#       but we log the error and continue with the next steps.
run_cmd() {
  desc="$1"
  shift

  echo "<INFO> $desc"
  "$@"
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "<ERROR> Failed: $desc (exit code $rc)"
    return $rc
  fi
  echo "<OK> $desc"
  return 0
}

# Installing Perl Module for some grabbers that require interpolation of values. 
run_cmd "Installing Perl Module Math::Function::Interpolator" cpanm Math::Function::Interpolator

# Installing Perl Module for almost all grabbers that require moon phase calculations.
run_cmd "Installing Perl Module Astro::MoonPhase" cpanm Astro::MoonPhase

run_cmd "Reconfigure Timezone - just to make sure..." dpkg-reconfigure -f noninteractive tzdata

# Install 'headers' module to Apache2 web server. The Apache Config for W4Lox requires the 'Headers' module to be enabled
run_cmd "Adding Apache2 headers module" a2enmod headers

# moved to dpkg/apt
# echo "<INFO> Installing Perl Module DateTime::Format::ISO8601"
# apt-get update
# apt-get install -y libdatetime-format-iso8601-perl

# Ensure dnsmasq does not start automatically after installation
# dnsmasq is no longer in dpkg/apt but may be installed later by cloudemu enable.
# This guard is a safety net in case dnsmasq is already installed on the system.
if command -v dnsmasq > /dev/null 2>&1; then
    echo "<INFO> dnsmasq found on system - ensuring it does not interfere with DNS if emulator is disabled"
    # Only stop dnsmasq if weather4lox cloudemu_state does NOT exist
    # (meaning the emulator was never enabled by this plugin)
    if [ ! -f "${ARGV5}/config/plugins/${ARGV3}/cloudemu_state" ]; then
        systemctl stop dnsmasq > /dev/null 2>&1 || true
        systemctl disable dnsmasq > /dev/null 2>&1 || true
    fi
fi

echo "<INFO> POSTROOT script completed!"
# Exit with Status 0
exit 0
