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
