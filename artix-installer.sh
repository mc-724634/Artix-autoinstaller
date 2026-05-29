#!/bin/bash

set -e

echo "================================="
echo " Artix Linux Automated Installer "
echo "================================="
echo

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

if [[ "$TARGET" == "1" ]]; then
    DISK="vda"
elif [[ "$TARGET" == "2" ]]; then
    DISK="nvme0n1"
else
    echo "Invalid choice."
    exit 1
fi

EFI="/dev/${DISK}1"
SWAP="/dev/${DISK}2"
ROOT="/dev/${DISK}3"

echo
echo "Using:"
echo "  EFI  -> $EFI"
echo "  SWAP -> $SWAP"
echo "  ROOT -> $ROOT"
echo

read -rp "This will FORMAT partitions. Continue? (yes/no): " CONFIRM
[[ "$CONFIRM" == "yes" ]] || exit 1

echo "[1/5] Formatting partitions..."
mkfs.fat -F 32 "$EFI"
mkswap "$SWAP"
mkfs.ext4 "$ROOT"

echo "[2/5] Enabling swap..."
swapon "$SWAP"

echo "[3/5] Mounting root..."
mount "$ROOT" /mnt

echo "[4/5] Mounting EFI..."
mkdir -p /mnt/boot/efi
mount "$EFI" /mnt/boot/efi

echo "[5/5] Done!"

echo "[6/15] Installing base system..."
basestrap /mnt base base-devel dinit elogind-dinit
basestrap /mnt linux-zen linux-firmware

echo "[7/15] Generating fstab..."
fstabgen -U /mnt >> /mnt/etc/fstab

echo "[8/15] Creating post-install script..."

cat > /mnt/root/postinstall.sh << 'EOF'
#!/bin/bash

set -e

echo "[9/15] Installing editor..."
pacman -Sy --noconfirm nano

echo "[10/15] Setting locale configuration..."
echo 'export LANG="en_US.UTF-8"' > /etc/locale.conf

echo "[11/15] Installing bootloader..."
pacman -Sy --noconfirm grub os-prober efibootmgr

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=grub

grub-mkconfig -o /boot/grub/grub.cfg

echo "[12/15] Set root password"
passwd

echo "[13/15] Creating user..."
useradd -m cowboybub2003

echo "[14/15] Set user password"
passwd cowboybub2003

echo "[15/15] Installing networking..."
pacman -Sy --noconfirm \
    iwd \
    iwd-dinit \
    networkmanager \
    networkmanager-dinit

echo
echo "========================================"
echo " MANUAL STEPS REQUIRED BEFORE REBOOT "
echo "========================================"
echo
echo "1. Set timezone:"
echo "   ln -sf /usr/share/zoneinfo/Region/City /etc/localtime"
echo
echo "2. Sync hardware clock:"
echo "   hwclock --systohc"
echo
echo "3. Edit locale.gen:"
echo "   nano /etc/locale.gen"
echo
echo "4. Generate locales:"
echo "   locale-gen"
echo
echo "5. Set hostname:"
echo "   nano /etc/hostname"
echo
echo "6. Configure hosts file:"
echo "   nano /etc/hosts"
echo
echo "After completing those steps:"
echo "   exit"
echo "   reboot"
echo
EOF

chmod +x /mnt/root/postinstall.sh

echo
echo "================================="
echo " Base install complete!"
echo "================================="
echo
echo "Next run:"
echo
echo "artix-chroot /mnt"
echo "/root/postinstall.sh"
echo
