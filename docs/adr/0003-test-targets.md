# ADR 0003 — Three machine roles: build host, VM target, bare-metal target

**Status:** Accepted
**Date:** 2026-08-02

## Context

The answer to Phase 0's open question 2 was "I need a VM to test." That is the
right answer for most of Phase 0 and the wrong answer for the part of Phase 0
that carries the most risk, so it needs splitting rather than accepting whole.

A VM on the Windows laptop cannot present an NVIDIA DRM device to the guest.
Hyper-V's discrete device assignment is Windows Server only; GPU-PV is a WDDM
paravirtualisation path that no Linux compositor consumes; and the Predator is a
hybrid-graphics laptop, which makes PCIe passthrough impractical even where the
hypervisor supports it. A Linux guest therefore sees `virtio-gpu` and runs on
Mesa.

That matters because M1's entire purpose is "can gamescope take DRM master on
the NVIDIA driver." Running that spike in a VM would produce a confident green
result about Mesa on virtio-gpu and tell us nothing about the question asked.
The same applies to the NVIDIA-specific half of M2: the modeset transition is one
of the likeliest sources of a boot flash, and it does not exist in a VM.

Meanwhile a VM is genuinely better than hardware for M0 — snapshots make
`bootc upgrade`/`rollback` testing fast and consequence-free.

## Decision

Three roles. Two of them are VMs on the Predator; the third is the Predator itself.

| Role | Machine | Covers |
|------|---------|--------|
| Build host | **WSL2 `FedoraLinux-43`** + podman | Everything. `podman build`, push, and `bootc-image-builder` |
| VM target | Hyper-V VM, 2 vCPU / 4 GB, snapshotted | All of M0. Most of M2 (GRUB, plymouth, getty masking, kargs). All of M3 |
| Bare-metal target | The Predator, booted from an external USB SSD | M1 entirely. The NVIDIA half of M2. Every acceptance gate that is filmed |

**Revision (2026-08-02, after testing):** the build host was originally specced as
a Hyper-V Fedora VM, on the assumption that `bootc-image-builder` needs
privileges WSL2 cannot give. That assumption was wrong. WSL2 provides
`/dev/loop-control`, device-mapper, xfs/ext4 and systemd as PID 1, and bib built
a 6.6 GB VHDX there in 299 seconds. The build VM is deleted from the plan; only
the *target* is a VM now.

**Bare metal is reached by USB, not dual-boot.** Windows is never repartitioned
and never at risk. This is what makes "I need a VM" and "I need real NVIDIA
hardware" both true at once without buying a second machine.

There are two ways to get there, and the second is preferred:

| Route | How | Trade-off |
|-------|-----|-----------|
| Installer ISO | `make-installer.sh anaconda-iso`, boot it, install to the USB device | Anaconda asks which disk to install to, *next to the Windows drive*. The one destructive step in the project |
| **Raw image** | `make-installer.sh raw`, write it to the USB device with Rufus in DD mode | No installer at all. The device is chosen once, on Windows, where names and sizes are visible. Preferred |

**A plain USB stick is enough to start; an SSD is a later requirement.** M1 only
asks whether gamescope can take DRM master on the NVIDIA driver, and a slow
device answers that as well as a fast one. M2 is where it changes: a 15-second
boot budget measured on flash memory is meaningless, so the timed and filmed
gates need a real USB 3.x SSD.

Size the device from the raw image (~15 GB), not the root filesystem. A nominal
16 GB stick usually formats to less than that, so **32 GB is the practical
minimum**.

**Acceptance gates are bare-metal only.** A gate passed in the VM is a smoke
test, not a pass. The M2 camera test in particular means the TV over HDMI.

## Consequences

- With the build VM gone, only one VM runs at a time, which 16 GB and four
  physical cores handle comfortably. WSL2 builds, then the target VM pulls.
- The laptop is a *hybrid-graphics* machine, so it is an imperfect stand-in for a
  desktop where NVIDIA is the sole DRM device. Drive the TV over HDMI (which on
  this chassis routes to the dGPU) and confirm with `loginctl`/`drm_info` which
  card actually owns the output before trusting any M1 result. If the internal
  panel is what gamescope grabs, the spike is measuring the Intel iGPU.
- Secure Boot is off on the target for Phase 0 (D7). On a USB SSD this is a
  firmware toggle affecting only what that machine will boot, and it is reversible.
- Phase 0's exit criteria stay honest: everything filmed happens on hardware that
  has the GPU the project is about.

## Addendum (2026-08-03) — the bare-metal target boots a UKI, and no VM can show you why

The first attempt to boot the raw image on the Predator (Acer PT314-51s,
firmware V1.10) turned up two findings that change how these three roles relate.

**The firmware cannot boot GRUB from USB.** It loads EFI binaries off the stick
without complaint — shim starts, GRUB starts — and then GRUB cannot read the
stick's own partition table. `ls (hd0)/` answers `unknown filesystem` and no
`(hd0,gptN)` devices appear at all. So the shim → GRUB → BLS chain is simply
unavailable on the one machine every filmed acceptance gate has to run on, and
no change to the image can repair it: the failing component is the firmware's
block layer as GRUB sees it.

