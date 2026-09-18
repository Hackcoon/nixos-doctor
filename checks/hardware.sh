# hardware checks [U/R]
check_hardware() {
    vendor=$(gpu_vendor)
    if printf '%s' "$vendor" | grep -q nvidia && lsmod 2>/dev/null | grep -q "^nvidia "; then
        finding PASS hardware "nvidia kernel module loaded"
        if have nvidia-smi; then
            vram=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
            used=${vram%%,*}; total=${vram##*,}
            if [ -n "$used" ] && [ -n "$total" ] && [ "$total" -gt 0 ] 2>/dev/null; then
                pct=$((used * 100 / total))
                [ "$pct" -ge 85 ] && finding WARN hardware "VRAM ${pct}% used (${used}/${total}M)" "close GPU apps; check loaded GPU models" || finding PASS hardware "VRAM ${pct}% used"
            fi
            drv=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
            [ -n "$drv" ] && finding PASS hardware "nvidia driver $drv"
        fi
    else
        case "$vendor" in
            *nvidia*) finding_status FAIL hardware hardware.nvidia_module hardware high "NVIDIA GPU detected but kernel module absent" "lspci,lsmod" "nvidia GPU detected but module is not loaded" ;;
            *amd*|*advanced\ micro\ devices*|*radeon*) finding_status PASS hardware hardware.amd hardware high "AMD GPU detected; NVIDIA checks not applicable" lspci "AMD GPU detected" ;;
            *intel*) finding_status PASS hardware hardware.intel hardware high "Intel GPU detected; NVIDIA checks not applicable" lspci "Intel GPU detected" ;;
            *) finding_status UNKNOWN hardware hardware.gpu_vendor hardware low "GPU not detected or lspci unavailable" lspci "GPU vendor could not be identified" ;;
        esac
    fi
    gov=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null || true)
    [ -n "$gov" ] && finding PASS hardware "cpu governor: $gov"
    if have sensors; then
        hot=$(sensors 2>/dev/null | grep -oE '\+[0-9]{1,3}\.[0-9]°C' | tr -d '+°C' | awk '$1 < 125' | sort -rn | head -1)
        if [ -n "$hot" ]; then
            awk "BEGIN{exit !( $hot > 90 )}" && finding WARN hardware "hottest sensor ${hot}°C" "dust/fan curve; powertop" || finding PASS hardware "temps ok (max ${hot}°C)"
        fi
    fi
    # SMART short health runs every sweep (fast, seconds); the destructive
    # long self-test stays manual. Needs root for device reads.
    if have smartctl; then
        if need_root hardware "SMART health"; then
            bad=0; checked=0
            devices=()
            if [ -n "${SMART_DEVS:-}" ]; then
                read -r -a devices <<<"$SMART_DEVS"
            elif have lsblk; then
                mapfile -t devices < <(lsblk -dnpo NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}')
            else
                finding_status SKIP hardware hardware.smart hardware high "lsblk unavailable for device enumeration" "smartctl,lsblk" "SMART devices could not be enumerated"
            fi
            if [ "${#devices[@]}" -eq 0 ] && [ -n "${SMART_DEVS:-}" ]; then
                finding_status UNKNOWN hardware hardware.smart hardware medium "no SMART fixture devices supplied" SMART_DEVS "SMART device list is empty"
            fi
            for d in "${devices[@]}"; do
                [ -b "$d" ] || [ -n "${SMART_DEVS:-}" ] || continue
                health=$(sudo -n smartctl -H "$d" 2>&1)
                health_rc=$?
                if [ "$health_rc" -ne 0 ] && printf '%s\n' "$health" | grep -qiE 'unsupported|unavailable|not available|unknown usb bridge'; then
                    finding_status SKIP hardware hardware.smart hardware high "SMART unsupported on $d" "smartctl,root" "SMART health unsupported on $d"
                    continue
                elif [ "$health_rc" -ne 0 ] && ! printf '%s\n' "$health" | grep -qiE 'FAILED|BAD|FAILING'; then
                    finding_status ERROR hardware hardware.smart hardware high "smartctl failed on $d (exit $health_rc)" "smartctl,root" "SMART health could not be read on $d"
                    continue
                elif [ "$health_rc" -ne 0 ]; then
                    finding FAIL hardware "SMART health bad on $d" "back up NOW; replace disk"
                    bad=1
                    checked=$((checked+1))
                    continue
                fi
                checked=$((checked+1))
                if printf '%s\n' "$health" | grep -qiE "PASSED|OK"; then
                    :
                elif printf '%s\n' "$health" | grep -qiE 'FAILED|BAD|FAILING'; then
                    finding FAIL hardware "SMART health bad on $d" "back up NOW; replace disk"
                    bad=1
                else
                    finding_status UNKNOWN hardware hardware.smart hardware low "unrecognized SMART health output on $d" smartctl "SMART health result unknown on $d"
                    checked=$((checked-1))
                    continue
                fi
                # SSD wear: NVMe Percentage Used / Available Spare, or SATA
                # wear attributes (VALUE column = percent remaining).
                # smartctl prints names with spaces — match accordingly.
                worn=$(sudo -n smartctl -A "$d" 2>/dev/null | awk '/Percentage Used/ {print $NF; exit}' | tr -d '%')
                [ -n "$worn" ] && [ "$worn" -ge 90 ] 2>/dev/null && { finding WARN hardware "$d SSD ${worn}% worn" "plan replacement; check backups area"; bad=1; }
                spare=$(sudo -n smartctl -A "$d" 2>/dev/null | awk '/Available Spare:/ {print $NF; exit}' | tr -d '%')
                [ -n "$spare" ] && [ "$spare" -le 10 ] 2>/dev/null && { finding WARN hardware "$d spare blocks ${spare}%" "plan replacement"; bad=1; }
                sata_left=$(sudo -n smartctl -A "$d" 2>/dev/null | awk '/Media_Wearout_Indicator|Wear_Leveling_Count/ {print $4; exit}')
                [ -n "$sata_left" ] && [ "$sata_left" -le 10 ] 2>/dev/null && { finding WARN hardware "$d SSD life ${sata_left}% left" "plan replacement"; bad=1; }
            done
            [ "$checked" -gt 0 ] && [ "$bad" = 0 ] && finding PASS hardware "SMART health ok"
        fi
    else
        finding SKIP hardware "SMART checks (smartctl missing)"
    fi
    if have upower; then
        if ! power_devices=$(upower -e 2>/dev/null); then
            finding_status ERROR hardware hardware.battery hardware high "upower device enumeration failed" upower "battery applicability could not be determined"
            power_devices=""
            battery_probe=error
        else
            battery=$(printf '%s\n' "$power_devices" | grep -i battery | head -1)
            [ -n "$battery" ] && battery_probe=present || battery_probe=absent
        fi
    else
        battery_probe=missing
        battery=""
    fi
    if [ "$battery_probe" = present ]; then
        if ! info=$(upower -i "$battery" 2>/dev/null); then
            finding_status ERROR hardware hardware.battery hardware high "upower query failed" upower "battery state could not be read"
        else
            cap=$(printf '%s\n' "$info" | grep -i percentage | grep -oE '[0-9]+%' | head -1)
            [ -n "$cap" ] && finding PASS hardware "battery $cap" || finding_status UNKNOWN hardware hardware.battery hardware low "percentage missing" upower "battery detected but capacity is unknown"
        fi
    elif [ "$battery_probe" = absent ]; then
        finding_status SKIP hardware hardware.battery hardware high "no battery detected" upower "battery checks not applicable"
    elif [ "$battery_probe" = missing ]; then
        finding_status SKIP hardware hardware.battery hardware high "command not installed" upower "battery checks unavailable"
    fi
    if have fwupdmgr; then
        finding PASS hardware "fwupd present (updates reported in updates area)"
    fi
}
