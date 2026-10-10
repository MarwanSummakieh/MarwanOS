# Steam display corruption — October 7, 2026

Status: accelerated NVIDIA Xorg display and automatic 174.96 Hz startup are
implemented; the owner confirmed smooth, stable Steam display and working
Silksong menu controls. A graphical-session restart passed. Replacement-image
and full-machine reboot acceptance remain pending. Earlier failed trials below
are retained as historical evidence.

The owner's phone recording shows a clean shell, Steam startup, a black interval,
then duplicated/offset startup graphics and bright horizontal bands. The owner
reports that it settles after idling and returns with activity. Disabling Steam
GPU acceleration made it worse and was undone.

## Live baseline

PC1 is running candidate11, source `cc19931`, build `0.0.202610071109`, boot
`077cbe6f-26e2-4c32-a2be-ea7830e169eb`. The connected monitor is a Samsung Odyssey
G85SD on DP-2, 3440×1440 at approximately 60 Hz, with an NVIDIA RTX 3070 and driver
610.43.03. Gamescope already runs `--force-composition` without adaptive sync.

While the owner confirmed that the physical monitor remained corrupted, an actual
gamescope screenshot showed a clean Steam Big Picture library. This points toward
scanout/output rather than Steam's rendered content, but screenshot capture can
change the composition path and is not itself proof of correct physical output.

The active primary framebuffer is XB30, modifier `0x300000000606014` (NVIDIA tiled),
3440×1440, pitch 13760. No NVIDIA Xid or gamescope kernel fault was found in the
sample. The boot link-scrub completed successfully at 14:07:58 UTC; it did not
prevent this later failure.

Steam had enabled `GAMESCOPE_DISPLAY_HDR_ENABLED=1`, despite HDR not being enabled
in the session's launch arguments. Setting that property to zero live did **not**
fix the physical corruption: the owner tested movement and confirmed it remained.
This excludes HDR enablement as a sufficient explanation, not every color-path
interaction. The session subsequently restarted independently of this test.

## Controlled scanout trial

The proposed gamescope patch adds `GAMESCOPE_DRM_FORCE_LINEAR`, affecting only
compositor-owned output images. Imported client textures keep their existing
modifiers and GPU acceleration. DRM output must advertise linear support and
Vulkan must support exporting the requested format; unsupported allocation fails
explicitly rather than silently selecting a tiled layout.

The trial preserves resolution, refresh rate, composition and color depth. Its
single-binary override has a timed rollback and does not replace controller or
shell changes being tested separately. Physical motion/transition observations
are required; a clean screenshot or successful startup is not a physical pass.

### Linear 10-bit trial: rejected by the driver

The first test package builds and all 11 existing ELF/lifetime regressions pass.
The temporary compositor starts, allocates linear XB30 buffers and publishes its
ready handshake, but DRM rejects its actual one-layer atomic test with `EINVAL`.
The console framebuffer remains scanned out. This is a **failed trial**, not a
working display. It was rolled back promptly; the original compositor resumed
normal tiled XB30 scanout. The timer was stopped after restoration.

This exposes a readiness limitation: the compositor handshake and shell heartbeat
can succeed without a committed application framebuffer. Future physical gates
must inspect actual scanout and atomic errors, not just process health.

### Linear 8-bit trial: also rejected by the driver

The second package builds successfully (binary RPM SHA256
`e9776fb5b799cf037198bb240aa3e747ad42ad1cd3071a4630325e8f4f2c1b19`).
Forcing XR24/AR24 output still produces repeated atomic `EINVAL` errors and leaves
fbcon scanned out. It was rolled back promptly. Linear output is therefore not
an accepted workaround on this bench, at either tested depth.

### Tiled 8-bit trial: physical failure

The same binary, with only `GAMESCOPE_DRM_FORCE_8BIT=1`, successfully scans out a
gamescope-owned XR24 framebuffer with NVIDIA's tiled modifier. This is an actual
display commit, independently checked through DRM state. Steam opened successfully
and the actual framebuffer remained XR24; Steam again requested HDR. No physical
result was received during the trial window. The owner subsequently confirmed
that it **still flickered like crazy**. This rejects the 8-bit workaround.

The timed recovery failed with `203/EXEC` / permission denied executing its
script from `/var/tmp`. The original compositor was restored manually and
verified scanning out a gamescope-owned tiled XB30 buffer. The override is
unmounted. Future recovery runs an installed interpreter with the recovery body
as an argument, rather than executing the temporary script. No production
session default has been changed.

The rejected linear/depth patch and its packages are retained under `out/` for
diagnosis. They have been removed from production packaging; gamescope remains
`3.16.23-1.pc1.3.fc43`.

### Accelerated Xorg: stable at 175 Hz on PC1

The image already contains the Xorg/Openbox compatibility backend used by VMs.
For a temporary physical test, the matching `xorg-x11-nvidia-610.43.03-1.fc43`
RPM was extracted from the **same pinned akmods sidecar**. Its signature verifies
on PC1. Its modules are staged outside the image; a temporary Xorg configuration
uses NVIDIA's driver, 24-bit output and `ForceCompositionPipeline=True`. The
session's OpenGL VRR policy remains disabled. The live controller-patched session is copied and overridden
temporarily, preserving the prior bind mount underneath. Recovery removes only
this trial's overlay and configuration and restarts the original session.

The first start encountered the prior display socket still occupied. A retry
started successfully. Standard socket security labels were checked and are
correct. `glxinfo -B` confirms direct rendering on RTX 3070, driver 610.43.03;
Xorg confirms a 3440×1440 screen. This is hardware acceleration, not llvmpipe.
Steam was tested in Big Picture. The owner confirmed that the display was
stable, then reported that the refresh rate felt very low.

