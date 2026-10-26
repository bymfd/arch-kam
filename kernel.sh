#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

BOOT_DIR=/boot
PRESET_DIR=/etc/mkinitcpio.d
MIN_FREE_KB=$((1024 * 1024)) # 1 GB

usage() {
	cat <<EOF
Kullanım: sudo $0 [--list] [--clean] [--all] [--dry-run]

Ancestor's Passage: /boot içindeki kernel ve initramfs çiftlerini denetler,
mkinitcpio preset'i eşleşmeyen eski dosyaları listeler, onayla temizler.

  --list     Çiftleri ve eşleşmeyenleri listele (varsayılan)
  --clean    Eşleşmeyen ve onaylanan dosyaları sil, sonra initramfs + grub yenile
  --all      --clean ile; onay sormadan uygula
  --dry-run  Ne silineceğini göster, silme
  -h, --help Bu yardım
EOF
}

MODE='list'
ALL=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
	case $1 in
		--list) MODE=list; shift ;;
		--clean) MODE=clean; shift ;;
		--all) ALL=1; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		-h | --help) usage; exit 0 ;;
		*) die "Bilinmeyen argüman: $1" ;;
	esac
done

require_arch
have mkinitcpio || die "mkinitcpio bulunamadı."
[[ -d $BOOT_DIR ]] || die "$BOOT_DIR yok."

ISSUES=0

# Aktif kernel ve preset'lerle eşleşen kernel adlarını üret.
kernel_names() {
	local preset
	for preset in "$PRESET_DIR"/*.preset; do
		[[ -f $preset ]] || continue
		basename "$preset" .preset
	done
}

# /boot altında bulunan vmlinuz-* / initramfs-* çiftlerini listele.
boot_files() {
	local pattern
	for pattern in 'vmlinuz-*' 'initramfs-*' 'ucode.img' 'intel-ucode.img' 'amd-ucode.img'; do
		for f in "$BOOT_DIR"/$pattern; do
			[[ -f $f ]] && printf '%s\n' "$f"
		done
	done
}

mapfile -t KERNELS < <(kernel_names | sort -u)
mapfile -t FILES < <(boot_files | sort -u)

section "Kernel çiftleri"
note "Preset'ler: ${KERNELS[*]:-yok}"
note "Aktif kernel: $(uname -r)"
echo

section "Eşleşmeyen /boot dosyaları"
ORPHANS=()
for f in "${FILES[@]}"; do
	name=$(basename "$f")
	stem=""
	case $name in
		vmlinuz-*) stem=vmlinuz ;;
		initramfs-*) stem=initramfs ;;
		*ucode.img) stem=ucode ;;
	esac
	match=0
	for k in "${KERNELS[@]}"; do
		[[ $name == ${stem}-${k} || $name == ${stem}-${k}.img ]] && { match=1; break; }
	done
	if [[ $stem == ucode && ! -f $BOOT_DIR/vmlinuz-* ]]; then
		match=1
	fi
	if ((match)); then
		ok "$name (preset eşleşiyor)"
	else
		bad "$name (eşleşen preset yok)"
		ORPHANS+=("$f")
	fi
done

if ((${#ORPHANS[@]} == 0)); then
	ok "Eşleşmeyen dosya yok."
fi

echo
# mkinitcpio preset'i kernel adını kullanır (örn. linux-cachyos); uname -r sürüm tanelidir.
preset_ok=0
for k in "${KERNELS[@]}"; do
	[[ -f $BOOT_DIR/vmlinuz-$k ]] && preset_ok=1
done
if ((preset_ok)); then
	ok "Kernel preset'leri için initramfs mevcut"
else
	bad "Hiçbir preset initramfs ile eşleşmiyor"
fi

echo
section "Alan"
df -h "$BOOT_DIR" | sed 's/^/  /'

if [[ $MODE != clean ]]; then
	echo
	note "Temizlemek için: sudo $0 --clean"
	exit 0
fi

if ((${#ORPHANS[@]} == 0)); then
	ok "Silinecek eşleşmeyen dosya yok."
	exit 0
fi

section "Temizlik"
for f in "${ORPHANS[@]}"; do
	if ((DRY_RUN)); then
		printf '  [dry-run] silinecek: %s\n' "$f"
	else
		printf '  silinecek: %s\n' "$f"
	fi
done

if ((DRY_RUN)); then
	note "Dry-run; hiçbir şey silinmedi."
	exit 0
fi

require_root

if ! ((ALL)) && ! ask_yes "${#ORPHANS[@]} dosya silinsin mi?"; then
	note "Vazgeçildi."
	exit 0
fi

for f in "${ORPHANS[@]}"; do
	if [[ $f == *ucode* || $f == *microcode* ]]; then
		warn "ucode dosyası atlandı (elle karar ver): $f"
		continue
	fi
	if rm -f -- "$f"; then
		log "Silindi: $f"
	else
		warn "Silinemedi: $f"
	fi
done

BOOTLOADER=$(detect_bootloader)
if [[ $BOOTLOADER == grub ]]; then
	have grub-mkconfig || die "grub-mkconfig bulunamadı."
	grub-mkconfig -o /boot/grub/grub.cfg
fi
mkinitcpio -P
log "initramfs ve bootloader yenilendi."

if have pacman; then
	local_pkgs=$(pacman -Qq 'linux*' 2>/dev/null || true)
	if [[ -n $local_pkgs ]]; then
		note "Kurulu linux* paketleri (elle denetle):"
		printf '    %s\n' "$local_pkgs"
	fi
fi
