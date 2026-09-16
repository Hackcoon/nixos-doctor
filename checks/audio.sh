# audio/bluetooth checks [U]
check_audio() {
    if ! user_bus_available; then
        finding_status SKIP audio audio.user_bus user high "user systemd manager unavailable" "systemctl,user-session" "user systemd session unavailable"
        return 0
    fi
    for u in "pipewire.service" "wireplumber.service" "pipewire-pulse.service"; do
        unit_state=$(systemctl --user show "$u" -p LoadState --value 2>/dev/null)
        unit_rc=$?
        if [ "$unit_rc" -ne 0 ]; then
            finding_status ERROR audio "audio.unit.$u" user high "systemctl unit query failed" "systemctl,user-session" "$u state unavailable"
            continue
        elif [ "$unit_state" = not-found ]; then
            finding_status SKIP audio "audio.unit.$u" user high "unit not installed" "systemctl,user-session" "$u not installed"
            continue
        fi
        if [ "$(systemctl --user is-active "$u" 2>/dev/null)" = "active" ]; then
            finding PASS audio "$u active"
        else
            finding_fix FAIL audio "$u not active" service_restart "systemctl --user restart $u" user "$u"
        fi
    done
    if have bluetoothctl; then
        if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
            finding PASS audio "bluetooth adapter powered"
        else
            finding WARN audio "no powered bluetooth adapter" "bluetoothctl power on; rfkill list"
        fi
        storms=$(journalctl -b --no-pager 2>/dev/null | grep -ciE "bluetooth.*(disconnect|failed|timeout)" || true)
        [ "${storms:-0}" -gt 15 ] && finding WARN audio "$storms bluetooth error lines" "journalctl -b | grep -i bluetooth | tail -20"
    fi
    return 0
}
