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
    _check_internet
    _check_required_tools
    _detect_firmware
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

# Every external command the installer shells out to, anywhere in any
# phase, mapped to the package that provides it. Checked up front so a
# missing tool fails fast with a clear message instead of dying halfway
# through partitioning or chrooting.
declare -A REQUIRED_TOOLS=(
    [lsblk]=util-linux
    [blockdev]=util-linux
    [mkswap]=util-linux
    [swapon]=util-linux
    [parted]=parted
    [partprobe]=parted
    [udevadm]=eudev
    [mkfs.fat]=dosfstools
    [mkfs.ext4]=e2fsprogs
    [basestrap]=artix-install-scripts
    [artix-chroot]=artix-install-scripts
    [fstabgen]=artix-install-scripts
    [pacman]=pacman
)

_check_required_tools() {
    local tool missing=()

    for tool in "${!REQUIRED_TOOLS[@]}"; do
        command -v "$tool" &>/dev/null || missing+=("$tool")
    done

    [[ ${#missing[@]} -eq 0 ]] && return 0

    # Build a deduped list of packages that need installing.
    local pkg pkgs=()
    for tool in "${missing[@]}"; do
        pkg="${REQUIRED_TOOLS[$tool]}"
        [[ " ${pkgs[*]:-} " == *" $pkg "* ]] || pkgs+=("$pkg")
    done

    if command -v pacman &>/dev/null; then
        ui_msgbox "Missing required tools: ${missing[*]}\n\nAttempting to install: ${pkgs[*]}" 10 70
        pacman -Sy --needed --noconfirm "${pkgs[@]}" >>"$LOG_FILE" 2>&1
    fi

    # Re-check after the install attempt (or immediately, if pacman
    # itself isn't even available — e.g. not actually on Artix).
    local still_missing=()
    for tool in "${missing[@]}"; do
        command -v "$tool" &>/dev/null || still_missing+=("$tool")
    done

    if [[ ${#still_missing[@]} -gt 0 ]]; then
        die "Missing required tools that could not be auto-installed: ${still_missing[*]}\n\nThis installer expects to run from the Artix live ISO. Install these manually (pacman -S <package>) and re-run."
    fi
}

# Detected ONCE, up front, and persisted — partitioning (Phase 3) needs to
# know this before it lays out the disk: a GPT disk with no bios_grub
# partition can fail to boot under legacy BIOS, so BIOS and UEFI get
# genuinely different partition layouts, not just a different grub-install
# flag at the very end.
_detect_firmware() {
    local firmware="bios"
    [[ -d /sys/firmware/efi ]] && firmware="uefi"
    conf_set "FIRMWARE" "$firmware"
    ui_msgbox "Detected firmware mode: ${firmware^^}\n\nIf this is wrong (e.g. you intended to install for the other mode), reboot the live ISO in that mode and re-run the installer." 9 65
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
