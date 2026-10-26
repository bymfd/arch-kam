#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

ZRAM_CONF_DIR=/etc/systemd/zram-generator.conf.d
ZRAM_CONF=/etc/systemd/zram-generator.conf
SWAPFILE=/swapfile

usage() {
	cat <<EOF
Kullanım: sudo $0 [--list] [--fix] [--dry-run] [--prio N]

Breath of Compression: zram ve swapfile'in birlikte çalıştığı sistemlerde
öncelik sırasını denetler. Hibernate için swapfile'ın öncelikli olması gerekir.

  --list     Mevcut swap ve zram durumunu göster (varsayılan, root gerektirmez)
  --fix      Swapfile önceliğini yükselt (swapon -p), zram'ı düşür
  --prio N   Swapfile için hedef öncelik (varsayılan 100)
  --dry-run  Ne değişeceğini göster
  -h, --help Bu yardım
EOF
}

MODE='list'
DRY_RUN=0
PRIO=100

while [[ $# -gt 0 ]]; do
	case $1 in
		--list) MODE=list; shift ;;
		--fix) MODE=fix; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		--prio)
			[[ $# -ge 2 ]] || die "--prio bir sayı istiyor."
			PRIO=$2
			shift 2
			;;
		--prio=*) PRIO=${1#*=}; shift ;;
		-h | --help) usage; exit 0 ;;
		*) die "Bilinmeyen argüman: $1" ;;
	esac
done

[[ $PRIO =~ ^[0-9]+$ ]] || die "--prio pozitif tam sayı olmalı."

ISSUES=0

section "Swap kaynakları"
if swapon --show --noheadings 2>/dev/null | grep -q .; then
	swapon --show | sed 's/^/  /'
else
	note "Aktif swap yok."
fi

echo
section "Durum"
mapfile -t ZRAM_PIDS < <(swapon --show=NAME --noheadings 2>/dev/null | grep -E '^/dev/zram' || true)
mapfile -t SWAPFILE_PIDS < <(swapon --show=NAME --noheadings 2>/dev/null | grep -F "$SWAPFILE" || true)

if ((${#ZRAM_PIDS[@]} == 0)); then
	note "zram swap yok (yalnızca swapfile kullanılıyor olabilir)."
elif ((${#SWAPFILE_PIDS[@]} == 0)); then
	bad "Swapfile bağlı değil; hibernate swapfile'i kullanamaz."
else
	# Öncelikleri karşılaştır
	zram_prio=$(swapon --show=NAME,PRIO --noheadings 2>/dev/null | grep -E '^/dev/zram' | awk '{print $2}' | sort -n | tail -n1 || true)
	file_prio=$(swapon --show=NAME,PRIO --noheadings 2>/dev/null | grep -F "$SWAPFILE" | awk '{print $2}' | tail -n1 || true)
	note "zram öncelik : ${zram_prio:-?}"
	note "swapfile prio: ${file_prio:-?}"

	if [[ -n $zram_prio && -n $file_prio ]] && ((zram_prio > file_prio)); then
		warn "zram, swapfile'dan YÜKSEK öncelikli. Hibernate swapfile'e yazamaz;"
		warn "zram sıkıştırılmış sayfalar swapfile'i doldurmaz ama öncelik ters."
		bad "Swap önceliği ters (zram=$zram_prio > swapfile=$file_prio)"
	else
		ok "Swap önceliği makul (swapfile=$file_prio, zram=$zram_prio)"
	fi
fi

echo
section "zram yapılandırması"
if [[ -f $ZRAM_CONF ]]; then
	note "$ZRAM_CONF:"
	sed 's/^/    /' "$ZRAM_CONF"
elif [[ -d $ZRAM_CONF_DIR ]] && compgen -G "$ZRAM_CONF_DIR/*.conf" >/dev/null; then
	note "zram-generator drop-in'leri:"
	for f in "$ZRAM_CONF_DIR"/*.conf; do
		sed "s/^/    /" "$f"
	done
else
	note "Yapılandırma dosyası yok; systemd varsayılanı kullanılıyor."
	note "  /usr/lib/systemd/zram-generator.conf (varsayılan: zram-size = ram)"
fi

echo
if have zramctl; then
	note "zram aygıtları:"
	zramctl --output-all 2>/dev/null | sed 's/^/    /' || true
fi

# Swapfile boyutu vs RAM
RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')
SWAP_SIZE_MB=$(du -m "$SWAPFILE" 2>/dev/null | cut -f1 || echo 0)
note "RAM: ${RAM_MB}MB | swapfile: ${SWAP_SIZE_MB}MB"
if ((SWAP_SIZE_MB > 0 && SWAP_SIZE_MB < RAM_MB)); then
	warn "Swapfile RAM'den küçük; hibernate başarısız olabilir."
fi

if [[ $MODE != fix ]]; then
	echo
	note "Öncelik düzeltmek için: sudo $0 --fix"
	exit 0
fi

require_root

if [[ ! -e $SWAPFILE ]]; then
	die "Swapfile yok: $SWAPFILE"
fi

section "Düzeltme"
if ! swapon --show=NAME --noheadings 2>/dev/null | grep -qF "$SWAPFILE"; then
	# Swapfile bağlı değilse önce bağla
	if ((DRY_RUN)); then
		note "[dry-run] swapon -p $PRIO $SWAPFILE"
	else
		if swapon -p "$PRIO" "$SWAPFILE"; then
			log "Swapfile bağlandı (prio=$PRIO)"
		else
			die "Swapfile bağlanamadı."
		fi
	fi
else
	# Bağlıysa önceliği değiştir
	current_prio=$(swapon --show=NAME,PRIO --noheadings 2>/dev/null | grep -F "$SWAPFILE" | awk '{print $2}' | tail -n1 || true)
	if [[ $current_prio == "$PRIO" ]]; then
		ok "Swapfile önceliği zaten $PRIO"
		exit 0
	fi
	if ((DRY_RUN)); then
		note "[dry-run] swapoff $SWAPFILE && swapon -p $PRIO $SWAPFILE"
		exit 0
	fi
	if swapoff "$SWAPFILE" 2>/dev/null || true; then
		if swapon -p "$PRIO" "$SWAPFILE"; then
			log "Swapfile önceliği güncellendi: $PRIO"
		else
			# Bağlanamazsa eski haline döndür
			warn "Yeni öncelikle bağlanamadı; eski haline dönülüyor..."
			swapon "$SWAPFILE" && log "Eski durum geri yüklendi." || die "Kritik: swapfile bağlanamadı!"
		fi
	fi
fi

log "Swap önceliği denetimi tamam."
