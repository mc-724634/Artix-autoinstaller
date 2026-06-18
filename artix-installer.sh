#!/bin/bash

CONFIG="/tmp/artix.conf"
LOG="/tmp/artix-installer.log"

exec 2> "$LOG"

set -u
set +e   # IMPORTANT: prevents silent exits (your main bug)

### -------------------------
### SAFE DIALOG WRAPPER
### -------------------------
msg() {
    dialog --msgbox "$1" 8 60
}

inf() {
    dialog --infobox "$1" 5 50
}

### -------------------------
### ROOT CHECK
### -------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        msg "Run as root."
        exit 1
    fi
}

### -------------------------
### DEPENDENCIES (SAFE)
### -------------------------
deps() {
    inf "Checking dependencies..."

    for p in dialog basestrap artix-archlinux-support; do
        pacman -Qi "$p" >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            inf "Installing $p..."
            pacman -Sy --noconfirm "$p" >/dev/null 2>&1
        fi
    done

    command -v basestrap >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        msg "basestrap missing. Use official Artix ISO."
        exit 1
    fi
}

### -------------------------
### CONFIG INIT
### -------------------------
init_config() {
cat > "$CONFIG" <<EOF
DISK=""
EFI=""
ROOT=""
SWAP=""
INIT=""
KERNEL=""
TIMEZONE="America/New_York"
HOSTNAME="ArtixPC"
USERNAME="user"
EOF
}

source_config() {
    source "$CONFIG"
}

### -------------------------
### INTERNET CHECK (FIXED)
### -------------------------
internet_check() {
    inf "Checking internet..."

    # IMPORTANT: timeout prevents "freeze feel"
    ping -c1 -W2 archlinux.org >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        msg "No internet detected.\nOpen network tool (nmtui)."
        nmtui
    fi
}

### -------------------------
### DISK SELECT (SAFE)
### -------------------------
select_disk() {
    local disks
    disks=$(lsblk -dpno NAME,SIZE,MODEL | grep -E "/dev/(sd|nvme)")

    DISK=$(dialog --menu "Select Disk" 20 70 10 \
        $(echo "$disks" | awk '{print $1" "$1" "$2" "$3}') \
        3>&1 1>&2 2>&3)

    echo "DISK=$DISK" >> "$CONFIG"
}

### -------------------------
### PREP DISK (FIX FREEZE CAUSE)
### -------------------------
prep_disk() {
    swapoff -a >/dev/null 2>&1
    umount -R /mnt >/dev/null 2>&1

    blockdev --rereadpt "$DISK" >/dev/null 2>&1
}

### -------------------------
### PARTITION (STABLE)
### -------------------------
partition_disk() {

    dialog --yesno "WIPE $DISK?\nTHIS WILL DESTROY ALL DATA" 8 50
    [[ $? -ne 0 ]] && return

    prep_disk

    inf "Partitioning disk..."

    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart ROOT ext4 513MiB 90%
    parted -s "$DISK" mkpart SWAP linux-swap 90% 100%

    partprobe "$DISK"
    sleep 1

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
format_parts() {
    inf "Formatting..."

    mkfs.fat -F32 "$EFI"
    mkfs.ext4 "$ROOT"
    mkswap "$SWAP"
    swapon "$SWAP"
}

### -------------------------
### MOUNT
### -------------------------
mount_parts() {
    inf "Mounting..."

    mount "$ROOT" /mnt
    mkdir -p /mnt/boot/efi
    mount "$EFI" /mnt/boot/efi
}

### -------------------------
### INIT
### -------------------------
select_init() {
    INIT=$(dialog --menu "Init System" 12 40 4 \
        dinit "Dinit" \
        openrc "OpenRC" \
        runit "Runit" \
        s6 "S6" \
        3>&1 1>&2 2>&3)

    echo "INIT=$INIT" >> "$CONFIG"
}

### -------------------------
### KERNEL
### -------------------------
select_kernel() {
    KERNEL=$(dialog --menu "Kernel" 10 40 3 \
        linux "Stable" \
        lts "LTS" \
        zen "Zen" \
        3>&1 1>&2 2>&3)

    echo "KERNEL=$KERNEL" >> "$CONFIG"
}

### -------------------------
### BASE INSTALL
### -------------------------
install_base() {
    case "$INIT" in
        dinit) basestrap /mnt base base-devel dinit elogind-dinit ;;
        openrc) basestrap /mnt base base-devel openrc elogind-openrc ;;
        runit) basestrap /mnt base base-devel runit elogind-runit ;;
        s6) basestrap /mnt base base-devel s6-base elogind-s6 ;;
    esac
}

### -------------------------
### KERNEL INSTALL
### -------------------------
install_kernel() {
    case "$KERNEL" in
        linux) basestrap /mnt linux linux-firmware ;;
        lts) basestrap /mnt linux-lts linux-firmware ;;
        zen) basestrap /mnt linux-zen linux-firmware ;;
    esac
}

### -------------------------
### FSTAB
### -------------------------
fstab_gen() {
    fstabgen -U /mnt >> /mnt/etc/fstab
}

### -------------------------
### CHROOT
### -------------------------
make_chroot() {
cat > /mnt/root/post.sh <<EOF
#!/bin/bash
set -e

source /tmp/artix.conf

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
### CLEAN
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
    deps
    init_config
    source_config

    msg "Welcome to Artix Installer"

    internet_check

    select_disk
    partition_disk
    format_parts
    mount_parts

    select_init
    select_kernel

    install_base
    install_kernel

    fstab_gen
    make_chroot
    run_chroot

    cleanup

    msg "Install complete!"
}

main
