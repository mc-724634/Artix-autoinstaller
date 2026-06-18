#!/usr/bin/env bash
#
# modules/deps.sh — PHASE 0: bootstrap checks
#
# This is the most common place TUI installers freeze: an unbounded ping
# or a missing binary that errors into a hung pipeline. Every check here
# is bounded and reports failure through dialog, never silently.

phase0_bootstrap_check() {
    _check_root
    _check_dialog
    _check_basestrap
    _check_internet
}

_check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        # dialog may not even be available yet, so also echo to terminal
        echo "This installer must be run as root." >&2
        echo "This installer must be run as root."
        exit 1
    fi
}

_check_dialog() {
    if ! command -v dialog &>/dev/null; then
        echo "The 'dialog' package is required but not installed." >&2
        echo "Install it with: pacman -Sy dialog"
        exit 1
    fi
}

_check_basestrap() {
    if ! command -v basestrap &>/dev/null; then
        die "basestrap not found. Are you running the Artix live ISO?"
    fi
}

# RULE A: never use unbounded ping. Always -W (timeout) and -c (count).
_check_internet() {
    if ping -W2 -c1 archlinux.org &>/dev/null; then
        return 0
    fi

    ui_yesno "No internet connection detected.\n\nLaunch nmtui to connect now?" 9 60
    if [[ $? -eq 0 ]]; then
        if command -v nmtui &>/dev/null; then
            nmtui
        else
            ui_msgbox "nmtui not found. Connect manually in another TTY, then retry." 8 60
        fi
    fi

    # Re-check once after the user has had a chance to connect.
    if ping -W2 -c1 archlinux.org &>/dev/null; then
        return 0
    fi

    ui_yesno "Still no internet connection.\n\nContinue anyway? (package install will fail)" 9 60
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
}
