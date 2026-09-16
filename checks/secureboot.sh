# Secure Boot checks [U/R]
check_secureboot() {
    if ! uefi_booted; then
        finding_status SKIP secureboot secureboot.uefi system high "system not booted with UEFI" "${NIXOS_DOCTOR_EFI_ROOT:-/sys/firmware/efi}" "Secure Boot is not applicable to this boot"
        return 0
    fi
    finding_status PASS secureboot secureboot.uefi system high "UEFI firmware interface present" "${NIXOS_DOCTOR_EFI_ROOT:-/sys/firmware/efi}" "system booted in UEFI mode"

    bootctl_out=""; bootctl_ok=0; bootctl_partial=0
    bootctl_confidence=high; loader=""; loader_kind=unknown; stub=""; entry=""
    if have bootctl; then
        if root_available; then
            bootctl_out=$(sudo -n bootctl status --no-pager 2>&1)
        else
            bootctl_out=$(bootctl status --no-pager 2>&1)
        fi
        bootctl_rc=$?
        if printf '%s\n' "$bootctl_out" | grep -qE 'Secure Boot:|Current Boot Loader:'; then
            bootctl_ok=1
            [ "$bootctl_rc" -ne 0 ] && bootctl_partial=1
            [ "$bootctl_partial" = 1 ] && bootctl_confidence=medium
            firmware_state=$(printf '%s\n' "$bootctl_out" | awk -F': ' '/Secure Boot:/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
            case "$firmware_state" in
                enabled*) finding_status PASS secureboot secureboot.firmware_state system "$bootctl_confidence" "firmware reports $firmware_state" bootctl "Secure Boot enabled" ;;
                disabled*) finding_status WARN secureboot secureboot.firmware_state system high "firmware reports $firmware_state" bootctl "Secure Boot disabled" ;;
                *) finding_status UNKNOWN secureboot secureboot.firmware_state system medium "Secure Boot field missing or unrecognized" bootctl "firmware Secure Boot state unknown" ;;
            esac
            loader=$(printf '%s\n' "$bootctl_out" | awk -F': ' '/Product:/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
            stub=$(printf '%s\n' "$bootctl_out" | awk -F': ' '/Current Stub:/{stub_section=1; next} stub_section && /Product:/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
            entry=$(printf '%s\n' "$bootctl_out" | awk -F': ' '/Current Entry:/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
            case "${loader,,}" in
                *systemd-boot*) loader_kind=systemd-boot ;;
                *grub*) loader_kind=grub ;;
                *limine*) loader_kind=limine ;;
                "") loader_kind=unknown ;;
                *) loader_kind=other ;;
            esac
            if [ "$loader_kind" = unknown ]; then
                finding_status UNKNOWN secureboot secureboot.bootloader system medium "bootloader product missing" bootctl "current bootloader unknown"
            else
                finding_status PASS secureboot secureboot.bootloader system "$bootctl_confidence" "bootctl identified $loader_kind" bootctl "current bootloader: $loader"
            fi
            [ -n "$stub" ] && finding_status PASS secureboot secureboot.stub system high "bootctl current stub" bootctl "current boot stub: $stub"
            [ -n "$entry" ] && finding_status PASS secureboot secureboot.current_entry system high "bootctl current entry" bootctl "current boot entry: $entry" || finding_status UNKNOWN secureboot secureboot.current_entry system medium "current entry missing" bootctl "current boot entry unknown"
            if [[ "$entry" == *.efi ]]; then
                finding_status PASS secureboot secureboot.uki system medium "current entry is an EFI executable" bootctl "current boot entry is a UKI-style EFI artifact"
            elif [ -n "$entry" ]; then
                finding_status UNKNOWN secureboot secureboot.uki system low "current entry is not an .efi filename" bootctl "current UKI artifact could not be identified"
            fi
            if [ "$bootctl_partial" = 1 ]; then
                finding_status SKIP secureboot secureboot.bootctl_details system high "bootctl returned partial data; protected ESP files were unreadable" "bootctl,root" "some bootloader details require --sudo"
            fi
        else
            finding_status ERROR secureboot secureboot.bootctl system high "bootctl status failed" bootctl "bootloader and firmware state unavailable"
        fi
    fi
    if [ "$bootctl_ok" = 0 ] && have mokutil; then
        if mok_out=$(mokutil --sb-state 2>/dev/null); then
            case "$mok_out" in
                *enabled*) finding_status PASS secureboot secureboot.firmware_state system high "mokutil reports enabled" mokutil "Secure Boot enabled" ;;
                *disabled*) finding_status WARN secureboot secureboot.firmware_state system high "mokutil reports disabled" mokutil "Secure Boot disabled" ;;
                *) finding_status UNKNOWN secureboot secureboot.firmware_state system medium "mokutil output unrecognized" mokutil "firmware Secure Boot state unknown" ;;
            esac
        else
            finding_status ERROR secureboot secureboot.firmware_state system high "mokutil query failed" mokutil "firmware Secure Boot state unavailable"
        fi
    elif [ "$bootctl_ok" = 0 ] && ! have mokutil; then
        finding_status SKIP secureboot secureboot.firmware_state system high "bootctl and mokutil missing" "bootctl,mokutil" "firmware Secure Boot state unavailable"
    fi

    if [ "$bootctl_ok" = 1 ]; then
        if root_available; then
            boot_list=$(sudo -n bootctl list --no-pager 2>&1)
        else
            boot_list=$(bootctl list --no-pager 2>&1)
        fi
        boot_list_rc=$?
        entry_count=$(printf '%s\n' "$boot_list" | grep -ciE '^[[:space:]]*(title|id):' || true)
        if [ "$entry_count" -gt 0 ]; then
            finding_status PASS secureboot secureboot.entries system high "bootctl listed entries" bootctl "$entry_count boot-entry field(s) visible"
        elif [ "$boot_list_rc" -ne 0 ] && printf '%s\n' "$boot_list" | grep -qi 'permission denied'; then
            finding_status SKIP secureboot secureboot.entries system high "boot entry files require privilege" "bootctl,root" "boot-entry listing requires --sudo"
        elif [ "$boot_list_rc" -ne 0 ]; then
            finding_status ERROR secureboot secureboot.entries system high "bootctl list exited $boot_list_rc" bootctl "boot entries could not be listed"
        else
            finding_status UNKNOWN secureboot secureboot.entries system low "bootctl list returned no entries" bootctl "no boot entries were visible"
        fi
    fi

    config_root="${NIXOS_DOCTOR_FLAKE_ROOT:-/etc/nixos}"
    if [ -d "$config_root" ]; then
        mapfile -d '' config_files < <(find "$config_root" -type f -name '*.nix' ! -path '*/.git/*' -print0 2>/dev/null)
        if [ -n "$stub" ] && [[ "${stub,,}" == *lanzastub* ]]; then
            finding_status PASS secureboot secureboot.lanzaboote system high "running boot stub is lanzastub" bootctl "running system uses Lanzaboote"
        elif [ "${#config_files[@]}" -gt 0 ] && grep -hE '^[[:space:]]*boot\.lanzaboote\.enable[[:space:]]*=[[:space:]]*true[[:space:]]*;' "${config_files[@]}" 2>/dev/null | grep -q .; then
            finding_status UNKNOWN secureboot secureboot.lanzaboote system low "static declaration found; effective evaluation not performed" "$config_root" "Lanzaboote is declared enabled in configuration"
        elif [ "${#config_files[@]}" -gt 0 ] && grep -hE '^[[:space:]]*boot\.lanzaboote\.enable[[:space:]]*=[[:space:]]*false[[:space:]]*;' "${config_files[@]}" 2>/dev/null | grep -q .; then
            finding_status WARN secureboot secureboot.lanzaboote system low "static disabled declaration found" "$config_root" "Lanzaboote is declared disabled in configuration"
        elif [ "${#config_files[@]}" -gt 0 ] && grep -qsE 'boot\.loader\.systemd-boot\.enable[[:space:]]*=[[:space:]]*true' "${config_files[@]}" 2>/dev/null; then
            finding_status PASS secureboot secureboot.configuration system medium "systemd-boot option found in configuration" "$config_root" "systemd-boot configured without detected Lanzaboote option"
        elif [ "${#config_files[@]}" -gt 0 ] && grep -hE '^[[:space:]]*boot\.loader\.grub\.enable[[:space:]]*=[[:space:]]*true[[:space:]]*;' "${config_files[@]}" 2>/dev/null | grep -q .; then
            finding_status UNKNOWN secureboot secureboot.configuration system low "static GRUB declaration found" "$config_root" "GRUB is declared enabled in configuration"
        elif [ "${#config_files[@]}" -gt 0 ] && grep -hE '^[[:space:]]*boot\.loader\.limine\.enable[[:space:]]*=[[:space:]]*true[[:space:]]*;' "${config_files[@]}" 2>/dev/null | grep -q .; then
            finding_status UNKNOWN secureboot secureboot.configuration system low "static Limine declaration found" "$config_root" "Limine is declared enabled in configuration"
        else
            finding_status UNKNOWN secureboot secureboot.configuration system low "known bootloader option not found by static scan" "$config_root" "declarative bootloader configuration unknown"
        fi
    else
        finding_status SKIP secureboot secureboot.configuration system high "configuration root absent" "$config_root" "declarative bootloader configuration unavailable"
    fi

    esp="${NIXOS_DOCTOR_ESP:-}"
    if [ -z "$esp" ] && have findmnt; then
        for candidate in /boot /boot/efi /efi; do
            fstype=$(findmnt -rn -o FSTYPE --target "$candidate" 2>/dev/null || true)
            if [ "$fstype" = vfat ]; then esp="$candidate"; break; fi
        done
    fi
    if [ -z "$esp" ]; then
        finding_status UNKNOWN secureboot secureboot.esp system medium "vfat ESP mount not found" findmnt "EFI System Partition mountpoint unknown"
    elif ! esp_row=$(df --output=avail "$esp" 2>/dev/null); then
        finding_status ERROR secureboot secureboot.esp_space system high "df failed for $esp" df "ESP space unavailable at $esp"
    else
        esp_kb=$(printf '%s\n' "$esp_row" | awk 'NR==2 {print $1}')
        if [[ "$esp_kb" =~ ^[0-9]+$ ]]; then
            esp_mb=$((esp_kb / 1024))
            if [ "$esp_mb" -lt 30 ]; then
                finding_status FAIL secureboot secureboot.esp_space system high "less than 30 MiB free" df "ESP at $esp has ${esp_mb} MiB free"
            elif [ "$esp_mb" -lt 100 ]; then
                finding_status WARN secureboot secureboot.esp_space system high "less than 100 MiB free" df "ESP at $esp has ${esp_mb} MiB free"
            else
                finding_status PASS secureboot secureboot.esp_space system high "ESP space measured" df "ESP at $esp has ${esp_mb} MiB free"
            fi
        else
            finding_status UNKNOWN secureboot secureboot.esp_space system low "free-space value not parsed" df "ESP space unknown at $esp"
        fi
    fi

    efi_vars="${NIXOS_DOCTOR_EFI_ROOT:-/sys/firmware/efi}/efivars"
    if [ -d "$efi_vars" ] && compgen -G "$efi_vars/*" >/dev/null; then
        first_var=$(compgen -G "$efi_vars/*" | head -1)
        if [ -r "$first_var" ]; then
            finding_status PASS secureboot secureboot.efivars system high "at least one EFI variable is readable" "$efi_vars" "EFI variables accessible"
        else
            finding_status SKIP secureboot secureboot.efivars system high "EFI variable entries require additional privilege" "$efi_vars" "EFI variables not readable as current user"
        fi
    elif [ -d "$efi_vars" ]; then
        finding_status UNKNOWN secureboot secureboot.efivars system medium "EFI variable directory is empty" "$efi_vars" "no EFI variable entries visible"
    elif [ -d "$efi_vars" ]; then
        finding_status SKIP secureboot secureboot.efivars system high "EFI variables require additional privilege" "$efi_vars" "EFI variables not readable as current user"
    else
        finding_status UNKNOWN secureboot secureboot.efivars system medium "EFI variable directory absent" "$efi_vars" "EFI variable access unavailable"
    fi

    booted=$(readlink -f /run/booted-system 2>/dev/null || true)
    current=$(readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)
    if [ -z "$booted" ] || [ -z "$current" ]; then
        finding_status UNKNOWN secureboot secureboot.generation system medium "generation links unavailable" "readlink,NixOS profiles" "booted/current generation alignment unknown"
    elif [ "$booted" = "$current" ]; then
        finding_status PASS secureboot secureboot.generation system high "generation links match" readlink "booted generation matches current profile"
    else
        booted_kernel=$(readlink -f /run/booted-system/kernel 2>/dev/null || true)
        current_kernel=$(readlink -f /nix/var/nix/profiles/system/kernel 2>/dev/null || true)
        if [ -n "$booted_kernel" ] && [ "$booted_kernel" = "$current_kernel" ]; then
            finding_status WARN secureboot secureboot.generation system high "generation differs but kernel matches" readlink "booted generation differs from current profile (rollback or userspace switch pending)"
        else
            finding_status WARN secureboot secureboot.generation system high "generation and kernel differ" readlink "booted generation differs from current profile; reboot or rollback state likely"
        fi
    fi
    booted_kernel=$(readlink -f /run/booted-system/kernel 2>/dev/null || true)
    current_kernel=$(readlink -f /nix/var/nix/profiles/system/kernel 2>/dev/null || true)
    if [ -n "$booted_kernel" ] && [ -n "$current_kernel" ]; then
        [ "$booted_kernel" = "$current_kernel" ] && finding_status PASS secureboot secureboot.kernel system high "kernel links match" readlink "booted kernel matches current profile" || finding_status WARN secureboot secureboot.kernel system high "kernel links differ" readlink "booted kernel differs from current profile"
    else
        finding_status UNKNOWN secureboot secureboot.kernel system medium "kernel links unavailable" readlink "booted/current kernel alignment unknown"
    fi
    booted_initrd=$(readlink -f /run/booted-system/initrd 2>/dev/null || true)
    current_initrd=$(readlink -f /nix/var/nix/profiles/system/initrd 2>/dev/null || true)
    if [ -n "$booted_initrd" ] && [ -n "$current_initrd" ]; then
        [ "$booted_initrd" = "$current_initrd" ] && finding_status PASS secureboot secureboot.initrd system high "initrd links match" readlink "booted initrd matches current profile" || finding_status WARN secureboot secureboot.initrd system high "initrd links differ" readlink "booted initrd differs from current profile"
    else
        finding_status UNKNOWN secureboot secureboot.initrd system medium "initrd links unavailable" readlink "booted/current initrd alignment unknown"
    fi

    if have sbctl; then
        if root_available; then
            sb_status=$(sudo -n sbctl status 2>&1); sb_status_rc=$?
            if printf '%s\n' "$sb_status" | grep -qi 'old configuration detected'; then
                finding_status WARN secureboot secureboot.sbctl_status system high "old sbctl configuration detected" sbctl "sbctl configuration needs migration"
            elif [ "$sb_status_rc" -ne 0 ]; then
                finding_status ERROR secureboot secureboot.sbctl_status system high "sbctl status exited $sb_status_rc" "sbctl,root" "sbctl status unavailable"
            else
                finding_status PASS secureboot secureboot.sbctl_status system high "sbctl status completed" sbctl "sbctl configuration readable"
            fi
            verify=$(sudo -n sbctl verify 2>&1); verify_rc=$?
            if printf '%s\n' "$verify" | grep -qiE 'not signed|unsigned|verification failed|invalid signature|signature.*failed|error verifying'; then
                finding_status FAIL secureboot secureboot.signatures system high "unsigned or failed artifact reported" "sbctl,root" "one or more EFI artifacts failed signature verification"
            elif [ "$verify_rc" -ne 0 ]; then
                finding_status ERROR secureboot secureboot.signatures system high "sbctl verify exited $verify_rc" "sbctl,root" "EFI artifact signatures could not be verified"
            elif [ -z "$verify" ]; then
                finding_status UNKNOWN secureboot secureboot.signatures system low "sbctl verify returned no output" "sbctl,root" "signature verification result unknown"
            else
                finding_status PASS secureboot secureboot.signatures system high "sbctl verify completed without unsigned artifacts" "sbctl,root" "EFI artifacts verified by sbctl"
            fi
        else
            finding_status SKIP secureboot secureboot.signatures system high "root capability unavailable" "sbctl,sudo --sudo" "signed EFI artifact verification needs --sudo with noninteractive sudo"
        fi
    else
        finding_status SKIP secureboot secureboot.signatures system high "command not installed" sbctl "signed EFI artifact verification unavailable"
    fi

    if have efibootmgr && root_available; then
        if ! efi_out=$(sudo -n efibootmgr -v 2>/dev/null); then
            finding_status ERROR secureboot secureboot.boot_order system high "efibootmgr query failed" "efibootmgr,root" "EFI boot order unavailable"
        elif printf '%s\n' "$efi_out" | grep -qiE 'Linux Boot Manager|systemd-boot|NixOS|\\EFI\\BOOT\\BOOTX64.EFI'; then
            finding_status PASS secureboot secureboot.boot_order system high "NixOS-compatible EFI entry found" efibootmgr "EFI boot entries include the NixOS loader"
        else
            finding_status WARN secureboot secureboot.boot_order system medium "NixOS-compatible EFI entry not recognized" efibootmgr "EFI boot order does not visibly reference the NixOS loader"
        fi
    elif ! have efibootmgr; then
        finding_status SKIP secureboot secureboot.boot_order system high "command not installed" efibootmgr "EFI boot-order inspection unavailable"
    else
        finding_status SKIP secureboot secureboot.boot_order system high "root capability unavailable" "efibootmgr,sudo --sudo" "EFI boot-order inspection needs --sudo with noninteractive sudo"
    fi
    return 0
}
