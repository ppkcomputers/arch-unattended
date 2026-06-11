#!/usr/bin/env bash

set -e

CONFIG_PATH="/tmp/user_configuration.json"
CREDS_PATH="/tmp/user_credentials.json"

echo "------------------------------------------------------------"
echo "📥 FETCHING ARCHINSTALL BLUEPRINTS FROM GITHUB"
echo "------------------------------------------------------------"

# Fetch with a highly volatile randomized query parameter to bust any CDN caching
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

echo "🔄 Injecting target drive mapping..."
sed -i "s|/dev/sdb|${TARGET_DRIVE}|g" "$CONFIG_PATH"

# EMERGENCY SANITY CHECK: If the downloaded file still contains old keys due to caching,
# this manually swaps the layout block style right in RAM to prevent Python validation crashes.
if grep -q '"config_type": "default_layout"' "$CONFIG_PATH"; then
    echo "⚠️ Cache detected! Force-converting disk layout profile in RAM..."
    
    # Use python's internal json tool to cleanly overwrite the file safely without breaking syntax
    python3 -c "
import json
with open('$CONFIG_PATH', 'r') as f:
    data = json.load(f)

data['disk_config'] = {
    'btrfs_options': {'snapshot_config': {'type': 'Snapper'}},
    'config_type': 'pre_configured_layout',
    'pre_configured_layout': {
        'device': '${TARGET_DRIVE}',
        'filesystem': 'btrfs',
        'mount_options': ['compress=zstd'],
        'subvolumes': [
            {'mountpoint': '/', 'name': '@'},
            {'mountpoint': '/home', 'name': '@home'},
            {'mountpoint': '/var/log', 'name': '@log'},
            {'mountpoint': '/var/cache/pacman/pkg', 'name': '@pkg'}
        ],
        'wipe': True
    }
}

with open('$CONFIG_PATH', 'w') as f:
    json.dump(data, f, indent=4)
"
fi

echo "🚀 Commencing automated archinstall installation sequence..."
echo "------------------------------------------------------------"

archinstall --config "$CONFIG_PATH" --creds "$CREDS_PATH"
