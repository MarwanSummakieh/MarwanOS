# The tearing: reproduced, recovered, and cornered to the link-after-training

**Status (2026-08-12, small hours — supersedes everything below, including
every previous status header). THE CAUSAL LOOP IS CLOSED AND REPRODUCIBLE:**

1. **Trigger: a freshly-trained link.** A cold boot or a physical
   unplug/replug of the display cable puts the link in a state where the
   gamescope session shimmers on a static screen and tears under motion. This
   was demonstrated on demand: the owner replugged DP mid-session and the
   artifact returned immediately.
2. **Recovery: a plymouth modeset cycle.** Stop greetd → `plymouthd` +
   `plymouth show-splash` → quit → start greetd, and the same session on the
   same connector is clean. **Demonstrated twice**, the second time against a
   deliberately re-broken link. The clean state then survives everything:
   greetd restarts (6+), GPU at 53°C, memory clock locked at 7001, memory
   clock flapping freely, gamescope color management on and off. Only a fresh
   link training breaks it again.
3. **The artifact needs BOTH halves.** On the same freshly-trained marginal
   link, plymouth's splash is stable (3/3 across its own modesets) while
   gamescope shimmers. The scanout difference is measured, not guessed:
   plymouth scans an **8-bit XR24 linear** framebuffer with no color
   pipeline; gamescope scans a **10-bit XB30 NVIDIA block-linear**
   (`modifier=0x300000000606014`, decoded: uncompressed, kind 6) framebuffer
   through nvidia-drm's color pipeline with live PQ-125 EOTF/inverse-EOTF
   colorops. Fresh link + plymouth-style scanout = clean. Settled link +
   gamescope-style scanout = clean. Fresh link + gamescope-style scanout =
   the artifact.
4. **Transport does not matter; driver version does not matter.** Both HDMI
   ports and DP-1 show it; 610.43.03/7.1.5 and 610.57.04/7.1.8 show it
   identically. The same panel, same cable, same 3440x1440@100 over HDMI is
   clean on a different laptop — so it is this machine's side, in whatever
   the NVIDIA driver family negotiates onto a fresh link that plymouth's
   legacy 8-bit modeset then settles.

**Eliminated this session, each at n≥3 and mostly blind** (details in the trial
log): the compositor's composition flag, the shell (vkcube control), the HDMI
ports, the HDMI transport itself (DP identical), the driver version, GPU
temperature (still clean at 53°C), and GPU memory-clock flapping — measured
flapping P3↔P5 every ~7s on an idle screen, but clean with it flapping and
shimmering with it locked, so it is out in both directions.

**The workaround this arms** (not yet built): a boot-time "link scrub" — after
the first session is up, bounce the display through one plymouth cycle. Boot
already runs plymouth BEFORE greetd and still tears, so the order matters: the
healing transition observed is specifically gamescope-modeset →
plymouth-modeset → gamescope-modeset. Cost: one ~10s splash flash shortly
after the shell first appears. Ugly, mechanical, and it worked 2 out of 2
times tonight. n=2, so build it as an experiment, not as a triumph.

**For the NVIDIA report**, the sentence this file existed to find: *on an RTX
3070 Laptop (10de:2488), open kernel modules 610.43.03 and 610.57.04
identically, a freshly-trained HDMI or DP link shows static-image sparkle and
motion tearing when scanning a 10-bit XB30 block-linear framebuffer with
active color-pipeline PQ colorops, is clean scanning an 8-bit XR24 linear
framebuffer on the same link state, and becomes permanently clean for the
10-bit path after one legacy 8-bit modeset cycle — surviving all subsequent
atomic modesets until the link is physically retrained.*

---

**The finding that reordered the investigation: THE ARTIFACT IS PRESENT ON A
COMPLETELY STATIC SCREEN.** With nothing moving — no input, no animation, no frames being
delivered that differ from the last one — the owner reports shimmer and sparkle
on the picture. That single observation moves the fault below every layer this
investigation has spent three days in. A compositor that is presenting the same
unchanged pixels cannot tear them; a shell that is drawing nothing cannot ghost.
Whatever is corrupting the image is doing it **after the GPU has finished with
the frame**, which means the signal on the wire or the hardware driving it.

