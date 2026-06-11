Run this script to prepare your flash drive with new arch intallation files:
curl -L "https://raw.githubusercontent.com/ppkcomputers/arch-unattended/refs/heads/main/arch-to-usb.sh" -o arch-to-usb.sh && chmod +x arch-to-usb.sh && sudo ./arch-to-usb.sh

Run this script once in live install environment to copy standard user config json file and start archinstall:
curl -L "https://raw.githubusercontent.com/ppkcomputers/arch-unattended/refs/heads/main/run-install.sh" -o /tmp/run-install.sh && bash /tmp/run-install.sh

Default user_conifiguration file will install the following:
-btrfs file system
-Desktop windows manager: hyprland
-pipewire
-ufw firewall

