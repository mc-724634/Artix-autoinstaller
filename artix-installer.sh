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

echo "[1/6] Formatting partitions..."
mkfs.fat -F 32 "$EFI"
mkswap "$SWAP"
mkfs.ext4 "$ROOT"

echo "[2/6] Enabling swap..."
swapon "$SWAP"

echo "[3/6] Mounting system..."
mount "$ROOT" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI" /mnt/boot/efi

########################################
# BASE SYSTEM
########################################

echo "[4/6] Installing base system..."
basestrap /mnt base base-devel dinit elogind-dinit \
    linux-zen linux-firmware \
    iwd iwd-dinit networkmanager networkmanager-dinit sudo

echo "[5/6] Generating fstab..."
fstabgen -U /mnt >> /mnt/etc/fstab

########################################
# PASS VARIABLES INTO CHROOT
########################################

export HOSTNAME="$HOSTNAME"
export USERNAME="$USERNAME"

########################################
# POST INSTALL SCRIPT
########################################

cat > /mnt/root/postinstall.sh << 'EOF'
#!/bin/bash
set -e

HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"

set_password() {
    local user="$1"

    while true; do
        set +e
        passwd "$user"
        STATUS=$?
        set -e

        [[ $STATUS -eq 0 ]] && break
        echo "Password failed. Try again."
    done
}

########################################
# TIME
########################################

echo "[1/7] Timezone setup"
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

########################################
# LOCALE
########################################

echo "[2/7] Locale setup"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG="en_US.UTF-8"' > /etc/locale.conf

########################################
# BOOTLOADER
########################################

echo "[3/7] Bootloader setup"

pacman -Sy --noconfirm grub os-prober efibootmgr

grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot/efi \
  --bootloader-id=grub

grub-mkconfig -o /boot/grub/grub.cfg

########################################
# USERS
########################################

echo "[4/7] Root password"
set_password root

echo "[5/7] Creating user: $USERNAME"
useradd -m "$USERNAME"

echo "[5.1/7] Adding user to wheel group"
usermod -aG wheel "$USERNAME"

set_password "$USERNAME"

########################################
# SUDO (WHEEL ENABLED AUTOMATICALLY)
########################################

echo "[6/7] Enabling sudo for wheel group"

pacman -Sy --noconfirm sudo

echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

########################################
# HOSTNAME + HOSTS
########################################

echo "[7/7] Hostname setup"

echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts << HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

echo "POST INSTALL COMPLETE"
EOF

chmod +x /mnt/root/postinstall.sh

########################################
# AUTO CHROOT EXECUTION
########################################

echo "[6/6] Running post-install automatically..."
artix-chroot /mnt /root/postinstall.sh

rm /mnt/root/postinstall.sh

echo
echo "================================="
echo " INSTALL COMPLETE "
echo " Reboot when ready."
echo "================================="
