#!/bin/bash

# --- COLORS ---
GREEN=$(printf '\033[0;32m')
RED=$(printf '\033[0;31m')
YELLOW=$(printf '\033[0;33m')
NC=$(printf '\033[0m')
CHECKMARK="${GREEN}✔${NC}"

# --- SMART UPDATE CHECK ---
echo ":: Checking for system updates..."

if ! command -v checkupdates &> /dev/null; then
    sudo pacman -S --needed --noconfirm pacman-contrib
fi

if checkupdates &> /dev/null; then
    echo ":: Updates found! Upgrading system..."
    sudo pacman -Syu --noconfirm
else
    echo ":: System is already up to date. Proceeding..."
    sleep 1
fi

# --- FUNCTIONS ---

is_installed() {
    if pacman -Qi "$1" &> /dev/null; then
        return 0
    elif [[ "$1" == "swww" ]] && pacman -Qi "awww" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

ensure_yay() {
    if ! command -v yay &> /dev/null; then
        echo -e "${RED}:: Error: yay is not installed but is required.${NC}"
        read -p ":: Would you like to install yay now? (y/n): " yn < /dev/tty
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            install_yay
        else
            echo ":: Skipping because yay is missing."
            sleep 2
            return 1
        fi
    fi
    return 0
}

show_header() {
    clear
    echo "==========================================="
    echo "    ARCH LINUX POST-INSTALLATION MENU      "
    echo "==========================================="
}

manage_service() {
    echo -e "\n"
    read -p ":: Enable and start $1? (y/n): " answer < /dev/tty
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        sudo systemctl enable --now "$1"
    fi
}

install_yay() {
    if ! command -v yay &> /dev/null; then
        echo ":: Installing yay..."
        sudo pacman -S --needed --noconfirm base-devel git
        TEMP_DIR=$(mktemp -d)
        git clone https://aur.archlinux.org/yay-bin.git "$TEMP_DIR/yay-bin"
        cd "$TEMP_DIR/yay-bin" && makepkg -si --noconfirm
        cd ~ && rm -rf "$TEMP_DIR"
    fi
}

install_ufw_safely() {
    echo ":: Checking for existing firewall setups..."
    local conflict_found=0

    if systemctl is-active --quiet firewalld 2>/dev/null || is_installed "firewalld"; then
        conflict_found=1
    elif systemctl is-active --quiet nftables 2>/dev/null; then
        conflict_found=1
    elif systemctl is-active --quiet iptables 2>/dev/null && [ -s /etc/iptables/iptables.rules ]; then
        conflict_found=1
    fi

    if [ "$conflict_found" -eq 1 ]; then
        echo -e "${YELLOW}:: Warning: Another firewall detected. Skipping UFW.${NC}"
        sleep 2
        return 1
    else
        sudo pacman -S --noconfirm ufw
        sudo systemctl enable --now ufw
        sudo ufw --force enable
        echo ":: UFW installed and activated successfully."
        return 0
    fi
}

robust_install() {
    local name="$1"
    local cmd="$2"

    echo -e "\n${GREEN}:: Processing: $name...${NC}"
    eval "$cmd"

    if is_installed "$name"; then
        return 0
    else
        echo -e "${YELLOW}:: Installation failed. Retrying...${NC}"
        sudo pacman -Sy
        eval "$cmd"
        if is_installed "$name"; then
            return 0
        else
            echo -e "${RED}:: Failed to install $name.${NC}"
            return 1
        fi
    fi
}

convert_to_hyprland_lua() {
    echo ":: Processing hyprland.lua configuration..."

    local config_dir="$HOME/.config/hypr"
    local config_file="$config_dir/hyprland.lua"
    local backup_file="$config_dir/hyprland.lua.bak"

    # Create directory
    mkdir -p "$config_dir"

    # Backup existing config if it exists
    if [ -f "$config_file" ]; then
        echo ":: Existing hyprland.lua found. Creating backup..."
        cp "$config_file" "$backup_file"
        echo -e "${YELLOW}:: Backup created: $backup_file${NC}"
    fi

    # Download latest hyprland.lua
    echo ":: Downloading latest hyprland.lua..."
    if ! curl -sS https://raw.githubusercontent.com/ppkcomputers/arch-new-install-menu/main/hyprland.lua -o /tmp/hyprland.lua; then
        echo -e "${RED}:: Failed to download hyprland.lua.${NC}"
        return 1
    fi

    # Check for jq and configure monitor if available
    if command -v jq &> /dev/null; then
        echo ":: jq detected. Auto-configuring primary monitor..."

        # Get primary monitor info
        monitor_json=$(hyprctl monitors -j 2>/dev/null | jq '.[0]' 2>/dev/null)

        if [ -n "$monitor_json" ]; then
            monitor_name=$(echo "$monitor_json" | jq -r '.name')

            if [ -n "$monitor_name" ] && [ "$monitor_name" != "null" ]; then
                # Update monitor section using sed
                sed -i "s/output   = \".*\"/output   = \"$monitor_name\"/" /tmp/hyprland.lua
                sed -i "s/mode     = \".*\"/mode     = \"1920x1080@60\"/" /tmp/hyprland.lua
                sed -i "s/position = \".*\"/position = \"0x0\"/" /tmp/hyprland.lua
                sed -i "s/scale    = \".*\"/scale    = \"1\"/" /tmp/hyprland.lua

                echo -e "${GREEN}:: Monitor configured: $monitor_name (1920x1080@60, scale 1)${NC}"
            else
                echo -e "${YELLOW}:: Could not detect monitor name. Using defaults.${NC}"
            fi
        else
            echo -e "${YELLOW}:: Could not retrieve monitor information.${NC}"
        fi
    else
        echo -e "${YELLOW}:: jq not installed. Skipping automatic monitor configuration.${NC}"
        echo ":: You can install jq with: sudo pacman -S jq"
    fi

    # Copy the (possibly modified) file
    cp /tmp/hyprland.lua "$config_file"
    echo -e "${GREEN}:: hyprland.lua successfully installed to ~/.config/hypr/${NC}"
}

## --- MAIN MENU LOOP ---
while true; do
    show_header

    apps=("yay" "brave-origin-beta-bin" "dunst" "kate" "swww" "thunar" "kitty" "snapper" "snap-pac" "grub-btrfs" "hyprpolkitagent" "Convert to hyprland.lua" "ufw" "openssh")
    all_options=("${apps[@]}" "Install All" "Remove & Clean All" "Quit")

    echo "Select an option to install or configure:"
    echo ""

    for i in "${!all_options[@]}"; do
        idx=$((i + 1))
        item="${all_options[$i]}"

        if [[ $i -lt 14 ]]; then
            if [[ "$item" == "Convert to hyprland.lua" ]]; then
                printf "%2d) %-22b\n" "$idx" "$item"
            elif is_installed "$item"; then
                printf "%2d) %-22b %b\n" "$idx" "$item" "$CHECKMARK"
            else
                printf "%2d) %-22b\n" "$idx" "$item"
            fi
        else
            printf "%2d) %-22b\n" "$idx" "$item"
        fi
    done

    echo ""
    read -p "Choice: " choice < /dev/tty

    case $choice in
        1)  install_yay ;;
        2)  ensure_yay && yay -S --noconfirm brave-origin-beta-bin ;;
        3)  sudo pacman -S --noconfirm dunst && manage_service "dunst" ;;
        4)  sudo pacman -S --noconfirm kate ;;
        5)  ensure_yay && (yay -S --noconfirm swww || yay -S --noconfirm awww) ;;
        6)  sudo pacman -S --noconfirm thunar ;;
        7)  sudo pacman -S --noconfirm kitty ;;
        8)  sudo pacman -S --noconfirm snapper ;;
        9)  sudo pacman -S --noconfirm snap-pac ;;
        10) sudo pacman -S --noconfirm grub-btrfs && manage_service "grub-btrfsd" ;;
        11) ensure_yay && yay -S --noconfirm hyprpolkitagent ;;
        12) convert_to_hyprland_lua ;;
        13) install_ufw_safely ;;
        14) sudo pacman -S --noconfirm openssh ;;
        15)
            echo ":: Executing full installation..."
            failed_apps=()

            install_yay
            if ! command -v yay &> /dev/null; then failed_apps+=("yay"); fi

            if ! robust_install "brave-origin-beta-bin" "ensure_yay && yay -S --noconfirm brave-origin-beta-bin"; then failed_apps+=("brave-origin-beta-bin"); fi
            if ! robust_install "dunst" "sudo pacman -S --noconfirm dunst && manage_service 'dunst'"; then failed_apps+=("dunst"); fi
            if ! robust_install "kate" "sudo pacman -S --noconfirm kate"; then failed_apps+=("kate"); fi
            if ! robust_install "swww" "ensure_yay && (yay -S --noconfirm swww || yay -S --noconfirm awww)"; then failed_apps+=("swww"); fi
            if ! robust_install "thunar" "sudo pacman -S --noconfirm thunar"; then failed_apps+=("thunar"); fi
            if ! robust_install "snapper" "sudo pacman -S --noconfirm snapper"; then failed_apps+=("snapper"); fi
            if ! robust_install "snap-pac" "sudo pacman -S --noconfirm snap-pac"; then failed_apps+=("snap-pac"); fi
            if ! robust_install "grub-btrfs" "sudo pacman -S --noconfirm grub-btrfs && manage_service 'grub-btrfsd'"; then failed_apps+=("grub-btrfs"); fi
            if ! robust_install "hyprpolkitagent" "ensure_yay && yay -S --noconfirm hyprpolkitagent"; then failed_apps+=("hyprpolkitagent"); fi

            if ! is_installed "ufw"; then
                if ! install_ufw_safely; then failed_apps+=("ufw"); fi
            fi

            if ! robust_install "openssh" "sudo pacman -S --noconfirm openssh"; then failed_apps+=("openssh"); fi

            echo -e "\n==========================================="
            if [ ${#failed_apps[@]} -eq 0 ]; then
                echo -e "${GREEN}✔ All packages installed successfully!${NC}"
            else
                echo -e "${RED}❌ Some packages failed:${NC}"
                for app in "${failed_apps[@]}"; do echo "   - $app"; done
            fi
            echo "==========================================="
            read -r -p "Press Enter to continue..." < /dev/tty
            ;;
        16)
            echo -e "\n${RED}:: Warning: This will remove selected packages (except Kitty).${NC}"
            read -p ":: Proceed? (y/n): " clean_yn < /dev/tty
            if [[ "$clean_yn" =~ ^[Yy]$ ]]; then
                sudo systemctl disable --now dunst grub-btrfsd hyprpolkitagent ufw sshd &> /dev/null
                for pkg in snap-pac grub-btrfs snapper brave-origin-beta-bin dunst kate swww awww thunar hyprpolkitagent ufw openssh yay-bin yay; do
                    if is_installed "$pkg" || pacman -Qi "$pkg" &> /dev/null; then
                        sudo pacman -Rns --noconfirm "$pkg" 2>/dev/null || true
                    fi
                done
                sudo pacman -Sc --noconfirm
                echo ":: Cleanup completed."
                sleep 2
            fi
            ;;
        17) exit 0 ;;
        *)  echo "Invalid option."; sleep 1.5 ;;
    esac
done
