# flake/config checks [U]
check_flake() {
    flake_root="${NIXOS_DOCTOR_FLAKE_ROOT:-/etc/nixos}"
    if [ -d "$flake_root/.git" ]; then
        git_status_ok=0
        if ! git_status=$(git -C "$flake_root" status --porcelain 2>/dev/null); then
            finding_status ERROR flake flake.git system high "git status failed" git "$flake_root status could not be read"
        else
            git_status_ok=1
            dirty=$(printf '%s\n' "$git_status" | head -8)
        fi
        if [ -n "${dirty:-}" ]; then
            finding WARN flake "$flake_root has uncommitted changes" "git -C $flake_root status --short"
        elif [ "$git_status_ok" = 1 ]; then
            finding PASS flake "/etc/nixos tree clean"
        fi
    fi
    if [ -f "$flake_root/flake.lock" ]; then
        age_days=$(( ( $(date +%s) - $(stat -c %Y "$flake_root/flake.lock") ) / 86400 ))
        [ "$age_days" -gt 60 ] && finding WARN flake "flake.lock ${age_days}d old" "nix flake update (Tier 2, rebuild after)" || finding PASS flake "flake.lock ${age_days}d old"
    fi
    if nix-channel --list 2>/dev/null | grep -q .; then
        finding WARN flake "legacy nix-channels set alongside flakes" "nix-channel --list (remove if unused: nix-channel --remove)"
    fi
    if grep -rq "system.autoUpgrade.enable = true" "$flake_root/" 2>/dev/null; then
        finding PASS flake "system.autoUpgrade enabled"
    else
        finding WARN flake "autoUpgrade off — updates are manual" "services: system.autoUpgrade.enable"
    fi
    if have nh; then
        finding PASS flake "nh helper present"
        grep -rq "nh\.clean\|programs\.nh" "$flake_root/" 2>/dev/null && finding PASS flake "nh housekeeping configured"
    fi
    return 0
}
