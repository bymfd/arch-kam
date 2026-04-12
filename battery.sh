#!/bin/bash

# Colors (Sky Blue, Nature Green, and Fire Red)
SKY='\033[0;36m'
LEAF='\033[0;32m'
FIRE='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${SKY}=======================================${NC}"
echo -e "${SKY}      ARKUN: Battery Guardian          ${NC}"
echo -e "${SKY}   (Shamanic Power Management)         ${NC}"
echo -e "${SKY}=======================================${NC}"
echo -e "1) ${LEAF}Grant Kut (Install TLP - Save Energy)${NC}"
echo -e "2) ${FIRE}Recall Kut (Remove TLP - Max Speed)${NC}"
echo -e "3) Depart (Exit)"
echo -e "${SKY}=======================================${NC}"

read -p "Make your choice, traveler [1-3]: " choice

case $choice in
    1)
        echo -e "\n${LEAF}>> Arkun is harnessing the energy (Installing TLP)...${NC}"
        sudo pacman -S --noconfirm tlp
        sudo systemctl enable tlp.service
        echo -e "${LEAF}>> Kut granted. May your battery life be long!${NC}"
        ;;
    2)
        echo -e "\n${FIRE}>> Arkun is releasing the constraints (Removing TLP)...${NC}"
        sudo systemctl disable --now tlp.service
        sudo pacman -Rs --noconfirm tlp
        echo -e "${FIRE}>> Constraints lifted. The system runs wild again.${NC}"
        ;;
    3)
        echo "Spirit of the machine remains... Farewell."
        exit 0
        ;;
    *)
        echo -e "${FIRE}Do not lose your way! Please choose 1, 2, or 3.${NC}"
        ;;
esac
