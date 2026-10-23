#!/bin/bash

big_version=`lsb_release -r | awk -F ' '  '{printf $NF}'`
deb_version=`cat /etc/debian_version | tr -d '\n'`
hw_result=`tr -d '\0' < /proc/device-tree/model`
username="${SUDO_USER:-$(logname 2>/dev/null | tr -d '\n')}"
if [ -z "$username" ] || [ "$username" = "root" ]; then
    username="$( awk -F: '$3==1000 {print $1}' /etc/passwd )"
fi

ver_lt() { dpkg --compare-versions "$1" lt "$2"; }
ver_ge() { dpkg --compare-versions "$1" ge "$2"; }

if [ $(getconf WORD_BIT) = '32' ] && [ $(getconf LONG_BIT) = '64' ] ; then
hardware_arch=64
else
hardware_arch=32
fi

if [[ $hw_result == *"Raspberry Pi 5"* ]]; then
hardware_model=5
else
hardware_model=255
fi

if [ "${LCD_AUTOLOGIN:-0}" = "1" ]; then
    sudo raspi-config nonint do_boot_behaviour B2
else
    if ver_ge "$deb_version" "13.1"; then
        sudo raspi-config nonint do_boot_behaviour B1
    else
        sudo raspi-config nonint do_boot_behaviour B3
    fi
fi
sudo raspi-config nonint do_wayland W1
if [ -f /boot/firmware/config.txt ]; then
sudo ln -sf /boot/firmware/config.txt /boot/config.txt
fi

if [ $hardware_arch -eq 32 ]; then
if [ $(($big_version)) -lt 10 ]; then
sudo cp -rf ./boot/config-nomal-10.9-32.txt ./boot/config.txt.bak
else
if ver_lt "$deb_version" "10.9" || [ "$deb_version" = "10.9" ]; then
sudo cp -rf ./boot/config-nomal-10.9-32.txt ./boot/config.txt.bak
elif ver_lt "$deb_version" "12.10"; then
sudo cp -rf ./boot/config-nomal-11.4-32.txt ./boot/config.txt.bak
else
sudo cp -rf ./boot/config-nomal-12.10-32.txt ./boot/config.txt.bak
fi
fi
elif [ $hardware_arch -eq 64 ]; then
if ver_lt "$deb_version" "12.10"; then
sudo cp -rf ./boot/config-nomal-11.4-64.txt ./boot/config.txt.bak
else
sudo cp -rf ./boot/config-nomal-12.10-64.txt ./boot/config.txt.bak
fi
fi


