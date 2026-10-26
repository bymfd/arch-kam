#!/usr/bin/env bash
# kam.sh — arch-kam motoru. Tek generic yürütücü: rituals/*.yaml'ı okur,
# her check'in kind'ına göre koşulu değerlendirir, pass/fail seviyesiyle basar.
#
# Hiçbir ritüel mantığı bu dosyada TANIMLANMAZ. Yalnızca kind'ların
# (koşul tiplerinin) nasıl değerlendirildiği burada olur; ne kontrol edileceği,
# ne konuşulacağı, hangi seviyede olacağı tamamen YAML'dadır.
#
# Kullanım:
#   kam.sh list               Ritüelleri listele
#   kam.sh show <ritüel>      Ritüel tanımını göster
#   kam.sh run <ritüel> [a]   Ritüeli çalıştır
#   kam.sh menu               Menü
#   kam.sh help

set -uo pipefail

KAM_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=kam_yaml.sh
source "$KAM_ROOT/kam_yaml.sh"

RITUAL_DIR="$KAM_ROOT/rituals"
ISSUES=0
YAML_FILE=''

if [[ -t 1 ]]; then
	C_RESET=$'\033[0m'
	C_GREEN=$'\033[0;32m'
	C_RED=$'\033[0;31m'
	C_YELLOW=$'\033[1;33m'
	C_CYAN=$'\033[0;36m'
else
	C_RESET=''
	C_GREEN=''
	C_RED=''
	C_YELLOW=''
	C_CYAN=''
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
	local name=$1 yaml="$RITUAL_DIR/$1.yaml"
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
list_rituals() {
	local f
	for f in "$RITUAL_DIR"/*.yaml; do
		[[ -f $f ]] || continue
		printf '%s\n' "$(basename "$f" .yaml)"
	done
}

cmd_list() {
	printf 'Ritüeller (%s):\n' "$(list_rituals | wc -l)"
	local name ro title
	while read -r name; do
		[[ -z $name ]] && continue
		kam_yaml_parse "$RITUAL_DIR/$name.yaml" >/dev/null 2>&1
		title=$(kam_yaml_get "$RITUAL_DIR/$name.yaml" title 2>/dev/null)
		printf '  %-14s %s\n' "$name" "$title"
	done < <(list_rituals | sort)
}

cmd_show() {
	local name=$1
	[[ -n $name ]] || die "Ritüel adı gerekli."
	local f="$RITUAL_DIR/$name.yaml"
	[[ -f $f ]] || die "Ritüel bulunamadı: $name"
	kam_yaml_parse "$f" >/dev/null 2>&1
	section "$name"
	kam_yaml_dump "$f" | sed 's/^/  /'
}

cmd_run() {
	local name=$1
	shift
	[[ -n $name ]] || die "Ritüel adı gerekli."
	_run_ritual "$name"
}

cmd_menu() {
	local -a names=()
	while read -r n; do [[ -n $n ]] && names+=("$n"); done < <(list_rituals | sort)
	printf '%s\n' "${C_CYAN}========================================${C_RESET}"
	printf '%s\n' "${C_CYAN}        ARCH-KAM RİTÜEL MENÜSÜ        ${C_RESET}"
	printf '%s\n' "${C_CYAN}========================================${C_RESET}"
	local i=0 n title
	for n in "${names[@]}"; do
		((i++))
		kam_yaml_parse "$RITUAL_DIR/$n.yaml" >/dev/null 2>&1
		title=$(kam_yaml_get "$RITUAL_DIR/$n.yaml" title 2>/dev/null)
		printf '%2d) %-14s %s\n' "$i" "$n" "$title"
	done
	printf '%2d) Çıkış\n' "$((i + 1))"
	printf '%s\n' "${C_CYAN}========================================${C_RESET}"
	local choice
	read -r -p "Seçim [1-$((i + 1))]: " choice
	[[ $choice =~ ^[0-9]+$ ]] || die "Geçersiz seçim."
	((choice == i + 1)) && exit 0
	((choice >= 1 && choice <= i)) || die "Geçersiz seçim."
	_run_ritual "${names[$((choice - 1))]}"
}

case ${1:-} in
	list) cmd_list ;;
	show) shift; cmd_show "$@" ;;
	run) shift; cmd_run "$@" ;;
	menu) cmd_menu ;;
	-h | --help | help)
		printf 'Kullanım: %s {list|show <r>|run <r>|menu|help}\n' "$0"
		printf 'Ritüel tanımları: %s/*.yaml\n' "$RITUAL_DIR"
		;;
	'') cmd_menu ;;
	*) die "Bilinmeyen komut: $1" ;;
esac
