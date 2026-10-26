# arch-kam

A sacred collection of digital shamanic rituals for Linux distributions. This repository acts as your system's *Kam*: it diagnoses possessed configs, heals broken swap states, and restores the cosmic balance of your boot setup.

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

## How it works

`arch-kam.sh` is a generic engine. Rituals live in `rituals/<klasör>/<ritüel>.yaml` and are executed by a shim-free Bash parser (`kam_yaml.sh`). Each ritual declares:

- `distro:` — which distributions it applies to (`arch`, `deb`, `fedora`, `alpine`, `gentoo`, `any`; `any` is the implicit fallback). The engine auto-detects your distribution and filters the list.
- `checks:` — the actual work: `command_exists`, `output`, `literal`, `swapon`, `mkinitcpio_hook`, `service_active`, `failed_units`, `masked_units`, `orphans`, `foreign`, `file_grep`, `cmdline_has`, `glob_count`, `compare` and more.
- `sections:` — grouped checks with a title, inherited by summary.
- `summary:` — `ok`/`issues` templates with `{value}`, `{count}`, `{b}` (bold white) substitutions.
- `options:` — `dry_run`, `yes`, `needs_root`, `can_write`, `commands:`, `scan_dirs:`, `suffixes:`, etc.

## Commands

```
kam.sh <command> [args]

Commands:
  list              List applicable rituals (filtered by your distro)
  --all list        List ALL rituals, ignoring distro filter
  show <ritüel>     Show a ritual's parsed config
  run <ritüel>      Execute a ritual
  menu              Interactive menu
  help              Show help
```

Ritüel adı iki biçimde olabilir: `doctor` (klasör aranır) veya `arch/hibernate` (klasör/ad). Kısayol: `deb/doctor` → `deb/doctor`, `doctor` → `common/doctor`.

## Rituals by directory

### `common/`
| Ritüel | Açıklama |
| --- | --- |
| `doctor` | Salt okunur teşhis: dağıtım, kernel, bootloader, rootfs, disk, swap, hibernate, mkinitcpio hook, TLP, servisler, yetim/AUR paketler, `.pacnew` çiftleri. |

### `arch/`
| Ritüel | Açıklama |
| --- | --- |
| `pacdiff` | `.pacnew` / `.pacsave` çiftlerini bul, göster, çözümle. |
| `hibernate` | Swap + hibernate: swap dosyası, `resume=` parametresi, `mkinitcpio` hook. |

### `deb/`
| Ritüel | Açıklama |
| --- | --- |
| `aptclean` | `apt` önbelleği, artık paket, journal temizliği. |
| `doctor` | Debian/Ubuntu sistemin salt okunur teşhisi. |

### `fedora/`
| Ritüel | Açıklama |
| --- | --- |
| `doctor` | Fedora/RHEL sistemin salt okunur teşhisi. |
| `dnfclean` | `dnf` önbellek, artık paket, journal temizliği. |

### `alpine/`
| Ritüel | Açıklama |
| --- | --- |
| `apktool` | `apk` temizliği ve hızlı durum özeti. |

### `gentoo/`
| Ritüel | Açıklama |
| --- | --- |
| `emergeclean` | `emerge` ile artık paket ve önbellek temizliği. |

### `fix/`
| Ritüel | Açıklama |
| --- | --- |
| `pacnew` | `.pacnew`/`.pacsave` çiftlerini bul ve listele. |
| `brokenlinks` | Sistemdeki kırık symlink'leri bul. |

### `apps/`
| Ritüel | Açıklama |
| --- | --- |
| `firewall` | Dağıtım güvenlik duvarını etkinleştir ve durumunu göster. |
| `docker` | Kullanılmayan Docker imajı, konteyner ve volume'leri temizle. |

## Workflow per ritual

Read-only rituals (salt okunur) do not change anything and run without root.

### Safeguard Rite — `.pacnew` / `.pacsave`

Finds `.pacnew` / `.pacsave` pairs and lets you merge them safely.

- `--list` (default) lists pairs
- `--diff` shows a unified diff per pair
- `--resolve <file>` backs up the original, writes the `.pacnew` over it, and removes the pair

Reports which side is newer so you can decide.

### Kernel's Passage

Checks `/boot` kernel and initramfs pairs against `mkinitcpio` presets.

- Lists presets, active kernel, and files without a matching preset
- `--clean` removes unmatched files, then regenerates initramfs and bootloader
- `--dry-run` shows what would be removed

### Swift Current

Refreshes the package mirror list.

- `--list` shows reflector, timer state, and active mirror counts
- `--update` runs `reflector --latest N --sort rate`, backing up existing lists to `/var/lib/arch-kam/mirrorlist`

### Renewal Rite

