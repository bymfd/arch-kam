#!/usr/bin/env bash
# kam.sh — arch-kam motoru. Tek generic yürütücü: rituals/<klasör>/*.yaml'ı okur,
# her check'in kind'ına göre koşulu değerlendirir, pass/fail seviyesiyle basar.
#
# Hiçbir ritüel mantığı bu dosyada TANIMLANMAZ. Yalnızca kind'ların
# (koşul tiplerinin) nasıl değerlendirildiği burada olur; ne kontrol edileceği,
# ne konuşulacağı, hangi seviyede olacağı tamamen YAML'dadır.
#
# Ritüel klasörleri (rituals/ altında):
#   common/   Tüm dağıtımlarda çalışır (salt okunur teşhis, dosya kontrolleri)
#   arch/     Arch tabanlı (pacman, mkinitcpio, GRUB)
#   deb/      Debian/Ubuntu tabanlı (apt, dpkg)
#   fedora/   Fedora/RHEL tabanlı (dnf, rpm)
#   alpine/   Alpine tabanlı (apk)
#   gentoo/   Gentoo tabanlı (emerge, portage)
#   apps/     Dağıtımdan bağımsız uygulama ritüelleri
#   fix/      Dağıtımdan bağımsız düzeltme ritüelleri
#
# Sistem otomatik tanınır (os-release + paket yöneticisi) ve menüde yalnızca
# uygun ritüeller gösterilir; --all ile hepsi listelenir. Kullanıcı isterse
# her zaman istediği ritüeli doğrudan çalıştırabilir.
#
# Kullanım:
#   kam.sh list [--all]      Ritüelleri listele
#   kam.sh show <ritüel>     Ritüel tanımını göster
#   kam.sh run <ritüel> [a]  Ritüeli çalıştır
#   kam.sh menu              Menü (sisteme göre filtrelenmiş)
#   kam.sh help

set -uo pipefail

KAM_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=kam_yaml.sh
source "$KAM_ROOT/kam_yaml.sh"

RITUAL_DIR="$KAM_ROOT/rituals"
ISSUES=0
YAML_FILE=''
KAM_ALL=0

if [[ -t 1 ]]; then
	C_RESET=$'\033[0m'
	C_GREEN=$'\033[0;32m'
	C_RED=$'\033[0;31m'
	C_YELLOW=$'\033[1;33m'
	C_CYAN=$'\033[0;36m'
	C_DIM=$'\033[2m'
else
	C_RESET=''
	C_GREEN=''
	C_RED=''
	C_YELLOW=''
	C_CYAN=''
	C_DIM=''
fi

log() { printf '%b[INFO]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
error() { printf '%b[ERROR]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die() { error "$*"; exit 1; }
section() { printf '\n%b== %s ==%b\n' "$C_CYAN" "$*" "$C_RESET"; }
note() { printf '  - %s\n' "$*"; }
ok() { printf '  %b[ok]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
bad() {
	printf '  %b[!!]%b %s\n' "$C_RED" "$C_RESET" "$*"
	((ISSUES += 1))
}
have() { command -v "$1" >/dev/null 2>&1; }

# --- sistem tanıma ----------------------------------------------------------
# ID/ID_LIKE (os-release) ve paket yöneticisi ile dağıtım ailesi bulunur.
# Ortak değerler: arch, deb, fedora, alpine, gentoo, any

KAM_DISTRO='any'

_detect_distro() {
	local id id_like pm=''
	local -a like_parts=()

	if [[ -r /etc/os-release ]]; then
		id=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2; exit}' /etc/os-release)
		id_like=$(awk -F= '/^ID_LIKE=/{gsub(/"/, "", $2); print $2; exit}' /etc/os-release)
	fi

	# paket yöneticisi (id LIKE ile uyumsuz olabilir; ona öncelik ver)
	if have pacman; then
		pm=arch
	elif have apt-get || have dpkg; then
		pm=deb
	elif have dnf || have rpm; then
		pm=fedora
	elif have apk; then
		pm=alpine
	elif have emerge || have portage; then
		pm=gentoo
	fi

	# id veya ID_LIKE içinde arama: arch, debian/ubuntu, fedora/rhel/centos, alpine, gentoo
	_match_family() {
		local hay="$1"
		case $hay in
			*arch*) echo arch ;;
			*debian* | *ubuntu* | *linuxmint* | *pop*) echo deb ;;
			*fedora* | *rhel* | *centos* | *rocky* | *almalinux*) echo fedora ;;
			*alpine*) echo alpine ;;
			*gentoo*) echo gentoo ;;
			*) return 1 ;;
		esac
	}

	if [[ -n $pm ]]; then
		KAM_DISTRO=$pm
	else
		local hit
		hit=$(_match_family "$id") || true
		if [[ -z $hit ]]; then
			read -r -a like_parts <<< "$id_like"
			local p
			for p in "${like_parts[@]}"; do
				hit=$(_match_family "$p") && break
			done
		fi
		KAM_DISTRO=${hit:-any}
	fi
}

