#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
	cat <<EOF
Kullanım: $0 [--list] [--kernel] [--sysctl] [--services] [--listening]

Veil of the Depths: salt okunur güvenlik denetimi.
Kernel hardening parametreleri, sysctl ayarları, açık portlar,
gereksiz çalışan servisler, imza ve boot durumu.

  --list       Tüm denetimleri çalıştır (varsayılan)
  --kernel     Yalnızca kernel parametreleri
  --sysctl     Yalnızca sysctl güvenlik ayarları
  --services   Yalnızca servis ve port denetimi
  --listening  Yalnızca açık portlar
  -h, --help   Bu yardım
EOF
}

MODE='list'

while [[ $# -gt 0 ]]; do
	case $1 in
		--list) MODE=list; shift ;;
		--kernel) MODE=kernel; shift ;;
		--sysctl) MODE=sysctl; shift ;;
		--services) MODE=services; shift ;;
		--listening) MODE=listening; shift ;;
		-h | --help) usage; exit 0 ;;
		*) die "Bilinmeyen argüman: $1" ;;
	esac
done

ISSUES=0

kernel_check() {
	section "Kernel parametreleri"
	cmdline=$(cat /proc/cmdline 2>/dev/null || true)

	if [[ $cmdline =~ slab_nomerge ]]; then
		ok "slab_nomerge (kernel heap isolation)"
	else
		warn "slab_nomerge yok;Spectre/Meltdown mitigations'ı zayıflatabilir."
	fi

	if [[ $cmdline =~ mds=full ]]; then
		ok "mds=full (MDS azaltması)"
	else
		note "mds=full yok (CPU mitigations'ı için kontrol edilebilir)."
	fi

	if [[ $cmdline =~ page_poison=1 ]]; then
		ok "page_poison=1"
	fi

	if [[ $cmdline =~ init_on_alloc=1 ]]; then
		ok "init_on_alloc=1 (bellek sıfırlama)"
	else
		warn "init_on_alloc=1 yok; ayrıcalıklı bellek sızıntısı riski artar."
	fi

	if [[ $cmdline =~ init_on_free=1 ]]; then
		ok "init_on_free=1"
	else
		warn "init_on_free=1 yok."
	fi

	if [[ $cmdline =~ randomize_kstack_offset=on ]]; then
		ok "randomize_kstack_offset=on"
	fi

	if [[ $cmdline =~ lockdown=confidentiality ]]; then
		ok "lockdown=confidentiality"
	elif [[ $cmdline =~ lockdown=integrity ]]; then
		note "lockdown=integrity (confidentiality daha sıkı)"
	else
		note "lockdown yok (UEFI Secure Boot ile etkinleştirilebilir)"
	fi

	if [[ $cmdline =~ oops=panic ]]; then
		ok "oops=panic"
	fi

	if [[ $cmdline =~ bpf_jit_harden=2 ]]; then
		ok "bpf_jit_harden=2"
	else
		note "bpf_jit_harden=2 yok"
	fi

	if have mokutil; then
		sb=$(mokutil --sb-state 2>/dev/null || true)
		[[ $sb == *"SecureBoot enabled"* ]] && ok "Secure Boot etkin" || warn "Secure Boot etkin değil: ${sb:-bilinmiyor}"
	fi
}