`xrandr --verbose` measured 3440×1440 at 59.96 Hz, the EDID-preferred mode,
and advertised 119.96 and 174.96 Hz at the same resolution. Changing the active
output DP-2 to 174.96 Hz succeeded. A synchronized GL probe measured 174.973 FPS
(875 frames in five seconds); its intentional seven-second timeout then closed
the probe. The owner confirmed **“Smooth and stable”** after the switch.
The temporary refresh rollback timer was canceled after this confirmation.

Source now selects accelerated NVIDIA Xorg explicitly, includes the matching
Xorg driver package from the pinned sidecar, and selects the fastest advertised
progressive refresh at the preferred resolution. See ADR 0013. This is physical
acceptance of the observed Steam display, not of every game or controller.

After confirming accelerated rendering and the actual Big Picture window, the
startup recovery timer was stopped and the temporary trial was left active for
the owner's monitor observation. This avoids an answer arriving after the
backend has already changed. This temporary configuration was subsequently
replaced by the persistent, image-scoped hotfix described below.

`marwanos-nvidia-xorg-hotfix.service` is enabled on PC1 and checks the SHA256 of
`/usr/share/marwanos/build-info` before applying. Its payload is under
`/var/lib/marwanos/hotfixes/nvidia-xorg-20261007`. It preserves the already active
controller repair across reboot, uses the extracted matching NVIDIA modules,
and applies the source session with only external helper/module paths adapted
for the immutable installed image. A replacement image skips the override.

An actual greetd restart verified the production hardware-selection branch,
the generic NVIDIA OutputClass configuration, and automatic 174.96 Hz selection
before the Godot shell starts. The shell reports Vulkan on RTX 3070 and GLX
confirms direct NVIDIA rendering. No full reboot or replacement image boot has
been claimed. The startup recovery timer was canceled after verification.
The log also revealed that `AllowGSYNC` and `AllowGSYNCCompatible` are ignored
as standalone Xorg options; they are MetaMode attributes. Those ineffective
options were removed. A nominal 175 Hz selection and the OpenGL client policy
do not independently prove global VRR disablement for every presentation path.
The saved recovery script is
`/var/lib/marwanos/hotfixes/nvidia-xorg-20261007/rollback-body`; it restores the
earlier temporary Xorg trial at its original preferred rate.

## Duplicate Hollow Knight Home cards

The two records were a desktop shortcut (`Hollow Knight Silksong`) launching
`steam://rungameid/1030300` and the scanner's canonical manifest record
`steam.1030300`. The scanner now merges recognized Steam shortcuts by numeric
app ID when the manifest record is present. Desktop-only shortcuts and games
with the same title but different IDs remain visible. Filtering occurs after
cached sources are joined, so manifest removal does not require editing a
desktop file. The canonical game can reuse the shortcut's themed icon.

Native `steam.desktop` now uses `steamctl signin` to request Big Picture,
matching the game launch contract. Previously it emitted plain `/usr/bin/steam`,
which exposed desktop/Friends windows in the Xorg diagnostic.

Sixteen focused icon/Steam integration checks and five scanout checks pass. The bench now publishes one
Silksong record. The source fix is in `appscan`. A persistent, image-scoped bench
hotfix is installed as `marwanos-steam-shortcuts-hotfix.service`; it applies only
when the original scanner's SHA256 matches, and automatically skips a future
image with a different scanner. Its actual service application was verified
without rebooting or disturbing the controller changes.

## Silksong controller investigation

The owner's physical trace showed changing states on both the physical DualSense
and the broker's routed device while the game was in front. The game opened the
routed evdev node. This rules out a completely neutral broker output for that
trace; it does not establish that the game interpreted the controls.

Steam's per-game controller screen showed **Using the game's built-in support**.
Steam Input was enabled through that screen with Team Cherry's official gamepad
layout. A cold launch through the Home card then created a
`Microsoft X-Box 360 pad 0` application device. The broker now skips third-party
uinput application devices before opening them, and udev leaves them classified
as joysticks. Bluetooth UHID physical sources remain broker-owned. These changes
prevent a translated Steam Input pad being grabbed and routed back as hardware.
The source has 37 passing controller policy checks and a passing real Linux
uinput fixture. The image-scoped bench payload includes the guard.

The game opened the translated Xbox evdev node, whose udev classification remains
`ID_INPUT_JOYSTICK=1`. The broker retained one physical player rather than claiming
Steam's output. The owner confirmed **“Controller works now”** after testing
D-pad navigation and Cross selection. This accepts the observed Silksong menu
controls; force feedback and other games are separate acceptance scopes.

A diagnostic-only Steam start inherited the SSH account's D-Bus address and
failed to start its sandboxed web helper. That launcher was replaced with one
using the full actual player session environment and groups. Steam was stopped
normally and restarted successfully; sandboxing and GPU acceleration stay on.

The refresh, controller and duplicate-card changes have 61 focused policy/parser
checks passing in total, plus the real Linux uinput fixture. The Xorg session was
actually restarted and automatically selected 174.96 Hz. A full rebuilt image
and a full machine reboot remain untested in this investigation.

`scripts/inspect-pc1-scanout.py` rejects fbcon, missing modifier evidence, and
inactive CRTCs. Its five regression checks include the false-ready failure from
both rejected trials.

Local evidence: `out/pc1-steam-corruption-before.png`,
`out/steam-display-hdr-off.json`, and `out/steam-scanout-build.log`. These are
diagnostic artifacts, not release acceptance. Historical findings in
[the earlier NVIDIA investigation](flicker-nvidia-610.md) remain scoped to their
dated trials.
