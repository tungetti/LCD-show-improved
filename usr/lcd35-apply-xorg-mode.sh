#!/bin/bash
# lcd35-apply-xorg-mode.sh
# Generates /etc/X11/xorg.conf.d/99-lcd35-layout.conf dynamically based on whether
# any HDMI cable is connected:
# - 0 HDMI cables connected ("single"):
#   Sets Option "AutoAddGPU" "false" (preventing 99-v3d.conf from hijacking PrimaryGPU
#   onto a headless vc4 card) and binds Screen 0 directly to the 3.5" SPI LCD.
# - 1 or 2 HDMI cables connected ("multi"):
#   Binds Screen 0 (main desktop) to the vc4 HDMI card (HDMI-1 / HDMI-2) and binds
#   Screen 1 (RightOf Screen 0) to the 3.5" SPI LCD as 2nd / 3rd screen.

set -u

SYS_GRAPHICS_DIR="${SYS_GRAPHICS_DIR:-/sys/class/graphics}"
SYS_DRM_DIR="${SYS_DRM_DIR:-/sys/class/drm}"
XORG_CONF_OUT="${XORG_CONF_OUT:-/etc/X11/xorg.conf.d/99-lcd35-layout.conf}"
STATE_FILE="${STATE_FILE:-/run/lcd35-xorg-mode}"
RESTART_FLAG_FILE="${RESTART_FLAG_FILE:-/run/lcd35-restart-x}"
FBDEV_DRV_PATH="${FBDEV_DRV_PATH:-}"

detect_fbdev_driver() {
    if [ -n "$FBDEV_DRV_PATH" ]; then
        [ -f "$FBDEV_DRV_PATH" ] && return 0 || return 1
    fi
    if [ -f /usr/lib/xorg/modules/drivers/fbdev_drv.so ]; then
        return 0
    fi
    local p
    for p in /usr/lib/*/xorg/modules/drivers/fbdev_drv.so; do
        if [ -f "$p" ]; then
            return 0
        fi
    done
    return 1
}

detect_spi_fb() {
    local fb_dir fb_name dev_path
    for fb_dir in "$SYS_GRAPHICS_DIR"/fb[0-9]*; do
        [ -d "$fb_dir" ] || continue
        fb_name="$(cat "$fb_dir/name" 2>/dev/null || true)"
        dev_path="$(readlink -f "$fb_dir/device" 2>/dev/null || true)"
        if printf '%s %s\n' "$fb_name" "$dev_path" | grep -Eiq "ili9486|piscreen|tft|fbtft|spi|st77|hx8357"; then
            printf '/dev/%s\n' "$(basename "$fb_dir")"
            return 0
        fi
    done

    for fb_dir in "$SYS_GRAPHICS_DIR"/fb[0-9]*; do
        [ -d "$fb_dir" ] || continue
        fb_name="$(cat "$fb_dir/name" 2>/dev/null || true)"
        if [ -n "$fb_name" ] && ! printf '%s\n' "$fb_name" | grep -Eiq "vc4|bcm2708"; then
            printf '/dev/%s\n' "$(basename "$fb_dir")"
            return 0
        fi
    done

    if [ -e /dev/fb1 ]; then
        printf '/dev/fb1\n'
    else
        printf '/dev/fb0\n'
    fi
}

detect_spi_card() {
    local card_dir card_base dev_path drv_path uevent_txt conn_dir conn_base
    for card_dir in "$SYS_DRM_DIR"/card[0-9]*; do
        [ -d "$card_dir" ] || continue
        card_base="$(basename "$card_dir")"
        case "$card_base" in
            card[0-9]|card[0-9][0-9]) ;;
            *) continue ;;
        esac
        dev_path="$(readlink -f "$card_dir/device" 2>/dev/null || true)"
        drv_path="$(readlink -f "$card_dir/device/driver" 2>/dev/null || true)"
        uevent_txt="$(cat "$card_dir/device/uevent" 2>/dev/null || true)"
        if printf '%s %s %s\n' "$dev_path" "$drv_path" "$uevent_txt" | grep -Eiq "spi|ili9486|piscreen|mi0283qt|hx8357|st77|drm_mipi_dbi"; then
            printf '/dev/dri/%s\n' "$card_base"
            return 0
        fi
        for conn_dir in "$SYS_DRM_DIR"/"${card_base}"-*; do
            [ -d "$conn_dir" ] || continue
            conn_base="$(basename "$conn_dir")"
            case "$conn_base" in
                "${card_base}"-HDMI-*|"${card_base}"-Writeback-*|"${card_base}"-Composite-*)
                    ;;
                "${card_base}"-SPI-*|"${card_base}"-None-*|"${card_base}"-Unknown-*|"${card_base}"-DPI-*|*)
                    printf '/dev/dri/%s\n' "$card_base"
                    return 0
                    ;;
            esac
        done
    done
    printf '\n'
}

detect_vc4_card() {
    local conn_dir conn_base card_base
    for conn_dir in "$SYS_DRM_DIR"/card[0-9]*-HDMI-A-*; do
        [ -d "$conn_dir" ] || continue
        conn_base="$(basename "$conn_dir")"
        card_base="${conn_base%%-*}"
        if [ -n "$card_base" ]; then
            printf '/dev/dri/%s\n' "$card_base"
            return 0
        fi
    done

    if [ -e /dev/dri/card1 ]; then
        printf '/dev/dri/card1\n'
    else
        printf '/dev/dri/card0\n'
    fi
}

is_any_hdmi_connected() {
    local status_file
    for status_file in "$SYS_DRM_DIR"/card*-HDMI-A-*/status; do
        if [ -f "$status_file" ] && [ "$(cat "$status_file" 2>/dev/null | tr -d '[:space:]')" = "connected" ]; then
            return 0
        fi
    done
    return 1
}

