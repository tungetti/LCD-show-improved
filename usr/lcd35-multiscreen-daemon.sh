#!/bin/bash
# lcd35-multiscreen-daemon.sh
# Dynamically manages display priority between HDMI-1, HDMI-2, and the 3.5" SPI LCD:
# - 0 HDMI connected: 3.5" LCD is 1st (primary) screen at 0x0
# - 1 HDMI connected: HDMI-1 is 1st (primary) screen, 3.5" LCD is 2nd screen (right-of HDMI-1)
# - 2 HDMI connected: HDMI-1 is 1st, HDMI-2 is 2nd, 3.5" LCD is 3rd screen (right-of HDMI-2)
# When 1 or 2 HDMI cables are unplugged, automatically turns off the disconnected HDMI output(s)
# and pulls the 3.5" LCD back to 2nd screen or 1st (primary) main screen at 0x0.
# Also maps the ADS7846 resistive touchscreen to the 3.5" LCD output via xinput.

set -u

SYS_DRM_DIR="${SYS_DRM_DIR:-/sys/class/drm}"

wait_for_display_server() {
    local i
    for i in $(seq 1 15); do
        if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wlr-randr >/dev/null 2>&1; then
            if wlr-randr >/dev/null 2>&1; then
                return 0
            fi
        fi
        if command -v xrandr >/dev/null 2>&1; then
            if xrandr --query >/dev/null 2>&1; then
                return 0
            fi
        fi
        sleep 1
    done
    return 1
}

# Cross-check kernel DRM connector status so an unplugged HDMI cable is treated as
# disconnected immediately even if Xorg/Wayland caches a stale "connected" state.
is_hdmi_drm_disconnected() {
    local out_name="$1"
    local idx="${out_name##*-}"
    local found_any=0
    local status_file status_val

    for status_file in "$SYS_DRM_DIR"/card*-HDMI-A-"${idx}"/status; do
        if [ -f "$status_file" ]; then
            found_any=1
            status_val="$(cat "$status_file" 2>/dev/null | tr -d '[:space:]')"
            if [ "$status_val" = "connected" ]; then
                return 1
            fi
        fi
    done

    if [ "$found_any" -eq 1 ]; then
        return 0
    fi
    return 1
}

apply_x11_layout() {
    command -v xrandr >/dev/null 2>&1 || return 0

    local providers_out
    providers_out="$(xrandr --listproviders 2>/dev/null || true)"
    local num_providers
    num_providers="$(printf '%s\n' "$providers_out" | awk -F'number : ' '/Providers: number :/ {print $2}' | tr -d '[:space:]')"
    if [ -n "$num_providers" ] && [ "$num_providers" -ge 2 ] 2>/dev/null && printf '%s\n' "$providers_out" | grep -q "associated providers: 0"; then
        local prov_id
        for prov_id in $(printf '%s\n' "$providers_out" | awk '/^Provider [1-9][0-9]*:/ {sub(/:/, "", $2); print $2}'); do
            xrandr --setprovideroutputsource "$prov_id" 0 2>/dev/null || \
                xrandr --setprovideroutputsource 0 "$prov_id" 2>/dev/null || true
        done
    fi

    # Call xrandr without --query/--current so Xorg actively re-probes DRM connectors on hotplug/unplug
    local xrandr_out
    xrandr_out="$(xrandr 2>/dev/null || true)"
    [ -z "$xrandr_out" ] && return 0

    local -a connected_hdmis=()
    local -a disconnected_hdmis=()
    local out state

    while IFS=' ' read -r out state; do
        [ -z "$out" ] && continue
        if [ "$state" = "connected" ] && ! is_hdmi_drm_disconnected "$out"; then
            connected_hdmis+=("$out")
        else
            disconnected_hdmis+=("$out")
        fi
    done < <(printf '%s\n' "$xrandr_out" | awk '/^HDMI-[A-Z0-9-]+ (connected|disconnected)/ {print $1, $2}' | sort -V -k1,1)

    local spi_out=""
    spi_out="$(printf '%s\n' "$xrandr_out" | awk '/^(SPI|None|Unknown|DPI|DSI)-[A-Za-z0-9-]+ connected/ {print $1; exit}')"
    if [ -z "$spi_out" ]; then
        spi_out="$(printf '%s\n' "$xrandr_out" | awk '/ connected/ && $1 !~ /^(HDMI|Composite)-[A-Za-z0-9-]+$/ {print $1; exit}')"
    fi

    local hdmi_count="${#connected_hdmis[@]}"
    local -a xrandr_args=()
    local dis_hdmi

    for dis_hdmi in "${disconnected_hdmis[@]}"; do
        xrandr_args+=(--output "$dis_hdmi" --off)
    done

    if [ "$hdmi_count" -eq 0 ]; then
        if [ -n "$spi_out" ]; then
            xrandr_args+=(--output "$spi_out" --auto --primary --pos 0x0)
        fi
    elif [ "$hdmi_count" -eq 1 ]; then
        local hdmi1="${connected_hdmis[0]}"
        xrandr_args+=(--output "$hdmi1" --auto --primary --pos 0x0)
        if [ -n "$spi_out" ]; then
            xrandr_args+=(--output "$spi_out" --auto --right-of "$hdmi1")
        fi
    else
        local hdmi1="${connected_hdmis[0]}"
        local hdmi2="${connected_hdmis[1]}"
        xrandr_args+=(--output "$hdmi1" --auto --primary --pos 0x0 --output "$hdmi2" --auto --right-of "$hdmi1")
        local prev_hdmi="$hdmi2"
        local idx
        for (( idx=2; idx<hdmi_count; idx++ )); do
            xrandr_args+=(--output "${connected_hdmis[$idx]}" --auto --right-of "$prev_hdmi")
            prev_hdmi="${connected_hdmis[$idx]}"
        done
        if [ -n "$spi_out" ]; then
            xrandr_args+=(--output "$spi_out" --auto --right-of "$prev_hdmi")
        fi
    fi

    if [ "${#xrandr_args[@]}" -gt 0 ] && { [ "$hdmi_count" -gt 0 ] || [ -n "$spi_out" ]; }; then
        xrandr "${xrandr_args[@]}" 2>/dev/null || true
        if command -v lxpanelctl >/dev/null 2>&1 && pgrep -x lxpanel >/dev/null 2>&1; then
            lxpanelctl restart >/dev/null 2>&1 || true
        fi
    fi

    if [ -n "$spi_out" ] && command -v xinput >/dev/null 2>&1; then
        local id
        for id in $(
            {
                xinput list --id-only "ADS7846 Touchscreen" 2>/dev/null
                xinput list --id-only "pointer:ADS7846 Touchscreen" 2>/dev/null
                xinput list 2>/dev/null | grep -i "ADS7846" | grep -v "master" | sed -n 's/.*id=\([0-9][0-9]*\).*/\1/p'
            } | sort -u
        ); do
            if [ -n "$id" ]; then
                xinput map-to-output "$id" "$spi_out" 2>/dev/null || true
            fi
        done
    fi
}

