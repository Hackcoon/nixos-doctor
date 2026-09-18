# nixos-doctor — Design Record and Roadmap

> Status: core implementation exists; packaging, CI, and ongoing hardening are tracked in `CHANGELOG.md`. What follows is the design record. The original reference target was a desktop NVIDIA system with
> mango + DMS, flake `/etc/nixos#nixos`, systemd-boot + Secure Boot on
> (**sbctl present** — custom keys, kernels must stay signed), **ext4**
> (no fs snapshots — rollback means boot-menu generations only),
> `auto-optimise-store=true`, GC via nh, Home Manager present.
> Treat hardware paths, versions, and services below as examples and adapt
> them to the machine under test.

Manual anchors used below (`https://nixos.org/manual/nixos/stable/`):
`#ch-troubleshooting` `#sec-nix-gc` `#sec-switching-systems`
`#sec-systemctl` `#sec-logging` `#sec-rebooting`
`#ch-system-state` `#ch-containers` `#sec-wayland`
`#sec-gpu-accel` `#sec-networking` `#sec-kernel-config`

## 1. Vision (unchanged)

One command answering "is my NixOS healthy, and if not, exactly
what do I run?" Three frontends (CLI sweep, `--interactive` menu,
`AI-RUNBOOK.md` + `--bundle`), one engine, **report-first**: nothing
mutates unless you pick the fix. New in v2: every check is tagged
`[U]` (runs as user) or `[R]` (needs root); `[R]` checks are skipped
with a note unless `--sudo` is passed, and sudo uses `-n` only —
the tool **never prompts for a password** (manual: Troubleshooting
recommends non-interactive, re-runnable diagnostics).

## 2. Frontends (v2 detail)

### 2a. CLI

```
nixos-doctor                        # full sweep, report only
nixos-doctor boot store services    # subset by area name
nixos-doctor --fix-safe             # + auto Tier 1
nixos-doctor --deep                 # + slow checks (store verify --all)
nixos-doctor --sudo                 # + [R] checks via sudo -n (skips if no NOPASSWD)
nixos-doctor --interactive          # TUI
nixos-doctor --bundle               # secure tarball; review before sharing
nixos-doctor backup --dry-run       # preview an allowlisted Git backup
nixos-doctor backup --push          # push an existing private remote after YES
```

Output: `[AREA] SEVERITY message → fix-description`. Exit 0/1/2
(pass/warn/fail). `--json` emits schema-v2 reports with stable
`fix_id`/`fix_args` fields; `--json-v1` preserves the previous top-level
contract for compatibility. `--watch` remains future work.

### 2b. TUI

Numbered bash menu (no dialog deps — must work on a broken box):
areas list, drill-in, findings, and confirmed structured Tier 1 fixes.
Legacy and Tier 2 fixes are displayed for manual execution only. Global keys:
`b` writes a bundle and `q` quits cleanly.

### 2c. AI pair (`AI-RUNBOOK.md` + bundle)

Runbook maps the current symptom set to checks (section 5). Bundle output
pairs with it. Secrets rule stands: the tool does not intentionally collect
`/var/lib/*/env`, sops/agenix material, shell history, browser
profiles, SSH keys; prints the reminder; never uploads.

## 3. Check catalog (32 areas, including DMS, Noctalia, Nix, systemd, and Secure Boot integrations)

Format: check — command [U/R] — trigger. Manual ref where one exists.

### 3.1 BOOT [U/R mix] (manual: bootloader + `#sec-rebooting`)
- Loader + entries exist: `bootctl status`, `/boot/loader/entries` [R for ESP read] — FAIL: none.
- EFI boot order sane (`efibootmgr` BootOrder points at NixOS entry) [R] — WARN otherwise.
- ESP free: `df /boot` [U] — WARN <100M, FAIL <30M (old kernels pile here).
- Booted vs current generation: `/run/booted-system` vs `/nix/var/nix/profiles/system` [U] — FAIL mismatch.
- Last-boot errors: `journalctl -b -1 -p err` count [U] — FAIL + top 5.
- Secure Boot + sbctl/lanzaboote state [U] — INFO (report-only zone).
- **`sbctl verify` all signed [R]** — FAIL on any unsigned kernel/initrd
  (post-update unbootable Secure Boot; fix = re-sign per wiki).
