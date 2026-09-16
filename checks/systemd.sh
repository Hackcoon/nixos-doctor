# systemd manager diagnostics [U]
systemd_unit_name() {
    [[ "$1" =~ ^[A-Za-z0-9_@:.~-]+\.(service|socket|target|timer|scope|mount|slice|path)$ ]]
}

systemd_report_units() {
    local scope="$1" label="$2" failed unit props active result restarts
    if [ "$scope" = user ]; then
        if ! failed=$(systemctl --user --failed --type=service --no-legend --plain 2>/dev/null); then
            finding_observed ERROR systemd "systemd.${scope}.failed_units" user high "failed-unit query failed" "systemctl,user-session" "failed user units unavailable" "systemctl --user --failed --type=service" 1 "$failed" user-systemd
            return 0
        fi
    elif ! failed=$(systemctl --failed --type=service --no-legend --plain 2>/dev/null); then
        finding_observed ERROR systemd "systemd.${scope}.failed_units" system high "failed-unit query failed" systemctl "failed system units unavailable" "systemctl --failed --type=service" 1 "$failed" system-systemd
        return 0
    fi
    if [ -z "$failed" ]; then
        if [ "$scope" = user ]; then
            query_command="systemctl --user --failed --type=service"
        else
            query_command="systemctl --failed --type=service"
        fi
        finding_observed PASS systemd "systemd.${scope}.failed_units" "$scope" high "query succeeded with no failed units" systemctl "no failed $label service units" "$query_command" 0 "$failed" "$scope-systemd"
        return 0
    fi
    while read -r unit rest; do
        systemd_unit_name "$unit" || continue
        if [ "$scope" = user ]; then
            props=$(systemctl --user show "$unit" -p LoadState -p ActiveState -p SubState -p Result -p NRestarts 2>/dev/null) || props=""
        else
            props=$(systemctl show "$unit" -p LoadState -p ActiveState -p SubState -p Result -p NRestarts 2>/dev/null) || props=""
        fi
        active=$(printf '%s\n' "$props" | awk -F= '$1=="ActiveState" {print $2}')
        result=$(printf '%s\n' "$props" | awk -F= '$1=="Result" {print $2}')
        restarts=$(printf '%s\n' "$props" | awk -F= '$1=="NRestarts" {print $2}')
        [ -n "$active" ] || active=unknown
        [ -n "$result" ] || result=unknown
        [ -n "$restarts" ] || restarts=unknown
        if [ "$scope" = user ]; then
            finding_fix FAIL systemd "failed $label unit $unit (state=$active result=$result restarts=$restarts)" service_restart "systemctl --user restart $unit" user "$unit"
        else
            finding_fix FAIL systemd "failed $label unit $unit (state=$active result=$result restarts=$restarts)" service_restart "systemctl restart $unit" system "$unit"
        fi
    done <<<"$failed"
}

systemd_report_jobs() {
    local scope="$1" jobs
    if [ "$scope" = user ]; then
        jobs=$(systemctl --user list-jobs --no-legend 2>/dev/null) || {
            finding_status ERROR systemd systemd.user.jobs user high "job query failed" "systemctl,user-session" "user systemd jobs unavailable"
            return 0
        }
    else
        jobs=$(systemctl list-jobs --no-legend 2>/dev/null) || {
            finding_status ERROR systemd systemd.system.jobs system high "job query failed" systemctl "systemd jobs unavailable"
            return 0
        }
    fi
    if [ -z "$jobs" ]; then
        finding PASS systemd "no queued $scope systemd jobs"
    else
        finding WARN systemd "$scope systemd jobs present: $(printf '%s\n' "$jobs" | awk '{print $1}' | tr '\n' ' ')" "systemctl list-jobs"
    fi
}

