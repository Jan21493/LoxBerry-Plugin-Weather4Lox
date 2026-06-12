#!/bin/sh

ARGV0=$0 # Zero argument is shell command
ARGV1=$1 # First argument is temp folder during install
ARGV2=$2 # Second argument is Plugin-Name for scipts etc.
ARGV3=$3 # Third argument is Plugin installation folder
ARGV4=$4 # Forth argument is Plugin version
ARGV5=$5 # Fifth argument is Base folder of LoxBerry

echo "<INFO> Creating temporary folders for upgrading"
mkdir -p /tmp/$ARGV1\_upgrade
mkdir -p /tmp/$ARGV1\_upgrade/config
mkdir -p /tmp/$ARGV1\_upgrade/log
mkdir -p /tmp/$ARGV1\_upgrade/themes
chown loxberry:loxberry $ARGV5/log/plugins/$ARGV3/*Emulator.log
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
