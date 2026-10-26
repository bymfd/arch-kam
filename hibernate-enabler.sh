#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

SWAPFILE=/swapfile
TARGET_SWAP_MB=
FORCE=0
RESTORE=0

usage() {
	cat <<EOF
Kullanım: sudo $0 [--size MB] [--force] [--restore]

  --size MB   Swap dosyası boyutu (varsayılan: RAM + 2048 MB)
  --force     Mevcut swap dosyasının üzerine yaz
  --restore   resume ayarlarını kaldır ve swap dosyasını sil
EOF
}

while [[ $# -gt 0 ]]; do
	case $1 in
		--size)
			[[ $# -ge 2 ]] || die "--size bir MB değeri istiyor."
			TARGET_SWAP_MB=$2
			shift 2
			;;
		--size=*)
			TARGET_SWAP_MB=${1#*=}
			shift
			;;
		--force | -f)
			FORCE=1
			shift
			;;
		--restore)
			RESTORE=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*) die "Bilinmeyen argüman: $1" ;;
	esac
done

require_root
require_arch
have mkinitcpio || die "mkinitcpio bulunamadı."

if [[ -n $TARGET_SWAP_MB && ! $TARGET_SWAP_MB =~ ^[0-9]+$ ]]; then
	die "--size pozitif bir tam sayı olmalı (MB)."
fi

BOOTLOADER=$(detect_bootloader)
if [[ $BOOTLOADER == grub ]]; then
	have grub-mkconfig || die "grub-mkconfig bulunamadı."
fi

