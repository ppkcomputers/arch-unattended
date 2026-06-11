#!/usr/bin/env bash

set -e

CONFIG_PATH="/tmp/user_configuration.json"
CREDS_PATH="/tmp/user_credentials.json"

echo "------------------------------------------------------------"
echo "📥 FETCHING ARCHINSTALL BLUEPRINTS FROM GITHUB"
echo "------------------------------------------------------------"

# Fetch with an aggressive volatile random query to completely burst all CDN/proxy cache blocks
echo "Downloading user_configuration.json (forcing fresh cache)..."
curl -L "https://raw.githubusercontent.com/ppkcomputers/arch-unattended/refs/heads/main/user_configuration.json?nocache=$RANDOM$RANDOM" -o "$CONFIG_PATH"

echo "Checking for user_credentials.json on GitHub..."
CREDS_URL="https://raw.githubusercontent.com/ppkcomputers/arch-unattended/refs/heads/main/user_credentials.json?nocache=$RANDOM$RANDOM"

if curl -sfL "$CREDS_URL" -o "$CREDS_PATH"; then
    echo "✅ Credentials configuration pulled successfully."
else
    echo "⚠️ user_credentials.json not found. Generating custom credentials..."
    echo -n "🔑 Enter desired ROOT password: "
    read -s ROOT_PASS
    echo ""
    echo -n "👤 Enter new USERNAME: "
    read REQ_USER
    echo -n "🔑 Enter password for user '$REQ_USER': "
    read -s USER_PASS
    echo ""

    cat << EOF > "$CREDS_PATH"
{
    "root-password": "${ROOT_PASS}",
    "users": [
        { "username": "${REQ_USER}", "password": "${USER_PASS}", "sudo": true }
    ]
}
EOF
fi

echo ""
echo "------------------------------------------------------------"
echo "🖥️  AVAILABLE SYSTEM STORAGE DRIVES"
echo "------------------------------------------------------------"
lsblk -p -dno NAME,SIZE,MODEL | grep -vE "loop|airootfs" || true
echo "------------------------------------------------------------"

echo -n "👉 Enter the full drive path to install Arch onto (e.g., /dev/sda or /dev/vda): "
read -r TARGET_DRIVE

if [ ! -b "$TARGET_DRIVE" ]; then
    echo "❌ Error: $TARGET_DRIVE is not a valid block device."
    exit 1
fi

echo "🧹 Clearing existing partition traces on $TARGET_DRIVE..."
umount "${TARGET_DRIVE}"* 2>/dev/null || true
wipefs -a -f "$TARGET_DRIVE"

echo "🔄 Injecting target drive string mappings..."
# This modifies any instance of /dev/sdb over to your real target drive choice inside the JSON layout
sed -i "s|/dev/sdb|${TARGET_DRIVE}|g" "$CONFIG_PATH"

echo "🚀 Commencing automated archinstall installation sequence..."
echo "------------------------------------------------------------"

archinstall --config "$CONFIG_PATH" --creds "$CREDS_PATH"
