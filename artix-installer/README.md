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

0. Bootstrap checks (root, `dialog`, internet — bounded `ping -W2 -c1` with
   an `nmtui` fallback — required tools, then firmware mode detection)
1. Disk selection (`lsblk -dpno NAME,SIZE,MODEL` → menu)
2. Disk preparation (`swapoff -a`, `umount -R /mnt`, reread partition table)
3. Partitioning (`parted -s`) — **branches on firmware mode**:
   - UEFI: GPT, 512MiB EFI + root (ext4) + swap
   - BIOS: MBR/msdos, root (ext4, boot flag) + swap — no ESP, no GPT
     (avoids the classic "GPT without a bios_grub partition" boot failure)
4. Format (`mkfs.fat` only if there's an ESP, `mkfs.ext4`, `mkswap`/`swapon`)
5. Mount (`/mnt`, plus `/mnt/boot/efi` only on UEFI)
6. Init system selection — dinit / openrc / runit / s6, **or systemd**.
   Choosing systemd reconfigures pacman to pull a genuine Arch Linux base
   (different repos + keyring) instead of Artix — see "systemd / Arch
   Linux mode" below.
7. Kernel selection (linux / linux-lts / linux-zen) + `basestrap`
8. `fstabgen -U /mnt >> /mnt/etc/fstab`
9. Chroot config — writes and runs `/mnt/root/post.sh`: timezone, locale,
   hostname, `iwd` + `NetworkManager` (init-specific packages, enabled for
   first boot, NetworkManager configured to use iwd as its Wi-Fi backend),
   and GRUB (UEFI or BIOS, matching the partition layout from Phase 3)
10. User setup — username + confirmed password; sudo access is **asked
    for**, not automatic
10b. Root password — optional; skipping leaves root locked (login via
    `sudo` only)
11. Cleanup — unmount, swapoff, restore the live ISO's original
    pacman.conf if it was swapped for Arch repos, optional reboot

## systemd / Arch Linux mode

Artix exists specifically to ship without systemd, so there's no such
thing as "Artix with systemd" — picking `systemd` in the init menu
instead reconfigures the **live environment's** pacman to point at real
Arch Linux repos (`core`, `extra`) and bootstraps the `archlinux-keyring`
(temporarily disabling signature checks just long enough to fetch and
trust that keyring, then re-enabling `SigLevel = Required DatabaseOptional`).
From that point on, `basestrap` pulls genuine Arch packages — Arch's
`base` package depends on `systemd` directly, so no extra init package is
needed. Network services are enabled via `systemctl enable`.

The live ISO's original `/etc/pacman.conf` is backed up before the swap
and restored automatically in cleanup (Phase 11), so the live session
itself isn't left pointed at Arch repos after the installer exits.

This path needs working internet (already required by Phase 0) and pulls
in everything from upstream Arch mirrors, so expect it to take longer
than the Artix-native init options.

## Networking (iwd + NetworkManager)

Every init system gets `iwd` and `NetworkManager` installed with the
correct per-init package suffix (e.g. `iwd-dinit` + `networkmanager-dinit`
for dinit, plain `iwd` + `networkmanager` for systemd) and enabled for
first boot using that init's actual enable mechanism — symlinks for
dinit/runit, `rc-update add` for OpenRC, `systemctl enable` for systemd.
NetworkManager is pointed at iwd as its Wi-Fi backend via
`/etc/NetworkManager/conf.d/wifi-backend.conf`, since wpa_supplicant is
never installed.

The s6 enable step is the least certain of the four — Artix's s6 service
management (s6-rc vs. the 66 suite, depending on variant) is less
consistently documented than the others. If `iwd`/`NetworkManager` don't
come up after reboot on an s6 install, check `/root/post-install.log` and
the current Artix wiki for the exact enable command for your s6 variant.

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
