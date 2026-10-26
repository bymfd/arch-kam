#!/usr/bin/env bash

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
		cp -a "$file" "$backup"
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
