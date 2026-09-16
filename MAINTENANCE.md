# nixos-doctor — maintenance log

Newest entries first. Every change gets a dated entry: what, why,
validation (`./tests.sh` + live sweep result).

## 2026-09-14 — v1.0.0 Step 6 Nix correlation
- Added `nix` diagnostics for flake revision/dirty state, lock metadata,
  read-only deep validation, generation/kernel/initrd alignment, daemon state,
  and database lock visibility.
- Validation: Nix correlation fixture, full tests, ShellCheck, flake checks,
  package build, and live Nix report.

## 2026-09-14 — v0.10.0 Step 6 Nix correlation
- Added `nix` for flake revision/dirty state, lock metadata, deep read-only
  flake validation, generation/kernel/initrd alignment, daemon state, and DB lock.

## 2026-09-14 — v0.9.0 Step 5 JSON Schema v2
- Default JSON reports now include schema-v2 report metadata: report ID, UTC
  timestamp, and one-way host/boot/generation hashes.
- `--json-v1` preserves the previous top-level report contract. Added separate
  v1 and v2 schema documents and compatibility tests.

## 2026-09-14 — v0.8.0 Step 4 evidence and provenance
- Added bounded evidence objects to JSON findings, with sanitized command,
  exit code, output limited to 4096 bytes, and source scope for observed checks.
- Legacy findings explicitly mark evidence unavailable. Added escaping and
  truncation regression coverage.

## 2026-09-13 — v0.6.0 Step 3 systemd diagnostics
- Added the dedicated `systemd` area for separate system/user manager state,
  failed unit properties, restart counts, queued jobs, timers, OOM services,
  and optional deep boot analysis.
- Validation: `./tests.sh` 68/68; ShellCheck; all-system flake checks; package
  build; live deep systemd report.

## 2026-09-13 — v0.5.0 Step 3 dedicated systemd diagnostics
- Added `systemd` for separate system/user manager state, failed service
  properties, restart counts, queued jobs, timer schedule/missed-run signals,
  OOM service visibility, and optional deep boot timing.
- Added deterministic fixtures for failed system/user units, restart counts,
  queued jobs, timers without schedule data, and unavailable user managers.
- Validation: `./tests.sh` 68/68; ShellCheck; `nix flake check --all-systems`;
  `nix build`; live systemd report showed both managers running, no failed
  services, and two user timers without recorded next/last-run data.

## 2026-09-13 — v0.4.0 Step 2 dedicated Secure Boot diagnostics
- Added `secureboot` for UEFI state, firmware Secure Boot, current loader/stub/
  entry, Lanzaboote configuration, ESP capacity, EFI variables, generation
  alignment, `sbctl` signatures/status, and optional EFI boot-order evidence.
- Partial unprivileged `bootctl` output is retained while protected details are
  marked as requiring `--sudo`; signing and bootloader changes remain manual.
- Added deterministic BIOS, missing-tool, unsigned-artifact, and failed-verify fixtures.

## 2026-09-13 — Step 1 capability/applicability foundation complete
- Added `ERROR` and `UNKNOWN`, structured result metadata, and shared user-bus,
  UEFI, battery, GPU, and session probes.
- Migrated false-confidence paths across boot, disk, services, journal, time,
  network, graphics, hardware/SMART, power, store, generations, Home Manager,
  containers, security, updates, KDE, rebuild, secrets, and boot performance.
- Added deterministic fixtures for missing capabilities, failed measurements,
  query failures, disk-journal failure, unsupported SMART, and SMART exit status.

## 2026-09-13 — v0.3.0 Git backup workflow
- Added `nixos-doctor backup` with an explicit allowlist for NixOS and selected
  dotfiles, private staging, secret-pattern rejection, dry-run mode, local Git
  commits, and opt-in push to an existing remote.
- GitHub integration is deliberately local-first: the user creates and keeps
  the destination repository private; the tool never creates or changes it.
- Validation: backup dry-run, secret rejection, local commit, ShellCheck,
  flake checks, package build, and regression suite.

## 2026-09-12 — v0.2.0 release hardening and DMS integration
- Automatic fixes now execute validated argument arrays; no finding text is
  passed through `bash -c`. Tier-2 actions are manual-only.
- Area traversal, relative symlinks, TUI record parsing/indexing, audit-log
  setup, and secure bundle creation were hardened.
- Added `dms` via the upstream `dms doctor --json` contract, Nix flake
  packaging, a pinned lock file, CI, ShellCheck, MIT license, and changelog.