Pre-flight checks, then upgrades, then a report.

- `--list` shows kernel, package count, pending updates, foreign packages, `.pacnew` pairs, disk and memory
- `--apply` records state to `/var/log/arch-kam/`, runs `pacman -Syu`, and logs the result

### Slumber Ritual

Configures hibernation to a swap file.

- Supports BTRFS (CoW disabled) and EXT4
- Default size is RAM + 2048 MB; override with `--size MB`
- Checks free disk space and refuses to overwrite an existing swap file without `--force`
- Writes `resume=` and `resume_offset=` for GRUB, systemd-boot entries, or `/etc/kernel/cmdline`
- Inserts the `resume` mkinitcpio hook after `block`/`udev`, before `filesystems`
- Backs up touched files as `*.arch-kam-hibernate.bak`
- `--restore` removes the resume parameters, the hook, and the swap file

Reboot after configuring, then test with `systemctl hibernate`.

### ARKUN, the Spirit of Endurance

TLP-based battery management.

- Installs/enables TLP with `--needed`
- Detects a running `power-profiles-daemon` and offers to disable it first
- Removes TLP and the arch-kam TLP drop-in
- Shows `tlp-stat` output
- Writes optional charge thresholds to `/etc/tlp.d/99-arch-kam.conf`

Charge thresholds are hardware-dependent; verify them with `tlp-stat -b`.

### TIN, Vision and Void

GRUB-only background manager.

- Sets a PNG/JPG background (JPG is converted with ImageMagick when available)
- Sets a pure black `console` mode
- Restores the original `/etc/default/grub` from `*.arch-kam-boot.bak`

systemd-boot does not support background images natively, so the script reports that instead of pretending otherwise.

### Firmware Omen

Inspects UEFI boot entries.

- `--list` shows BootOrder, BootCurrent, Timeout, and all entries (default, no root needed)
- Flags a missing GRUB entry, duplicate entries, a dirty BootOrder, and a too-short timeout
- `--fix` raises the timeout and re-creates the GRUB EFI entry when missing

### First Light

Verifies CPU microcode loading.

- Checks for `/boot/intel-ucode.img` or `amd-ucode.img` and whether the package is installed
- Reads `GRUB_EARLY_INITRD_LINUX_STOCK` and checks each path exists
- Lists whether each initramfs embeds ucode (early cpio and main cpio)
- `--fix` sets the early initrd line to the ucode image and regenerates `grub.cfg`

### The Nine Realms

Compares `/etc/fstab` with real mount state.

- Resolves `UUID=` / `PARTUUID=` / `LABEL=` / `PARTLABEL=` through `/dev/disk/by-*`
- Flags entries whose device cannot be found and entries that are not mounted
- Verifies swap entries with `swapon`
- Cross-checks btrfs subvolumes against `subvol=` options
- `--fix` attempts to mount entries that are not mounted

### Breath of the Earth

Btrfs health check.

- `--list` shows filesystem, data, metadata, subvolumes, and quota status
- `--snapshots` lists snapshots (via snapper when configured)
- `--space` shows df and physical allocation
- `--scrub` runs a scrub (dry-run previews the command)
- `--balance` shows a balance recommendation (dry-run previews it)

### Breath of Compression

Checks swap priority ordering between zram and the swap file.

- Lists all swap sources with priorities
- Warns when zram outranks the swap file, which breaks hibernation
- Shows the zram-generator configuration and device statistics
- `--fix` re-enables the swap file with a chosen priority (`--prio N`, default 100), rolling back if it fails

### Veil of the Depths

Read-only security audit.

- `--kernel` checks `slab_nomerge`, `init_on_alloc`, `init_on_free`, `lockdown`, `bpf_jit_harden`, Secure Boot
- `--sysctl` checks hardening sysctls (bpf, kptr, dmesg, yama, sysrq, rp_filter, redirects, martians, IPv6 RA, hardlinks, suid_dumpable)
- `--services` / `--listening` shows listening ports, firewall state, SSH root login, and fail2ban

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

- Bash, util-linux, `mkinitcpio`.
- `btrfs-progs` for BTRFS hibernation and `btrfs.sh`.
- `pacman-contrib` for `paccache`.
- `reflector` for `mirror.sh --update` (installed on demand).
- `efibootmgr` for `efi.sh`.
- ImageMagick only if you want to use JPG boot backgrounds.
- Root for anything that writes to the system.

## The Shamanic Tradition

In ancient Turkic spirituality, a **Kam** is a shaman, healer, and spiritual guide. They perform rituals to connect the upper and lower worlds, cure ailments, and ensure the community's well-being. These scripts are a small, modern echo of that tradition: inspect first, change carefully, and always leave a way back.
