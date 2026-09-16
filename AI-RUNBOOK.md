# nixos-doctor AI runbook

How any AI (or human) diagnoses a NixOS box the same way every time.
Start with `nixos-doctor <area>` for the subsystem, escalate as noted.
Example profile: NVIDIA GPU/proprietary driver, mango + DMS session, flake
`/etc/nixos#nixos`, systemd-boot + Secure Boot (sbctl), ext4 (no
snapshots — rollback = boot menu only), nh-managed GC. Adapt paths and
sessions to the machine under test.

## Boot / generations
- **No GUI after rebuild** → `nixos-doctor boot generations services`;
  check booted-vs-current mismatch; `bootctl status`; last errors
  `journalctl -b -1 -p err`. Roll back: pick previous gen in boot menu.
- **Machine won't boot at all** (manual `#ch-troubleshooting` flows):
  at the boot menu pick an older generation; if the menu itself is
  broken, boot the NixOS installer USB, `nixos-enter`, fix config,
  `nixos-rebuild boot`. Kernel-param rescue without USB: edit the
  boot entry (`e`), append `systemd.unit=rescue.target` (or
  `emergency`), boot, fix, `systemctl reboot`.
- **Rebuilds keep failing, system still runs** → expected: NixOS
  switch is atomic, the running system is untouched until a switch
  succeeds. Fix config, rebuild again; never reboot mid-debug "to
  see if it helps" (reboot changes nothing about a failed eval).
- **Rollback permanently** → boot the good generation, then
  `nixos-rebuild switch --rollback` to make it current.
- **Boot-menu entry missing** → ESP mounted? `/boot/loader/entries`
  ([R]); `bootctl install` territory (Tier 2).
- **Secure-Boot refuses kernel** → `sbctl verify` ([R]); re-sign flow.
- **Login loop / greeter dead** → `systemctl status dms-greeter
  greetd`; greeter compositor (hyprland) logs.
- **Rebuild fails (eval)** → rerun with `--show-trace`, first
  file:line wins; `nix-instantiate --parse` the file.
- **Rebuild OOM** → `free`, retry `--option max-jobs 1 --option cores 2`
  (low-build-concurrency retry for OOM-prone builders).
- **Flake lock conflict / stale pins** → lock age, `nix flake update`
  single input first, dry-build before switch.

## Desktop (mango/DMS/Hyprland/KDE)
- **Black screen in mango** → `mango -p` config first; then
  `mango-session.target` + `dms.service` states; journal user errors.
- **DMS bar gone** → toggle script state (`barConfigs[0].enabled`
  flips + reload), island vs bar mode.
- **Cheatsheet empty** → `dms keybinds show mangowc` row count; DMS
  parses only `bind=` at column 1 (indented media.conf binds are
  invisible by design).
- **Keyboard dead in overlay** → layer-shell Exclusive focus; known
  quickshell-0.3+mango quirk, prefer DMS-native modals.
- **Admin prompts never appear** → no polkit auth agent in mango
  sessions (daemon alone insufficient); needs exec-once agent.
- **Screenshare black / file picker wrong** → portals active?
  (`xdg-desktop-portal*` user units), `XDG_CURRENT_DESKTOP` set,
  wlr portal routed for mango session.
- **KDE session broken / plasmashell crash-loop** → `nixos-doctor
  kde services journal`; top crashers via `coredumpctl -F
  COREDUMP_EXE`; baloo churn (`balooctl6 status` waiting count);
  greetd-vs-sddm seat check; plasma user units
  (`plasma-kactivitymanagerd`, `plasma-dolphin` fail here today).
- **Hyprland session issues** → `nixos-doctor hyprland graphics`;
  hyprctl IPC, config files, quickshell shell running, log tail.
- **Steam games slow/huge** → `nixos-doctor gaming hardware`;
  shader cache size, gamemode missing?, VRAM pressure, GBM renderer.
- **X11 app blank** → `mmsg get all-clients` `is_xwayland` flags;
  vesktop/upscayl are deliberately X11-wrapped here.

## System
- **No audio / mic dead** → pipewire+wireplumber+pulse user units;
  `wpctl status`; kernel firmware lines.
- **Bluetooth flaps** → adapter power, journal disconnect storms.
- **Wi-Fi drops / DNS dead** → NM vs networkd conflict check;
  `resolvectl`; disconnect counts in journal.
- **Suspend never wakes / hibernate fails** → swap/zram present?;
  `nvidia-suspend` hook enabled?; resume error lines.
- **Games stutter / tearing** → GBM renderer is NVIDIA (not
  llvmpipe); fullscreen + bars hidden for direct scanout;
  syncobj default-on; VRR via mmsg.
- **Disk full / store huge** → generations count, GC roots
  (`result*` links), journal size, flatpak/podman reclaimable.
- **Fan full blast idle** → temps, runaway process (top RSS),
  large GPU/model services running needlessly (manual-start pattern).
- **Clock wrong → TLS errors** → NTP sync state first, always.

## Configuration backup
- **Back up NixOS and dotfiles** → first run `nixos-doctor backup --dry-run`;
  review the allowlisted paths and secret-scan result, then run
  `nixos-doctor backup` to create a local Git commit.
- **Back up to GitHub** → create a private repository, add it as `origin` in
  `~/.local/share/nixos-doctor-backup`, then run `nixos-doctor backup --push`.
  Confirm the `YES` prompt only after checking the remote and the dry-run.
- **Secret concern** → the backup rejects common token/key/password patterns,
  but that scan is not proof of safety. Never add secret files, API keys,
  environment files, SSH keys, or private material to a configuration backup.

## Escalate when
Hardware SMART failure, filesystem errors, unsigned kernels you did
not expect, repeated OOMs with headroom, upstream (NVIDIA/mango)
bugs — collect `--bundle` and take it to issue trackers with the
report attached.
