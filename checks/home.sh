# home-manager checks [U]
check_home() {
    hm_prof="$HOME/.local/state/nix/profiles/home-manager"
    if [ -e "$hm_prof" ]; then
        if ! have nix-env; then
            finding_status SKIP home home.generations user high "command not installed" nix-env "home-manager generation query requires nix-env"
        elif n=$(nix-env --list-generations --profile "$hm_prof" 2>/dev/null) && [ -n "$n" ]; then
            finding PASS home "home-manager profile: $(printf '%s\n' "$n" | grep -c .) generations"
        else
            finding_status ERROR home home.generations user high "profile query failed or returned no data" nix-env "home-manager profile could not be read"
        fi
    else
        finding_status SKIP home home.generations user high "profile not present" home-manager "no standalone home-manager profile (NixOS integration may be in use)"
    fi
    # $USER may be unset in bare environments (set -u is on).
    if [ -L "$HOME/.nix-profile" ] && [ -e /etc/profiles/per-user/"${USER:-$(id -un)}" ]; then
        finding PASS home "user profile link sane"
    fi
    return 0
}
