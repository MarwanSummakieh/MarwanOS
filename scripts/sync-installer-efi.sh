#!/usr/bin/env bash
# Repair an already branded ISO's embedded USB boot menu without rebuilding its OS.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$(realpath "${1:?source ISO required}")"
OUTPUT="$(realpath -m "${2:?new output ISO required}")"
[[ "$SOURCE" != "$OUTPUT" && ! -e "$OUTPUT" ]] || { echo 'Use a new output file' >&2; exit 1; }
WORK="$(mktemp -d /var/tmp/pc1-efi.XXXXXX)"
echo "Work directory: $WORK"
xorriso -osirrox on -indev "$SOURCE" \
    -extract /EFI/BOOT/grub.cfg "$WORK/grub.cfg" \
    -extract /images/efiboot.img "$WORK/efiboot.img"
grep -q 'Set up PC1' "$WORK/grub.cfg"
mcopy -o -i "$WORK/efiboot.img" "$WORK/grub.cfg" ::/EFI/BOOT/grub.cfg
mtype -i "$WORK/efiboot.img" ::/EFI/BOOT/grub.cfg > "$WORK/embedded.cfg"
cmp "$WORK/grub.cfg" "$WORK/embedded.cfg"
xorriso -indev "$SOURCE" -outdev "$OUTPUT" -boot_image any replay \
    -append_partition 2 0xef "$WORK/efiboot.img" \
    -map "$WORK/efiboot.img" /images/efiboot.img
python3 "$REPO_ROOT/scripts/check-installer-efi.py" "$OUTPUT" "$WORK/efiboot.img"
sha256sum "$OUTPUT" | tee "$OUTPUT.sha256"
