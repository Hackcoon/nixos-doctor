#!/usr/bin/env bash
# nixos-doctor self-tests. No root or network; uses temporary fixtures.
# Run: ./tests.sh
set -u
D="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
pass=0; fail=0
ok() { pass=$((pass+1)); echo "ok: $1"; }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }
cleanup() { rm -rf "$D/.test-bin" "$D/.test-link" "$D/.test-hw" "$D/.test-bin-cap" "$D/.test-bin-failure" "$D/.test-secureboot" "$D/.test-systemd" "$D/.test-nix" "$D/.test-noctalia"; }
trap cleanup EXIT HUP INT TERM

# Backup dry-run is isolated from the real machine and uses only an allowlist.
backup_repo=$(mktemp -d)
mkdir -p "$backup_repo/source" "$backup_repo/home"
printf 'system.stateVersion = "26.05";\n' >"$backup_repo/source/configuration.nix"
if NIXOS_DOCTOR_BACKUP_REPO="$backup_repo/repo" NIXOS_DOCTOR_NIXOS_ROOT="$backup_repo/source" HOME="$backup_repo/home" "$D/backup.sh" --dry-run >/dev/null 2>&1; then
    ok "backup-dry-run"
else
    bad "backup-dry-run"
fi
rm -rf "$backup_repo/repo"
if NIXOS_DOCTOR_BACKUP_REPO="$backup_repo/repo" NIXOS_DOCTOR_NIXOS_ROOT="$backup_repo/source" HOME="$backup_repo/home" "$D/backup.sh" >/dev/null 2>&1 && [ -f "$backup_repo/repo/.git/HEAD" ] && git -C "$backup_repo/repo" ls-files | grep -q '^etc/nixos/configuration.nix$'; then
    ok "backup-local-commit"
else
    bad "backup-local-commit"
fi
printf 'api_key = "do-not-commit"\n' >"$backup_repo/source/secret.nix"
if NIXOS_DOCTOR_BACKUP_REPO="$backup_repo/repo" NIXOS_DOCTOR_NIXOS_ROOT="$backup_repo/source" HOME="$backup_repo/home" "$D/backup.sh" --dry-run >/dev/null 2>&1; then
    bad "backup-secret-rejection"
else
    ok "backup-secret-rejection"
fi
rm -rf "$backup_repo"

for f in "$D/nixos-doctor" "$D/tui.sh" "$D/bundle.sh" "$D/checks/"*.sh "$D/tests.sh"; do
    bash -n "$f" 2>/dev/null && ok "syntax $(basename "$f")" || bad "syntax $(basename "$f")"
done

# engine rejects unknown areas with a useful error status
unknown_out=$(mktemp)
if "$D/nixos-doctor" nosucharea >"$unknown_out" 2>&1; then
    bad "unknown-area"
elif grep -q "unknown area" "$unknown_out"; then
    ok "unknown-area"
else
    bad "unknown-area"
fi
rm -f "$unknown_out"

# --json v2 is valid JSON with report metadata and matching summary counts
"$D/nixos-doctor" generations home kde gaming disk --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
s=d['summary']
assert s['pass']+s['warn']+s['fail']+s['skip']+s['error']+s['unknown']==len(d['findings']), 'count mismatch'
assert set(d.keys())>={'tool','version','summary','findings'}
assert d['schema_version']==2
assert len(d['report_id'])==64 and len(d['identity']['host_hash'])==64
assert len(d['identity']['generation_hash'])==64
assert 'generated_at' in d
assert all({'severity','area','check','scope','confidence','reason','requires','message','fix','fix_id','fix_args','evidence'} <= set(f) for f in d['findings'])
assert all((not f['evidence']['available']) or (f['evidence']['exit_code'] is not None and len(f['evidence']['output']) <= 4096) for f in d['findings'])
print('json-ok')" >/dev/null 2>&1 && ok "json-schema" || bad "json-schema"

# Schema v1 remains available for older report consumers.
"$D/nixos-doctor" generations --json-v1 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['schema_version']==1
assert 'report_id' not in d and 'identity' not in d
print('json-v1-ok')" >/dev/null 2>&1 && ok "json-v1-compat" || bad "json-v1-compat"

