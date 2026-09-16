# rebuild-triage checks [U]
check_rebuild() {
    free_mb=$(df --output=avail /tmp 2>/dev/null | tail -1 | tr -d ' ')
    if [ -z "$free_mb" ]; then
        finding_status ERROR rebuild rebuild.tmp_space system high "df failed or returned no value" df "/tmp free space could not be read"
    elif [ "$free_mb" -lt 5242880 ] 2>/dev/null; then
        finding WARN rebuild "/tmp low for builds" "TMPDIR=/nix/var/tmp or free space"
    else
        finding PASS rebuild "/tmp headroom ok"
    fi
    mem_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || true)
    if [ -z "$mem_kb" ]; then
        finding_status ERROR rebuild rebuild.memory system high "MemAvailable unavailable" /proc/meminfo "available RAM could not be read"
    elif [ "$mem_kb" -lt 2000000 ]; then
        finding WARN rebuild "low RAM for builds (${mem_kb}K avail)" "nixos-rebuild switch --option max-jobs 1 --option cores 2"
    fi
    lock=/nix/var/nix/db/big-lock
    if [ ! -e "$lock" ]; then
        finding_status SKIP rebuild rebuild.db_lock system high "lock path absent" "$lock" "Nix DB lock check not applicable"
    elif ! have fuser; then
        finding_status SKIP rebuild rebuild.db_lock system high "command not installed" fuser "Nix DB lock holder unavailable"
    elif fuser "$lock" >/dev/null 2>&1; then
        finding WARN rebuild "nix DB lock held — another build may be running" "ps aux | grep -E 'nix-build|nixos-rebuild'"
    else
        finding PASS rebuild "nix DB lock free"
    fi
    finding SKIP rebuild "last rebuild trace (paste failures here in TUI)"
}
