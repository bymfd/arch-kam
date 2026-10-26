#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DRY_RUN=0
YES=0

usage() {
	cat <<EOF
Kullanım: sudo $0 [--dry-run] [--yes]

  --dry-run   Hiçbir şeyi silme; yalnızca ne yapılacağını göster
  --yes       Onay sormadan çalıştır

Temizlik: paccache, journal (14 gün), yetim paketler, systemd tmpfiles.
EOF
}

while [[ $# -gt 0 ]]; do
	case $1 in
		--dry-run)
			DRY_RUN=1
			shift
			;;
		--yes | -y)
			YES=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*) die "Bilinmeyen argüman: $1" ;;
	esac
done

require_arch
if ((!DRY_RUN)); then
	require_root
fi

run() {
	if ((DRY_RUN)); then
		printf '  [dry-run] %s\n' "$*"
	else
		"$@"
	fi
}

section() { printf '\n%b== %s ==%b\n' "$C_CYAN" "$*" "$C_RESET"; }

section "Özet"
if [[ -d /var/cache/pacman/pkg ]]; then
	note_size=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1 || true)
	printf '  Paket önbelleği: %s\n' "${note_size:-?}"
fi
printf '  Journal: '
journalctl --disk-usage 2>/dev/null || echo 'okunamadı'

mapfile -t ORPHANS < <(pacman -Qtdq 2>/dev/null || true)
if ((${#ORPHANS[@]} > 0)); then
	printf '  Yetim paketler (%s):\n' "${#ORPHANS[@]}"
	printf '    %s\n' "${ORPHANS[@]}"
else
	printf '  Yetim paket: yok\n'
fi

if ((!YES && !DRY_RUN)); then
	confirm "Temizlik çalışsın mı?" || exit 0
fi

section "Paket önbelleği"
if have paccache; then
	run paccache -r
	run paccache -ruk0
else
	warn "paccache yok; paket önbelleğine dokunulmadı. Kurmak için: pacman -S pacman-contrib"
fi

section "Journal"
run journalctl --vacuum-time=14d

section "Yetim paketler"
if ((${#ORPHANS[@]} > 0)); then
	run pacman -Rns --noconfirm "${ORPHANS[@]}"
else
	log "Kaldırılacak yetim paket yok."
fi

section "Geçici dosyalar"
run systemd-tmpfiles --clean

printf '\n'
log "Temizlik ritüeli tamam."
