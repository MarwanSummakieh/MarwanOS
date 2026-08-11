# The tearing, the day of elimination, and the driver swap

**Status: swap staged 2026-08-11; verdict pending the owner's next reboot.**
Whoever holds the pen after that reboot: fill in the verdict section at the
bottom. If the tearing is gone, this file *is* the NVIDIA bug report — send it.
If it is not, this file is the record that the driver branch was also
exonerated, and the next suspect list is at the bottom too.

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

## Verdict of the swap

_Pending the owner's reboot._

- Tearing **gone** at 610.57.04 → 610.43.03 carried an HDMI flip regression
  fixed upstream between .43 and .57. Report the table above to NVIDIA
  against 610.43.03 anyway: the elimination is complete and reproducible,
  and a fixed-later bug with a clean table is still a useful report.
- Tearing **unchanged** at 610.57.04 → the whole 610 open-module branch is
  suspect on this flip path. Next moves, in order: pin the previous major
  branch (an *older* akmods digest whose kmod matches an equally old base
  digest — pairs move together); failing that, the closed kmod sidecar
  (`akmods-nvidia`) as a diagnostic; and file the NVIDIA report with this
  table regardless. Do NOT reopen compositor, Steam, cable, port, VRR, or
  refresh-rate theories — they are measured out, above.
