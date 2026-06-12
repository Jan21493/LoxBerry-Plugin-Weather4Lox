#!/bin/bash

pluginname=weather4lox

PATH="/sbin:/bin:/usr/sbin:/usr/bin:$LBHOMEDIR/bin:$LBHOMEDIR/sbin"

# Load LoxBerry environment variables correctly
set -a
. /etc/environment
set +a

# ── Verbose option for logging to standard output ───────────────────────────────────────────
# Argument parsing for the --verbose switch (before log start)
# LoxBerry Bashlib reacts to the set ENVIRONMENT="terminal" to display output directly on the shell
VERBOSE=0
ACTION=""

for arg in "$@"; do
    case $arg in
        --verbose)
            VERBOSE=1
            # These variables force LoxBerry's LOGSTART to mirror output to the console
            export STDERR=1
            export ADDTIME=1
            shift
            ;;
        enable|disable)
            ACTION=$arg
            shift
            ;;
    esac
done

# ── LoxBerry Logging setup ────────────────────────────────────────────────────
. $LBHOMEDIR/libs/bashlib/loxberry_log.sh

# OWN HELPER FUNCTION: Processes pipe output line by line for LoxBerry's WRITE
# Behaves like PIPE_TO_LOG but uses the existing WRITE function
function PIPE_TO_LOG {
    loadvariables
    while IFS= read -r line; do
        if [ -n "$pADDTIME" ]; then CURRTIME=$(date +"%H:%M:%S "); else CURRTIME=""; fi
        WRITE "$CURRTIME$line"
    done
}

PACKAGE=$pluginname
NAME="Emulator"
LOGDIR=$LBPLOG/$pluginname

LOGSTART "Cloud emulator $ACTION"
# ─────────────────────────────────────────────────────────────────────────────

LOGOK "Loxone weather cloud emulator script started ..."

# Check for WLAN adapter
#CHECKWLAN=`ifconfig | grep -c -i wlan0`
#if [ $CHECKWLAN -eq 1 ]; then
#	echo "Found configured WLAN adapter."
#	OWNIP=`ip addr show wlan0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1`
#	PING=`ping -c1 $OWNIP`
#	if [ $? -ne 0 ]; then
#		echo "Something is wrong with wlan0. Fallback to eth0."
#		OWNIP=`ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1`
#	fi
#else
#	OWNIP=`ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1`
#fi

# Check if we figured out an IP
# Use PIPE_TO_LOG to capture potential errors/output of the Perl script in the log
OWNIP=$(perl $LBHOMEDIR/bin/plugins/$pluginname/ownip.pl 2>&1)
if [ -z "$OWNIP" ]; then
    LOGERR "Cannot figure out a valid IP address. Giving up."
    LOGEND "Cloud Emulator failed"
    exit 1
fi
LOGDEB "Own IP address of Loxberry: $OWNIP"

# Check if own IP is reachable
ping -c1 $OWNIP 2>&1 | PIPE_TO_LOG
if [ $? -ne 0 ]; then
    LOGERR "Cannot reach my own IP address $OWNIP. Giving up."
    LOGEND "Cloud Emulator failed"
    exit 1
fi

# Check for DNSMasq Plugin
CHECKDNSMASQ=$(grep -c '"title" : "DNSmasq"' "$LBSDATA/plugindatabase.json")

