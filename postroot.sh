#!/bin/bash

# postroot.sh - Executed as the absolute last installation step, after everything else.
# Runs as user "ROOT" AFTER postinstall.sh and AFTER postupgrade.sh.
# Use this for final tasks that require root privileges, e.g. reloading system services,
# setting special file ownership, or applying sudoers rules.
# Use with caution - remember that all target systems may differ.
#
# Exit codes:
#   0 = success, installation continues
#   1 = warning, installation continues but a warning is shown
#   2 = error, installation is cancelled
#
# All variables from /etc/environment are available in this script.
#
# Arguments passed to this script:
#   $0 = path to this script
#   $1 = temporary folder used during installation (short form)
#   $2 = plugin short name (NAME from plugin.cfg, used for scripts/cron)
#   $3 = plugin installation folder (FOLDER from plugin.cfg, may have 01/02 suffix)
#   $4 = plugin version (VERSION from plugin.cfg)
#   $5 = (unused, was LBHOMEDIR - now comes from /etc/environment)
#   $6 = full temporary path during installation
#
# Output tags for colorized installer log:
#   <OK>      green  - operation successful
#   <INFO>    blue   - informational message
#   <WARNING> yellow - non-fatal warning
#   <ERROR>   red    - error (combined with exit 2 to cancel)
#   <FAIL>    red    - failure

# Old-Style: To use important variables from command line use the following code:
ARGV0=$0 # Zero argument is shell command
ARGV1=$1 # First argument is temp folder during install
ARGV2=$2 # Second argument is Plugin-Name for scipts etc.
ARGV3=$3 # Third argument is Plugin installation folder
ARGV4=$4 # Forth argument is Plugin version
ARGV5=$5 # Fifth argument is Base folder of LoxBerry

# Track overall installation errors
INSTALL_ERRORS=0

# New-Style: To use important variables from /etc/environment use the following code:
COMMAND=$0      # Path to this script
PTEMPDIR=$1     # Temporary folder (short) during installation
PSHNAME=$2      # Plugin short name for scripts/cron
PDIR=$3         # Plugin installation folder
PVERSION=$4     # Plugin version
# $5 unused - LBHOMEDIR now comes from /etc/environment
PTEMPPATH=$6    # Full temporary path during installation

# Build full plugin-specific paths from environment variables
PCGI=$LBPCGI/$PDIR
PHTML=$LBPHTML/$PDIR
PTEMPL=$LBPTEMPL/$PDIR
PDATA=$LBPDATA/$PDIR
PLOG=$LBPLOG/$PDIR       # Stored on a RAM disk - not persistent across reboots!
PCONFIG=$LBPCONFIG/$PDIR
PSBIN=$LBPSBIN/$PDIR
PBIN=$LBPBIN/$PDIR

echo -n "<INFO> Current working folder is: "
pwd
echo "<INFO> Command is: $COMMAND"
echo "<INFO> Temporary folder is: $PTEMPDIR"
echo "<INFO> Temporary full path is: $PTEMPPATH"
echo "<INFO> Plugin short name is: $PSHNAME"
echo "<INFO> Installation folder is: $PDIR"
echo "<INFO> Plugin version is: $PVERSION"

# Add your final root-level tasks here.
# Example: reload sudoers after the sudoers file was installed
# visudo -c && echo "<OK> sudoers syntax is valid"

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
    INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
    return $rc
  fi
  echo "<OK> $desc"
  return 0
}

# Helper like run_cmd, but also prints the cpanm build log on failure
run_cpanm() {
  desc="$1"
  shift

  echo "<INFO> $desc"
  # Run cpanm and capture output (keep it visible AND capture for log check)
  "$@"
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "<ERROR> Failed: $desc (exit code $rc)"
    # Show the cpanm build log for better diagnostics
    CPANM_LOG=$(ls -t /root/.cpanm/work/*/build.log 2>/dev/null | head -1)
    if [ -n "$CPANM_LOG" ]; then
      echo "<INFO> cpanm build log ($CPANM_LOG):"
      tail -30 "$CPANM_LOG" | while IFS= read -r line; do
        echo "<INFO>   $line"
      done
    fi
    INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
    return $rc
  fi
  echo "<OK> $desc"
  return 0
}

# Installing Perl Module for some grabbers that require interpolation of values.
run_cpanm "Installing Perl Module Math::Function::Interpolator" cpanm Math::Function::Interpolator

# Installing Perl Module for almost all grabbers that require moon phase calculations.
run_cpanm "Installing Perl Module Astro::MoonPhase" cpanm Astro::MoonPhase

run_cmd "Reconfigure Timezone - just to make sure..." dpkg-reconfigure -f noninteractive tzdata

# Install 'headers' module to Apache2 web server. The Apache Config for W4Lox requires the 'Headers' module to be enabled
run_cmd "Adding Apache2 headers module" a2enmod headers

# moved to dpkg/apt
# echo "<INFO> Installing Perl Module DateTime::Format::ISO8601"
# apt-get update
# apt-get install -y libdatetime-format-iso8601-perl

if [ $INSTALL_ERRORS -gt 0 ]; then
  echo "<ERROR> POSTROOT completed with $INSTALL_ERRORS error(s). Some features may not work correctly."
else
  echo "<INFO> POSTROOT script completed!"
fi

# Exit with Status 0 - non-critical errors (e.g. optional Perl modules) should
# not abort the installation. Change to 'exit $INSTALL_ERRORS' if you want the
# installer to treat any failure as a hard error.
exit 0