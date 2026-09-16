#!/usr/bin/env bash
# nixos-doctor TUI — numbered menu, tick fixes, per-item confirm.
# No dialog/whiptail deps: manual read loop + python3 (--json parsing).
set -u -o pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
DOCTOR="$SELF_DIR/nixos-doctor"
# Reuse first_cmd() extraction (fix strings carry human suffixes).
# shellcheck disable=SC1090
. "$SELF_DIR/nixos-doctor"
AREAS="boot secureboot systemd nix generations store services journal hardware network audio graphics gaming hyprland kde dms power time disk memory flake home secrets containers security updates bootperf rebuild backups"

run_area_json() { "$DOCTOR" "$1" --json 2>/dev/null; }

menu() {
    echo "== nixos-doctor interactive =="
    echo " 0) EVERYTHING (full sweep first)"
    i=1
    for a in $AREAS; do printf '%2d) %s\n' "$i" "$a"; i=$((i+1)); done
    echo "  b) write log bundle for AI review"
    echo "  q) quit"
}

apply_fixes() { # apply_fixes <area>
    area="$1"
    if ! data=$(run_area_json "$area"); then
        echo "could not inspect $area; the check failed to run." >&2
        return 2
    fi
    mapfile -t lines < <(printf '%s' "$data" | python3 -c "
import base64,json,sys
d=json.load(sys.stdin)
for i,f in enumerate([x for x in d['findings'] if x['severity'] in ('WARN','FAIL','ERROR') and x['fix']]):
    fields=(str(i),f['severity'],f['message'][:80],f['fix'],f.get('fix_id','legacy'),json.dumps(f.get('fix_args',[])))
    print('\t'.join(base64.b64encode(x.encode()).decode() for x in fields))")
    if [ "${#lines[@]}" -eq 0 ]; then echo "nothing actionable in $area."; return 0; fi
    i=1
    for line in "${lines[@]}"; do
        IFS=$'\t' read -r _ sev msg_b64 fix_b64 _ fix_args_b64 <<<"$line"
        msg=$(printf '%s' "$msg_b64" | base64 -d)
        fix=$(printf '%s' "$fix_b64" | base64 -d)
        printf '%d) [%s] %s\n   fix: %s\n' "$i" "$sev" "$msg" "$fix"
        i=$((i+1))
    done
    printf 'pick numbers (space-separated) or Enter to skip: '
    read -r picks || return 0
    for p in $picks; do
        # digits only and >= 1 (index 0 would wrap to the last element).
        case "$p" in ''|*[!0-9]*|0) continue ;; esac
        [ "$p" -le "${#lines[@]}" ] || { echo "selection out of range: $p" >&2; continue; }
        line="${lines[$((p-1))]}"
        [ -z "$line" ] && continue
        IFS=$'\t' read -r _ _ _ fix_b64 fix_id fix_args_b64 <<<"$line"
        fix=$(printf '%s' "$fix_b64" | base64 -d)
        if [ "$fix_id" = legacy ] || [ -z "$fix_id" ]; then
            printf 'Manual action (not executed by TUI): %s\n' "$fix"
            continue
        fi
        mapfile -t fix_args < <(printf '%s' "$fix_args_b64" | base64 -d | python3 -c 'import json,sys; print(*json.load(sys.stdin),sep="\n")')
        printf 'Run: %s ? [y/N] ' "$fix"
        read -r yn || continue
        case "$yn" in y|Y|yes|YES) ;; *) continue ;; esac
        run_fix "$fix_id" "${fix_args[@]}" 2>&1 | tail -5
        rc=${PIPESTATUS[0]}
        audit "$fix_id $fix (rc=$rc)" || true
        [ "$rc" -eq 0 ] && echo "fix applied" || echo "fix failed (exit $rc)" >&2
    done
    echo "--- re-checking $area ---"
    "$DOCTOR" "$area"
}

[ -t 0 ] || { echo "interactive needs a TTY" >&2; exit 2; }
while true; do
    menu
    printf '> '
    read -r choice || break
    case "$choice" in
        q|Q) break ;;
        b|B) "$SELF_DIR/bundle.sh"; continue ;;
        0) "$DOCTOR"; continue ;;
        ''|*[!0-9]*) echo "pick a number"; continue ;;
    esac
    area=$(printf '%s\n' $AREAS | sed -n "${choice}p")
    [ -z "$area" ] && { echo "out of range"; continue; }
    "$DOCTOR" "$area"
    apply_fixes "$area"
done
