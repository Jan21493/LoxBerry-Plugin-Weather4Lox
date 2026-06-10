#!/bin/bash

pluginname=weather4lox

PATH="/sbin:/bin:/usr/sbin:/usr/bin:$LBHOMEDIR/bin:$LBHOMEDIR/sbin"

ENVIRONMENT=$(cat /etc/environment)
export $ENVIRONMENT

echo "Loxone Weather Emulator started..."

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
OWNIP=`perl $LBHOMEDIR/bin/plugins/$pluginname/ownip.pl`
if [ -z $OWNIP ]; then
    echo "Cannot figure out a valid IP address. Giving up."
    exit 1
fi

# Check if own IP is reachable
PING=`ping -c1 $OWNIP`
if [ $? -ne 0 ]; then
    echo "Cannot reach my own IP address $OWNIP. Giving up."
    exit 1
fi

# Check for DNSMasq Plugin
CHECKDNSMASQ=`grep -c '"title" : "DNSmasq"' "$LBSDATA/plugindatabase.json"`

# Enable DNSMasq Config
case "$1" in

  enable)
    if [ $CHECKDNSMASQ -ge 1 ]; then
        echo "Found installed DNSMasq Plugin. Will add changes to existing DNSMasq configuration."
        echo "  address=/weather.loxone.com/$OWNIP > /etc/dnsmasq.d/$pluginname.conf"
        echo "  address=/weather-beta.loxone.com/$OWNIP >> /etc/dnsmasq.d/$pluginname.conf"

        sudo sh -c "echo 'address=/weather.loxone.com/$OWNIP' > /etc/dnsmasq.d/$pluginname.conf"
        sudo sh -c "echo 'address=/weather-beta.loxone.com/$OWNIP' >> /etc/dnsmasq.d/$pluginname.conf"
        sudo service dnsmasq restart > /dev/null 2>&1
    else
        echo "No DNSMasq Plugin found. Will set up standalone dnsmasq for Weather4Lox Cloud Emulator and manage its lifecycle."
        echo "Installing and enabling DNSMasq, add configuration for Weather4Lox, and set upstream DNS servers."
        echo "My own IP is $OWNIP. Redirecting weather.loxone.com to $OWNIP."

        # 1. Check if systemd-resolved stub is active on port 53
        if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
            if ss -tlunp 2>/dev/null | grep -qE "127\.0\.0\.53:53|0\.0\.0\.0:53"; then
                # Disable systemd-resolved stub listener to free port 53 for dnsmasq
                echo "<INFO> Disabling systemd-resolved stub listener to free port 53"
                sudo mkdir -p /etc/systemd/resolved.conf.d
                # Back up /etc/resolv.conf BEFORE overwriting
                if [ -L /etc/resolv.conf ]; then
                    # It's a symlink - save the link target
                    RESOLV_TARGET=$(readlink /etc/resolv.conf)
                    sudo sh -c "echo 'SYMLINK:$RESOLV_TARGET' > /etc/systemd/resolved.conf.d/weather4lox-resolv.bak"
                else
                    # It's a regular file - save full content
                    sudo cp /etc/resolv.conf /etc/systemd/resolved.conf.d/weather4lox-resolv.bak
                fi

                sudo sh -c "printf '[Resolve]\nDNSStubListener=no\n' > /etc/systemd/resolved.conf.d/weather4lox-nostub.conf"
                sudo systemctl restart systemd-resolved
                # Update /etc/resolv.conf to point to dnsmasq (127.0.0.1) instead of stub
                sudo sh -c "echo 'nameserver 127.0.0.1' > /etc/resolv.conf"
            fi
        fi

        # 2. Install dnsmasq if not present
        if ! command -v dnsmasq > /dev/null 2>&1; then
            echo "<INFO> Installing dnsmasq for Cloud Emulator"
            sudo apt-get install -y dnsmasq > /dev/null 2>&1
        fi
        
        # 3. enable and start dnsmasq in any case, even if it was already installed, to apply new configuration
        sudo systemctl enable dnsmasq > /dev/null 2>&1
        sudo systemctl stop dnsmasq > /dev/null 2>&1   # stop before configuring

        # 4. Configure dnsmasq
        sudo sh -c "echo 'address=/weather.loxone.com/$OWNIP' > /etc/dnsmasq.d/$pluginname.conf"
        sudo sh -c "echo 'address=/weather-beta.loxone.com/$OWNIP' >> /etc/dnsmasq.d/$pluginname.conf"
        sudo sh -c "echo '# add cloudflare DNS servers' >> /etc/dnsmasq.d/$pluginname.conf"
        sudo sh -c "echo 'server=1.1.1.1' >> /etc/dnsmasq.d/$pluginname.conf"
        sudo sh -c "echo 'server=1.0.0.1' >> /etc/dnsmasq.d/$pluginname.conf"
        sudo service dnsmasq restart
    fi
    # Enable Apache Config
    echo "Enabling Apache2 Configuration for Weather4Lox"
    sudo a2ensite 001-$pluginname > /dev/null 2>&1
    sudo service apache2 reload > /dev/null 2>&1
    exit 0
  ;;

  disable)
    # Disable DNSMasq Config
    if [ $CHECKDNSMASQ -ge 1 ]; then
        echo "Found installed DNSMasq Plugin. Will only remove Weather4Lox specific entries:"
        echo "  removing /etc/dnsmasq.d/$pluginname.conf"

        sudo rm /etc/dnsmasq.d/$pluginname.conf > /dev/null 2>&1
        sudo service dnsmasq restart > /dev/null 2>&1
    else
        echo "No DNSMasq Plugin found. Removing standalone dnsmasq for Weather4Lox."
        echo "This includes removing the Weather4Lox configuration and restoring any previous DNS settings."
        # 1. Remove weather4lox dnsmasq config
        sudo rm -f /etc/dnsmasq.d/$pluginname.conf

        # 2. Stop and remove dnsmasq service
        echo "<INFO> Removing dnsmasq and restoring previous DNS configuration"
        sudo systemctl stop dnsmasq > /dev/null 2>&1
        sudo apt-get purge -y dnsmasq dnsmasq-base > /dev/null 2>&1

        # 3. Restore DNS: if we disabled systemd-resolved stub, re-enable it
        if [ -f /etc/systemd/resolved.conf.d/weather4lox-nostub.conf ]; then
            echo "<INFO> Restoring systemd-resolved stub listener"
            sudo rm -f /etc/systemd/resolved.conf.d/weather4lox-nostub.conf
            sudo systemctl restart systemd-resolved
            # Restore /etc/resolv.conf from backup
            if [ -f /etc/systemd/resolved.conf.d/weather4lox-resolv.bak ]; then
                BACKUP=$(cat /etc/systemd/resolved.conf.d/weather4lox-resolv.bak)
                case "$BACKUP" in
                    SYMLINK:*)
                        LINK_TARGET="${BACKUP#SYMLINK:}"
                        sudo ln -sf "$LINK_TARGET" /etc/resolv.conf
                        echo "<INFO> Restored /etc/resolv.conf as symlink to $LINK_TARGET"
                        ;;
                    *)
                        sudo cp /etc/systemd/resolved.conf.d/weather4lox-resolv.bak /etc/resolv.conf
                        echo "<INFO> Restored /etc/resolv.conf from backup"
                        ;;
                esac
                sudo rm -f /etc/systemd/resolved.conf.d/weather4lox-resolv.bak
            else
                # Fallback if no backup exists
                sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
            fi
        fi
    fi
    # Disable Apache Config
    echo "Disabling Apache2 Configuration for Weather4Lox"
    sudo a2dissite 001-$pluginname > /dev/null 2>&1
    sudo service apache2 reload > /dev/null 2>&1
    exit 0
  ;;

  *)
    echo "Usage: $0 [enable|disable]" >&2
    exit 3
  ;;

esac
