#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

LOG_DIR=/var/log/arch-kam

usage() {
	cat <<EOF
Kullanım: sudo $0 [--list] [--apply] [--all] [--reboot]

Renewal Rite: güncelleme öncesi sistemi denetler, paketleri yükseltir,
sonucu raporlar. Yedeği ve geri dönüş bilgisini tutar.

  --list     Mevcut durumu göster, güncelleme yapma (varsayılan)
  --apply    Pacman veritabanını tazele ve sistemi yükselt
  --all      --apply ile; onay sormadan uygula
  --reboot   --apply sonrası yeniden başlat
  -h, --help Bu yardım
EOF
}

MODE='list'
ALL=0
DO_REBOOT=0

while [[ $# -gt 0 ]]; do
	case $1 in
		--list) MODE=list; shift ;;
		--apply) MODE=apply; shift ;;
		--all) ALL=1; shift ;;
		--reboot) DO_REBOOT=1; shift ;;
		-h | --help) usage; exit 0 ;;
		*) die "Bilinmeyen argüman: $1" ;;
	esac
done

require_arch
ISSUES=0

LOG_DIR=${ARCH_KAM_LOG_DIR:-/var/log/arch-kam}
PENDING_FILE="$LOG_DIR/pending.txt"

section "Yükseltme öncesi durum"

BEFORE_KERNEL=$(uname -r)
BEFORE_PKGS=$(pacman -Q 2>/dev/null | wc -l)
note "Kernel: $BEFORE_KERNEL"
note "Kurulu paket: $BEFORE_PKGS"

mapfile -t PENDING < <(checkupdates 2>/dev/null || true)
mkdir -p "$LOG_DIR"
PENDING_FILE="$LOG_DIR/pending.txt"
if ((${#PENDING[@]} > 0)); then
	warn "${#PENDING[@]} güncelleme var:"
	if printf '%s\n' "${PENDING[@]}" > "$PENDING_FILE"; then
		head -20 "$PENDING_FILE" | sed 's/^/    /'
	fi
	((${#PENDING[@]} > 20)) && note "... ve $(( ${#PENDING[@]} - 20 )) tane daha"
else
	ok "Sistem güncel görünüyor."
fi

mapfile -t FOREIGN < <(pacman -Qmq 2>/dev/null || true)
if ((${#FOREIGN[@]} > 0)); then
	note "Foreign (AUR) paketler: ${#FOREIGN[@]} — pacman bunları yükseltmez; yay/paru gerekir."
fi

PACNEW_COUNT=$(find /etc -name '*.pacnew' 2>/dev/null | wc -l || true)
if ((PACNEW_COUNT > 0)); then
	warn "$PACNEW_COUNT .pacnew çifti bekliyor (sudo $SCRIPT_DIR/pacdiff.sh --list)"
fi

echo
section "Disk ve bellek"
df -h / /boot 2>/dev/null | sed 's/^/  /' || true
free -h | sed 's/^/  /'

if [[ $MODE != apply ]]; then
	echo
	note "Yükseltmek için: sudo $0 --apply"
	exit 0
fi

require_root

if ((${#PENDING[@]} == 0)); then
	ok "Yükseltilecek paket yok; sistem zaten güncel."
	exit 0
fi

section "Yükseltme"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/sysupdate-$(date +%Y%m%d-%H%M%S).log"

if ! ((ALL)) && ! ask_yes "${#PENDING[@]} paket yükseltilsin mi?"; then
	note "Vazgeçildi."
	exit 0
fi

# Yükseltmeden önce durum kaydı: geri dönüş noktası.
printf 'kernel: %s\npackages: %s\ntime: %s\n' "$BEFORE_KERNEL" "$BEFORE_PKGS" "$(date -Is)" > "$LOG_DIR/last-state.txt"
log "Durum kaydı: $LOG_DIR/last-state.txt"

# Pacnew çiftlerini yükseltme öncesi not et; yükseltme sonrası temizlik kolaylaşır.
find /etc -name '*.pacnew' -printf '%p\n' 2>/dev/null > "$LOG_DIR/pacnew-before.txt" || true

pacman -Syu --noconfirm 2>&1 | tee "$LOG_FILE"
rc=${PIPESTATUS[0]}
log "Yükseltme kaydı: $LOG_FILE"

if ((rc != 0)); then
	error "pacman yükseltmesi başarısız (rc=$rc)."
	warn "Geri dönüş için: pacman -U /var/cache/pacman/pkg/<eski-paket>.pkg.tar.zst"
	exit 1
fi

AFTER_KERNEL=$(uname -r)
AFTER_PKGS=$(pacman -Q 2>/dev/null | wc -l)
printf 'kernel: %s -> %s\npackages: %s -> %s\n' "$BEFORE_KERNEL" "$AFTER_KERNEL" "$BEFORE_PKGS" "$AFTER_PKGS" >> "$LOG_DIR/last-state.txt"

if [[ $BEFORE_KERNEL != "$AFTER_KERNEL" ]]; then
	warn "Kernel değişti: $BEFORE_KERNEL -> $AFTER_KERNEL"
	warn "Yeni kernel yalnızca yeniden başlatınca etkin olur."
	DO_REBOOT=1
fi

NEW_PACNEW=$(find /etc -name '*.pacnew' 2>/dev/null | wc -l)
((NEW_PACNEW > PACNEW_COUNT)) && warn "Yeni .pacnew çiftleri oluştu: sudo $SCRIPT_DIR/pacdiff.sh --list"

if ((DO_REBOOT)); then
	if ((ALL)) || ask_yes "Yeniden başlatılsın mı?"; then
		log "Yeniden başlatılıyor..."
		shutdown -r now
	fi
fi

log "Yükseltme tamam."
