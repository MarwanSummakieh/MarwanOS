# Candidate13 replacement image — October 7, 2026

Status: PASS for the replacement image, PC1 full reboot, and offline VM fresh
installation plus installed full reboot.

The requested replacement includes the current NVIDIA accelerated Xorg and
controller fixes, plus the startup correction discovered while testing
[candidate12](candidate12-replacement-20261007.md). Exact source:
`a38dce115dac453db2ffe35a38782492e02c7f60`, branch
`codex/automatic-game-metadata`.
[Build run 37661837411](https://github.com/MarwanSummakieh/MarwanOS/actions/runs/37661837411)
publishes only `candidate13-xorg-boot-20261007`; `latest` is unchanged.

## Boot corrections

The gamescope-specific link scrub now exits before stopping greetd or starting
Plymouth when no gamescope session is running. NVIDIA and virtual machines use
Xorg, so this removes an unnecessary restart and avoids the enforcing Plymouth
denial observed on PC1. Tests cover preserving Xorg and both successful and
failed gamescope cleanup.

PC1's obsolete image-scoped live hotfixes were backed up and disabled. Their
payloads are baked into this replacement. The old display hotfix had ordered
device coldplug behind local filesystem mounting, causing a maintenance prompt
even when its hash guard skipped the payload. Disabling it restored unattended
startup on the subsequent full reboot. This machine-local cleanup is separate
from the source change and is preserved in the release evidence.

## Validation

The exact clean Linux checkout is `/var/tmp/pc1-release-source-a38dce1`.
All component pins and the targeted boot regressions pass. The NVIDIA driver
and base/kernel remain pinned. Candidate13 independently passed direct NVIDIA
RTX 3070 rendering, the expected rendered pixel, automatic 3440×1440 at
174.96 Hz and one routed SDL DualSense before and after its full hardware reboot.

CI passed 251 backend tests (249 passed, two optional skips) and the controller
shell suite. Registry manifest verification and all seven baked source hashes
passed. PC1's staged deployment also matches those hashes, the exact source and
the pinned NVIDIA/gamescope package versions.

Immutable image:
`ghcr.io/marwansummakieh/marwanos@sha256:fe77aebbd90092e61a2120a5a01326c4c2ea43d2d4b6abe75f1cb09b84c162fd`.
Build version: `0.0.202610071750`.

PC1 booted candidate13 as `37d26e75-98ec-4866-b343-3c910cb49123`, then completed
a full `systemctl reboot` into `7aecdf18-6284-4178-ad78-8d412727b974`. Both boots
match the immutable image and exact source. The first postboot gate passed all
checks after its boot-success timer. The full reboot proof records normal
greetd shutdown and reboot, no prior-boot faults or cores, no forced kills and
no shutdown timeouts. Both candidate13 startup gates reject emergency mode,
device mount timeouts, obsolete hotfix activation and unnecessary Xorg bounce;
both passed. Enforcing SELinux remains enabled.

The owner confirmed that PC1's physical display returned to MarwanOS
automatically after the corrected full reboot, without a login prompt or
pressing Enter.

Direct NVIDIA GLX rendering and the expected pixel pass on both boots. DP-2
retains 3440×1440 at 174.96 Hz. SDL identifies one routed Sony DualSense as PS5;
the physical node is excluded and remembered controller slot identities are
unchanged. PC1's cached game metadata, artwork and history also passed the
software gate. The older candidate12 boot contained an Xorg core during its
link-scrub transition; it remains recorded in the upgrade-boundary evidence
and is not counted as a clean candidate13 reboot.

## Installation media

Raw media and the branded Anaconda installer are built from that exact digest
using pinned bootc-image-builder
`sha256:2b52843ea2bfda73b0a08d97e76b734393b1d3a804681b9fabb26723bd3a2f0b`.
Raw GPT, ISO boot records, appended EFI contents, embedded ISO checksum,
runtime directory permissions and the Windows ISO copy all passed verification.

Replacement ISO: `out/release-20261007-candidate13/MarwanOS-candidate13.iso`
(6,007,357,440 bytes). SHA-256:
`9138bfba4e37cd8b8972a1bed879d5b1f197b03cbd06ba067dd5b1147c4ab7d0`.
The adjacent `.sha256` file records the same digest.

The installer booted offline into the branded graphical setup. Its sole
destination is the new private 80 GiB virtio disk. Controller actions opened
destination selection, deselected/reselected the disk, confirmed automatic
partitioning, focused Begin Installation and activated it. QEMU disk maps prove
the destination remained entirely zero/unallocated before setup and immediately
before Begin Installation. QMP supplied observation and VM lifecycle control
only; all setup input came through the forwarded uinput controller and shipped
installer bridge.

## Fresh installation and installed reboot

Installation reached Complete / Ready to play. The installer VM was stopped,
and its consistency-checked new disk booted with no USB or ISO attached, using
only restricted host-forwarded SSH. The installed system booted as
`4a6bc246-82fa-491b-b839-2879487a5e7a` and completed a full `systemctl reboot`
into `09d7f39a-fe1e-465a-8dc8-df578be5ce00`.

All 15 installed health checks passed on both boots after their two-minute
boot-success timers: exact source/digest/origin, active system and user services,
no failed units, ready session and fresh heartbeat, enforcing SELinux with no
enforcing AVCs, no current-boot cores, recorded/hidden-menu GRUB success and
disabled development mode. The reboot proof also passed normal shutdown,
changed boot ID, no prior-boot faults/cores and no forced kills/timeouts.
Filesystem UUIDs and fstab remained unchanged.

The forwarded synthetic pad navigated the installed shell into Steam details
and back, then opened details again after reboot. Installed VirGL screenshots
use the VM's private Xvfb window; no guest keyboard or mouse input was injected.
This verifies controller input through the baked broker, not physical rumble.
The verified VM was cleanly powered off and its final qcow2 consistency check
passed. The controller fixture was stopped and its JSONL input trace preserved.

Retained installation disk:
`/var/tmp/pc1-final-install-vm.NLKkGC/target.qcow2`.
Retained installed-test overlay:
`/var/tmp/pc1-boot-vm.k40HNv/disk.qcow2`.

Fresh installation was verified in a disposable VM; PC1's physical disk received
the immutable image update and full reboot verification. Physical display
motion, audible sound, game rumble, multiplayer, Bluetooth and controller wake
retain their separately documented acceptance scopes. Automatic PC1 startup
is established by the boot journal, ready session and direct NVIDIA renderer.

Evidence and helpers: `out/release-20261007-candidate13`. The offline installer
uses only a private removable-media overlay and a new 80 GiB destination, with
no network or host block devices. Installed verification permits only restricted
host-forwarded SSH. Physical PC1 disks are not erased by that installation test.
