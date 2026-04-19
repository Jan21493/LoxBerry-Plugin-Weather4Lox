#!/bin/sh
set -e   # exit immediately on error

ARGV0=$0 # Zero argument is shell command
ARGV1=$1 # First argument is temp folder during install
ARGV2=$2 # Second argument is Plugin-Name for scipts etc.
ARGV3=$3 # Third argument is Plugin installation folder
ARGV4=$4 # Forth argument is Plugin version
ARGV5=$5 # Fifth argument is Base folder of LoxBerry

# Guard each copy with a directory existence check:
echo "<INFO> Copy back existing config files"
if [ -d "/tmp/${ARGV1}_upgrade/config/${ARGV3}" ] && \
   [ "$(ls -A /tmp/${ARGV1}_upgrade/config/${ARGV3}/)" ]; then
    cp -p -v -r /tmp/${ARGV1}_upgrade/config/${ARGV3}/* \
        "${ARGV5}/config/plugins/${ARGV3}/"
fi

echo "<INFO> Copy back existing log files"
if [ -d "/tmp/${ARGV1}_upgrade/log/${ARGV3}" ] && \
   [ "$(ls -A /tmp/${ARGV1}_upgrade/log/${ARGV3}/)" ]; then
    cp -p -v -r /tmp/${ARGV1}_upgrade/log/${ARGV3}/* \
        "${ARGV5}/log/plugins/${ARGV3}/"
fi

echo "<INFO> Copy back custom theme files"
if [ -d "/tmp/${ARGV1}_upgrade/themes" ] && \
   [ "$(ls -A /tmp/${ARGV1}_upgrade/themes/)" ]; then
    cp -p -v -r /tmp/${ARGV1}_upgrade/themes/* \
        "${ARGV5}/templates/plugins/${ARGV3}/themes/"
fi

echo "<INFO> Remove temporary folders"
rm -r /tmp/$ARGV1\_upgrade

echo "<INFO> Recreate cronjob for fetching data from Weather Services"
# Remove existing cronjob symlink - may return an error, because it is automatically done by installation script.
rm $ARGV5/system/cron/cron.01min/$ARGV3
ln -s $ARGV5/bin/plugins/$ARGV3/cronjob.pl $ARGV5/system/cron/cron.01min/$ARGV3

# Read config, explicitly export/set LBHOMEDIR from ARGV5 as a fallback:
LBHOMEDIR="${LBHOMEDIR:-$ARGV5}"
. "${LBHOMEDIR}/libs/bashlib/iniparser.sh"
iniparser "${ARGV5}/config/plugins/${ARGV3}/weather4lox.cfg" "SERVER"

if [ "${SERVEREMU:-0}" -eq 1 ]; then   # safe default if variable is empty
    echo "<INFO> Enabling Cloud Weather Emulator"
    $ARGV5/bin/plugins/$ARGV3/cloudemu enable > /dev/null 2>&1
fi
echo "<INFO> POSTUPGRADE script completed!"
# Exit with Status 0
exit 0
