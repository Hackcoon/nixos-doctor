# security hygiene checks [U/R]
check_security() {
    if ! have journalctl; then
        finding_status SKIP security security.ssh_logins system high "command not installed" journalctl "SSH login history unavailable"
    elif ! ssh_log=$(journalctl --since -7d -u sshd --no-pager 2>/dev/null); then
        finding_status ERROR security security.ssh_logins system high "journal query failed" journalctl "SSH login history could not be read"
    else
        n=$(printf '%s\n' "$ssh_log" | grep -ciE "Failed password|Invalid user|authentication failure" || true)
        if [ "${n:-0}" -gt 20 ]; then
            finding WARN security "$n failed SSH logins in 7d" "journalctl -u sshd | tail"
        else
            finding PASS security "$n failed SSH logins in 7d"
        fi
    fi
    if [ -d ~/.ssh ]; then
        [ "$(stat -c %a "$HOME/.ssh" 2>/dev/null)" = 700 ] || finding WARN security "SSH directory permissions wrong" "chmod 700 $HOME/.ssh"
        find ~/.ssh -type f ! -name '*.pub' -perm /077 2>/dev/null | grep -q . && finding WARN security "group/other-readable private files under ~/.ssh" "find ~/.ssh -type f ! -name '*.pub' -exec chmod 600 {} +"
    fi
    find ~ -maxdepth 1 -type f -perm -002 2>/dev/null | grep -q . && finding WARN security "world-writable files in \$HOME" "ls -la ~ | grep '^..w.*w'"
    if have aa-status; then
        if ! aa_out=$(aa-status 2>/dev/null); then
            finding_status ERROR security security.apparmor system high "aa-status failed" aa-status "AppArmor state unavailable"
        elif printf '%s\n' "$aa_out" | grep -qiE "0 profiles|apparmor not enabled"; then
            finding WARN security "AppArmor has no loaded profiles"
        else
            finding PASS security "AppArmor profiles loaded"
        fi
    else
        finding_status SKIP security security.apparmor system high "command not installed" aa-status "AppArmor check unavailable"
    fi
    return 0
}
