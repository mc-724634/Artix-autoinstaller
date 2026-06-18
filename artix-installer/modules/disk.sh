#!/usr/bin/env bash
#
# modules/disk.sh — PHASE 1-5: disk selection, prep, partition, format, mount

# ---- PHASE 1: disk selection ----------------------------------------------

phase1_disk_selection() {
    local raw menu_items=() line tag desc

    raw=$(lsblk -dpno NAME,SIZE,MODEL)
    check_exit $? "Failed to enumerate block devices (lsblk)."

    if [[ -z "$raw" ]]; then
        die "No block devices found."
    fi

    while IFS= read -r line; do
        tag=$(awk '{print $1}' <<<"$line")
        desc=$(cut -d' ' -f2- <<<"$line")
        menu_items+=("$tag" "$desc")
    done <<<"$raw"

    local disk
    disk=$(ui_menu "Select installation disk" 16 60 8 "${menu_items[@]}")
    if [[ $? -ne 0 || -z "$disk" ]]; then
        die "No disk selected."
    fi

    ui_yesno "ALL DATA ON $disk WILL BE ERASED.\n\nContinue?" 9 60
    if [[ $? -ne 0 ]]; then
        die "Installation cancelled by user."
    fi

    conf_set "DISK" "$disk"

    # NVMe / mmcblk devices use a 'p' before the partition number,
    # plain sd*/vd* devices do not.
    local suffix=""
    if [[ "$disk" =~ (nvme|mmcblk) ]]; then
        suffix="p"
    fi
    conf_set "EFI"  "${disk}${suffix}1"
    conf_set "ROOT" "${disk}${suffix}2"
    conf_set "SWAP" "${disk}${suffix}3"
}

# ---- PHASE 2: disk preparation --------------------------------------------

phase2_disk_preparation() {
    conf_load
    swapoff -a || true
    umount -R /mnt 2>/dev/null || true
    blockdev --rereadpt "$DISK" 2>/dev/null || true
}

# ---- PHASE 3: partitioning (auto mode, parted -s only) --------------------

phase3_partitioning() {
    conf_load

    ui_msgbox "Partitioning $DISK:\n  1) 512MiB  EFI (FAT32)\n  2) rest-4GiB  root (ext4)\n  3) 4GiB  swap" 10 60

    parted -s "$DISK" -- \
        mklabel gpt \
        mkpart ESP fat32 1MiB 513MiB \
        set 1 esp on \
        mkpart primary ext4 513MiB -4GiB \
        mkpart primary linux-swap -4GiB 100%
    check_exit $? "parted failed to partition $DISK."

    # RULE C: always refresh the partition table after writing it.
    partprobe "$DISK" || true
    udevadm settle
    sleep 1
}

# ---- PHASE 4: format -------------------------------------------------------

phase4_format() {
    conf_load

    mkfs.fat -F32 "$EFI"
    check_exit $? "Failed to format EFI partition ($EFI)."

    mkfs.ext4 -F "$ROOT"
    check_exit $? "Failed to format root partition ($ROOT)."

    mkswap "$SWAP"
    check_exit $? "Failed to create swap on $SWAP."

    swapon "$SWAP"
    check_exit $? "Failed to enable swap on $SWAP."
}

# ---- PHASE 5: mount --------------------------------------------------------

phase5_mount() {
    conf_load

    mount "$ROOT" /mnt
    check_exit $? "Failed to mount $ROOT at /mnt."

    mkdir -p /mnt/boot/efi
    mount "$EFI" /mnt/boot/efi
    check_exit $? "Failed to mount $EFI at /mnt/boot/efi."
}
