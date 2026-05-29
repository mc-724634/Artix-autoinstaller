#!/bin/bash
set -e

echo "================================="
echo " Artix Linux Automated Installer "
echo "================================="
echo

########################################
# DISK SELECTION
########################################

echo "======================================="
echo " Disk Setup (post-cfdisk stage)"
echo "======================================="
echo

echo "Make sure you already ran cfdisk and created:"
echo "  1 = EFI"
echo "  2 = SWAP"
echo "  3 = ROOT"
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

read -rp "THIS WILL ERASE PARTITIONS. Continue? (yes/no): " CONFIRM
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
basestrap /mnt base base-devel dinit elogind-dinit
basestrap /mnt linux-zen linux-firmware

echo "[5/6] Generating fstab..."
fstabgen -U /mnt >> /mnt/etc/fstab

########################################
# POST INSTALL SCRIPT
########################################

cat > /mnt/root/postinstall.sh << 'EOF'
#!/bin/bash
set -e

echo "===== POST INSTALL START ====="

########################################
# SAFE PASSWORD FUNCTION (FIXED)
########################################
set_password() {
    local user="$1"

    while true; do
        echo
        echo "Setting password for $user"

        set +e
        if [[ "$user" == "root" ]]; then
            passwd root
        else
            passwd "$user"
        fi
        STATUS=$?
        set -e

        if [[ $STATUS -eq 0 ]]; then
            echo "Password set successfully for $user"
            break
        else
            echo "Password mismatch or error. Try again."
        fi
    done
}

########################################
# LOCALE
########################################

echo "[1/6] Locale setup"
echo 'export LANG="en_US.UTF-8"' > /etc/locale.conf

########################################
# BOOTLOADER
########################################

echo "[2/6] Installing bootloader"
pacman -Sy --noconfirm grub os-prober efibootmgr

grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot/efi \
  --bootloader-id=grub

grub-mkconfig -o /boot/grub/grub.cfg

########################################
# PASSWORDS (NOW SAFE)
########################################

echo "[3/6] Root password"
set_password root

echo "[4/6] Creating user"
useradd -m cowboybub2003

echo "[5/6] User password"
set_password cowboybub2003

########################################
# NETWORKING
########################################

echo "[6/6] Installing networking"
pacman -Sy --noconfirm \
  iwd iwd-dinit \
  networkmanager networkmanager-dinit

echo "===== POST INSTALL COMPLETE ====="
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
echo " You can now reboot safely."
echo "================================="
