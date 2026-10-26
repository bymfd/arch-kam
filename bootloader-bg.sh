#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

GRUB_FILE=/etc/default/grub
GRUB_CFG=/boot/grub/grub.cfg
GRUB_DIR=/boot/grub
BACKUP_FILE="$GRUB_FILE.arch-kam-boot.bak"
BG_FILE="$GRUB_DIR/tin_bg.png"

usage() {
	cat <<EOF
Kullanım: sudo $0

Tın ritüeli (yalnızca GRUB):
  1) Özel arkaplan görseli (PNG/JPG)
  2) Saf siyah / terminal modu
  3) Yedeğe dön
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
	usage
	exit 0
fi
[[ $# -eq 0 ]] || die "Bilinmeyen argüman: $1"

require_root
require_arch

BOOTLOADER=$(detect_bootloader)
case $BOOTLOADER in
	grub) ;;
	systemd-boot) die "systemd-boot arkaplan görseli desteklemiyor. Bu ritüel yalnızca GRUB için." ;;
	*) die "GRUB bulunamadı." ;;
esac

[[ -f $GRUB_FILE ]] || die "$GRUB_FILE yok."
[[ -d $GRUB_DIR ]] || die "$GRUB_DIR yok."
have grub-mkconfig || die "grub-mkconfig bulunamadı."

if [[ ! -f $BACKUP_FILE ]]; then
	cp -a "$GRUB_FILE" "$BACKUP_FILE"
	log "Yedek: $BACKUP_FILE"
fi

apply_grub() {
	grub-mkconfig -o "$GRUB_CFG"
}

set_image() {
	local img=$1 mime

	[[ -f $img ]] || die "Dosya yok: $img"

	mime=$(file --mime-type -b "$img" 2>/dev/null || true)
	if [[ -z $mime ]]; then
		case ${img##*.} in
			png | PNG) mime=image/png ;;
			jpg | jpeg | JPG | JPEG) mime=image/jpeg ;;
		esac
	fi

	case $mime in
		image/png)
			install -m 644 "$img" "$BG_FILE"
			;;
		image/jpeg)
			if have magick; then
				magick "$img" "$BG_FILE"
			elif have convert; then
				convert "$img" "$BG_FILE"
			else
				die "JPG verildi ama ImageMagick yok. PNG kullan."
			fi
			chmod 644 "$BG_FILE"
			;;
		*)
			die "PNG veya JPG olmalı (bulunan: ${mime:-bilinmiyor})."
			;;
	esac

	sed -i -E 's/^GRUB_THEME=/#GRUB_THEME=/' "$GRUB_FILE"
	sed -i -E 's/^GRUB_TERMINAL_OUTPUT=/#GRUB_TERMINAL_OUTPUT=/' "$GRUB_FILE"
	sed -i -E '/^GRUB_BACKGROUND=/d' "$GRUB_FILE"
	printf 'GRUB_BACKGROUND="%s"\n' "$BG_FILE" >> "$GRUB_FILE"
	apply_grub
	log "Görsel ayarlandı. Yeniden başlatınca görünür."
}

set_void() {
	sed -i -E 's/^GRUB_THEME=/#GRUB_THEME=/' "$GRUB_FILE"
	sed -i -E 's/^GRUB_BACKGROUND=/#GRUB_BACKGROUND=/' "$GRUB_FILE"

	if grep -qE '^GRUB_TERMINAL_OUTPUT=' "$GRUB_FILE"; then
		sed -i -E 's/^GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT="console"/' "$GRUB_FILE"
	else
		printf 'GRUB_TERMINAL_OUTPUT="console"\n' >> "$GRUB_FILE"
	fi

	apply_grub
	log "Void ayarlandı. Sadece karanlık kaldı."
}

restore_default() {
	[[ -f $BACKUP_FILE ]] || die "Yedek yok: $BACKUP_FILE"
	cp -a "$BACKUP_FILE" "$GRUB_FILE"
	apply_grub
	log "Varsayılan ayarlar geri yüklendi."
}

cat <<EOF
${C_CYAN}=======================================${C_RESET}
${C_CYAN}        TIN: The Vision Ritual         ${C_RESET}
${C_CYAN}     (GRUB Bootloader Manager)         ${C_RESET}
${C_CYAN}=======================================${C_RESET}
1) ${C_GREEN}Vision:${C_RESET} özel görsel (PNG/JPG)
2) ${C_RED}Void:${C_RESET} saf siyah / terminal modu
3) ${C_CYAN}Restore:${C_RESET} yedeğe dön
4) Çıkış
${C_CYAN}=======================================${C_RESET}
EOF

read -r -p "Seçim [1-4]: " choice
case $choice in
	1)
		read -r -p "Görselin tam yolu: " img
		set_image "$img"
		;;
	2) set_void ;;
	3) restore_default ;;
	4) exit 0 ;;
	*) die "Geçersiz seçim." ;;
esac
