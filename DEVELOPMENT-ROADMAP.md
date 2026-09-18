# nixos-doctor Development Roadmap

This is the living implementation plan for making `nixos-doctor` the primary
diagnostic interface for NixOS. It covers NixOS configuration, Secure Boot,
systemd, hardware, networking, desktop sessions, DMS, recovery, incident
reporting, and configuration backup.

`README.md` documents the current user interface. `PLAN.md` is the original
design record. `MAINTENANCE.md` records historical work. This document tracks
the remaining development sequence and acceptance criteria.

## Product Goal

The tool should be the first command to run when a NixOS machine appears broken.
It must collect trustworthy evidence, distinguish unhealthy from unavailable or
inapplicable checks, explain what it observed, and provide safe next actions.
It must not pretend to replace specialized tools or a recovery USB.

The tool must remain report-first, safe for normal-user execution, explicit
about privilege/session/hardware requirements, useful from TTY/SSH/rescue
environments, machine-readable, and conservative with secrets and uploads.

## Current Baseline

Version `1.1.0` currently includes:

- 32 areas, including DMS, Noctalia, Secure Boot, systemd, and Nix integrations.
- Nix flake packaging, CI, Bash syntax checks, ShellCheck, and regression tests.
- Versioned JSON output (`schema_version: 2`) with `--json-v1` compatibility.
- Structured fix IDs for migrated Tier 1 actions.
- Local-first Git backup with dry-run and secret-pattern scanning.
- Private bundle staging and explicit GitHub push confirmation.

Remaining gaps include legacy display-only fixes, incomplete evidence metadata,
limited history, no dedicated Secure Boot/systemd areas, limited redaction, and
no declarative installation or recovery mode.

## Development Rules

Every new check must declare applicability, required commands, privilege,
session state, scope, and confidence. It must distinguish healthy, unhealthy,
unavailable, and not-applicable results; preserve command exit status; prefer
structured command output; avoid secret contents; never execute raw finding
strings; use validated fix IDs; and include success/failure fixtures.

Each phase must run:

```sh
./tests.sh
nix flake check --all-systems
nix build .#default
```

## Step 1: Capability and Applicability Model `[x]`

Define `PASS`, `WARN`, `FAIL`, `SKIP`, `ERROR`, and `UNKNOWN`. Add result fields
for `check`, `scope`, `requires`, `reason`, `confidence`, and evidence reference.
Create shared probes for command availability, root capability, user bus,
graphical session, UEFI mode, filesystem type, battery, and GPU vendor.

Update checks so command failure never becomes a false PASS. Gate Mango,
Hyprland, KDE, DMS, PipeWire, GPU, battery, bootloader, ZFS, and Btrfs checks
on actual applicability.

**Acceptance:** missing commands produce SKIP/INFO; missing user bus is not
“no failed units”; fixtures cover missing, failed, empty-success, and healthy.

Implemented foundation in the current development tree: `ERROR` and `UNKNOWN`
  result states, summary counters, capability helpers for user bus/UEFI/battery/GPU,
  structured metadata (`check`, `scope`, `confidence`, `reason`, `requires`), and
migrations for command/capability failure paths across the check catalog. This
includes session services, boot, disk, Nix profiles/store, DMS, GPU/SMART/battery,
time, network, containers, security, KDE, rebuild, secrets, and boot performance.

Step 1 completion included a final focused audit for false PASS/FAIL behavior.
Evidence and provenance are tracked separately under Step 4.

## Step 2: Dedicated Secure Boot Diagnostics `[x]`

Add a `secureboot` area. Detect UEFI versus BIOS. Inspect `bootctl status`,
`bootctl list`, `mokutil --sb-state`, `sbctl status`, `sbctl verify`, and
`efibootmgr -v` when available. Use the actual ESP mountpoint. Detect
systemd-boot, Lanzaboote, GRUB, Limine, or unknown bootloaders.

Compare booted generation, current profile, running kernel/initrd/UKI, EFI
entry, boot order, EFI variables, and ESP space. Distinguish disabled,
enabled-and-verified, enabled-but-unverified, unavailable, and not-applicable.
Signing and bootloader changes remain manual-only.

**Acceptance:** no systemd-boot warnings on GRUB/Limine; failed `sbctl` cannot
be PASS; fixtures cover UEFI, BIOS, missing tools, unsigned artifacts, and ESP paths.

Completed with explicit UEFI applicability, partial `bootctl` handling,
firmware state, loader/stub/current-entry detection, Lanzaboote/static
configuration detection, vfat ESP discovery, ESP capacity, EFI-variable
access, generation/kernel alignment, root-gated `sbctl status`/`verify`, and
optional `efibootmgr` evidence. Fixtures cover BIOS, missing tools, unsigned
artifacts, verification failure, and configurable EFI/ESP roots.

