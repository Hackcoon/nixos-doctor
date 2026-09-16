# services checks [U]
check_services() {
    # NOTE: unquoted $scope is intentional (empty string or one flag).
    for scope in "" "--user"; do
        label="system"; [ -n "$scope" ] && label="user"
        if [ -n "$scope" ] && ! user_bus_available; then
            finding_status SKIP services services.user_bus user high "user systemd manager unavailable" "systemctl,user-session" "user systemd manager unavailable"
            continue
        fi
        if [ -n "$scope" ]; then
            if ! failed_out=$(systemctl --user --failed --no-legend --plain 2>/dev/null); then
                finding_status ERROR services services.failed_units user high "systemctl query failed" "systemctl,user-session" "failed user units could not be read"
                continue
            fi
        elif ! failed_out=$(systemctl --failed --no-legend --plain 2>/dev/null); then
            finding_status ERROR services services.failed_units system high "systemctl query failed" systemctl "failed system units could not be read"
            continue
        fi
        units=$(printf '%s\n' "$failed_out" | grep -oE '[A-Za-z0-9_@:.~-]+\.(service|socket|target|timer|scope|mount|slice|path)' | sed -E 's/@[^.]+\./@./' | sort | uniq -c | sort -rn || true)
        if [ -z "$units" ]; then
            finding PASS services "no failed $label units"
        else
            while read -r count name; do
                [ -z "$name" ] && continue
                case "$name" in
                    *@*)
                        if [ -n "$scope" ]; then
                            finding_fix FAIL services "failed $label: $name ×$count (transient instances)" service_reset_failed "systemctl --user reset-failed $name" user "$name"
                        else
                            finding_fix FAIL services "failed $label: $name ×$count (transient instances)" service_reset_failed "systemctl reset-failed $name" system "$name"
                        fi ;;
                    *)
                        if [ -n "$scope" ]; then
                            finding_fix FAIL services "failed $label unit: $name" service_restart "systemctl --user restart $name" user "$name"
                        else
                            finding_fix FAIL services "failed $label unit: $name" service_restart "systemctl restart $name" system "$name"
                        fi ;;
                esac
            done <<<"$units"
        fi
    done
    if ! st=$(systemctl is-system-running 2>/dev/null); then
        case "$st" in
            degraded) finding WARN services "system state: degraded (see failed units above)" "systemctl --failed" ;;
            *) finding_status ERROR services services.system_state system high "systemctl query failed or state=$st" systemctl "system manager state unavailable" ;;
        esac
    elif [ "$st" = running ]; then
        finding PASS services "system state: running"
    else
        finding_status UNKNOWN services services.system_state system medium "unrecognized state=$st" systemctl "system state: $st"
    fi
    # DMS-specific stack is handled by the dms area; only inspect it when a
    # matching user unit is actually installed.
    u="mango-session.target:--user"
    unit="${u%%:*}"; scope="${u##*:}"
    if systemctl --user list-unit-files "$unit" >/dev/null 2>&1; then
        active=$(systemctl --user is-active "$unit" 2>/dev/null || true)
        if [ "$active" = active ]; then
            finding PASS services "$unit active"
        else
            finding_fix WARN services "$unit not active" service_restart "systemctl --user restart $unit" user "$unit"
        fi
    fi
    # failed timers, listed separately (unit names alone don't say which kind failed)
    for scope in "" "--user"; do
        label="system"; [ -n "$scope" ] && label="user"
        # shellcheck disable=SC2086
        ft=$(systemctl $scope --failed --type=timer --no-legend --plain 2>/dev/null | grep -oE '[A-Za-z0-9_@:.~-]+\.timer' | sort -u | tr '\n' ' ')
        [ -n "$ft" ] && finding WARN services "failed $label timers: $ft" "systemctl$([ -n "$scope" ] && printf ' --user') status <timer>"
    done
    # timers that missed runs
    if systemctl list-timers --no-legend 2>/dev/null | grep -q .; then
        finding PASS services "timers enumerated (missed-run detection in TUI)"
    fi
}