# Enable DNSMasq Config
case "$ACTION" in

  enable)
    if [ $CHECKDNSMASQ -ge 1 ]; then
        LOGINF "Found installed DNSMasq Plugin. Will add changes to existing DNSMasq configuration."
        LOGDEB "  address=/weather.loxone.com/$OWNIP will be added to /etc/dnsmasq.d/$pluginname.conf"
        LOGDEB "  address=/weather-beta.loxone.com/$OWNIP will be added to /etc/dnsmasq.d/$pluginname.conf"
        LOGINF "Redirecting weather.loxone.com to $OWNIP."

        sudo sh -c "echo 'address=/weather.loxone.com/$OWNIP' > /etc/dnsmasq.d/$pluginname.conf" 2>&1 | PIPE_TO_LOG
        sudo sh -c "echo 'address=/weather-beta.loxone.com/$OWNIP' >> /etc/dnsmasq.d/$pluginname.conf" 2>&1 | PIPE_TO_LOG
        LOGINF "Restarting dnsmasq service"
        sudo service dnsmasq restart 2>&1 | PIPE_TO_LOG
    else
        LOGINF "No DNSMasq Plugin found. Will set up standalone dnsmasq for Weather4Lox Cloud Emulator and manage its lifecycle."
        LOGINF "Installing and enabling DNSMasq, add configuration for Weather4Lox, and set upstream DNS servers."

        # 1. Install dnsmasq if not present
        if ! command -v dnsmasq > /dev/null 2>&1; then
            LOGINF "Installing dnsmasq for Cloud Emulator (this takes a moment)..."
            # Recommended before apt-get install
            sudo apt-get update 2>&1 | PIPE_TO_LOG
            sudo apt-get install -y dnsmasq 2>&1 | PIPE_TO_LOG
        fi
        
        # 2. enable and start dnsmasq in any case, even if it was already installed, to apply new configuration
        LOGDEB "Enable dnsmasq and stop it temporarily."
        sudo systemctl enable dnsmasq 2>&1 | PIPE_TO_LOG
        # stop before configuring to avoid potential issues with dnsmasq running with incomplete config during setup
        sudo systemctl stop dnsmasq 2>&1 | PIPE_TO_LOG

        # 3. Configure dnsmasq
        LOGDEB "Redirecting weather.loxone.com to $OWNIP."
        sudo sh -c "echo 'address=/weather.loxone.com/$OWNIP' > /etc/dnsmasq.d/$pluginname.conf" 2>&1 | PIPE_TO_LOG
        sudo sh -c "echo 'address=/weather-beta.loxone.com/$OWNIP' >> /etc/dnsmasq.d/$pluginname.conf" 2>&1 | PIPE_TO_LOG

        sudo sh -c "echo '# add cloudflare DNS servers' >> /etc/dnsmasq.d/$pluginname.conf" 2>&1 | PIPE_TO_LOG
        sudo sh -c "echo 'server=1.1.1.1' >> /etc/dnsmasq.d/$pluginname.conf" 2>&1 | PIPE_TO_LOG
        sudo sh -c "echo 'server=1.0.0.1' >> /etc/dnsmasq.d/$pluginname.conf" 2>&1 | PIPE_TO_LOG
        LOGDEB "Adding Cloudflare DNS servers (1.1.1.1 and 1.0.0.1) to DNSmasq config"
        LOGINF "Restarting dnsmasq service"
        sudo service dnsmasq restart 2>&1 | PIPE_TO_LOG

        # ── Check status of DNSMasq service and log details ─────────────────
        if systemctl is-active --quiet dnsmasq; then
            # If active, get the PID and the uptime
            DNSMASQ_PID=$(systemctl show -p MainPID --value dnsmasq)
            DNSMASQ_ACTIVE_SINCE=$(systemctl show -p ActiveEnterTimestamp --value dnsmasq)
            
            LOGOK "DNSMasq service status: ACTIVE (Running successfully with PID $DNSMASQ_PID since $DNSMASQ_ACTIVE_SINCE)."
        else
            # If inactive or faulty, get the exact reason (SubState)
            DNSMASQ_SUBSTATE=$(systemctl show -p SubState --value dnsmasq)
            
            LOGWARN "DNSMasq service status: NOT RUNNING (Current substate: '$DNSMASQ_SUBSTATE'). Please check systemctl status dnsmasq."
        fi
    fi
    # Enable Apache Config
    LOGINF "Enabling Apache2 Configuration for Weather4Lox"
    sudo a2ensite 001-$pluginname 2>&1 | PIPE_TO_LOG
    LOGDEB "Reloading Apache2 to apply changes"
    sudo service apache2 reload 2>&1 | PIPE_TO_LOG
    
    # ── Check status of Apache2 service and log details ─────────────────
    if systemctl is-active --quiet apache2; then
        # If active, get the PID and the uptime
        APACHE_PID=$(systemctl show -p MainPID --value apache2)
        APACHE_ACTIVE_SINCE=$(systemctl show -p ActiveEnterTimestamp --value apache2)
        
        LOGOK "Apache2 Webserver status: ACTIVE (Running successfully with PID $APACHE_PID since $APACHE_ACTIVE_SINCE)."
    else
        # If inactive or faulty, get the exact reason (SubState)
        APACHE_SUBSTATE=$(systemctl show -p SubState --value apache2)
        
        LOGWARN "Apache2 Webserver status: NOT RUNNING (Current substate: '$APACHE_SUBSTATE'). Please check systemctl status apache2."
    fi

    # Check if public FQDN is reachable
    ping -c1 www.google.com 2>&1 | PIPE_TO_LOG
    if [ $? -ne 0 ]; then
        LOGERR "Cannot reach www.google.com. This might indicate a serious network issue."
    else
        LOGOK "Public FQDN is reachable, so DNS name resolution is working."
    fi

    LOGOK "Loxone Cloud emulator script finished - emulator is enabled."
    LOGEND
    exit 0
  ;;

  disable)
    # Disable DNSMasq Config
    if [ $CHECKDNSMASQ -ge 1 ]; then
        LOGINF "Found installed DNSMasq Plugin. Will only remove Weather4Lox specific entries:"
        LOGINF "  removing /etc/dnsmasq.d/$pluginname.conf"

        sudo rm -f /etc/dnsmasq.d/$pluginname.conf 2>&1 | PIPE_TO_LOG
        LOGINF "Restarting dnsmasq service"
        sudo service dnsmasq restart 2>&1 | PIPE_TO_LOG
    else
        LOGINF "No DNSMasq Plugin found. Removing standalone dnsmasq for Weather4Lox."
        LOGINF "This includes removing the Weather4Lox configuration and restoring any previous DNS settings."

        # 1. Remove weather4lox dnsmasq config
        LOGDEB "Step 1: Removing /etc/dnsmasq.d/$pluginname.conf"
        sudo rm -f /etc/dnsmasq.d/$pluginname.conf 2>&1 | PIPE_TO_LOG

        # 2. Stop dnsmasq service
        LOGDEB "Step 2: Stopping dnsmasq service"
        sudo systemctl stop dnsmasq 2>&1 | PIPE_TO_LOG

        # 2a. Logging off dnsmasq from resolvconf 
        if command -v resolvconf >/dev/null 2>&1; then
            LOGDEB "Step 2a: resolvconf used - unregistering dnsmasq from resolvconf"
            sudo resolvconf -d lo.dnsmasq 2>&1 | PIPE_TO_LOG
        fi

        # 3. Deinstalling dnsmasq packages
        LOGDEB "Step 3: Purging dnsmasq packages"
        sudo apt-get purge -y dnsmasq dnsmasq-base 2>&1 | PIPE_TO_LOG

        # 4. Generate /etc/resolv.conf from configured upstream DNS servers in resolvconf if available,
        #    to restore original DNS configuration before dnsmasq was installed
        if command -v resolvconf >/dev/null 2>&1; then
            LOGDEB "Step 4: resolvconf used - updating resolv.conf"
            sudo resolvconf -u 2>&1 | PIPE_TO_LOG
        fi
    fi
    # Disable Apache Config
    LOGINF "Disabling Apache2 Configuration for Weather4Lox"
    sudo a2dissite 001-$pluginname 2>&1 | PIPE_TO_LOG
    LOGDEB "Reloading Apache2 to apply changes"
    sudo service apache2 reload 2>&1 | PIPE_TO_LOG

    # ── Check status of Apache2 service and log details ─────────────────
    if systemctl is-active --quiet apache2; then
        # If active, get the PID and the uptime
        APACHE_PID=$(systemctl show -p MainPID --value apache2)
        APACHE_ACTIVE_SINCE=$(systemctl show -p ActiveEnterTimestamp --value apache2)
        
        LOGOK "Apache2 Webserver status: ACTIVE (Running successfully with PID $APACHE_PID since $APACHE_ACTIVE_SINCE)."
    else
        # If inactive or faulty, get the exact reason (SubState)
        APACHE_SUBSTATE=$(systemctl show -p SubState --value apache2)
        
        LOGWARN "Apache2 Webserver status: NOT RUNNING (Current substate: '$APACHE_SUBSTATE'). Please check systemctl status apache2."
    fi

    # Check if public FQDN is reachable
    ping -c1 www.google.com 2>&1 | PIPE_TO_LOG
    if [ $? -ne 0 ]; then
        LOGERR "Cannot reach www.google.com. This might indicate a serious network issue."
    else
        LOGOK "Public FQDN is reachable, so DNS name resolution is working."
    fi

    LOGOK "Loxone Cloud emulator script finished - emulator is disabled."
    LOGEND
    exit 0
  ;;

  *)
    LOGERR "Usage: $0 [enable|disable] [--verbose]"
    LOGEND
    exit 3
  ;;

esac