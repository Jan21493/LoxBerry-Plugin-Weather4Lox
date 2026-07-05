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
# The grabber scheduler depends entirely on this symlink.  It MUST be restored
# before any fallible operations so that a subsequent failure (e.g. ENOSPC on
# the log RAM disk) cannot leave the plugin permanently dead.
echo "<INFO> Recreate cronjob for fetching data from Weather Services"
# Remove existing symlink first (in case it points to a stale target)
rm -f "$ARGV5/system/cron/cron.01min/$ARGV3"
ln -s "$ARGV5/bin/plugins/$ARGV3/cronjob.pl" "$ARGV5/system/cron/cron.01min/$ARGV3"
# Verify the symlink was actually created
if [ -L "$ARGV5/system/cron/cron.01min/$ARGV3" ]; then
    echo "<OK> Cronjob symlink created: $ARGV5/system/cron/cron.01min/$ARGV3"
else
    echo "<ERROR> Failed to create cronjob symlink: $ARGV5/system/cron/cron.01min/$ARGV3"
    exit 1
fi

# ── Step 2: Restore config files (persistent storage, no space concerns) ────
echo "<INFO> Copy back existing config files"
if [ -d "/tmp/${ARGV1}_upgrade/config/${ARGV3}" ] && \
   [ "$(ls -A /tmp/${ARGV1}_upgrade/config/${ARGV3}/)" ]; then
    cp -p -v -r /tmp/${ARGV1}_upgrade/config/${ARGV3}/* \
        "${ARGV5}/config/plugins/${ARGV3}/"
fi

# ── Step 3: RAM disk space guard before restoring log files ─────────────────
# $PLOG lives on a zram RAM disk.  A full disk causes cp to fail and, under
# set -e, would abort the script.  We check available space, clean up stale
# log files in stages if needed, and protect the cp so ENOSPC is non-fatal.
#
# Thresholds (KiB):
#   AVAIL < 20 MiB (20480 KiB) → INFO   + remove plugin logs > 7 days old
#   AVAIL < 10 MiB (10240 KiB) → WARNING + remove all plugin logs > 1 day old
#   AVAIL <  2 MiB  (2048 KiB) → CRITICAL: staged cleanup; skip restore if still low
LOG_FS="${ARGV5}/log/plugins"
AVAIL_KB=$(df -k "$LOG_FS" 2>/dev/null | awk 'NR==2 {print $4}') || true

THRESH_INFO=20480   # 20 MiB in KiB
THRESH_WARN=10240   # 10 MiB in KiB
THRESH_CRIT=2048    #  2 MiB in KiB
SKIP_LOG_RESTORE=0

if [[ "$AVAIL_KB" =~ ^[0-9]+$ ]]; then
    if [ "$AVAIL_KB" -lt "$THRESH_CRIT" ]; then
        echo "<WARNING> Log RAM disk critically low: ${AVAIL_KB} KiB free. Cleaning up log files..."
        # Stage 1: remove log files older than 7 days
        find "$LOG_FS" -type f -mtime +7 -delete 2>/dev/null || true
        AVAIL_KB=$(df -k "$LOG_FS" 2>/dev/null | awk 'NR==2 {print $4}') || true
        [[ "$AVAIL_KB" =~ ^[0-9]+$ ]] || AVAIL_KB=0
        echo "<INFO> Available space after removing logs older than 7 days: ${AVAIL_KB} KiB"
        if [ "$AVAIL_KB" -lt "$THRESH_CRIT" ]; then
            # Stage 2: remove log files older than 1 day
            find "$LOG_FS" -type f -mtime +1 -delete 2>/dev/null || true
            AVAIL_KB=$(df -k "$LOG_FS" 2>/dev/null | awk 'NR==2 {print $4}') || true
            [[ "$AVAIL_KB" =~ ^[0-9]+$ ]] || AVAIL_KB=0
            echo "<INFO> Available space after removing logs older than 1 day: ${AVAIL_KB} KiB"
        fi
        if [ "$AVAIL_KB" -lt "$THRESH_CRIT" ]; then
            echo "<ERROR> Log RAM disk still critically low (${AVAIL_KB} KiB free). Log file restore will be skipped to prevent upgrade failure."
            SKIP_LOG_RESTORE=1
        fi
    elif [ "$AVAIL_KB" -lt "$THRESH_WARN" ]; then
        echo "<WARNING> Log RAM disk very low: ${AVAIL_KB} KiB free (< 10 MiB). Cleaning log files older than 1 day..."
        find "$LOG_FS" -type f -mtime +1 -delete 2>/dev/null || true
        AVAIL_KB=$(df -k "$LOG_FS" 2>/dev/null | awk 'NR==2 {print $4}') || true
        [[ "$AVAIL_KB" =~ ^[0-9]+$ ]] || AVAIL_KB=0
        echo "<INFO> Available space after cleanup: ${AVAIL_KB} KiB"
    elif [ "$AVAIL_KB" -lt "$THRESH_INFO" ]; then
        echo "<INFO> Log RAM disk low: ${AVAIL_KB} KiB free (< 20 MiB). Cleaning log files older than 7 days..."
        find "$LOG_FS" -type f -mtime +7 -delete 2>/dev/null || true
        AVAIL_KB=$(df -k "$LOG_FS" 2>/dev/null | awk 'NR==2 {print $4}') || true
        [[ "$AVAIL_KB" =~ ^[0-9]+$ ]] || AVAIL_KB=0
        echo "<INFO> Available space after cleanup: ${AVAIL_KB} KiB"
    fi
else
    echo "<WARNING> Could not determine available space on log disk (${LOG_FS}). Proceeding with caution."
fi

# ── Step 4: Restore log files (non-critical: on RAM disk, protected from set -e)
echo "<INFO> Copy back existing log files"
if [ "$SKIP_LOG_RESTORE" -eq 0 ] && \
   [ -d "/tmp/${ARGV1}_upgrade/log/${ARGV3}" ] && \
   [ "$(ls -A /tmp/${ARGV1}_upgrade/log/${ARGV3}/)" ]; then
    set +e
    cp -p -v -r /tmp/${ARGV1}_upgrade/log/${ARGV3}/* \
        "${ARGV5}/log/plugins/${ARGV3}/"
    CP_LOG_EXIT=$?
    set -e
    if [ "$CP_LOG_EXIT" -ne 0 ]; then
        echo "<WARNING> Some log files could not be restored (log RAM disk may be full). Continuing upgrade."
    fi
elif [ "$SKIP_LOG_RESTORE" -eq 1 ]; then
    echo "<WARNING> Log file restore skipped: log RAM disk was critically low even after cleanup."
fi

echo "<INFO> Copy back custom theme files"
if [ -d "/tmp/${ARGV1}_upgrade/themes" ] && \
   [ "$(ls -A /tmp/${ARGV1}_upgrade/themes/)" ]; then
    cp -p -v -r /tmp/${ARGV1}_upgrade/themes/* \
        "${ARGV5}/templates/plugins/${ARGV3}/themes/"
fi

echo "<INFO> Remove temporary folders"
rm -r /tmp/${ARGV1}_upgrade

# Read config, explicitly export/set LBHOMEDIR from ARGV5 as a fallback:
LBHOMEDIR="${LBHOMEDIR:-$ARGV5}"
if [ -f "${ARGV5}/config/plugins/${ARGV3}/weather4lox.cfg" ]; then
    . "${LBHOMEDIR}/libs/bashlib/iniparser.sh"
    iniparser "${ARGV5}/config/plugins/${ARGV3}/weather4lox.cfg" "SERVER"
fi

# Re-enable Cloud Emulator if it was enabled before upgrade
if [ "${SERVEREMU:-0}" -eq 1 ]; then
    echo "<INFO> Re-enabling Cloud Weather Emulator after upgrade"
    if ! $ARGV5/bin/plugins/$ARGV3/cloudemu.sh enable; then
        echo "<WARNING> Cloud Emulator could not be enabled - check DNS configuration manually"
    fi
fi
echo "<INFO> POSTUPGRADE script completed!"
# Exit with Status 0
exit 0