- Failed `switch` debris: `systemctl list-jobs` stuck, `/run/nixos/*` [U].

### 3.2 GENERATIONS [U]
- Count/age of system + user + home-manager profiles — WARN >20/>30d, FAIL >50.
- Closure size outliers: biggest 3 closures via `nix path-info -Sh` — INFO (feeds STORE).
- `nix-env --delete-generations` preview (`--dry-run` style count) — INFO.

### 3.3 STORE [U, verify R-optional]
- Size/disk pressure [U] — WARN >60G or `/` >80%.
- `nix store verify --all` — `--deep` only (78G is slow) — FAIL + repair cmd.
- `nix-store --optimise` dry-run savings [U] — INFO (auto-optimise is on; reports if off).
- GC roots audit: dead home-manager generations, deleted-flake dirs, `/result*` symlinks [U] — WARN + delete cmds.
- nh state: `nh clean` configured? last run? [U] — WARN if never.
- Daemon health: `nix-daemon` socket + `nix show-config` sanity (substituters reachable? `curl -sI cache` quick check) [U].

### 3.4 SERVICES [U/R]
- Failed units system+user [U] — FAIL each + restart/status cmds.
- Degraded boot: `systemctl is-system-running` [U].
- Key stack: mango-session.target, dms, display-manager/greetd, pipewire, NetworkManager [U].
- Enabled-but-dead + restart-loop detection (`NRestarts` via `systemctl show`) [U].
- Timer health: `systemctl list-timers --failed`, timers not run in 2× period [U].

### 3.5 JOURNAL [U]
- Error scan this boot, dedup by unit, top lines [U].
- Disk use [U] — WARN >1G + vacuum cmd.
- Coredumps 7d [U] — WARN per binary + `coredumpctl info` hint.
- Kernel taint + OOM kills: `dmesg | grep -i "taint\|oom-killer\|killed process"` [R, fallback: journal `-k`] — FAIL on OOM.

### 3.6 HARDWARE [U/R]
- NVIDIA: module loaded, `nvidia-smi -L`, driver vs kernel mismatch after update [U] — FAIL.
- VRAM pressure [U] — WARN >85%.
- Missing firmware in dmesg/journal [U] — WARN per device.
- CPU: governor, temp (`sensors` if present), throttling flags in dmesg [U].
- SMART short health every sweep [R] (seconds); NVMe Percentage
  Used / Available Spare + SATA wear attrs warn near end-of-life;
  long self-test stays manual. `SMART_DEVS` override for fixtures.
- Battery (UPower capacity <70% WARN) [U]; webcam/audio PCI presence [U].
- Firmware updates: `fwupdmgr get-updates` [U] — INFO only (manual step).

### 3.7 NETWORK [U]
- Link/carrier per iface, default route, DNS resolve (`getent hosts`), portal captive check [U].
- NetworkManager vs systemd-networkd conflict (both enabled) [U] — FAIL.
- Firewall: `nft list ruleset` count / `iptables -L` [R] — INFO + WARN if ssh open to world.
- Wi-Fi: signal %, disconnects in journal [U].
- VPN/tailscale/wireguard unit states if configured [U].

### 3.8 AUDIO/BLUETOOTH [U]
- pipewire + wireplumber active (user), sinks/sources listed [U] — FAIL with restart cmds.
- Bluetooth: adapter powered, recent disconnect storms [U].
- Camera/mic privacy: portal permission states — INFO.

### 3.9 GRAPHICS STACK [U] (manual: `#sec-wayland` `#sec-gpu-accel`)
- Compositor runs (mango pid), XWayland present iff X11 clients exist [U].
- GBM/EGL: `eglinfo`/`glxinfo` renderer string is NVIDIA (not llvmpipe!) [U] — FAIL software rendering.
- Explicit sync: `syncobj_enable` default-on note; tearing/VRR state via mmsg [U].
- Monitors: refresh/resolution vs EDID max, fractional scale cost note [U].
- mango config valid (`mango -p`), DMS units, cheatsheet row count [U].
- Portals all active (base, wlr, gtk — screenshare/clipboard need them) [U].
- XWayland clients flagged via mmsg (`is_xwayland`; expect vesktop,
  upscayl — both deliberately wrapped to X11) [U] — WARN surprises.
