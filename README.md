# arch-kam

A sacred collection of digital shamanic rituals for Arch-based Linux distributions. This repository acts as your system's *Kam*: it diagnoses possessed configs, heals broken swap states, and restores the cosmic balance of your boot setup.

> These scripts write to system files. Read the warnings, keep backups, and do not run them on a system you do not understand.

## Quick start

```bash
git clone https://github.com/bymfd/arch-kam.git
cd arch-kam
chmod +x *.sh
sudo ./arch-kam.sh
```

Run `./arch-kam.sh` without `sudo` to see the menu; privileged rituals will tell you when they need root. You can also call a ritual directly:

```bash
sudo ./arch-kam.sh doctor
sudo ./arch-kam.sh hibernate --size 32768
sudo ./arch-kam.sh pacdiff --diff
sudo ./arch-kam.sh kernel --clean --dry-run
sudo ./arch-kam.sh mirror --update
```

Every ritual has its own `--help`.

## Rituals

Read-only rituals (salt okunur) do not change anything and run without root.

### `doctor.sh` — The Diagnosis Rite

Read-only. Checks the distribution, bootloader, root filesystem, disk space, swap/zram, swap size vs RAM, hibernation support, `resume` kernel parameters, `mkinitcpio` hooks, TLP conflicts, failed systemd units, masked units, orphan packages, foreign (AUR) packages, and pending `.pacnew` files. It changes nothing.

### `pacdiff.sh` — Safeguard Rite

Finds `.pacnew` / `.pacsave` pairs pacman left behind and lets you merge them safely.

- `--list` lists pairs (default), `--quiet` prints only the count.
- `--diff` shows a unified diff per pair.
- `--resolve <file>` backs up the original, then writes the `.pacnew` over it and removes the pair.
- Reports which side is newer so you can decide.

### `kernel.sh` — Ancestor's Passage

Checks `/boot` kernel and initramfs pairs against `mkinitcpio` presets.

- Lists presets, active kernel, and files that have no matching preset.
- `--clean` removes unmatched files (skips microcode), then regenerates initramfs and bootloader.
- `--dry-run` shows what would be removed.
- Reports disk space on the boot filesystem.

### `mirror.sh` — Swift Current

Refreshes the pacman mirror list with `reflector`.

- `--list` shows reflector, timer state, and active mirror counts (default).
- `--update` runs `reflector --latest N --sort rate`, backing up existing lists to `/var/lib/arch-kam/mirrorlist`.
- `--latest N` sets the number of mirrors (default 10).
- Installs `reflector` if missing, and can refresh the package database afterwards.

### `sysupdate.sh` — Renewal Rite

Pre-flight checks, then upgrades, then a report.

- `--list` shows kernel, package count, pending updates, foreign packages, `.pacnew` pairs, disk and memory.
- `--apply` records state to `/var/log/arch-kam/`, runs `pacman -Syu`, and logs the result.
- Detects a kernel change and offers a reboot.
- `ARCH_KAM_LOG_DIR` overrides the log directory (useful for testing).

### `hibernate-enabler.sh` — The Slumber Ritual

Configures hibernation to a swap file.

- Supports BTRFS (CoW disabled) and EXT4.
- Default size is RAM + 2048 MB; override with `--size MB`.
- Checks free disk space and refuses to overwrite an existing swap file without `--force`.
- Writes `resume=` and `resume_offset=` for GRUB, systemd-boot entries, or `/etc/kernel/cmdline`.
- Inserts the `resume` mkinitcpio hook after `block`/`udev`, before `filesystems`.
- Backs up touched files as `*.arch-kam-hibernate.bak`.
- `--restore` removes the resume parameters, the hook, and the swap file.

Reboot after configuring, then test with `systemctl hibernate`.

### `battery.sh` — ARKUN, the Spirit of Endurance

TLP-based battery management.

- Installs/enables TLP with `--needed`.
- Detects a running `power-profiles-daemon` and offers to disable it first.
- Removes TLP and the arch-kam TLP drop-in.
- Shows `tlp-stat` output.
- Writes optional charge thresholds to `/etc/tlp.d/99-arch-kam.conf`.

Charge thresholds are hardware-dependent; verify them with `tlp-stat -b`.

### `bootloader-bg.sh` — TIN, Vision and Void

GRUB-only background manager.

- Sets a PNG/JPG background (JPG is converted with ImageMagick when available).
- Sets a pure black `console` mode.
- Restores the original `/etc/default/grub` from `*.arch-kam-boot.bak`.

systemd-boot does not support background images natively, so the script reports that instead of pretending otherwise.

### `efi.sh` — Firmware Omen

Inspects UEFI boot entries.

