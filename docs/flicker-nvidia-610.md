# The tearing, the day of elimination, and the driver swap that was reverted

**Status (2026-08-11, end of day): 610.57.04 was tried and REVERTED. It did not
buy its way in — the owner reported that game performance collapsed across the
board on it. The image is pinned back at 610.43.03, tearing and all.** The
elimination table below still stands and is still the material for an NVIDIA
report; what changed is that "just move to a newer driver" is now a measured
dead end rather than an untried idea.

## Symptom

Heavy tearing and ghosting on the bench appliance. Not brightness pulsing —
tearing: horizontal displacement lines under motion, plus ghost trails.

## Hardware and stack

| Piece | Exactly |
| --- | --- |
| GPU | NVIDIA RTX 3060 Laptop (10de:2488) |
| Driver | **610.43.03 open kernel modules** (ublue akmods sidecar, landed in the image ~2026-08-02) |
| Panel | Samsung Odyssey G85SD, 3440x1440 QD-OLED, over **HDMI** (`card1-HDMI-A-1`; DP unused by design — TVs are HDMI) |
| Cable | PS5-certified Ultra High Speed HDMI |
| Compositor | gamescope 3.16, `--backend drm`, DRM master, no desktop underneath |
| OS | MarwanOS (bootc image on ublue-os/base-main:43), kernel 7.1.5-101.fc43 at the time of measurement |
| Kargs | `nvidia-drm.modeset=1` (image default), `nvidia_drm.fbdev=0` tested both ways |

## The elimination table (all measured 2026-08-11, one day, one machine)

Every row below was tested live on the bench with the tearing present, and the
instrument for the mode rows was the session's own `screen 0:` journal line —
not an assumption about what the compositor did.

| Theory | Test | Result |
| --- | --- | --- |
| Steam's background client | Zero Steam processes (pgrep-verified, zero GPU handles) | Tears — reported *worse* |
| gamescope layering / direct scanout | `--force-composition` + `--disable-layers` (maximally conservative pipeline) | Tears |
| 60 Hz panel starvation | 100 Hz confirmed live (`screen 0: refresh 99.99`) | Tears "a lot" |
| 60 Hz itself | 59.90 confirmed live | Tears |
| Async flips | No `--immediate-flips`, no async env vars anywhere in the session | Tears (sync flips confirmed) |
| Monitor VRR interaction | OSD Adaptive Sync off | Tears |
| Cable | PS5-certified Ultra High Speed | Tears |
| Port | BOTH HDMI ports | Identical tearing |
| fbdev console path | `nvidia_drm.fbdev=0` booted | Identical |
| `video=` mode forcing | `video=HDMI-A-1:3440x1440@100` karg | Inert — DRM backend takes EDID-preferred regardless |

One observed correlation survives: the tearing's severity changes across
**modesets** — identical config minutes apart went "worse" then "stopped"
across a compositor restart that re-trained the HDMI link. That is consistent
with a link/flip-training fault, not with any of the software rows above.

## Verdict of the elimination

With Steam absent, composition forced, both refresh rates, sync flips, VRR
off, a certified cable, both ports, and the fbdev path all individually
eliminated, what remains is the **610.43.03 open-kernel-module KMS/HDMI flip
path** itself. The driver landed in the image ~2026-08-02 (dmesg akmods
stamp) — a week before the reports — which is regression-shaped.

## The experiment this commit arms

The image's driver comes entirely from the pinned
`ghcr.io/ublue-os/akmods-nvidia-open:main-43` sidecar digest (the
fedora-multimedia repo is excluded by name for every package the sidecar
ships, so the digest IS the driver pin). The sidecar publishes no
per-driver-version tags, so the branch is chosen by choosing the digest.

Swapped 2026-08-11: **610.43.03 → 610.57.04** (the newest available; same
branch, fourteen point-releases ahead), paired with the base digest whose
kernel (7.1.8-100.fc43) the new kmod is built for. Instruments after the
owner's reboot, over SSH:

