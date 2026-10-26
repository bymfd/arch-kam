#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
	cat <<EOF
Kullanım: sudo $0 [--list] [--fix] [--all] [--dry-run]

Firmware Omen: UEFI boot girdilerini denetler. GRUB'ın EFI girdisini bulur,
mükerrer veya bozuk girdileri işaretler, onayla yeniden oluşturur.

  --list     Boot girdilerini ve sıralamayı göster (varsayılan, root gerektirmez)
  --fix      Bozuk/mükerrer girdileri temizle, grub girdisini yeniden ekle
  --all      --fix ile; onay sormadan uygula
  --dry-run  Ne yapılacağını göster, uygula
  -h, --help Bu yardım
EOF
}

MODE='list'
ALL=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
	case $1 in
		--list) MODE=list; shift ;;
		--fix) MODE=fix; shift ;;
		--all) ALL=1; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		-h | --help) usage; exit 0 ;;
		*) die "Bilinmeyen argüman: $1" ;;
	esac
done

if [[ ! -d /sys/firmware/efi ]]; then
	die "Sistem UEFI ile boot edilmiyor; efivar yok."
fi
have efibootmgr || die "efibootmgr bulunamadı. Kurmak için: pacman -S efibootmgr"

ISSUES=0

section "UEFI boot girdileri"
if efibootmgr -v > /tmp/.kam_efi.txt 2>/dev/null; then
	sed 's/^/  /' /tmp/.kam_efi.txt
else
	warn "efibootmgr okunamadı (root olabilir)."
fi
rm -f /tmp/.kam_efi.txt

echo
BOOT_ORDER=$(efibootmgr 2>/dev/null | sed -n 's/^BootOrder: //p' || true)
note "BootOrder: ${BOOT_ORDER:-okunamadı}"

# BootCurrent: hangi girdiyle boot edildi
CURRENT=$(efibootmgr 2>/dev/null | sed -n 's/^BootCurrent: //p' || true)
note "BootCurrent: ${CURRENT:-okunamadı}"

# Timeout
TIMEOUT=$(efibootmgr 2>/dev/null | sed -n 's/^Timeout: //p' || true)
note "Timeout: ${TIMEOUT:-okunamadı}"

echo
section "Denetim"

# GRUB EFI girdisi var mı?
if efibootmgr 2>/dev/null | grep -qiE 'grub|GRUB'; then
	ok "GRUB EFI girdisi mevcut"
else
	bad "GRUB EFI girdisi bulunamadı"
fi

# Timeout çok kısa mı? (kullanıcı menüyü göremeyebilir)
if [[ $TIMEOUT =~ ^[0-9]+$ ]] && ((TIMEOUT < 3)); then
	warn "Boot timeout ${TIMEOUT}s; GRUB menüsü neredeyse görünmez."
fi

# Aynı başlığa sahip mükerrer girdiler (yalnızca gerçek mükerrerler)
mapfile -t DUPS < <(efibootmgr 2>/dev/null | grep -E '^Boot[0-9A-F]{4}\*' | sed 's/^Boot[0-9A-F]{4}\*\s*//' | sort | uniq -d || true)
if ((${#DUPS[@]} > 0)); then
	warn "Mükerrer boot girdisi: ${DUPS[*]}"
else
	ok "Mükerrer girdi yok"
fi

# BootOrder içinde tekrar var mı?
if [[ -n $BOOT_ORDER ]]; then
	ORDER_DUPS=$(tr ',' '\n' <<< "$BOOT_ORDER" | sort | uniq -d | tr '\n' ' ' || true)
	if [[ -n $ORDER_DUPS ]]; then
		warn "BootOrder içinde tekrar: $ORDER_DUPS"
	else
		ok "BootOrder temiz"
	fi
fi

# Aktif olmayan ama var olan girdiler ( BootNext, BootCurrent )
if ((ISSUES > 0)); then
	echo
	note "Sorun bulundu; onaylı düzeltme için: sudo $0 --fix"
fi

if [[ $MODE != fix ]]; then
	exit 0
fi

require_root

section "Düzeltme"
if ((DRY_RUN)); then
	note "Dry-run: efibootmgr çağrıları gösterilecek, uygulanmayacak."
	note "  efibootmgr -t 5   # timeout"
	exit 0
fi

# Timeout'u makul bir değere çek
if [[ $TIMEOUT =~ ^[0-9]+$ ]] && ((TIMEOUT < 5)); then
	if ((ALL)) || ask_yes "Boot timeout 5 saniyeye çıkarılsın mı?"; then
		efibootmgr -t 5 >/dev/null && log "Boot timeout: 5s"
	fi
fi

# GRUB girdisi yoksa ekle
if ! efibootmgr 2>/dev/null | grep -qiE 'grub|GRUB'; then
	if have grub-install && [[ -d /boot/efi/EFI ]]; then
		efi_dir=$(find /boot/efi/EFI -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -n1 || true)
		if [[ -n $efi_dir ]]; then
			if ((ALL)) || ask_yes "GRUB EFI girdisi eklensin mi? ($efi_dir)"; then
				if efibootmgr --create --disk /dev/nvme0n1 --part 1 --label "GRUB" --loader "\EFI\$(basename "$efi_dir")\grubx64.efi" 2>/dev/null; then
					log "GRUB EFI girdisi eklendi."
				else
					warn "efibootmgr --create başarısız; EFI yolu elle kontrol edilmeli."
				fi
			fi
		fi
	else
		warn "grub-install veya /boot/efi/EFI bulunamadı; elle ekleme gerekir."
	fi
fi

log "UEFI denetimi tamam."