**It is also no longer honest to call this a coin flip.** Eighteen judged trials
produced three clean verdicts. A 1-in-6 rate is not a 50/50 variable flipping
across identical boots; it is much better explained by an artifact that is
*nearly always present* and is *sometimes not noticed* — which is exactly how
2026-08-11's "tearing is gone", followed hours later by "it tears", came about.
The per-modeset variability is real (severity genuinely moves between restarts,
and a marginal link re-trains at every modeset), but the previous status header
overstated it into a coin flip and then let that coin flip excuse everything.

## What this session actually did

Nineteen `systemctl restart greetd` trials plus one non-shell control, on the
bench, with the owner as the instrument and **the two native-resolution
configurations blinded** — the owner was told nothing about which trial was
which, and consecutive trials at the same resolution are visually identical, so
there was nothing to infer from. Blinding matters here specifically: this
investigation has produced three confident wrong answers and every one of them
was scored by someone who knew what they were hoping to see.

The 1920x1080 arm could not be blinded — a 16:9 mode on a 21:9 panel is
obvious — and that is stated rather than papered over, because it is also the
arm with the best score and the one most likely to be flattered by the
monitor's own upscaler blurring a high-frequency artifact.

### The trial log, all of it, including the boring ones

| # | Output mode | Composition | Port | Verdict |
| --- | --- | --- | --- | --- |
| 1 | 3440x1440@60 | on | HDMI-A-1 | **Clean** |
| 2 | 3440x1440@100 | on | HDMI-A-1 | Tearing |
| 3 | 1920x1080@60 | on | HDMI-A-1 | Tearing |
| 4 | 3440x1440@100 | on | HDMI-A-1 | Tearing |
| 5 | 1920x1080@60 | on | HDMI-A-1 | **Clean** |
| 6 | 3440x1440@60 | on | HDMI-A-1 | Worse |
| 7 | 3440x1440@100 | on | HDMI-A-1 | Tearing |
| 8 | 1920x1080@60 | on | HDMI-A-1 | **Clean** |
| 9 | 3440x1440@60 | on | HDMI-A-1 | Worse |
| 10 | 3440x1440@60 | **off** | HDMI-A-1 | Tearing |
| 11 | 3440x1440@60 | on | HDMI-A-1 | Tearing |
| 12 | 3440x1440@60 | **off** | HDMI-A-1 | Tearing |
| 13 | 3440x1440@60 | on | HDMI-A-1 | Tearing |
| 14 | 3440x1440@60 | on | HDMI-A-1 | Tearing |
| 15 | 3440x1440@60 | **off** | HDMI-A-1 | Tearing |
| — | 3440x1440@100, **vkcube instead of the shell** | on | HDMI-A-1 | Tears identically |
| — | 3440x1440@100, **screen completely static** | on | HDMI-A-1 | **Shimmers/sparkles** |
| 16 | 3440x1440@100 | on | **HDMI-A-2** | Tearing |
| 17 | 3440x1440@100 | on | **HDMI-A-2** | Tearing |
| 18 | 3440x1440@100 | on | **HDMI-A-2** | Tearing |
| 19 | 3440x1440@100, shell pillarboxed at 1920x1080 | on | HDMI-A-2 | (config change, not judged) |
| 20 | 2560x1080@100 requested | on | HDMI-A-2 | **Void** — see below |
| 21 | 3440x1440@100 on **610.43.03 / 7.1.5**, static | on | HDMI-A-2 | **Shimmers** |
| 22 | 3440x1440@100 on **610.43.03 / 7.1.5**, moving | on | HDMI-A-2 | Tearing |

### The DP night session (2026-08-12, owner connected a DP cable; all on 610.43.03 / 7.1.5)

All of these ran at 3440x1440@60 — the booted (old) image does not know the
`hundred` profile, so the stock session falls back to `steady`/`-r 60`. Mode
verified from the journal per trial as before.

