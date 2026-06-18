# Artix TUI Installer

A modular `dialog`-based TUI installer for Artix Linux, designed to run
from the live ISO.

## Structure

```
installer.sh          entry point — sources modules, runs phases in order
modules/
  ui.sh                dialog wrappers, state-file helpers, error checking
  deps.sh              PHASE 0  — root/dialog/basestrap/internet checks
  disk.sh              PHASE 1-5 — disk select, prep, partition, format, mount
  system.sh            PHASE 6-8 — init system, kernel, base install, fstab
  chroot.sh            PHASE 9-11 — chroot config, user setup, cleanup
config/
  artix.conf.example   reference for the keys written to /tmp/artix.conf
```

## Usage

Boot the Artix live ISO as root, then:

```bash
git clone <this repo> artix-installer   # or copy the files over
cd artix-installer
bash installer.sh
```

All output you'd normally see scroll past (stderr, command noise) is
redirected to `/tmp/install.log` instead, so the dialog UI never gets
corrupted. If something fails, the installer stops with a message box
and that log has the details.

## Flow

0. Bootstrap checks (root, `dialog`, `basestrap`, internet — with a
   bounded `ping -W2 -c1` and an `nmtui` fallback if it's missing)
1. Disk selection (`lsblk -dpno NAME,SIZE,MODEL` → menu)
2. Disk preparation (`swapoff -a`, `umount -R /mnt`, reread partition table)
3. Partitioning (`parted -s`: 512MiB EFI, rest-4GiB root ext4, 4GiB swap)
4. Format (`mkfs.fat`, `mkfs.ext4`, `mkswap`/`swapon`)
5. Mount (`/mnt`, `/mnt/boot/efi`)
6. Init system selection (dinit / openrc / runit / s6) + `basestrap`
7. Kernel selection (linux / linux-lts / linux-zen) + `basestrap`
8. `fstabgen -U /mnt >> /mnt/etc/fstab`
9. Chroot config — writes and runs `/mnt/root/post.sh` for timezone,
   locale, hostname, network/boot packages, and GRUB (UEFI or BIOS,
   auto-detected from `/sys/firmware/efi`)
10. User setup — username + confirmed password, `wheel` group + `sudo`
11. Cleanup — unmount, swapoff, optional reboot

## Stability rules baked in

- No `set -e` anywhere — every command's exit code is checked explicitly
  via `check_exit`/`die`, and failures show a message box instead of
  dying silently.
- `set -u` everywhere; stderr always redirected to `/tmp/install.log`.
- Every internet/network check uses a bounded `ping -W2 -c1`, never an
  unbounded ping.
- Disk prep always runs `swapoff -a` and `umount -R /mnt` before any
  partitioning, and `partprobe` + `udevadm settle` immediately after.
- Dialog menus that need to capture a value always use
  `dialog ... 3>&1 1>&2 2>&3` — never a bare `$(dialog ...)` pipeline
  that can swallow input.
- All selections persist to `/tmp/artix.conf` as soon as they're made,
  so every later phase reads from a single source of truth via
  `conf_load`/`conf_get`/`conf_set`.

## Customizing the partition layout

The partition sizes are set in `modules/disk.sh` inside
`phase3_partitioning` (currently: 512MiB EFI, root takes everything
except the last 4GiB, swap gets the last 4GiB). Adjust the `parted`
arguments there if you want a different scheme — e.g. no swap partition,
a separate `/home`, or LVM/LUKS (which would need new phases of their
own; this build covers the spec's plain-partition flow only).
