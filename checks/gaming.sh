# gaming checks [U] — steam/shader/vrr on this box
check_gaming() {
    if [ -d "$HOME/.local/share/Steam" ]; then
        lib=$(du -sh "$HOME/.local/share/Steam" 2>/dev/null | cut -f1)
        [ -n "$lib" ] && finding PASS gaming "steam library $lib"
        sh=$(du -sh "$HOME/.local/share/Steam/steamapps/shadercache" 2>/dev/null | cut -f1 | tr -d ' ')
        if [ -n "$sh" ]; then
            num=${sh%%[GMK]*}
            unit=${sh##*[0-9.]}
            big=0
            { [ "$unit" = G ] && [ "${num%.*}" -ge 10 ]; } 2>/dev/null && big=1
            [ "$big" = 1 ] && finding WARN gaming "shader cache $sh" "Steam > Settings > Storage > clear shader cache (Tier 1)" || finding PASS gaming "shader cache $sh"
        fi
        ntools=$(find "$HOME/.steam/root/compatibilitytools.d" -mindepth 1 -maxdepth 1 -print 2>/dev/null | wc -l)
        [ "${ntools:-0}" -gt 0 ] && finding PASS gaming "$ntools custom Proton tool(s)"
    else
        finding SKIP gaming "no Steam library found"
    fi
    have gamemode || finding WARN gaming "gamemode not installed (free fps smoothing)" "environment.systemPackages += gamemode (Tier 2 rebuild)"
    have mangohud && finding PASS gaming "mangohud present"
    return 0
}
