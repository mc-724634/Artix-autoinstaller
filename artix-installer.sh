#!/bin/bash

set -e

echo "================================="
echo " Artix Linux Automated Installer "
echo "================================="
echo

echo "[1/10] Installing base system..."
basestrap /mnt base base-devel dinit elogind-dinit
basestrap /mnt linux-zen linux-firmware

echo "[2/10] Generating fstab..."
fstabgen -U /mnt >> /mnt/etc/fstab

echo "[3/10] Creating post-install script..."

cat > /mnt/root/postinstall.sh << 'EOF'
#!/bin/bash

set -e

echo "[1/7] Installing editor..."
pacman -Sy --noconfirm nano

echo "[2/7] Setting locale configuration..."
echo 'export LANG="en_US.UTF-8"' > /etc/locale.conf

echo "[3/7] Installing bootloader..."
pacman -Sy --noconfirm grub os-prober efibootmgr

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=grub

grub-mkconfig -o /boot/grub/grub.cfg

echo "[4/7] Set root password"
passwd

echo "[5/7] Creating user..."
useradd -m cowboybub2003

echo "[6/7] Set user password"
passwd cowboybub2003

echo "[7/7] Installing networking..."
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
