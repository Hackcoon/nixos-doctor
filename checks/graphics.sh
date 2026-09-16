# graphics-stack checks [U]
check_graphics() {
    expected="${NIXOS_DOCTOR_EXPECTED_COMPOSITOR:-auto}"
    active=$(session_kind)
    if [ "$expected" = none ]; then
        finding SKIP graphics "graphics checks disabled by profile"
        return 0
    fi
    if [ "$expected" = mango ] && [ "$active" != mango ]; then
        finding_status WARN graphics graphics.compositor session high "expected mango, detected $active" "mango,session" "configured Mango compositor is not active"
    fi
    user_bus=1
    if ! user_bus_available; then
        user_bus=0
        finding_status SKIP graphics graphics.user_bus user high "user systemd manager unavailable" "systemctl,user-session" "user systemd session unavailable; portal service state unavailable"
    fi
    if [ "$active" = mango ]; then
        finding PASS graphics "mango compositor running"
    elif [ "$expected" = auto ]; then
        finding_status SKIP graphics graphics.mango session high "active session is $active" mango "Mango runtime checks not applicable"
    fi
    if have glxinfo; then
        r=$(glxinfo 2>/dev/null | grep -i "OpenGL renderer" | head -1 || true)
        case "$r" in
            *llvmpipe*|*softpipe*|*Software*) finding FAIL graphics "software rendering ($r)" "check nvidia driver + GBM: lsmod | grep nvidia" ;;
            NVIDIA*|"") [ -z "$r" ] && finding WARN graphics "glxinfo gave no renderer" || finding PASS graphics "GL renderer: $(printf '%s' "$r" | cut -d: -f2 | head -c 40)" ;;
            *) finding PASS graphics "GL renderer: $(printf '%s' "$r" | cut -d: -f2 | head -c 40)" ;;
        esac
    fi
    if [ "$active" = mango ] && have mmsg; then
        xw=$(mmsg get all-clients 2>/dev/null | python3 -c "import json,sys; print(sum(1 for c in json.load(sys.stdin).get('clients',[]) if c.get('is_xwayland')))" 2>/dev/null || true)
        [ -n "$xw" ] && finding PASS graphics "$xw X11 clients via xwayland (vesktop/upscayl expected)"
        if mmsg get all-monitors 2>/dev/null | grep -q .; then
            finding PASS graphics "mango IPC responsive"
        else
            finding WARN graphics "mango IPC not responding" "echo \$MANGO_INSTANCE_SIGNATURE"
        fi
    fi
    if have mango && [ -f "${HOME:-}/.config/mango/config.conf" ] && mango -p -c "${HOME}/.config/mango/config.conf" >/dev/null 2>&1; then
        finding PASS graphics "mango config valid"
    elif have mango && [ -f "${HOME:-}/.config/mango/config.conf" ]; then
        finding FAIL graphics "mango config invalid" "mango -p -c ~/.config/mango/config.conf"
    else
        finding SKIP graphics "mango config (mango or config not present)"
    fi
    # DMS needs mango >= 0.14 for the new IPC (bar workspaces die below it).
    if have mango; then
        ver=$(mango -v 2>/dev/null | grep -oE "[0-9]+\.[0-9]+" | head -1)
    else
        ver=""
    fi
    if [ -n "$ver" ]; then
        minor=${ver##*.}
        [ "$minor" -ge 14 ] 2>/dev/null && finding PASS graphics "mango $ver (>= 0.14, DMS IPC ok)" || finding FAIL graphics "mango $ver too old for DMS bar IPC" "upgrade mangowc to >= 0.14"
    fi
    dms_settings="${HOME:-}/.config/DankMaterialShell/settings.json"
    if [ -f "$dms_settings" ] && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$dms_settings" 2>/dev/null; then
        finding PASS graphics "DMS settings.json parses"
    elif [ -f "$dms_settings" ]; then
        finding FAIL graphics "DMS settings.json broken" "python3 -m json.tool ~/.config/DankMaterialShell/settings.json (restore from backup)"
    else
        finding SKIP graphics "DMS settings.json (not present)"
    fi
    if [ "$user_bus" = 1 ] && [ "$active" != none ]; then
        if systemctl --user is-active xdg-desktop-portal.service >/dev/null 2>&1; then
            finding PASS graphics "xdg-desktop-portal.service active"
        else
            finding_fix WARN graphics "xdg-desktop-portal.service not active" service_restart "systemctl --user restart xdg-desktop-portal.service" user xdg-desktop-portal.service
        fi
        portal_backends=$(systemctl --user is-active xdg-desktop-portal-wlr.service xdg-desktop-portal-gtk.service xdg-desktop-portal-kde.service 2>/dev/null | grep -c '^active$' || true)
        if [ "$portal_backends" -gt 0 ]; then
            finding PASS graphics "$portal_backends desktop portal backend(s) active"
        else
            finding WARN graphics "no supported desktop portal backend active" "systemctl --user status 'xdg-desktop-portal-*'"
        fi
    fi
    if pgrep -f "polkit.*auth|polkit-gnome|lxpolkit|xfce-polkit" >/dev/null 2>&1; then
        finding PASS graphics "polkit auth agent running"
    else
        finding WARN graphics "no polkit auth agent (admin prompts fail silently in mango)" "exec-once=/usr/libexec/polkit-gnome-authentication-agent-1 (or xfce-polkit) in mango config"
    fi
    if [ -z "${XDG_CURRENT_DESKTOP:-}" ]; then
        finding WARN graphics "XDG_CURRENT_DESKTOP unset in this shell (portals/file pickers may misbehave)" "export XDG_CURRENT_DESKTOP=mango (mango exec-once env)"
    fi
}
