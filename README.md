# nixos-doctor — user documentation

Report-first NixOS health checker. It inspects, reports, and suggests
possible fixes. It changes **nothing** unless you explicitly pick a fix
(`--fix-safe`, or confirmed Tier 1 actions in the TUI).

## Running it

```sh
nixos-doctor --sudo           # add root checks via passwordless sudo
```

From a source checkout, run `./nixos-doctor` directly. To install the
checkout for regular use, keep the directory in place and run:

```sh
mkdir -p ~/.local/bin
ln -sfn "$PWD/nixos-doctor" ~/.local/bin/nixos-doctor
```

The tool targets Bash 5.x on NixOS/Linux. Python 3 is required by
`--interactive` and `--fix-safe`; other commands such as `systemctl`, `nix`,
`journalctl`, `smartctl`, and desktop tools are optional and are skipped when
not available. Checks for a desktop, GPU, bootloader, or battery are only
meaningful when that hardware or session exists.

## Configuration Backup

`nixos-doctor backup` creates a local Git repository containing an explicit
allowlist of NixOS `.nix` files, `flake.lock`, and selected shell, Mango, and
DMS configuration. It does not upload anything by default.

```sh
nixos-doctor backup --dry-run
nixos-doctor backup
nixos-doctor backup --repo "$HOME/backups/nixos" --dry-run
nixos-doctor backup --push
```

The backup refuses to commit when it detects common private-key, token,
password, or API-key patterns. This is a safety net, not proof that a file is
safe. It does not delete files already in an existing backup repository, and
it does not automatically include arbitrary files from your home directory.
Review the dry-run output and keep the GitHub repository private. The
`--push` option requires an existing `origin` remote and uses normal Git
credentials. It asks for `YES` immediately before pushing; it never creates a
repository or changes GitHub visibility.

To use GitHub, create a **private** repository first, then configure it once:

```sh
git -C ~/.local/share/nixos-doctor-backup remote add origin git@github.com:OWNER/REPO.git
nixos-doctor backup --push
```

The push prompt is intentionally separate from the local commit. GitHub CLI,
SSH keys, or a credential helper can provide authentication, but this tool
does not create repositories, manage credentials, or change visibility.

> Do NOT run `sudo nixos-doctor`: as root every user-session check
> (audio, portals, mango/DMS, steam) measures root's empty
> environment and misreports. The `--sudo` flag is the correct way
> to get root checks while staying in your session.

Exit codes: `0` all pass · `1` warnings · `2` failures.

## Reading output

```
WARN [disk] / 85% full
      -> du -sh /* 2>/dev/null | sort -rh | head
```

`[area]`, severity, finding, then `->` a displayable fix description. JSON
also exposes stable `fix_id` and `fix_args` fields; automation should use
those fields rather than parse command text. The default JSON contract is
`schema_version: 2`, documented in `docs/json-schema-v2.json`. Use
`--json-v1` for consumers that require the previous top-level report shape.

Schema v2 also includes `report_id`, `generated_at` (UTC), and one-way
`identity` hashes for host, boot, and generation context. Raw hostnames, boot
IDs, and generation paths are not required in report metadata. Both schema
documents live under `docs/`; CI checks that they are valid Draft 2020-12
JSON Schemas.
`SKIP` means the check is unavailable, not applicable, or needs `--sudo` or
`--deep`.

Newly migrated checks also use `ERROR` when the check itself could not obtain a
required measurement, and `UNKNOWN` when available evidence cannot identify a
state confidently. These differ from `FAIL`, which means the check completed
and found an unhealthy condition.

Every JSON finding includes an `evidence` object. Observed checks include the
sanitized command, exit code, bounded output (up to 4096 bytes), and source
scope. Findings whose command evidence is unavailable explicitly use
`{"available":false}`. Evidence is diagnostic context and may still contain
sensitive data; inspect reports before sharing them.

## The 31 areas

boot · secureboot · systemd · nix · generations · store · services · journal · hardware ·
network · audio · graphics (mango/DMS: version gate, config, IPC,
settings JSON) · gaming (steam/shaders, gamemode, mangohud) ·
hyprland (session-aware SKIP, hyprctl IPC, quickshell shell, log
tail) · kde (session-aware SKIP, greetd/sddm seat check, baloo,
akonadi, crash culprits) · dms (official DMS doctor integration) · power · time · disk · memory · flake ·
home · secrets (metadata only, never contents) · containers ·
security · updates · bootperf · rebuild · backups

