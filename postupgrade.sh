#!/bin/bash

# postupgrade.sh - Executed as the very last step when updating an already-installed plugin.
# Runs as user "loxberry" AFTER postinstall.sh, only during updates (not on fresh install).
# Use this to restore user data saved by preupgrade.sh, or to run any migration logic
# needed when upgrading from an older plugin version.
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

set -e   # exit immediately on error

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

# Add your post-update restore/migration tasks here.
# Example: restore user config saved by preupgrade.sh
# if [ -f "/tmp/${PSHNAME}_myconfig.cfg.bak" ]; then
#   cp "/tmp/${PSHNAME}_myconfig.cfg.bak" "$PCONFIG/myconfig.cfg"
#   echo "<OK> Restored user config from backup"
# fi

# ── Step 1: Recreate the critical cronjob symlink FIRST ─────────────────────
# The grabber scheduler depends entirely on this symlink. It MUST be restored
# before any fallible operations so that a subsequent failure cannot leave
# the plugin scheduler disabled.
echo "<INFO> Recreate cronjob for fetching data from Weather Services"
CRON_DIR="$ARGV5/system/cron/cron.01min"
if [ ! -d "$CRON_DIR" ]; then
    echo "<ERROR> Cron directory not found: $CRON_DIR"
    exit 1
fi
# Remove existing symlink first (in case it points to a stale target)
rm -f "$CRON_DIR/$ARGV3"
ln -s "$ARGV5/bin/plugins/$ARGV3/cronjob.pl" "$CRON_DIR/$ARGV3"
# Verify the symlink was actually created
if [ -L "$CRON_DIR/$ARGV3" ]; then
    echo "<OK> Cronjob symlink created: $CRON_DIR/$ARGV3"
else
    echo "<ERROR> Failed to create cronjob symlink: $CRON_DIR/$ARGV3"
    exit 1
fi

# ── Step 2: Restore config files (persistent storage, no space concerns) ────
echo "<INFO> Copy back existing config files"
if [ -d "/tmp/${ARGV1}_upgrade/config/${ARGV3}" ] && \
   [ "$(ls -A /tmp/${ARGV1}_upgrade/config/${ARGV3}/)" ]; then
    cp -p -v -r "/tmp/${ARGV1}_upgrade/config/${ARGV3}/"* \
        "${ARGV5}/config/plugins/${ARGV3}/"
fi

# ── Step 3: Restore selected log/data files (best effort) ───────────────────
# preupgrade.sh already applied retention/space policy:
#   - live weather data files always included
#   - .log files included adaptively (<=5d, <=1d, or none)
# Therefore no destructive cleanup is needed here.

echo "<INFO> Copy back selected log files"
LOG_BACKUP_DIR="/tmp/${ARGV1}_upgrade/log/${ARGV3}"
LOG_DEST_DIR="${ARGV5}/log/plugins/${ARGV3}"

if [ -d "$LOG_BACKUP_DIR" ] && [ "$(ls -A "$LOG_BACKUP_DIR"/)" ]; then
    mkdir -p "$LOG_DEST_DIR"
    set +e
    cp -p -v -r "${LOG_BACKUP_DIR}/"* "${LOG_DEST_DIR}/"
    CP_LOG_EXIT=$?
    set -e
    if [ "$CP_LOG_EXIT" -ne 0 ]; then
        echo "<WARNING> Some selected log/data files could not be restored (RAM log disk may be full). Continuing upgrade."
    else
        echo "<OK> Selected log/data files restored successfully."
    fi
else
    echo "<INFO> No selected log backup found to restore."
fi

echo "<INFO> Copy back custom theme files"
if [ -d "/tmp/${ARGV1}_upgrade/themes" ] && \
   [ "$(ls -A /tmp/${ARGV1}_upgrade/themes/)" ]; then
    cp -p -v -r /tmp/${ARGV1}_upgrade/themes/* \
        "${ARGV5}/templates/plugins/${ARGV3}/themes/"
fi

echo "<INFO> Remove temporary folders"
rm -r "/tmp/${ARGV1}_upgrade"

# Read config, explicitly export/set LBHOMEDIR from ARGV5 as a fallback:
LBHOMEDIR="${LBHOMEDIR:-$ARGV5}"
if [ -f "${ARGV5}/config/plugins/${ARGV3}/weather4lox.cfg" ]; then
    . "${LBHOMEDIR}/libs/bashlib/iniparser.sh"
    iniparser "${ARGV5}/config/plugins/${ARGV3}/weather4lox.cfg" "SERVER"
fi

# Re-enable Cloud Emulator if it was enabled before upgrade
if [ "${SERVEREMU:-0}" -eq 1 ]; then
    echo "<INFO> Re-enabling Cloud Weather Emulator after upgrade"
    if ! "$ARGV5/bin/plugins/$ARGV3/cloudemu.sh" enable; then
        echo "<WARNING> Cloud Emulator could not be enabled - check DNS configuration manually"
    fi
fi

echo "<INFO> POSTUPGRADE script completed!"
# Exit with Status 0
exit 0