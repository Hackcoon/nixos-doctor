#!/usr/bin/env bash
# nixos-doctor --bundle — collect an AI-review tarball. Never uploads.
set -u -o pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
FLAKE_ROOT="${NIXOS_DOCTOR_FLAKE_ROOT:-/etc/nixos}"
umask 077
WORK=$(mktemp -d "${TMPDIR:-/tmp}/nixos-doctor.XXXXXXXX") || {
    echo "bundle: cannot create private temporary directory" >&2
    exit 2
}
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
trap 'exit 2' HUP INT TERM
host=$(hostname 2>/dev/null || printf unknown)
stamp=$(date +%Y%m%d-%H%M%S)
OUT="${TMPDIR:-/tmp}/nixos-doctor-${host}-${stamp}.tar.gz"
if [ -e "$OUT" ]; then
    echo "bundle: refusing to overwrite existing file: $OUT" >&2
    exit 2
fi

report_args=()
for arg in "$@"; do
    case "$arg" in
        --bundle) ;;
        *) report_args+=("$arg") ;;
    esac
done

{
    echo "### report"; "$SELF_DIR/nixos-doctor" "${report_args[@]}" --json
    echo "### generations"; nix-env --list-generations --profile /nix/var/nix/profiles/system 2>/dev/null
    echo "### systemd-failed"; systemctl --failed --no-legend 2>/dev/null; systemctl --user --failed --no-legend 2>/dev/null
    echo "### blame"; systemd-analyze blame --no-pager 2>/dev/null | head -15
    echo "### flake"; git -C "$FLAKE_ROOT" status --short 2>/dev/null; stat -c 'lock-mtime: %y' "$FLAKE_ROOT/flake.lock" 2>/dev/null
    echo "### desktop"
    command -v mango >/dev/null 2>&1 && [ -f "${HOME:-}/.config/mango/config.conf" ] && mango -p -c "$HOME/.config/mango/config.conf" 2>&1
    command -v dms >/dev/null 2>&1 && systemctl --user is-active dms.service 2>/dev/null
    command -v noctalia >/dev/null 2>&1 && noctalia config validate 2>&1
    echo "### memory"; free -h 2>/dev/null; cat /proc/pressure/memory 2>/dev/null
} >"$WORK/doctor-report.txt" 2>&1
journalctl -b --no-pager >"$WORK/journal-full.txt" 2>&1
journalctl -b -1 -p err --no-pager >"$WORK/journal-prev-errors.txt" 2>&1
dmesg >"$WORK/dmesg.txt" 2>&1
{ command -v lspci >/dev/null 2>&1 && lspci; echo ---; command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L; command -v sensors >/dev/null 2>&1 && sensors; } >"$WORK/hardware.txt" 2>&1
{ ip route; echo ---; getent hosts nixos.org; echo ---; nmcli device status 2>/dev/null; } >"$WORK/network.txt" 2>&1

if ! tar -czf "$OUT" -C "$WORK" . 2>/dev/null; then
    rm -f "$OUT"
    echo "bundle: archive creation failed" >&2
    exit 2
fi
echo "bundle: $OUT"
echo "WARNING: review before sharing — journals may contain hostnames, IPs, usernames. Never includes /var/lib secrets, keys, or shell history (not collected)."
