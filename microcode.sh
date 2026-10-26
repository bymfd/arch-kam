#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

GRUB_FILE=/etc/default/grub
BOOT_DIR=/boot

usage() {
	cat <<EOF
Kullanım: sudo $0 [--list] [--fix] [--dry-run]

First Light: initramfs'in microcode (CPU firmware) içerip içermediğini ve
GRUB'ın early initrd satırının doğru olup olmadığını denetler.

  --list     Mevcut durumu göster (varsayılan, root gerektirmez)
  --fix      GRUB_EARLY_INITRD_LINUX_STOCK satırını ucode ile doldur
  --dry-run  Ne değişeceğini göster
  -h, --help Bu yardım
EOF
}

MODE='list'
DRY_RUN=0

while [[ $# -gt 0 ]]; do
	case $1 in
		--list) MODE=list; shift ;;
		--fix) MODE=fix; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		-h | --help) usage; exit 0 ;;
		*) die "Bilinmeyen argüman: $1" ;;
	esac
done

ISSUES=0

section "Microcode / early initrd"

# Ucode dosyası hangi mimari?
UCODE_IMG=''
for cand in "$BOOT_DIR/intel-ucode.img" "$BOOT_DIR/amd-ucode.img"; do
	if [[ -f $cand ]]; then
		UCODE_IMG=$cand
		break
	fi
done

if [[ -n $UCODE_IMG ]]; then
	ok "Ucode imajı mevcut: $(basename "$UCODE_IMG")"
else
	bad "Ucode imajı bulunamadı (/boot/intel-ucode.img veya amd-ucode.img)"
fi

# Ucode paketi kurulu mu?
if have pacman; then
	if pacman -Q intel-ucode >/dev/null 2>&1; then
		ok "intel-ucode kurulu"
	elif pacman -Q amd-ucode >/dev/null 2>&1; then
		ok "amd-ucode kurulu"
	else
		warn "Ne intel-ucode ne amd-ucode kurulu görünüyor."
	fi
fi

echo
section "GRUB early initrd satırı"
if [[ -f $GRUB_FILE ]]; then
	if grep -qE '^GRUB_EARLY_INITRD_LINUX_STOCK=' "$GRUB_FILE"; then
		line=$(grep -E '^GRUB_EARLY_INITRD_LINUX_STOCK=' "$GRUB_FILE" | tail -n1)
		value=$(strip_quotes "${line#GRUB_EARLY_INITRD_LINUX_STOCK=}")
		if [[ -z $value ]]; then
			bad "GRUB_EARLY_INITRD_LINUX_STOCK boş; ucode initramfs'e gömülü olmayabilir."
			warn "Değer olmadan microcode yalnızca initramfs içinde uygulanır."
		else
			ok "GRUB_EARLY_INITRD_LINUX_STOCK=$value"
			for part in $value; do
				[[ -f $part ]] && ok "  $part mevcut" || bad "  $part bulunamadı"
			done
		fi
	else
		note "GRUB_EARLY_INITRD_LINUX_STOCK satırı yok (mkinitcpio preset'i ucode'i initramfs'e gömüyor olabilir)."
	fi
else
	warn "$GRUB_FILE okunamadı."
fi

echo
section "initramfs ucode içeriği"
found_ucode=0
for img in "$BOOT_DIR"/initramfs-*.img; do
	[[ -f $img ]] || continue
	name=$(basename "$img")

	# 1) early cpio içinde ucode var mı? (ucode genelde buraya gömülür)
	early=0
	if have lsinitcpio; then
		if lsinitcpio --early -l "$img" 2>/dev/null | grep -qiE 'ucode|microcode'; then
			early=1
		fi
	fi

	# 2) normal cpio içinde ucode var mı?
	main=0
	if have lsinitcpio; then
		if lsinitcpio -l "$img" 2>/dev/null | grep -qiE 'ucode|microcode'; then
			main=1
		fi
	elif have unzip; then
		if unzip -l "$img" 2>/dev/null | grep -qiE 'ucode|microcode'; then
			main=1
		fi
	fi

	if ((early || main)); then
		where='main'
		((early)) && where='early'
		((early && main)) && where='early+main'
		ok "$name: ucode içeriyor ($where)"
		found_ucode=1
	else
		note "$name: ucode içermiyor (early initrd satırına bak)"
	fi
done
if ((found_ucode == 0)); then
	warn "Hiçbir initramfs ucode içermiyor; early initrd satırını kontrol et."
fi

if [[ $MODE != fix ]]; then
	echo
	note "Düzeltmek için: sudo $0 --fix"
	exit 0
fi

require_root
[[ -f $GRUB_FILE ]] || die "$GRUB_FILE yok."

section "Düzeltme"
new_value=''
if [[ -f $BOOT_DIR/intel-ucode.img ]]; then
	new_value="$BOOT_DIR/intel-ucode.img"
elif [[ -f $BOOT_DIR/amd-ucode.img ]]; then
	new_value="$BOOT_DIR/amd-ucode.img"
else
	die "Ucode imajı yok; düzeltme yapılamaz."
fi

current=$(grep -E '^GRUB_EARLY_INITRD_LINUX_STOCK=' "$GRUB_FILE" | tail -n1 | sed -E "s/^GRUB_EARLY_INITRD_LINUX_STOCK=['\"]?//; s/['\"]$//" || true)
if [[ $current == "$new_value" ]]; then
	ok "Early initrd satırı zaten doğru: $new_value"
	exit 0
fi

if ((DRY_RUN)); then
	printf '  [dry-run] GRUB_EARLY_INITRD_LINUX_STOCK=%s\n' "$new_value"
	exit 0
fi

backup_once "$GRUB_FILE" arch-kam-microcode.bak
if upsert_line "$GRUB_FILE" '^GRUB_EARLY_INITRD_LINUX_STOCK=' "GRUB_EARLY_INITRD_LINUX_STOCK=\"$new_value\""; then
	log "Early initrd satırı güncellendi: $new_value"
else
	die "Satır güncellenemedi."
fi

BOOTLOADER=$(detect_bootloader)
if [[ $BOOTLOADER == grub ]]; then
	grub-mkconfig -o /boot/grub/grub.cfg && log "grub.cfg yenilendi."
else
	warn "Bootloader grub değil; grub.cfg elle yenilenmeli."
fi
log "Microcode denetimi tamam."
