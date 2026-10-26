#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

ISSUES=0

usage() {
	cat <<EOF
Kullanım: $0

Salt okunur teşhis. Hiçbir şeyi değiştirmez; yalnızca rapor verir.
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
	usage
	exit 0
fi
[[ $# -eq 0 ]] || die "Bilinmeyen argüman: $1"

section() { printf '\n%b== %s ==%b\n' "$C_CYAN" "$*" "$C_RESET"; }
ok() { printf '  %b[ok]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
bad() {
	printf '  %b[!!]%b %s\n' "$C_RED" "$C_RESET" "$*"
	((ISSUES += 1))
}
note() { printf '  - %s\n' "$*"; }

section "Sistem"
if [[ -r /etc/os-release ]]; then
	OS_NAME=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2; exit}' /etc/os-release)
	note "Dağıtım: ${OS_NAME:-bilinmiyor}"
fi
note "Kernel: $(uname -r)"
note "Mimari: $(uname -m)"

if [[ -f /etc/arch-release ]] || have pacman; then
	ok "Arch tabanlı"
else
	bad "Arch tabanlı değil (pacman bulunamadı)"
fi

section "Önyükleme"
BOOTLOADER=$(detect_bootloader)
case $BOOTLOADER in
	grub) ok "GRUB" ;;
	systemd-boot) ok "systemd-boot" ;;
	*) bad "Bootloader tanınmadı" ;;
esac

ROOT_FS=$(root_fs)
ROOT_SRC=$(findmnt -no SOURCE / 2>/dev/null || true)
note "Kök dosya sistemi: $ROOT_FS (${ROOT_SRC:-bilinmiyor})"

if have mokutil; then
	SB=$(mokutil --sb-state 2>/dev/null || true)
	note "Secure Boot: ${SB:-bilinmiyor}"
fi

section "Disk"
df -h / /boot /var 2>/dev/null | awk 'NR==1 {print; next} ($6=="/" || $6=="/boot" || $6=="/var") && !seen[$6]++ {print}'

section "Bellek ve swap"
free -h
if swapon --show --noheadings 2>/dev/null | grep -q .; then
	swapon --show
else
	note "Aktif swap yok."
fi

if [[ -e /swapfile ]]; then
	note "/swapfile: $(du -h /swapfile 2>/dev/null | cut -f1 || echo '?')"
fi

if have zramctl && zramctl --noheadings 2>/dev/null | grep -q .; then
	warn "zram aktif:"
	zramctl 2>/dev/null | sed 's/^/    /'
fi

section "Hibernate"
if grep -qw disk /sys/power/state 2>/dev/null; then
	ok "Kernel hibernate (disk) destekliyor"
else
	bad "Kernel hibernate desteklemiyor (test: cat /sys/power/state)"
fi

CMDLINE=$(cat /proc/cmdline 2>/dev/null || true)
if [[ $CMDLINE =~ (^| )resume=([^ ]+) ]]; then
	ok "resume=${BASH_REMATCH[2]}"
else
	bad "resume= kernel parametresi yok"
fi

if [[ $CMDLINE =~ (^| )resume_offset=([^ ]+) ]]; then
	ok "resume_offset=${BASH_REMATCH[2]}"
else
	note "resume_offset yok (swapfile ile hibernate için gerekli)"
fi

HOOKS_LINE=$(grep -E '^HOOKS=' /etc/mkinitcpio.conf 2>/dev/null | tail -n1 || true)
if [[ $HOOKS_LINE == *resume* ]]; then
	ok "mkinitcpio resume hook var"
	if [[ $HOOKS_LINE =~ filesystems.*resume ]]; then
		bad "resume hook filesystems'ten sonra; doğru sıra değil"
	fi
else
	bad "mkinitcpio resume hook yok"
fi

section "Güç yönetimi"
if have tlp-stat; then
	ok "TLP kurulu"
	tlp-stat -s 2>/dev/null | sed -n '1,10p' | sed 's/^/    /' || true
else
	note "TLP kurulu değil"
fi

if systemctl is-active --quiet power-profiles-daemon.service 2>/dev/null; then
	warn "power-profiles-daemon aktif; TLP ile çakışabilir."
fi

section "Servisler ve paketler"
FAILED=$(systemctl --failed --no-legend --no-pager 2>/dev/null || true)
if [[ -n $FAILED ]]; then
	bad "Başarısız systemd unit:"
	printf '%s\n' "$FAILED" | sed 's/^/    /'
else
	ok "Başarısız systemd unit yok"
fi

if have pacman; then
	mapfile -t ORPHANS < <(pacman -Qtdq 2>/dev/null || true)
	if ((${#ORPHANS[@]} > 0)); then
		note "Yetim paketler (${#ORPHANS[@]}):"
		printf '    %s\n' "${ORPHANS[@]}"
	else
		ok "Yetim paket yok"
	fi
fi

printf '\n'
if ((ISSUES == 0)); then
	log "Teşhis tamam: kritik sorun yok."
else
	warn "Teşhis tamam: $ISSUES sorun bulundu."
fi
exit $((ISSUES > 0))
