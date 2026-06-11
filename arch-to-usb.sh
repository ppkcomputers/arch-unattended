#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# 1. Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run this script with sudo."
    exit 1
fi

# 2. Install core utilities if missing
echo "Checking for required utilities..."
pacman -S --needed --noconfirm wget curl grep awk util-linux

echo "----------------------------------------"
echo "🖥️  AVAILABLE DISKS (Excluding OS Drive)"
echo "----------------------------------------"

# SAFETY TRACKING: Strip Btrfs subvolume syntax brackets '[...]' from findmnt output safely
RAW_SOURCE=$(findmnt -no SOURCE / | sed 's/\[.*\]//')
OS_DISK=$(lsblk -no PKNAME "$RAW_SOURCE" | tr -d '[:space:]')

if [ -z "$OS_DISK" ]; then
    OS_DISK="nvme0n1"
fi

# List all disk devices except your active OS drive, optical drives, or zram
AVAILABLE_DISKS=$(lsblk -dno NAME,SIZE | grep -vE "$OS_DISK|sr0|zram" || true)

if [ -z "$AVAILABLE_DISKS" ]; then
    echo "❌ No external/flash disks found!"
    exit 1
fi

echo "$AVAILABLE_DISKS"
echo "----------------------------------------"

# Force user to type the disk name (e.g., sda, sdb)
echo -n "👉 Enter the disk name you want to target (e.g., sda or sdb): "
read -r USER_CHOICE

# Clean up input and build full path
TARGET_DISK="/dev/${USER_CHOICE//\/dev\//}"

# Absolute Security Trap
if [ "$TARGET_DISK" = "/dev/$OS_DISK" ]; then
    echo "❌ SECURITY BLOCK: You cannot target /dev/$OS_DISK. That is your running OS drive!"
    exit 1
fi

if [ ! -b "$TARGET_DISK" ]; then
    echo "❌ Error: Target disk $TARGET_DISK does not exist."
    exit 1
fi

echo "‼️  CRITICAL WARNING: This will completely WIPE and ERASE $TARGET_DISK."
echo "Everything on $TARGET_DISK will be permanently deleted!"
echo "Running data clear protocols in 5 seconds. Hit Ctrl+C to abort!"

for i in {5..1}; do
    echo -n "$i... "
    sleep 1
done
echo -e "\n\n🚀 Starting drive preparation..."

# ----------------------------------------------------------------------
# CLEANING EXISTING SIGNATURES
# ----------------------------------------------------------------------
echo "Releasing device mappings and clearing headers..."
umount "${TARGET_DISK}"* 2>/dev/null || true
wipefs -a "$TARGET_DISK" || true
sync

# ----------------------------------------------------------------------
# DYNAMIC ISO ACQUISITION (ALWAYS FRESH DOWNLOAD)
# ----------------------------------------------------------------------
echo "🔄 Connecting to Arch Linux release mirrors to fetch newest image..."
MIRROR_URL="https://archlinux.za.mirror.allworldit.com/archlinux/iso/latest/"

# Scrape the mirror page dynamically to extract the exact name of this month's newest release
ISO_NAME=$(curl -sL "$MIRROR_URL" | grep -oE 'archlinux-[0-9.]+-x86_64\.iso' | head -n 1 || true)

# Fallback if the mirror layout changes or curl blips
if [ -z "$ISO_NAME" ]; then
    ISO_NAME="archlinux-x86_64.iso"
fi

DOWNLOAD_URL="${MIRROR_URL}${ISO_NAME}"

echo "------------------------------------------------------------"
echo "🌐 TARGET LIVE ISO URL FOUND:"
echo "🔗 $DOWNLOAD_URL"
echo "------------------------------------------------------------"

TARGET_ISO="./archlinux-latest.iso"

# Clear out any older downloaded file if it exists to ensure a completely pristine write block
rm -f "$TARGET_ISO"

echo "📥 Downloading newest Arch Linux release..."
wget -q --show-progress -O "$TARGET_ISO" "$DOWNLOAD_URL"

# ----------------------------------------------------------------------
# RAW DD BLOCK FLASHING
# ----------------------------------------------------------------------
echo "Writing raw Arch Linux ISO blocks onto $TARGET_DISK..."

# bs=4M speeds up execution safely
# conv=fsync guarantees data hits the hardware sectors completely
sudo dd if="$TARGET_ISO" of="$TARGET_DISK" bs=4M status=progress conv=fsync

echo "Flushing file system buffer caches..."
sync

echo "------------------------------------------------------------"
echo "🚀 SUCCESS! Pristine, Latest Arch Linux Media Prepared Natively."
echo "------------------------------------------------------------"
