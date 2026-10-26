#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

TLP_CONF=/etc/tlp.d/99-arch-kam.conf

usage() {
	cat <<EOF
Kullanım: sudo $0

Arkun ritüeli:
  1) TLP kur ve etkinleştir
  2) TLP kaldır
  3) TLP durumunu göster
  4) Batarya şarj eşiklerini ayarla
EOF
}

ppd_present() {
	systemctl list-unit-files power-profiles-daemon.service --no-legend 2>/dev/null | grep -q .
}

ppd_running() {
	systemctl is-active --quiet power-profiles-daemon.service 2>/dev/null ||
		systemctl is-enabled --quiet power-profiles-daemon.service 2>/dev/null
}

install_tlp() {
	if ppd_present && ppd_running; then
		warn "power-profiles-daemon etkin; TLP ile çakışır."
		if confirm "power-profiles-daemon devre dışı bırakılsın mı?"; then
			systemctl disable --now power-profiles-daemon.service
		else
			die "TLP kurulmadı; önce power-profiles-daemon'u kapat."
		fi
	fi

	pacman -S --needed --noconfirm tlp
	systemctl enable --now tlp.service
	log "TLP kuruldu ve etkinleştirildi."
}

remove_tlp() {
	systemctl disable --now tlp.service 2>/dev/null || true
	pacman -Rs --noconfirm tlp 2>/dev/null || warn "TLP paketi zaten kurulu değil."
	rm -f "$TLP_CONF"
	log "TLP ve arch-kam yapılandırması kaldırıldı."
}

status_tlp() {
	if ! have tlp-stat; then
		warn "TLP kurulu değil."
		return
	fi

	tlp-stat -s || true
	echo
	tlp-stat -b || true
}

charge_thresholds() {
	if ! have tlp-stat; then
		die "Önce TLP'yi kur."
	fi

	echo "Mevcut batarya durumu:"
	tlp-stat -b || true
	echo

	local start stop
	read -r -p "Başlangıç eşiği (örn. 40): " start
	read -r -p "Bitiş eşiği (örn. 80): " stop

	[[ $start =~ ^[0-9]+$ && $stop =~ ^[0-9]+$ ]] || die "Sayı gir."
	(( start >= 0 && stop <= 100 && start < stop )) || die "0 <= başlangıç < bitiş <= 100 olmalı."

	mkdir -p /etc/tlp.d
	cat > "$TLP_CONF" <<EOF
# arch-kam: batarya şarj eşikleri
START_CHARGE_THRESH_BAT0=$start
STOP_CHARGE_THRESH_BAT0=$stop
EOF

	systemctl restart tlp.service
	log "Eşikler yazıldı ve TLP yeniden başlatıldı."
	warn "Bu eşikler her cihazda desteklenmez; tlp-stat -b ile doğrula."
}

while [[ $# -gt 0 ]]; do
	case $1 in
		-h | --help)
			usage
			exit 0
			;;
		*) die "Bilinmeyen argüman: $1" ;;
	esac
done

require_root
require_arch

cat <<EOF
${C_CYAN}=======================================${C_RESET}
${C_CYAN}      ARKUN: Battery Guardian          ${C_RESET}
${C_CYAN}   (Shamanic Power Management)         ${C_RESET}
${C_CYAN}=======================================${C_RESET}
1) ${C_GREEN}Grant Kut (TLP kur - enerji tasarrufu)${C_RESET}
2) ${C_RED}Recall Kut (TLP kaldır - tam güç)${C_RESET}
3) ${C_CYAN}Durum (tlp-stat)${C_RESET}
4) ${C_CYAN}Şarj eşikleri${C_RESET}
5) Çıkış
${C_CYAN}=======================================${C_RESET}
EOF

read -r -p "Seçim [1-5]: " choice
case $choice in
	1) install_tlp ;;
	2) remove_tlp ;;
	3) status_tlp ;;
	4) charge_thresholds ;;
	5) exit 0 ;;
	*) die "Geçersiz seçim." ;;
esac