- `--list` shows BootOrder, BootCurrent, Timeout, and all entries (default, no root needed).
- Flags a missing GRUB entry, duplicate entries, a dirty BootOrder, and a too-short timeout.
- `--fix` raises the timeout and re-creates the GRUB EFI entry when missing.

### `microcode.sh` — First Light

Verifies CPU microcode loading.

- Checks for `/boot/intel-ucode.img` or `amd-ucode.img` and whether the package is installed.
- Reads `GRUB_EARLY_INITRD_LINUX_STOCK` and checks each path exists.
- Lists whether each initramfs embeds ucode (early cpio and main cpio).
- `--fix` sets the early initrd line to the ucode image and regenerates `grub.cfg`.

### `mounts.sh` — The Nine Realms

Compares `/etc/fstab` with real mount state.

- Resolves `UUID=` / `PARTUUID=` / `LABEL=` / `PARTLABEL=` through `/dev/disk/by-*`.
- Flags entries whose device cannot be found and entries that are not mounted.
- Verifies swap entries with `swapon`.
- Cross-checks btrfs subvolumes against `subvol=` options.
- `--fix` attempts to mount entries that are not mounted.

### `btrfs.sh` — Breath of the Earth

Btrfs health check.

- `--list` shows filesystem, data, metadata, subvolumes, and quota status.
- `--snapshots` lists snapshots (via snapper when configured).
- `--space` shows df and physical allocation.
- `--scrub` runs a scrub (dry-run previews the command).
- `--balance` shows a balance recommendation (dry-run previews it).

### `zram.sh` — Breath of Compression

Checks swap priority ordering between zram and the swap file.

- Lists all swap sources with priorities.
- Warns when zram outranks the swap file, which breaks hibernation.
- Shows the zram-generator configuration and device statistics.
- `--fix` re-enables the swap file with a chosen priority (`--prio N`, default 100), rolling back if it fails.

### `security.sh` — Veil of the Depths

Read-only security audit.

- `--kernel` checks `slab_nomerge`, `init_on_alloc`, `init_on_free`, `lockdown`, `bpf_jit_harden`, Secure Boot.
- `--sysctl` checks hardening sysctls (bpf, kptr, dmesg, yama, sysrq, rp_filter, redirects, martians, IPv6 RA, hardlinks, suid_dumpable).
- `--services` / `--listening` shows listening ports, firewall state, SSH root login, and fail2ban.

### `clean.sh` — The Cleanup Rite

Safe, explicit cleanup with a dry-run mode.

- `paccache -r` and `paccache -ruk0` (requires `pacman-contrib`).
- `journalctl --vacuum-time=14d`.
- Removes orphan packages after showing the list.
- Runs `systemd-tmpfiles --clean`.

Use `--dry-run` first. If `paccache` is missing, the package cache is left untouched.

## Files and backups

| File | Backup suffix |
| --- | --- |
| `/etc/default/grub` | `.arch-kam-hibernate.bak` or `.arch-kam-boot.bak` or `.arch-kam-microcode.bak` |
| `/etc/mkinitcpio.conf` | `.arch-kam-hibernate.bak` |
| `/etc/kernel/cmdline` | `.arch-kam-hibernate.bak` |
| `/boot/loader/entries/*.conf` | `.arch-kam-hibernate.bak` |
| any file resolved by `pacdiff.sh` | `.arch-kam-pacnew.bak` |

Backups are created once and never overwritten by a later run. Remove them manually when you are sure the new state is good.

`mirror.sh` keeps timestamped copies under `/var/lib/arch-kam/mirrorlist/`; `sysupdate.sh` writes state and logs under `/var/log/arch-kam/`.

## Makefile

```bash
make lint        # shellcheck if present, otherwise bash -n
make test        # syntax + basic behaviour checks
make doctor      # run doctor.sh
make install     # install rituals to /usr/local/bin
make uninstall   # remove them again
make clean-dist  # build a tarball
```

## Requirements

- Arch-based distribution (`pacman`).
- Bash, util-linux, `mkinitcpio`.
- `btrfs-progs` for BTRFS hibernation and `btrfs.sh`.
- `pacman-contrib` for `paccache`.
- `reflector` for `mirror.sh --update` (installed on demand).
- `efibootmgr` for `efi.sh`.
- ImageMagick only if you want to use JPG boot backgrounds.
- Root for anything that writes to the system.

## The Shamanic Tradition

In ancient Turkic spirituality, a **Kam** is a shaman, healer, and spiritual guide. They perform rituals to connect the upper and lower worlds, cure ailments, and ensure the community's well-being. These scripts are a small, modern echo of that tradition: inspect first, change carefully, and always leave a way back.