write_lcd35_device_section() {
    local spi_fb="$1"
    local spi_card="$2"
    local has_fbdev="$3"
    local is_primary="${4:-0}"

    if [ -n "$spi_card" ]; then
        cat <<EOF
Section "Device"
    Identifier "LCD35_Device"
    Driver "modesetting"
    Option "kmsdev" "${spi_card}"
    Option "AccelMethod" "none"
    Option "SWcursor" "true"
EOF
        if [ "$is_primary" -eq 1 ]; then
            cat <<EOF
    Option "PrimaryGPU" "true"
EOF
        fi
        cat <<EOF
EndSection
EOF
    elif [ "$has_fbdev" -eq 1 ]; then
        cat <<EOF
Section "Device"
    Identifier "LCD35_Device"
    Driver "fbdev"
    Option "fbdev" "${spi_fb}"
EndSection
EOF
    else
        cat <<EOF
Section "Device"
    Identifier "LCD35_Device"
    Driver "fbdev"
    Option "fbdev" "${spi_fb}"
EndSection
EOF
    fi
}

main() {
    local action="${1:---no-restart}"
    local spi_fb spi_card vc4_card has_fbdev=0 hdmi_connected=0 target_mode prev_mode=""

    spi_fb="$(detect_spi_fb)"
    spi_card="$(detect_spi_card)"
    vc4_card="$(detect_vc4_card)"

    if detect_fbdev_driver; then
        has_fbdev=1
    fi

    if is_any_hdmi_connected; then
        hdmi_connected=1
        target_mode="multi"
    else
        hdmi_connected=0
        target_mode="single"
    fi

    if [ -f "$STATE_FILE" ]; then
        prev_mode="$(cat "$STATE_FILE" 2>/dev/null | tr -d '[:space:]')"
    fi
    if [ -z "$prev_mode" ] && [ -f "$XORG_CONF_OUT" ]; then
        if grep -q "LCD35_MultiLayout" "$XORG_CONF_OUT" 2>/dev/null; then
            prev_mode="multi"
        elif grep -q "LCD35_SingleLayout" "$XORG_CONF_OUT" 2>/dev/null; then
            prev_mode="single"
        fi
    fi

    mkdir -p "$(dirname "$XORG_CONF_OUT")"

    if [ "$hdmi_connected" -eq 0 ]; then
        {
            cat <<EOF
Section "ServerFlags"
    Option "AutoAddGPU" "false"
EndSection

EOF
            write_lcd35_device_section "$spi_fb" "$spi_card" "$has_fbdev" 1
            cat <<EOF

Section "Screen"
    Identifier "Screen_LCD35"
    Device "LCD35_Device"
EndSection

Section "ServerLayout"
    Identifier "LCD35_SingleLayout"
    Screen 0 "Screen_LCD35" 0 0
EndSection
EOF
        } > "$XORG_CONF_OUT"
    else
        {
            cat <<EOF
Section "ServerFlags"
    Option "AutoAddGPU" "false"
EndSection

Section "Device"
    Identifier "HDMI_Device"
    Driver "modesetting"
    Option "kmsdev" "${vc4_card}"
    Option "PrimaryGPU" "true"
EndSection

Section "Screen"
    Identifier "Screen_HDMI"
    Device "HDMI_Device"
EndSection

EOF
            write_lcd35_device_section "$spi_fb" "$spi_card" "$has_fbdev" 0
            cat <<EOF

Section "Screen"
    Identifier "Screen_LCD35"
    Device "LCD35_Device"
EndSection

Section "ServerLayout"
    Identifier "LCD35_MultiLayout"
    Screen 0 "Screen_HDMI" 0 0
    Screen 1 "Screen_LCD35" RightOf "Screen_HDMI"
EndSection
EOF
        } > "$XORG_CONF_OUT"
    fi

    mkdir -p "$(dirname "$STATE_FILE")"
    printf '%s\n' "$target_mode" > "$STATE_FILE"
    chmod 644 "$STATE_FILE" 2>/dev/null || true

    if [ "$action" = "--restart-x" ] && [ -n "$prev_mode" ] && [ "$prev_mode" != "$target_mode" ]; then
        touch "$RESTART_FLAG_FILE" 2>/dev/null || true
        chmod 666 "$RESTART_FLAG_FILE" 2>/dev/null || true
        if systemctl is-active --quiet lightdm 2>/dev/null; then
            systemctl restart lightdm 2>/dev/null || true
        else
            killall -TERM Xorg 2>/dev/null || pkill -TERM -x Xorg 2>/dev/null || true
        fi
    fi
}

main "$@"
