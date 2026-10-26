#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

FSTAB=/etc/fstab

usage() {
	cat <<EOF
Kullanım: $0 [--list] [--fix] [--all]

The Nine Realms: /etc/fstab ile gerçek mount durumunu karşılaştırır.
Çözülemeyen kaynakları, mount edilmemiş girdileri ve
fstab'da olmayan mount'ları işaretler.

  --list     fstab ve mount özetini göster (varsayılan, root gerektirmez)
  --fix      fstab'da olup bağlanmamış girdileri bağlamayı dene (root gerekir)
  --all      --fix ile; onay sormadan uygula
  -h, --help Bu yardım
EOF
}

MODE='list'
ALL_FIX=0

while [[ $# -gt 0 ]]; do
	case $1 in
		--list) MODE=list; shift ;;
		--fix) MODE=fix; shift ;;
		--all) ALL_FIX=1; shift ;;
		-h | --help) usage; exit 0 ;;
		*) die "Bilinmeyen argüman: $1" ;;
	esac
done

ISSUES=0

is_virtual() {
	case $1 in
		none | tmpfs | devtmpfs | proc | sysfs | cgroup | cgroup2 | ramfs | debugfs | securityfs | bpf | pstore | efivarfs | mqueue | hugetlbfs | fusectl | configfs | binfmt_misc | tracefs | autofs | nsfs | rpc_pipefs | selinuxfs | devpts | portal | nfsd | sunrpc | dev | run)
			return 0
			;;
		*) return 1 ;;
	esac
}