# Evidence is bounded and JSON-safe for quotes, backslashes, newlines, and
# output larger than the 4096-byte limit.
. "$D/nixos-doctor"
# shellcheck disable=SC2034
JSON=1; JSON_ITEMS=""; PASS_N=0; WARN_N=0; FAIL_N=0; SKIP_N=0; ERROR_N=0; UNKNOWN_N=0
: "$JSON" "$PASS_N" "$WARN_N" "$FAIL_N" "$SKIP_N" "$ERROR_N" "$UNKNOWN_N"
long_output=$(printf '"quoted"\\path\n%*s' 5000 '')
finding_observed PASS evidence evidence.fixture system high "fixture command succeeded" fixture "evidence fixture" "fixture --quoted" 0 "$long_output" fixture
python3 -c 'import json,sys; f=json.loads(sys.argv[1])[0]; assert f["evidence"]["available"]; assert len(f["evidence"]["output"]) <= 4096; assert "quoted" in f["evidence"]["output"]; print("evidence-ok")' "[$JSON_ITEMS]" >/dev/null 2>&1 && ok "evidence-bounded" || bad "evidence-bounded"

# Missing capabilities are explicit skips, not false healthy results.
mkdir -p "$D/.test-bin-cap"
cat >"$D/.test-bin-cap/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$D/.test-bin-cap/systemctl"
out=$(PATH="$D/.test-bin-cap:$PATH" "$D/nixos-doctor" audio --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert any(f['severity']=='SKIP' and 'user systemd session unavailable' in f['message'] for f in d['findings'])
row=next(f for f in d['findings'] if f['severity']=='SKIP')
assert row['check']=='audio.user_bus' and row['scope']=='user' and row['confidence']=='high'
assert 'systemctl' in row['requires'] and row['reason']
print('capability-skip-ok')")
[ "$out" = "capability-skip-ok" ] && ok "capability-skip" || bad "capability-skip (got: $out)"
rm -rf "$D/.test-bin-cap"

# A failed measurement must not be emitted as PASS.
mkdir -p "$D/.test-bin-failure"
cat >"$D/.test-bin-failure/df" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$D/.test-bin-failure/df"
out=$(PATH="$D/.test-bin-failure:$PATH" "$D/nixos-doctor" rebuild --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert any(f['severity']=='ERROR' and 'free space' in f['message'] for f in d['findings'])
row=next(f for f in d['findings'] if f['severity']=='ERROR')
assert row['check']=='rebuild.tmp_space' and row['reason']
assert not any(f['severity']=='PASS' and 'headroom' in f['message'] for f in d['findings'])
print('failure-state-ok')")
[ "$out" = "failure-state-ok" ] && ok "failure-state" || bad "failure-state (got: $out)"
rm -rf "$D/.test-bin-failure"

# Secure Boot is explicitly not applicable outside UEFI.
mkdir -p "$D/.test-secureboot/config"
out=$(NIXOS_DOCTOR_EFI_ROOT="$D/.test-secureboot/no-efi" NIXOS_DOCTOR_FLAKE_ROOT="$D/.test-secureboot/config" "$D/nixos-doctor" secureboot --json 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin)['findings']
assert len(rows)==1, rows
assert rows[0]['severity']=='SKIP' and rows[0]['check']=='secureboot.uefi', rows
print('secureboot-bios-ok')")
[ "$out" = "secureboot-bios-ok" ] && ok "secureboot-bios" || bad "secureboot-bios (got: $out)"

# UEFI without optional tooling remains diagnosable and reports limitations.
mkdir -p "$D/.test-secureboot/min-bin" "$D/.test-secureboot/efi/efivars"
for cmd in bash find grep awk sed tr df readlink id dirname; do
    path=$(command -v "$cmd" 2>/dev/null || true)
    [ -n "$path" ] && ln -sf "$path" "$D/.test-secureboot/min-bin/$cmd"
done
out=$(PATH="$D/.test-secureboot/min-bin" NIXOS_DOCTOR_EFI_ROOT="$D/.test-secureboot/efi" NIXOS_DOCTOR_FLAKE_ROOT="$D/.test-secureboot/config" "$D/nixos-doctor" secureboot --json 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin)['findings']
assert any(f['severity']=='SKIP' and f['check']=='secureboot.firmware_state' for f in rows), rows
assert any(f['severity']=='SKIP' and f['check']=='secureboot.signatures' for f in rows), rows
assert any(f['severity']=='SKIP' and f['check']=='secureboot.boot_order' for f in rows), rows
print('secureboot-missing-tools-ok')")
[ "$out" = "secureboot-missing-tools-ok" ] && ok "secureboot-missing-tools" || bad "secureboot-missing-tools (got: $out)"

# Signed-artifact verification distinguishes unsigned output from tool failure.
mkdir -p "$D/.test-secureboot/bin" "$D/.test-secureboot/efi/efivars" "$D/.test-secureboot/esp"
cat >"$D/.test-secureboot/bin/bootctl" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = status ]; then
    printf '%s\n' 'Secure Boot: enabled (user)' 'Current Boot Loader:' '       Product: systemd-boot 260' ' Current Entry: nixos-generation-1.efi' 'Current Stub:' '      Product: lanzastub 1.1.0'
else
    printf '%s\n' 'title: NixOS' 'id: nixos-generation-1.efi'
fi
EOF
cat >"$D/.test-secureboot/bin/sudo" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -n ] && shift
exec "$@"
EOF
cat >"$D/.test-secureboot/bin/sbctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  status) echo 'Secure Boot: Enabled' ;;
  verify) echo '/boot/EFI/Linux/nixos.efi is not signed'; exit 1 ;;
