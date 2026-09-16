# Nix/flake/rebuild correlation checks [U, deep optional]
check_nix() {
    root="${NIXOS_DOCTOR_FLAKE_ROOT:-/etc/nixos}"
    if ! have nix; then
        finding_status SKIP nix nix.command system high "command not installed" nix "Nix diagnostics unavailable"
        return 0
    fi
    if [ ! -f "$root/flake.nix" ]; then
        finding_status SKIP nix nix.flake system high "flake.nix not present" "$root/flake.nix" "flake correlation not applicable"
    else
        if have git && [ -d "$root/.git" ]; then
            if ! revision=$(git -C "$root" rev-parse --short HEAD 2>/dev/null); then
                finding_status ERROR nix nix.revision system high "git revision query failed" git "configuration revision unavailable"
            else
                finding PASS nix "flake revision $revision"
            fi
            if ! status=$(git -C "$root" status --porcelain 2>/dev/null); then
                finding_status ERROR nix nix.dirty system high "git status query failed" git "flake dirty state unavailable"
            elif [ -n "$status" ]; then
                finding WARN nix "flake tree has uncommitted changes" "git -C $root status --short"
            else
                finding PASS nix "flake tree clean"
            fi
        else
            finding_status SKIP nix nix.revision system high "Git repository unavailable" git "flake revision correlation unavailable"
        fi
        if [ -f "$root/flake.lock" ]; then
            if ! lock_info=$(nix flake metadata --json "$root" 2>/dev/null); then
                finding_status ERROR nix nix.metadata system high "nix flake metadata failed" nix "flake metadata unavailable"
            else
                lock_rev=$(printf '%s' "$lock_info" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("revision", "unknown"))' 2>/dev/null || true)
                [ -n "$lock_rev" ] && finding PASS nix "flake metadata revision ${lock_rev:0:16}"
            fi
        else
            finding_status SKIP nix nix.lock system high "flake.lock not present" "$root/flake.lock" "lock correlation not applicable"
        fi
        if [ "$DEEP" = 1 ]; then
            if ! flake_check=$(nix flake check --no-build "$root" 2>&1); then
                finding_status ERROR nix nix.flake_check system high "nix flake check failed" "nix,flake" "flake validation failed"
            else
                finding_observed PASS nix nix.flake_check system high "read-only flake check succeeded" "nix,flake" "flake validation passed" "nix flake check --no-build $root" 0 "$flake_check" nix
            fi
        else
            finding_status SKIP nix nix.flake_check system high "deep mode not enabled" "--deep,nix" "flake validation skipped"
        fi
    fi

    booted=$(readlink -f /run/booted-system 2>/dev/null || true)
    current=$(readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)
    if [ -n "$booted" ] && [ -n "$current" ]; then
        if [ "$booted" = "$current" ]; then
            finding PASS nix "booted generation matches current profile"
        else
            finding WARN nix "booted generation differs from current profile" "reboot to boot current generation, or review rollback state"
        fi
    else
        finding_status UNKNOWN nix nix.generation system medium "generation links unavailable" readlink "booted/current generation correlation unknown"
    fi
    for artifact in kernel initrd; do
        booted_artifact=$(readlink -f "/run/booted-system/$artifact" 2>/dev/null || true)
        current_artifact=$(readlink -f "/nix/var/nix/profiles/system/$artifact" 2>/dev/null || true)
        if [ -n "$booted_artifact" ] && [ -n "$current_artifact" ]; then
            [ "$booted_artifact" = "$current_artifact" ] && finding PASS nix "booted $artifact matches current profile" || finding WARN nix "booted $artifact differs from current profile"
        else
            finding_status UNKNOWN nix "nix.$artifact" system medium "$artifact link unavailable" readlink "booted/current $artifact correlation unknown"
        fi
    done
    if have systemctl; then
        if systemctl is-active nix-daemon.service >/dev/null 2>&1 || systemctl is-active nix-daemon.socket >/dev/null 2>&1; then
            finding PASS nix "Nix daemon active"
        else
            finding WARN nix "Nix daemon service/socket not active"
        fi
    fi
    if [ -e /nix/var/nix/db/big-lock ]; then
        if have fuser && fuser /nix/var/nix/db/big-lock >/dev/null 2>&1; then
            finding WARN nix "Nix database lock is held" "inspect the active Nix build before rebuilding"
        else
            finding PASS nix "Nix database lock not held"
        fi
    else
        finding_status SKIP nix nix.db_lock system high "lock path absent" /nix/var/nix/db/big-lock "Nix database lock check not applicable"
    fi
    return 0
}
