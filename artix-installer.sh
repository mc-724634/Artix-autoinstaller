#!/bin/bash

CONFIG="/tmp/artix-installer.conf"
LOG="/tmp/artix-installer.log"

exec 2> "$LOG"

### -----------------------------
### SAFE MODE (IMPORTANT)
### -----------------------------
set -u   # no unset vars (safer than set -e for installers)

trap 'error_exit' ERR

error_exit() {
    dialog --msgbox "Installer crashed.\nCheck log:\n$LOG" 10 50
    exit 1
}

### -----------------------------
### ROOT CHECK
### -----------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        dialog --msgbox "Run as root." 6 30
        exit 1
    fi
}

### -----------------------------
### DEPENDENCIES (SAFE)
### -----------------------------
install_deps() {
    local deps=(dialog artix-archlinux-support)

    for pkg in "${deps[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            pacman -Sy --noconfirm "$pkg" || {
                dialog --msgbox "Failed installing $pkg" 6 40
                exit 1
            }
        fi
    done

    command -v basestrap >/dev/null || {
        dialog --msgbox "basestrap missing - use official Artix ISO" 6 50
        exit 1
    }
}

### -----------------------------
### INIT CONFIG
### -----------------------------
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

load_config() {
    source "$CONFIG"
}

### -----------------------------
### INTERNET CHECK
### -----------------------------
check_internet() {
    dialog --infobox "Checking internet..." 5 40
    sleep 1

    if ! ping -c1 archlinux.org >/dev/null 2>&1; then
        dialog --msgbox "No internet. Opening network tool." 6 40
        nmtui
    fi
}

### -----------------------------
### DISK SELECT
### -----------------------------
select_disk() {
    local disks
    disks=$(lsblk -dpno NAME,SIZE,MODEL | grep -E "/dev/(sd|nvme)" || true)

    DISK=$(dialog --menu "Select Disk" 20 70 10 \
        $(echo "$disks" | awk '{print $1" "$1" "$2" "$3}') \
        3>&1 1>&2 2>&3)

    echo "DISK=$DISK" >> "$CONFIG"
}

### -----------------------------
### PARTITION (AUTO)
### -----------------------------
partition_disk() {

    prepare_disk

    dialog --yesno "WIPE AND PARTITION $DISK?\nTHIS WILL DESTROY ALL DATA" 8 60

    [[ $? -ne 0 ]] && return

    dialog --infobox "Creating partition table..." 3 40
    sleep 1

    parted -s "$DISK" mklabel gpt

    parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on

    parted -s "$DISK" mkpart ROOT ext4 513MiB 90%
    parted -s "$DISK" mkpart SWAP linux-swap 90% 100%

    # IMPORTANT: refresh kernel view
    partprobe "$DISK"
    udevadm settle

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

### -----------------------------
### FORMAT
### -----------------------------
format_parts() {
    mkfs.fat -F32 "$EFI"
    mkfs.ext4 "$ROOT"
    mkswap "$SWAP"
    swapon "$SWAP"
}

### -----------------------------
### MOUNT
### -----------------------------
mount_parts() {
    mount "$ROOT" /mnt
    mkdir -p /mnt/boot/efi
    mount "$EFI" /mnt/boot/efi
}

### -----------------------------
### INIT SELECT
### -----------------------------
select_init() {
    INIT=$(dialog --menu "Init System" 12 40 4 \
        dinit "Dinit (recommended)" \
        openrc "OpenRC" \
        runit "Runit" \
        s6 "S6" \
        3>&1 1>&2 2>&3)

    echo "INIT=$INIT" >> "$CONFIG"
}

### -----------------------------
### KERNEL SELECT
### -----------------------------
select_kernel() {
    KERNEL=$(dialog --menu "Kernel" 10 40 3 \
        linux "Stable" \
        lts "LTS" \
        zen "Zen" \
        3>&1 1>&2 2>&3)

    echo "KERNEL=$KERNEL" >> "$CONFIG"
}

### -----------------------------
### INSTALL BASE
### -----------------------------
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

### -----------------------------
### INSTALL KERNEL
### -----------------------------
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

### -----------------------------
### FSTAB
### -----------------------------
gen_fstab() {
    fstabgen -U /mnt >> /mnt/etc/fstab
}

### -----------------------------
### CHROOT SCRIPT
### -----------------------------
make_chroot() {
cat > /mnt/root/post.sh <<EOF
#!/bin/bash
set -e

source /tmp/artix-installer.conf

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

### -----------------------------
### CLEANUP
### -----------------------------
cleanup() {
    umount -R /mnt
    swapoff -a
}

### -----------------------------
### MAIN
### -----------------------------
main() {
    check_root

    install_deps
    init_config
    load_config

    dialog --msgbox "Welcome to Artix Installer" 6 40

    check_internet

    select_disk
    partition_disk
    format_parts
    mount_parts

    select_init
    select_kernel

    install_base
    install_kernel

    gen_fstab

    make_chroot
    run_chroot

    cleanup

    dialog --msgbox "Install complete!" 6 30
}

main
