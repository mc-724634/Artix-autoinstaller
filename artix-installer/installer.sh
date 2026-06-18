#!/usr/bin/env bash
#
# installer.sh — Artix Linux TUI Installer (entry point)
#
# Run this from the Artix live ISO as root:
#   bash installer.sh
#
# Do NOT use `set -e` here — every step checks its own exit code and
# fails loudly through dialog + the log file instead of dying silently.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Make sure everything is executable regardless of how these files were
# copied/extracted onto the live ISO (tarballs, git clones over certain
# transports, etc. can all drop the execute bit). Modules are sourced
# below, not executed, so they don't strictly need +x to work — but this
# also covers running `./installer.sh` directly, and any future module
# that gets exec'd rather than sourced.
chmod +x "$SCRIPT_DIR/installer.sh" "$SCRIPT_DIR"/modules/*.sh 2>/dev/null || true

# shellcheck source=modules/ui.sh
source "$SCRIPT_DIR/modules/ui.sh"
# shellcheck source=modules/deps.sh
source "$SCRIPT_DIR/modules/deps.sh"
# shellcheck source=modules/disk.sh
source "$SCRIPT_DIR/modules/disk.sh"
# shellcheck source=modules/system.sh
source "$SCRIPT_DIR/modules/system.sh"
# shellcheck source=modules/chroot.sh
source "$SCRIPT_DIR/modules/chroot.sh"

export CONF_FILE="/tmp/artix.conf"
export LOG_FILE="/tmp/install.log"

main() {
    # Phase: debug/log setup. All stderr from here on goes to the log,
    # not the terminal, so dialog screens never get corrupted by noise.
    : > "$LOG_FILE"
    exec 2>>"$LOG_FILE"

    : > "$CONF_FILE"

    phase0_bootstrap_check
    phase1_disk_selection
    phase2_disk_preparation
    phase3_partitioning
    phase4_format
    phase5_mount
    phase6_init_selection
    phase7_kernel_selection
    phase8_fstab
    phase9_chroot_config
    phase10_user_setup
    phase11_cleanup

    ui_msgbox "Installation complete! The system will reboot." 7 50
}

main "$@"
