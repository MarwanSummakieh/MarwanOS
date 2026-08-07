#!/usr/bin/env bash
#
# Write a MarwanOS INSTALLER ISO to a USB stick, and prove the bytes landed.
#
# WHY THIS EXISTS ALONGSIDE flash-usb.sh, RATHER THAN AS A FLAG ON IT. That
# script writes a GPT DISK IMAGE and then repairs the partition table for the
# stick's real size -- `sgdisk -e`, a four-partition check, filesystem UUIDs
# read out of partitions 3 and 4, a checksum of BOOTX64.EFI mounted off
# partition 2. Every one of those steps is meaningless here and most of them
# are actively wrong: an installer ISO is a hybrid ISO9660 image whose layout
# is not a GPT disk, and running `sgdisk -e` across it would rewrite structures
# the ISO does not have. Two write paths that share nothing but `dd` are
# clearer as two files than as one file with a mode switch threading through
# every check.
#
# WHAT VERIFICATION MEANS FOR AN ISO. There are no partition UUIDs to compare,
# so the check is the honest one: read back exactly as many bytes as were
# written and compare a hash. That catches a short write, a silently failing
# stick, and a truncated image -- which is the whole failure surface here.
#
# THE WINDOWS GPT TRAP DOES NOT APPLY. That trap is Windows rewriting the GPT
# of a removable disk it enumerates; an ISO has no GPT to rewrite, so the
# elaborate pull-it-physically dance around flash-usb.sh is unnecessary here.
# Windows may still pop a "format this disk?" dialog -- say no; it is reacting
# to a filesystem it cannot read, not to damage.
#
#   FLASH_CONFIRM=yes ./scripts/flash-iso.sh <iso> <device>
#   e.g. FLASH_CONFIRM=yes ./scripts/flash-iso.sh /var/tmp/bench-out/install.iso /dev/sde
#
set -euo pipefail

die() { echo >&2; echo "flash-iso: $*" >&2; exit 1; }

ISO="${1:-}"
DEV="${2:-}"
[[ -n "$ISO" && -n "$DEV" ]] || die "usage: FLASH_CONFIRM=yes flash-iso.sh <iso> <device>"

[[ -r "$ISO" ]] || die "cannot read $ISO"
[[ -b "$DEV" ]] || die "$DEV is not a block device"

BASE="$(basename "$DEV")"
# Refusing anything that is not USB is the one guard that matters: this script
# destroys whatever it is pointed at, and the difference between the stick and
# the machine's own disk is one letter.
TRAN="$(lsblk -ndo TRAN "$DEV" 2>/dev/null || true)"
[[ "$TRAN" == "usb" ]] || die "$DEV is not a USB device (transport '${TRAN:-unknown}') -- refusing"

# A partition, not a whole disk, would write the ISO somewhere unbootable.
[[ -e "/sys/block/$BASE" ]] || die "$DEV looks like a partition; give the whole disk (e.g. /dev/sde)"

ISO_BYTES=$(stat -c%s "$ISO")
DEV_BYTES=$(blockdev --getsize64 "$DEV")
(( DEV_BYTES >= ISO_BYTES )) || die "device ($DEV_BYTES B) smaller than image ($ISO_BYTES B)"

MODEL="$(tr -s ' ' < "/sys/block/$BASE/device/model" 2>/dev/null || echo unknown)"
echo "==> Target: $DEV  model='${MODEL}'  $(( DEV_BYTES / 1024 / 1024 / 1024 )) GiB (usb)"
echo "==> ISO   : $ISO  $(( ISO_BYTES / 1024 / 1024 )) MiB"
echo "==> EVERYTHING ON $DEV WILL BE DESTROYED."
[[ "${FLASH_CONFIRM:-}" == "yes" ]] || die "set FLASH_CONFIRM=yes to proceed"

# Anything the kernel auto-mounted has to go before the device is overwritten,
# or the write lands under a live mount and the stick is inconsistent.
for part in "${DEV}"?*; do
    [[ -b "$part" ]] || continue
    umount "$part" 2>/dev/null || true
done

echo "==> Writing"
dd if="$ISO" of="$DEV" bs=4M conv=fsync status=progress
sync

# Drop the page cache before reading back, or the comparison is against what
# was just written from memory rather than against what the stick actually
# holds -- which would pass on a stick that silently discarded every byte.
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

echo "==> Verifying (reading back ${ISO_BYTES} bytes)"
ISO_SHA="$(sha256sum "$ISO" | cut -d' ' -f1)"
DEV_SHA="$(head -c "$ISO_BYTES" "$DEV" | sha256sum | cut -d' ' -f1)"

[[ "$ISO_SHA" == "$DEV_SHA" ]] \
    || die "read-back mismatch: stick $DEV_SHA vs image $ISO_SHA -- do not boot this"

cat <<EOF

==> VERIFIED. ${ISO_BYTES} bytes read back match the image byte for byte.
    sha256: $ISO_SHA

    This is an INSTALLER, not a live image. Booting it will offer to install
    MarwanOS onto the target machine's own disk -- which ERASES whatever is on
    the disk you select. Point it at the test bench, never at a machine whose
    contents matter.

    Boot: F12 (or the target's boot-menu key) -> EFI USB Device.
    Secure Boot must be off.

    Unlike the disk-image sticks, this one has no GPT for Windows to corrupt,
    so it survives being left plugged in. If Windows offers to format it, say
    no -- it simply cannot read ISO9660.
EOF
