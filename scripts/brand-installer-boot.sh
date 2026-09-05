#!/usr/bin/env bash
# Add the graphical Plymouth module missing from the stock installer initramfs.
set -euo pipefail
WORK="${1:?work directory}"
REPO="${2:?repository}"
ROOT="$WORK/root"
OVERLAY="$WORK/boot-overlay"
mkdir -p "$WORK/rpms" "$WORK/rpm-root" "$OVERLAY/usr/lib64/plymouth/renderers" \
    "$OVERLAY/usr/share/plymouth/themes" "$OVERLAY/etc/plymouth" "$WORK/patch/images/pxeboot"
# Same Fedora 43 release as the installer's October 2025 Plymouth core.
dnf download --destdir "$WORK/rpms" \
    plymouth-plugin-script-24.004.60-20.fc43.x86_64 \
    plymouth-graphics-libs-24.004.60-20.fc43.x86_64
for package in "$WORK/rpms/"*.rpm; do
    (cd "$WORK/rpm-root"; rpm2cpio "$package" | cpio -idmu --quiet)
done
cp -a "$WORK/rpm-root/usr/lib64/plymouth/script.so" "$OVERLAY/usr/lib64/plymouth/"
cp -a "$WORK/rpm-root/usr/lib64/libply-splash-graphics.so."* "$OVERLAY/usr/lib64/"
cp -a "$WORK/rpm-root/usr/lib64/plymouth/renderers/"* "$OVERLAY/usr/lib64/plymouth/renderers/"
for pattern in 'libpng16.so*' 'libdrm.so*'; do
    find "$ROOT/usr/lib64" -maxdepth 1 -name "$pattern" -exec cp -a -t "$OVERLAY/usr/lib64" {} +
done
cp -a "$REPO/os/files/usr/share/plymouth/themes/marwanos" "$OVERLAY/usr/share/plymouth/themes/"
printf '[Daemon]\nTheme=marwanos\nShowDelay=0\n' > "$OVERLAY/etc/plymouth/plymouthd.conf"
# Overlay is appended as a gzip-compressed newc archive. Kernel initramfs loading
# supports concatenated archives; the original driver/microcode archive is intact.
cp "$WORK/source/initrd.img" "$WORK/patch/images/pxeboot/initrd.img"
(cd "$OVERLAY"; find . -print0 | cpio --null -o -H newc --quiet | gzip -1) >> "$WORK/patch/images/pxeboot/initrd.img"
cp -a "$OVERLAY/." "$ROOT/"
