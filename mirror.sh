#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

MIRROR_FILE=/etc/pacman.d/mirrorlist
CACHYOS_DIR=/etc/pacman.d
BACKUP_DIR=/var/lib/arch-kam/mirrorlist

usage() {
	cat <<EOF
Kullanım: sudo $0 [--list] [--update] [--all] [--dry-run] [--latest N]

Swift Current: pacman mirror listesini hız sıralamasıyla yeniler.
reflector kurulu değilse kurar; /etc/pacman.d altındaki mirrorlist'leri birleştirir.

  --list       Mevcut mirrorlist durumunu göster (varsayılan)
  --update     reflector ile mirrorlist'i yenile
  --all        --update ile; onay sormadan uygula
  --dry-run    reflector komutunu göster, çalıştırma
  --latest N   En hızlı N mirror (varsayılan 10)
  -h, --help   Bu yardım
EOF
}

MODE='list'
ALL=0
DRY_RUN=0
LATEST=10

while [[ $# -gt 0 ]]; do
	case $1 in
		--list) MODE=list; shift ;;
		--update) MODE=update; shift ;;
		--all) ALL=1; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		--latest)
			[[ $# -ge 2 ]] || die "--latest bir sayı istiyor."
			LATEST=$2
			shift 2
			;;
		--latest=*) LATEST=${1#*=}; shift ;;
		-h | --help) usage; exit 0 ;;
		*) die "Bilinmeyen argüman: $1" ;;
	esac
done

require_arch
[[ $LATEST =~ ^[0-9]+$ ]] || die "--latest pozitif tam sayı olmalı."

section "Mirror durumu"
if have reflector; then
	ok "reflector kurulu: $(reflector --version 2>/dev/null | head -n1 || echo '?')"
else
	warn "reflector kurulu değil."
fi
if systemctl list-unit-files reflector.timer --no-legend 2>/dev/null | grep -q .; then
	state=$(systemctl is-enabled reflector.timer 2>/dev/null || true)
	[[ $state == enabled ]] && ok "reflector.timer etkin" || note "reflector.timer $state (otomatik yenileme kapalı)"
fi
echo

if [[ -f $MIRROR_FILE ]]; then
	servers=$(grep -cE '^Server[[:space:]]*=' "$MIRROR_FILE" 2>/dev/null || echo 0)
	note "pacman.d/mirrorlist: $servers etkin mirror"
	grep -vE '^\s*#|^\s*$' "$MIRROR_FILE" | head -5 | sed 's/^/    /'
else
	bad "mirrorlist yok: $MIRROR_FILE"
fi
ISSUES=0

cachyos_lists=("$CACHYOS_DIR"/cachyos*.mirrorlist)
for f in "${cachyos_lists[@]}"; do
	[[ -f $f ]] && note "$(basename "$f"): $(grep -cE '^Server[[:space:]]*=' "$f" 2>/dev/null || echo 0) mirror"
done

if [[ $MODE != update ]]; then
	echo
	note "Yenilemek için: sudo $0 --update"
	exit 0
fi

require_root

if ! have reflector; then
	warn "reflector kurulu değil; kurulması gerekiyor: pacman -S reflector"
	if ask_yes "reflector kurulsun mu?"; then
		pacman -S --needed --noconfirm reflector
	else
		die "reflector olmadan devam edilemez."
	fi
fi

CMD=(reflector --latest "$LATEST" --sort rate --save "$MIRROR_FILE")

section "Yenileme"
if ((DRY_RUN)); then
	printf '  [dry-run] %s\n' "${CMD[*]}"
	note "Dry-run; hiçbir şey değiştirilmedi."
	exit 0
fi

if ! ((ALL)) && ! ask_yes "mirrorlist yenilensin mi?"; then
	note "Vazgeçildi."
	exit 0
fi

mkdir -p "$BACKUP_DIR"
for f in "$MIRROR_FILE" "${cachyos_lists[@]}"; do
	[[ -f $f ]] || continue
	ts=$(date +%Y%m%d-%H%M%S)
	cp -a "$f" "$BACKUP_DIR/$(basename "$f").$ts"
done
log "Yedekler: $BACKUP_DIR"

if ! "${CMD[@]}"; then
	warn "reflector başarısız; yedeğe dönmek için: cp $BACKUP_DIR/$(basename "$MIRROR_FILE").* $MIRROR_FILE"
	exit 1
fi

ok "mirrorlist yenilendi."

if have checkupdates; then
	if ask_yes "Şimdi paket veritabanı tazelenip güncelleme listesi çıkarılsın mı?"; then
		pacman -Sy --noconfirm
		updates=$(checkupdates 2>/dev/null | wc -l || echo 0)
		if ((updates > 0)); then
			note "$updates güncelleme var:"
			checkupdates 2>/dev/null | sed 's/^/    /'
		else
			ok "Sistem güncel."
		fi
	fi
fi
