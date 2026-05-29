#!/bin/bash
set -e

echo "================================="
echo " Artix Linux Automated Installer "
echo "================================="
echo

########################################
# USER INPUTS
########################################

read -rp "Enter hostname: " HOSTNAME
read -rp "Enter username: " USERNAME

echo
echo "Select disk type:"
echo "1) Virtual Machine (vda)"
echo "2) Real Machine (nvme0n1)"
echo

read -rp "Choice [1/2]: " TARGET

case "$TARGET" in
    1) DISK="vda" ;;
    2) DISK="nvme0n1" ;;
    *) echo "Invalid choice"; exit 1 ;;
esac

EFI="/dev/${DISK}1"
SWAP="/dev/${DISK}2"
ROOT="/dev/${DISK}3"

echo
echo "Using:"
echo "  EFI  -> $EFI"
echo "  SWAP -> $SWAP"
echo "  ROOT -> $ROOT"
echo

########################################
# SAFETY CHECK
########################################

[[ -b "$ROOT" ]] || { echo "Root partition missing"; exit 1; }

read -rp "THIS WILL ERASE THESE PARTITIONS. Continue? (yes/no): " CONFIRM
[[ "$CONFIRM" == "yes" ]] || exit 1

########################################
# FORMAT + MOUNT
########################################

echo "[1/7] Formatting partitions..."
mkfs.fat -F 32 "$EFI"
mkswap "$SWAP"
mkfs.ext4 "$ROOT"

swapon "$SWAP"

mount "$ROOT" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI" /mnt/boot/efi

########################################
# BASE SYSTEM + ARCH SUPPORT
########################################

echo "[2/7] Installing base system + arch support..."

basestrap /mnt base base-devel dinit elogind-dinit \
    linux-zen linux-firmware \
    iwd iwd-dinit networkmanager networkmanager-dinit \
    sudo artix-archlinux-support

########################################
# ENABLE ARCH REPOS
########################################

cat >> /mnt/etc/pacman.conf << 'EOF'

[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF

########################################
# FSTAB
########################################

fstabgen -U /mnt >> /mnt/etc/fstab

########################################
# PASS VARIABLES
########################################

export HOSTNAME="$HOSTNAME"
export USERNAME="$USERNAME"

########################################
# POST INSTALL (CHROOT STAGE)
########################################

cat > /mnt/root/postinstall.sh << EOF
#!/bin/bash
set -e

HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"

set_password() {
    local user="\$1"
    while true; do
        set +e
        passwd "\$user"
        STATUS=\$?
        set -e
        [[ \$STATUS -eq 0 ]] && break
        echo "Try again..."
    done
}

echo "[1/10] Timezone"
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo "[2/10] Locale"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG="en_US.UTF-8"' > /etc/locale.conf

echo "[3/10] Keyring + Arch support init"
pacman-key --init
pacman-key --populate archlinux

echo "[4/10] Bootloader"
pacman -Sy --noconfirm grub os-prober efibootmgr

grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot/efi \
  --bootloader-id=grub

grub-mkconfig -o /boot/grub/grub.cfg

echo "[5/10] Users"
set_password root

useradd -m "\$USERNAME"
usermod -aG wheel "\$USERNAME"
set_password "\$USERNAME"

echo "[6/10] Sudo"
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

echo "[7/10] Hostname"
echo "\$HOSTNAME" > /etc/hostname

cat > /etc/hosts << HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   \$HOSTNAME.localdomain \$HOSTNAME
HOSTS

echo "[8/10] Core services + Plasma"
pacman -Sy \
  dbus dbus-dinit \
  elogind elogind-dinit \
  sddm sddm-dinit \
  bluez bluez-utils bluez-dinit \
  turnstile turnstile-dinit \
  pipewire pipewire-pulse wireplumber \
  pipewire-dinit pipewire-pulse-dinit wireplumber-dinit \
  flatpak \
  discord telegram-desktop steam gamemode lib32-gamemode\
  plasma plasma-meta

echo "[9/10] Firstboot setup script"
cat > /home/\$USERNAME/firstboot.sh << 'FEOF'
#!/bin/bash
set -e

FLAG="\$HOME/.firstboot-done"
[[ -f "\$FLAG" ]] && exit 0

echo "First boot setup..."

sudo dinitctl enable iwd
sudo dinitctl enable NetworkManager

echo "[*] Configuring NetworkManager to use iwd backend..."

sudo mkdir -p /etc/NetworkManager/conf.d

cat <<EOF | sudo tee /etc/NetworkManager/conf.d/wifi_backend.conf
[device]
wifi.backend=iwd
EOF

sudo pacman -S --needed base-devel git

if [[ ! -d "\$HOME/paru" ]]; then
    git clone https://aur.archlinux.org/paru.git "\$HOME/paru"
fi

cd "\$HOME/paru"
su -c 'makepkg -si --noconfirm' $USER
cd "\$HOME"

flatpak remote-add --if-not-exists flathub \
  https://flathub.org/repo/flathub.flatpakrepo

paru -S --noconfirm wayvr-bin || true
flatpak install -y flathub io.github.vysp3r.Wivrn || true

sudo dinitctl enable dbus
sudo dinitctl enable elogind
sudo dinitctl enable turnstiled
sudo dinitctl enable bluetoothd
sudo dinitctl enable sddm

touch "\$FLAG"

echo "Done — rebooting..."
sleep 5
reboot
FEOF

chmod +x /home/\$USERNAME/firstboot.sh
chown \$USERNAME:\$USERNAME /home/\$USERNAME/firstboot.sh

mkdir -p /home/\$USERNAME/.config/autostart

cat > /home/\$USERNAME/.config/autostart/firstboot.desktop << 'DCEF'
[Desktop Entry]
Type=Application
Exec=/home/$USERNAME/firstboot.sh
Hidden=false
NoDisplay=false
Name=First Boot Setup
X-GNOME-Autostart-enabled=true
DCEF

chown -R \$USERNAME:\$USERNAME /home/\$USERNAME/.config

echo "INSTALL COMPLETE"
EOF

chmod +x /mnt/root/postinstall.sh

########################################
# RUN INSTALL
########################################

artix-chroot /mnt /root/postinstall.sh
rm /mnt/root/postinstall.sh

echo
echo "================================="
echo " INSTALL COMPLETE - REBOOT NOW "
echo "================================="
