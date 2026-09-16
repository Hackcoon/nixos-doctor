# disk/fs checks [U/R]
check_disk() {
    # Collect df rows first, then iterate from a herestring: piping df
    # directly into `while read` runs the loop in a subshell, which would
    # silently drop every finding() counter update.
    if ! df_output=$(df -h -x tmpfs -x devtmpfs -x overlay 2>/dev/null); then
        finding_status ERROR disk disk.usage system high "df query failed" df "filesystem usage could not be read"
        _df=""
    else
        _df=$(printf '%s\n' "$df_output" | awk 'NR>1 {print $5" "$6}')
    fi
    while read -r pct mnt; do
        [ -z "$pct" ] && continue
        n=${pct%%%*}
        if [ "$n" -ge 95 ]; then
            finding FAIL disk "$mnt ${pct} full"
        elif [ "$n" -ge 85 ]; then
            finding WARN disk "$mnt ${pct} full" "du -sh $mnt/* 2>/dev/null | sort -rh | head"
        fi
    done <<EOF
$_df
EOF
    if ! inode_out=$(df -i / 2>/dev/null); then
        finding_status ERROR disk disk.inodes system high "df inode query failed" df "root inode usage unavailable"
    else
        inodes=$(printf '%s\n' "$inode_out" | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
        if [ -z "$inodes" ]; then
            finding_status UNKNOWN disk disk.inodes system low "inode percentage not parsed" df "root inode usage unknown"
        elif [ "$inodes" -ge 90 ]; then
            finding WARN disk "root inodes ${inodes}% used" "many small files: check ~/.cache, /var/tmp"
        else
            finding PASS disk "root inodes ${inodes}% used"
        fi
    fi
    # Root filesystem flavor drives the checks below (ext4/xfs/btrfs/zfs/...).
    if ! have findmnt; then
        ROOT_FSTYPE=""; ROOT_DEV=""
        finding_status SKIP disk disk.root_filesystem system high "command not installed" findmnt "root filesystem type unavailable"
    elif ! ROOT_FSTYPE=$(findmnt -no FSTYPE / 2>/dev/null) || ! ROOT_DEV=$(findmnt -no SOURCE / 2>/dev/null); then
        finding_status ERROR disk disk.root_filesystem system high "findmnt query failed" findmnt "root filesystem could not be identified"
        ROOT_FSTYPE=""; ROOT_DEV=""
    else
        finding PASS disk "root filesystem: $ROOT_FSTYPE"
    fi
    # Filesystem distress scan: generic signals plus per-fs dialects.
    # (btrfs/zfs report checksums and pool health in their own words;
    # ext4/xfs lean on the generic I/O + error lines too.)
    if ! have journalctl; then
        finding_status SKIP disk disk.kernel_errors system high "command not installed" journalctl "filesystem kernel-log check unavailable"
    elif ! kernel_log=$(journalctl -b -k --no-pager 2>/dev/null); then
        finding_status ERROR disk disk.kernel_errors system high "kernel journal query failed" journalctl "filesystem kernel log could not be read"
    elif printf '%s\n' "$kernel_log" | grep -qiE "I/O error|Buffer I/O error|remount.*read-only|Remounting filesystem read-only|fsck.*UNEXPECTED|EXT4-fs error|XFS.*(error|corruption|shut.*down)|BTRFS (error|warning.*checksum|parent transid)|ZFS.*(error|checksum|DEGRADED|FAULTED|UNAVAIL)"; then
        finding FAIL disk "filesystem/IO errors in kernel log" "journalctl -k --no-pager | grep -iE 'EXT4-fs error|XFS|BTRFS|ZFS|I/O error|remount' | tail -20 (Tier 2: fsck/repair from installer USB)"
    else
        finding PASS disk "no filesystem errors in kernel log"
    fi
    # ZFS pool health (zpool status is user-readable).
    if [ "$ROOT_FSTYPE" = "zfs" ] || have zpool; then
        if have zpool; then
            if zpool status -x 2>/dev/null | grep -q "all pools are healthy"; then
                finding PASS disk "zpool status: all pools healthy"
            elif zpool list -H -o name >/dev/null 2>&1 && [ -n "$(zpool list -H -o name 2>/dev/null)" ]; then
                finding FAIL disk "zpool reports unhealthy pool" "zpool status -v (Tier 2: replace/resilver per output)"
            else
                finding SKIP disk "zpool installed but no imported pools"
            fi
        fi
    fi
    # btrfs snapshots change the rollback story (ext4 has none).
    if [ "$ROOT_FSTYPE" = "btrfs" ] && [ -d /.snapshots ]; then
        finding PASS disk "btrfs snapshots present (rollback beyond boot menu possible)"
    fi
    # ext4 root-reserved blocks (xfs/btrfs/zfs have no such knob).
    if [ "$ROOT_FSTYPE" = "ext4" ] && [ -b "${ROOT_DEV:-/nonexistent}" ] && need_root disk "ext4 reserved blocks"; then
        tune=$(sudo -n tune2fs -l "$ROOT_DEV" 2>/dev/null || true)
        res=$(printf '%s\n' "$tune" | grep -i "reserved block count" | awk '{print $NF}')
        total=$(printf '%s\n' "$tune" | grep -i "block count" | head -1 | awk '{print $NF}')
        if [ -n "$res" ] && [ -n "$total" ] && [ "$total" -gt 0 ]; then
            pct=$((res * 100 / total))
            [ "$pct" -ge 5 ] && finding WARN disk "ext4 reserves ${pct}% (~$((res*4/1024/1024))G) for root" "sudo tune2fs -m 1 $ROOT_DEV (Tier 2)"
        fi
    fi
    if findmnt -no FSTYPE / 2>/dev/null | grep -qE '^(btrfs|ext4|xfs|f2fs)$'; then
        if systemctl is-enabled fstrim.timer >/dev/null 2>&1; then
            finding PASS disk "fstrim.timer enabled"
        else
            finding_fix WARN disk "fstrim.timer off (periodic discard may improve SSD maintenance)" fstrim "fstrim -a"
        fi
    else
        finding SKIP disk "TRIM timer (root filesystem is not a known local filesystem)"
    fi
    for d in /tmp /var/tmp; do
        sz=$(du -sh "$d" 2>/dev/null | cut -f1)
        [ -n "$sz" ] && finding PASS disk "$d using $sz"
    done
    return 0
}
