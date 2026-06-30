#!/bin/bash

# postinstall.sh - Executed after all plugin files have been copied.
# Runs as user "loxberry" AFTER files are installed and BEFORE postupgrade.sh.
# Use this for post-copy tasks that do not require root, e.g. setting file
# permissions, writing initial config values, or enabling a cron job.
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
echo "<INFO> Plugin CGI folder is: $PCGI"
echo "<INFO> Plugin HTML folder is: $PHTML"
echo "<INFO> Plugin Template folder is: $PTEMPL"
echo "<INFO> Plugin Data folder is: $PDATA"
echo "<INFO> Plugin Log folder (RAM disk!) is: $PLOG"
echo "<INFO> Plugin Config folder is: $PCONFIG"

# Add your post-copy installation tasks here.
# Example: make a CGI script executable
# chmod 755 "$PCGI/myscript.cgi"
# echo "<OK> Set permissions on CGI script"

# Copy Apache2 configuration for WU4Lox
echo "<INFO> Installing Apache2 configuration for Weather4Lox"
cp $LBHOMEDIR/config/plugins/$ARGV3/apache2.conf $LBHOMEDIR/system/apache2/sites-available/001-$ARGV3.conf > /dev/null 2>&1

echo "<INFO> Installing Cronjob"
ln -s REPLACELBPBINDIR/weather4lox_cronjob.sh $LBHOMEDIR/system/cron/cron.hourly/99-weather4lox_cronjob > /dev/null 2>&1

# Copy Dummy files
echo "<INFO> Copy dummy data files"
# JSON dummy files for fresh installations
if [ ! -e $LBPLOG/$ARGV3/current.json ]; then
	cp $LBPDATA/$ARGV3/dummies/current.json $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/dailyforecast.json ]; then
	cp $LBPDATA/$ARGV3/dummies/dailyforecast.json $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/hourlyforecast.json ]; then
	cp $LBPDATA/$ARGV3/dummies/hourlyforecast.json $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/webpage.html ]; then
	cp $LBPDATA/$ARGV3/dummies/webpage.html $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/webpage.map.html ]; then
	cp $LBPDATA/$ARGV3/dummies/webpage.map.html $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/webpage.dfc.html ]; then
	cp $LBPDATA/$ARGV3/dummies/webpage.dfc.html $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/webpage.hfc.html ]; then
	cp $LBPDATA/$ARGV3/dummies/webpage.hfc.html $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/weatherdata.html ]; then
	cp $LBPDATA/$ARGV3/dummies/weatherdata.html $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/index.txt ]; then
	cp $LBPDATA/$ARGV3/dummies/index.txt $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
REPLACELBPBINDIR/weather4lox_cronjob.sh > /dev/null 2>&1

echo "<INFO> Creating Symlinks in Webfolder"
ln -s $LBPLOG/REPLACELBPPLUGINDIR/webpage.html $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/webpage.html > /dev/null 2>&1
ln -s $LBPLOG/REPLACELBPPLUGINDIR/webpage.map.html $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/webpage.map.html > /dev/null 2>&1
ln -s $LBPLOG/REPLACELBPPLUGINDIR/webpage.dfc.html $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/webpage.dfc.html > /dev/null 2>&1
ln -s $LBPLOG/REPLACELBPPLUGINDIR/webpage.hfc.html $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/webpage.hfc.html > /dev/null 2>&1
ln -s $LBPLOG/REPLACELBPPLUGINDIR/weatherdata.html $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/weatherdata.html > /dev/null 2>&1
ln -s $LBPLOG/REPLACELBPPLUGINDIR/index.txt $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/emu/forecast/index.txt > /dev/null 2>&1

ln -s $LBPLOG/REPLACELBPPLUGINDIR/current.json $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/current.json > /dev/null 2>&1
ln -s $LBPLOG/REPLACELBPPLUGINDIR/dailyforecast.json $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/dailyforecast.json > /dev/null 2>&1
ln -s $LBPLOG/REPLACELBPPLUGINDIR/hourlyforecast.json $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/hourlyforecast.json > /dev/null 2>&1

### TEMPORARY workaround since old cronjobs are not deleted by LoxBerry V3
# if [ -e $ARGV5/system/cron/cron.01min/$ARGV3 ]; then
#         echo "<INFO> Old cronjob for every minute was removed"
#         rm $ARGV5/system/cron/cron.01min/$ARGV3
# fi
if [ -e $ARGV5/system/cron/cron.03min/$ARGV3 ]; then
        echo "<INFO> Old cronjob for every 3 minutes was removed"
        rm $ARGV5/system/cron/cron.03min/$ARGV3 > /dev/null 2>&1
fi
if [ -e $ARGV5/system/cron/cron.05min/$ARGV3 ]; then
        echo "<INFO> Old cronjob for every 5 minutes was removed"
        rm $ARGV5/system/cron/cron.05min/$ARGV3 > /dev/null 2>&1
fi
if [ -e $ARGV5/system/cron/cron.10min/$ARGV3 ]; then
        echo "<INFO> Old cronjob for every 10 minutes was removed"
        rm $ARGV5/system/cron/cron.10min/$ARGV3 > /dev/null 2>&1
fi
if [ -e $ARGV5/system/cron/cron.15min/$ARGV3 ]; then
        echo "<INFO> Old cronjob for every 15 minutes was removed"
        rm $ARGV5/system/cron/cron.15min/$ARGV3 > /dev/null 2>&1
fi
if [ -e $ARGV5/system/cron/cron.30min/$ARGV3 ]; then
        echo "<INFO> Old cronjob for every 30 minutes was removed"
        rm $ARGV5/system/cron/cron.30min/$ARGV3 > /dev/null 2>&1
fi
if [ -e $ARGV5/system/cron/cron.hourly/$ARGV3 ]; then
        echo "<INFO> Old cronjob for every hour was removed"
        rm $ARGV5/system/cron/cron.hourly/$ARGV3 > /dev/null 2>&1
fi
echo "<INFO> POSTINSTALL script completed!"

# Exit with Status 0
exit 0
