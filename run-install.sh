#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

CONFIG_PATH="/tmp/user_configuration.json"
CREDS_PATH="/tmp/user_credentials.json"

echo "------------------------------------------------------------"
echo "📥 FETCHING ARCHINSTALL BLUEPRINTS FROM GITHUB"
echo "------------------------------------------------------------"

# Fetch with a randomized string to force GitHub to bypass its cache layer entirely
echo "Downloading user_configuration.json (forcing fresh cache)..."
curl -L "https://raw.githubusercontent.com/ppkcomputers/arch-unattended/refs/heads/main/user_configuration.json?nocache=$RANDOM" -o "$CONFIG_PATH"

echo "Checking for user_credentials.json on GitHub..."
CREDS_URL="https://raw.githubusercontent.com/ppkcomputers/arch-unattended/refs/heads/main/user_credentials.json?nocache=$RANDOM"

if curl -sfL "$CREDS_URL" -o "$CREDS_PATH"; then
    echo "✅ Credentials configuration pulled successfully."
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
# List all block storage targets clearly for selection (omits loopback and live media mounts)
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

echo "🧹 Clearing existing partition system traces on $TARGET_DRIVE..."
umount "${TARGET_DRIVE}"* 2>/dev/null || true
wipefs -a -f "$TARGET_DRIVE"

echo "🔄 Mapping target drive to configuration template..."
# Dynamically swap /dev/sdb out for the user's specific choice inside the JSON blueprint
sed -i "s|/dev/sdb|${TARGET_DRIVE}|g" "$CONFIG_PATH"

echo "✅ Configuration adjustments synchronized dynamically."
echo "🚀 Commencing automated archinstall installation sequence..."
echo "------------------------------------------------------------"

# 4. Fire up archinstall referencing our updated assets inside RAM
archinstall --config "$CONFIG_PATH" --creds "$CREDS_PATH"
