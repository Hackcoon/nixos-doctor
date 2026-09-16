# updates checks [U]
check_updates() {
    flake_root="${NIXOS_DOCTOR_FLAKE_ROOT:-/etc/nixos}"
    if [ -f "$flake_root/flake.lock" ]; then
        if ! lock_mtime=$(stat -c %Y "$flake_root/flake.lock" 2>/dev/null); then
            finding_status ERROR updates updates.lock_age system high "stat failed" stat "flake.lock age unavailable"
            lock_mtime=""
        fi
        [ -n "$lock_mtime" ] && age_days=$(( ( $(date +%s) - lock_mtime ) / 86400 ))
        if [ -n "${age_days:-}" ] && [ "$age_days" -gt 90 ]; then
            finding WARN updates "flake inputs ${age_days}d old (kernel CVEs accumulate)" "nix flake update (Tier 2) + rebuild"
        elif [ -n "${age_days:-}" ]; then
            finding PASS updates "flake.lock ${age_days}d old"
        fi
    else
        finding_status SKIP updates updates.lock_age system high "flake.lock not present" "$flake_root/flake.lock" "flake input age check not applicable"
    fi
    if [ -e /run/booted-system/kernel ] && [ -e /nix/var/nix/profiles/system/kernel ]; then
        [ "$(readlink /run/booted-system/kernel 2>/dev/null)" = "$(readlink /nix/var/nix/profiles/system/kernel 2>/dev/null)" ] || finding WARN updates "new kernel staged but not booted" "reboot"
    fi
    if have fwupdmgr; then
        finding SKIP updates "firmware catalog (manual: fwupdmgr get-updates)"
    else
        finding_status SKIP updates updates.firmware hardware high "command not installed" fwupdmgr "firmware update check unavailable"
    fi
    return 0
}