esac
EOF
chmod +x "$D/.test-secureboot/bin/"*
printf 'boot.lanzaboote.enable = true;\n' >"$D/.test-secureboot/config/boot.nix"
out=$(PATH="$D/.test-secureboot/bin:$PATH" NIXOS_DOCTOR_EFI_ROOT="$D/.test-secureboot/efi" NIXOS_DOCTOR_ESP="$D/.test-secureboot/esp" NIXOS_DOCTOR_FLAKE_ROOT="$D/.test-secureboot/config" "$D/nixos-doctor" secureboot --sudo --json 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin)['findings']
assert any(f['severity']=='PASS' and f['check']=='secureboot.firmware_state' for f in rows), rows
assert any(f['severity']=='FAIL' and f['check']=='secureboot.signatures' for f in rows), rows
assert not any(f['severity']=='PASS' and f['check']=='secureboot.signatures' for f in rows), rows
print('secureboot-unsigned-ok')")
[ "$out" = "secureboot-unsigned-ok" ] && ok "secureboot-unsigned" || bad "secureboot-unsigned (got: $out)"

cat >"$D/.test-secureboot/bin/sbctl" <<'EOF'
#!/usr/bin/env bash
[ "$1" = status ] && { echo 'Secure Boot: Enabled'; exit 0; }
echo 'could not read files database' >&2
exit 2
EOF
chmod +x "$D/.test-secureboot/bin/sbctl"
out=$(PATH="$D/.test-secureboot/bin:$PATH" NIXOS_DOCTOR_EFI_ROOT="$D/.test-secureboot/efi" NIXOS_DOCTOR_ESP="$D/.test-secureboot/esp" NIXOS_DOCTOR_FLAKE_ROOT="$D/.test-secureboot/config" "$D/nixos-doctor" secureboot --sudo --json 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin)['findings']
assert any(f['severity']=='ERROR' and f['check']=='secureboot.signatures' for f in rows), rows
assert not any(f['severity']=='PASS' and f['check']=='secureboot.signatures' for f in rows), rows
print('secureboot-verify-failure-ok')")
[ "$out" = "secureboot-verify-failure-ok" ] && ok "secureboot-verify-failure" || bad "secureboot-verify-failure (got: $out)"

# Static configuration detection must not report disabled Lanzaboote as healthy.
printf 'boot.lanzaboote.enable = false;\nboot.loader.grub.enable = true;\n' >"$D/.test-secureboot/config/boot.nix"
cat >"$D/.test-secureboot/bin/bootctl" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = status ]; then
    printf '%s\n' 'Secure Boot: enabled (user)' 'Current Boot Loader:' '       Product: GRUB 2.12' ' Current Entry: grub.conf'
