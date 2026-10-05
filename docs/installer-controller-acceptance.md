# Installer controller acceptance

Use a fresh branded ISO and a newly created disposable disk. The commands below
forward a real host uinput gamepad into the guest through QEMU. Input then passes
through the shipped installer bridge to GTK. The helper does not send QMP input,
invoke GTK, select storage, or initiate installation.

This is a prepared procedure; record the ISO checksum, screenshots, controller
JSONL and installer outcome after running it. Preparation alone is not evidence
of a successful installation. Coordinate with other VM users before allocating
4 GiB of guest memory.

The remaster sanitizes both `/osbuild.ks` and its included `/osbuild-base.ks`.
It preserves BIB's existing identities, OCI deployment, bootc switch, and
locale/network defaults, while removing automatic disk selection, partitioning,
erasure and reboot directives from both files. The normal graphical GRUB entry
is the explicit default with a three-second timeout; media-check remains
available, and the remaster refreshes and verifies its embedded checksum.

## Create the fixture and VM

Run as root on the Linux QEMU host, from the repository directory. Set `ISO` to
the final branded ISO. Its read-only USB medium and the new 80 GiB virtio disk
are the only storage drives attached; no host block device is passed to QEMU.

```bash
ISO="$(realpath /absolute/path/pc1-installer.iso)"
WORK="$(mktemp -d /var/tmp/pc1-installer-controller.XXXXXX)"
sha256sum "$ISO" > "$WORK/iso.sha256"
modprobe uinput
python3 tests/installer_controller_host.py serve \
    --socket "$WORK/controller.sock" --device-file "$WORK/controller.device" \
    --evidence "$WORK/controller.jsonl" --lifetime 7200 \
    > "$WORK/controller.log" 2>&1 &
printf '%s\n' "$!" > "$WORK/controller.pid"
for attempt in {1..50}; do
    [[ -s "$WORK/controller.device" ]] && break
    sleep 0.1
done
test -s "$WORK/controller.device"
PAD="$(cat "$WORK/controller.device")"
test -c "$PAD"
qemu-img create -f qcow2 "$WORK/install.qcow2" 80G
cp /usr/share/edk2/ovmf/OVMF_VARS.fd "$WORK/vars.fd"
qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -m 4096 -smp 4 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
    -drive "if=pflash,format=raw,file=$WORK/vars.fd" \
    -drive "if=none,id=stick,format=raw,file=$ISO,readonly=on" \
    -device qemu-xhci \
    -device usb-storage,drive=stick,removable=on,bootindex=1 \
    -drive "file=$WORK/install.qcow2,format=qcow2,if=virtio" \
    -device "virtio-input-host-pci,evdev=$PAD" \
    -vga virtio -display none -nic none \
    -qmp "unix:$WORK/qmp.sock,server=on,wait=off" \
    -serial "file:$WORK/serial.log" -daemonize -pidfile "$WORK/qemu.pid"
printf 'Acceptance directory: %s\n' "$WORK"
```

Allow the default normal setup boot entry to start automatically. If the boot
menu fails to advance, capture it and report that separately. The installer-only
controller bridge starts after Linux boots; it cannot control firmware menus.

## Drive the installer with the controller

Use screenshots through QMP solely for observation:

```bash
python3 scripts/installer-vm-control.py "$WORK/qmp.sock" shot "$WORK/welcome.ppm"
python3 tests/installer_controller_host.py status --socket "$WORK/controller.sock"
python3 tests/installer_controller_host.py tap r1 --socket "$WORK/controller.sock"
python3 tests/installer_controller_host.py tap square --socket "$WORK/controller.sock"
python3 tests/installer_controller_host.py axis left_x .7 --duration .5 --socket "$WORK/controller.sock"
```

The helper emits Linux/DualSense face-button codes: Cross/A clicks, Square/X
sends Space to activate the focused control, Triangle/Y toggles the installer
keyboard, Circle/B sends Escape, Options sends Enter. R1 sends Tab; hold L1 while
tapping R1 for Shift+Tab. Left-stick axes move the pointer. D-pad commands `up`,
`down`, `left`, `right` emit standard hat axes and become arrow keys. `press`
and `release` allow chords; `neutral` releases every held control.

Observe focus after each short command sequence. Screenshot before and after
each meaningful transition. Do not use the QMP helper's `key`, `type` or `click`
commands during controller acceptance.

Verify these checkpoints:

1. Branded setup appears; a supplied language default may skip welcome and open
   the summary directly. R1 changes focus and controller activation opens settings.
2. Installation summary appears. Enter a text field, toggle the keyboard with
   Triangle, navigate and enter a character, then dismiss with Circle. Capture
   the compact keyboard and verify that dismissal does not submit the form.
3. Open Installation Destination. The fresh **80 GiB virtio disk `/dev/vda`**
   is the sole writable target. Stock Anaconda may preselect it. Verify no writes
   occurred; explicitly deselect and reselect it with the controller, then confirm
   automatic partitioning. The installer USB remains read-only.
4. Return to the summary and explicitly activate Begin Installation through
   the controller. Capture progress and retain errors if installation fails.
5. Capture the completed Ready to play screen. Stop the VM, boot
   `install.qcow2` without the installer USB, and verify the PC1 shell starts.
   Keep the new disk and evidence until review completes.

`controller.jsonl` proves the fixture emitted each physical controller command;
screenshots and completed transitions prove the guest consumed those commands.
Neither record alone establishes controller-only completion.

## Finish

Stop only this acceptance VM and fixture:

```bash
python3 scripts/installer-vm-control.py "$WORK/qmp.sock" quit
python3 tests/installer_controller_host.py stop --socket "$WORK/controller.sock"
qemu-img info --output=json "$WORK/install.qcow2" > "$WORK/installed-disk.json"
```

If testing host-fixture unplug, quit QEMU before destroying the forwarded
device. The separate `tests/installer_controller_device.py` regression runs
inside a guest and covers bridge release on actual gamepad removal without
depending on a forwarded host device remaining attached to QEMU.
