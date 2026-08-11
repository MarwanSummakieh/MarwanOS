# The tearing, the day of elimination, and the driver swap that was reverted

**Status (2026-08-11, LATEST — supersedes everything below): THE TEARING IS
INTERMITTENT PER BOOT, and no single-boot test in this file proves anything.**

Measured: the bench booted 610.57.04 and the owner reported "tearing is gone".
It was rebooted with NOTHING changed — same image digest 383d90b3, same driver
610.57.04, same kernel 7.1.8, same `hundred` profile, same 99.99 Hz confirmed in
the journal — and it tore again. Same everything, opposite result.

**So every verdict recorded in this file was N=1 against a random variable.**
That includes the ones that read as discoveries: killing Steam "stopping" it,
`flat` "not stopping" it, and 610.57.04 "fixing" it. The elimination table below
is still a useful record of what was TRIED, but it is not proof that any of
those things were exonerated — a test that runs once cannot exonerate anything
when the symptom flips on its own across identical boots.

**THE REAL SHAPE**: the variable is per-modeset, not per-configuration. It was
visible earlier and misread — "identical config, minutes apart, gave 'worse'
then 'stopped', the difference being a compositor restart" — which is the same
coin flip, seen once and explained away.

**METHODOLOGY FROM HERE, non-negotiable**: no configuration may be called good
or bad on fewer than 3 boots (or 3 `systemctl restart greetd` cycles, which
re-roll the same dice more cheaply). Record every trial, including the boring
ones. A run of 3 clean starts is weak evidence; 5 is worth acting on.

**Previous status, now known unreliable and kept only as history: "610.57.04
FIXES THE TEARING; it also runs games badly; the image is pinned back at
610.43.03."** The performance half may also have been N=1.

The verdict arrived after the revert, which is the coordination failure this
file's own "next moves" list was written to prevent: the swap was reverted on
the performance report alone, while the question it was made to answer — what
did it do to the tearing — was still unasked. Asked and answered 2026-08-11 by
the owner, on the bench, booted on 610.57.04: **"tearing is gone"**. Two days of
elimination end here, and the cause is named: the tearing is the NVIDIA
**610.43.03** open-kernel-module flip path.

So the choice is no longer "find the cause". It is a trade, and both sides are
measured:

| Pin | Tearing | Games |
| --- | --- | --- |
| 610.43.03 (shipping now) | **tears** | fast |
| 610.57.04 | **clean** | slow |

**AND THE TRADE MAY BE FALSE, which is the next thing to test rather than
assume.** The swap moved TWO things at once: the driver 610.43.03 → 610.57.04
*and* the base kernel 7.1.5 → 7.1.8, because an akmods kmod is built against one
exact kernel and the pair moves together. Nothing has separated "610.57.04 is
slow" from "7.1.8 is slow" — see the Containerfile's own note. Until that is
split, "the newer driver runs games badly" is one of two candidate sentences,
and the other one has a different fix.

The elimination table below stands and is still the material for an NVIDIA
report — which is now a much sharper report than it was, because it names a
version that fixes it.

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
- **610.57.04**: **tearing gone** (owner, 2026-08-11, on the bench), games run
  badly.

Step 1 below is now ANSWERED and struck through; the live question is step 1a.

1. ~~Ask what 610.57.04 did to the tearing before spending anything else.~~
   **Done: it fixes it.** So this is no longer a hunt for the cause — it is a
   trade between two known-bad states, and the work is to break the trade.
1a. **Separate the driver from the kernel, because the swap moved both.**
   610.43.03 pairs with base kernel 7.1.5 and 610.57.04 with 7.1.8, so the
   performance report accuses two suspects at once. Find an akmods digest for
   610.57.04 built against 7.1.5 (or any pair that holds one variable still)
   and the answer falls out in one boot. If the kernel is the slow half, the
   trade dissolves entirely: 610.57.04 on 7.1.5 would be clean AND fast.
1b. **Failing that, make it a choice rather than a default.** Both pins work;
   they are simply good at different things. A build-time switch — or an owner
   who knowingly runs the clean-but-slow image while games wait — beats
   shipping the tearing silently, which is what the revert did.
2. **An older pair** — an akmods digest carrying a driver *older* than
   610.43.03, with the base digest whose kernel it was built against. This is
   the "previous stable branch" idea, and note it is a pair hunt, not a
   one-line change. Lower priority now that a KNOWN-GOOD-for-tearing driver
   exists.
3. **The closed kmod sidecar** (`akmods-nvidia` rather than
   `akmods-nvidia-open`) purely as a diagnostic: if the closed module does not
   tear, the fault is specific to the open module's flip path, which is
   exactly the sentence an NVIDIA bug report wants.
4. **File the report regardless.** The elimination table above is complete and
   reproducible, and it is worth sending whether or not we ever find a
   workaround.

Do NOT reopen compositor, Steam, cable, port, VRR, or refresh-rate theories —
they are measured out in the table at the top of this file.