# Ritüelin distro alanı ile eşleşiyor mu?
_ritual_matches_distro() {
	local name=$1
	kam_yaml_parse "$RITUAL_DIR/$name" >/dev/null 2>&1 || return 0
	local distro_field
	distro_field=$(kam_yaml_get "$RITUAL_DIR/$name" distro 2>/dev/null)
	# distro alanı yoksa her sistemde çalışır
	[[ -z $distro_field ]] && return 0

	# Liste biçiminde mi (path[0]=...) yoksa tek satır mı?
	local -a list=()
	local n i
	n=$(kam_yaml_count "$RITUAL_DIR/$name" distro 2>/dev/null || echo 0)
	if [[ -n $n && $n -gt 0 ]]; then
		for ((i = 0; i < n; i++)); do
			list+=("$(kam_yaml_get "$RITUAL_DIR/$name" "distro[$i]" 2>/dev/null)")
		done
	else
		list+=("$distro_field")
	fi
	local d
	for d in "${list[@]}"; do
		[[ $d == "$KAM_DISTRO" || $d == any ]] && return 0
	done
	return 1
}

_detect_distro

# --- mesaj şablonlarını çöz: {value}, {count}, {issues}, {b} vb. -----------
_resolve_msg() {
	local msg=$1
	msg=${msg//\{value\}/${KAM_VALUE:-}}
	msg=${msg//\{count\}/${KAM_COUNT:-0}}
	msg=${msg//\{issues\}/$ISSUES}
	msg=${msg//\{b\}/${KAM_B:-}}
	msg=${msg//\{a\}/${KAM_A:-}}
	printf '%s' "$msg"
}

_emit() {
	local level=$1 msg=$2
	msg=$(_resolve_msg "$msg")
	case $level in
		note) note "$msg" ;;
		ok) ok "$msg" ;;
		warn) warn "$msg" ;;
		bad) bad "$msg" ;;
		*) note "$msg" ;;
	esac
}

# --- kind değerlendiriciler -------------------------------------------------
# Her kind bir fonksiyon: kam_kind_<kind> — sonuç 0 (pass) veya 1 (fail).
# KAM_VALUE / KAM_COUNT / KAM_A / KAM_B ile sonuç taşınır.

kam_kind_literal() {
	local v
	v=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.value")
	# $(...) içindeki kabuk çağrılarını çalıştır (örn. $(uname -r))
	KAM_VALUE=$(eval "printf '%s' \"$v\"" 2>/dev/null || true)
	[[ -n $KAM_VALUE ]]
}

kam_kind_output() {
	local cmd
	cmd=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.command")
	[[ -z $cmd ]] && { KAM_VALUE=''; return 1; }
	# YAML'dan gelen komutu çalıştır (eval yerine, tırnak bozulmasın)
	KAM_VALUE=$(eval "$cmd" 2>/dev/null || true)
	[[ -n $KAM_VALUE ]]
}

kam_kind_command_output() {
	kam_kind_output "$@"
}

kam_kind_bootloader() {
	local bl
	if [[ -f /boot/loader/loader.conf ]]; then
		bl=systemd-boot
	elif [[ -f /boot/grub/grub.cfg ]]; then
		bl=grub
	elif have bootctl; then
		bl=systemd-boot
	elif have grub-mkconfig; then
		bl=grub
	else
		bl=unknown
	fi
	if [[ $bl == unknown ]]; then
		KAM_VALUE=''
		return 1
	fi
	KAM_VALUE=$bl
	return 0
}

