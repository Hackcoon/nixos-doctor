# power/suspend checks [U/R]
check_power() {
    if have powerprofilesctl; then
        if ! profile=$(powerprofilesctl get 2>/dev/null); then
            finding_status ERROR power power.profile system high "powerprofilesctl query failed" powerprofilesctl "active power profile unavailable"
        elif [ -z "$profile" ]; then
            finding_status UNKNOWN power power.profile system low "empty profile output" powerprofilesctl "active power profile unknown"
        else
            finding PASS power "active profile: $profile"
        fi
    else
        finding_status SKIP power power.profile system high "command not installed" powerprofilesctl "power profile check unavailable"
    fi
    if [ -e /sys/power/mem_sleep ]; then
        mode=$(cat /sys/power/mem_sleep 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
        [ -n "$mode" ] && finding PASS power "suspend mode: $mode"
    fi
    # zram helps with memory pressure but cannot hold a hibernation image.
    if ! have swapon; then
        finding_status SKIP power power.swap system high "command not installed" swapon "hibernate backing-store check unavailable"
    elif ! swap_out=$(swapon --show --noheadings 2>/dev/null); then
        finding_status ERROR power power.swap system high "swapon query failed" swapon "swap state unavailable"
    elif printf '%s\n' "$swap_out" | grep -v '/dev/zram' | grep -q .; then
        finding PASS power "persistent swap present for hibernate"
    elif [ -e /dev/zram0 ] || [ -n "$swap_out" ]; then
        finding WARN power "zram-only swap cannot back hibernate" "configure a persistent swap device and resumeDevice"
    else
        finding WARN power "no swap/zram found — hibernate would fail" "zramSwap.enable=true or swapDevices in /etc/nixos"
    fi
    if journalctl -b --no-pager 2>/dev/null | grep -qiE "suspend.*fail|resume.*fail|PM:.*error"; then
        finding WARN power "suspend/resume errors this boot" "journalctl -b | grep -iE 'suspend|resume' | tail -20"
    fi
    if lsmod 2>/dev/null | grep -q "^nvidia"; then
        if systemctl list-unit-files "nvidia-suspend.service" 2>/dev/null | grep -q enabled; then
            finding PASS power "nvidia-suspend hook enabled"
        else
            finding WARN power "nvidia-suspend hook not enabled (resume may lose displays)" "hardware.nvidia.powerManagement.enable=true"
        fi
    fi
    return 0
}