**Decision: the bare-metal target boots a Unified Kernel Image.** Kernel,
initramfs and command line linked into a single EFI binary behind the
systemd-boot stub, installed at `EFI/BOOT/BOOTX64.EFI`, with `EFI/fedora` renamed
aside so nothing can chain back into GRUB. The firmware loads the whole ~350 MB
file by itself, through the path that already demonstrably works, and no
bootloader filesystem access ever happens. `scripts/make-usb.sh` post-processes a
`make-installer.sh raw` image into that shape.

What this does to the roles above:

- The bare-metal route is three steps now, not two: `make-installer.sh raw`,
  `make-usb.sh`, flash. The VM target is untouched and keeps booting GRUB
  normally, which is right — that is the path any eventual internal install uses.
- **The UKI is a copy, and it goes stale.** `bootc upgrade` on the bare-metal
  target rewrites the kernel, initramfs and BLS entry on the boot partition,
  none of which the firmware reads. Upgrade and rollback testing therefore stays
  a VM-target job, and the bare-metal target receives whole images. This sharpens
  the split this ADR argues for rather than softening it.
- Secure Boot stays off there, which D7 already required; the UKI is unsigned.
- This entire class of bug is invisible in a VM. The firmware is the component
  under test, and no hypervisor reproduces it.

**Second finding: VM storage attachment is not representative either.** Booted
via the UKI, the machine reached the initramfs and then timed out in
`dracut-initqueue` waiting for the root filesystem's UUID — while the identical
image booted to a login prompt in QEMU.

The diagnosis went through two wrong convictions before landing (2026-08-03,
final). First "missing initramfs drivers": disproved — `uas` and `usb_storage`
were modular and present, `xhci-pci` and `sd_mod` built into the Fedora kernel
(`=y`), and the kernel booted the image over *both* transports in QEMU. Then
"the stick's broken UAS implementation": also disproved — the per-device quirk
(`usb-storage.quirks=346d:5678:u`) changed nothing, because the transport was
never the problem.

**The actual cause: the image is smaller than the stick, and the resulting GPT
is invalid on the device.** A 14.9 GB GPT image written to a 29.3 GB stick
leaves the backup GPT header mid-disk and the protective MBR sized to the
image. Firmware and Windows tolerate this — the UKI boots — but GRUB and the
Linux kernel reject the partition table wholesale, so no `(hd0,gptN)` for GRUB
and no `/dev/sdX4` for the kernel, ever. Windows then auto-"repairs" the header
on insertion and corrupts the main partition table CRC, cementing the failure.
Proven by attaching the physical stick to WSL's kernel over usbipd: disk
visible, zero partitions, `sgdisk -v` reporting the CRC damage — and one
`sgdisk -e` later, all four partitions appeared with the exact UUIDs the boot
arguments name, and the next bare-metal boot reached login.

`scripts/flash-usb.sh` makes this unrepeatable: write from WSL, `sgdisk -e`,
then verify partitions, UUIDs and the boot binary checksum before any reboot.
The dracut drop-in and the `EXTRA_KARGS` quirk plumbing remain — insurance and
a lever, not fixes for this symptom.

**Third finding: a verified stick can still be dead on arrival, because the
host corrupts it after verification.** The same timeout recurred on a stick
`flash-usb.sh` had just passed, with the geometry repair intact. Cause: Windows
rewrites the GPT of every removable disk it enumerates, relocating the entry
array from LBA 2 to LBA 2016 in *two* writes (header, then array). Unplugging
between them leaves a header pointing at zeros and the only valid array
orphaned at LBA 2 — CRC invalid, zero partitions, same symptom, filesystems
untouched. Verified by experiment: given time to flush, Windows completes both
writes and the table stays valid; the corruption is strictly the interrupted
case.

The architectural lesson is the one this ADR keeps relearning: **verification is
only valid if nothing touches the artefact between the check and the boot.** A
flash pipeline that ends at "VERIFIED" and then hands the device back to the
host OS has not proven anything. So the stick is now unplugged physically while
still attached to WSL, never `usbipd detach`-ed, and `flash-usb.sh` gained a
`VERIFY_ONLY=yes` mode for re-checking a stick immediately before a boot plus a
hard `sgdisk -v` CRC gate — because `sfdisk`, `blkid` and `lsblk` all silently
fall back to the backup table and report success on a stick the kernel will
refuse.

**QEMU testing of USB images, calibrated by what each mode can prove:**

- `usb-storage` attachment (bulk-only) is the end-to-end rig — firmware → UKI →
  kernel → root — and is also the transport a quirked stick actually uses.
- `usb-uas` attachment exercises the kernel's UAS path, but **OVMF cannot boot
  from it** (it has no UAS driver of its own): pair it with QEMU's direct kernel
  boot (`-kernel/-initrd/-append`) instead of a firmware boot.
- Neither mode reproduces a *broken* UAS device. A green VM boot narrows the
  search; only hardware convicts the stick.

```bash
# kernel-UAS path (no firmware):
qemu-system-x86_64 -m 3072 -machine q35 \
    -kernel vmlinuz -initrd initramfs.img -append "root=UUID=... rw ..." \
    -device qemu-xhci,id=xhci \
    -drive if=none,id=stick,format=raw,file=disk.raw \
    -device usb-uas,id=uas,bus=xhci.0 \
    -device scsi-hd,drive=stick,bus=uas.0
```
