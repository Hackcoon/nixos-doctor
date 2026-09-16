# boot checks [U, ESP reads R]
check_boot() {
    if ! uefi_booted; then
        finding_status SKIP boot boot.uefi system high "system not booted with UEFI" /sys/firmware/efi "UEFI and EFI boot-entry checks not applicable"
    fi
    # Only require systemd-boot entries when bootctl identifies that loader.
    loader=""
    have bootctl && loader=$(bootctl status 2>/dev/null | grep -i 'Product:' | head -1 || true)
    if uefi_booted && need_root boot "ESP entry listing"; then
        if [ -n "$loader" ] || [ -d /boot/loader/entries ]; then
            if ! entries=$(sudo -n ls /boot/loader/entries/ 2>/dev/null); then
                finding_status ERROR boot boot.loader_entries system high "loader entry listing failed" "root,/boot" "systemd-boot entries could not be read"
                n=-1
            else
                n=$(printf '%s\n' "$entries" | grep -c . || true)
            fi
        else
            finding_status SKIP boot boot.loader_entries system high "different bootloader or ESP unavailable" bootctl "systemd-boot entry check not applicable"
            n=-1
        fi
        if [ "$n" -eq 0 ]; then
            finding FAIL boot "no loader entries in /boot/loader/entries" "bootctl install; check boot.loader in /etc/nixos"
        elif [ "$n" -gt 0 ]; then
            finding PASS boot "$n loader entries present"
        fi
        if have efibootmgr; then
            if ! efi_entries=$(sudo -n efibootmgr 2>/dev/null); then
                finding_status ERROR boot boot.efi_entries system high "efibootmgr query failed" "efibootmgr,root" "EFI boot entries could not be read"
            elif printf '%s\n' "$efi_entries" | grep -qiE 'NixOS|Linux Boot Manager|systemd-boot'; then
                finding PASS boot "EFI BootOrder references NixOS"
            else
                finding WARN boot "no NixOS entry in EFI boot order" "sudo efibootmgr --create --disk ... (see manual bootloader)"
            fi
        else
            finding_status SKIP boot boot.efi_entries system high "command not installed" efibootmgr "EFI boot-entry check unavailable"
        fi
    fi
    # ESP free space
    esp_free_kb=$(df --output=avail /boot 2>/dev/null | awk 'NR==2 {gsub(/[[:space:]]/, "", $1); print $1}')
    if [ -n "$esp_free_kb" ] && [ "$esp_free_kb" -gt 0 ] 2>/dev/null; then
        esp_free_mb=$((esp_free_kb / 1024))
        if [ "$esp_free_mb" -lt 30 ]; then
            finding FAIL boot "ESP only ${esp_free_mb}M free" "delete old generations + nixos-rebuild boot; check kernels piling up"
        elif [ "$esp_free_mb" -lt 100 ]; then
            finding WARN boot "ESP ${esp_free_mb}M free" "nix-collect-garbage -d (asks first); rebuild"
        else
            finding PASS boot "ESP ${esp_free_mb}M free"
        fi
    else
        finding_status ERROR boot boot.esp_space system high "df failed or /boot is unavailable" df "cannot read /boot usage"
    fi
    # booted vs current
    if [ -e /run/booted-system/kernel ] && [ -e /nix/var/nix/profiles/system/kernel ]; then
        if [ "$(readlink /run/booted-system/kernel 2>/dev/null)" = "$(readlink /nix/var/nix/profiles/system/kernel 2>/dev/null)" ]; then
            finding PASS boot "booted kernel matches current profile"
        else
            finding WARN boot "rebuilt but running an older kernel — reboot pending" "reboot when convenient"
        fi
    fi
    # last-boot errors
    if have journalctl; then
        if ! previous_errors=$(journalctl -b -1 -p err --no-pager 2>/dev/null); then
            finding_status SKIP boot boot.previous_errors system high "previous boot journal unavailable" journalctl "previous boot errors could not be read"
            previous_errors=""
            n=-1
        else
            n=$(printf '%s\n' "$previous_errors" | grep -c . || true)
        fi
        if [ "${n:-0}" -gt 0 ]; then
            finding FAIL boot "${n} error lines in previous boot log" "journalctl -b -1 -p err --no-pager | head -30"
        elif [ "${n:-0}" -eq 0 ]; then
            finding PASS boot "previous boot had no logged errors"
        fi
    else
        finding_status SKIP boot boot.previous_errors system high "command not installed" journalctl "previous boot journal check unavailable"
    fi
    # sbctl signatures
    if have sbctl && need_root boot "sbctl verify"; then
        sbctl_output=$(sudo -n sbctl verify 2>&1)
        sbctl_rc=$?
        if [ "$sbctl_rc" -ne 0 ]; then
            finding_status ERROR boot boot.sbctl_verify system high "sbctl verify exited $sbctl_rc" "sbctl,root" "Secure Boot signatures could not be verified"
        elif printf '%s\n' "$sbctl_output" | grep -qiE "not signed|failed"; then
            finding FAIL boot "sbctl reports unsigned binaries (Secure Boot would refuse them)" "sudo sbctl verify; re-sign per wiki"
        else
            finding PASS boot "sbctl signatures verify"
        fi
    elif ! have sbctl; then
        finding_status SKIP boot boot.sbctl_verify system high "command not installed" sbctl "Secure Boot signature verification unavailable"
    fi
    return 0
}
