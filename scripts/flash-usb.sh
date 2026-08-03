#!/usr/bin/env bash
#
# Write a MarwanOS image to a physical USB stick from WSL, then repair the GPT
# for the stick's real size and verify every link before anyone reboots.
#
# Exists because of three days lost to the alternative. Writing a GPT image to
# a LARGER stick leaves the backup GPT stranded mid-disk and the protective MBR
# undersized. UEFI firmware and Windows tolerate that; GRUB and the Linux
# kernel reject the partition table outright -- so the machine boots from a
# stick it then cannot see, and dracut times out on a root UUID that is
# genuinely present. Windows then "helpfully" rewrites the GPT header on next
# insertion and corrupts the main partition table CRC, making the rejection
# permanent. Rufus writes the bytes fine; everything after the write is the
# problem. `sgdisk -e` after writing fixes all of it, so this script does the
# write and the repair as one operation, from Linux, and proves the result.
#
# Prerequisites (Windows side, elevated, once per stick):
#   winget install --exact dorssel.usbipd-win
#   & "C:\Program Files\usbipd-win\usbipd.exe" bind   --hardware-id <VID:PID>
#   & "C:\Program Files\usbipd-win\usbipd.exe" attach --wsl --hardware-id <VID:PID>
# Find the VID:PID with:  usbipd list
#
# Usage (WSL, root):
#   FLASH_CONFIRM=yes ./scripts/flash-usb.sh <image> <device>
#   e.g. FLASH_CONFIRM=yes ./scripts/flash-usb.sh /var/tmp/m1-out/image/disk.raw /dev/sde
#
set -euo pipefail

IMG="${1:-}"
DEV="${2:-}"

die() { echo >&2; echo "flash-usb: $*" >&2; exit 1; }

[[ -n "$IMG" && -n "$DEV" ]] || die "usage: FLASH_CONFIRM=yes flash-usb.sh <image> <device>"
[[ -f "$IMG" ]] || die "no image at $IMG"
[[ -b "$DEV" ]] || die "$DEV is not a block device (is the stick attached via usbipd?)"
command -v sgdisk >/dev/null || die "sgdisk missing:  dnf install -y gdisk"

# --- interlocks: this tool must never be pointable at a system disk ---------

BASE="$(basename "$DEV")"
[[ -e "/sys/block/$BASE" ]] || die "$DEV is a partition, not a whole disk"

DEVPATH="$(readlink -f "/sys/block/$BASE/device" 2>/dev/null || true)"
case "$DEVPATH" in
    *usb*|*vhci*) ;;
    *) die "$DEV does not look USB-attached (sysfs: ${DEVPATH:-unknown}). Refusing." ;;
esac

grep -q "^$DEV" /proc/mounts && die "$DEV has mounted partitions; unmount first"
for p in "$DEV"?*; do
    [[ -b "$p" ]] && grep -q "^$p " /proc/mounts && die "$p is mounted; unmount first"
done

IMG_BYTES=$(stat -c%s "$IMG")
DEV_BYTES=$(blockdev --getsize64 "$DEV")
(( DEV_BYTES >= IMG_BYTES )) || die "device ($DEV_BYTES B) smaller than image ($IMG_BYTES B)"

MODEL="$(cat "/sys/block/$BASE/device/model" 2>/dev/null | tr -s ' ' || echo unknown)"
echo "==> Target: $DEV  model='${MODEL}'  $(( DEV_BYTES / 1024 / 1024 / 1024 )) GiB (usb)"
echo "==> Image : $IMG  $(( IMG_BYTES / 1024 / 1024 )) MiB"
echo "==> EVERYTHING ON $DEV WILL BE DESTROYED."
[[ "${FLASH_CONFIRM:-}" == "yes" ]] || die "set FLASH_CONFIRM=yes to proceed"

# --- expected identity, read from the image itself ---------------------------

part_off() { # partition number -> byte offset, via sfdisk
    sfdisk -J "$IMG" | python3 -c "
import json,sys
j=json.load(sys.stdin)
print(j['partitiontable']['partitions'][int(sys.argv[1])-1]['start']*512)
" "$1"
}
EXP_BOOT=$(blkid -p -O "$(part_off 3)" -o value -s UUID "$IMG" | head -1)
EXP_ROOT=$(blkid -p -O "$(part_off 4)" -o value -s UUID "$IMG" | head -1)
[[ -n "$EXP_BOOT" && -n "$EXP_ROOT" ]] || die "could not read filesystem UUIDs from the image"
echo "==> Expect boot=$EXP_BOOT root=$EXP_ROOT"

# --- write, repair, verify ---------------------------------------------------

echo "==> Writing (this is the slow part)"
dd if="$IMG" of="$DEV" bs=4M conv=fsync status=progress
sync

echo "==> Repairing GPT for the device's real size (backup header + protective MBR)"
sgdisk -e "$DEV" >/dev/null
sync
blockdev --rereadpt "$DEV" 2>/dev/null || true
sleep 2

echo "==> Verifying"
PARTS=$(lsblk -nro NAME "$DEV" | grep -c "^${BASE}[0-9]" || true)
[[ "$PARTS" -eq 4 ]] || die "expected 4 partitions after write, kernel sees $PARTS -- do not boot this"

GOT_BOOT=$(blkid -o value -s UUID "${DEV}3" | head -1)
GOT_ROOT=$(blkid -o value -s UUID "${DEV}4" | head -1)
[[ "$GOT_BOOT" == "$EXP_BOOT" ]] || die "boot UUID mismatch: got $GOT_BOOT"
[[ "$GOT_ROOT" == "$EXP_ROOT" ]] || die "root UUID mismatch: got $GOT_ROOT"

MNT=$(mktemp -d)
mount -o ro "${DEV}2" "$MNT"
STICK_SHA=$(sha256sum "$MNT/EFI/BOOT/BOOTX64.EFI" | cut -d' ' -f1)
umount "$MNT"; rmdir "$MNT"

IMG_MNT=$(mktemp -d)
LOOP=$(losetup -f -P --show "$IMG")
mount -o ro "${LOOP}p2" "$IMG_MNT"
IMG_SHA=$(sha256sum "$IMG_MNT/EFI/BOOT/BOOTX64.EFI" | cut -d' ' -f1)
umount "$IMG_MNT"; rmdir "$IMG_MNT"; losetup -d "$LOOP"

[[ "$STICK_SHA" == "$IMG_SHA" ]] || die "BOOTX64.EFI on stick differs from image"

cat <<EOF

==> VERIFIED. The stick is bootable-by-construction:
    partitions : 4/4 visible to the Linux kernel
    boot UUID  : $GOT_BOOT
    root UUID  : $GOT_ROOT
    BOOTX64.EFI: checksum-identical to the image

    Detach (Windows, elevated):
      & "C:\\Program Files\\usbipd-win\\usbipd.exe" detach --hardware-id <VID:PID>
    or just unplug. Then boot: F12 -> EFI USB Device.
EOF