- Applicability and command-failure reporting improved across audio, services,
  graphics, boot, disk, memory, network, security, Home Manager, and rebuild.
- Validation: `./tests.sh` 51/51; `nix flake check --all-systems`; `nix build`;
  live DMS report imported 46 findings (36 pass, 2 warn, 8 informational).

## 2026-09-11 — `sudo nixos-doctor` misreports user sessions
- Root cause of a confusing run: as root, audio/portals/mango/DMS/
  steam checks read root's world (no user bus, no `~/.config`) and
  FAIL bogusly. Engine now prints a steering banner under EUID 0;
  README documents `--sudo`-as-user as the correct form.
- generations count silently vanished for unprivileged users
  (profile lock unreadable) — now an explicit SKIP pointing at
  `--sudo`. (Side discovery that way: 47 system generations.)
- Validation: `./tests.sh` green; banner text reviewed (EUID-0 path
  itself can't run in this sandbox).
- Bug: `SELF_DIR` came from unresolved `BASH_SOURCE[0]`, so running
  via `~/.local/bin/nixos-doctor` looked for `checks/` next to the
  link → every area "unknown area". Fixed with a readlink loop +
  a hard error if `checks/` is still missing.
- Regression test: runs the tool through a temp symlink and asserts
  findings exist.

## 2026-09-11 — all-filesystem disk support + review fixes (historical)
- disk.sh is fstype-aware (`findmnt`): per-fs kernel-log dialects
  (ext4/xfs/btrfs-checksum/zfs-pool), `zpool status -x` when ZFS is
  present, btrfs `/.snapshots` flips rollback notes, ext4 reserves
  only on ext4 with auto-detected root device (was hardcoded sdb2).
- Review repairs: restored a line dropped by a bad edit
  (services.sh units assignment — caught by re-reading, not tests),
  shellcheck-disable annotations on intentional word-splitting,
  stale timers comment reworded.
- Validation: `./tests.sh` green; `services disk` live
  11 pass · 0 fail.
- Full usage text in the script header (`--help` strips `#`
  prefixes for clean output; sed range auto-tracks via `/^set -u/`).
- `print_topic()`: one-liners for the original 25 areas + fix-safe/deep/
  sudo/json/interactive/bundle/policy; unknown topic exits 2.
- Validation: `./tests.sh` 48/48 (new: help-usage/area/flag/unknown).

## 2026-09-11 — adversarial hunt: repass flags, TUI index, attribution
- `--fix-safe` re-pass dropped `--sudo/--deep` (findings could differ
  from pass 1) — now preserved. `--fix-safe`+`--json` interaction
  documented (fix-safe ignored, inspect data first).
- TUI: picks validated (`0` rejected — index -1 wraps to last
  element in bash), `|` sanitized out of displayed messages (both
  display and extraction split on it), stale `select` comment fixed.
- Journal error count used a capped `head -20` sample (once hid a
  397k-line flood) — full count now; unit attribution via `-o json`.
- journal size regex missed `K` units; power mem_sleep empty guard;
  `$USER` hardened for bare envs (`set -u`).
- store.sh lost its `fi` in an edit — caught by live run (crash
  handler worked), reinforcing: run tests.sh after EVERY edit batch.
- Validation: `./tests.sh` 48/48; full sweep
  64 pass · 12 warn · 2 fail · 12 skip.
- SMART short health runs every sweep ([R] via need_root); NVMe
  Percentage Used / Available Spare + SATA wear attributes warn at
  end-of-life; long self-test stays manual. `SMART_DEVS` override
  exists for fixture tests (CI has no disks).
- disk.sh: kernel-log scan for EXT4-fs/IO errors and forced
  read-only remounts (fast, [U]).
- Bugs caught by the new fixture tests: smartctl names have SPACES
  (`Percentage Used:`, not `Percentage_Used`) — the first version
  silently matched nothing; tests need `--sudo` or need_root SKIPs.
- Validation: `./tests.sh` 44/44 (new: smart-healthy, smart-sick).

## 2026-09-11 — review pass: fix-safe applier, attribution, guards
- `--fix-safe` actually implemented (was a no-op flag): JSON
  second pass, Tier-1 allowlist (`tier1_allowed`), extraction via
  `first_cmd()`, audit-logged. Restructure: `main()` guard so tests
  can source the engine without sweeping.
- Fixed same latent bug in TUI (executed human suffixes) — both
  runners now execute `first_cmd()` output only.
- Journal errors attributed via `-o json` (`_SYSTEMD_UNIT` counter;
  box top: user@1000.service) instead of "unknown".
- Failed timers checked explicitly (old "timers enumerated" PASS
  was vacuous). nh-clean presence check in flake area.
- bundle.sh guards mango/dms calls with `command -v`.
- Disk stale comment rewritten; README gained fix-string convention.
- Validation: `./tests.sh` 42/42 (new: 6 tier1 + 2 first_cmd tests);
  `--fix-safe updates journal` correctly skips non-allowlisted.

## 2026-09-11 — kde + gaming areas, manual recovery flows
- New `checks/kde.sh`: session-aware SKIP; greetd-vs-sddm seat check
  (unit is `greetd`, not `dms-greeter`); baloo via waiting-count
  (substring match false-positived on "content indexing: 0" — fixed);
  akonadi running-but-broken only; crash culprits via `coredumpctl
  -F COREDUMP_EXE` basenames (box: drkonqi's own launcher + quickshell).
- New `checks/gaming.sh`: Steam lib/shader sizes, Proton tools,
  gamemode/mangohud presence. Box: 82G lib, 5.9G shaders, no gamemode.
- AI-RUNBOOK.md: manual-grounded recovery flows (boot-menu rollback,
  `systemd.unit=rescue.target`, `nixos-enter` from USB, atomic-switch
  reassurance, `switch --rollback`), KDE/Hyprland/Steam symptoms.
- Historical note: 25 areas were wired everywhere at this point; the current
  release later grew to 27 areas including DMS and Secure Boot integration.
- Validation: `./tests.sh` green; `kde gaming` live
  5 pass · 2 warn · 0 fail · 1 skip.

## 2026-09-11 — compositor coverage: hyprland area + mango/DMS gates
- New `checks/hyprland.sh`: session-aware SKIP in mango sessions;
  hyprctl IPC, config files, fury-bar shell, log-tail scan when live.
  (Live-running path untested — Hyprland wasn't up; re-verify there.)
- `graphics.sh`: mango >= 0.14 gate (DMS bar IPC floor; box is 0.16.2),
  DMS settings.json parse check.
- Wired `hyprland` into engine + TUI area lists (23 areas), README,
  PLAN (3.23), tests.sh (+hyprland-skip test).
- Validation: `./tests.sh` green; `hyprland graphics` live
  10 pass · 1 warn · 0 fail · 1 skip.

## 2026-09-11 — v0.1.0 initial build
- Engine (`nixos-doctor`): runner, PASS/WARN/FAIL/SKIP + exit 0/1/2,
  `--json/--deep/--sudo/--fix-safe/--interactive/--bundle/--help`,
  `[R]` gating via `sudo -n` (never prompts).
- All 22 areas in `checks/`: boot, generations, store, services,
  journal, hardware, network, audio, graphics, power, time, disk,
  memory, flake, home, secrets, containers, security, updates,
  bootperf, rebuild, backups.
- `tui.sh` (original bash menu and per-fix confirmation),
  `bundle.sh` (tarball + secrets warning), `AI-RUNBOOK.md`,
  `tests.sh` (original 30-test baseline), `README.md`, `PLAN.md` marked implemented.
- Symlinked to `~/.local/bin/nixos-doctor`.
- Bugs fixed during live testing on this box:
  1. services: `awk '{print $1}'` grabbed the `●` bullet → unit-name
     regex + `@instance` collapsing (`×N` rollup).
  2. Pipe-to-`while read` lost finding counters (subshell) → herestring.
  3. `systemctl show --all` hung on 13k dead units → dropped broad
     dump; restart-loop detail deferred to TUI.
  4. `du -sh /nix/store` stalled sweeps → closure-size query; full
     `du` behind `--deep`.
  5. PSI field `$5`→`$2` (bogus 2492231% stall reading).
  6. `nvidia-suspend` checked `is-active` (oneshot, always inactive)
     → checks `list-unit-files` enabled instead.
  7. gawk: bare `$2 !/.../ ` misparses — always use `!~`.
  8. Trailing bare conditionals return 1 → "check crashed"; end
     checks with `return 0`.
- Live findings worth noting: ~13.9k transient drkonqi crash units
  (+4.6k coredumps, still growing — something crashes constantly),
  2 dead plasma user units, no backups on ext4, no polkit agent in
  mango sessions, 20 boot errors.
- Validation: `./tests.sh` 30 passed / 0 failed; full sweep
  `54 pass · 8 warn · 4 fail · 10 skip`.
