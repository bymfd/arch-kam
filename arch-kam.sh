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
${C_CYAN}=======================================${C_RESET}
${C_CYAN}          ARCH-KAM RİTÜEL MENÜSÜ       ${C_RESET}
${C_CYAN}=======================================${C_RESET}
1) Doctor     — sistem teşhisi
2) Hibernate  — uyku / swap
3) Arkun      — batarya / TLP
4) Tın        — GRUB arkaplanı
5) Temizlik   — paket / journal / yetim
6) Çıkış
${C_CYAN}=======================================${C_RESET}
EOF

	local choice
	read -r -p "Seçim [1-6]: " choice
	case $choice in
		1) run_ritual doctor.sh ;;
		2) run_ritual hibernate-enabler.sh ;;
		3) run_ritual battery.sh ;;
		4) run_ritual bootloader-bg.sh ;;
		5) run_ritual clean.sh ;;
		6) exit 0 ;;
		*) die "Geçersiz seçim." ;;
	esac
}

case ${1:-} in
	doctor) shift; run_ritual doctor.sh "$@" ;;
	hibernate) shift; run_ritual hibernate-enabler.sh "$@" ;;
	battery) shift; run_ritual battery.sh "$@" ;;
	boot) shift; run_ritual bootloader-bg.sh "$@" ;;
	clean) shift; run_ritual clean.sh "$@" ;;
	-h | --help | help) usage ;;
	'') menu ;;
	*) die "Bilinmeyen ritüel: $1" ;;
esac
