#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

CONFIG_PATH="/tmp/user_configuration.json"
CREDS_PATH="/tmp/user_credentials.json"

echo "------------------------------------------------------------"
echo "📥 FETCHING ARCHINSTALL BLUEPRINTS FROM GITHUB"
echo "------------------------------------------------------------"

# 1. Curl your configuration file straight into RAM (/tmp)
echo "Downloading user_configuration.json..."
curl -L "https://raw.githubusercontent.com/ppkcomputers/arch-unattended/refs/heads/main/user_configuration.json" -o "$CONFIG_PATH"

# 2. Check for credentials file (Fallback to manual input if missing on GitHub)
echo "Checking for user_credentials.json on GitHub..."
CREDS_URL="https://raw.githubusercontent.com/ppkcomputers/arch-unattended/refs/heads/main/user_credentials.json"

if curl -sfL "$CREDS_URL" -o "$CREDS_PATH"; then
    echo "✅ Credentials configuration pulled successfully from GitHub."
else
    echo "⚠️ user_credentials.json not found on GitHub. Generating custom credentials in RAM..."
    echo "------------------------------------------------------------"
    echo "🔐 TARGET CONFIGURATION CREDENTIALS"
    echo "------------------------------------------------------------"
    echo -n "🔑 Enter desired ROOT password: "
    read -s ROOT_PASS
    echo ""
    echo -n "👤 Enter new USERNAME (all lowercase): "
    read REQ_USER
    echo -n "🔑 Enter password for user '$REQ_USER': "
    read -s USER_PASS
    echo ""

    # Generate the credentials file structurally
    cat << EOF > "$CREDS_PATH"
{
    "root-password": "${ROOT_PASS}",
    "users": [
        {
            "username": "${REQ_USER}",
            "password": "${USER_PASS}",
            "sudo": true
        }
    ]
}
EOF
    echo "✅ Temporary credentials mapped successfully."
fi

echo ""
echo "------------------------------------------------------------"
echo "🖥️  AVAILABLE SYSTEM STORAGE DRIVES"
echo "------------------------------------------------------------"
# List all block storage targets clearly for selection
lsblk -p -dno NAME,SIZE,MODEL | grep -vE "loop|airootfs" || true
echo "------------------------------------------------------------"

# 3. Prompt user for target storage block injection
echo -n "👉 Enter the full drive path to install Arch onto (e.g., /dev/sda or /dev/vda): "
read -r TARGET_DRIVE

# Basic validation catch
if [ ! -b "$TARGET_DRIVE" ]; then
    echo "❌ Error: $TARGET_DRIVE is not a valid block device name."
    exit 1
fi

echo "🧹 Clearing block constraints..."
umount "${TARGET_DRIVE}"* 2>/dev/null || true
wipefs -a -f "$TARGET_DRIVE"

echo "🔄 Injecting target drive and dynamic disk scaling mappings..."
# A. Swap out the default device name for your chosen target drive
sed -i "s|/dev/sdb|${TARGET_DRIVE}|g" "$CONFIG_PATH"

# B. STRIP HARDCODED SIZE CONSTRAINTS: 
# This removes the fixed 126 GiB byte allocation block and forces archinstall to auto-scale the drive layout
sed -i '/"size": {/,/}/c\"size": "100%"' "$CONFIG_PATH"
sed -i '/"start": {/,/}/d' "$CONFIG_PATH"

# Fix formatting trailing commas that the deletions might disrupt
sed -i 's/"status": "create"/"status": "create"/g' "$CONFIG_PATH"

echo "✅ Configuration adjustments synchronized dynamically."
echo "🚀 Commencing automated archinstall installation sequence..."
echo "------------------------------------------------------------"

# 4. Fire up archinstall referencing our updated assets inside RAM
archinstall --config "$CONFIG_PATH" --creds "$CREDS_PATH"
