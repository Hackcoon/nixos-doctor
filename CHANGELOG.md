# Changelog

## 1.0.0 - 2026-09-14

- Added the dedicated `nix` area for flake revision and dirty state, lock
  metadata, optional deep read-only flake validation, generation/kernel/initrd
  alignment, Nix daemon health, and database-lock visibility.
- Added fixture coverage for revision metadata and read-only flake failures.

## 0.9.0 - 2026-09-14

- Promoted default JSON reports to schema version 2 with report IDs, UTC
  timestamps, and privacy-preserving host/boot/generation hashes.
- Added `--json-v1` compatibility output and separate v1/v2 JSON Schema documents.
- Added the dedicated `nix` area for flake/revision state, lock metadata,
  read-only deep validation, generation/kernel/initrd alignment, daemon health,
  and database lock visibility.

## 0.8.0 - 2026-09-14

- Added bounded evidence and provenance objects to JSON findings.
- Observed checks can report sanitized command, exit code, bounded output, and
  source scope; legacy findings explicitly report unavailable evidence.
- Added regression coverage for evidence truncation and JSON-special characters.

## 0.6.0 - 2026-09-13

- Added the dedicated `systemd` area for separate system/user manager state,
  failed units, restart counts, queued jobs, timers, OOM services, and deep boot analysis.
- Added fixtures for failed system/user units, restart counts, queued jobs,
  timers without schedule data, and manager diagnostics.

## 0.5.0 - 2026-09-13

- Completed the capability/applicability foundation across the check catalog.
- Added the dedicated `secureboot` area with UEFI applicability, firmware state,
  explicit systemd-boot/GRUB/Limine classification, loader/stub/UKI entry,
  Lanzaboote runtime/configuration state, ESP discovery and capacity, real EFI
  variable access, generation/kernel/initrd alignment, root-gated `sbctl`
  signature verification, and optional EFI boot-order inspection.
- Added BIOS, missing-tool, unsigned-artifact, failed-verification, disabled
  Lanzaboote, GRUB, and efivar fixtures.
- Added the dedicated `systemd` area for separate system/user manager state,
  failed units, restart counts, jobs, timers, OOM services, and deep boot analysis.

## 0.4.0 - 2026-09-13

## 0.3.0 - 2026-09-13

- Added `nixos-doctor backup`, a local-first Git backup workflow with an
  explicit NixOS/dotfile allowlist, secret-pattern rejection, dry-run mode,
  and opt-in push to an existing Git remote.
- Began the capability/applicability foundation with explicit `ERROR` and
  `UNKNOWN` states, result metadata, shared capability probes, and regression
  tests preventing unavailable checks from becoming false PASS results.
- Migrated journal, time, network, SMART, battery, graphics user-session, audio,
  services, DMS, hardware GPU, rebuild measurement, and crash handling paths to
  distinguish unavailable, failed, unknown, healthy, and unhealthy states.

## 0.2.0 - 2026-09-12

- Added a structured `dms` area backed by `dms doctor --json`.
- Hardened automatic fixes so only validated Tier 1 argument vectors execute.
- Added secure bundle creation, Nix packaging, CI, ShellCheck, and release metadata.
- Improved desktop, audio, boot, disk, memory, network, security, Home Manager,
  and rebuild applicability and failure reporting.

## 0.1.0 - 2026-09-11

- Initial report-first NixOS health checker release.
