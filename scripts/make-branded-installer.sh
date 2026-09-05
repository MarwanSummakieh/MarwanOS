#!/usr/bin/env bash
# Remaster a bootc Anaconda ISO while preserving its boot records and OCI payload.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$(realpath "${1:?usage: make-branded-installer.sh source.iso output.iso}")"
OUTPUT="$(realpath -m "${2:?output ISO required}")"
[[ "$SOURCE" != "$OUTPUT" ]] || { echo 'Source and output must differ' >&2; exit 1; }
[[ ! -e "$OUTPUT" ]] || { echo 'Output already exists' >&2; exit 1; }
for tool in xorriso unsquashfs mksquashfs magick python3 grub2-mkfont dnf rpm2cpio cpio mcopy; do command -v "$tool" >/dev/null; done
WORK="$(mktemp -d /var/tmp/pc1-media.XXXXXX)"
echo "Work directory: $WORK"
mkdir -p "$WORK/source" "$WORK/patch/images" "$WORK/patch/EFI/BOOT" "$WORK/patch/boot/grub2"
xorriso -osirrox on -indev "$SOURCE" \
    -extract /images/install.img "$WORK/source/install.img" \
    -extract /osbuild.ks "$WORK/source/osbuild.ks" \
    -extract /images/pxeboot/initrd.img "$WORK/source/initrd.img" \
    -extract /images/efiboot.img "$WORK/patch/images/efiboot.img" \
    -extract /EFI/BOOT/grub.cfg "$WORK/source/grub.cfg"
unsquashfs -d "$WORK/root" "$WORK/source/install.img"
python3 "$REPO_ROOT/scripts/brand-installer.py" "$WORK/root"
python3 "$REPO_ROOT/scripts/brand-installer.py" kickstart "$WORK/source/osbuild.ks" "$WORK/patch/osbuild.ks"
bash "$REPO_ROOT/scripts/brand-installer-boot.sh" "$WORK" "$REPO_ROOT"
grub2-mkfont -s 24 -o "$WORK/patch/boot/grub2/pc1.pf2" /usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf
THEME="$REPO_ROOT/os/files/usr/share/plymouth/themes/marwanos"
PIX="$WORK/root/usr/share/anaconda/pixmaps"
magick "$THEME/field.png" -resize '300x900!' \
    \( "$THEME/pc1.png" -resize 230x \) -gravity north -geometry +0+90 -composite \
    \( "$THEME/powered-by.png" -resize 90x \) -geometry +0+190 -composite \
    \( "$THEME/marwanos.png" -resize 210x \) -geometry +0+230 -composite "$PIX/pc1-sidebar.png"
magick "$THEME/pc1.png" -resize 110x "$PIX/pc1-header.png"
magick "$THEME/splash.png" -resize 700x394 "$PIX/pc1-progress.png"
magick "$THEME/field.png" -resize '1280x720!' \
    \( "$THEME/pc1.png" -resize 560x \) -gravity north -geometry +0+75 -composite \
    \( "$THEME/powered-by.png" -resize 100x \) -geometry +0+290 -composite \
    \( "$THEME/marwanos.png" -resize 300x \) -geometry +0+335 -composite \
    -depth 8 -alpha off "$WORK/patch/boot/grub2/pc1.png"
cp "$REPO_ROOT/os/installer/grub-theme.txt" "$WORK/patch/boot/grub2/pc1-theme.txt"
magick -size 8x8 xc:'#1c1c1e' -depth 8 "PNG24:$WORK/patch/boot/grub2/selection_c.png"
python3 - "$WORK" <<'PY'
import sys
from pathlib import Path
w = Path(sys.argv[1])
grub = (w / 'source/grub.cfg').read_text()
grub = grub.replace('set timeout=3', 'set timeout=-1')
search = next(line for line in grub.splitlines() if line.startswith('search --no-floppy'))
grub = grub.replace(search, search + '''
insmod gfxterm
insmod png
loadfont /boot/grub2/pc1.pf2
set gfxmode=1280x720,auto
terminal_output gfxterm
background_image /boot/grub2/pc1.png
set theme=/boot/grub2/pc1-theme.txt
export theme''')
grub = grub.replace('Install MarwanOS 43 in basic graphics mode', 'PC1 setup - compatibility graphics')
grub = grub.replace('Install MarwanOS 43', 'Set up PC1 - Powered by MarwanOS')
grub = grub.replace('Rescue a MarwanOS system', 'Recover an existing PC1 installation')
# inst.cmdline would bypass the UI; fail rather than inherit an unattended entry.
if 'inst.cmdline' in grub or 'inst.text' in grub:
    raise SystemExit('Unsupported non-graphical source boot configuration')
for path in ('EFI/BOOT/grub.cfg', 'boot/grub2/grub.cfg'):
    (w / 'patch' / path).write_text(grub)
PY
# USB firmware loads the FAT EFI partition, not the ISO's /EFI directory.
# Keep its menu in sync and replace the appended partition as well as the
# visible file. Replaying boot records alone preserves the stale FAT image.
mcopy -o -i "$WORK/patch/images/efiboot.img" "$WORK/patch/EFI/BOOT/grub.cfg" ::/EFI/BOOT/grub.cfg
mksquashfs "$WORK/root" "$WORK/patch/images/install.img" -noappend -comp zstd -processors 4
xorriso -indev "$SOURCE" -outdev "$OUTPUT" -boot_image any replay \
    -append_partition 2 0xef "$WORK/patch/images/efiboot.img" \
    -map "$WORK/patch/images/efiboot.img" /images/efiboot.img \
    -map "$WORK/patch/images/install.img" /images/install.img \
    -map "$WORK/patch/images/pxeboot/initrd.img" /images/pxeboot/initrd.img \
    -map "$WORK/patch/osbuild.ks" /osbuild.ks \
    -map "$WORK/patch/EFI/BOOT/grub.cfg" /EFI/BOOT/grub.cfg \
    -map "$WORK/patch/boot/grub2/grub.cfg" /boot/grub2/grub.cfg \
    -map "$WORK/patch/boot/grub2/pc1.png" /boot/grub2/pc1.png \
    -map "$WORK/patch/boot/grub2/pc1.pf2" /boot/grub2/pc1.pf2 \
    -map "$WORK/patch/boot/grub2/pc1-theme.txt" /boot/grub2/pc1-theme.txt \
    -map "$WORK/patch/boot/grub2/selection_c.png" /boot/grub2/selection_c.png
python3 "$REPO_ROOT/scripts/check-installer-efi.py" "$OUTPUT" "$WORK/patch/images/efiboot.img"
sha256sum "$OUTPUT" | tee "$OUTPUT.sha256"
echo "Built $OUTPUT. Boot and installation validation are required before flashing."
