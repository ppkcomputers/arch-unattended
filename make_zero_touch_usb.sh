#!/usr/bin/env bash
set -euo pipefail

# --- COLORS FOR TERMINAL OUTPUT ---
RED='\033[0;31m'
NC='\033[0m' # No Color / Reset

# Confirm root privilege availability
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Error: This setup wrapper requires sudo authorization.${NC}" >&2
    exit 1
fi

# Ensure grub is installed on the host system to build the USB bootloader
if ! command -v grub-install &> /dev/null; then
    echo "⚙️ Installing grub package for legacy MBR compilation..."
    sudo pacman -S --needed --noconfirm grub
fi

echo "=========================================================="
echo "    ARCH AUTOPILOT - GRUB2 LEGACY PLUG CREATOR            "
echo "=========================================================="

# 1. Smart Hardware Detection (Find Main Internal Drive)
echo "🔍 Analyzing system hardware..."
INTERNAL_DRIVE=""

if [ -b "/dev/nvme0n1" ]; then
    INTERNAL_DRIVE="nvme0n1"
elif [ -b "/dev/sda" ]; then
    INTERNAL_DRIVE="sda"
else
    INTERNAL_DRIVE=$(lsblk -dno NAME,TYPE | grep -E "disk" | awk '{print $1}' | head -n 1)
fi

if [ -z "$INTERNAL_DRIVE" ]; then
    echo -e "${RED}❌ Error: Could not automatically detect an internal hard drive.${NC}" >&2
    exit 1
fi

echo "🎯 Targeted Internal Drive for Arch Installation: /dev/$INTERNAL_DRIVE"
echo -e "${RED}⚠️  WARNING: When you reboot, /dev/$INTERNAL_DRIVE will be COMPLETELY WIPED!${NC}"
echo "=========================================================="
echo ""

# 2. Gather User Account Information
read -s -p "🔑 Enter desired ROOT password: " ROOT_PASSWORD </dev/tty
echo ""
read -p "👤 Enter your new username: " USER_NAME </dev/tty
read -s -p "🔑 Enter password for $USER_NAME: " USER_PASSWORD </dev/tty
echo ""

# 3. Select Desktop Profile
echo "📺 Select your preferred Desktop Profile:"
echo "1) Cinnamon"
echo "2) GNOME"
echo "3) Hyprland"
echo "4) KDE Plasma"
read -p "Choose an option (1-4): " DESKTOP_CHOICE </dev/tty

case "$DESKTOP_CHOICE" in
    1) PROFILE="cinnamon" ;;
    2) PROFILE="gnome" ;;
    3) PROFILE="hyprland" ;;
    4) PROFILE="kde" ;;
    *) echo "❌ Invalid selection. Defaulting to GNOME."; PROFILE="gnome" ;;
esac

# 4. Automatically detect system timezone and map mirror region
echo -e "\n🌐 Detecting local system timezone..."
TIMEZONE=$(timedatectl show --property=Timezone --value || echo "UTC")
echo "📍 Detected Timezone: $TIMEZONE"

ZONE_PREFIX=$(echo "$TIMEZONE" | cut -d'/' -f1)
case "$ZONE_PREFIX" in
    "Africa") REGION="South Africa" ;;
    "America") REGION="United States" ;;
    "Europe") REGION="Germany" ;;
    "Asia") REGION="Japan" ;;
    "Australia") REGION="Australia" ;;
    *) REGION="Worldwide" ;;
esac

# 5. Show ONLY removable USB drives
echo -e "\n=========================================================="
echo "🔌 AVAILABLE USB FLASH DRIVES DETECTED:"
echo "----------------------------------------------------------"
lsblk -dno NAME,SIZE,RM,TYPE | grep -E "1 disk" | awk '{print " 👉 Drive Letter: " $1 " (Size: " $2 ")"}' || echo "⚠️  No USB flash drives detected!"
echo "=========================================================="
echo ""
read -p "Type your USB drive letter here (e.g., sdb): " TARGET_DEV </dev/tty
TARGET="/dev/$TARGET_DEV"

if [ "$TARGET_DEV" == "$INTERNAL_DRIVE" ]; then
    echo -e "${RED}❌ CRITICAL ERROR: You cannot use your main internal drive as the installation USB!${NC}" >&2
    exit 1
fi

if [ ! -b "$TARGET" ]; then
    echo -e "${RED}❌ Error: Target /dev/$TARGET_DEV could not be resolved.${NC}" >&2
    exit 1
fi

# 6. Partition and Format the USB using standard MBR layouts
echo "🧹 Wiping and structuring partition tables..."
umount "${TARGET}"* 2>/dev/null || true

# Completely clear existing master boot records
dd if=/dev/zero of="$TARGET" bs=512 count=40 conv=notrunc

