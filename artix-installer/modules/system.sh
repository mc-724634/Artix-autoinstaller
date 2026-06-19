#!/usr/bin/env bash
#
# modules/system.sh — PHASE 6-8: init system, kernel, base install, fstab

# ---- PHASE 6: init system selection ---------------------------------------

phase6_init_selection() {
    local init
    init=$(ui_menu "Select init system" 16 64 5 \
        "dinit"    "Fast, dependency-based init (recommended)" \
        "openrc"   "Classic OpenRC init" \
        "runit"    "Minimalist runit init" \
        "s6"       "s6-based init" \
        "systemd"  "Installs Arch Linux instead of Artix (see note)")
    if [[ $? -ne 0 || -z "$init" ]]; then
        die "No init system selected."
    fi
    conf_set "INIT" "$init"

    local pkgs
    case "$init" in
        dinit)    pkgs="base base-devel dinit elogind-dinit" ;;
        openrc)   pkgs="base base-devel openrc elogind-openrc" ;;
        runit)    pkgs="base base-devel runit elogind-runit" ;;
        s6)       pkgs="base base-devel s6-base elogind-s6" ;;
        systemd)
            ui_yesno "systemd is not part of Artix — Artix exists specifically to avoid it.\n\nChoosing it here will reconfigure pacman to install a standard Arch Linux base instead (different repos + package keyring), not Artix-with-systemd-bolted-on.\n\nContinue?" 12 70
            if [[ $? -ne 0 ]]; then
                die "Installation cancelled — systemd selection requires switching to an Arch Linux base."
            fi
            _switch_to_arch_repos
            # Arch's `base` package already depends on systemd directly,
            # so no separate systemd/elogind package is needed here.
            pkgs="base base-devel"
            ;;
        *)        die "Unknown init system: $init" ;;
    esac

    ui_msgbox "Installing base system with $init via basestrap.\nThis can take several minutes." 8 60
    # shellcheck disable=SC2086
    basestrap /mnt $pkgs
    check_exit $? "basestrap failed while installing base system."

    conf_set "INIT_PKGS" "$pkgs"
}

# _switch_to_arch_repos — reconfigures the LIVE environment's pacman to
# pull from real Arch Linux repos (core/extra) instead of Artix's, and
# bootstraps the archlinux-keyring so signature checks pass. basestrap
# itself doesn't care which repos pacman is pointed at — it's just a
# wrapper around `pacman --root` — so once this is done, basestrap installs
# genuine Arch packages (including a systemd-based `base`) into /mnt.
#
# The live ISO's own pacman.conf is backed up and restored in
# phase11_cleanup so the live session itself is left untouched.
_switch_to_arch_repos() {
    conf_load
    [[ "${ARCH_REPOS_ACTIVE:-no}" == "yes" ]] && return 0

    if [[ ! -f /etc/pacman.conf.artix-installer.bak ]]; then
        cp /etc/pacman.conf /etc/pacman.conf.artix-installer.bak
        check_exit $? "Failed to back up /etc/pacman.conf before switching to Arch repos."
    fi

    cat > /etc/pacman.d/mirrorlist-archlinux <<'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
EOF

    # Step 1: SigLevel = Never temporarily, just long enough to pull down
    # archlinux-keyring itself (chicken-and-egg: can't verify Arch package
    # signatures with a keyring we don't have yet).
    cat > /etc/pacman.conf <<'EOF'
[options]
Architecture = auto
SigLevel = Never
ParallelDownloads = 5

[core]
Include = /etc/pacman.d/mirrorlist-archlinux

[extra]
Include = /etc/pacman.d/mirrorlist-archlinux
EOF

    ui_msgbox "Fetching the Arch Linux package keyring. This requires internet access." 7 60

    pacman -Sy --noconfirm >>"$LOG_FILE" 2>&1
    check_exit $? "Failed to sync Arch Linux package databases."

    pacman -S --noconfirm archlinux-keyring >>"$LOG_FILE" 2>&1
    check_exit $? "Failed to install archlinux-keyring."

    pacman-key --init >>"$LOG_FILE" 2>&1
    pacman-key --populate archlinux >>"$LOG_FILE" 2>&1
    check_exit $? "Failed to populate the archlinux keyring."

    # Step 2: now that keys are trusted, turn signature checking back on.
    cat > /etc/pacman.conf <<'EOF'
[options]
Architecture = auto
SigLevel = Required DatabaseOptional
ParallelDownloads = 5

[core]
Include = /etc/pacman.d/mirrorlist-archlinux

[extra]
Include = /etc/pacman.d/mirrorlist-archlinux
EOF

    pacman -Sy --noconfirm >>"$LOG_FILE" 2>&1
    check_exit $? "Failed to sync Arch Linux package databases (signed)."

    conf_set "ARCH_REPOS_ACTIVE" "yes"
}

# ---- PHASE 7: kernel selection ---------------------------------------------

phase7_kernel_selection() {
    local kernel
    kernel=$(ui_menu "Select kernel" 13 60 3 \
        "linux"     "Latest stable kernel" \
        "linux-lts" "Long-term support kernel" \
        "linux-zen" "Performance-tuned kernel")
    if [[ $? -ne 0 || -z "$kernel" ]]; then
        die "No kernel selected."
    fi
    conf_set "KERNEL" "$kernel"

    basestrap /mnt "$kernel" linux-firmware
    check_exit $? "basestrap failed while installing kernel ($kernel)."
}

# ---- PHASE 8: fstab ---------------------------------------------------------

phase8_fstab() {
    fstabgen -U /mnt >> /mnt/etc/fstab
    check_exit $? "fstabgen failed to generate /etc/fstab."
}
