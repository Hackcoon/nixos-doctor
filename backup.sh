#!/usr/bin/env bash
# nixos-doctor backup — explicit, local-first Git backup of configuration.
set -u -o pipefail

usage() {
    cat <<'EOF'
Usage: nixos-doctor backup [options]

Options:
  --dry-run          list files and secret findings; do not write Git data
  --push             push the committed snapshot to the existing origin remote
  --repo DIR         backup repository (default: ~/.local/share/nixos-doctor-backup)
  --help             show this help

The default source allowlist contains NixOS .nix files/flake.lock and selected
shell, Mango, and DMS configuration files. Secrets, credentials, private keys,
and environment files are rejected. Review the list before using --push.
EOF
}

DRY_RUN=0
PUSH=0
REPO="${NIXOS_DOCTOR_BACKUP_REPO:-${HOME:-/tmp}/.local/share/nixos-doctor-backup}"
NIXOS_ROOT="${NIXOS_DOCTOR_NIXOS_ROOT:-/etc/nixos}"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --push) PUSH=1 ;;
        --repo) shift; [ "$#" -gt 0 ] || { echo "backup: --repo needs a directory" >&2; exit 2; }; REPO="$1" ;;
        --help|-h) usage; exit 0 ;;
        *) echo "backup: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if ! command -v git >/dev/null 2>&1; then
    echo "backup: git is required" >&2
    exit 2
fi

umask 077
WORK=$(mktemp -d "${TMPDIR:-/tmp}/nixos-doctor-backup.XXXXXXXX") || {
    echo "backup: cannot create private staging directory" >&2
    exit 2
}
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT HUP INT TERM
mkdir -p "$WORK/etc/nixos" "$WORK/home"

copied=0
copy_file() {
    local src="$1" rel="$2"
    [ -f "$src" ] || return 0
    mkdir -p "$WORK/$(dirname "$rel")"
    cp -p -- "$src" "$WORK/$rel"
    printf '%s\n' "$rel"
    copied=$((copied+1))
}

if [ -d "$NIXOS_ROOT" ]; then
    while IFS= read -r -d '' src; do
        copy_file "$src" "etc/nixos/${src#"$NIXOS_ROOT"/}"
    done < <(find "$NIXOS_ROOT" -type f ! -path '*/.git/*' ! -name '*.bak*' \( -name '*.nix' -o -name 'flake.lock' \) -print0 2>/dev/null)
fi

if [ -n "${HOME:-}" ]; then
    for rel in .bashrc .profile .config/mango/config.conf \
        .config/DankMaterialShell/settings.json \
        .config/DankMaterialShell/plugin_settings.json; do
        copy_file "$HOME/$rel" "home/$rel"
    done
fi

if [ "$copied" -eq 0 ]; then
    echo "backup: no allowlisted files found" >&2
    exit 1
fi

printf 'backup: %d allowlisted file(s)\n' "$copied"
if ! secret_hits=$(grep -RInE --exclude='*.lock' \
    '(^|[^A-Za-z])(PRIVATE KEY|BEGIN RSA|BEGIN OPENSSH|api[_-]?key|access[_-]?token|secret[_-]?key|password[[:space:]]*[:=]|ghp_[A-Za-z0-9]|github_pat_|AKIA[0-9A-Z]{16})([^A-Za-z]|$)' \
    "$WORK" 2>/dev/null); then
    secret_hits=""
fi
if [ -n "$secret_hits" ]; then
    echo "backup: refusing to continue; secret-like content found:" >&2
    printf '%s\n' "$secret_hits" >&2
    echo "backup: remove it from the allowlist/source or use a secret manager" >&2
    exit 2
fi
if [ "$DRY_RUN" = 1 ]; then
    echo "backup: dry run; no repository changes made"
    exit 0
fi

mkdir -p "$REPO"
if [ ! -d "$REPO/.git" ]; then
    git -C "$REPO" init -q
fi
cp -a "$WORK/." "$REPO/"
git -C "$REPO" add -A
if git -C "$REPO" diff --cached --quiet; then
    echo "backup: no changes to commit"
else
    git -C "$REPO" -c user.name=nixos-doctor -c user.email=nixos-doctor@localhost \
        commit -q -m "backup: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "backup: committed snapshot in $REPO"
fi

if [ "$PUSH" = 1 ]; then
    if ! git -C "$REPO" remote get-url origin >/dev/null 2>&1; then
        echo "backup: --push requires an existing Git remote named origin" >&2
        exit 2
    fi
    echo "backup: pushing to configured origin; verify the repository is private"
    printf 'Type YES to push this snapshot: '
    read -r confirmation || exit 2
    [ "$confirmation" = YES ] || { echo "backup: push cancelled"; exit 0; }
    git -C "$REPO" push origin HEAD
fi
