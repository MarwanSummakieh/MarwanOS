# The tearing: twenty trials, and the first evidence that points below the software

**Status (2026-08-11, evening — supersedes everything below, including the
previous status header): THE ARTIFACT IS PRESENT ON A COMPLETELY STATIC
SCREEN.** With nothing moving — no input, no animation, no frames being
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

## What is NOT separated, and this is the honest limit

The other-laptop test changed **two** things at once — a different GPU *and* a
different operating system with a different driver. So "the panel, cable and
mode are fine" is solid, but **this laptop's HDMI transmitter has not been
separated from this laptop's driver**. Both remain live:

- The GPU's HDMI output on this chassis is marginal at these rates, in a way the
  other laptop's is not. Fits the static shimmer, fits the per-modeset severity
  changes (link training re-runs at every modeset), fits the weak improvement at
  lower pixel clocks.
- The NVIDIA driver programs this link badly — drive strength, scrambling, SCDC,
  bit depth — in a way Windows on the other machine does not. A driver absolutely
  can produce static corruption; this is not a "software can't do that" argument.

Note also that the resolution gradient is weak and confounded. 1920x1080 scored
2/3, but a 16:9 mode on a 21:9 panel is upscaled by the *monitor*, and upscaling
softens exactly the kind of high-frequency sparkle being judged. A better score
there may be a blurrier picture rather than a healthier link.

## The next experiment, and it is cheap

**Boot the old driver locally.** The 610.43.03 / kernel 7.1.5 deployment tree is
still on disk at
`/ostree/deploy/default/deploy/3bf1e336…0/` (confirmed with `modinfo -F version`
on its `nvidia.ko.xz`) but has **no BLS entry**, so it is not currently
bootable. Writing a third entry in `/boot/loader/entries/` is machine-local,
purely additive, reversible by deleting the file, and touches neither the pinned
deployment nor `:latest`. If the static shimmer is present on 610.43.03 as well,
driver *version* is out and the transmitter becomes the leading suspect; if
610.43.03 is clean on a static screen across three trials, it is a driver
regression and the report writes itself.

That is the one remaining experiment that separates the two live suspects, and
it costs a reboot rather than an image build.

## HAZARD, found while working and not yet acted on

`rpm-ostreed-automatic.timer` is **enabled and active** on the bench, with
`AutomaticUpdates: stage`, and it next fires roughly six hours after this was
written. When it does it will resolve `:latest`, stage it, and make it the
**default boot** — which means the next reboot lands on 610.43.03 and the
pinned 610.57.04 deployment silently stops being what the machine runs. The pin
protects the deployment from garbage collection; it does not stop a newer one
becoming default. Masking the timer is a one-line machine-local change and has
not been made without asking.

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

**greetd's config is currently pointed at the trial session** and the live mode
is `3440 1440 100 NESTED=1920x1080 -S fit` — the owner's chosen configuration:
native 3440x1440@100 on the wire with the shell rendered at 1920x1080 and
pillarboxed inside it. Note plainly what that does and does not do: it fixes the
*shape* of a 16:9 picture on a 21:9 panel, and it changes the link not at all —
the wire still carries 3440x1440@100. It is not a tearing workaround and was not
chosen as one. It also costs sharpness, since the UI is now upscaled 1.33x to
fill the output.

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
