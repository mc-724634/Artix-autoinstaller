#!/usr/bin/env bash
#
# modules/system.sh — PHASE 6-8: init system, kernel, base install, fstab

# ---- PHASE 6: init system selection ---------------------------------------

phase6_init_selection() {
    local init
    init=$(ui_menu "Select init system" 14 60 4 \
        "dinit"  "Fast, dependency-based init (recommended)" \
        "openrc" "Classic OpenRC init" \
        "runit"  "Minimalist runit init" \
        "s6"     "s6-based init")
    if [[ $? -ne 0 || -z "$init" ]]; then
        die "No init system selected."
    fi
    conf_set "INIT" "$init"

    local pkgs
    case "$init" in
        dinit)  pkgs="base base-devel dinit elogind-dinit" ;;
        openrc) pkgs="base base-devel openrc elogind-openrc" ;;
        runit)  pkgs="base base-devel runit elogind-runit" ;;
        s6)     pkgs="base base-devel s6-base elogind-s6" ;;
        *)      die "Unknown init system: $init" ;;
    esac

    ui_msgbox "Installing base system with $init via basestrap.\nThis can take several minutes." 8 60
    # shellcheck disable=SC2086
    basestrap /mnt $pkgs
    check_exit $? "basestrap failed while installing base system."

    conf_set "INIT_PKGS" "$pkgs"
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
