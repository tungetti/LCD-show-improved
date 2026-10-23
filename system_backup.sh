#!/bin/bash
deb_ver=`cat /etc/debian_version | tr -d '\n'`
username="${SUDO_USER:-$(logname 2>/dev/null | tr -d '\n')}"
if [ -z "$username" ] || [ "$username" = "root" ]; then
    username="$( awk -F: '$3==1000 {print $1}' /etc/passwd )"
fi

ver_lt() { dpkg --compare-versions "$1" lt "$2"; }
ver_ge() { dpkg --compare-versions "$1" ge "$2"; }

wait_for_apt_lock() {
    local waited=0
    while sudo fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1 \
       || pgrep -x "apt|apt-get|dpkg|unattended-upgr" >/dev/null 2>&1; do
        if [ "$waited" -eq 0 ]; then
            echo "Waiting for background apt/dpkg process to finish..."
        fi
        sleep 2
        waited=$((waited + 2))
        if [ "$waited" -ge 180 ]; then
            break
        fi
    done
}

if [ ! -f "./.system_backup/.backup_complete" ]; then
    sudo mkdir -p ./.system_backup
    sudo rm -rf ./.system_backup/* ./.system_backup/.[!.]* 2>/dev/null || true
    sudo mkdir -p ./.system_backup/xorg.conf.d

    if [ -d /etc/X11/xorg.conf.d ]; then
        sudo cp -rf /etc/X11/xorg.conf.d/. ./.system_backup/xorg.conf.d/
    fi

    result=`grep -rn "^dtoverlay=" /boot/config.txt 2>/dev/null | grep ":rotate=" | tail -n 1`
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        str=`echo -n $result | awk -F: '{printf $2}' | awk -F= '{printf $NF}'`
        if [ -f /boot/overlays/$str-overlay.dtb ]; then
            sudo cp -rf /boot/overlays/$str-overlay.dtb ./.system_backup
        fi
        if [ -f /boot/overlays/$str.dtbo ]; then
            sudo cp -rf /boot/overlays/$str.dtbo ./.system_backup
        fi
    fi

    if [ -f /boot/config.txt ]; then
        sudo cp -rf /boot/config.txt ./.system_backup/config.txt
    fi
    if [ -f /boot/cmdline.txt ]; then
        sudo cp -rf /boot/cmdline.txt ./.system_backup/cmdline.txt
    fi
    if [ -f /boot/firmware/cmdline.txt ]; then
        sudo cp -rf /boot/firmware/cmdline.txt ./.system_backup/firmware_cmdline.txt
    fi
    if [ -f /usr/share/X11/xorg.conf.d/99-fbturbo.conf ]; then
        sudo cp -rf /usr/share/X11/xorg.conf.d/99-fbturbo.conf ./.system_backup/
    fi
    if [ -f /etc/rc.local ]; then
        sudo cp -rf /etc/rc.local ./.system_backup/
    fi
    if [ -f /etc/modules ]; then
        sudo cp -rf /etc/modules ./.system_backup/
    fi
    if [ -f /etc/modprobe.d/fbtft.conf ]; then
        sudo cp -rf /etc/modprobe.d/fbtft.conf ./.system_backup
    fi
    if [ -f /etc/inittab ]; then
        sudo cp -rf /etc/inittab ./.system_backup
    fi
    if [ -n "$username" ] && [ -f "/home/$username/.bash_profile" ]; then
        sudo cp -rf "/home/$username/.bash_profile" ./.system_backup/.bash_profile
        sudo touch ./.system_backup/had_bash_profile
    fi
    type fbcp > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        sudo touch ./.system_backup/have_fbcp
    fi
    if [ -f /usr/share/X11/xorg.conf.d/10-evdev.conf ]; then
        sudo cp -rf /usr/share/X11/xorg.conf.d/10-evdev.conf ./.system_backup
    fi
    if [ -f /usr/share/X11/xorg.conf.d/45-evdev.conf ]; then
        sudo cp -rf /usr/share/X11/xorg.conf.d/45-evdev.conf ./.system_backup
    fi
    if [ -f ./.have_installed ]; then
        sudo cp -rf ./.have_installed ./.system_backup
    fi

    sudo touch ./.system_backup/.backup_complete
fi

if [ -f /etc/X11/xorg.conf.d/99-calibration.conf ]; then
    sudo rm -rf /etc/X11/xorg.conf.d/99-calibration.conf
fi

if [ -f /etc/X11/xorg.conf.d/40-libinput.conf ]; then
    sudo rm -rf /etc/X11/xorg.conf.d/40-libinput.conf
fi

result=`grep -rn "^dtoverlay=" /boot/config.txt 2>/dev/null | grep ":rotate=" | tail -n 1`
if [ $? -eq 0 ] && [ -n "$result" ]; then
    str=`echo -n $result | awk -F: '{printf $2}' | awk -F= '{printf $NF}'`
    if [ -f /boot/overlays/$str-overlay.dtb ]; then
        sudo rm -rf /boot/overlays/$str-overlay.dtb
    fi
    if [ -f /boot/overlays/$str.dtbo ]; then
        sudo rm -rf /boot/overlays/$str.dtbo
    fi
fi

root_dev=`grep -oPr "root=[^\s]*" /boot/cmdline.txt 2>/dev/null | awk -F= '{printf $NF}'`
if test "$root_dev" = "/dev/mmcblk0p7"; then
    sudo cp -rf ./boot/config-noobs-nomal.txt /boot/config.txt
    #sudo cp -rf ./usr/cmdline.txt-noobs-original /boot/cmdline.txt
else
    sudo cp -rf ./boot/config-nomal.txt /boot/config.txt

    if ver_ge "$deb_ver" "13.1"; then
        if [ -f /boot/firmware/cmdline.txt ]; then
            sudo sed -i '/ video/s/ video.*$//' /boot/firmware/cmdline.txt
        fi
        if [ -f /etc/xdg/lxsession/rpd-x/autostart ]; then
            sudo sed -i "/xrandr/d" /etc/xdg/lxsession/rpd-x/autostart
        fi
        if [ -n "$username" ]; then
            if [ -f ./.system_backup/had_bash_profile ] && [ -f ./.system_backup/.bash_profile ]; then
                sudo cp -rf ./.system_backup/.bash_profile "/home/$username/.bash_profile"
                sudo chown "$username:$username" "/home/$username/.bash_profile"
            elif [ -f "/home/$username/.bash_profile" ]; then
                sudo rm -rf "/home/$username/.bash_profile"
            fi
        fi
        if [ -f /usr/share/X11/xorg.conf.d/99-fbturbo.~ ]; then
            sudo rm -rf /usr/share/X11/xorg.conf.d/99-fbturbo.~
        fi

        #sudo cp -rf ./usr/cmdline.txt-original /boot/firmware/cmdline.txt
        #sudo cp ./etc/autostart /etc/xdg/lxsession/rpd-x/
    fi
fi

if ver_lt "$deb_ver" "12.1"; then
    sudo cp -rf ./usr/99-fbturbo.conf-original /usr/share/X11/xorg.conf.d/99-fbturbo.conf
fi
sudo cp -rf ./etc/rc.local-original /etc/rc.local
sudo cp -rf ./etc/modules-original /etc/modules

if [ -f /etc/modprobe.d/fbtft.conf ]; then
    sudo rm -rf /etc/modprobe.d/fbtft.conf
fi

if [ -f /etc/inittab ]; then
    sudo rm -rf /etc/inittab
fi

type fbcp > /dev/null 2>&1
if [ $? -eq 0 ]; then
    sudo rm -rf /usr/local/bin/fbcp
fi

#type cmake > /dev/null 2>&1
#if [ $? -eq 0 ]; then
#sudo touch ./.system_backup/have_cmake
#sudo apt-get purge cmake -y 2> error_output.txt
#result=`cat ./error_output.txt`
#echo -e "\033[31m$result\033[0m"
#fi

if [ -f /usr/share/X11/xorg.conf.d/10-evdev.conf ]; then
    wait_for_apt_lock
    sudo dpkg -P xserver-xorg-input-evdev
    #sudo apt-get purge xserver-xorg-input-evdev -y  2> error_output.txt
    #result=`cat ./error_output.txt`
    #echo -e "\033[31m$result\033[0m"
fi

if [ -f /usr/share/X11/xorg.conf.d/45-evdev.conf ]; then
    sudo rm -rf /usr/share/X11/xorg.conf.d/45-evdev.conf
fi

if [ -f /usr/local/bin/lcd35-multiscreen-daemon.sh ]; then
    sudo rm -rf /usr/local/bin/lcd35-multiscreen-daemon.sh
fi

if [ -f /usr/local/bin/lcd35-apply-xorg-mode.sh ]; then
    sudo rm -rf /usr/local/bin/lcd35-apply-xorg-mode.sh
fi

if [ -f /etc/xdg/autostart/lcd35-multiscreen.desktop ]; then
    sudo rm -rf /etc/xdg/autostart/lcd35-multiscreen.desktop
fi

if [ -f /etc/X11/xorg.conf.d/99-lcd35-layout.conf ]; then
    sudo rm -rf /etc/X11/xorg.conf.d/99-lcd35-layout.conf
fi

if [ -f /etc/sudoers.d/lcd35-multiscreen ]; then
    sudo rm -rf /etc/sudoers.d/lcd35-multiscreen
fi

sudo rm -rf /run/lcd35-xorg-mode /run/lcd35-restart-x 2>/dev/null || true

if [ -f ./.have_installed ]; then
    sudo rm -rf ./.have_installed
fi
