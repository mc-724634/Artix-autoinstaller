#!/bin/bash
set -e

CONFIG="/tmp/artix-install.conf"

### -------------------------
### BOOTSTRAP DEPENDENCIES
### -------------------------
install_deps() {
    local deps=(dialog basestrap artix-archlinux-support)

    for pkg in "${deps[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            pacman -Sy --noconfirm "$pkg"
        fi
    done
}

### -------------------------
### CONFIG
### -------------------------
init_config() {
cat > "$CONFIG" <<EOF
DISK=""
EFI=""
ROOT=""
SWAP=""
INIT=""
KERNEL=""
TIMEZONE=""
HOSTNAME="ArtixPC"
USERNAME="user"
EOF
}

source_config() {
    source "$CONFIG"
}

### -------------------------
### CHECK ROOT
### -------------------------
check_root() {
    [[ $EUID -ne 0 ]] && {
        dialog --msgbox "Run as root." 6 30
        exit 1
    }
}

### -------------------------
### INTERNET CHECK
### -------------------------
check_internet() {
    if ! ping -c1 archlinux.org &>/dev/null; then
        dialog --msgbox "No internet detected. Launching Network Manager..." 7 50
        nmtui
    fi
}

### -------------------------
### DISK SELECT
### -------------------------
select_disk() {
    local disks=$(lsblk -dpno NAME,SIZE,MODEL | grep -E "/dev/(sd|nvme)")

    DISK=$(dialog --menu "Select Disk" 20 70 10 \
        $(echo "$disks" | awk '{print $1" "$1" "$2" "$3}') \
        3>&1 1>&2 2>&3)

    echo "DISK=$DISK" >> "$CONFIG"
}

### -------------------------
### PARTITION (AUTO GPT)
### -------------------------
partition_disk() {
    dialog --yesno "Wipe and auto-partition $DISK ?" 7 50

    if [[ $? -ne 0 ]]; then
        cfdisk "$DISK"
        exit 0
    fi

    parted "$DISK" --script mklabel gpt
    parted "$DISK" --script mkpart ESP fat32 1MiB 513MiB
    parted "$DISK" --script set 1 esp on
    parted "$DISK" --script mkpart ROOT ext4 513MiB 90%
    parted "$DISK" --script mkpart SWAP linux-swap 90% 100%

    if [[ "$DISK" == *"nvme"* ]]; then
        EFI="${DISK}p1"
        ROOT="${DISK}p2"
        SWAP="${DISK}p3"
    else
        EFI="${DISK}1"
        ROOT="${DISK}2"
        SWAP="${DISK}3"
    fi

    echo "EFI=$EFI" >> "$CONFIG"
    echo "ROOT=$ROOT" >> "$CONFIG"
    echo "SWAP=$SWAP" >> "$CONFIG"
}

### -------------------------
### FORMAT
### -------------------------
format_partitions() {
    mkfs.fat -F32 "$EFI"
    mkfs.ext4 "$ROOT"
    mkswap "$SWAP"
    swapon "$SWAP"
}

### -------------------------
### MOUNT
### -------------------------
mount_partitions() {
    mount "$ROOT" /mnt
    mkdir -p /mnt/boot/efi
    mount "$EFI" /mnt/boot/efi
}

### -------------------------
### INIT SELECTION
### -------------------------
select_init() {
    INIT=$(dialog --menu "Init System" 15 40 4 \
        dinit "Dinit (recommended)" \
        openrc "OpenRC" \
        runit "Runit" \
        s6 "S6" \
        3>&1 1>&2 2>&3)

    echo "INIT=$INIT" >> "$CONFIG"
}

### -------------------------
### KERNEL SELECTION
### -------------------------
select_kernel() {
    KERNEL=$(dialog --menu "Kernel" 12 40 3 \
        linux "Stable" \
        lts "Long Term" \
        zen "Performance" \
        3>&1 1>&2 2>&3)

    echo "KERNEL=$KERNEL" >> "$CONFIG"
}

### -------------------------
### BASE INSTALL
### -------------------------
install_base() {
    case "$INIT" in
        dinit)
            basestrap /mnt base base-devel dinit elogind-dinit ;;
        openrc)
            basestrap /mnt base base-devel openrc elogind-openrc ;;
        runit)
            basestrap /mnt base base-devel runit elogind-runit ;;
        s6)
            basestrap /mnt base base-devel s6-base elogind-s6 ;;
    esac
}

### -------------------------
### KERNEL INSTALL
### -------------------------
install_kernel() {
    case "$KERNEL" in
        linux)
            basestrap /mnt linux linux-firmware ;;
        lts)
            basestrap /mnt linux-lts linux-firmware ;;
        zen)
            basestrap /mnt linux-zen linux-firmware ;;
    esac
}

### -------------------------
### FSTAB
### -------------------------
generate_fstab() {
    fstabgen -U /mnt >> /mnt/etc/fstab
}

### -------------------------
### CHROOT SCRIPT
### -------------------------
create_chroot() {
cat > /mnt/root/post.sh <<EOF
#!/bin/bash
set -e

TIMEZONE="\$(cat /tmp/artix-install.conf | grep TIMEZONE | cut -d= -f2)"
HOSTNAME="\$(cat /tmp/artix-install.conf | grep HOSTNAME | cut -d= -f2)"
KERNEL="\$(cat /tmp/artix-install.conf | grep KERNEL | cut -d= -f2)"

ln -sf /usr/share/zoneinfo/\$TIMEZONE /etc/localtime
hwclock --systohc

sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "\$HOSTNAME" > /etc/hostname
echo "127.0.1.1 \$HOSTNAME.localdomain \$HOSTNAME" >> /etc/hosts

pacman -S --noconfirm grub efibootmgr os-prober iwd networkmanager chrony

if [ -d /sys/firmware/efi ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    grub-install --recheck /dev/sda
fi

grub-mkconfig -o /boot/grub/grub.cfg

EOF

chmod +x /mnt/root/post.sh
}

run_chroot() {
    artix-chroot /mnt /root/post.sh
}

### -------------------------
### CLEANUP
### -------------------------
cleanup() {
    umount -R /mnt
    swapoff -a
}

### -------------------------
### MAIN FLOW
### -------------------------
main() {
    check_root
    install_deps
    init_config

    check_internet

    select_disk
    partition_disk
    format_partitions
    mount_partitions

    select_init
    select_kernel

    install_base
    install_kernel

    generate_fstab

    create_chroot
    run_chroot

    cleanup

    dialog --msgbox "Installation complete. Reboot now." 6 40
}

main
