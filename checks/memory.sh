# memory checks [U]
check_memory() {
    if [ -r /proc/pressure/memory ]; then
        full=$(awk '/^full/ {for (i=1; i<=NF; i++) if ($i ~ /^avg10=/) {sub("avg10=", "", $i); print $i}}' /proc/pressure/memory 2>/dev/null)
        if [ -n "$full" ]; then
            awk -v value="$full" 'BEGIN { exit !(value >= 20) }' && finding WARN memory "memory stall ${full}% (avg10 full)" "close tabs; check top-RSS below" || finding PASS memory "memory pressure low"
        else
            finding SKIP memory "memory PSI could not be read"
        fi
    else
        finding SKIP memory "memory PSI unavailable"
    fi
    if [ -e /dev/zram0 ]; then
        finding PASS memory "zram present"
    elif swapon --show 2>/dev/null | grep -q .; then
        finding PASS memory "swap active"
    else
        finding WARN memory "no swap or zram (OOM kills instead of slowing down)" "zramSwap.enable=true"
    fi
    if [ -r /proc/meminfo ]; then
        avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
        if [ -z "$avail" ]; then
            finding SKIP memory "MemAvailable could not be read"
        elif [ "$avail" -lt 500000 ]; then
            finding WARN memory "only $((avail/1024))M RAM available"
        else
            finding PASS memory "RAM headroom ok"
        fi
    else
        finding SKIP memory "/proc/meminfo unavailable"
    fi
}
