#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
	cat <<EOF
Kullanım: sudo $0 [ritüel] [seçenekler]

Ritüeller:
  doctor      Salt okunur sistem teşhisi
  hibernate   Swap + hibernate yapılandırması
  battery     TLP / batarya yönetimi (Arkun)
  boot        GRUB arkaplan yönetimi (Tın)
  clean       Paket, journal ve yetim temizliği

  pacdiff     .pacnew / .pacsave çiftlerini denetle ve uygul
  kernel      /boot kernel ve initramfs çiftlerini denetle
  mirror      pacman mirrorlist'ini yenile
  sysupdate   Güncelleme öncesi durum ve yükseltme
  efi         UEFI boot girdilerini denetle
  microcode   initramfs ucode ve early initrd satırı
  mounts      fstab ile mount durumunu karşılaştır
  btrfs       btrfs durumu, snapshot ve alan denetimi
  zram        zram/swapfile öncelik denetimi
  security    Salt okunur güvenlik denetimi

Ritüelsiz çalıştırırsan menü açılır.
Her ritüel için: $0 <ritüel> --help
EOF
}

run_ritual() {
	local script=$1
	shift
	local path="$SCRIPT_DIR/$script"

	[[ -x $path ]] || die "$path yok veya çalıştırılabilir değil. chmod +x *.sh çalıştır."
	exec "$path" "$@"
}

menu() {
	if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
		warn "Bazı ritüeller root ister. Menüyü sudo ile çalıştırmak daha kolay."
	fi

	cat <<EOF
${C_CYAN}========================================${C_RESET}
${C_CYAN}          ARCH-KAM RİTÜEL MENÜSÜ        ${C_RESET}
${C_CYAN}========================================${C_RESET}
  --- Dişar (read) ---
 1) Doctor      — salt okunur teşhis
 2) Mounts      — fstab vs gerçek
 3) Btrfs       — durum / snapshot
 4) Security    — güvenlik denetimi
 5) Microcode   — ucode / early initrd
 6) Efi         — UEFI boot girdileri
 7) Kernel      — /boot çiftleri
 8) Mirror      — mirrorlist durumu
 9) Sysupdate   — güncelleme durumu
10) Zram        — swap önceliği
  --- Değiştiren (heal) ---
11) Pacdiff     — .pacnew çiftleri
12) Hibernate   — uyku / swap
13) Arkun       — batarya / TLP
14) Tın         — GRUB arkaplanı
15) Temizlik    — paket / journal / yetim
16) Çıkış
${C_CYAN}========================================${C_RESET}
EOF

	local choice
	read -r -p "Seçim [1-16]: " choice
	case $choice in
		1) run_ritual doctor.sh ;;
		2) run_ritual mounts.sh ;;
		3) run_ritual btrfs.sh ;;
		4) run_ritual security.sh ;;
		5) run_ritual microcode.sh ;;
		6) run_ritual efi.sh ;;
		7) run_ritual kernel.sh ;;
		8) run_ritual mirror.sh ;;
		9) run_ritual sysupdate.sh ;;
		10) run_ritual zram.sh ;;
		11) run_ritual pacdiff.sh ;;
		12) run_ritual hibernate-enabler.sh ;;
		13) run_ritual battery.sh ;;
		14) run_ritual bootloader-bg.sh ;;
		15) run_ritual clean.sh ;;
		16) exit 0 ;;
		*) die "Geçersiz seçim." ;;
	esac
}

case ${1:-} in
	doctor) shift; run_ritual doctor.sh "$@" ;;
	hibernate) shift; run_ritual hibernate-enabler.sh "$@" ;;
	battery) shift; run_ritual battery.sh "$@" ;;
	boot) shift; run_ritual bootloader-bg.sh "$@" ;;
	clean) shift; run_ritual clean.sh "$@" ;;
	pacdiff) shift; run_ritual pacdiff.sh "$@" ;;
	kernel) shift; run_ritual kernel.sh "$@" ;;
	mirror) shift; run_ritual mirror.sh "$@" ;;
	sysupdate) shift; run_ritual sysupdate.sh "$@" ;;
	efi) shift; run_ritual efi.sh "$@" ;;
	microcode) shift; run_ritual microcode.sh "$@" ;;
	mounts) shift; run_ritual mounts.sh "$@" ;;
	btrfs) shift; run_ritual btrfs.sh "$@" ;;
	zram) shift; run_ritual zram.sh "$@" ;;
	security) shift; run_ritual security.sh "$@" ;;
	-h | --help | help) usage ;;
	'') menu ;;
	*) die "Bilinmeyen ritüel: $1" ;;
esac
