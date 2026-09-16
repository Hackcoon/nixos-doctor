# Installing nixos-doctor

This guide covers source checkout installation, Nix flake installation,
declarative NixOS/Home Manager installation patterns, upgrades, verification,
uninstallation, and troubleshooting.

`nixos-doctor` is designed for NixOS/Linux systems with Bash 5.x. It should be
run as the normal user. Use `--sudo` for checks that need noninteractive root
access. Do not run the main doctor command as `sudo nixos-doctor` because user
session checks would inspect root's environment instead of yours.

## Requirements

Required for a normal source installation:

- Bash 5.x.
- GNU/Linux or NixOS.
- Python 3 for `--interactive`, `--fix-safe`, and DMS JSON parsing.

Optional commands enable additional checks:

- `nix`, `nix-env`, `nixos-rebuild` for NixOS configuration checks.
- `systemctl`, `journalctl`, and `systemd-analyze` for systemd diagnostics.
- `bootctl`, `sbctl`, `efibootmgr`, and `mokutil` for Secure Boot diagnostics.
- `smartctl`, `sensors`, `upower`, `nvidia-smi`, and `lspci` for hardware checks.
- `dms` for DMS integration through `dms doctor --json`.
- `git` for configuration backups.
- `curl`, `nmcli`, `ip`, `getent`, `flatpak`, `podman`, and other optional
  tools for their respective areas.

Missing optional tools should result in `SKIP`, `ERROR`, or `UNKNOWN` findings;
they are not all required for the tool to run.

## Method 1: Run From A Checkout

Clone the repository and run the executable directly:

```sh
git clone https://github.com/OWNER/nixos-doctor.git ~/src/nixos-doctor
cd ~/src/nixos-doctor
./nixos-doctor --help
./nixos-doctor --json
```

Replace `OWNER` with the GitHub account or organization that owns the project.

This method requires the checkout to remain in place because the main script
loads its `checks/` directory and helper scripts beside itself.

## Method 2: Install A User Symlink

Keep the checkout at a stable path and add the executable to your user PATH:

```sh
mkdir -p ~/.local/bin
ln -sfn "$HOME/src/nixos-doctor/nixos-doctor" ~/.local/bin/nixos-doctor
```

Ensure `~/.local/bin` is in your PATH:

```sh
case ":$PATH:" in
  *:"$HOME/.local/bin":*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
```

For a persistent shell configuration, add the PATH export to the shell file
you actually use, such as `~/.bashrc` or `~/.zshrc`.

Verify the symlinked installation:

```sh
command -v nixos-doctor
nixos-doctor --version
nixos-doctor help areas
```

The symlink target must point to the repository's `nixos-doctor` file, not to a
copied executable without its `checks/` directory.

## Method 3: Install With Nix Flakes

From a local checkout:

```sh
cd ~/src/nixos-doctor
nix flake check --all-systems
nix build .#default
nix run . -- --json
nix profile install .
```

After `nix profile install .`, verify:

```sh
nixos-doctor --version
nixos-doctor --help
```

From a hosted GitHub repository:

```sh
nix run github:OWNER/nixos-doctor -- --json
nix profile install github:OWNER/nixos-doctor
```

The flake package installs the engine, checks, TUI, bundle exporter, backup
command, and JSON schema documentation together. Do not copy only the main
script out of the Nix store or source checkout.

## Declarative NixOS Installation

The project currently provides a flake package, but not yet a dedicated
NixOS/Home Manager module. Until those modules are added, install the package
through a flake input and add it to `environment.systemPackages`:

```nix
{
  inputs.nixos-doctor.url = "github:OWNER/nixos-doctor";

  outputs = { self, nixpkgs, nixos-doctor, ... }:
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ({ pkgs, ... }: {
            environment.systemPackages = [
              nixos-doctor.packages.${pkgs.system}.default
            ];
          })
        ];
      };
    };
}
```

Adapt this example into your existing configuration rather than replacing your
current flake. Then apply the configuration using your normal command:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

Run the tool as your normal user after activation:

```sh
nixos-doctor --sudo
```

## Home Manager Installation

Until a Home Manager module is provided, use the package in your existing
Home Manager configuration:

```nix
{ inputs, pkgs, ... }:
{
  home.packages = [
    inputs.nixos-doctor.packages.${pkgs.system}.default
  ];
}
```

Apply Home Manager using your existing workflow, then verify:

