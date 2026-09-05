# PC1 USB installation

The PC1 media uses the first-party PC1 wordmark, original MarwanOS artwork and
pale boot background. Anaconda retains responsibility for storage validation,
partitioning, deployment, progress, error reporting and completion.

## Flow

1. Boot the USB in UEFI mode. Choose **Set up PC1 – Powered by MarwanOS**.
   The menu waits for input; its troubleshooting entries include compatibility
   graphics and recovery. Secure Boot must be disabled for this OS image.
2. Choose a language. The welcome screen explains the setup stages and controls.
3. Review keyboard, language, time zone and networking. The OS payload is on the
   USB, so downloading the OS is not required. Existing administrator public
   keys are preserved from the source media; bench mode is not enabled.
4. Open **Installation Destination**, check the drive's identity and capacity,
   and choose a storage layout. Anaconda handles space reclamation and encryption
   dialogs. Return with **Done**. Unselected drives are not installation targets.
5. Review the setup. **Begin Installation** is disabled while required choices
   are incomplete. Selecting it commits the chosen storage operations. Reclaiming
   or formatting existing partitions destroys their data.
6. Keep power and the USB connected while actual deployment progress runs.
   Installer errors remain visible; success is shown only after installation
   tasks have completed. A failed install is not advertised as recoverable by
   cancellation after partitioning has begun; reboot the media to retry.
7. Select **Restart** on completion. Remove the USB when the screen goes dark,
   then boot from the installed internal drive.

## Controller input

The installer-only bridge supports standard Linux gamepad event mappings:

| Control | Action |
|---|---|
| Left stick | Move pointer |
| A / cross | Left click |
| D-pad | Arrow keys |
| R1 / RB | Next focus |
| Hold L1 / LB + R1 / RB | Previous focus |
| X / square | Space / activate focused control |
| B / circle | Escape / close dialog |
| Y / triangle | Open on-screen keyboard when a text field is focused |
| Start | Enter |

Keyboard and mouse remain available. The on-screen keyboard also opens with F8,
includes letters, numbers and common punctuation, and preserves password masking.
Done commits the entry; Escape discards it. Controller hotplug is polled every two
seconds; disconnection releases held virtual keys. Firmware and GRUB controller
support depends on the machine; the bridge starts in the Linux installer.

## Build

Run as root in Fedora 43 Linux/WSL with squashfs-tools, xorriso, ImageMagick,
grub2-tools-extra, DejaVu Sans, Python, dnf, rpm2cpio, cpio and mtools available:

```bash
bash scripts/make-branded-installer.sh out/marwanos-installer.iso /var/tmp/pc1-installer.iso
python3 -m unittest discover -s tests -p test_installer_branding.py -v
```

The builder refuses to overwrite its input or an existing output. It creates a
unique work directory under `/var/tmp` and prints it for inspection. It preserves
the source ISO's OCI payload and boot records, replaces the runtime and boot
presentation, and rebuilds the kickstart from an allowlist of identity commands.
It deliberately does not carry through automatic partitioning, disk selection,
reboot, development markers or arbitrary source `%post` commands. The base
kickstart remains the bootc deployment contract.

The graphical Plymouth additions use Fedora's signed
`plymouth-plugin-script` and `plymouth-graphics-libs` 24.004.60-20.fc43 packages,
matching the original runtime generation. A new gzip/newc overlay is appended
to the unchanged original initramfs. Drivers and early microcode are preserved.
Network access is required to obtain those two build dependencies.

The output is an installer for the OS snapshot embedded in the source ISO.
Remastering does not update that OS payload to the current working tree.
For a new OS snapshot, build the OS and source installer first.

After VM validation, use `scripts/flash-iso.sh` with the verified USB device
identity. It checks USB transport, writes the ISO and compares a complete
read-back SHA-256. Do not treat a file copy onto a FAT USB as bootable media.

## Validation on 2026-09-05

- Booted the remastered installer under QEMU/KVM with UEFI and a disposable
  40 GiB disk. Inspected the graphical PC1 boot menu, animated Plymouth splash,
  welcome, setup, storage, progress and completion screens.
- Completed an interactive install to that virtual disk. Anaconda reported
  completion and the bootc post-install marker was emitted. Restart remained
  disabled during deployment and became available on completion.
- Opened the on-screen keyboard in the actual welcome search field, entered
  `de`, selected Done and observed the language list filter to German and Dutch.
- The controller service starts in the installer target. A synthetic Linux
  gamepad verified the actual daemon's keyboard toggle, D-pad, pointer events
  and release of a held key when the controller disconnects. Reproduce inside
  the installer with `python3 tests/installer_controller_device.py`.
- Five regression tests cover unattended-kickstart removal, identity requirements,
  incompatible runtime rejection, controller deadzone/D-pad release, and ensuring
  that the keyboard-toggle button does not submit a form.

These checks do not establish physical controller, TV, firmware or installed
NVIDIA-session behavior. The source OS payload is the existing August 12 image.
USB writing and complete read-back verification are separate evidence, only
available after the physical device is connected and flashed.

### USB boot-path correction

The initial VM check used a virtual DVD. A subsequent USB mass-storage test
found that `/images/efiboot.img` and the actual appended EFI system partition
still contained the source installer menu. Updating `/EFI/BOOT/grub.cfg` in
the ISO alone did not update the menu loaded through the USB EFI partition.
The builder now updates all three locations. `check-installer-efi.py` verifies
GPT checksums and compares the appended partition to the updated FAT image.

For an existing branded ISO, create a separate corrected artifact:

```bash
bash scripts/sync-installer-efi.sh out/pc1-installer.iso out/pc1-installer-usb.iso
bash scripts/check-installer-usb.sh out/pc1-installer-usb.iso
```

The USB test uses a disposable 32 GiB overlay and no target disk. Verify the
PC1 boot menu and that selecting setup reaches the graphical welcome screen.
This complements the earlier installation test; it does not reproduce a
particular physical machine's UEFI behavior.

The corrected `out/pc1-installer-usb.iso` was tested through this 32 GiB
USB mass-storage path: the branded menu appeared and selecting setup reached
the graphical welcome screen. The appended EFI image comparison and GPT
checksum checks passed. Its SHA-256 is
`a8eb6bd2644fb05163167162cf1cf1ca9fde5fb200d87e455cd4df13d071c245`.

The reported `efidisk.c:531: invalid buffer alignment -2017877944` occurs
before Linux loads. GRUB rejects a firmware block-I/O alignment value;
`you need to load the kernel first` is the consequent loader error. The menu
correction is a confirmed packaging repair, not proof that this separate
hardware error is fixed. Inspect the actual written USB and its checksum
before attributing that failure to the ISO, firmware or storage device.
