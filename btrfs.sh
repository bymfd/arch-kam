#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
	cat <<EOF
Kullanım: $0 [--list] [--snapshots] [--space] [--scrub] [--balance]

Breath of the Earth: btrfs dosya sistemi durumunu denetler.
Alan kullanımı, alt hacimler, snapshot'lar, scrub/balance önerisi.

  --list       Genel durum (varsayılan)
  --snapshots  Snapshot'ları listele (snapper varsa)
  --space      Dosya sistemi ve alan kullanımı
  --scrub      btrfs scrub başlat (yavaş; --dry-run ile önizleme)
  --balance    btrfs balance önerisi (dry-run önizleme)
  --dry-run    --scrub/--balance için yalnızca ne yapılacağını göster
  -h, --help   Bu yardım
EOF
}

MODE='list'
DRY_RUN=0

while [[ $# -gt 0 ]]; do
	case $1 in
		--list) MODE=list; shift ;;
		--snapshots) MODE=snapshots; shift ;;
		--space) MODE=space; shift ;;
		--scrub) MODE=scrub; shift ;;
		--balance) MODE=balance; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		-h | --help) usage; exit 0 ;;
		*) die "Bilinmeyen argüman: $1" ;;
	esac
done

ISSUES=0
FS=$(root_fs)

if [[ $FS != btrfs ]]; then
	note "Kök dosya sistemi btrfs değil ($FS); bu ritüel atlanıyor."
	exit 0
fi

have btrfs || die "btrfs komutu yok; pacman -S btrfs-progs"

case $MODE in
	list)
		section "Btrfs durumu"
		btrfs filesystem show / 2>/dev/null | sed 's/^/  /' || warn "btrfs show başarısız"
		echo
		btrfs filesystem df / 2>/dev/null | sed 's/^/  /' || true
		echo
		note "Alt hacimler:"
		btrfs subvolume list / 2>/dev/null | sed 's/^/    /' || warn "subvolume listesi okunamadı (root olabilir)."
		echo
		note "Quota:"
		btrfs quota status / 2>&1 | sed 's/^/    /' || note "quota etkin değil"
		;;
	snapshots)
		section "Snapshot'lar"
		if have snapper && snapper list-configs 2>/dev/null | grep -q .; then
			snapper list 2>/dev/null | sed 's/^/  /' || warn "snapper list başarısız"
		else
			note "snapper yapılandırması yok; btrfs ile doğrudan bakılabilir."
			btrfs subvolume list -s / 2>/dev/null | sed 's/^/  /' || warn "snapshot listesi okunamadı."
		fi
		;;
	space)
		section "Alan kullanımı"
		df -h / | sed 's/^/  /'
		echo
		note "Fiziksel tahsis (btrfs):"
		btrfs filesystem usage / 2>/dev/null | sed 's/^/  /' || warn "usage okunamadı."
		;;
	scrub)
		section "Scrub"
		if ((DRY_RUN)); then
			note "btrfs scrub başlatılacak (tüm kök):"
			note "  btrfs scrub start -Bd /"
			exit 0
		fi
		require_root
		log "Scrub başlatılıyor (arka planda devam edebilir)..."
		btrfs scrub start -Bd / && log "Scrub tamamlandı." || warn "Scrub tamamlanamadı."
		btrfs scrub status / 2>/dev/null | sed 's/^/  /' || true
		;;
	balance)
		section "Balance"
		if ((DRY_RUN)); then
			note "Dengesizlik önerisi:"
			btrfs filesystem usage / 2>/dev/null | grep -E 'Data|Unallocated' | sed 's/^/  /' || true
			note "Düşük kullanımlı blok gruplar için: btrfs balance start -dusage=50 /"
			exit 0
		fi
		require_root
		btrfs filesystem usage / 2>/dev/null | sed 's/^/  /' || true
		if ask_yes "Balance başlatılsın mı? (uzun sürebilir)"; then
			btrfs balance start -dusage=50 / && log "Balance tamamlandı." || warn "Balance tamamlanamadı."
		fi
		;;
esac

log "Btrfs denetimi tamam."