| # | What | Verdict |
| --- | --- | --- |
| DP1–DP3 | gamescope, fresh DP link, 3 restarts | Shimmers/tears, 3/3 |
| — | memclock watch: P3↔P5 flap (5001↔810) every ~7s on an idle static screen | measured |
| — | memclock **locked** 5001, static screen | Still shimmers |
| P1–P3 | plymouth splash, no gamescope, same mode (verified in DRM state), 3 modesets | **Stable, 3/3** |
| — | gamescope again after the plymouth cycle, stock config | **Clean** |
| A | gamescope, `GAMESCOPE_COLOR_MANAGEMENT_DISABLE=1` | Clean |
| B | gamescope, stock (blind interleave) | **Clean** — kills the CM theory |
| C | gamescope, CM disabled again | Clean |
| — | GPU heated to 53°C, mem locked 7001 / gfx 1305 | **Still clean** — kills the temperature theory |
| — | owner **replugs DP** (fresh link training) | **Shimmer returns** |
| — | plymouth cycle repeated against the re-broken link | Splash stable; **gamescope clean again after** |

Objective facts pulled from debugfs/NVML during the above: gamescope does
**not** page-flip while the screen is static (same fb id over 10s), so flips
are out; gamescope's scanout buffer is XB30 10-bit block-linear, uncompressed
(modifier `c=0`); plymouth's is XR24 8-bit linear; nvidia-drm's
`color_pipeline` parameter defaults on and keeps PQ-125 EOTF colorop pairs
active in the plane pipeline even with gamescope's color management disabled
(`nvidia_drm.color_pipeline=0` exists and was NOT yet tried — it needs a karg
via a direct BLS edit and became moot for tonight once the link-state
mechanism was found, but it is the right first lever if the 10-bit/colorop
path needs to be split from the link-training half).

### Found in passing, and it is a real image bug

The current `:latest` (the post-revert image the bench now boots) is
**internally mismatched**: kernel modules are 610.43.03, but the userspace is
610.57.04 (`/usr/lib64/libnvidia-ml.so.610.57.04`, and the flatpak GL
extension is `nvidia-610-57-04`). The revert moved the akmods sidecar digest
back and did not move the userspace packages with it. Rendering and NVML
demonstrably work anyway on the GSP path, but every conclusion about "the
610.43.03 driver" on this boot is really about that mixed pair, and the
Containerfile should either weld the two or assert they match.

Every trial's mode was verified from the journal (`drm: selecting mode ...` and
the shell's own `screen 0: ... refresh ...`) before its verdict was recorded, so
no verdict is about a configuration that did not actually run. Trial 20 is void
for exactly that reason and is kept because a void trial is a result: gamescope
did **not** synthesise the requested mode, it fell back to a listed one and
selected 3440x1440@**60**. `--generate-drm-mode cvt` does not get a 21:9
low-bandwidth mode out of this connector.

### Scores

| Configuration | Clean / trials |
| --- | --- |
| 3440x1440@100, composited, HDMI-A-1 | 0 / 3 |
| 3440x1440@100, composited, HDMI-A-2 | 0 / 3 |
| 3440x1440@60, composited | 1 / 6 |
| 3440x1440@60, **not** composited | 0 / 3 |
| 1920x1080@60 output | 2 / 3 |
| **Total** | **3 / 18** |

## What is now excluded, and how

Each of these is a claim about evidence, not a hunch. Where the old elimination
table had one observation against a symptom nobody had characterised, these have
three or more against a measured 1-in-6 base rate.

**`--force-composition` is not the variable. Six blind trials, one mode.** Three
with the flag and three without, at 3440x1440@60, interleaved, all six torn.
This flag was added on 2026-08-10 to fix ghosting, the ghosting survived it, and
until now it had never been tested more than once in either direction. It does
nothing for this symptom and the ghosting it was supposed to fix is not
something it fixes.

**The shell is not the cause.** `vkcube` — a different client, a different
renderer, none of the shell's code — was run fullscreen under the same
gamescope at 3440x1440@100, and its rotating cube shows the same displacement
and trails. This control had never been run: for three days every single
observation in this investigation was of the Godot shell's rail scrolling, so
"the shell" was never on the suspect list and was never eliminated either. It is
eliminated now.

**The port is not the cause. Three trials.** The owner moved the cable to the
laptop's second HDMI port (confirmed in sysfs: HDMI-A-1 disconnected, HDMI-A-2
connected) and all three trials at 3440x1440@100 tore. The old table's "BOTH
HDMI ports → identical tearing" row was N=1; it now has n=3 behind it.

