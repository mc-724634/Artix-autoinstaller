#!/usr/bin/env bash
#
# modules/chroot.sh — PHASE 9-11: chroot config, user setup, cleanup

# ---- PHASE 9: chroot script creation ---------------------------------------

phase9_chroot_config() {
    conf_load

    local timezone hostname

    timezone=$(ui_inputbox "Enter timezone (e.g. America/New_York):" "UTC")
    if [[ $? -ne 0 || -z "$timezone" ]]; then
        die "No timezone entered."
    fi
    if [[ ! -e "/usr/share/zoneinfo/$timezone" ]]; then
        ui_msgbox "Warning: /usr/share/zoneinfo/$timezone not found on the live ISO.\nProceeding anyway; verify after install." 8 60
    fi
    conf_set "TIMEZONE" "$timezone"

    hostname=$(ui_inputbox "Enter hostname:" "ArtixPC")
    if [[ $? -ne 0 || -z "$hostname" ]]; then
        die "No hostname entered."
    fi
    conf_set "HOSTNAME" "$hostname"

    # Determine firmware type now, while we still have access to /sys.
    local firmware="bios"
    [[ -d /sys/firmware/efi ]] && firmware="uefi"
    conf_set "FIRMWARE" "$firmware"

    _write_post_script "$timezone" "$hostname" "$firmware"

    ui_msgbox "Running post-install configuration inside chroot.\nThis can take a few minutes." 8 60
    artix-chroot /mnt bash /root/post.sh
    check_exit $? "Post-install chroot script failed. Check $LOG_FILE."
}

# _write_post_script TIMEZONE HOSTNAME FIRMWARE
# Writes /mnt/root/post.sh. Values are baked in directly (no env-passing
# across the chroot boundary needed).
_write_post_script() {
    local timezone="$1" hostname="$2" firmware="$3"

    cat > /mnt/root/post.sh <<EOF
#!/usr/bin/env bash
set -u
exec 2>>/root/post-install.log

# 9.1 timezone
ln -sf "/usr/share/zoneinfo/${timezone}" /etc/localtime
hwclock --systohc

# 9.2 locale
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# 9.3 hostname
echo "${hostname}" > /etc/hostname
{
    echo "127.0.0.1 localhost"
    echo "::1       localhost"
    echo "127.0.1.1 ${hostname}.localdomain ${hostname}"
} >> /etc/hosts

# 9.4 packages
pacman -Sy --noconfirm grub efibootmgr os-prober iwd networkmanager chrony

# 9.5 bootloader
if [[ "${firmware}" == "uefi" ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    grub-install --recheck "${DISK:-/dev/sda}"
fi

# 9.6 grub config
grub-mkconfig -o /boot/grub/grub.cfg
EOF
    # Note: ${DISK:-/dev/sda} above is expanded immediately while writing
    # the heredoc (unquoted EOF), using the DISK value from conf_load.

    chmod +x /mnt/root/post.sh
}

# ---- PHASE 10: user setup ---------------------------------------------------

phase10_user_setup() {
    local username password password2

    username=$(ui_inputbox "Enter username for new user:" "user")
    if [[ $? -ne 0 || -z "$username" ]]; then
        die "No username entered."
    fi
    conf_set "USERNAME" "$username"

    while true; do
        password=$(ui_passwordbox "Enter password for $username:")
        [[ $? -ne 0 ]] && die "No password entered."
        password2=$(ui_passwordbox "Confirm password:")
        [[ $? -ne 0 ]] && die "No password confirmation entered."
        if [[ "$password" == "$password2" ]]; then
            break
        fi
        ui_msgbox "Passwords did not match. Try again." 7 50
    done

    artix-chroot /mnt useradd -m -G wheel "$username"
    check_exit $? "Failed to create user $username."

    artix-chroot /mnt bash -c "echo '${username}:${password}' | chpasswd"
    check_exit $? "Failed to set password for $username."

    # Allow wheel group sudo access.
    artix-chroot /mnt bash -c "pacman -Sy --noconfirm sudo && sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers"
    check_exit $? "Failed to configure sudo for the wheel group."
}

# ---- PHASE 11: cleanup -------------------------------------------------------

phase11_cleanup() {
    rm -f /mnt/root/post.sh

    umount -R /mnt 2>/dev/null || true
    swapoff -a || true

    ui_yesno "Installation finished. Reboot now?" 7 50
    if [[ $? -eq 0 ]]; then
        reboot
    fi
}
