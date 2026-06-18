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

    # FIRMWARE was already detected in Phase 0 (_detect_firmware) and used
    # to choose the partition layout in Phase 3 — reuse the same value
    # here rather than re-detecting, so partitioning and bootloader
    # install can never disagree about which mode we're in.
    _write_post_script "$timezone" "$hostname" "${FIRMWARE:-bios}"

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
pacman -Sy --noconfirm grub iwd networkmanager chrony
EOF

    if [[ "$firmware" == "uefi" ]]; then
        cat >> /mnt/root/post.sh <<EOF
pacman -Sy --noconfirm efibootmgr os-prober

# 9.5 bootloader (UEFI)
# Primary install: registers an NVRAM boot entry via efibootmgr.
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
GRUB_PRIMARY_STATUS=\$?

# Fallback install: writes to the removable-media default path
# (EFI/BOOT/BOOTX64.EFI). Several firmwares — especially VMs (VirtualBox,
# some VMware/Hyper-V configs) and some laptops — don't reliably persist
# NVRAM entries created from a chroot, and silently fall back to nothing
# bootable on reboot. This fallback path is what most firmware tries when
# no NVRAM entry is found, so install it unconditionally as a safety net.
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable
GRUB_FALLBACK_STATUS=\$?

if [[ \$GRUB_PRIMARY_STATUS -ne 0 && \$GRUB_FALLBACK_STATUS -ne 0 ]]; then
    echo "grub-install failed on both the primary and removable paths" >&2
    exit 1
fi
EOF
    else
        cat >> /mnt/root/post.sh <<EOF
pacman -Sy --noconfirm os-prober

# 9.5 bootloader (BIOS/MBR)
grub-install --target=i386-pc --recheck "${DISK:-/dev/sda}"
EOF
    fi

    cat >> /mnt/root/post.sh <<'EOF'

# 9.6 grub config
grub-mkconfig -o /boot/grub/grub.cfg
EOF
    # Note: values like ${hostname}, ${DISK:-/dev/sda} above are expanded
    # immediately while writing the heredoc (unquoted EOF), using the
    # variables from conf_load. The final block uses a quoted 'EOF' so it
    # is NOT expanded here — it runs as-is inside the chroot.

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

# ---- PHASE 10b: root password (optional) -----------------------------------

phase10b_root_password() {
    # basestrap leaves the root account locked (no password) by default,
    # which is the safer choice when a sudo-capable user exists — but the
    # spec calls this out as optional, so offer it explicitly rather than
    # silently skipping it.
    ui_yesno "Set a root password?\n\n(If you skip this, root login stays locked — you can still use 'sudo' as your new user.)" 9 65
    if [[ $? -ne 0 ]]; then
        return 0
    fi

    local password password2
    while true; do
        password=$(ui_passwordbox "Enter root password:")
        [[ $? -ne 0 ]] && { ui_msgbox "No password entered; root will stay locked." 7 50; return 0; }
        password2=$(ui_passwordbox "Confirm root password:")
        [[ $? -ne 0 ]] && { ui_msgbox "No confirmation entered; root will stay locked." 7 50; return 0; }
        if [[ "$password" == "$password2" ]]; then
            break
        fi
        ui_msgbox "Passwords did not match. Try again." 7 50
    done

    artix-chroot /mnt bash -c "echo 'root:${password}' | chpasswd"
    check_exit $? "Failed to set root password."
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