- Polkit auth agent present in mango sessions (none found 2026-09-11;
  daemon alone isn't enough) [U] — WARN with autostart fix.
- Greeter (dms-greeter/greetd) unit state [U]; cliphist `wl-paste --watch`
  guard running (exec-once is commented out here) [U].
- Session env sane (`XDG_CURRENT_DESKTOP`, `XDG_SESSION_TYPE=wayland`)
  inside mango sessions [U] — WARN if unset (breaks portals/file pickers).

### 3.10 POWER/SUSPEND [U/R]
- Power profile (power-profiles-daemon), governor [U].
- Suspend readiness: swap/zram present? (`zramctl`, swapfile) — WARN hibernate configured with no swap (will fail) [U].
- Last resume errors: journal `suspend|resume` errs [U].
- NVIDIA resume: `nvidia-suspend` service + preserve-video-memory [U].

### 3.11 TIME/LOCALE [U]
- NTP sync (`timedatectl`), RTC drift [U] — FAIL unsynced (breaks TLS/caches).
- Locale set + available, timezone matches GeoIP-ish expectation [U].

### 3.12 DISK/FS [U/R]
- Usage per mount, inode pressure [U].
- Root fstype detected (`findmnt`); per-fs error dialects in one
  kernel-log scan: generic I/O + remount-RO plus EXT4-fs / XFS /
  BTRFS checksum / ZFS pool keywords [U].
- `zpool status -x` when ZFS present [U]; btrfs `/.snapshots`
  presence flips the rollback story [U].
- Reserved-block share, ext4 only, root device auto-detected
  (`tune2fs`, root device auto-detected; never hardcode a block device) [R]
  — WARN with `tune2fs -m 1` cmd (Tier 2, data-safe).
- TRIM: `fstrim.timer` enabled (SSD) [U] — WARN if off.
- /tmp + /var/tmp size, stale crash dumps [U].

### 3.13 MEMORY [U]
- Pressure: `free`, PSI (`/proc/pressure/memory`) [U] — WARN full-avg high.
- zram/swap usage; earlyoom/systemd-oomd present? [U].
- Top RSS processes snapshot [U] — INFO for AI context.

### 3.14 FLAKE/CONFIG [U] (manual: `#sec-changing-config`)
- `/etc/nixos` git-dirty list [U] — WARN (unreproducible state).
- `flake.lock` age [U] — WARN >60d.
- Legacy channels set (`nix-channel --list` non-empty alongside flakes)
  [U] — WARN (channel/flake mixups cause "updated but nothing changed").
- `system.autoUpgrade` enabled? last run result [U] — INFO.
- nh clean configured? (`nh.clean` in config) stale `result*` links [U].
- `nix-instantiate --parse` on modules [U] — FAIL file:line.
- `nixos-rebuild dry-build` summary [U] — INFO what would change.
- `nixos-option` spot-checks for values the tool relies on [U].

### 3.15 HOME-MANAGER [U]
- `home.nix` present: last generation age, failed `home-manager switch` markers [U].
- Dangling `~/.nix-profile` vs system profile conflicts [U].

### 3.16 SECRETS-adjacent (metadata only, never contents)
- Referenced secret files exist + perms 0600 (`/var/lib/hermes/env` pattern from module grep) [R for stat] — FAIL missing/wide-open, never cat.
- sops-nix/agenix unit state if used [U].

### 3.17 CONTAINERS/VMs [U] (manual: `#ch-containers`)
- podman/docker/libvirt unit states, image disk hogs (`podman system df`) [U].
- Flatpak: unused runtimes (`flatpak uninstall --unused --dry-run`) [U].

### 3.18 SECURITY HYGIENE [U/R]
- Failed SSH logins spike (journal `sshd`) [U] — WARN.
- Firewall active? (see NETWORK) [R].
- AppArmor denials spike (`aa-status`, journal `apparmor=`) [U/R] — WARN with profile hint.
- World-writable dotfiles / `~/.ssh` perms [U].
- Pending CVE-relevant staleness: kernel vs latest in lock (flake inputs age) [U] — INFO.

### 3.19 UPDATES [U]
- `flake.lock` input lag vs upstream day-count (offline: mtime only) [U].
- `nixos-rebuild dry-build` package churn count [U] — INFO "47 package updates pending".
- Pending reboot: booted kernel/initrd vs current profile
  (`/run/booted-system` vs profile) [U] — WARN "rebuilt, not booted".
- fwupd pending [U] — INFO.

### 3.20 BOOT PERFORMANCE [U]
- `systemd-analyze` total + `blame` top 10 + `critical-chain` [U] — WARN units >5s with mask/disable hints (never auto).
- initrd size outliers [U].

### 3.21 REBUILD TRIAGE [U] (manual: `#sec-switching-systems`)
A failed `nixos-rebuild switch` is the #1 NixOS emergency; this area
exists for it (also wired into TUI as "I just broke my rebuild"):
- Eval failure: re-run with `--show-trace`, first error file:line [U] — FAIL with exact snippet.
- Build-time space: `/tmp` + `/nix/store` free vs estimated closure [U] — FAIL <5G free.
- Build OOM risk: RAM + current load vs `max-jobs`/`cores` (this box
  throttles to cores=2/max-jobs=1 — past OOM pain) [U] — WARN suggests
  `--option max-jobs 1 --option cores 2` retry cmd.
- Daemon/lock state: another rebuild running? (`/nix/var/nix/db/big-lock`) [U].
- Post-failure: system is untouched until `switch` succeeds (NixOS
  atomicity note) — report says so explicitly to stop panic.

### 3.22 BACKUPS [U]
- restic/borgbackup jobs configured? last snapshot age [U] — WARN
  **none configured on this box (2026-09-11)** with setup pointers.
- ext4 has no snapshots: rollback == boot-menu generations only —
  restated wherever Tier 2 runs.

The separate `nixos-doctor backup` command provides a local-first Git backup
for allowlisted NixOS and selected dotfiles. It is not part of a normal health
sweep and does not replace encrypted secret storage.

### 3.23 HYPRland [U] (second compositor on this box)
- Session-aware: SKIP cleanly when mango runs (pgrep + signature
  check); full checks only inside Hyprland sessions.
- hyprctl IPC responsive (monitors JSON parses) [U].
- Config files present (hyprland.lua, binds.lua) [U].
- configured quickshell shell alive under Hyprland [U].
- Log tail error scan (`~/.cache/hyprland/hyprland.log`) [U].
- Graphics area also gates: mango >= 0.14 (DMS bar IPC floor) and
  DMS settings.json parses.

### 3.24 KDE/PLASMA [U] (third session on this box)
- Session-aware SKIP (no plasmashell in mango/hyprland).
- greetd-vs-sddm seat ownership (kde.nix gates sddm off; FAIL both).
- baloo idle/churn (`balooctl[6]`, waiting-count based, no substring
  false-positives), akonadi running-but-broken only.
- Crash culprits via `coredumpctl -F COREDUMP_EXE` basenames (found:
  drkonqi's own launcher wrapper + quickshell on this box).

### 3.25 GAMING [U]
- Steam library + shadercache sizes (WARN >10G cache), custom Proton
  tools count, gamemode present?, mangohud present.

## 4. Fix tiers

- **Tier 0 report-only default.** Reads listed above.
- **Tier 1 safe-auto** (`--fix-safe` / TUI tick): `nix-collect-garbage`
  (no `-d` unprompted), `journalctl --vacuum-*`, `daemon-reload`,
  restarts of *normal* failed units, `fstrim` run, `flatpak
  uninstall --unused` (prompted — deletes), tmp cleanup, coredump
  prune, `fwupdmgr refresh` (metadata only).
- **Tier 2 manual-only**: rebuild/rollback/repair/`-d`/reboot,
  kernel/driver/firmware changes, bootloader writes, Secure Boot
  ops, firewall edits, NVIDIA switches, user deletion, anything
  under `/boot` or LUKS headers.
- Audit log `~/.local/state/nixos-doctor.log`: timestamp, command,
  exit, before/after check state.

## 5. Symptom map (AI-RUNBOOK.md current map; expand as symptoms are added)

No-GUI-after-rebuild · boot-menu-missing-entry · boot-hang-at-stage
· Secure-Boot-refuses-kernel · login-loop-greeter · black-screen-
mango · DMS-bar-gone · no-audio · mic-dead · bluetooth-pairs-never
· wifi-drops · DNS-resolves-nothing · portal-says-no-network ·
NVIDIA-fell-back-to-llvmpipe · games-stutter · tearing · wayland-
app-wont-start · X11-app-blank · clipboard-broken · screenshare-
black · suspend-never-wakes · hibernate-fails · battery-drains-idle
· clock-wrong-TLS-errors · disk-full · store-78G-why · rebuild-OOM
· flake-lock-conflict · module-eval-error · service-fails-on-boot
· timer-never-fires · flatpak-no-runtimes · printer-vanished ·
fan-full-blast-idle · cursor-gone · keyboard-dead-in-overlay ·
cheatsheet-empty · rebuild-fails-eval-error · rebuild-OOM-killed ·
admin-prompts-never-appear · kernel-unsigned-after-update ·
no-backups-yet · pending-reboot-weirdness. Each: checks to run →
commands → what-good-looks-like → escalate-when.

## 6. Bundle contents

`journal-full.txt` (this boot) · `journal-prev-errors.txt` ·
`boot-entries.txt` · `generations.txt` · `systemd-failed.txt` +
`blame-top.txt` · `dmesg.txt` · `hardware.txt` (lspci, nvidia-smi,
sensors) · `network.txt` (routes, DNS test, NM state — no keys) ·
`nix-status.txt` (dry-build summary, lock age, git status, parse
results) · `desktop.txt` (mango -p, dms units, cheatsheet rows) ·
`memory.txt` (free, PSI, top-RSS) · `secureboot.txt` (sbctl verify,
bootctl) · `backups.txt` (job states) · `doctor-report.txt` (+ `--json`
dump). Secrets rule + no-upload reminder printed every time.

## 7. Layout / install

```
~/nixos-doctor/
  PLAN.md  AI-RUNBOOK.md  nixos-doctor  tests.sh  checks/ (one file per area, sourced)
~/.local/bin/nixos-doctor -> symlink (no rebuild needed)
~/.local/state/nixos-doctor.log (audit trail)
```

`checks/` split keeps areas independently testable; engine stays a
thin runner (discovery → run → render → policy).

## 8. Self-tests (`tests.sh`)

Fixture-based, no root, no network: sample `journalctl`/`df`/
`nix-env` outputs → assert PASS/WARN/FAIL mapping; mock a FAIL
service path; schema-check `--json`; bundle manifest completeness
(no secrets by filename/pattern scan). CI-able with `nix-shell -p
shellcheck bats` — plus `shellcheck` clean on the script itself.

## 9. Completed work and roadmap

Completed: engine, checks, TUI, structured JSON, DMS integration, secure
bundles, Git backup workflow, packaging, CI, tests, and ShellCheck.

Future: structured fix coverage for every remaining legacy display-only fix,
configurable backup manifests, encrypted secret-manager integration, and the
optional `--watch` mode.

## 10. Risks / non-goals (extended)

- ext4 ⇒ no snapshot rollback; boot-menu generations are the only
  safety net — the tool says so loudly before any Tier 2 action.
- `verify --all` on 78G and SMART-long stay `--deep` opt-in.
- Secure Boot + kernel/driver ops: report-only, link manual.
- No hardware repair, no upstream bug filing (it drafts the text).
- NVIDIA specifics (explicit sync, GBM, hw cursors) reported with
  current state, not auto-toggled.
- nh-managed GC: tool detects `nh clean` config and defers to it
  rather than double-scheduling GC.
