#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

PACNEW_SUFFIX='pacnew'
PACSAVE_SUFFIX='pacsave'
SCAN_DIRS=(/etc)
PAIRS=()

usage() {
	cat <<EOF
Kullanım: $0 [--list] [--diff] [--resolve <eski-dosya>] [--all] [--quiet]

Safeguard ritüeli: pacman'ın bıraktığı .pacnew / .pacsave çiftlerini bulur,
farkı gösterir, onayla yeni dosyayı eski dosyanın üzerine yazar. Kendi başına değiştirmez.

  --list      Yalnızca çiftleri listele (varsayılan)
  --diff      Her çiftin farkını göster
  --resolve F F ile aynı addaki .pacnew'i esas al, yedekle, F üzerine yaz
  --all       --resolve ile kullanılır; onay sormadan tümünü uygula
  --quiet     Yalnızca özet satırı bas
  -h, --help  Bu yardım
EOF
}

MODE='list'
TARGET=''
QUIET=0
ALL=0

while [[ $# -gt 0 ]]; do
	case $1 in
		--list) MODE=list; shift ;;
		--diff) MODE=diff; shift ;;
		--resolve)
			[[ $# -ge 2 ]] || die "--resolve bir dosya adı istiyor."
			MODE=resolve
			TARGET=$2
			shift 2
			;;
		--all) ALL=1; shift ;;
		--quiet) QUIET=1; shift ;;
		-h | --help) usage; exit 0 ;;
		*) die "Bilinmeyen argüman: $1" ;;
	esac
done

require_arch

# .pacnew / .pacsave çiftlerini topla: herbiri "eski<TAB>yeni"
collect_pairs() {
	local dir file base
	for dir in "${SCAN_DIRS[@]}"; do
		[[ -d $dir ]] || continue
		while IFS= read -r -d '' file; do
			base=${file%.${PACNEW_SUFFIX}}
			[[ -f $base ]] && printf '%s\t%s\n' "$base" "$file"
		done < <(find "$dir" -type f -name "*.${PACNEW_SUFFIX}" -print0 2>/dev/null | sort -z)
		while IFS= read -r -d '' file; do
			base=${file%.${PACSAVE_SUFFIX}}
			[[ -f $base ]] && printf '%s\t%s\n' "$base" "$file"
		done < <(find "$dir" -type f -name "*.${PACSAVE_SUFFIX}" -print0 2>/dev/null | sort -z)
	done
}

# Hangi taraf daha yeni? Pacman eskiyi korur; kullanıcı yeni üzerine yazarsa eski kaybolur.
age_label() {
	local base=$1 new=$2
	if [[ $base -nt $new ]]; then
		echo "eski-daha-yeni"
	elif [[ $new -nt $base ]]; then
		echo "yeni-daha-yeni"
	else
		echo "eşit"
	fi
}

mapfile -t PAIRS < <(collect_pairs)

if ((QUIET)); then
	printf 'Bulunan .pacnew/.pacsave çifti: %s\n' "${#PAIRS[@]}"
	exit 0
fi

section "Safeguard: pacnew çiftleri"

if ((${#PAIRS[@]} == 0)); then
	ok "Çift yok; /etc temiz görünüyor."
	exit 0
fi

warn "${#PAIRS[@]} çift bulundu."
echo

for pair in "${PAIRS[@]}"; do
	base=${pair%%$'\t'*}
	new=${pair#*$'\t'}
	printf '  %s\n    yeni : %s\n    durum: %s\n' "$base" "$new" "$(age_label "$base" "$new")"
	if [[ $MODE == diff ]]; then
		echo "    --- fark ---"
		if have diff; then
			diff -u -- "$base" "$new" | sed 's/^/      /' || true
		else
			note "diff bulunamadı; sadece listeleyebilirsin."
		fi
		echo
	fi
done

if [[ $MODE == resolve ]]; then
	if [[ -z $TARGET ]]; then
		die "--resolve bir 'eski' dosya adı istiyor (yukarıda listelenen)."
	fi

	RESOLVE_SRC=''
	RESOLVE_NEW=''
	for pair in "${PAIRS[@]}"; do
		base=${pair%%$'\t'*}
		new=${pair#*$'\t'}
		if [[ $base == "$TARGET" ]]; then
			RESOLVE_SRC=$base
			RESOLVE_NEW=$new
			break
		fi
	done

	if [[ -z $RESOLVE_SRC ]]; then
		die "Çift bulunamadı: $TARGET"
	fi

	require_root

	section "Uygulama"
	echo "  Esas alınan : $RESOLVE_NEW"
	echo "  Yazılacak   : $RESOLVE_SRC"
	echo
	backup_once "$RESOLVE_SRC" arch-kam-pacnew.bak

	if ((ALL)) || ask_yes "$RESOLVE_NEW -> $RESOLVE_SRC üzerine yazılsın mı?"; then
		atomic_write "$RESOLVE_SRC" < "$RESOLVE_NEW"
		log "Uygulandı: $RESOLVE_SRC"
		rm -f -- "$RESOLVE_NEW"
		log "Çift temizlendi: $RESOLVE_NEW silindi"
	else
		note "Vazgeçildi; hiçbir şey değişmedi."
	fi
	exit 0
fi

echo
note "Fark için: $0 --diff"
note "Uygulamak için: sudo $0 --resolve <eski-dosya>"