# systemd tarafından üretilen sanal hedefler (fstab'a girmez, normaldir).
is_system_mount() {
	local t=$1 base
	base=${t%%/*}            # /dev/shm -> dev, /sys/kernel -> sys, /run/user -> run
	base=${base#/}
	base=${t#/}
	base=${base%%/*}
	case $base in
		dev | sys | proc | run | var | tmp) return 0 ;;
		*) return 1 ;;
	esac
}

read_fstab() {
	grep -vE '^\s*#|^\s*$' "$FSTAB" 2>/dev/null | awk '{printf "%s\t%s\t%s\n", $1, $2, $3}'
}

# Kaynağı gerçek cihaz yoluna çöz; yetkisiz okumada boş döner.
resolve_source() {
	local src=$1 resolved=''
	if [[ $src =~ ^(UUID|PARTUUID|LABEL|PARTLABEL)= ]]; then
		case ${src%%=*} in
			UUID) resolved=$(readlink -f "/dev/disk/by-uuid/${src#*=}" 2>/dev/null || true) ;;
			PARTUUID) resolved=$(readlink -f "/dev/disk/by-partuuid/${src#*=}" 2>/dev/null || true) ;;
			LABEL) resolved=$(readlink -f "/dev/disk/by-label/${src#*=}" 2>/dev/null || true) ;;
			PARTLABEL) resolved=$(readlink -f "/dev/disk/by-partlabel/${src#*=}" 2>/dev/null || true) ;;
		esac
		[[ -z $resolved ]] && resolved=$(blkid --match-token "$src" -o device 2>/dev/null | head -n1 || true)
	else
		resolved=$src
	fi
	printf '%s' "$resolved"
}

# Hedef dizinin mount noktası kaynağın taban cihazına mı işaret ediyor?
target_mounted() {
	local target=$1 source_base=$2
	[[ -z $target || -z $source_base ]] && return 1
	[[ -d $target ]] || return 1
	local t_src t_base
	t_src=$(findmnt -rno SOURCE --target "$target" 2>/dev/null | head -n1 || true)
	[[ -z $t_src ]] && return 1
	t_base=${t_src%%\[*}
	[[ $t_base == "$source_base" ]] && return 0
	return 1
}

# Gerçek bir mount'un TARGET/SOURCE satırı (findmnt -T <path>)
mount_of() {
	local path=$1
	findmnt -rno TARGET,SOURCE -T "$path" 2>/dev/null | head -n1 | awk '{printf "%s	%s\n", $1, $2}'
}

section "Mount durumu"
echo "  Gerçek mount'lar (kök, /boot/efi, /home):"
for p in / /boot/efi /home; do
	[[ -e $p ]] || continue
	if s=$(findmnt -rno SOURCE -T "$p" 2>/dev/null | head -n1); then
		printf '    %-12s %s\n' "$p" "$s"
	else
		printf '    %-12s (bulunamadı)\n' "$p"
	fi
done
echo

section "fstab denetimi"
if [[ ! -f $FSTAB ]]; then
	die "$FSTAB bulunamadı."
fi

mapfile -t FSTAB_ROWS < <(read_fstab)
note "fstab girdileri: ${#FSTAB_ROWS[@]}"
echo

for row in "${FSTAB_ROWS[@]}"; do
	src=${row%%$'	'*}
	rest=${row#*$'	'}
	target=${rest%%$'	'*}
	fstype=${rest#*$'	'}

	if is_virtual "$src"; then
		note "$target: sanal fs ($src) — denetlenmez"
		continue
	fi
	# Swap girdileri mount noktası değil; swapon ile denetlenir.
	if [[ $fstype == swap ]]; then
		if swapon --show=NAME --noheadings 2>/dev/null | grep -qxF "$src"; then
			ok "$src swap olarak etkin"
		else
			bad "$src swap değil (bağlı değil)"
		fi
		continue
	fi

	resolved=$(resolve_source "$src")
	if [[ -z $resolved ]]; then
		bad "$target: $src çözülemedi (cihaz yok veya yetki yok)"
		continue
	fi
	resolved_base=${resolved%%\[*}
	note "$target: $src -> $resolved"

	if target_mounted "$target" "$resolved_base"; then
		ok "$target bağlı ($src)"
	else
		bad "$target bağlı DEĞİL ($src)"
	fi
done

echo
echo "  Bağlı mount'lerın hedefleri fstab'da var mı?"
for t in $(findmnt -rno TARGET --uniq 2>/dev/null | grep -v '^$' || true); do
	is_virtual "$t" && continue
	# systemd'ın ürettiği sanal mount'lar (dev/sys/proc/run/var/tmp alt dizinleri) fstab'a girmez.
	if is_system_mount "$t"; then
		continue
	fi
	grep -qF -- "$t" "$FSTAB" 2>/dev/null || note "$t (fstab'da yok)"
done

echo
section "Btrfs alt hacimleri"
if have btrfs && [[ $(root_fs) == btrfs ]]; then
	if btrfs subvolume list / > /tmp/.kam_subvols.txt 2>/dev/null; then
		while read -r line; do
			path=$(sed -n 's/.* path \(.*\)$/\1/p' <<< "$line")
			[[ -z $path ]] && continue
			if grep -qF "subvol=/$path" "$FSTAB" 2>/dev/null; then
				ok "subvol=/$path (fstab'da)"
			else
				note "subvol=/$path (fstab'da yok)"
			fi
		done < /tmp/.kam_subvols.txt
		rm -f /tmp/.kam_subvols.txt
	else
		note "Alt hacim listesi okunamadı (root olabilir)."
	fi
else
	note "Kök dosya sistemi btrfs değil veya btrfs yok."
fi

if [[ $MODE != fix ]]; then
	echo
	note "Bağlanmamış girdiler için: sudo $0 --fix"
	exit 0
fi

require_root

section "Bağlama denemesi"
for row in "${FSTAB_ROWS[@]}"; do
	src=${row%%$'\t'*}
	rest=${row#*$'\t'}
	target=${rest%%$'\t'*}
	fstype=${rest#*$'\t'}

	is_virtual "$src" && continue
	[[ $target == none || $fstype == swap ]] && continue

	resolved=$(resolve_source "$src")
	[[ -z $resolved ]] && continue
	resolved_base=${resolved%%\[*}
	target_mounted "$target" "$resolved_base" && continue

	if ((ALL_FIX)) || ask_yes "$target bağlansın mı? ($src)"; then
		if mkdir -p -- "$target" && mount -- "$target"; then
			log "Bağlandı: $target"
		else
			warn "Bağlanamadı: $target"
		fi
	fi
done

log "Mount denetimi tamam."