kam_kind_rootfs() {
	KAM_VALUE="$(findmnt -no FSTYPE / 2>/dev/null || echo unknown) ($(findmnt -no SOURCE / 2>/dev/null || echo '?'))"
	[[ $KAM_VALUE != 'unknown'* ]]
}

kam_kind_mokutil() {
	have mokutil || { KAM_VALUE='bilinmiyor'; return 1; }
	KAM_VALUE=$(mokutil --sb-state 2>/dev/null || echo 'bilinmiyor')
	[[ -n $KAM_VALUE ]]
}

kam_kind_swap() {
	if swapon --show --noheadings 2>/dev/null | grep -q .; then
		KAM_VALUE=$(swapon --show 2>/dev/null | tr '\n' ';' | sed 's/;$//')
		return 0
	fi
	KAM_VALUE='Aktif swap yok.'
	return 1
}

kam_kind_zram() {
	if have zramctl && zramctl --noheadings 2>/dev/null | grep -q .; then
		KAM_VALUE=$(zramctl 2>/dev/null | tr '\n' ';' | sed 's/;$//')
		return 0
	fi
	KAM_VALUE=''
	return 1
}

kam_kind_compare() {
	local cmd a_cmd b_cmd op
	cmd=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.cmd")
	a_cmd=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.a_cmd")
	b_cmd=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.b_cmd")
	op=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.op")
	[[ -z $cmd || -z $a_cmd || -z $b_cmd ]] && { KAM_VALUE=''; return 1; }
	local out
	out=$(eval "$cmd" 2>/dev/null || true)
	# awk komutlarını çalıştır; $2 gibi alanlar genişletilmeden geçmeli
	KAM_A=$(eval "printf '%s\\n' \"\$out\" | $a_cmd" 2>/dev/null || true)
	KAM_B=$(eval "printf '%s\\n' \"\$out\" | $b_cmd" 2>/dev/null || true)
	[[ -n $KAM_A && -n $KAM_B ]] || { KAM_VALUE=''; return 1; }
	KAM_VALUE=$KAM_A
	case $op in
		ge) ((KAM_A >= KAM_B)) ;;
		gt) ((KAM_A > KAM_B)) ;;
		le) ((KAM_A <= KAM_B)) ;;
		lt) ((KAM_A < KAM_B)) ;;
		eq) [[ $KAM_A == "$KAM_B" ]] ;;
		ne) [[ $KAM_A != "$KAM_B" ]] ;;
		*) return 1 ;;
	esac
}

kam_kind_file_grep() {
	local file pattern
	file=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.file")
	pattern=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.pattern")
	[[ -z $file ]] && { KAM_VALUE=''; return 1; }
	KAM_VALUE=$(grep -o "$pattern" "$file" 2>/dev/null | head -n1 || true)
	[[ -n $KAM_VALUE ]]
}

kam_kind_file_exists() {
	local file
	file=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.file")
	[[ -z $file ]] && { KAM_VALUE=''; return 1; }
	[[ -e $file ]]
}

kam_kind_command_exists() {
	local cmd
	cmd=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.command")
	[[ -z $cmd ]] && { KAM_VALUE=''; return 1; }
	have "$cmd"
}

kam_kind_cmdline_has() {
	local key cmdline
	key=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.key")
	[[ -z $key ]] && { KAM_VALUE=''; return 1; }
	cmdline=$(cat /proc/cmdline 2>/dev/null || true)
	if [[ $cmdline =~ (^| )$key=([^ ]+) ]]; then
		KAM_VALUE=${BASH_REMATCH[2]}
		return 0
	fi
	KAM_VALUE=''
	return 1
}

kam_kind_mkinitcpio_hook() {
	local hook hooks_line
	hook=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.hook")
	hooks_line=$(grep -E '^HOOKS=' /etc/mkinitcpio.conf 2>/dev/null | tail -n1 || true)
	[[ -z $hook || -z $hooks_line ]] && { KAM_VALUE=''; return 1; }
	KAM_VALUE=$hook
	[[ $hooks_line == *"$hook"* ]]
}

