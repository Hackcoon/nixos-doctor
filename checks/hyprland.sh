# hyprland checks [U] — skip cleanly when in mango sessions
check_hyprland() {
    [ "${NIXOS_DOCTOR_EXPECTED_COMPOSITOR:-auto}" = none ] && { finding SKIP hyprland "Hyprland checks disabled by profile"; return 0; }
    if ! pgrep -x Hyprland >/dev/null 2>&1 && [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        finding SKIP hyprland "Hyprland not running (mango session?)"
        return 0
    fi
    if ! have hyprctl; then
        finding FAIL hyprland "Hyprland runs but hyprctl missing" "check hyprland package install"
        return 0
    fi
    if hyprctl monitors -j 2>/dev/null | python3 -c "import json,sys; assert json.load(sys.stdin)" 2>/dev/null; then
        finding PASS hyprland "hyprctl IPC responsive"
    else
        finding FAIL hyprland "hyprctl IPC not responding" "echo \$HYPRLAND_INSTANCE_SIGNATURE; hyprctl version"
    fi
    for f in ~/.config/hypr/hyprland.lua ~/.config/hypr/binds.lua; do
        [ -f "$f" ] && finding PASS hyprland "$(basename "$f") present" || finding WARN hyprland "$f missing" "restore from backup/dotfiles"
    done
    # Optional quickshell-based shell in Hyprland sessions.
    # Accept any running quickshell shell; only warn when none is present.
    if shell=$(quickshell list --all 2>/dev/null | grep -o "quickshell/[^[:space:]]*" | head -1); then
        finding PASS hyprland "quickshell shell running ($shell)"
    else
        finding WARN hyprland "Hyprland runs without a quickshell shell" "quickshell -p ~/.config/quickshell/<your-shell> (manual)"
    fi
    # crash/error tail in hyprland log
    log=$(ls -t ~/.cache/hyprland/hyprland.log 2>/dev/null | head -1)
    if [ -n "$log" ] && [ -r "$log" ]; then
        if tail -50 "$log" 2>/dev/null | grep -qiE "error|critical|failed|crash"; then
            finding WARN hyprland "errors in recent hyprland log tail" "tail -50 $log"
        else
            finding PASS hyprland "hyprland log tail clean"
        fi
    fi
    return 0
}