check_systemd() {
    if ! have systemctl; then
        finding_status SKIP systemd systemd.command system high "command not installed" systemctl "systemd diagnostics unavailable"
        return 0
    fi

    if ! state=$(systemctl is-system-running 2>/dev/null); then
        finding_status ERROR systemd systemd.system_state system high "system manager query failed" systemctl "systemd state unavailable"
    elif [ "$state" = running ]; then
        finding_observed PASS systemd systemd.system_state system high "query succeeded" systemctl "system manager running" "systemctl is-system-running" 0 "$state" system-systemd
    elif [ "$state" = degraded ]; then
        finding WARN systemd "system manager degraded" "systemctl --failed"
    else
        finding_status UNKNOWN systemd systemd.system_state system medium "unrecognized state=$state" systemctl "system manager state: $state"
    fi
    systemd_report_units system system
    systemd_report_jobs system

    if user_bus_available; then
        if ! user_state=$(systemctl --user is-system-running 2>/dev/null); then
            finding_status ERROR systemd systemd.user_state user high "user manager query failed" "systemctl,user-session" "user systemd state unavailable"
        elif [ "$user_state" = running ]; then
        finding_observed PASS systemd systemd.user_state user high "query succeeded" "systemctl,user-session" "user systemd manager running" "systemctl --user is-system-running" 0 "$user_state" user-systemd
        elif [ "$user_state" = degraded ]; then
            finding WARN systemd "user systemd manager degraded" "systemctl --user --failed"
        else
            finding_status UNKNOWN systemd systemd.user_state user medium "unrecognized state=$user_state" "systemctl,user-session" "user manager state: $user_state"
        fi
        systemd_report_units user user
        systemd_report_jobs user
    else
        finding_status SKIP systemd systemd.user_manager user high "user systemd manager unavailable" "systemctl,user-session" "user systemd diagnostics not applicable"
    fi

    for scope in system user; do
        if [ "$scope" = user ]; then
            user_bus_available || continue
            timers=$(systemctl --user list-timers --all --no-legend --no-pager 2>/dev/null) || {
                finding_status ERROR systemd systemd.user.timers user high "timer query failed" "systemctl,user-session" "user timer state unavailable"
                continue
            }
        else
            timers=$(systemctl list-timers --all --no-legend --no-pager 2>/dev/null) || {
                finding_status ERROR systemd systemd.system.timers system high "timer query failed" systemctl "system timer state unavailable"
                continue
            }
        fi
        if [ -z "$timers" ]; then
            finding PASS systemd "no $scope timers listed"
        else
            waiting=$(printf '%s\n' "$timers" | awk '$1 == "-" {count++} END {print count+0}')
            if [ "$waiting" -gt 0 ]; then
                finding WARN systemd "$scope timer(s) have no recorded next/last run: $waiting" "systemctl${scope:+ --user} list-timers --all"
            else
                finding PASS systemd "$scope timers listed with schedule data"
            fi
        fi
    done

    for unit in systemd-oomd.service earlyoom.service; do
        if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
            state=$(systemctl is-active "$unit" 2>/dev/null || true)
            [ "$state" = active ] && finding PASS systemd "$unit active" || finding WARN systemd "$unit installed but not active"
        fi
    done

    if [ "$DEEP" = 1 ] && have systemd-analyze; then
        if ! analyze_time=$(systemd-analyze time 2>/dev/null); then
            finding_status ERROR systemd systemd.boot_time system high "systemd-analyze time failed" systemd-analyze "boot timing unavailable"
        else
            finding PASS systemd "boot timing: $analyze_time"
        fi
        if ! blame=$(systemd-analyze blame --no-pager 2>/dev/null); then
            finding_status ERROR systemd systemd.blame system high "systemd-analyze blame failed" systemd-analyze "slow-unit analysis unavailable"
        else
            slow=$(printf '%s\n' "$blame" | awk '$1 ~ /^[0-9.]+s$/ && $1+0 >= 5 && $2 !~ /\.device$/ {print $1" "$2}' | head -5)
            [ -n "$slow" ] && finding WARN systemd "slow boot units: $(printf '%s' "$slow" | tr '\n' ' ')" "systemd-analyze critical-chain" || finding PASS systemd "no non-device boot units at or above 5s"
        fi
        if ! systemd-analyze critical-chain --no-pager >/dev/null 2>&1; then
            finding_status ERROR systemd systemd.critical_chain system high "critical-chain query failed" systemd-analyze "boot dependency chain unavailable"
        else
            finding PASS systemd "critical boot dependency chain available"
        fi
    else
        finding SKIP systemd systemd.boot_analysis system high "deep mode not enabled or systemd-analyze missing" "--deep,systemd-analyze" "boot timing analysis skipped"
    fi
    return 0
}
