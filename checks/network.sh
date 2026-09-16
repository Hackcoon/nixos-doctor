# network checks [U/R]
check_network() {
    if have ip; then
        if ! links=$(ip -o link show up 2>/dev/null); then
            finding_status ERROR network network.links system high "ip link query failed" ip "network links could not be read"
        elif printf '%s\n' "$links" | grep -qv LOOPBACK; then
            finding PASS network "at least one link up"
        else
            finding FAIL network "no links up (loopback only)" "ip link; rfkill list; systemctl status NetworkManager"
        fi
        if ! routes=$(ip route show default 2>/dev/null); then
            finding_status ERROR network network.route system high "route query failed" ip "default route could not be read"
        elif [ -n "$routes" ]; then
            finding PASS network "default route present"
        else
            finding FAIL network "no default route" "ip route; nmcli device status"
        fi
    else
        finding_status SKIP network network.ip system high "command not installed" ip "link and route checks unavailable"
    fi
    if have getent && getent hosts "${NIXOS_DOCTOR_DNS_TEST:-nixos.org}" >/dev/null 2>&1; then
        finding PASS network "DNS resolves"
    elif have getent; then
        finding FAIL network "DNS does not resolve" "resolvectl status; cat /etc/resolv.conf; nmcli dev show | grep DNS"
    else
        finding_status SKIP network network.dns system high "command not installed" getent "DNS resolution check unavailable"
    fi
    if have nmcli; then
        if ! nm_state=$(nmcli -t -f TYPE,STATE dev status 2>/dev/null); then
            finding_status ERROR network network.networkmanager system high "nmcli query failed" nmcli "NetworkManager state unavailable"
        else
            wifi=$(printf '%s\n' "$nm_state" | grep -c "^wifi:connected" || true)
            eth=$(printf '%s\n' "$nm_state" | grep -c "^ethernet:connected" || true)
            [ "$((wifi + eth))" -gt 0 ] && finding PASS network "NetworkManager connected" || finding WARN network "NetworkManager reports nothing connected" "nmcli device status; nmcli radio all"
        fi
        drops=$(journalctl -b --no-pager 2>/dev/null | grep -ciE "disconnected|association failed|deauthenticat" || true)
        [ "${drops:-0}" -gt 10 ] && finding WARN network "$drops disconnect-related lines this boot" "journalctl -b -u NetworkManager | tail -30"
    fi
    if systemctl is-active systemd-networkd >/dev/null 2>&1 && systemctl is-active NetworkManager >/dev/null 2>&1; then
        finding WARN network "both systemd-networkd and NetworkManager enabled (they fight)" "disable one: systemctl disable ..."
    fi
    if need_root network "firewall ruleset"; then
        if ! have nft; then
            finding_status SKIP network network.firewall system high "command not installed" nft "nftables firewall check unavailable"
        elif ! rules=$(sudo -n nft list ruleset 2>/dev/null); then
            finding_status ERROR network network.firewall system high "nft query failed" "nft,root" "firewall ruleset could not be read"
        elif printf '%s\n' "$rules" | grep -q "hook input"; then
            finding PASS network "nftables input hook present"
        else
            finding WARN network "no nftables input hook visible" "check networking.firewall in /etc/nixos"
        fi
    fi
}
