#!/bin/bash

# =================================================================
# Project: arch-kam (The Shamanic System Healer)
# Ritual: Linux Hibernate Enabler (Anti-Kamos Protocol)
# Description: Automated Swap & Hibernate configuration for Arch-based systems
# Supports: BTRFS and EXT4 file systems
# =================================================================

# Renk Tanımlamaları
SET_GREEN='\033[0;32m'
SET_RED='\033[0;31m'
SET_YELLOW='\033[1;33m'
SET_NC='\033[0m'

# Hata anında ritüeli durdur
set -e

log() { echo -e "${SET_GREEN}[INFO] $1${SET_NC}"; }
warn() { echo -e "${SET_YELLOW}[WARN] $1${SET_NC}"; }
error() {
    echo -e "${SET_RED}[ERROR] $1${SET_NC}"
    echo -e "${SET_RED}"
    cat << "EOF"
          .      .
       .   \    /   .
        \   \  /   /
         \  _)(_  /
         / /    \ \
        / | @  @ | \    [ KAMOS HAS POSSESSED THE SYSTEM ]
        | \  --  / |
        /_/------\_\
           \____/
EOF
    echo -e "${SET_NC}"
    exit 1
}

# Root Şaman Kontrolü
if [[ $EUID -ne 0 ]]; then
   error "Only a Root Shaman (sudo) can banish the shadows."
fi

echo -e "${SET_YELLOW}"
cat << "EOF"
       Scanning for Kamos (The Karabasan of Configs)...
               .      .
            .   \    /   .
             \   \  /   /
              \  _)(_  /
              / /    \ \
             / | ^  ^ | \
             | | @  @ | |
             | \  --  / |
             /_/------\_\
EOF
echo -e "${SET_NC}"

log "Kamos detected in the kernel parameters. Initiating Arch-Kam ritual..."

# Dosya Sistemi Tespiti
FS_TYPE=$(stat -f -c %T /)
log "Root filesystem detected: $FS_TYPE"

# Hedef Swap Boyutu Hesaplama (RAM + 2GB)
RAM_SIZE=$(free -m | grep -i mem | awk '{print $2}')
TARGET_SWAP=$((RAM_SIZE + 2048))
log "Target swap size for safe slumber: ${TARGET_SWAP}MB"

# Mevcut Swap'ı Kapat ve Yedekle
warn "Disabling current swap and creating sacred backups..."
swapoff -a 2>/dev/null || true
[ -f /etc/default/grub ] && cp /etc/default/grub /etc/default/grub.bak
[ -f /etc/mkinitcpio.conf ] && cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak

# Swap Dosyası Oluşturma Ritüeli
if [[ "$FS_TYPE" == "btrfs" ]]; then
    log "BTRFS detected. Applying specific shamanic protocols..."
    truncate -s 0 /swapfile
    chattr +C /swapfile
    btrfs property set /swapfile compression none
    fallocate -l "${TARGET_SWAP}M" /swapfile
else
    log "Standard filesystem detected. Using dd for swap creation..."
    dd if=/dev/zero of=/swapfile bs=1M count=$TARGET_SWAP status=progress
fi

chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile || error "Failed to activate the swap spirit!"

# UUID ve Offset Hesaplama
SWAP_UUID=$(findmnt -no UUID -T /swapfile)
if [[ "$FS_TYPE" == "btrfs" ]]; then
    if command -v btrfs-inspect-internal &> /dev/null; then
        NEW_OFFSET=$(btrfs inspect-internal map-swapfile -r /swapfile)
    else
        warn "btrfs-progs not found. Falling back to filefrag rituals..."
        NEW_OFFSET=$(filefrag -v /swapfile | awk '{if($1=="0:"){print $4}}' | sed 's/\..//')
    fi
else
    NEW_OFFSET=$(filefrag -v /swapfile | awk '{if($1=="0:"){print $4}}' | sed 's/\..//')
fi

log "Calculated Sacred UUID: $SWAP_UUID"
log "Calculated Sacred Offset: $NEW_OFFSET"

# GRUB Güncelleme (Eski parametreleri temizle ve yenilerini yaz)
log "Updating the sacred scrolls (/etc/default/grub)..."
sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT=".*\)resume=[^ "]*\(.*\)"/\1\2"/' /etc/default/grub
sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT=".*\)resume_offset=[^ "]*\(.*\)"/\1\2"/' /etc/default/grub
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"resume=UUID=$SWAP_UUID resume_offset=$NEW_OFFSET /" /etc/default/grub

# Initcpio Hook Güncelleme
log "Updating /etc/mkinitcpio.conf hooks..."
if ! grep -q "resume" /etc/mkinitcpio.conf; then
    sed -i '/^HOOKS=/s/)/ resume)/' /etc/mkinitcpio.conf
fi

# Kernel Parametrelerini Uygula
log "Regenerating GRUB and Initcpio. The spirits are awakening..."
update-grub || error "GRUB update failed! Kamos is resisting."
mkinitcpio -P || error "Initcpio generation failed! The ritual is broken."

# --- THE SACRED MASTERPIECE BANNER ---
echo -e "${SET_GREEN}"
cat << "EOF"
$$$$$$$$$$$$$$$$""$o$o$o$o$o$oo$$""$$$$$$$$$$$$$$$
$$$$$$$$$$$$""o$$$$$$$$$$"$"$$$$$$$o$"$$$$$$$$$$$$
$$$$$$$$$"$o$$$$""$oo $ ""      """$$$oo"$$$$$$$$$
$$$$$$$"o  $$$ $$                        $$$$$$$$$
$$$$$$$$$$o""$$$$$$$$$$$$$$$$$$$$$$$$$"oo$$$$$$$$$
$$$$$$$$$$$$$o$""$$$$$$$$$$$$$$$$$""oo$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$o$o$"$"$"$"$oo$o$$$$$$$$$$$$$$$$
       [ THE ARCH-KAM HAS SEALED THE RITUAL ]
EOF
echo -e "--------------------------------------------------------"
echo "  THE RITUAL OF ARCH-KAM IS COMPLETE"
echo "  The spirits of the kernel have been appeased."
echo "  Kamos has been exorcised from your system."
echo "  The balance of your slumber is now restored."
echo "--------------------------------------------------------"
echo -e "${SET_NC}"

log "Sacred configuration sealed with .bak protection."
warn "Kowtow to the Machine Spirit: REBOOT your system now."
warn "After awakening, test the slumber with: systemctl hibernate"