```sh
nixos-doctor --version
```

## First Run

Start with a non-mutating, non-root report:

```sh
nixos-doctor
```

For root-readable checks while preserving your user session:

```sh
nixos-doctor --sudo
```

For machine-readable output:

```sh
nixos-doctor --json
```

For a focused report:

```sh
nixos-doctor secureboot systemd nix
```

For slow read-only Nix and boot analysis:

```sh
nixos-doctor nix systemd --deep
```

## Verify The Installation

From a source checkout:

```sh
./tests.sh
nix flake check --all-systems
nix build .#default
```

Verify JSON output:

```sh
nixos-doctor --json >/tmp/nixos-doctor.json
python3 -m json.tool /tmp/nixos-doctor.json >/dev/null
```

Verify the current schema version:

```sh
nixos-doctor --json | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["schema_version"])'
```

The current default is schema version 2. Older consumers can request the
compatibility format:

```sh
nixos-doctor --json-v1
```

## Updating A Source Installation

```sh
cd ~/src/nixos-doctor
git pull --ff-only
./tests.sh
nix flake check --all-systems
nixos-doctor --version
```

If the repository is installed through a symlink, the symlink does not need to
change as long as the checkout path remains the same.

## Updating A Nix Profile Installation

From a local checkout:

```sh
cd ~/src/nixos-doctor
nix profile upgrade nixos-doctor
```

If the profile package name differs, inspect installed packages first:

```sh
nix profile list
```

For a GitHub flake installation, update from the remote reference using your
normal Nix profile workflow, or remove and reinstall the profile entry.

## Uninstalling

Symlink installation:

```sh
rm -f ~/.local/bin/nixos-doctor
```

Nix profile installation:

```sh
nix profile list
nix profile remove <index-or-package>
```

Source checkout installation:

```sh
rm -rf ~/src/nixos-doctor
```

Only remove the checkout after removing or updating any symlink that points to
it. The tool's audit log and backup repository are separate:

```text
~/.local/state/nixos-doctor.log
~/.local/share/nixos-doctor-backup/
```

They are not removed automatically.

## Backup Installation Notes

The diagnostic tool and configuration backup workflow are separate. A normal
doctor run never uploads anything. To preview the allowlisted configuration
backup:

```sh
nixos-doctor backup --dry-run
```

For GitHub backup setup, create a private repository, add it as `origin`, and
push only after reviewing the dry run:

```sh
git -C ~/.local/share/nixos-doctor-backup remote add origin \
  git@github.com:OWNER/PRIVATE-REPO.git
nixos-doctor backup --push
```

The backup scans for common secrets, but the scan is not proof of safety.
Review the files and repository visibility yourself.

## Troubleshooting

### `checks directory missing`

The executable was copied without its companion files, or a symlink points to
the wrong location. Recreate the symlink from the repository checkout or use a
Nix package installation.

### User-session checks are skipped

Run the command inside your normal login session. Do not use `sudo
nixos-doctor`. Use `--sudo` from your normal user account for privileged checks.

### Secure Boot checks are skipped

Run:

```sh
nixos-doctor secureboot --sudo
```

The machine must be booted in UEFI mode. `sbctl`, `bootctl`, and `efibootmgr`
are optional; missing tools are reported as skips. The tool never migrates keys,
signs artifacts, installs bootloaders, or changes firmware state automatically.

### DMS checks are skipped

Install or expose the DMS CLI in the user session, then run:

```sh
dms doctor --verbose
nixos-doctor dms --json
```

### Nix checks are skipped

Ensure `nix` is available and point the profile at the correct flake root:

```sh
NIXOS_DOCTOR_FLAKE_ROOT=/etc/nixos nixos-doctor nix --deep
```

### A report contains warnings or failures

Use the matching area directly, inspect its evidence in JSON, and consult
`AI-RUNBOOK.md`. Generate a bundle only after reviewing its privacy contents:

```sh
nixos-doctor --bundle
```

## Security and Privacy

- Normal scans do not upload data.
- Bundle journals may contain hostnames, usernames, paths, tokens, or other
  sensitive log content despite not intentionally collecting secret files.
- Backup secret scanning is a safety net, not a guarantee.
- Secure Boot, filesystem repair, rebuild, reboot, firmware, and bootloader
  changes remain manual operations.
- Review any report, bundle, backup, or issue draft before sharing it.