sysctl_check() {
	section "Sysctl güvenlik ayarları"

	check_sysctl() {
		local key=$1 expected=$2 desc=$3
		local val
		val=$(sysctl -n "$key" 2>/dev/null || true)
		if [[ -z $val ]]; then
			note "$key okunamadı"
		elif [[ $val == "$expected" ]]; then
			ok "$key = $val ($desc)"
		else
			warn "$key = $val (önerilen: $expected) — $desc"
			((ISSUES += 1))
		fi
	}

	check_sysctl kernel.unprivileged_bpf_disabled 2 "bpf kısıtlı"
	check_sysctl kernel.kptr_restrict 2 "çekirdek adresi gizleme"
	check_sysctl kernel.dmesg_restrict 1 "dmesg kısıtlı"
	check_sysctl kernel.yama.ptrace_scope 2 "ptrace kısıtlı"
	check_sysctl kernel.sysrq 0 "SysRQ kapalı"
	check_sysctl net.ipv4.conf.all.rp_filter 1 "rp_filter (yanlış paket engelleme)"
	check_sysctl net.ipv4.conf.default.rp_filter 1 "rp_filter default"
	check_sysctl net.ipv4.conf.all.accept_redirects 0 "ICMP redirect reddi"
	check_sysctl net.ipv4.conf.all.secure_redirects 0 "secure redirect reddi"
	check_sysctl net.ipv4.conf.all.log_martians 1 "martian paket log"
	check_sysctl net.ipv4.icmp_echo_ignore_broadcasts 1 "ICMP broadcast yoksay"
	check_sysctl net.ipv6.conf.all.accept_ra_defrtr 0 "IPv6 RA reddi"
	check_sysctl net.ipv6.conf.all.accept_ra_pinfo 0 "IPv6 RA prefix reddi"
	check_sysctl fs.protected_hardlinks 1 "hardlink koruması"
	check_sysctl fs.protected_symlinks 1 "symlink koruması"
	check_sysctl fs.suid_dumpable 0 "SUID core dump kapalı"
}

services_check() {
	section "Servisler ve portlar"

	# Açık portlar
	if have ss; then
		note "Dinlenen TCP portları:"
		ss -tulnp 2>/dev/null | sed 's/^/    /' || note "ss çıktısı okunamadı."
	elif have netstat; then
		netstat -tulnp 2>/dev/null | sed 's/^/    /' || note "netstat çıktısı okunamadı."
	else
		note "ss veya netstat yok; port listesi çıkarılamadı."
	fi

	# Firewall durumu
	if have firewall-cmd; then
		state=$(firewall-cmd --state 2>/dev/null || true)
		[[ $state == running ]] && ok "firewalld çalışıyor" || warn "firewalld çalışmıyor"
	elif have ufw; then
		state=$(ufw status 2>/dev/null | head -n1 || true)
		[[ $state == *"active"* ]] && ok "ufw etkin" || warn "ufw etkin değil: ${state:-bilinmiyor}"
	elif have nft; then
		if nft list ruleset 2>/dev/null | grep -q .; then
			ok "nftables kuralları var"
		else
			warn "nftables kuralları boş veya okunamadı."
		fi
	else
		warn "Tanınan güvenlik duvarı yok (firewalld/ufw/nftables)."
	fi

	# SSH root girişi
	if [[ -f /etc/ssh/sshd_config ]]; then
		root_login=$(grep -iE '^\s*PermitRootLogin' /etc/ssh/sshd_config | tail -n1 | awk '{print $2}' || true)
		if [[ $root_login == no ]]; then
			ok "SSH PermitRootLogin no"
		elif [[ -n $root_login ]]; then
			warn "SSH PermitRootLogin = $root_login"
		else
			note "SSH PermitRootLogin belirtilmemiş (varsayılan genelde prohibit-password)"
		fi
	fi

	# Fail2ban
	if systemctl is-active --quiet fail2ban 2>/dev/null; then
		ok "fail2ban çalışıyor"
	else
		note "fail2ban çalışmıyor"
	fi
}

run_mode() {
	case $MODE in
		list)
			kernel_check
			sysctl_check
			services_check
			;;
		kernel) kernel_check ;;
		sysctl) sysctl_check ;;
		services | listening) services_check ;;
	esac
}

run_mode

echo
if ((ISSUES > 0)); then
	warn "Güvenlik denetimi tamam: $ISSUES öneri bulundu."
else
	log "Güvenlik denetimi tamam: kritik öneri yok."
fi
exit 0
