#!/bin/bash

# preupgrade.sh - Executed as the first step when updating an already-installed plugin.
# Runs as user "loxberry" BEFORE preinstall.sh, only during updates (not on fresh install).
# Use this to preserve existing user data before new files overwrite them,
# e.g. copy config files to /tmp so postinstall.sh or postupgrade.sh can restore them.
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
echo "<INFO> Plugin Config folder is: $PCONFIG"

# Add your pre-update backup tasks here.
# Example: save user config before it is overwritten by new default files
# if [ -f "$PCONFIG/myconfig.cfg" ]; then
#   cp "$PCONFIG/myconfig.cfg" /tmp/${PSHNAME}_myconfig.cfg.bak
#   echo "<INFO> Saved user config to /tmp/${PSHNAME}_myconfig.cfg.bak"
# fi

echo "<INFO> Creating temporary folders for upgrading"
mkdir -p /tmp/$ARGV1\_upgrade
mkdir -p /tmp/$ARGV1\_upgrade/config
mkdir -p /tmp/$ARGV1\_upgrade/log
mkdir -p /tmp/$ARGV1\_upgrade/themes

if [ -f $ARGV5/config/plugins/$ARGV3/cloudemu_state ]; then
    echo "<INFO> Removing existing cloudemu_state file"
    rm $ARGV5/config/plugins/$ARGV3/cloudemu_state
fi

echo "<INFO> Backing up existing config files"
cp -p -v -r $ARGV5/config/plugins/$ARGV3/ /tmp/$ARGV1\_upgrade/config

echo "<INFO> Backing up existing log files"
cp -p -v -r $ARGV5/log/plugins/$ARGV3/ /tmp/$ARGV1\_upgrade/log

echo "<INFO> Backing up existing custom theme files"
THEMES_DIR="${ARGV5}/templates/plugins/${ARGV3}/themes"
if [ -d "${THEMES_DIR}" ]; then
    cd "${THEMES_DIR}"
    for i in */; do                              # trailing / matches dirs only
        i="${i%/}"                               # strip trailing slash
        [ -d "$i" ] || continue
        CUSTOM=$(ls "${i}"/custom*.html 2>/dev/null) || true
        if [ -n "$CUSTOM" ]; then
            mkdir -p "/tmp/${ARGV1}_upgrade/themes/${i}"
            cp -p -v "${i}"/custom*.html "/tmp/${ARGV1}_upgrade/themes/${i}/"
        fi
    done
else
    echo "<WARN> Themes directory ${THEMES_DIR} not found; skipping theme backup"
fi
echo "<INFO> PREUPGRADE script completed!"
# Exit with Status 0
exit 0
