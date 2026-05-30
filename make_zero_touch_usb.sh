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

# Ensure grub is installed on the host to use compilation binaries
if ! command -v grub-mkstandalone &> /dev/null; then
    echo "⚙️ Installing missing grub dependencies for standalone compilation..."
    sudo pacman -S --needed --noconfirm grub dosfstools mtools
fi

echo "=========================================================="
echo "    ARCH AUTOPILOT - COMPLED ONE-CLICK USB ARMER           "
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
echo -e "\n📺 Select your preferred Desktop Profile:"
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
echo "🪞 Automatically matching mirror region: $REGION"

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

# 6. Build the USB Partition Structure (Strict EFI Alignment)
echo "🧹 Re-initializing storage structures..."
umount "${TARGET}"* 2>/dev/null || true
dd if=/dev/zero of="$TARGET" bs=512 count=40 conv=notrunc

parted -s "$TARGET" mklabel gpt
parted -s "$TARGET" mkpart primary fat32 2048s 100%
parted -s "$TARGET" set 1 esp on

if [[ "$TARGET_DEV" == *"nvme"* || "$TARGET_DEV" == *"mmcblk"* ]]; then
    PARTITION="${TARGET}p1"
else
    PARTITION="${TARGET}1"
fi

sleep 2
mkfs.vfat -F 32 -n "ARCH_LAUNCH" "$PARTITION"

# 7. Mount USB Environment
MOUNT_DIR=$(mktemp -d)
mount "$PARTITION" "$MOUNT_DIR"
trap 'umount "$MOUNT_DIR" 2>/dev/null && rmdir "$MOUNT_DIR" 2>/dev/null' EXIT

mkdir -p "$MOUNT_DIR/EFI/BOOT"

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

# 9. Dynamically Compile a Standalone GRUB Bootloader Image straight to the USB
echo "📦 Compiling native hardware boot application wrapper..."

# Create a temporary internal configuration directory for compilation injection
TMP_BUILD=$(mktemp -d)
mkdir -p "$TMP_BUILD/boot/grub"

# Write embedded boot directives telling GRUB exactly how to load netboot elements
cat <<EOF > "$TMP_BUILD/boot/grub/grub.cfg"
insmod efi_gop
insmod efi_uga
insmod font
insmod gfxterm

set timeout=0
set default=0

menuentry "Arch Autopilot Live Setup" {
    echo "🌐 Initializing Autopilot Live Environment..."
    loopback loop /netboot.xyz.lkrn
    linux16 /netboot.xyz.lkrn
}
EOF

# Fetch the network bootstrap binary right into our compilation payload loop
curl -sL -o "$TMP_BUILD/netboot.xyz.lkrn" "https://boot.netboot.xyz/ipxe/netboot.xyz.lkrn"
cp "$TMP_BUILD/netboot.xyz.lkrn" "$MOUNT_DIR/netboot.xyz.lkrn"

# Bake everything into an official native BOOTX64.EFI module (with verified module names)
grub-mkstandalone \
    -O x86_64-efi \
    -o "$MOUNT_DIR/EFI/BOOT/BOOTX64.EFI" \
    --modules="part_gpt fat test normal efi_gop efi_uga gfxterm loopback boot linux" \
    "boot/grub/grub.cfg=$TMP_BUILD/boot/grub/grub.cfg"

rm -rf "$TMP_BUILD"

# Drop network routing fallback map
cat <<EOF > "$MOUNT_DIR/autoexec.ipxe"
#!ipxe
chain https://raw.githubusercontent.com/ppkcomputers/arch-unattended/main/script.ipxe
EOF

echo ""
echo "=========================================================="
echo "✅ SUCCESS: Zero-touch installation USB armed!"
echo "=========================================================="
echo "🎯 Automated Configuration Profile Built:"
echo " - Installation Target Hard Drive: /dev/$INTERNAL_DRIVE"
echo " - Desktop Deployment Target: $PROFILE"
echo " - Local Mirror Core: $REGION"
echo "=========================================================="
echo -e "${RED}\n🔄 ALL STEPS COMPLETE. REBOOT YOUR MACHINE NOW TO RUN THE UNATTENDED SETUP!${NC}"
echo "=========================================================="
