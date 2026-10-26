# ADR 0013 — Accelerated Xorg for NVIDIA displays

**Status:** Accepted for PC1; other NVIDIA hardware requires physical acceptance
**Date:** 2026-10-07
**Supersedes:** ADR 0005's direct gamescope backend on connected NVIDIA displays

PC1's RTX 3070 and Odyssey G85SD repeatedly corrupt the physical display when
Steam animates under gamescope, while compositor screenshots remain clean.
Disabling HDR and using tiled 8-bit output did not resolve it. Linear output
failed NVIDIA's atomic tests at both tested depths. No claim is made about the
precise driver defect; the evidence is recorded in
[the investigation](../steam-display-corruption-20261007.md).

Use the existing Xorg/Openbox/xcompmgr session on connected NVIDIA displays,
with the NVIDIA Xorg and GLX server modules from the same pinned sidecar as the
kernel and userspace driver. Use 24-bit output and ForceCompositionPipeline.
OpenGL clients retain the session's `__GL_VRR_ALLOWED=0` policy. VMs retain Mesa Xorg. Other GPUs retain
gamescope. This is an explicit hardware selection, not a runtime crash fallback.

Select the fastest progressive refresh advertised at the monitor's preferred
resolution after Xorg starts. Do not synthesize timings or enable inactive
outputs. PC1 initially selected the EDID-preferred 3440×1440 at 59.96 Hz; this
looked slow to the owner. Switching to the advertised 174.96 Hz mode measured
174.973 synchronized GL frames per second. The owner then confirmed
**“Smooth and stable”** with Steam. This does not certify every game or long
running session.

The compositor environment must identify Xorg and disable gamescope WSI so
Steam and the shell use their existing Xorg window lifecycle. Controller
routing remains independently managed. HDR and gamescope-specific display
profiles are not acceptance claims for this backend.

The live bench override is scoped to its original image and skips a replacement
image. The source change supplies the matching package and configuration for
future images; a complete replacement image has not yet been built or booted.
