#!/usr/bin/env bash

# Ortak ritüel altyapısı: renk, loglama, root/arch denetimi, yedekleme,
# dosya işlemlerinde atomik yazma, daemon özetleri.

if [[ -t 1 ]]; then
	C_RESET=$'\033[0m'
	C_GREEN=$'\033[0;32m'
	C_RED=$'\033[0;31m'
	C_YELLOW=$'\033[1;33m'
	# shellcheck disable=SC2034
	C_CYAN=$'\033[0;36m'
else
	C_RESET=''
	C_GREEN=''
	C_RED=''
	C_YELLOW=''
	# shellcheck disable=SC2034
	C_CYAN=''
fi

log() { printf '%b[INFO]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
error() { printf '%b[ERROR]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die() {
	error "$*"
	exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

# Kullanıcı istemini göstermeden, yalnızca arayüz bayrağı var mı diye bak.
auto_mode() {
	NO_CONFIRM=1 YES_ALL=1 DRY_RUN=1 ASSUME_YES=1 NON_INTERACTIVE=1
	for arg in "$@"; do
		case $arg in
			--dry-run | --yes | -y | --force | -f | --non-interactive | --no-confirm)
				printf '%s\n' "$arg"
				return 0
				;;
		esac
	done
	return 1
}

require_root() {
	if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
		die "Bu ritüel root şaman gerektiriyor. Şunu dene: sudo $0"
	fi
}

require_arch() {
	if [[ ! -f /etc/arch-release ]] && ! have pacman; then
		die "Bu ritüel Arch tabanlı bir sistem istiyor (/etc/arch-release veya pacman bulunamadı)."
	fi
}

confirm() {
	local prompt=${1:-"Devam edeyim mi?"} answer
	printf '%b%s [y/N]%b ' "$C_YELLOW" "$prompt" "$C_RESET"
	read -r answer
	[[ $answer =~ ^[Yy]$ ]]
}

# Evet bayrağı iletilmediyse onay iste; --yes/--dry-run vb. tek başına otomatik onay verir.
ask_yes() {
	local prompt=${1:-"Devam edeyim mi?"} auto
	if auto=$(auto_mode "$@"); then
		[[ -n $auto ]] && printf '  [auto-yes] %s (%s)\n' "$prompt" "$auto"
		return 0
	fi
	confirm "$prompt"
}

section() { printf '\n%b== %s ==%b\n' "$C_CYAN" "$*" "$C_RESET"; }
note() { printf '  - %s\n' "$*"; }
ok() { printf '  %b[ok]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '  - %s\n' "$*"; }
bad() {
	printf '  %b[!!]%b %s\n' "$C_RED" "$C_RESET" "$*"
	((ISSUES += 1))
}

detect_bootloader() {
	if [[ -f /boot/loader/loader.conf ]]; then
		echo systemd-boot
	elif [[ -f /boot/grub/grub.cfg ]]; then
		echo grub
	elif have bootctl; then
		echo systemd-boot
	elif have grub-mkconfig; then
		echo grub
	else
		echo unknown
	fi
}

root_fs() {
	findmnt -no FSTYPE / 2>/dev/null || echo unknown
}

backup_once() {
	local file=$1 suffix=${2:-bak}
	local backup="$file.$suffix"

	[[ -f $file ]] || return 0
	if [[ ! -f $backup ]]; then
		cp -a "$file" "$backup" || die "Yedek oluşturulamadı: $backup"
		log "Yedek: $backup"
	fi
}

filter_resume_words() {
	local value=$1
	local -a words
	local out='' word

	read -r -a words <<< "$value"
	for word in "${words[@]}"; do
		case $word in
			resume=* | resume_offset=*) continue ;;
			*) out+="${out:+ }$word" ;;
		esac
	done
	printf '%s' "$out"
}

# Tek farklılık (added/removed) ile mevcut değerden yeni değeri üret.
diff_text() {
	local old=$1 new=$2
	printf '%s' "$new" | tr ' ' '\n' | sort > /tmp/.kam_new.$$
	printf '%s' "$old" | tr ' ' '\n' | sort > /tmp/.kam_old.$$
	local added removed
	added=$(comm -13 /tmp/.kam_old.$$ /tmp/.kam_new.$$ | tr '\n' ' ')
	removed=$(comm -23 /tmp/.kam_old.$$ /tmp/.kam_new.$$ | tr '\n' ' ')
	rm -f /tmp/.kam_new.$$ /tmp/.kam_old.$$
	[[ -n $added ]] && printf '  + %s\n' "$added"
	[[ -n $removed ]] && printf '  - %s\n' "$removed"
}

# Satırdaki kabuk tırnaklarını koruyarak önceki resume parametrelerini temizle.
filter_line_resume() {
	local line=$1
	printf '%s' "$line" | sed -E 's/\b(resume|resume_offset)=[^ ]*//g; s/[[:space:]]+/ /g; s/^ //; s/ $//'
}

