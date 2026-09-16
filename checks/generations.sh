# generations checks [U]
check_generations() {
    if ! have nix-env; then
        finding_status SKIP generations generations.command system high "command not installed" nix-env "generation counts unavailable"
        return 0
    fi
    for prof in "/nix/var/nix/profiles/system:system" "$HOME/.local/state/nix/profiles/home-manager:home-manager"; do
        p="${prof%%:*}"; name="${prof##*:}"
        [ -e "$p" ] || continue
        if ! out=$(nix-env --list-generations --profile "$p" 2>/dev/null); then
            finding_status SKIP generations "generations.$name" system high "profile unreadable as current user" nix-env "$name profile unreadable (root-owned profile may require --sudo)"
            continue
        elif [ -z "$out" ]; then
            finding_status UNKNOWN generations "generations.$name" system medium "profile returned no generations" nix-env "$name profile contains no readable generations"
            continue
        fi
        n=$(printf '%s' "$out" | grep -c . || true)
        n=${n:-0}
        if [ "$n" -gt 50 ]; then
            finding FAIL generations "$name profile: $n generations" "nix-env --delete-generations --profile $p 30d (asks first)"
        elif [ "$n" -gt 20 ]; then
            finding WARN generations "$name profile: $n generations" "nix-env --delete-generations --profile $p 30d (asks first)"
        elif [ "$n" -gt 0 ]; then
            finding PASS generations "$name profile: $n generations"
        fi
    done
    # booted vs current system
    if [ -e /run/booted-system ] && [ -e /nix/var/nix/profiles/system ]; then
        if [ "$(readlink /run/booted-system 2>/dev/null)" = "$(readlink /nix/var/nix/profiles/system 2>/dev/null)" ]; then
            finding PASS generations "running the current system generation"
        else
            finding WARN generations "running an older generation than current (rollback state or pending reboot)" "reboot, or nixos-rebuild switch --rollback to align"
        fi
    fi
    return 0
}
