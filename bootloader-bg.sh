#!/bin/bash

# Renkler
SKY='\033[0;36m'
LEAF='\033[0;32m'
FIRE='\033[0;31m'
NC='\033[0m'

echo -e "${SKY}=======================================${NC}"
echo -e "${SKY}        TIN: The Vision Ritual         ${NC}"
echo -e "${SKY}     (GRUB & Bootloader Manager)       ${NC}"
echo -e "${SKY}=======================================${NC}"

# 1. Bootloader Kontrolü
if [ ! -d "/boot/grub" ]; then
    echo -e "${FIRE}>> Error: GRUB not found. This ritual is for GRUB only.${NC}"
    exit 1
fi

GRUB_FILE="/etc/default/grub"
BACKUP_FILE="/etc/default/grub.bak"

# 2. Yedekleme
if [ ! -f "$BACKUP_FILE" ]; then
    sudo cp "$GRUB_FILE" "$BACKUP_FILE"
    echo -e "${LEAF}>> Sacred backup created.${NC}"
fi

echo -e "1) ${LEAF}Vision:${NC} Set custom image (PNG/JPG)"
echo -e "2) ${FIRE}Void:${NC} Set pure black (Terminal Mode)"
echo -e "3) ${SKY}Restore:${NC} Back to default scrolls"
echo -e "4) Exit"
echo -e "${SKY}=======================================${NC}"

read -p "Choose your path [1-4]: " choice

case $choice in
    1)
        # Görsel Seçici
        read -p "Enter the full path to your image: " img_path
        if [ -f "$img_path" ]; then
            sudo cp "$img_path" /boot/grub/tin_bg.png
            # Temayı ve terminal modunu kapat, görseli aç
            sudo sed -i 's/^GRUB_THEME=/#GRUB_THEME=/' "$GRUB_FILE"
            sudo sed -i 's/^GRUB_TERMINAL_OUTPUT=/#GRUB_TERMINAL_OUTPUT=/' "$GRUB_FILE"
            sudo sed -i '/^GRUB_BACKGROUND=/d' "$GRUB_FILE"
            echo 'GRUB_BACKGROUND="/boot/grub/tin_bg.png"' | sudo tee -a "$GRUB_FILE"
            echo -e "${LEAF}>> Vision set. The image is now your guide.${NC}"
        else
            echo -e "${FIRE}>> Image not found!${NC}"
            exit 1
        fi
        ;;
    2)
        # Saf Siyah (Void)
        sudo sed -i 's/^GRUB_THEME=/#GRUB_THEME=/' "$GRUB_FILE"
        sudo sed -i 's/^GRUB_BACKGROUND=/#GRUB_BACKGROUND=/' "$GRUB_FILE"
        # Terminal modunu zorla (Saf siyah için kritik)
        if grep -q "^GRUB_TERMINAL_OUTPUT=" "$GRUB_FILE"; then
            sudo sed -i 's/^GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT="console"/' "$GRUB_FILE"
        else
            echo 'GRUB_TERMINAL_OUTPUT="console"' | sudo tee -a "$GRUB_FILE"
        fi
        echo -e "${FIRE}>> Void set. Only darkness remains.${NC}"
        ;;
    3)
        sudo cp "$BACKUP_FILE" "$GRUB_FILE"
        echo -e "${LEAF}>> Default settings restored.${NC}"
        ;;
    4) exit 0 ;;
    *) echo -e "${FIRE}Invalid choice!${NC}"; exit 1 ;;
esac

# 3. Mühürleme
echo -e "\n${SKY}>> Sealing the ritual (Updating GRUB config)...${NC}"
sudo grub-mkconfig -o /boot/grub/grub.cfg
echo -e "${LEAF}>> Done! Restart to witness the change.${NC}"
