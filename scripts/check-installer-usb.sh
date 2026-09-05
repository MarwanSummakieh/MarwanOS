#!/usr/bin/env bash
# Boot a hybrid installer as USB mass storage, including the appended EFI path.
# Only a disposable qcow2 overlay is writable; no host disks are attached.
set -euo pipefail
ISO="$(realpath "${1:?installer ISO required}")"
WORK="$(mktemp -d /var/tmp/pc1-usb-vm.XXXXXX)"
OVMF="${OVMF:-/usr/share/edk2/ovmf/OVMF_CODE.fd}"
qemu-img create -f qcow2 -F raw -b "$ISO" "$WORK/stick.qcow2" 32G
qemu-system-x86_64 -enable-kvm -m 4096 -smp 4 -bios "$OVMF" \
    -device qemu-xhci \
    -drive "if=none,id=stick,format=qcow2,file=$WORK/stick.qcow2" \
    -device usb-storage,drive=stick,removable=on,bootindex=1 \
    -device usb-tablet -vga virtio -display none \
    -qmp "unix:$WORK/qmp.sock,server=on,wait=off" \
    -serial "file:$WORK/serial.log" -daemonize -pidfile "$WORK/pid"
echo "USB validation VM: $WORK"
echo "Use scripts/installer-vm-control.py $WORK/qmp.sock shot /absolute/path/frame.ppm"
echo "Send key ret to boot; quit to stop the VM."