update_grub_cmdline() {
	local file=/etc/default/grub
	local line value new

	[[ -f $file ]] || die "GRUB yapılandırması yok: $file"
	backup_once "$file" arch-kam-hibernate.bak

	line=$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$file" | tail -n1 || true)
	if [[ -z $line ]]; then
		printf '\nGRUB_CMDLINE_LINUX_DEFAULT="resume=UUID=%s resume_offset=%s"\n' "$SWAP_UUID" "$NEW_OFFSET" >> "$file"
		return
	fi

	value=${line#GRUB_CMDLINE_LINUX_DEFAULT=}
	value=${value#\"}
	value=${value%\"}
	new=$(filter_resume_words "$value")
	new+="${new:+ }resume=UUID=$SWAP_UUID resume_offset=$NEW_OFFSET"

	awk -v new="$new" '
		/^GRUB_CMDLINE_LINUX_DEFAULT=/ && !done {
			print "GRUB_CMDLINE_LINUX_DEFAULT=\"" new "\""
			done=1
			next
		}
		{ print }
	' "$file" > "$file.tmp"
	mv "$file.tmp" "$file"
}

remove_grub_resume() {
	local file=/etc/default/grub
	local line value new

	[[ -f $file ]] || return 0
	backup_once "$file" arch-kam-hibernate.bak

	line=$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$file" | tail -n1 || true)
	[[ -n $line ]] || return 0

	value=${line#GRUB_CMDLINE_LINUX_DEFAULT=}
	value=${value#\"}
	value=${value%\"}
	new=$(filter_resume_words "$value")

	awk -v new="$new" '
		/^GRUB_CMDLINE_LINUX_DEFAULT=/ && !done {
			print "GRUB_CMDLINE_LINUX_DEFAULT=\"" new "\""
			done=1
			next
		}
		{ print }
	' "$file" > "$file.tmp"
	mv "$file.tmp" "$file"
}

update_options_file() {
	local file=$1
	local line value new

	line=$(grep -E '^options ' "$file" | tail -n1 || true)
	if [[ -z $line ]]; then
		printf 'options resume=UUID=%s resume_offset=%s\n' "$SWAP_UUID" "$NEW_OFFSET" >> "$file"
		return
	fi

	value=${line#options }
	new=$(filter_resume_words "$value")
	new+="${new:+ }resume=UUID=$SWAP_UUID resume_offset=$NEW_OFFSET"

	awk -v new="$new" '
		/^options / && !done {
			if (new == "") print "options"
			else print "options " new
			done=1
			next
		}
		{ print }
	' "$file" > "$file.tmp"
	mv "$file.tmp" "$file"
}

remove_options_file() {
	local file=$1
	local line value new

	line=$(grep -E '^options ' "$file" | tail -n1 || true)
	[[ -n $line ]] || return 0

	value=${line#options }
	new=$(filter_resume_words "$value")

	awk -v new="$new" '
		/^options / && !done {
			if (new == "") print "options"
			else print "options " new
			done=1
			next
		}
		{ print }
	' "$file" > "$file.tmp"
	mv "$file.tmp" "$file"
}

update_kernel_cmdline() {
	local file=/etc/kernel/cmdline
	local value new

	[[ -f $file ]] || return 0
	backup_once "$file" arch-kam-hibernate.bak

	value=$(tr '\n' ' ' < "$file")
	value=${value% }
	new=$(filter_resume_words "$value")
	new+="${new:+ }resume=UUID=$SWAP_UUID resume_offset=$NEW_OFFSET"
	printf '%s\n' "$new" > "$file"
}

remove_kernel_cmdline() {
	local file=/etc/kernel/cmdline
	local value new

	[[ -f $file ]] || return 0
	backup_once "$file" arch-kam-hibernate.bak

	value=$(tr '\n' ' ' < "$file")
	value=${value% }
	new=$(filter_resume_words "$value")
	printf '%s\n' "$new" > "$file"
}

update_systemd_boot_resume() {
	local entry updated=0

	update_kernel_cmdline
	for entry in /boot/loader/entries/*.conf; do
		[[ -e $entry ]] || continue
		backup_once "$entry" arch-kam-hibernate.bak
		update_options_file "$entry"
		updated=1
	done

	(( updated )) || warn "systemd-boot entry bulunamadı; resume parametresini elle eklemen gerekebilir."
}

remove_systemd_boot_resume() {
	local entry

	remove_kernel_cmdline
	for entry in /boot/loader/entries/*.conf; do
		[[ -e $entry ]] || continue
		backup_once "$entry" arch-kam-hibernate.bak
		remove_options_file "$entry"
	done
}

set_resume_hook() {
	local file=/etc/mkinitcpio.conf

	[[ -f $file ]] || die "mkinitcpio.conf yok: $file"
	backup_once "$file" arch-kam-hibernate.bak

	sed -i -E '/^HOOKS=/ s/[[:space:]]*\bresume\b[[:space:]]*/ /g' "$file"
	if grep -qE '^HOOKS=.*\bblock\b' "$file"; then
		sed -i -E '/^HOOKS=/ s/\bblock\b/block resume/' "$file"
	elif grep -qE '^HOOKS=.*\budev\b' "$file"; then
		sed -i -E '/^HOOKS=/ s/\budev\b/udev resume/' "$file"
	elif grep -qE '^HOOKS=.*\bfilesystems\b' "$file"; then
		sed -i -E '/^HOOKS=/ s/\bfilesystems\b/resume filesystems/' "$file"
	else
		sed -i -E '/^HOOKS=/ s/\)/ resume)/' "$file"
	fi
	sed -i -E '/^HOOKS=/ s/[[:space:]]+/ /g; /^HOOKS=/ s/\( /(/; /^HOOKS=/ s/ \)/)/' "$file"
}

remove_resume_hook() {
	local file=/etc/mkinitcpio.conf

	[[ -f $file ]] || return 0
	backup_once "$file" arch-kam-hibernate.bak

	sed -i -E '/^HOOKS=/ s/[[:space:]]*\bresume\b[[:space:]]*/ /g' "$file"
	sed -i -E '/^HOOKS=/ s/[[:space:]]+/ /g; /^HOOKS=/ s/\( /(/; /^HOOKS=/ s/ \)/)/' "$file"
}

regenerate() {
	case $BOOTLOADER in
		grub)
			have grub-mkconfig || die "grub-mkconfig bulunamadı."
			grub-mkconfig -o /boot/grub/grub.cfg
			;;
		systemd-boot)
			log "systemd-boot: kernel parametreleri entry dosyalarına yazıldı."
			;;
		*)
			warn "Bootloader tanınmadı; resume parametrelerini elle kontrol et."
			;;
	esac
	mkinitcpio -P
}

if (( RESTORE )); then
	log "Uyku ritüeli geri alınıyor..."

	case $BOOTLOADER in
		grub) remove_grub_resume ;;
		systemd-boot) remove_systemd_boot_resume ;;
		*) warn "Bootloader tanınmadı; resume parametrelerini elle kaldır." ;;
	esac
	remove_resume_hook

	if swapon --show=NAME --noheadings | grep -qx "$SWAPFILE"; then
		swapoff "$SWAPFILE"
	fi
	if [[ -e $SWAPFILE ]]; then
		if (( FORCE )) || confirm "$SWAPFILE silinsin mi?"; then
			rm -f "$SWAPFILE"
		fi
	fi

	regenerate
	log "Geri alma tamam. Yeniden başlat."
	exit 0
fi

RAM_SIZE=$(free -m | awk '/^Mem:/ {print $2}')
[[ -n $RAM_SIZE ]] || die "RAM boyutu okunamadı."
: "${TARGET_SWAP_MB:=$((RAM_SIZE + 2048))}"
(( TARGET_SWAP_MB > 0 )) || die "--size sıfırdan büyük olmalı."

if (( TARGET_SWAP_MB < RAM_SIZE )); then
	warn "Swap boyutu RAM'den küçük; hibernate başarısız olabilir."
	if (( ! FORCE )) && ! confirm "Yine de devam edeyim mi?"; then
		exit 1
	fi
fi

if (( TARGET_SWAP_MB > 65536 )); then
	warn "Swap boyutu ${TARGET_SWAP_MB}MB. Disk alanını kontrol et; --size ile küçültebilirsin."
fi

if swapon --show=NAME --noheadings | grep -qx "$SWAPFILE"; then
	if (( ! FORCE )); then
		warn "$SWAPFILE aktif swap. Üzerine yazmak için --force kullan."
		exit 1
	fi
	swapoff "$SWAPFILE"
fi

if [[ -e $SWAPFILE ]]; then
	if (( ! FORCE )); then
		warn "$SWAPFILE zaten var. Üzerine yazmak için --force kullan."
		exit 1
	fi
	rm -f "$SWAPFILE"
fi

AVAIL_MB=$(df -Pm "$(dirname "$SWAPFILE")" 2>/dev/null | awk 'NR==2 {print $4}')
if [[ -n ${AVAIL_MB:-} ]] && (( AVAIL_MB < TARGET_SWAP_MB + 512 )); then
	die "Yetersiz disk alanı: ${AVAIL_MB}MB boş, ${TARGET_SWAP_MB}MB + 512MB gerekiyor."
fi

FS_TYPE=$(root_fs)
log "Kök dosya sistemi: $FS_TYPE"
log "Swap dosyası: $SWAPFILE (${TARGET_SWAP_MB}MB)"

if [[ $FS_TYPE == btrfs ]]; then
	log "BTRFS protokolü uygulanıyor..."
	truncate -s 0 "$SWAPFILE"
	chattr +C "$SWAPFILE" 2>/dev/null || warn "chattr +C uygulanamadı; dosya CoW açık olabilir."
	if have btrfs; then
		btrfs property set "$SWAPFILE" compression none || warn "Btrfs compression=none ayarlanamadı."
	else
		warn "btrfs komutu yok; compression=none atlandı."
	fi
	fallocate -l "${TARGET_SWAP_MB}M" "$SWAPFILE"
else
	if have fallocate; then
		fallocate -l "${TARGET_SWAP_MB}M" "$SWAPFILE"
	else
		dd if=/dev/zero of="$SWAPFILE" bs=1M count="$TARGET_SWAP_MB" status=progress
	fi
fi

chmod 600 "$SWAPFILE"
mkswap "$SWAPFILE"
swapon "$SWAPFILE" || die "Swap etkinleştirilemedi."

SWAP_UUID=$(findmnt -no UUID -T "$SWAPFILE") || die "Swap UUID okunamadı."
[[ -n $SWAP_UUID ]] || die "Swap UUID boş."

if [[ $FS_TYPE == btrfs ]] && have btrfs && btrfs inspect-internal map-swapfile -r "$SWAPFILE" >/dev/null 2>&1; then
	NEW_OFFSET=$(btrfs inspect-internal map-swapfile -r "$SWAPFILE")
else
	have filefrag || die "filefrag bulunamadı (util-linux)."
	NEW_OFFSET=$(filefrag -v "$SWAPFILE" | awk '$1=="0:" {print $4; exit}' | tr -d '.')
fi
[[ -n $NEW_OFFSET ]] || die "resume_offset hesaplanamadı."

ROOT_SOURCE=$(findmnt -no SOURCE / 2>/dev/null || true)
ROOT_SOURCE=${ROOT_SOURCE%%\[*}
if [[ -n $ROOT_SOURCE ]] && lsblk -no TYPE "$ROOT_SOURCE" 2>/dev/null | grep -qx crypt; then
	warn "Şifreli kök algılandı; encrypt hook sırası ve resume parametresini elle doğrula."
fi

log "Swap UUID: $SWAP_UUID"
log "resume_offset: $NEW_OFFSET"

case $BOOTLOADER in
	grub) update_grub_cmdline ;;
	systemd-boot) update_systemd_boot_resume ;;
	*) warn "Bootloader tanınmadı. Şu parametreyi elle ekle: resume=UUID=$SWAP_UUID resume_offset=$NEW_OFFSET" ;;
esac

set_resume_hook
regenerate

log "Ritüel tamam. Yeniden başlat, sonra test et: systemctl hibernate"