**The panel, the cable and the mode are cleared — by the owner, not by us.** The
same monitor, over the *same cable*, at *3440x1440@100 or higher*, over HDMI, on
a different laptop, is clean. That is the strongest single fact in this file and
it was obtained by asking one question. It means the fault is on this machine's
side of the connector.

**Frame delivery is not the cause**, which is the static-screen observation
above and is what makes everything else in this section make sense. No
compositor flag, no refresh rate, no scanout path and no client can explain a
picture that breaks up while it is not being redrawn.

## The driver was separated after all, and it is not the cause

The 610.43.03 / kernel 7.1.5 deployment turned out not to need any bootloader
surgery: `ostree admin status` showed it **already staged**. The bench was
rebooted into it and confirmed on the target — `uname -r` 7.1.5-101.fc43,
`modinfo -F version nvidia` 610.43.03, `NVIDIA UNIX Open Kernel Module …
610.43.03` in dmesg — with everything else held still: stock session (greetd
restored from the pre-trial backup), `hundred` profile, HDMI-A-2, same cable,
live mode verified at 3440x1440 / 99.99 Hz.

| Driver | Kernel | Static screen | Under motion |
| --- | --- | --- | --- |
| 610.57.04 | 7.1.8-100 | Shimmers | Tears (0/6 clean at this mode) |
| 610.43.03 | 7.1.5-101 | **Shimmers** | **Tears** |

So the driver swap that started all of this was never going to fix anything, in
either direction. The trade the previous status header described — "610.43.03
tears / 610.57.04 is clean" — was one lucky observation in six on a symptom that
is nearly always present, and there is no trade. The remaining honest reason to
prefer one pin over the other is the *performance* report, which is untested at
power and confounded with the kernel, and which now has nothing pulling against
it.

### And the auto-update timer had already fired

The staged deployment was not left over from anything deliberate. Found the same
evening: `rpm-ostreed-automatic.timer` was enabled and active with
`AutomaticUpdates: stage`, and it had run 22 minutes earlier, resolved `:latest`
— the reverted image, carrying 610.43.03 — and staged it. **The next reboot was
going to change the driver under the investigation with nobody knowing.** Any
observation made across that reboot would have compared two drivers while
believing it was comparing two boots of one.

The timer is now masked (`systemctl mask --now rpm-ostreed-automatic.timer`,
machine-local, reversible with `unmask`). Note that masking is per-deployment
`/etc`, so it must be re-applied after booting a different deployment. And note
what pinning does and does not do: it protects a deployment from garbage
collection; **it does not stop a newer one becoming the default boot.** The
2026-08-11 warning about `rpm-ostree kargs` being "an upgrade in disguise" was
right about the mechanism and too narrow about the trigger — nothing had to be
typed at all.

## What is NOT separated, and this is the honest limit

The driver *version* is now separated and eliminated. What is **not** separated
is "this chassis's HDMI hardware" from "the NVIDIA Linux driver in general",
because the one clean reference — the other laptop — changed the GPU *and* the
operating system at the same time. Two readings survive, and both are outside
this repository's reach:

- **This laptop's HDMI output is marginal at these rates.** Fits the static
  shimmer, fits the severity moving across modesets (a marginal link re-trains
  at every modeset), fits the weak improvement at lower pixel clocks, fits both
  drivers behaving identically.
- **Both NVIDIA Linux branches program this chassis's link badly** — drive
  strength, scrambling/SCDC, bit depth — in a way the other laptop's stack does
  not. A driver can absolutely produce static corruption; "software can't do
  that" is not an argument available here. This reading is still a filable NVIDIA
  bug, and the fact that two branches fourteen point-releases apart are identical
  makes it a long-standing one rather than a regression.

Separating these needs something this bench cannot currently offer: the same
laptop, same port, under a different operating system; or a DisplayPort cable,
which the owner does not have. Until one of those exists, the file should not
claim to know which.