## Step 3: Dedicated Systemd Diagnostics `[x]`

Add a `systemd` area for system and user managers. Report manager reachability,
failed units, load/active/sub states, results, exit codes, restart counts,
failed jobs, activating/deactivating units, failed timers, last/next runs,
missed runs, critical chain, slow units, user lingering, and cgroup/OOM data.

Correlate unit state with journal evidence. Keep system and user scope separate.

**Acceptance:** no-bus is unavailable, not healthy; timer results identify the
timer and timing; fixtures cover failed units, restart loops, timers, and no bus.

Completed with separate system/user manager state, failed service properties,
restart counts, queued jobs, timer schedule/missed-run signals, OOM service
visibility, and optional deep boot timing/blame/critical-chain checks. The
existing `services` area remains focused on compatibility output; `systemd` is
the authoritative manager-diagnostics view.

## Step 4: Evidence and Provenance `[x]`

Add structured evidence containing sanitized command, arguments, exit code,
timestamp, bounded output, source boot/generation, and confidence. Redact or
summarize sensitive command output. Keep evidence size bounded and guarantee
valid JSON for unusual bytes, quotes, Unicode, and newlines.

**Acceptance:** every WARN/FAIL has evidence or an explicit unavailable reason;
no evidence field can contain unbounded journal output.

Completed with bounded evidence on every JSON finding, explicit unavailable
evidence for legacy findings, command/exit/output/source capture for observed
checks, JSON-safe escaping, a 4096-byte output limit, and regression coverage
for quotes, backslashes, newlines, and truncation.

## Step 5: JSON Schema Version 2 `[x]`

Keep schema 1 during migration. Define schema 2 with check IDs, applicability,
requirements, evidence, confidence, timestamps, report ID, and safe hashes for
host/boot/generation context. Publish schemas and migration notes under `docs/`.
Validate representative reports in CI with a JSON Schema validator.

**Acceptance:** consumers can select schema before parsing; no raw boot IDs,
tokens, or private paths are required for validity.

Completed with schema-v2 default reports, `--json-v1` compatibility output,
stable report IDs, UTC generation timestamps, one-way host/boot/generation
hashes, separate v1/v2 schema documents, and compatibility regression tests.

## Step 6: Nix, Flake, and Rebuild Correlation `[x]`

Report flake root, Git revision/dirty state, lock revision/age, current and
booted generation, running kernel/initrd, likely pending reboot versus rollback,
Nix daemon/database state, and last known good generation.

Add optional read-only `nix flake check`, evaluation, and dry-build diagnostics
behind `--deep` or an explicit flag. Preserve file/line evidence and never run
slow operations in the default sweep.

**Acceptance:** reports distinguish evaluated, built, activated, booted, and
rolled-back states; failures retain command status and useful evidence.

Completed with the dedicated `nix` area for flake revision/dirty state, lock
metadata, optional deep read-only flake validation, generation/kernel/initrd
alignment, Nix daemon state, and database-lock visibility. Mutating rebuilds
remain outside the diagnostic path.

## Step 7: Hardware and Storage Matrix `[-]`

Detect GPU vendor before vendor-specific checks. Add AMD/Intel paths. Distinguish
SMART unsupported, inaccessible, command failure, and health failure. Support
SATA, NVMe, USB, virtio, and multiple devices. Improve temperature parsing,
battery applicability, ZFS pool states, Btrfs subvolume/snapshot checks, and
actual ESP/root/Nix/temp filesystem detection.

**Acceptance:** AMD/Intel systems get no NVIDIA warning; unsupported SMART is
not disk failure; tests cover multiple filesystems and no-device cases.

Current implementation includes vendor-aware NVIDIA/AMD/Intel applicability,
SMART unsupported/error/health distinctions, battery detection, filesystem
applicability, and an optional Noctalia integration. Remaining work includes
full multi-device SMART/NVMe/SATA coverage, richer AMD/Intel renderer checks,
storage-matrix fixtures, and Noctalia upstream health/report integration when
its CLI exposes a stable structured doctor interface.

## Step 8: Network and Time Diagnostics

Report links, carrier, route, gateway, IPv4, IPv6, active network manager,
interface ownership, VPN/WireGuard/Tailscale state, MTU, and resolver details.
Use configurable/local DNS tests rather than requiring one external domain.
Make captive-portal checks optional. Detect the actual time-sync provider and
normalize locale aliases.

