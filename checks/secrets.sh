# secrets-metadata checks [R for stat; never reads contents]
check_secrets() {
    config_root="${NIXOS_DOCTOR_FLAKE_ROOT:-/etc/nixos}"
    if [ ! -d "$config_root" ]; then
        finding_status SKIP secrets secrets.references system high "configuration root absent" "$config_root" "secret reference scan not applicable"
        return 0
    fi
    grep_out=$(grep -rhoE "/var/lib/[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]*env[A-Za-z0-9_./-]*" "$config_root" 2>/dev/null)
    grep_rc=$?
    if [ "$grep_rc" -ne 0 ]; then
        if [ "$grep_rc" -gt 1 ]; then
            finding_status ERROR secrets secrets.references system high "configuration scan failed" grep "secret references could not be scanned"
            return 0
        fi
        grep_out=""
    fi
    refs=$(printf '%s\n' "$grep_out" | sort -u | head -5)
    if [ -z "$refs" ]; then
        finding SKIP secrets "no secret file references found in modules"
        return 0
    fi
    need_root secrets "secret file permission audit" || return 0
    for f in $refs; do
        if [ ! -e "$f" ]; then
            finding FAIL secrets "referenced secret missing: $f" "create it (0600) per module comment"
        else
            if ! mode=$(sudo -n stat -c %a "$f" 2>/dev/null); then
                finding_status ERROR secrets secrets.permissions system high "stat failed for $f" "stat,root" "secret permissions could not be read: $f"
                continue
            fi
            case "$mode" in
                600|400) finding PASS secrets "$f present, perms $mode" ;;
                *) finding FAIL secrets "$f perms $mode (must be 600/400)" "sudo chmod 600 $f" ;;
            esac
        fi
    done
    return 0
}
