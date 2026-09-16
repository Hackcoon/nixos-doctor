# backups checks [U]
check_backups() {
    if grep -rqiE "restic|borgbackup|bup|kopia" /etc/nixos/modules/ 2>/dev/null; then
        finding PASS backups "backup job configured in modules"
    else
        finding WARN backups "no backup jobs configured (ext4: no snapshots; rollback is boot-menu only)" "services.restic.backups.<name> or services.borgbackup.jobs.<name>"
    fi
}
