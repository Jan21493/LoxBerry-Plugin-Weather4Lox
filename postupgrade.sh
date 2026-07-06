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
    cp -p -v -r /tmp/${ARGV1}_upgrade/config/${ARGV3}/* \
        "${ARGV5}/config/plugins/${ARGV3}/"
fi

# ── Step 3: RAM disk space guard before restoring log files ─────────────────
# Strategy:
#   1. Measure the size of the log backup that is about to be restored.
#   2. Measure free space currently available on the RAM disk.
#   3. Predict free space after restore: free_after = avail - restore_size.
#   4. If free_after would drop below 20 MiB, delete old log files from THIS
#      plugin's log directory only (never touch other plugins' files).
#      Live data files (*.json, *.html, *.txt) are always excluded from
#      cleanup because they are actively served and must not be deleted.
#   5. Two cleanup stages: files older than 7 days first, then > 1 day.
#   6. If headroom is still insufficient after both stages, skip the restore
#      with a WARNING rather than risking ENOSPC under set -e.
#
# Headroom margin: 20 MiB (20480 KiB) - ensures the RAM disk does not
# become critically full immediately after the restore completes.

HEADROOM_KB=20480   # 20 MiB safety margin to keep free after restore

LOG_BACKUP_DIR="/tmp/${ARGV1}_upgrade/log/${ARGV3}"
LOG_DEST_DIR="${ARGV5}/log/plugins/${ARGV3}"

SKIP_LOG_RESTORE=0
RESTORE_KB=0
AVAIL_KB=0

if [ -d "$LOG_BACKUP_DIR" ] && [ "$(ls -A "$LOG_BACKUP_DIR"/)" ]; then
    # Measure the size of the backup to be restored (in KiB)
    RESTORE_KB=$(du -sk "$LOG_BACKUP_DIR" 2>/dev/null | awk '{print $1}') || true
    [[ "$RESTORE_KB" =~ ^[0-9]+$ ]] || RESTORE_KB=0
    echo "<INFO> Log backup size to restore: ${RESTORE_KB} KiB"

    # Measure free space on the RAM disk filesystem
    # Use LOG_DEST_DIR if it exists, fall back to parent directory for df
    DF_TARGET="$LOG_DEST_DIR"
    [ -d "$DF_TARGET" ] || DF_TARGET="${ARGV5}/log/plugins"
    [ -d "$DF_TARGET" ] || DF_TARGET="${ARGV5}/log"
    AVAIL_KB=$(df -k "$DF_TARGET" 2>/dev/null | awk 'NR==2 {print $4}') || true
    [[ "$AVAIL_KB" =~ ^[0-9]+$ ]] || AVAIL_KB=0
    echo "<INFO> RAM disk free space: ${AVAIL_KB} KiB"

    # Predict free space remaining after restore
    FREE_AFTER_KB=$(( AVAIL_KB - RESTORE_KB ))
    echo "<INFO> Predicted free space after restore: ${FREE_AFTER_KB} KiB (headroom required: ${HEADROOM_KB} KiB)"

    if [ "$FREE_AFTER_KB" -lt "$HEADROOM_KB" ]; then
        echo "<WARNING> Restore would leave less than 20 MiB free on log RAM disk. Cleaning old log files from this plugin only..."

        # Live data files that must never be deleted - they are actively served
        # by the web frontend and written by the grabber. Removing them would
        # break the plugin until the next grabber run.
        LIVE_DATA_EXCLUDES=(
            -not -name "current.json"
            -not -name "dailyforecast.json"
            -not -name "hourlyforecast.json"
            -not -name "webpage.html"
            -not -name "webpage.map.html"
            -not -name "webpage.dfc.html"
            -not -name "webpage.hfc.html"
            -not -name "weatherdata.html"
            -not -name "index.txt"
        )

        # Stage 1: remove log files older than 7 days (own plugin dir only)
        if [ -d "$LOG_DEST_DIR" ]; then
            FIND_RC=0
            find "$LOG_DEST_DIR" -type f -mtime +7 "${LIVE_DATA_EXCLUDES[@]}" -delete 2>/dev/null || FIND_RC=$?
            [ "$FIND_RC" -ne 0 ] && echo "<WARNING> Stage-1 cleanup (>7 days) encountered errors (rc=${FIND_RC})"
        fi

        # Re-measure free space after stage 1
        AVAIL_KB=$(df -k "$DF_TARGET" 2>/dev/null | awk 'NR==2 {print $4}') || true
        [[ "$AVAIL_KB" =~ ^[0-9]+$ ]] || AVAIL_KB=0
        FREE_AFTER_KB=$(( AVAIL_KB - RESTORE_KB ))
        echo "<INFO> Predicted free space after stage-1 cleanup: ${FREE_AFTER_KB} KiB"

        if [ "$FREE_AFTER_KB" -lt "$HEADROOM_KB" ]; then
            # Stage 2: remove log files older than 1 day (own plugin dir only)
            if [ -d "$LOG_DEST_DIR" ]; then
                FIND_RC=0
                find "$LOG_DEST_DIR" -type f -mtime +1 "${LIVE_DATA_EXCLUDES[@]}" -delete 2>/dev/null || FIND_RC=$?
                [ "$FIND_RC" -ne 0 ] && echo "<WARNING> Stage-2 cleanup (>1 day) encountered errors (rc=${FIND_RC})"
            fi

            # Re-measure free space after stage 2
            AVAIL_KB=$(df -k "$DF_TARGET" 2>/dev/null | awk 'NR==2 {print $4}') || true
            [[ "$AVAIL_KB" =~ ^[0-9]+$ ]] || AVAIL_KB=0
            FREE_AFTER_KB=$(( AVAIL_KB - RESTORE_KB ))
            echo "<INFO> Predicted free space after stage-2 cleanup: ${FREE_AFTER_KB} KiB"
        fi

        if [ "$FREE_AFTER_KB" -lt "$HEADROOM_KB" ]; then
            # Still not enough headroom even after cleaning all own log files.
            # If the disk is full because of other plugins, that is LoxBerry's
            # responsibility to handle - this plugin must not touch foreign files.
            echo "<WARNING> Log RAM disk does not have enough headroom for restore even after cleaning this plugin's old log files (${FREE_AFTER_KB} KiB would remain, ${HEADROOM_KB} KiB required). Log file restore will be skipped. This may indicate the RAM disk is full due to other plugins - check disk usage manually."
            SKIP_LOG_RESTORE=1
        fi
    fi
else
    echo "<INFO> No log backup found to restore, skipping space check."
    SKIP_LOG_RESTORE=1
fi

# ── Step 4: Restore log files (non-critical: on RAM disk, protected from set -e)
echo "<INFO> Copy back existing log files"
if [ "$SKIP_LOG_RESTORE" -eq 0 ]; then
    set +e
    cp -p -v -r "${LOG_BACKUP_DIR}/"* \
        "${LOG_DEST_DIR}/"
    CP_LOG_EXIT=$?
    set -e
    if [ "$CP_LOG_EXIT" -ne 0 ]; then
        echo "<WARNING> Some log files could not be restored (log RAM disk may be full). Continuing upgrade."
    else
        echo "<OK> Log files restored successfully."
    fi
elif [ -d "$LOG_BACKUP_DIR" ] && [ "$(ls -A "$LOG_BACKUP_DIR"/)" ]; then
    echo "<WARNING> Log file restore skipped: insufficient RAM disk headroom even after cleanup."
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