kam_kind_service_active() {
	local svc
	svc=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.service")
	[[ -z $svc ]] && { KAM_VALUE=''; return 1; }
	KAM_VALUE=$svc
	systemctl is-active --quiet "$svc" 2>/dev/null
}

kam_kind_failed_units() {
	local failed
	failed=$(systemctl --failed --no-legend --no-pager 2>/dev/null || true)
	[[ -z $failed ]] && { KAM_VALUE=''; return 0; }
	KAM_VALUE=$(printf '%s\n' "$failed" | tr '\n' '; ' | sed 's/; $//')
	return 1
}

kam_kind_masked_units() {
	local masked
	masked=$(systemctl list-unit-files --state=masked --no-legend --no-pager 2>/dev/null || true)
	[[ -z $masked ]] && { KAM_VALUE=''; return 0; }
	KAM_VALUE=$(printf '%s\n' "$masked" | tr '\n' '; ' | sed 's/; $//')
	return 1
}

kam_kind_orphans() {
	local -a list
	mapfile -t list < <(pacman -Qtdq 2>/dev/null || true)
	((${#list[@]} == 0)) && { KAM_VALUE=''; return 0; }
	KAM_COUNT=${#list[@]}
	KAM_VALUE=$(printf '%s ' "${list[@]}" | sed 's/ $//')
	return 1
}

kam_kind_foreign() {
	local -a list
	mapfile -t list < <(pacman -Qmq 2>/dev/null || true)
	((${#list[@]} == 0)) && { KAM_VALUE=''; return 0; }
	KAM_COUNT=${#list[@]}
	KAM_VALUE=$(printf '%s ' "${list[@]}" | sed 's/ $//')
	return 1
}

kam_kind_glob_count() {
	local pattern
	pattern=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.pattern")
	[[ -z $pattern ]] && { KAM_VALUE=0; return 0; }
	local -a list
	mapfile -t list < <(compgen -G "$pattern" 2>/dev/null || true)
	KAM_VALUE=${#list[@]}
	((KAM_VALUE == 0))
}

kam_kind_any() {
	# params.checks listesindeki koşullardan herhangi biri sağlanırsa pass
	local n i cond
	n=$(kam_yaml_count "$YAML_FILE" "$YAML_PATH.params.checks")
	for ((i = 0; i < n; i++)); do
		cond=$(kam_yaml_get "$YAML_FILE" "$YAML_PATH.params.checks[$i]")
		case $cond in
			file_exists) kam_kind_file_exists ;;
			file_grep) kam_kind_file_grep ;;
			command_exists) kam_kind_command_exists ;;
			*) continue ;;
		esac
		[[ $? -eq 0 ]] && return 0
	done
	KAM_VALUE=''
	return 1
}

kam_kind_arch() {
	if [[ -f /etc/arch-release ]] || have pacman; then
		KAM_VALUE='Arch'
		return 0
	fi
	KAM_VALUE=''
	return 1
}

kam_kind_unknown() { KAM_VALUE=''; return 1; }

# --- check yürütme ----------------------------------------------------------
_run_check() {
	local path=$1
	YAML_PATH=$path
	local kind
	kind=$(kam_yaml_get "$YAML_FILE" "$path.kind")
	[[ -z $kind ]] && return 0

	KAM_VALUE=''
	KAM_COUNT=0
	KAM_A=''
	KAM_B=''

	local fn="kam_kind_$kind"
	[[ $(type -t "$fn") == function ]] || fn=kam_kind_unknown

	local rc=0
	"$fn" || rc=1

	# pass/fail seviyesi ve mesaj
	local branch=pass
	((rc != 0)) && branch=fail
	local level msg
	level=$(kam_yaml_get "$YAML_FILE" "$path.$branch.level")
	msg=$(kam_yaml_get "$YAML_FILE" "$path.$branch.message")
	[[ -z $level ]] && level=note
	[[ -z $msg ]] && msg="{value}"
	_emit "$level" "$msg"
}

_run_ritual() {
	local name=$1 yaml=${2:-$RITUAL_DIR/$1.yaml}
	[[ -f $yaml ]] || die "Ritüel bulunamadı: $name"
	YAML_FILE=$yaml
	ISSUES=0

	# Ritüel verisini bir kez parse et; API'ler KAM_YAML'ı kullanır
	kam_yaml_parse "$yaml" >/dev/null 2>&1 || die "Ritüel dosyası okunamadı: $yaml"

	local title
	title=$(kam_yaml_get "$yaml" title)
	[[ -z $title ]] && title=$name

	# Ritüel başlığı
	printf '\n%b== %s ==%b\n' "$C_CYAN" "$title" "$C_RESET"

	local n_sections i j
	n_sections=$(kam_yaml_count "$yaml" sections)
	for ((i = 0; i < n_sections; i++)); do
		local stitle n_checks
		stitle=$(kam_yaml_get "$yaml" "sections[$i].title")
		[[ -n $stitle ]] && printf '%b  %s%b\n' "$C_CYAN" "$stitle" "$C_RESET"
		n_checks=$(kam_yaml_count "$yaml" "sections[$i].checks")
		for ((j = 0; j < n_checks; j++)); do
			_run_check "sections[$i].checks[$j]"
		done
	done

	printf '\n'
	if ((ISSUES == 0)); then
		local okmsg
		okmsg=$(kam_yaml_get "$yaml" summary.ok)
		[[ -z $okmsg ]] && okmsg="Ritüel tamam."
		log "$(_resolve_msg "$okmsg")"
	else
		local warnmsg
		warnmsg=$(kam_yaml_get "$yaml" summary.issues)
		[[ -z $warnmsg ]] && warnmsg="Ritüel tamam: $ISSUES sorun bulundu."
		warn "$(_resolve_msg "$warnmsg")"
	fi
	exit $((ISSUES > 0))
}

# --- CLI --------------------------------------------------------------------
# Ritüel adı iki biçimde olabilir: "doctor" (klasör aranır) veya "arch/hibernate".

# rituals/<klasör>/<ad>.yaml yolunu üretir; bulunamazsa boş döner.
_ritual_path() {
	local name=$1
	# Açık klasör: arch/hibernate
	if [[ $name == */* ]]; then
		local f="$RITUAL_DIR/$name.yaml"
		[[ -f $f ]] && { printf '%s' "$f"; return 0; }
		return 1
	fi
	# Tek ad: klasör sırasıyla ara
	local dir
	for dir in common arch deb fedora alpine gentoo apps fix; do
		if [[ -f "$RITUAL_DIR/$dir/$name.yaml" ]]; then
			printf '%s' "$RITUAL_DIR/$dir/$name.yaml"
			return 0
		fi
	done
	return 1
}

# Ritüel adlarını "klasör/ad" biçiminde listeler.
list_rituals() {
	local dir f
	for dir in common arch deb fedora alpine gentoo apps fix; do
		for f in "$RITUAL_DIR/$dir"/*.yaml; do
			[[ -f $f ]] || continue
			printf '%s/%s\n' "$dir" "$(basename "$f" .yaml)"
		done
	done
}

# Ritüel uyar mı (KAM_ALL değilse distro filtresi)
_ritual_applicable() {
	local path=$1
	kam_yaml_parse "$path" >/dev/null 2>&1 || return 0

	# distro bir liste olabilir (distro[0]=arch) veya tek satır (distro=arch)
	local -a dlist=()
	local dn i d
	dn=$(kam_yaml_count "$path" distro 2>/dev/null || echo 0)
	if [[ -n $dn && $dn -gt 0 ]]; then
		for ((i = 0; i < dn; i++)); do
			d=$(kam_yaml_get "$path" "distro[$i]" 2>/dev/null)
			[[ -n $d ]] && dlist+=("$d")
		done
	else
		d=$(kam_yaml_get "$path" distro 2>/dev/null)
		[[ -n $d ]] && dlist+=("$d")
	fi

	# distro alanı yoksa her sistemde çalışır
	((${#dlist[@]} == 0)) && return 0

	for d in "${dlist[@]}"; do
		[[ $d == "$KAM_DISTRO" ]] && return 0
	done
	return 1
}

cmd_list() {
	printf '%bDağıtım:%b %s\n' "$C_CYAN" "$C_RESET" "$KAM_DISTRO"
	printf 'Klasörler: common/ arch/ deb/ fedora/ alpine/ gentoo/ apps/ fix/\n\n'

	local -a show=()
	local p
	while read -r p; do
		[[ -z $p ]] && continue
		local full
		full=$(_ritual_path "$p") || continue
		if ((KAM_ALL)) || _ritual_applicable "$full"; then
			show+=("$p|$full")
		fi
	done < <(list_rituals | sort)

	printf 'Uygun ritüeller (%s):\n' "${#show[@]}"
	local entry name full title
	for entry in "${show[@]}"; do
		name=${entry%%|*}
		full=${entry#*|}
		kam_yaml_parse "$full" >/dev/null 2>&1
		title=$(kam_yaml_get "$full" title 2>/dev/null)
		printf '  %-24s %s\n' "$name" "$title"
	done
	if ((!KAM_ALL)); then
		printf '\n%s--all ile hepsini görebilirsin.%b\n' "$C_DIM" "$C_RESET"
	fi
}

cmd_show() {
	local name=$1
	[[ -n $name ]] || die "Ritüel adı gerekli."
	local f
	f=$(_ritual_path "$name") || die "Ritüel bulunamadı: $name"
	kam_yaml_parse "$f" >/dev/null 2>&1
	section "$name"
	kam_yaml_dump "$f" | sed 's/^/  /'
}

cmd_run() {
	local name=$1
	shift
	[[ -n $name ]] || die "Ritüel adı gerekli."
	local f
	f=$(_ritual_path "$name") || die "Ritüel bulunamadı: $name"
	local base
	base=${name##*/}
	_run_ritual "$base" "$f"
}

cmd_menu() {
	local -a names=() paths=()
	local p full
	while read -r p; do
		[[ -z $p ]] && continue
		full=$(_ritual_path "$p") || continue
		if ((KAM_ALL)) || _ritual_applicable "$full"; then
			names+=("$p")
			paths+=("$full")
		fi
	done < <(list_rituals | sort)

	printf '%s\n' "${C_CYAN}========================================${C_RESET}"
	printf '%s\n' "${C_CYAN}        ARCH-KAM RİTÜEL MENÜSÜ        ${C_RESET}"
	printf '%bDağıtım:%b %s  %b(klasör/ritüel)%b\n' "$C_CYAN" "$C_RESET" "$KAM_DISTRO" "$C_DIM" "$C_RESET"
	printf '%s\n' "${C_CYAN}========================================${C_RESET}"

	local i=0 n title
	for n in "${names[@]}"; do
		((i++))
		kam_yaml_parse "${paths[$((i - 1))]}" >/dev/null 2>&1
		title=$(kam_yaml_get "${paths[$((i - 1))]}" title 2>/dev/null)
		printf '%2d) %-24s %s\n' "$i" "$n" "$title"
	done
	printf '%2d) Çıkış\n' "$((i + 1))"
	printf '%s\n' "${C_CYAN}========================================${C_RESET}"

	local choice
	read -r -p "Seçim [1-$((i + 1))]: " choice
	[[ $choice =~ ^[0-9]+$ ]] || die "Geçersiz seçim."
	((choice == i + 1)) && exit 0
	((choice >= 1 && choice <= i)) || die "Geçersiz seçim."
	local picked=${names[$((choice - 1))]}
	_run_ritual "${picked##*/}" "${paths[$((choice - 1))]}"
}

while [[ $# -gt 0 ]]; do
	case $1 in
		--all) KAM_ALL=1; shift ;;
		*) break ;;
	esac
done

case ${1:-} in
	list) cmd_list ;;
	show) shift; cmd_show "$@" ;;
	run) shift; cmd_run "$@" ;;
	menu) cmd_menu ;;
	-h | --help | help)
		printf 'Kullanım: %s [--all] {list|show <r>|run <r>|menu|help}\n' "$0"
		printf 'Ritüel tanımları: %s/<klasör>/<ritüel>.yaml\n' "$RITUAL_DIR"
		printf 'Klasörler: common/ arch/ deb/ fedora/ alpine/ gentoo/ apps/ fix/\n'
		;;
	'') cmd_menu ;;
	*) die "Bilinmeyen komut: $1" ;;
esac