# Form a clean MSDOS partition record table
parted -s "$TARGET" mklabel msdos
parted -s "$TARGET" mkpart primary fat32 1MiB 100%
parted -s "$TARGET" set 1 boot on

if [[ "$TARGET_DEV" == *"nvme"* || "$TARGET_DEV" == *"mmcblk"* ]]; then
    PARTITION="${TARGET}p1"
else
    PARTITION="${TARGET}1"
fi

sleep 1
mkfs.vfat -F 32 -n "ARCH_LAUNCH" "$PARTITION"

# 7. Mount partition environment to configure GRUB2 and configurations
MOUNT_DIR=$(mktemp -d)
mount "$PARTITION" "$MOUNT_DIR"
trap 'umount "$MOUNT_DIR" 2>/dev/null && rmdir "$MOUNT_DIR" 2>/dev/null' EXIT

# Install GRUB2 directly onto the USB Drive for i386-pc target (Legacy BIOS)
echo "💾 Writing GRUB2 master boot record to physical drive..."
grub-install --target=i386-pc --boot-directory="$MOUNT_DIR/boot" "$TARGET"

# Determine terminal package to launch post-install script
LAUNCH_TERM="kitty"
if [[ "$PROFILE" == "kde" ]]; then
    LAUNCH_TERM="konsole"
fi

# 8. Generate the Custom user_configuration.json dynamically onto the USB
cat <<EOF > "$MOUNT_DIR/user_configuration.json"
{
    "audio": "pipewire",
    "bootloader": "grub",
    "desktop-environment": "$PROFILE",
    "gfx_driver": "All open-source",
    "hostname": "arch-station",
    "kernels": ["linux"],
    "language": "en_US",
    "keyboard-layout": "us",
    "mirror-region": "$REGION",
    "network_config": "Copy ISO network configuration",
    "root-password": "$ROOT_PASSWORD",
    "users": [
        {
            "username": "$USER_NAME",
            "password": "$USER_PASSWORD",
            "sudo": true
        }
    ],
    "packages": ["$LAUNCH_TERM"],
    "parallel_downloads": 5,
    "storage": {
        "disk_layouts": [
            {
                "device": "/dev/$INTERNAL_DRIVE",
                "wipe": true,
                "partitions": [
                    {
                        "boot": true,
                        "size": "512MiB",
                        "mountpoint": "/boot",
                        "filesystem": "vfat"
                    },
                    {
                        "size": "100%",
                        "mountpoint": "/",
                        "filesystem": "btrfs"
                    }
                ]
            }
        ]
    },
    "timezone": "$TIMEZONE",
    "version": "5.0.0",
    "custom-commands": [
        "mkdir -p /mnt/home/$USER_NAME/.config/autostart",
        "echo -e '[Desktop Entry]\\\\nType=Application\\\\nName=PostInstallMenu\\\\nExec=$LAUNCH_TERM -e bash -c \"curl -sSL https://raw.githubusercontent.com/ppkcomputers/arch-unattended/main/new-install.sh | bash; rm -- \\\\\\\"\\\\\\$0\\\\\\\"\"\\\\nX-GNOME-Autostart-enabled=true' > /mnt/home/$USER_NAME/.config/autostart/postinstall.desktop",
        "chown -R 1000:1000 /mnt/home/$USER_NAME/.config"
    ]
}
EOF

# 9. Configure the GRUB2 boot entry menu layout
mkdir -p "$MOUNT_DIR/boot/grub"
cat <<EOF > "$MOUNT_DIR/boot/grub/grub.cfg"
set default=0
set timeout=2

menuentry "Arch Linux Unattended Installation (netboot.xyz)" {
    insmod part_msdos
    insmod fat
    set root='hd0,msdos1'
    linux16 /netboot.xyz.lkrn
}
EOF

# Fetch the raw core binary image directly onto the USB
echo "🌐 Downloading real-mode core binary..."
curl -L -o "$MOUNT_DIR/netboot.xyz.lkrn" "https://boot.netboot.xyz/ipxe/netboot.xyz.lkrn"

# Mirror local configuration chain mapping
cat <<EOF > "$MOUNT_DIR/autoexec.ipxe"
#!ipxe
chain https://raw.githubusercontent.com/ppkcomputers/arch-unattended/main/script.ipxe
EOF

echo ""
echo "=========================================================="
echo "✅ ARCH AUTOPILOT COMPLETED: GRUB2 Boot Key Armed!"
echo "=========================================================="
echo -e "${RED}\n🔄 PLEASE REBOOT THE G550 NOW.${NC}"
echo "1. Turn on the machine and immediately smash the 'F12' key."
echo "2. Select 'USB HDD' (or your USB flash drive manufacturer name) from the list."
echo "=========================================================="
