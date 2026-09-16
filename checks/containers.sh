# containers/flatpak checks [U]
check_containers() {
    for u in podman.service docker.service libvirtd.service; do
        if systemctl is-enabled "$u" >/dev/null 2>&1; then
            systemctl is-active "$u" >/dev/null 2>&1 && finding PASS containers "$u enabled+active" || finding WARN containers "$u enabled but down" "systemctl start $u"
        fi
    done
    if have podman; then
        if ! podman_json=$(podman system df --format json 2>/dev/null); then
            finding_status ERROR containers containers.podman user high "podman system df failed" podman "Podman storage state unavailable"
        elif ! printf '%s' "$podman_json" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
            finding_status ERROR containers containers.podman user high "invalid JSON output" "podman,python3" "Podman storage output could not be parsed"
        else
            finding_status PASS containers containers.podman user high "query completed" podman "Podman storage state readable"
        fi
    else
        finding_status SKIP containers containers.podman user high "command not installed" podman "Podman checks not applicable"
    fi
    if have flatpak; then
        if flatpak uninstall --help 2>/dev/null | grep -q -- '--dry-run'; then
            if ! flatpak_out=$(flatpak uninstall --unused --dry-run 2>/dev/null); then
                finding_status ERROR containers containers.flatpak user high "Flatpak dry-run failed" flatpak "unused Flatpak runtimes could not be checked"
            elif [ -n "$flatpak_out" ]; then
                finding WARN containers "unused flatpak runtimes" "flatpak uninstall --unused (manual confirmation)"
            else
                finding PASS containers "no unused flatpak runtimes"
            fi
        else
            finding_status SKIP containers containers.flatpak user high "installed Flatpak lacks --dry-run" flatpak "safe unused-runtime preview unavailable"
        fi
    else
        finding_status SKIP containers containers.flatpak user high "command not installed" flatpak "Flatpak checks not applicable"
    fi
    return 0
}