`dms` uses the official `dms doctor --json` interface when installed. It
reports DMS's own installation, compositor, service, environment, optional
feature, configuration, and font checks without making DMS a requirement for
other desktop sessions.

The dedicated `secureboot` area detects UEFI mode, firmware Secure Boot state,
the current loader/stub/entry, Lanzaboote configuration, ESP location and free
space, EFI-variable access, booted/current generation alignment, `sbctl`
signature verification, and EFI boot order when the required tools and
privileges are available. Signing and bootloader changes are always manual.

The dedicated `systemd` area reports system and user manager state separately,
failed service properties, restart counts, queued jobs, timer schedule data,
missed-run signals, OOM service state, and optional deep boot analysis. Use
`nixos-doctor systemd --deep` when boot timing and dependency analysis is needed.

## Fix policy

- **Default**: report only. Safe to run anytime, even mid-crisis.
- **Tier 1 auto** (`--fix-safe` / TUI-confirmed): garbage collection
  (never `-d` unprompted), journal vacuum, daemon-reload, normal
  service restarts, fstrim, tmp cleanup.
- **Tier 2 manual** (never executed by the tool): rebuilds, rollbacks,
  `nix-store --repair-path`, `nix-collect-garbage -d`, reboots,
  bootloader/Secure Boot/firmware/driver changes.
- Everything applied is appended to
  `~/.local/state/nixos-doctor.log` (audit trail).

## License

MIT. See `LICENSE`.

## Installation

See [`INSTALL.md`](INSTALL.md) for source checkout, symlink, Nix flake,
NixOS/Home Manager, upgrade, uninstall, backup, and troubleshooting guidance.

## Nix Installation

From a local checkout with flakes enabled:

```sh
nix run . -- --json
nix profile install .
```

`nix build` produces the package without installing it. A hosted repository can
be installed with the equivalent `github:Hackcoon/nixos-doctor` flake reference.

## Files

```
~/nixos-doctor/
  nixos-doctor   # the tool (engine + CLI)
  checks/        # one file per area, sourced by the engine
  tui.sh         # --interactive menu (Bash + Python 3)
  bundle.sh      # --bundle exporter
  backup.sh      # backup subcommand implementation
  AI-RUNBOOK.md  # symptom → checks → commands map for AI agents
  tests.sh       # self-tests (./tests.sh, must stay green)
  README.md      # this file
  MAINTENANCE.md # change log — record every change here
  PLAN.md        # original design record
~/.local/bin/nixos-doctor  # symlink, puts it on PATH
```

The DMS area deliberately mirrors DMS's own result statuses instead of
reimplementing its checks. Run `nixos-doctor dms --json` for automation or
`dms doctor --verbose` for detailed upstream diagnostics.

## Profiles

Checks are generic by default. Optional environment settings provide safe,
non-executable host preferences without sourcing configuration files:

```sh
NIXOS_DOCTOR_EXPECTED_COMPOSITOR=mango nixos-doctor graphics
NIXOS_DOCTOR_EXPECTED_COMPOSITOR=none nixos-doctor graphics hyprland
NIXOS_DOCTOR_FLAKE_ROOT="$HOME/src/my-nixos" nixos-doctor flake
```

Supported compositor values are `auto`, `mango`, `hyprland`, `kde`, and
`none`. The profile changes applicability only; it never runs commands from
the environment.

## Maintenance

The full implementation sequence and acceptance criteria are maintained in
`DEVELOPMENT-ROADMAP.md`.

- After any change: `./tests.sh` (must pass) + one live
  `./nixos-doctor` sweep + log it in `MAINTENANCE.md`.
- Add a check: new file `checks/<area>.sh` defining
  `check_<area>()` using the `finding` helper, then register the
  area name in `nixos-doctor`'s `ALL_AREAS` (keep engine + checks
  alphabetical).
- Helpers available in checks: `finding SEV AREA msg [fix]`,
  `have cmd`, `need_root area what`. End check functions with
  `return 0` (a trailing bare conditional failing prints a bogus
  "check crashed"). Never pipe into `while read` (subshell eats
  counters) — use `done <<<"$var"`. In awk, always use `!~`, never
  bare `!/.../ ` after a field (gawk parses it wrong).
- Fixes: use `finding_fix` with a stable fix ID and argument list. Legacy
  `finding` fixes remain display-only and must never be treated as structured
  executable actions. Keep fix IDs registered in `run_fix()` and validate all
  arguments there.
- Keep checks fast: anything over ~5s goes behind `--deep`.
