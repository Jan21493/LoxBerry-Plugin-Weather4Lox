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
mkdir -p "/tmp/${ARGV1}_upgrade"
mkdir -p "/tmp/${ARGV1}_upgrade/config"
mkdir -p "/tmp/${ARGV1}_upgrade/log"
mkdir -p "/tmp/${ARGV1}_upgrade/themes"

if [ -f "$ARGV5/config/plugins/$ARGV3/cloudemu_state" ]; then
    echo "<INFO> Removing existing cloudemu_state file"
    rm "$ARGV5/config/plugins/$ARGV3/cloudemu_state"
fi

echo "<INFO> Backing up existing config files"
cp -p -v -r "$ARGV5/config/plugins/$ARGV3/" "/tmp/${ARGV1}_upgrade/config"

# ---- Selective backup from log directory ------------------------------------
# Policy:
#   - Always back up live weather data files used by frontend/runtime.
#   - For .log files:
#       * Never include logs older than 5 days.
#       * Keep up to 5 days if there is plenty of free space.
#       * Keep only last 1 day if there is some free space.
#       * Keep no .log files if free space is low.
#
# Note: We stage selected files in /tmp/${ARGV1}_upgrade/log/${ARGV3}/...
# to keep restore logic consistent with config backup layout.

echo "<INFO> Backing up existing log files (selective policy)"

LOG_SRC_DIR="$ARGV5/log/plugins/$ARGV3"
LOG_BACKUP_ROOT="/tmp/${ARGV1}_upgrade/log"
LOG_BACKUP_DIR="${LOG_BACKUP_ROOT}/${ARGV3}"

# Free-space thresholds on RAM log filesystem (KiB)
HEADROOM_KB=20480   # 20 MiB = "some free space"
PLENTY_KB=40960     # 40 MiB = "plenty free space"

LIVE_DATA_FILES=(
    "current.json"
    "dailyforecast.json"
    "hourlyforecast.json"
    "webpage.html"
    "webpage.map.html"
    "webpage.dfc.html"
    "webpage.hfc.html"
    "weatherdata.html"
    "index.txt"
)

if [ -d "$LOG_SRC_DIR" ]; then
    mkdir -p "$LOG_BACKUP_DIR"

    # 1) Always back up live data files
    LIVE_COUNT=0
    for f in "${LIVE_DATA_FILES[@]}"; do
        if [ -f "$LOG_SRC_DIR/$f" ]; then
            cp -p -v "$LOG_SRC_DIR/$f" "$LOG_BACKUP_DIR/"
            LIVE_COUNT=$((LIVE_COUNT + 1))
        fi
    done
    echo "<INFO> Backed up ${LIVE_COUNT} live data file(s)"

    # 2) Check currently available space on the target RAM log filesystem
    DF_TARGET="$LOG_SRC_DIR"
    [ -d "$DF_TARGET" ] || DF_TARGET="${ARGV5}/log/plugins"
    [ -d "$DF_TARGET" ] || DF_TARGET="${ARGV5}/log"

    AVAIL_KB=$(df -k "$DF_TARGET" 2>/dev/null | awk 'NR==2 {print $4}') || true
    [[ "$AVAIL_KB" =~ ^[0-9]+$ ]] || AVAIL_KB=0
    echo "<INFO> Current RAM log free space: ${AVAIL_KB} KiB"

    # 3) Decide .log retention window
    LOG_WINDOW_DAYS=0
    if [ "$AVAIL_KB" -ge "$PLENTY_KB" ]; then
        LOG_WINDOW_DAYS=5
        echo "<INFO> Free space is plenty. Backing up .log files from last 5 days."
    elif [ "$AVAIL_KB" -ge "$HEADROOM_KB" ]; then
        LOG_WINDOW_DAYS=1
        echo "<INFO> Free space is limited. Backing up .log files from last 1 day."
    else
        echo "<WARNING> Free space is low. Backing up no .log files (live data only)."
    fi

    # 4) Back up .log files according to retention window
    LOG_COUNT=0
    if [ "$LOG_WINDOW_DAYS" -eq 5 ]; then
        while IFS= read -r -d '' logfile; do
            rel="${logfile#$LOG_SRC_DIR/}"
            reldir="$(dirname "$rel")"
            [ "$reldir" = "." ] && reldir=""
            destdir="$LOG_BACKUP_DIR${reldir:+/$reldir}"
            mkdir -p "$destdir"
            cp -p -v "$logfile" "$destdir/"
            LOG_COUNT=$((LOG_COUNT + 1))
        done < <(find "$LOG_SRC_DIR" -type f -name "*.log" -mtime -6 -print0 2>/dev/null)
    elif [ "$LOG_WINDOW_DAYS" -eq 1 ]; then
        while IFS= read -r -d '' logfile; do
            rel="${logfile#$LOG_SRC_DIR/}"
            reldir="$(dirname "$rel")"
            [ "$reldir" = "." ] && reldir=""
            destdir="$LOG_BACKUP_DIR${reldir:+/$reldir}"
            mkdir -p "$destdir"
            cp -p -v "$logfile" "$destdir/"
            LOG_COUNT=$((LOG_COUNT + 1))
        done < <(find "$LOG_SRC_DIR" -type f -name "*.log" -mtime -2 -print0 2>/dev/null)
    fi
    echo "<INFO> Backed up ${LOG_COUNT} .log file(s) based on retention policy"

    # 5) Enforce deletion of logs older than 5 days in active log directory
    #    (only .log files, only this plugin directory).
    OLD_LOGS_DELETED=0
    while IFS= read -r -d '' oldlog; do
        rm -f "$oldlog" && OLD_LOGS_DELETED=$((OLD_LOGS_DELETED + 1))
    done < <(find "$LOG_SRC_DIR" -type f -name "*.log" -mtime +5 -print0 2>/dev/null)
    echo "<INFO> Deleted ${OLD_LOGS_DELETED} .log file(s) older than 5 days from active log directory"
else
    echo "<WARNING> Log source directory not found: ${LOG_SRC_DIR}; skipping log backup"
fi

echo "<INFO> Backing up existing custom theme files"
THEMES_DIR="${ARGV5}/templates/plugins/${ARGV3}/themes"
if [ -d "${THEMES_DIR}" ]; then
    cd "${THEMES_DIR}" || exit 1
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
    echo "<WARNING> Themes directory ${THEMES_DIR} not found; skipping theme backup"
fi

echo "<INFO> PREUPGRADE script completed!"
# Exit with Status 0
exit 0