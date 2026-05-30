#!/usr/bin/env bash
set -euo pipefail

# Confirm root privilege availability
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: This setup wrapper requires sudo authorization." >&2
    exit 1
fi

echo "=========================================================="
echo "    ARCH AUTOPILOT - USER CONFIGURATION CREATOR           "
echo "=========================================================="

# 1. Smart Hardware Detection (Find Main Internal Drive)
echo "🔍 Analyzing system hardware..."
INTERNAL_DRIVE=""

# Check if an NVMe drive exists and is likely the main OS drive
if [ -b "/dev/nvme0n1" ]; then
    INTERNAL_DRIVE="nvme0n1"
# Fallback to standard sda if it exists
elif [ -b "/dev/sda" ]; then
    INTERNAL_DRIVE="sda"
else
    # Ultimate fallback: Find the first non-removable disk that isn't a loop device
    INTERNAL_DRIVE=$(lsblk -dno NAME,TYPE | grep -E "disk" | awk '{print $1}' | head -n 1)
fi

if [ -z "$INTERNAL_DRIVE" ]; then
    echo "❌ Error: Could not automatically detect an internal hard drive." >&2
    exit 1
fi

echo "🎯 Targeted Internal Drive for Arch Installation: /dev/$INTERNAL_DRIVE"
echo "⚠️  NOTE: When you reboot, /dev/$INTERNAL_DRIVE will be COMPLETELY WIPED."
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

# 4. Automatically detect system timezone
echo -e "\n🌐 Detecting local system timezone..."
TIMEZONE=$(timedatectl show --property=Timezone --value || echo "UTC")
echo "📍 Detected Timezone: $TIMEZONE"

# 5. Show drives and get target USB
echo -e "\n=== SYSTEM TARGET DISK LIST ==="
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS | grep -E "disk|part"
echo "==============================="
read -p "Enter the USB drive identifier to format (e.g., sdb, sdc): " TARGET_DEV </dev/tty
TARGET="/dev/$TARGET_DEV"

# Safety sanity check: Make sure they didn't pick the internal installation drive as the USB!
if [ "$TARGET_DEV" == "$INTERNAL_DRIVE" ]; then
    echo "❌ CRITICAL ERROR: You cannot use your main internal drive (/dev/$INTERNAL_DRIVE) as the installation USB!" >&2
    exit 1
fi

if [ ! -b "$TARGET" ]; then
    echo "❌ Error: Target /dev/$TARGET_DEV could not be resolved." >&2
    exit 1
fi

# 6. Partition and Format the USB
echo "🧹 Clearing device mounts and storage structures..."
umount "${TARGET}"* 2>/dev/null || true
parted -s "$TARGET" mklabel msdos
parted -s "$TARGET" mkpart primary fat32 1MiB 100%
parted -s "$TARGET" set 1 boot on

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

# Determine terminal package to launch post-install script based on desktop choice
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
    "mirror-region": "United States",
    "network_config": "Copy ISO network configuration",
    "root-password": "$ROOT_PASSWORD",
    "users": [
        {
            "username": "$USER_NAME",
            "password": "$USER_PASSWORD",
            "sudo": true
        }
    ],
    "packages": ["firefox", "git", "fastfetch", "$LAUNCH_TERM"],
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
        "echo -e '[Desktop Entry]\\\\nType=Application\\\\nName=PostInstallMenu\\\\nExec=$LAUNCH_TERM -e bash -c \"curl -sSL https://raw.githubusercontent.com/ppkcomputers/arch-unattended/main/new-install.sh | bash; rm -- \\\\\\\"\\\\\\$0\\?\\\"\"\\\\nX-GNOME-Autostart-enabled=true' > /mnt/home/$USER_NAME/.config/autostart/postinstall.desktop",
        "chown -R 1000:1000 /mnt/home/$USER_NAME/.config"
    ]
}
EOF

# 9. Setup Bootloader files on the USB
echo "🌐 Syncing network bootstrap architecture onto hardware..."
curl -L -o "$MOUNT_DIR/EFI/BOOT/BOOTX64.EFI" "https://boot.netboot.xyz/ipxe/netboot.xyz.efi"

# Create local script routing redirection
cat <<EOF > "$MOUNT_DIR/autoexec.ipxe"
#!ipxe
chain https://raw.githubusercontent.com/ppkcomputers/arch-unattended/main/script.ipxe
EOF

echo ""
echo "=========================================================="
echo "✅ ARMING SUCCESSFUL: Intelligent key created!"
echo "=========================================================="
echo "🎯 USB Configuration Complete:"
echo " - Main Target Hard Drive: /dev/$INTERNAL_DRIVE"
echo " - User profile: $USER_NAME"
echo " - Desktop: $PROFILE"
echo " - Timezone: $TIMEZONE"
echo " - Storage Layout: Btrfs with GRUB bootloader"
echo "=========================================================="