else
    printf '%s\n' 'title: NixOS via GRUB' 'id: grub'
fi
EOF
chmod +x "$D/.test-secureboot/bin/bootctl"
printf 'x' >"$D/.test-secureboot/efi/efivars/SecureBoot-test"
out=$(PATH="$D/.test-secureboot/bin:$PATH" NIXOS_DOCTOR_EFI_ROOT="$D/.test-secureboot/efi" NIXOS_DOCTOR_ESP="$D/.test-secureboot/esp" NIXOS_DOCTOR_FLAKE_ROOT="$D/.test-secureboot/config" "$D/nixos-doctor" secureboot --json 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin)['findings']
assert any(f['severity']=='PASS' and f['check']=='secureboot.bootloader' and 'GRUB' in f['message'] for f in rows), rows
assert any(f['severity']=='WARN' and f['check']=='secureboot.lanzaboote' and 'disabled' in f['message'] for f in rows), rows
assert not any(f['severity']=='PASS' and f['check']=='secureboot.lanzaboote' for f in rows), rows
assert any(f['severity']=='PASS' and f['check']=='secureboot.efivars' for f in rows), rows
print('secureboot-grub-ok')")
[ "$out" = "secureboot-grub-ok" ] && ok "secureboot-grub" || bad "secureboot-grub (got: $out)"
rm -rf "$D/.test-secureboot"

# Systemd diagnostics keep system/user scopes and timer state separate.
mkdir -p "$D/.test-systemd/bin"
cat >"$D/.test-systemd/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
user=0
if [ "$1" = --user ]; then user=1; shift; fi
case "$*" in
  "is-system-running") echo running ;;
  "--failed --type=service --no-legend --plain") [ "$user" = 1 ] && echo 'broken-user.service loaded failed failed x' || echo 'broken.service loaded failed failed x' ;;
  "list-jobs --no-legend") echo '12 start waiting broken.service' ;;
  "list-timers --all --no-legend --no-pager") echo '- - - - missed.timer' ;;
  "show broken.service -p LoadState -p ActiveState -p SubState -p Result -p NRestarts") printf 'LoadState=loaded\nActiveState=failed\nSubState=failed\nResult=exit-code\nNRestarts=4\n' ;;
  "show broken-user.service -p LoadState -p ActiveState -p SubState -p Result -p NRestarts") printf 'LoadState=loaded\nActiveState=failed\nSubState=failed\nResult=exit-code\nNRestarts=2\n' ;;
  "list-unit-files systemd-oomd.service") echo systemd-oomd.service enabled ;;
  "is-active systemd-oomd.service") echo active ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$D/.test-systemd/bin/systemctl"
out=$(PATH="$D/.test-systemd/bin:$PATH" DBUS_SESSION_BUS_ADDRESS=test "$D/nixos-doctor" systemd --json 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin)['findings']
assert any('failed system unit' in f['message'] for f in rows), rows
assert any('failed user unit' in f['message'] for f in rows), rows
assert any('jobs present' in f['message'] for f in rows), rows
assert any('no recorded' in f['message'] for f in rows), rows
print('systemd-ok')")
[ "$out" = "systemd-ok" ] && ok "systemd-diagnostics" || bad "systemd-diagnostics (got: $out)"
rm -rf "$D/.test-systemd"

# Nix correlation reports revision/lock state and handles read-only validation failures.
mkdir -p "$D/.test-nix/config/.git" "$D/.test-nix/bin"
printf '{"revision":"abcdef1234567890"}\n' >"$D/.test-nix/config/flake.lock"
printf '{}\n' >"$D/.test-nix/config/flake.nix"
cat >"$D/.test-nix/bin/nix" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "flake metadata --json "*) echo '{"revision":"abcdef1234567890"}' ;;
  *"flake check --no-build"*) echo 'evaluation failed at configuration.nix:2' >&2; exit 1 ;;
  *) exit 0 ;;
esac
EOF
cat >"$D/.test-nix/bin/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"rev-parse --short HEAD"*) echo abcdef1 ;;
  *"status --porcelain"*) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$D/.test-nix/bin/"*