```
journalctl -b -t marwanos-session | grep "screen 0:"
```

```
dmesg | grep -i "nvidia.*610"
```

## Verdict of the swap: REVERTED — performance collapse

The bench booted 610.57.04 (image 43.20260811.1, kernel 7.1.8-100.fc43) and
the owner's report was immediate and unambiguous: **"this broke performance
completely, no game runs well anymore."** The pin was reverted the same day.

What was checked on the bench *before* reverting, so that the revert is a
measured decision rather than a flinch — none of these explain it:

| Suspected | Measured | Verdict |
| --- | --- | --- |
| Driver failed to load / wrong module | `NVRM: 610.57.04`, `nvidia_drm` + `nvidia_modeset` + `nvidia_uvm` all loaded | Healthy |
| Compositor fell back to software | gamescope on `NVIDIA GeForce RTX 3070`, `selecting mode 3440x1440@100Hz` | On the GPU |
| **Flatpak GL extension missing** (the classic: host driver moves, Steam's sandbox has no matching GL, everything drops to llvmpipe) | `org.freedesktop.Platform.GL.nvidia-610-57-04` **and** `GL32.` both installed from flathub | Not it |
| GPU stuck in a low-power state | Runtime D3 `Disabled by default`, power state `D0`, Video Memory `Active` | Full power |
| GPU faults | no `Xid`, no NVRM errors in dmesg | Clean |
| `CAP_SYS_NICE` lost in the rebuild (would degrade frame pacing globally) | `getcap`: `cap_sys_nice=ep` present | Intact |
| The `hundred` display profile's compositing tax (`-r 100 --force-composition`) | **Identical in the previous boot**, on the OLD driver, with Hollow Knight running under Proton 10.0 | Constant across both boots — not the new variable |

That last row is the load-bearing one. The compositing profile is a real and
permanent cost, but it did not change between the good boot and the bad one,
so it cannot be what changed. The only variable was the image.

**THE CONFOUND, stated plainly rather than buried:** the akmods kmod is built
against one exact kernel, so the base image and the driver sidecar are welded
and can only move together. This swap therefore moved 610.43.03 → 610.57.04
*and* kernel 7.1.5-101 → 7.1.8-100 *and* a day of base packages, in one step.
"The new driver is slow" is the leading hypothesis, not a proven one; "the new
kernel is slow" has not been separated from it. Separating them needs a base
bump with the driver held still, which the welding makes awkward — a
deliberate experiment, not a side effect of the next bump.

## Where this leaves the tearing

Both known states are now bad in different ways, which is worth saying out
loud so nobody re-runs this loop by accident:

- **610.43.03** (pinned, shipping): games run well, panel tears.
- **610.57.04**: games run badly. Its effect on the tearing was never
  separately reported and is now unknown.

Next moves, in rough order of cost:

1. **Ask what 610.57.04 did to the tearing before spending anything else.** If
   it fixed it, the problem becomes "find the performance cause on the newer
   driver", which is a much better problem than the one we have. If it changed
   nothing, the whole 610 open-module branch is suspect and step 2 is next.
2. **An older pair** — an akmods digest carrying a driver *older* than
   610.43.03, with the base digest whose kernel it was built against. This is
   the "previous stable branch" idea, and note it is a pair hunt, not a
   one-line change.
3. **The closed kmod sidecar** (`akmods-nvidia` rather than
   `akmods-nvidia-open`) purely as a diagnostic: if the closed module does not
   tear, the fault is specific to the open module's flip path, which is
   exactly the sentence an NVIDIA bug report wants.
4. **File the report regardless.** The elimination table above is complete and
   reproducible, and it is worth sending whether or not we ever find a
   workaround.

Do NOT reopen compositor, Steam, cable, port, VRR, or refresh-rate theories —
they are measured out in the table at the top of this file.
