#!/bin/bash

set -e

MOUNT="/mnt"

dialog --msgbox "Welcome to Artix Installer (MVP)" 10 40

# ----------------------------
# DISK SELECTION
# ----------------------------
DISK=$(lsblk -dno NAME | sed 's|^|/dev/|' | \
dialog --menu "Select disk to install to:" 15 50 8 3>&1 1>&2 2>&3)

clear
echo "Selected disk: $DISK"

# SAFETY CONFIRM
dialog --yesno "THIS WILL ERASE $DISK. Continue?" 8 50 || exit 1

# ----------------------------
# PARTITIONING
# ----------------------------
cfdisk "$DISK"

PART_ROOT="${DISK}1"

# ----------------------------
# FORMAT
# ----------------------------
mkfs.ext4 "$PART_ROOT"

# ----------------------------
# MOUNT
# ----------------------------
mount "$PART_ROOT" "$MOUNT"

# ----------------------------
# BASE INSTALL
# ----------------------------
basestrap "$MOUNT" base base-devel linux linux-firmware openrc elogind-openrc

# ----------------------------
# FSTAB
# ----------------------------
fstabgen -U "$MOUNT" >> "$MOUNT/etc/fstab"

# ----------------------------
# CHROOT CONFIG (basic)
# ----------------------------
artix-chroot "$MOUNT" /bin/bash <<EOF

echo "Setting root password"
passwd

echo "Installing GRUB"
grub-install --target=i386-pc $DISK
grub-mkconfig -o /boot/grub/grub.cfg

EOF

dialog --msgbox "Install complete. Reboot now." 10 40