out=$(PATH="$D/.test-nix/bin:$PATH" NIXOS_DOCTOR_FLAKE_ROOT="$D/.test-nix/config" "$D/nixos-doctor" nix --deep --json 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin)['findings']
assert any('flake revision' in f['message'] for f in rows), rows
assert any(f['severity']=='ERROR' and f['check']=='nix.flake_check' for f in rows), rows
print('nix-correlation-ok')")
[ "$out" = "nix-correlation-ok" ] && ok "nix-correlation" || bad "nix-correlation (got: $out)"
rm -rf "$D/.test-nix"

# Optional Noctalia integration consumes its stable CLI validation interface.
mkdir -p "$D/.test-noctalia/bin"
cat >"$D/.test-noctalia/bin/noctalia" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "--version") echo 'noctalia v5.1.0' ;;
  "config validate") echo 'configuration valid' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$D/.test-noctalia/bin/noctalia"
out=$(PATH="$D/.test-noctalia/bin:$PATH" "$D/nixos-doctor" noctalia --json 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin)['findings']
assert any(f['severity']=='PASS' and 'v5.1.0' in f['message'] for f in rows), rows
assert any(f['severity']=='PASS' and 'configuration valid' in f['message'] for f in rows), rows
print('noctalia-ok')")
[ "$out" = "noctalia-ok" ] && ok "noctalia-integration" || bad "noctalia-integration (got: $out)"
rm -rf "$D/.test-noctalia"

# Vendor detection must not produce an NVIDIA warning on AMD hardware.
mkdir -p "$D/.test-bin-gpu"
cat >"$D/.test-bin-gpu/lspci" <<'EOF'
#!/usr/bin/env bash
echo '03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Radeon RX 6800'
EOF
cat >"$D/.test-bin-gpu/lsmod" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$D/.test-bin-gpu/"*
out=$(PATH="$D/.test-bin-gpu:$PATH" SMART_DEVS='' "$D/nixos-doctor" hardware --json 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin)['findings']
assert any(f['severity']=='PASS' and 'AMD GPU detected' in f['message'] for f in rows), rows
assert not any('nvidia' in f['message'].lower() and f['severity'] in ('WARN','FAIL') for f in rows), rows
print('amd-applicability-ok')")
[ "$out" = "amd-applicability-ok" ] && ok "amd-applicability" || bad "amd-applicability (got: $out)"
rm -rf "$D/.test-bin-gpu"

# Journal and time command failures are errors, not healthy/unsynced guesses.
mkdir -p "$D/.test-bin-failure"
for cmd in journalctl timedatectl; do
    printf '#!/usr/bin/env bash\nexit 1\n' >"$D/.test-bin-failure/$cmd"
    chmod +x "$D/.test-bin-failure/$cmd"
done
out=$(PATH="$D/.test-bin-failure:$PATH" "$D/nixos-doctor" journal time --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); rows=d['findings']
assert any(f['severity']=='ERROR' and f['check']=='journal.current_errors' for f in rows)
assert any(f['severity']=='ERROR' and f['check']=='time.ntp' for f in rows)
assert not any(f['severity']=='PASS' and 'no errors this boot' in f['message'] for f in rows)
print('query-failure-ok')")
[ "$out" = "query-failure-ok" ] && ok "query-failure" || bad "query-failure (got: $out)"
rm -rf "$D/.test-bin-failure"

# Disk kernel-journal failure must not become a clean-filesystem PASS.
mkdir -p "$D/.test-bin-failure"
cat >"$D/.test-bin-failure/journalctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$D/.test-bin-failure/journalctl"
out=$(PATH="$D/.test-bin-failure:$PATH" "$D/nixos-doctor" disk --json 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin)['findings']
assert any(f['severity']=='ERROR' and f['check']=='disk.kernel_errors' for f in rows)
assert not any(f['severity']=='PASS' and 'no filesystem errors' in f['message'] for f in rows)
print('disk-journal-failure-ok')")
[ "$out" = "disk-journal-failure-ok" ] && ok "disk-journal-failure" || bad "disk-journal-failure (got: $out)"
rm -rf "$D/.test-bin-failure"

