# kde/plasma checks [U] — session-aware like hyprland
check_kde() {
    if ! pgrep -x plasmashell >/dev/null 2>&1; then
        finding_status SKIP kde kde.session session high "plasmashell not running" plasmashell "no Plasma session"
    else
        finding PASS kde "plasmashell running"
        if ! user_bus_available; then
            finding_status SKIP kde kde.user_bus user high "user systemd manager unavailable" "systemctl,user-session" "Plasma user-unit state unavailable"
        else
            for u in "plasma-kactivitymanagerd.service" "plasma-dolphin.service"; do
                if systemctl --user is-active "$u" >/dev/null 2>&1; then
                    finding PASS kde "$u active"
                else
                    finding WARN kde "$u down in Plasma session" "systemctl --user restart $u"
                fi
            done
        fi
    fi
    # display-manager conflict: greetd (dms-greeter) and sddm must never
    # both own the seat (kde.nix gates sddm off when the greeter is on)
    greeter=$(systemctl is-enabled greetd 2>/dev/null); greeter_rc=$?
    sddm=$(systemctl is-enabled sddm 2>/dev/null); sddm_rc=$?
    if [ "$greeter_rc" -ne 0 ] && [ "$greeter" != disabled ] && [ "$greeter" != not-found ]; then
        finding_status ERROR kde kde.seat system high "display-manager query failed" systemctl "display-manager seat ownership unavailable"
    elif [ "$sddm_rc" -ne 0 ] && [ "$sddm" != disabled ] && [ "$sddm" != not-found ]; then
        finding_status ERROR kde kde.seat system high "display-manager query failed" systemctl "display-manager seat ownership unavailable"
    elif [ "$greeter" = "enabled" ] && [ "$sddm" = "enabled" ]; then
        finding FAIL kde "greetd AND sddm both enabled (seat fight)" "keep one: kde.nix already gates sddm off when greeter is on"
    else
        finding PASS kde "seat ownership sane (greetd=$greeter sddm=$sddm)"
    fi
    # baloo indexer (CPU/disk churn culprit) — binary name varies
    for b in balooctl balooctl6; do
        if have "$b"; then
            if ! st=$("$b" status 2>/dev/null); then
                finding_status ERROR kde kde.baloo user high "$b status failed" "$b,user-session" "Baloo state unavailable"
            elif printf '%s' "$st" | grep -qi "not running"; then
                finding PASS kde "baloo indexer idle"
            elif printf '%s' "$st" | grep -qE "Files waiting for content indexing: [1-9]"; then
                finding WARN kde "baloo indexer actively churning" "$b suspend / $b disable (Tier 1)"
            elif [ -n "$st" ]; then
                finding PASS kde "baloo indexer idle"
            else
                finding_status UNKNOWN kde kde.baloo user low "empty status output" "$b,user-session" "Baloo state unknown"
            fi
            break
        fi
    done
    # akonadi: only interesting when running-but-broken
    if pgrep -f akonadi >/dev/null 2>&1; then
        if ! have akonadictl; then
            finding_status SKIP kde kde.akonadi user high "command not installed" akonadictl "Akonadi state unavailable"
        elif ! akonadi_state=$(akonadictl status 2>/dev/null); then
            finding_status ERROR kde kde.akonadi user high "akonadictl status failed" akonadictl "Akonadi state unavailable"
        elif printf '%s\n' "$akonadi_state" | grep -qiE "stopped|not running"; then
            finding WARN kde "akonadi processes linger but server stopped" "akonadictl stop; restart on demand"
        elif [ -n "$akonadi_state" ]; then
            finding PASS kde "akonadi stack running"
        else
            finding_status UNKNOWN kde kde.akonadi user low "empty status output" akonadictl "Akonadi state unknown"
        fi
    fi
    # tie the crash flood to culprits (EXE field, basenamed)
    if have coredumpctl; then
        top=$(coredumpctl --no-pager --no-legend -F COREDUMP_EXE 2>/dev/null | sed 's|.*/||' | sort | uniq -c | sort -rn | head -3 | awk '{print $2" x"$1}' | tr '\n' ';')
        [ -n "$top" ] && finding WARN kde "top crashers: $top" "coredumpctl info <exe>; update/downgrade suspect"
    fi
    return 0
}
