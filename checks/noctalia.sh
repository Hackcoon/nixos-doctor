# Noctalia shell checks [U]
check_noctalia() {
    service_state="unknown"
    if ! have noctalia; then
        finding_status SKIP noctalia noctalia.cli session high "command not installed" noctalia "Noctalia checks not applicable"
        return 0
    fi
    if ! user_bus_available; then
        finding_status SKIP noctalia noctalia.user_bus user high "user systemd manager unavailable" "systemctl,user-session" "Noctalia service state unavailable"
    else
        unit_state=$(systemctl --user show noctalia.service -p LoadState --value 2>/dev/null)
        unit_rc=$?
        if [ "$unit_rc" -ne 0 ]; then
            finding_status ERROR noctalia noctalia.service user high "systemctl unit query failed" "systemctl,user-session" "Noctalia service state unavailable"
        elif [ "$unit_state" = not-found ]; then
            finding_status SKIP noctalia noctalia.service user high "unit not installed" "systemctl,user-session" "Noctalia service not installed"
        else
            service_state=$(systemctl --user is-active noctalia.service 2>/dev/null || true)
            if [ "$service_state" = active ]; then
                finding PASS noctalia "noctalia.service active"
            else
                finding_status WARN noctalia noctalia.service user high "installed but state=$service_state" systemctl "Noctalia service is not active"
            fi
        fi
    fi
    if ! version=$(noctalia --version 2>/dev/null); then
        finding_status ERROR noctalia noctalia.version session high "version query failed" noctalia "Noctalia version unavailable"
    elif [ -n "$version" ]; then
        version=${version#noctalia }
        finding_status PASS noctalia noctalia.version session high "version query succeeded" noctalia "Noctalia $version"
    else
        finding_status UNKNOWN noctalia noctalia.version session low "empty version output" noctalia "Noctalia version unknown"
    fi
    if ! config_report=$(noctalia config validate 2>&1); then
        finding_status FAIL noctalia noctalia.config session high "configuration validation failed" noctalia "Noctalia configuration is invalid"
    else
        finding_observed PASS noctalia noctalia.config session high "configuration validation succeeded" noctalia "Noctalia configuration valid" "noctalia config validate" 0 "$config_report" noctalia
    fi
    if [ "${NIXOS_DOCTOR_EXPECTED_SHELL:-auto}" = noctalia ]; then
        if [ "$service_state" = active ]; then
            finding PASS noctalia "Noctalia is the configured shell"
        else
            finding_status WARN noctalia noctalia.expected_shell session high "Noctalia expected but service is not active" "noctalia,systemd" "configured Noctalia shell is not running"
        fi
    fi
    return 0
}