# Değerden kabuk tırnaklarını çıkar (tek veya çift olabilir).
strip_quotes() {
	local value=$1
	printf '%s' "$value" | sed -E "s/^['\"]//; s/['\"]$//"
}

# Atomik dosya yazma: ara dosya aynı dizinde, mv ile üzerine al, hata durumunda temizlik.
# Kullanım: atomic_write <hedef_dosya> <<'EOF' ... veya atomic_write <hedef> "içerik"
atomic_write() {
	local dest=$1 content=$2 tmp rc=0

	[[ -e $dest && ! -f $dest ]] && die "Hedef regular file değil: $dest"
	tmp=$(mktemp "${dest}.arch-kam.XXXXXX") || die "Geçici dosya oluşturulamadı: $dest"
	trap 'rm -f "$tmp"' RETURN
	if [[ $# -eq 2 ]]; then
		printf '%s\n' "$content" > "$tmp" || rc=1
	else
		cat > "$tmp" || rc=1
	fi
	((rc)) && { rm -f "$tmp"; trap - RETURN; return 1; }
	if [[ -f $dest ]]; then
		chmod --reference="$dest" "$tmp" 2>/dev/null || true
		chown --reference="$dest" "$tmp" 2>/dev/null || true
	fi
	mv -f "$tmp" "$dest" || { rm -f "$tmp"; trap - RETURN; return 1; }
	trap - RETURN
	return 0
}

# Yorumlanmış bir yapılandırma satırı yaz: var olanı değiştir, yoksa dosya sonuna ekle.
# Kullanım: upsert_line <dosya> <desen> <yeni_satır>
upsert_line() {
	local file=$1 pattern=$2 newline=$3 tmp rc=0

	[[ -f $file ]] || die "Dosya yok: $file"
	if grep -qE "$pattern" "$file"; then
		tmp=$(mktemp "${file}.arch-kam.XXXXXX") || die "Geçici dosya oluşturulamadı: $file"
		trap 'rm -f "$tmp"' RETURN
		awk -v newline="$newline" -v pattern="$pattern" '
			$0 ~ pattern && !done { print newline; done=1; next }
			{ print }
		' "$file" > "$tmp" || rc=1
		((rc)) && { rm -f "$tmp"; trap - RETURN; return 1; }
		chmod --reference="$file" "$tmp" 2>/dev/null || true
		mv -f "$tmp" "$file" || { rm -f "$tmp"; trap - RETURN; return 1; }
		trap - RETURN
		return 0
	fi
	if ! printf '%s\n' "$newline" >> "$file"; then
		die "Yazılamadı: $file"
	fi
	return 0
}

# Daemon durumunu tek bakışta özetle: etkin, maskeli, başarısız, ayrıcalıklı erişim.
daemon_summary() {
	local failed masked privileged

	if have systemctl; then
		failed=$(systemctl --failed --no-legend --no-pager 2>/dev/null || true)
		if [[ -n $failed ]]; then
			warn "Başarısız systemd unit:"
			printf '%s\n' "$failed" | sed 's/^/    /'
			((ISSUES += 1))
		else
			ok "Başarısız systemd unit yok"
		fi

		masked=$(systemctl list-unit-files --state=masked --no-legend --no-pager 2>/dev/null || true)
		if [[ -n $masked ]]; then
			warn "Maskeli unit (okunamaz, başlatılamaz):"
			printf '%s\n' "$masked" | sed 's/^/    /'
		else
			ok "Maskeli unit yok"
		fi
	fi

	if have systemctl; then
		privileged=$(systemctl list-units --type=service --state=running --no-legend --no-pager 2>/dev/null |
			awk '{print $1}' | sed 's/\.service$//' | sort -u || true)
		if [[ -n $privileged ]]; then
			note "Çalışan servis sayısı: $(printf '%s\n' "$privileged" | grep -c .)"
		fi
	fi
}

# Pacman tarzı foreign (elle kurulmuş) paketleri ve yetim bağımlılıkları raporla.
package_summary() {
	if ! have pacman; then
		note "pacman bulunamadı"
		return
	fi

	local orphans foreign
	mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)
	mapfile -t foreign < <(pacman -Qmq 2>/dev/null || true)

	if ((${#orphans[@]} > 0)); then
		note "Yetim paketler (${#orphans[@]}):"
		printf '    %s\n' "${orphans[@]}"
	else
		ok "Yetim paket yok"
	fi

	if ((${#foreign[@]} > 0)); then
		note "Elle kurulan (AUR/foreign) paketler (${#foreign[@]}):"
		printf '    %s\n' "${foreign[@]}"
	else
		ok "Foreign paket yok"
	fi
}

# Konsol taşmasını önlemek için metni verilen genişliğe kırpıp girintile.
wrap() {
	local text=$1 width=${2:-76}
	printf '%s\n' "$text" | fold -s -w "$width" | sed 's/^/    /'
}