Note also that the resolution gradient is weak and confounded. 1920x1080 scored
2/3, but a 16:9 mode on a 21:9 panel is upscaled by the *monitor*, and upscaling
softens exactly the kind of high-frequency sparkle being judged. A better score
there may be a blurrier picture rather than a healthier link.

## What this means for the product, which is the part that outlives the bug

The appliance is meant to drive a TV, and the owner's stated next target is
**4K at 60 Hz**. That is not an easier signal than the one failing today — it is
the same class or worse. 3840x2160@60 in RGB 8bpc is about **594 MHz** of TMDS
character rate; 3440x1440@100 is about 582 MHz. If this machine cannot hold 582
MHz cleanly, it will not hold 4K60 RGB either, and the plan should not assume
otherwise.

The routes that actually buy margin, in order of how much they cost the picture:

- **HDMI 2.1 FRL.** A different signalling scheme entirely rather than faster
  TMDS, and the sink advertises HDMI Forum support. If the driver negotiates FRL
  the margin question changes shape completely. Worth measuring before assuming
  anything, because it is the only route that costs nothing.
- **YCbCr 4:2:0.** Halves the rate for 4K60. Cheap in bandwidth, visible on UI
  text, and this connector currently reports `ycbcr_420_allowed=0`.
- **Lower refresh.** 4K at 30 Hz is unusable for a games appliance; 1440p or
  1080p at 60 is the realistic fallback and is what the trial data weakly
  favours.

None of these is a fix for the fault. They are what a product does about a link
it cannot fully trust.

## The trial harness, which is still installed

Under `/etc/marwanos-trial/` on the bench. Nothing in the image was modified and
no build was pulled, because the bench's booted deployment is pinned to a driver
`main` no longer carries and pulling is the one thing that must not happen here.

- `bin/gamescope` — a shim ahead of `/usr/bin/gamescope` on `PATH`. It rewrites
  the output mode (`-W/-H`), the nested resolution (`-w/-h`) and the refresh
  (`-r`) from a one-line file, can subtract `--force-composition` (`NOCOMPOSITE`)
  and can split the two resolutions (`NESTED=<w>x<h>`). Every unusable input —
  absent file, malformed line, mistyped token — execs the real gamescope with the
  session's own unmodified argument list, because the alternative on a machine
  with no console is a black television.
- `session` — sets `PATH` and execs the image's own session script, unchanged.
- `round` — runs a list of trials: write mode, restart greetd, dwell, then print
  what the journal says was *actually* selected.
- `mode` — the current trial's one line.
- `revert` — restores `/etc/greetd/config.toml` from the backup taken before the
  first edit and restarts greetd onto the stock session.

**greetd is back on the stock session** (`revert` run again at the end of the
DP night session), so the harness is installed but inert — it changes nothing
until greetd is pointed at it again. It survives on both deployments' `/etc`,
so it is there for the next round without re-uploading anything. The harness
gained two pieces during the night: the session file now sources
`/etc/marwanos-trial/env` (VAR=value lines, allexport) so per-trial environment
reaches gamescope, and `round2` runs env-varying trials the way `round` runs
mode-varying ones. `/root/nvml_clocks.py` and `/root/nvml_lock.py` (NVML via
ctypes; the image has no nvidia-smi) watch and lock GPU clocks.

**The bench was left as the owner chose**: DP cable connected, stock session,
native 3440x1440@60, in the healed-link state — clean at handoff. A reboot or
a replug re-rolls the fresh-link dice until the link-scrub workaround exists.

The pillarboxed configuration tried during this session —
`3440 1440 100 NESTED=1920x1080 -S fit`, native 3440x1440@100 on the wire with
the shell rendered at 1920x1080 and pillarboxed inside it — was reverted with
the rest. It fixes the *shape* of a 16:9 picture on a 21:9 panel and changes the
link not at all; it is not a tearing workaround and was not chosen as one. It
also costs sharpness, since the UI is upscaled 1.33x to fill the output. If it
is wanted for real it belongs in the image as a display profile, not in a
machine-local shim.

## Corrections to earlier records in this file

- **The GPU is an RTX 3070 Laptop, not a 3060.** `10de:2488` is GA104M, and both
  gamescope and vkcube name it `NVIDIA GeForce RTX 3070`. Every earlier version
  of this document says 3060. An NVIDIA report with the wrong part number is
  worth very little, so this matters more than a typo normally would.
