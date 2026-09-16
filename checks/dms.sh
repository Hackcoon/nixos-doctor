# DankMaterialShell checks [U]
check_dms() {
    if ! have dms; then
        finding_status SKIP dms dms.cli session high "command not installed" dms "DMS CLI not installed"
        return 0
    fi
    if ! have python3; then
        finding_status SKIP dms dms.parser session high "command not installed" python3 "DMS checks require python3"
        return 0
    fi
    if ! user_bus_available; then
        finding_status SKIP dms dms.user_bus user high "user systemd manager unavailable" "systemctl,user-session" "user systemd session unavailable; DMS service state unavailable"
    fi
    report=$(dms doctor --json 2>/dev/null) || {
        finding_status ERROR dms dms.doctor session high "dms doctor exited nonzero" dms "dms doctor failed; inspect with: dms doctor --verbose"
        return 0
    }
    if ! printf '%s' "$report" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
        finding_status ERROR dms dms.json session high "invalid JSON output" "dms,python3" "dms doctor returned invalid JSON"
        return 0
    fi
    while IFS=$'\t' read -r status category name message details url; do
        [ -n "$name" ] || continue
        text="$category/$name: $message"
        [ -n "$details" ] && text="$text ($details)"
        [ -n "$url" ] && text="$text [$url]"
        case "$status" in
            ok) finding PASS dms "$text" ;;
            warn) finding WARN dms "$text" "dms doctor --verbose" ;;
            error|fail) finding FAIL dms "$text" "dms doctor --verbose" ;;
            *) finding SKIP dms "$text" ;;
        esac
    done < <(printf '%s' "$report" | python3 -c '
import json, sys
for item in json.load(sys.stdin).get("results", []):
    values = [item.get(k, "") for k in ("status", "category", "name", "message", "details", "url")]
    print("\t".join(str(v).replace("\t", " ").replace("\n", " ") for v in values))')
    return 0
}