# services collapse: fixture with 3 identical transient failures -> 1 finding
mkdir -p "$D/.test-bin"
cat >"$D/.test-bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "--failed" ]; then
    printf '● a@1-2.service loaded failed failed x\n● a@3-4.service loaded failed failed x\n● b.service loaded failed failed y\n'
elif [ "$1" = "is-system-running" ]; then echo running
elif [ "$1" = "list-timers" ]; then echo "x"
else exit 1; fi
EOF
chmod +x "$D/.test-bin/systemctl"
out=$(PATH="$D/.test-bin:$PATH" "$D/nixos-doctor" services --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
rows=[(f['severity'],f['message']) for f in d['findings']]
a=[m for s,m in rows if 'a@.service' in m]
b=[m for s,m in rows if m.endswith('b.service')]
assert len(a)==1 and '×2' in a[0], rows
assert len(b)==1, rows
print('collapse-ok')")
[ "$out" = "collapse-ok" ] && ok "transient-collapse" || bad "transient-collapse (got: $out)"

# hyprland area skips cleanly outside Hyprland sessions
"$D/nixos-doctor" hyprland --json 2>/dev/null | python3 -c "
import json,sys,os
assert 'HYPRLAND_INSTANCE_SIGNATURE' not in os.environ
d=json.load(sys.stdin)
assert any(f['severity']=='SKIP' for f in d['findings']), d['findings']
print('hypr-skip-ok')" >/dev/null 2>&1 && ok "hyprland-skip" || bad "hyprland-skip"

# DMS integration consumes the structured dms doctor interface.
cat >"$D/.test-bin/dms" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = doctor ] && [ "$2" = --json ]; then
    printf '%s\n' '{"results":[{"category":"Services","name":"dms.service","status":"ok","message":"active"},{"category":"Environment","name":"XDG_MENU_PREFIX","status":"warn","message":"Not set","details":"set it","url":"https://example.test"},{"category":"Config","name":"settings.json","status":"error","message":"broken"}]}'
else
    exit 1
fi
EOF
chmod +x "$D/.test-bin/dms"
out=$(PATH="$D/.test-bin:$PATH" "$D/nixos-doctor" dms --json 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin)['findings']
assert any(f['severity']=='PASS' and 'dms.service' in f['message'] for f in rows)
assert any(f['severity']=='WARN' and 'XDG_MENU_PREFIX' in f['message'] for f in rows)
assert any(f['severity']=='FAIL' and 'settings.json' in f['message'] for f in rows)
print('dms-ok')")
[ "$out" = "dms-ok" ] && ok "dms-doctor-integration" || bad "dms-doctor-integration (got: $out)"

# engine pure functions (sourcing runs nothing thanks to the main guard)
. "$D/nixos-doctor"
tier1_allowed "journalctl --vacuum-size=500M" && ok "tier1-vacuum" || bad "tier1-vacuum"
tier1_allowed "systemctl --user reset-failed 'a@.service'" && ok "tier1-reset" || bad "tier1-reset"
tier1_allowed "nixos-rebuild switch" && bad "tier1-rebuild-denied" || ok "tier1-rebuild-denied"
tier1_allowed "systemctl --user restart nginx.service" && ok "tier1-restart-ok" || bad "tier1-restart-ok"
tier1_allowed "systemctl restart sddm.service" && bad "tier1-sddm-denied" || ok "tier1-sddm-denied"
tier1_allowed "nix-collect-garbage -d" && bad "tier1-gc-d-denied" || ok "tier1-gc-d-denied"
[ "$(first_cmd "journalctl --vacuum-size=500M (Tier 1)")" = "journalctl --vacuum-size=500M" ] && ok "firstcmd-strip" || bad "firstcmd-strip"
[ "$(first_cmd "systemctl restart x (Tier 1) · systemctl status x")" = "systemctl restart x" ] && ok "firstcmd-alt" || bad "firstcmd-alt"

# help system
"$D/nixos-doctor" --help 2>&1 | grep -q "^Usage:" && ok "help-usage" || bad "help-usage"
"$D/nixos-doctor" help store 2>&1 | grep -q "closure\|GC roots" && ok "help-area" || bad "help-area"
"$D/nixos-doctor" help fix-safe 2>&1 | grep -q "Tier-1" && ok "help-flag" || bad "help-flag"
"$D/nixos-doctor" help nosuchtopic >/dev/null 2>&1; [ "$?" = 2 ] && ok "help-unknown" || bad "help-unknown"