- The EDID's own limits, decoded this session: preferred detailed timing is
  3440x1440@60 at **349.25 MHz**; the range-limit descriptor declares **50–120
  Hz**, 30–162 kHz, and a **590 MHz** maximum pixel clock; the HDMI Forum block
  declares a 600 MHz maximum TMDS character rate while the older HDMI 1.4 block
  in the same EDID says 340 MHz. The 100 Hz mode therefore runs at about 98% of
  the ceiling the monitor declares for itself.
- `-W/-H` **do** move the DRM output mode on this connector, not just the nested
  surface — verified directly (`drm: selecting mode 1920x1080@60Hz` with the
  shell reporting 59.96). Only `video=` kargs are inert.

---

Everything below this line is the record as it stood before this session. It is
kept because it documents what was tried, and because two of its confident
verdicts being wrong is itself part of the history. **Read none of its
conclusions as current.**

## Symptom

Heavy tearing and ghosting on the bench appliance. Not brightness pulsing —
tearing: horizontal displacement lines under motion, plus ghost trails. (Now
known to be present without motion as well.)

## Hardware and stack

| Piece | Exactly |
| --- | --- |
| GPU | NVIDIA RTX 3070 Laptop (10de:2488) — *corrected; this file said 3060* |
| Driver | 610.57.04 open kernel modules on the bench's pinned deployment; `main` is pinned to 610.43.03 |
| Panel | Samsung Odyssey G85SD, 3440x1440 QD-OLED, over HDMI (DP unused by design — TVs are HDMI) |
| Cable | PS5-certified Ultra High Speed HDMI — *cleared: clean on another laptop at the same mode* |
| Compositor | gamescope 3.16, `--backend drm`, DRM master, no desktop underneath |
| OS | MarwanOS (bootc image on ublue-os/base-main:43), kernel 7.1.8-100.fc43 |
| Kargs | `nvidia-drm.modeset=1`, `nvidia_drm.fbdev=1`, `video=HDMI-A-1:3440x1440@100` |

## The old elimination table (2026-08-11, one day, all N=1)

Kept as a record of what was tried. The rows are **not** exonerations: each was
one observation, and at the time nobody knew the artifact's base rate. Several
have since been re-tested properly and are listed in "What is now excluded".

| Theory | Test | Result |
| --- | --- | --- |
| Steam's background client | Zero Steam processes (pgrep-verified) | Tears — reported *worse* |
| gamescope layering / direct scanout | `--force-composition` + `--disable-layers` | Tears |
| 60 Hz panel starvation | 100 Hz confirmed live | Tears "a lot" |
| 60 Hz itself | 59.90 confirmed live | Tears |
| Async flips | No `--immediate-flips` anywhere in the session | Tears |
| Monitor VRR interaction | OSD Adaptive Sync off | Tears |
| Cable | PS5-certified Ultra High Speed | Tears |
| Port | BOTH HDMI ports | Identical tearing |
| fbdev console path | `nvidia_drm.fbdev=0` booted | Identical |
| `video=` mode forcing | `video=HDMI-A-1:3440x1440@100` karg | Inert |

## The driver swap, and why it was reverted

610.43.03 → 610.57.04 was swapped on 2026-08-11 and reverted the same day on the
owner's report: **"this broke performance completely, no game runs well
anymore."** Checked before reverting, none of which explained it: the driver
loaded (`NVRM: 610.57.04`), gamescope was on the GPU, the Flatpak GL extension
matched, Runtime D3 was disabled, there were no Xid errors, `cap_sys_nice` was
intact, and the `hundred` profile's compositing cost was identical in the
previous boot.

**The confound, still unresolved:** an akmods kmod is built against one exact
kernel, so the swap moved 610.43.03 → 610.57.04 *and* kernel 7.1.5-101 →
7.1.8-100 together. "The new driver is slow" and "the new kernel is slow" have
never been separated. The performance half of that report may also have been
N=1; it was never repeated.

The tearing half of that report — "610.57.04 fixes it" — is now known to be one
of the three clean observations in six, and is not a finding.
