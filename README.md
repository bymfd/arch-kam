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
sudo ./arch-kam.sh battery
sudo ./arch-kam.sh boot
sudo ./arch-kam.sh clean --dry-run
```

Every ritual has its own `--help`.

## Rituals

### `doctor.sh` — The Diagnosis Rite

Read-only. Checks the distribution, bootloader, root filesystem, disk space, swap/zram, hibernation support, `resume` kernel parameters, `mkinitcpio` hooks, TLP conflicts, failed systemd units, and orphan packages. It changes nothing and can run without root.

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
| `/etc/default/grub` | `.arch-kam-hibernate.bak` or `.arch-kam-boot.bak` |
| `/etc/mkinitcpio.conf` | `.arch-kam-hibernate.bak` |
| `/etc/kernel/cmdline` | `.arch-kam-hibernate.bak` |
| `/boot/loader/entries/*.conf` | `.arch-kam-hibernate.bak` |

Backups are created once and never overwritten by a later run. Remove them manually when you are sure the new state is good.

## Requirements

- Arch-based distribution (`pacman`).
- Bash, util-linux, `mkinitcpio`.
- `btrfs-progs` for BTRFS hibernation.
- `pacman-contrib` for `paccache`.
- ImageMagick only if you want to use JPG boot backgrounds.
- Root for anything that writes to the system.

## The Shamanic Tradition

In ancient Turkic spirituality, a **Kam** is a shaman, healer, and spiritual guide. They perform rituals to connect the upper and lower worlds, cure ailments, and ensure the community's well-being. These scripts are a small, modern echo of that tradition: inspect first, change carefully, and always leave a way back.
