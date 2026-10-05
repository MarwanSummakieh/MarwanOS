#!/usr/bin/env bash
# Boot a disposable overlay; the supplied disk image remains read-only.
set -euo pipefail
image="$(realpath "${1:?usage: boot-vm.sh disk.raw}")"
work="$(mktemp -d /var/tmp/pc1-boot-vm.XXXXXX)"
display="${PC1_VM_DISPLAY:-98}"
ssh_port="${PC1_VM_SSH_PORT:-2228}"
controller_args=()
if [[ -n "${PC1_VM_CONTROLLER_DEVICE:-}" ]]; then
    [[ "$PC1_VM_CONTROLLER_DEVICE" =~ ^/dev/input/event[0-9]+$ && -c "$PC1_VM_CONTROLLER_DEVICE" ]] || {
        echo 'PC1_VM_CONTROLLER_DEVICE must name an existing evdev device' >&2
        exit 2
    }
    controller_args=(-device "virtio-input-host-pci,evdev=$PC1_VM_CONTROLLER_DEVICE")
fi
format="$(qemu-img info --output=json "$image" | python3 -c 'import json,sys;print(json.load(sys.stdin)["format"])')"
qemu-img create -f qcow2 -F "$format" -b "$image" "$work/disk.qcow2"
cp /usr/share/edk2/ovmf/OVMF_VARS.fd "$work/vars.fd"
cookie="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
xauth -f "$work/xauthority" add "127.0.0.1:$display" . "$cookie"
Xvfb ":$display" -screen 0 1920x1080x24 -nolisten unix -listen tcp \
    -auth "$work/xauthority" > "$work/xvfb.log" 2>&1 &
xvfb_pid=$!
printf '%s\n' "$xvfb_pid" > "$work/xvfb.pid"
trap 'kill "$xvfb_pid" 2>/dev/null || true' ERR
sleep 1
kill -0 "$xvfb_pid"
export DISPLAY="127.0.0.1:$display" XAUTHORITY="$work/xauthority"
export LIBGL_ALWAYS_SOFTWARE=1
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -m "${PC1_VM_MEMORY_MB:-4096}" -smp 4 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
    -drive "if=pflash,format=raw,file=$work/vars.fd" \
    -drive "file=$work/disk.qcow2,format=qcow2,if=virtio" \
    -device virtio-vga-gl -display sdl,gl=on \
    -device qemu-xhci -device usb-tablet \
    "${controller_args[@]}" \
    -netdev "user,id=net,hostfwd=tcp:127.0.0.1:$ssh_port-:22" -device virtio-net-pci,netdev=net \
    -qmp "unix:$work/qmp.sock,server=on,wait=off" \
    -serial "file:$work/serial.log" \
    > "$work/qemu.log" 2>&1 &
qemu_pid=$!
printf '%s\n' "$qemu_pid" > "$work/qemu.pid"
echo "VM directory: $work"
echo "SSH: 127.0.0.1:$ssh_port"
echo "Stop with scripts/installer-vm-control.py $work/qmp.sock quit; the private display is cleaned up automatically."
# Keep the WSL client attached; an idle WSL distribution can otherwise shut down
# underneath daemonized VM processes. The display is entirely inside Xvfb.
trap 'kill "$qemu_pid" "$xvfb_pid" 2>/dev/null || true' EXIT INT TERM
wait "$qemu_pid" || { result=$?; cat "$work/qemu.log"; exit "$result"; }
