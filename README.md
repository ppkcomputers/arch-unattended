Run this script to prepare your flash drive with new arch intallation files:

curl -L "https://raw.githubusercontent.com/ppkcomputers/arch-unattended/refs/heads/main/arch-to-usb.sh" -o arch-to-usb.sh && chmod +x arch-to-usb.sh && sudo ./arch-to-usb.sh

Run this script to install the usual arch apps choosing from a menu:

curl -sL "https://raw.githubusercontent.com/ppkcomputers/arch-unattended/refs/heads/main/new-install.sh" -o /tmp/new-install.sh && bash /tmp/new-install.sh