**Acceptance:** isolated/offline systems are not automatically broken; fix
suggestions name the actual time-sync/network service.

## Step 9: Desktop, DMS, and Session Correlation

Continue using `dms doctor --json` as the source of DMS-specific checks. Preserve
its categories, statuses, details, and URLs. Add only correlation: DMS service,
active compositor, session target, portals, polkit agent, Qt/theme variables,
and DMS warnings.

Keep all desktop checks session-aware and identify the selected portal backend.

**Acceptance:** non-DMS desktops receive no DMS failures; upstream warnings are
distinguishable; DMS findings link to `dms doctor --verbose`.

## Step 10: History, Timeline, and Regression Detection

Add `history`, `diff`, and `timeline` commands. Store sanitized summaries under
`~/.local/state/nixos-doctor/reports/`; use hashes instead of raw sensitive
output. Compare failed units, warnings, boot time, renderer, DMS, generations,
Secure Boot, and hardware. Add retention and migration handling. Never upload
history automatically.

**Acceptance:** reports show new, resolved, and unchanged findings; retention
and privacy are documented and tested.

## Step 11: Incident Bundles and Redaction

Add a stable `manifest.json` with versions, options, commands, exit codes,
files, and redaction status. Organize system, journal, hardware, network,
desktop, Nix, and privacy sections. Add safe default redaction for tokens,
passwords, private keys, paths, MAC addresses, IPs, and hostnames where practical.

Add `--redact` and explicit `--no-redact`, scan the final archive, record failed
collection in the manifest, and state that journals may still contain secrets.

**Acceptance:** manifest matches archive; redaction fixtures pass; archives are
private, non-overwriting, and collection failures are visible.

## Step 12: Declarative Installation and Scheduled Checks

Add NixOS and Home Manager modules. Support optional daily/weekly read-only
timers, retention, notifications only for new failures/severity changes, and a
restricted scheduled-service profile. Automatic remediation remains disabled.

**Acceptance:** module evaluation works; timers never prompt or mutate; alerts
are deduplicated.

## Step 13: Recovery Mode and Repair Plans

Add `nixos-doctor recovery` for TTY, SSH, rescue target, installer, and chroot
contexts. Avoid desktop assumptions. Report mounts, root/ESP, generations,
Secure Boot, failed units, boot errors, disk, Nix database, and network.

Add `nixos-doctor plan`, a deterministic non-executing sequence with risk,
privilege, reversibility, preconditions, expected results, and rollback notes.
Rebuild, reboot, repair, bootloader, signing, firmware, and LUKS operations stay
manual.

**Acceptance:** recovery runs without a GUI and performs no mutations; plans do
not hide dangerous assumptions.

## Step 14: Backup, Restore, and GitHub Issue Drafts

Extend `nixos-doctor backup` with `init`, `list`, `check`, `diff`, and
`restore --dry-run`. Add a user-controlled manifest, per-file reasons, generated
`.gitignore` protections, repository permission checks, commit signing support,
and optional age/SOPS encryption. Test restoration into a temporary directory.

Keep local commit separate from network push. Refuse public GitHub remotes by
default. Add `nixos-doctor issue --template github --redact` to create reviewed
drafts containing versions, evidence, reproduction commands, expected/actual
behavior, sanitized logs, and bundle hash. Never file or upload automatically.

**Acceptance:** backups restore into a clean temporary tree; scans run before
staging/pushing; GitHub pushes require an existing remote and explicit approval;
issue output is a draft file.

## Long-Term CLI

Keep shorthand support:

```sh
nixos-doctor secureboot systemd
```

Gradually add:

```sh
nixos-doctor scan
nixos-doctor scan --area secureboot --area systemd
nixos-doctor report
nixos-doctor history
nixos-doctor diff
nixos-doctor plan
nixos-doctor bundle --redact
nixos-doctor recovery
nixos-doctor backup
nixos-doctor issue --template github --redact
```

## Release Checklist

- Update version in executable, flake, changelog, and user documentation.
- Run `./tests.sh`, `nix flake check --all-systems`, and `nix build .#default`.
- Run a live normal sweep and DMS/Secure Boot checks when available.
- Validate JSON schemas, bundle manifest/redaction, backup dry-run/commit/restore.
- Review every new fix ID and confirm no raw command strings execute.
- Review docs for stale counts, unsupported flags, and unsafe privacy claims.

## Non-Goals

The tool will not replace a recovery USB, guarantee logs contain no secrets,
automatically repair filesystems/bootloaders/firmware/Secure Boot/LUKS, upload
diagnostics, create public repositories, or treat healthy Secure Boot as proof
that the NixOS configuration is healthy.