apply_wayland_layout() {
    command -v wlr-randr >/dev/null 2>&1 || return 0

    local wlr_out
    wlr_out="$(wlr-randr 2>/dev/null || true)"
    [ -z "$wlr_out" ] && return 0

    local -a connected_hdmis=()
    local -a disconnected_hdmis=()
    local out
    while IFS= read -r out; do
        [ -z "$out" ] && continue
        if is_hdmi_drm_disconnected "$out"; then
            disconnected_hdmis+=("$out")
        else
            connected_hdmis+=("$out")
        fi
    done < <(printf '%s\n' "$wlr_out" | awk '/^HDMI-[A-Z0-9-]+/ {print $1}' | sort -V)

    local dis_hdmi
    for dis_hdmi in "${disconnected_hdmis[@]}"; do
        wlr-randr --output "$dis_hdmi" --off 2>/dev/null || true
    done

    local spi_out=""
    spi_out="$(printf '%s\n' "$wlr_out" | awk '/^(SPI|DPI|DSI|None|Unknown)-[A-Za-z0-9-]+/ {print $1; exit}')"
    if [ -z "$spi_out" ]; then
        spi_out="$(printf '%s\n' "$wlr_out" | awk '/^[^[:space:]]/ && $1 !~ /^(HDMI|Composite)-[A-Za-z0-9-]+$/ {print $1; exit}')"
    fi

    local x_offset=0
    local hdmi width
    for hdmi in "${connected_hdmis[@]}"; do
        wlr-randr --output "$hdmi" --on --pos "${x_offset},0" 2>/dev/null || true
        width="$(printf '%s\n' "$wlr_out" | awk -v target="$hdmi" '
            $1 == target { in_block=1; next }
            /^[^[:space:]]/ { in_block=0 }
            in_block && /current/ && match($1, /^[0-9]+x[0-9]+/) {
                split($1, dims, "x"); print dims[1]; exit
            }
        ')"
        if [ -z "$width" ] || ! [ "$width" -gt 0 ] 2>/dev/null; then
            width=1920
        fi
        x_offset=$((x_offset + width))
    done

    if [ -n "$spi_out" ]; then
        wlr-randr --output "$spi_out" --on --pos "${x_offset},0" 2>/dev/null || true
    fi
}

get_state_signature() {
    local drm_state=""
    local status_file
    for status_file in "$SYS_DRM_DIR"/card*-HDMI-A-*/status; do
        if [ -f "$status_file" ]; then
            drm_state="${drm_state}${status_file}:$(cat "$status_file" 2>/dev/null);"
        fi
    done

    local disp_state=""
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wlr-randr >/dev/null 2>&1; then
        disp_state="$(wlr-randr 2>/dev/null | awk '/^[^[:space:]]/ {print $1}' | tr '\n' ',')"
    elif command -v xrandr >/dev/null 2>&1; then
        disp_state="$(xrandr --query 2>/dev/null | grep " connected" | awk '{print $1}' | tr '\n' ',')"
    fi

    printf '%s|%s\n' "$drm_state" "$disp_state"
}

main() {
    wait_for_display_server || true

    local last_signature=""
    local current_signature=""

    while true; do
        current_signature="$(get_state_signature)"
        if [ "$current_signature" != "$last_signature" ]; then
            sleep 1
            if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wlr-randr >/dev/null 2>&1; then
                apply_wayland_layout
            else
                apply_x11_layout
            fi
            last_signature="$(get_state_signature)"
        fi
        sleep 2
    done
}

main "$@"
