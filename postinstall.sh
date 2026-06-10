#!/bin/sh

# Bashscript which is executed by bash *AFTER* complete installation is done
# (but *BEFORE* postupdate). Use with caution and remember, that all systems
# may be different! Better to do this in your own Pluginscript if possible.
#
# Exit code must be 0 if executed successfull.
#
# Will be executed as user "loxberry".
#
# We add 5 arguments when executing the script:
# command <TEMPFOLDER> <NAME> <FOLDER> <VERSION> <BASEFOLDER>
#
# For logging, print to STDOUT. You can use the following tags for showing
# different colorized information during plugin installation:
#
# <OK> This was ok!"
# <INFO> This is just for your information."
# <WARNING> This is a warning!"
# <ERROR> This is an error!"
# <FAIL> This is a fail!"

# To use important variables from command line use the following code:
ARGV0=$0 # Zero argument is shell command
ARGV1=$1 # First argument is temp folder during install
ARGV2=$2 # Second argument is Plugin-Name for scipts etc.
ARGV3=$3 # Third argument is Plugin installation folder
ARGV4=$4 # Forth argument is Plugin version
ARGV5=$5 # Fifth argument is Base folder of LoxBerry

# Copy Apache2 configuration for WU4Lox
echo "<INFO> Installing Apache2 configuration for Weather4Lox"
cp $LBHOMEDIR/config/plugins/$ARGV3/apache2.conf $LBHOMEDIR/system/apache2/sites-available/001-$ARGV3.conf > /dev/null 2>&1

echo "<INFO> Installing Cronjob"
ln -s REPLACELBPBINDIR/weather4lox_cronjob.sh $LBHOMEDIR/system/cron/cron.hourly/99-weather4lox_cronjob > /dev/null 2>&1

# Remove old minutecron symlink if it exists from a previous installation
if [ -e $ARGV5/system/cron/cron.01min/99-weather4lox_minutecron ]; then
    echo "<INFO> Removing old minutecron symlink"
    rm $ARGV5/system/cron/cron.01min/99-weather4lox_minutecron > /dev/null 2>&1
fi

# Install 1-minute cronjob for local grabbers (FOSHK, PWSCatchUpload, Loxone)
echo "<INFO> Installing 1-minute cronjob for local grabbers"
ln -s REPLACELBPBINDIR/weather4lox_minutecron.pl \
    $LBHOMEDIR/system/cron/cron.01min/99-weather4lox_minutecron > /dev/null 2>&1

# Install Perl SQLite modules required for local observation buffer
echo "<INFO> Installing SQLite Perl modules for local observation buffer"
apt-get install -y libdbi-perl libdbd-sqlite3-perl sqlite3 > /dev/null 2>&1 \
    && echo "<OK> SQLite Perl modules installed successfully" \
    || echo "<WARNING> SQLite install had warnings - check manually"

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
