# arch-kam

A sacred collection of digital shamanic rituals and orchestration scripts for Arch-based Linux distributions. This repository acts as your system's *Kam*, healing broken states, exorcising bugs, and restoring the cosmic balance of your configurations.

---

**`arch-kam`** translates this ancient wisdom into bash scripts. If your Linux is possessed by evil configuration demons or has lost its spiritual connection to the swap file, this repository is your digital guide.

## Available Rituals (Scripts)

### 1. `hibernate-enabler.sh` (The Slumber Ritual)
A powerful ritual to guide your system into a deep, protected slumber (hibernating to a swap file) and ensure a safe spiritual journey back (resume).

- **Supports:** BTRFS (with CoW disabling) and EXT4 filesystems.
- **Action:** Calculates optimal swap space (RAM + 2GB safety), creates the swap file with the correct permissions, calculates the sacred UUID and Offset, and updates GRUB and Initcpio hooks.
- **Safety:** Performs a digital backup (`.bak`) of your sacred scrolls (`/etc/default/grub` and `/etc/mkinitcpio.conf`) before modification.

---

### 2. **ARKUN: The Spirit of Endurance** (battery.sh)
A sacred discipline to harmonize the machine's breath, calming its inner fire to preserve life force (**Battery Life**) during long journeys.

* **The Rite:** Invokes **TLP** protocols to manage energy flow, ensuring the system sips power with wisdom.
* **The Duality:** Allows the traveler to **Grant Kut** (Install) for longevity or **Recall Kut** (Remove) for untamed performance.
* **Thermal Balance:** Lowers the system's temperature by curbing excess energy, keeping the hardware cool and composed.
* **Swift Restoration:** A single command purifies the system, removing the ritual and returning the machine to its primal state.
---

### 3. **TIN:** Vision & Void (bootloader-bg.sh)

A ritual to define the system's entry point and visual essence.

*   The Vision: Allows the user to etch a custom image (PNG/JPG) onto the GRUB gateway.

*    The Void: Strips away all earthly illusions (themes/backgrounds) to achieve a Pure Black terminal interface.

*    Safety: Automatically creates sacred backups (.bak) of your scrolls before any modification.

*   Intelligence: Detects whether your system is guided by the ancient GRUB or the swift systemd-boot.

---
## Performing the Rituals

### Prerequisites
- You must be a Root Shaman (have `sudo` privileges).
- A functional brain (optional but recommended).

### Usage

1. **Summon the Repository:**
   ```bash
   git clone [https://github.com/yourusername/arch-kam.git](https://github.com/yourusername/arch-kam.git)
   cd arch-kam
   chmod +x *.sh
    
   sudo ./*.sh
   
   ```
   
## The Shamanic Tradition (Etymology)
In ancient Turkic spirituality, a **Kam** is a shaman, healer, and spiritual guide. They perform rituals to connect the upper and lower worlds, cure ailments, and ensure the community's well-being.