# symlinked invocation resolves checks next to the real file, not the link
mkdir -p "$D/.test-link"
ln -sf "$D/nixos-doctor" "$D/.test-link/nixos-doctor"
"$D/.test-link/nixos-doctor" generations --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert len(d['findings'])>0, 'no checks ran via symlink'
print('link-ok')" >/dev/null 2>&1 && ok "symlink-run" || bad "symlink-run"

# SMART parsing fixtures (fake sudo + smartctl, fake disk list)
mkdir -p "$D/.test-hw"
cat >"$D/.test-hw/sudo" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-n" ] && shift
exec "$@"
EOF
chmod +x "$D/.test-hw/sudo"
smart_fixture() { # smart_fixture <health-line> <used-pct> <spare-pct>
    cat >"$D/.test-hw/smartctl" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-H" ]; then echo "$1"; else
printf 'Percentage Used:                    %s%%\nAvailable Spare:                    %s%%\n' "$2" "$3"; fi
EOF
    chmod +x "$D/.test-hw/smartctl"
}
smart_fixture "SMART overall-health self-assessment test result: PASSED" 12 100
SMART_DEVS="fakedev" PATH="$D/.test-hw:$PATH" "$D/nixos-doctor" hardware --json --sudo 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
msgs=[f['message'] for f in d['findings']]
assert any('SMART health ok' in m for m in msgs), msgs
print('smart-ok')" >/dev/null 2>&1 && ok "smart-healthy" || bad "smart-healthy"
smart_fixture "SMART overall-health self-assessment test result: FAILED" 95 5
SMART_DEVS="fakedev" PATH="$D/.test-hw:$PATH" "$D/nixos-doctor" hardware --json --sudo 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
sevs=[(f['severity'],f['message']) for f in d['findings']]
assert any(s=='FAIL' and 'SMART health bad' in m for s,m in sevs), sevs
assert any(s=='WARN' and 'worn' in m for s,m in sevs), sevs
assert any(s=='WARN' and 'spare' in m for s,m in sevs), sevs
print('smart-sick-ok')" >/dev/null 2>&1 && ok "smart-sick" || bad "smart-sick"
cat >"$D/.test-hw/smartctl" <<'EOF'
#!/usr/bin/env bash
echo "SMART support is: Unavailable" >&2
exit 2
EOF
chmod +x "$D/.test-hw/smartctl"
SMART_DEVS="fakedev" PATH="$D/.test-hw:$PATH" "$D/nixos-doctor" hardware --json --sudo 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); rows=d['findings']
assert any(f['severity']=='SKIP' and 'unsupported' in f['reason'].lower() for f in rows), rows
assert not any(f['severity']=='FAIL' and 'SMART health bad' in f['message'] for f in rows), rows
print('smart-unsupported-ok')" >/dev/null 2>&1 && ok "smart-unsupported" || bad "smart-unsupported"
cat >"$D/.test-hw/smartctl" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-H" ]; then
    echo "SMART overall-health self-assessment test result: PASSED"
    exit 2
fi
exit 0
EOF
chmod +x "$D/.test-hw/smartctl"
SMART_DEVS="fakedev" PATH="$D/.test-hw:$PATH" "$D/nixos-doctor" hardware --json --sudo 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin)['findings']
assert any(f['severity']=='ERROR' and f['check']=='hardware.smart' for f in rows), rows
assert not any(f['severity']=='PASS' and f['message']=='SMART health ok' for f in rows), rows
print('smart-exit-status-ok')" >/dev/null 2>&1 && ok "smart-exit-status" || bad "smart-exit-status"

out=$("$D/bundle.sh" 2>/dev/null | grep -oE "/tmp/nixos-doctor-.*\.tar\.gz")
if [ -n "$out" ] && tar -tzf "$out" 2>/dev/null | grep -q "doctor-report.txt"; then
    ok "bundle-manifest"
else
    bad "bundle-manifest"
fi
rm -f "$out"

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
