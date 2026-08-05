# ADR 0005 — The compositor decision: gamescope as the session compositor

**Status:** Accepted
**Date:** 2026-08-05
**Decides:** D4 in [phase-0-plan.md](../phase-0-plan.md)
**Closes:** the spike scaffolded in [ADR 0004](0004-session-compositor-scaffold.md),
whose status was explicitly held at *Proposed* until this ADR existed
**Relates to:** [ADR 0003](0003-test-targets.md) (why this could only be measured on
bare metal), [ADR 0006](0006-shell-skeleton.md) (the client under test),
[ADR 0007](0007-single-display-appliance.md) (why only one screen is lit)

## Decision

**Plan A. gamescope runs as the session compositor, taking DRM master directly on
the NVIDIA card.** cage is not the appliance's compositor.

This was measured, not reasoned about. ADR 0004 said the question "cannot be
answered anywhere except on the Predator with the TV plugged in", and it was
answered across three hardware boots on 2026-08-05.

## Context

M1 asked one question — can gamescope take DRM master on the NVIDIA driver — and
ADR 0004 built everything around it so the spike would be spent measuring rather
than typing. It also wrote down, in advance, the five outcomes that would flip
the answer to plan B. That list is the reason this ADR can be short: none of the
five happened, and they were checked individually rather than in aggregate.

The measurement had to be unattended. D6 means no getty; `root` is `*` and
`player` is `nologin`; the Predator's wifi does not associate, so devmode ssh
needs ethernet — and there is exactly one machine, so there is nothing to ssh
*from*. The spike therefore ran as a root systemd oneshot injected into the
stick's ostree deployment, logging to the persistent journal, which is the same
pattern the VM harness established. Two of the three boots carried it.

## The evidence

| Boot | Window (CEST) | What it established |
|---|---|---|
| 1 | 18:54–19:01 | gamescope reaches ready and runs the shell on the external display |
| 2 | 19:30–19:38 | Survives screen off/on, input switch, and two HDMI replugs |
| 3 | 20:16–20:26 | ADR 0004 steps 4 and 5, both plans, unattended |

The oracle is the session script's own line, because `DisplayServer.get_name()`
says `X11` under both plans (ADR 0006) and is not evidence about D4:

```
marwanos-session: an external display is connected to the NVIDIA card
marwanos-session: starting gamescope: --backend drm --prefer-output HDMI-A-1,… \
    --prefer-vk-device 10de:2520 --force-windows-fullscreen
[gamescope] drm: selecting connector HDMI-A-1
[gamescope] drm: selecting mode 3440x1440@60Hz
marwanos-session: gamescope ready on DISPLAY=:0 WAYLAND=gamescope-0
marwanos-session: starting client /usr/lib/marwanos/shell/marwanos-shell
```

`cage` appears nowhere in boots 1 and 2. The fallback never fired.

**The card pinning works.** The shell reports
`adapter NVIDIA GeForce RTX 3060 Laptop GPU`, not the Intel iGPU. This is the
outcome ADR 0004 named as a flip condition and the reason `--prefer-vk-device`
is passed by PCI id rather than left to gamescope's own choice — two Vulkan ICDs
are installed on this chassis by design, so the wrong card is always available
to be picked.

**Measured behaviour, both plans (boot 3):**

| | gamescope | cage |
|---|---|---|
| Compositor reaches a running session with the shell | yes | yes |
| Client respawn after `kill -9` | **0.45 s** | **0.44 s** |
| Crash guard trips at 5-in-60 and holds | yes | yes |
| D5 dev-shell override engages | yes | **no — ran the baked client** |
| HDMI replug | survived, 4 cycles over boots 2 and 3 | **not measured** |

Respawn passes M3's "back at the grid in under three seconds" with an order of
magnitude to spare, on a USB-booted rootfs. The earlier worry that stick I/O
would dominate was wrong for process visibility; first-frame latency is a
separate number and is not this one.

## What would have flipped it, and why none of it did

Taken directly from ADR 0004's list, in its order:

1. **gamescope never reports ready.** It reported ready on every boot, within
   ~1 s of selecting the mode.
2. **Takes DRM master and the display stays black.** There was a picture every
   time, at the display's native mode, with no `--generate-drm-mode` or `-W/-H`
   needed.
3. **Survives a first boot but not a mode switch.** It survived screen off/on,
   an input switch, and four HDMI unplug/replug cycles. Across boot 2's two
   cycles the client kept the *same PID* (1383) — the session did not even
   restart, let alone die. gamescope re-read the EDID and reselected
   3440x1440@60Hz on its own each time.
4. **Composites on the Intel iGPU despite `--prefer-vk-device`.** It did not; see
   the adapter line above.
5. **The Godot export is unusable under gamescope and fine under cage.** It is
   usable under both. If anything the asymmetry runs the other way: the D5
   override worked under gamescope and silently did not under cage.

## Why gamescope rather than cage, given both work

cage came up, ran the shell, respawned it and tripped the crash guard. Plan B is
not broken, and ADR 0004 was right that "plan B winning is not a failure". The
decision is about control, and it was already visible in the packaging before
any of this was measured:

