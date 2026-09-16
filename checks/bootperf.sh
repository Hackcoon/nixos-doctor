# boot-performance checks [U]
check_bootperf() {
    if have systemd-analyze; then
        if ! analyze=$(systemd-analyze 2>/dev/null); then
            finding_status ERROR bootperf bootperf.total system high "systemd-analyze failed" systemd-analyze "boot duration unavailable"
        else
            total=$(printf '%s\n' "$analyze" | grep -oE "in [0-9.]+s" | head -1 || true)
            [ -n "$total" ] && finding PASS bootperf "boot $total" || finding_status UNKNOWN bootperf bootperf.total system low "duration not parsed" systemd-analyze "boot duration format unrecognized"
        fi
        if ! blame=$(systemd-analyze blame --no-pager 2>/dev/null); then
            finding_status ERROR bootperf bootperf.blame system high "systemd-analyze blame failed" systemd-analyze "slow-unit analysis unavailable"
            return 0
        fi
        slow=$(printf '%s\n' "$blame" | awk '$1 ~ /^[0-9.]+s$/ && $1+0 > 5 && $2 !~ /\.device$/ {print $2}' | head -5)
        if [ -n "$slow" ]; then
            finding WARN bootperf "slow units: $(printf '%s' "$slow" | tr '\n' ' ')" "systemd-analyze critical-chain (mask/disable hints in TUI, never auto)"
        else
            finding PASS bootperf "no units slower than 5s"
        fi
    else
        finding_status SKIP bootperf bootperf.command system high "command not installed" systemd-analyze "boot performance checks unavailable"
    fi
    return 0
}
