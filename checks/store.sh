# store checks [U, deep optional]
check_store() {
    if have nix; then
        if ! closure_out=$(nix path-info -Sh /run/current-system 2>/dev/null); then
            finding_status ERROR store store.closure system high "nix path-info failed" nix "current system closure unavailable"
        else
            closure=$(printf '%s\n' "$closure_out" | tail -1 | awk '{print $(NF-1)$NF}')
            [ -n "$closure" ] && finding PASS store "current system closure $closure" || finding_status UNKNOWN store store.closure system low "closure size not parsed" nix "current system closure size unknown"
        fi
    else
        finding_status SKIP store store.nix system high "command not installed" nix "Nix store checks unavailable"
    fi
    if [ "$DEEP" = 1 ]; then
        sz=$(du -sh /nix/store 2>/dev/null | cut -f1)
        [ -n "$sz" ] && finding PASS store "full store size $sz"
    fi
    use_pct=$(df --output=pcent / 2>/dev/null | awk 'NR==2 {gsub(/[^0-9]/, "", $1); print $1}')
    if [ -n "$use_pct" ]; then
        if [ "$use_pct" -ge 90 ]; then
            finding FAIL store "root filesystem ${use_pct}% full" "nix-collect-garbage (asks first); journalctl --vacuum-size=500M"
        elif [ "$use_pct" -ge 80 ]; then
            finding_fix WARN store "root filesystem ${use_pct}% full" nix_collect_garbage "nix-collect-garbage"
        else
            finding PASS store "root filesystem ${use_pct}% used"
        fi
    else
        finding_status ERROR store store.disk_usage system high "df failed or output not parsed" df "root filesystem usage unavailable"
    fi
    # daemon + substituters reachable (http(s) only; other schemes skipped)
    if have nix; then
        if ! config_out=$(nix show-config 2>/dev/null); then
            finding_status ERROR store store.substituters system high "nix show-config failed" nix "substituter configuration unavailable"
            config_out=""
        fi
        subs=$(printf '%s\n' "$config_out" | grep '^substituters' | cut -d= -f2-)
        ok=1; tested=0
        for s in $subs; do
            case "$s" in http*)
                tested=$((tested+1))
                if ! curl -sI -m 5 "$s" >/dev/null 2>&1; then
                    finding WARN store "substituter unreachable: $s" "check network / substituters in nix.settings"
                    ok=0
                fi ;;
            esac
        done
        [ "$ok" = 1 ] && [ "$tested" -gt 0 ] && finding PASS store "binary caches reachable ($tested tested)"
    fi
    # stale GC roots: result* symlinks in $HOME older than 14d
    stale_file=$(mktemp) || { finding_status ERROR store store.gc_roots system high "temporary file creation failed" mktemp "stale GC roots could not be checked"; return 0; }
    stale_scan_ok=0
    if find "$HOME" -maxdepth 2 -lname '/nix/store/*' -mtime +14 -print >"$stale_file" 2>/dev/null; then
        stale_scan_ok=1
        stale=$(head -5 "$stale_file")
    else
        finding_status ERROR store store.gc_roots user high "home-directory traversal failed" find "stale home GC roots could not be checked"
        stale=""
    fi
    rm -f "$stale_file"
    if [ -n "$stale" ]; then
        finding WARN store "stale result* GC roots pinning closures" "rm the dead result links: $(echo "$stale" | head -2 | tr '\n' ' ')"
    elif [ "$stale_scan_ok" = 1 ]; then
        finding PASS store "no stale result symlinks found"
    fi
    # deep integrity
    if [ "$DEEP" = 1 ]; then
        if have nix; then
            verify_log=$(mktemp "${TMPDIR:-/tmp}/nixos-doctor-verify.XXXXXXXX") || {
                finding SKIP store "store verification temporary log unavailable"
                return 0
            }
            if nix store verify --all 2>"$verify_log"; then
                finding PASS store "store verify --all clean"
            else
                finding FAIL store "corrupt store paths found (verification log: $verify_log)" "nix-store --repair-path <path> (asks first)"
            fi
            rm -f "$verify_log"
        fi
    else
        finding SKIP store "integrity verify (re-run with --deep)"
    fi
    return 0
}
