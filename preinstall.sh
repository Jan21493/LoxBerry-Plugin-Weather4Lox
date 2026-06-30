#!/bin/bash

# preinstall.sh - Executed before plugin files are copied to their destinations.
# Runs as user "loxberry" AFTER preroot.sh and AFTER preupgrade.sh (on updates).
# Use this to prepare the installation, e.g. backing up existing config files,
# checking for dependencies, or creating required directories.
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
echo "<INFO> Plugin CGI folder is: $PCGI"
echo "<INFO> Plugin HTML folder is: $PHTML"
echo "<INFO> Plugin Template folder is: $PTEMPL"
echo "<INFO> Plugin Data folder is: $PDATA"
echo "<INFO> Plugin Log folder (RAM disk!) is: $PLOG"
echo "<INFO> Plugin Config folder is: $PCONFIG"

# Add your pre-copy installation tasks here.
# Example: back up an existing config before it gets overwritten
# if [ -f "$PCONFIG/myconfig.cfg" ]; then
#   cp "$PCONFIG/myconfig.cfg" /tmp/myconfig.cfg.bak
#   echo "<INFO> Backed up existing config to /tmp/myconfig.cfg.bak"
# fi

echo "<INFO> PREINSTALL script completed!"
# Exit with Status 0
exit 0