- **cage 0.2.0 cannot be told which output to use.** Its entire CLI is
  `-d -h -m extend|last -s -v`. `-m last` disables an output by enumeration
  order, not by name, and switches to a display plugged in mid-session
  (ADR 0004 finding 9, as corrected by ADR 0007).
- **Its GPU can only be pinned indirectly**, through wlroots' `WLR_DRM_DEVICES`.
  Left unset, wlroots moves the `boot_vga` device to index 0 — the iGPU on this
  chassis — so plan B would have composited on Intel and fed the NVIDIA output
  by cross-GPU blits. Pinning it also drops the eDP panel from enumeration
  entirely, which is where the 2026-08-05 spanning defect came from.
- **gamescope takes an ordered connector list and a Vulkan device by PCI id**, and
  `--force-windows-fullscreen` and `--hide-cursor-delay 1` are the two flags that
  make a client satisfy the acceptance wording rather than merely render.

An appliance whose display policy is expressed in flags is one whose behaviour
can be read out of the image. An appliance whose display policy is an
enumeration order is not.

## Consequences

- **The automatic fallback to cage goes away, and `/var/marwanos/compositor` with
  it.** ADR 0004 already committed to this: it "is right for a spike and wrong
  for a product: an appliance that silently changes compositor is an appliance
  whose behaviour cannot be reasoned about from the image." Removing both is now
  a work item, not a judgement call.
- Whether cage stays *installed* is a separate question and is deliberately not
  decided here. It costs image size and it is a second, untested display path in
  a product that has exactly one. That belongs in M4's escape-hatch audit.
- `gamescope` becomes load-bearing enough that its version is part of the
  image's behaviour. ADR 0004 already warns to read it out of the image with
  `rpm -q` rather than trusting a number written down; that now applies to every
  flag this ADR relies on.
- The session script's plan A/B branching can collapse, which removes the
  `--client-loop` re-exec path that plan B needs.

## What this ADR does not claim

Three things, stated plainly so nobody has to re-derive them.

- **The display under test was a Samsung Odyssey G85SD, not a TV.** The plan
  names "the actual TV over HDMI" because overscan, HDMI-CEC and the resolution
  handshake are "part of what Phase 0 must survive". None of those were
  exercised. This ADR decides D4; it does not close the TV risk.
- **A replug flicker was observed once and has not been explained.** On boot 2,
  after an HDMI replug, the panel flickered for minutes while the journal stayed
  completely silent — one modeset, a stable 16.68 ms swapchain, no kernel DRM
  messages, and the shell fully responsive throughout. It did not reproduce
  across two further replugs on boot 3. It is **not** a flip condition: ADR 0004's
  wording is a mode switch that "leaves a dead session or a black screen that
  does not recover", and the session provably recovered every time. It is
  recorded as an open observation.

  It is also **outside the expected usage envelope**, which is why it is not
  treated as blocking. This appliance lives plugged into one display. The mode
  switches that actually happen in normal use are the display being turned off
  and on and its input being changed away and back — both of which passed on
  boot 2. Physically unplugging the cable mid-session is a diagnostic action, not
  a user action. A defect reachable only by an action nobody performs does not
  gate a milestone; it stays on the list and gets closed when something else
  requires a hardware trip anyway.
- **The same replug was never performed under cage**, so it is not known whether
  the flicker is compositor-specific at all. That is the one measurement that
  would move it from "unexplained observation" to either a plan A defect or a
  driver-level one, and it remains outstanding.

## Open questions

1. **Is the replug flicker gamescope's, or below it?** One replug under cage
   answers it. Candidates on the nvidia-drm path, neither confirmed:
   `nvidia_drm.fbdev=1` with `console=tty0` letting fbcon repaint a connector
   gamescope is committing to, and adaptive-sync returning enabled after a
   hotplug on a QD-OLED panel, where low-frame-rate VRR flicker is a documented
   artefact.
2. **Why did the D5 override not engage under cage?** `resolve_client()` is
   compositor-agnostic, so either plan B's `--client-loop` re-exec resolves it
   differently, or the test lost a race — the harness created the override ~28 ms
   before the kill under cage and ~35 ms before it under gamescope. Not
   distinguishable from this run. Only matters if cage survives M4.
3. **`CAP_SYS_NICE`.** gamescope logs `No CAP_SYS_NICE, falling back to
   regular-priority compute and threads. Performance will be affected.` on every
   boot, and the appliance is perceptibly laggy. `/usr` is composefs-backed and
   read-only at runtime, so this needs `setcap cap_sys_nice+ep` in the
   Containerfile and a rebuild — it cannot be tested by injection.
4. **60 Hz on a 240 Hz panel.** gamescope selects `3440x1440@60Hz`. Whether the
   higher modes are offered over this cable is captured in the boot 3 report and
   has not been read out yet.
5. **`nvidia-smi` is not in this image**, so ADR 0004's step 0 check
   ("absent => userspace driver missing") cannot be run as written. It is a false
   alarm here — the driver is demonstrably present — and the substitute is
   `/proc/driver/nvidia/version`. ADR 0004's checklist should be corrected.
6. **ADR numbering.** ADR 0004's open question 5 notes that M1's checklist points
   at a `docs/adr/0001-session-compositor.md` that does not exist. The accepted
   decision is this file, 0005. The plan should be repointed.
