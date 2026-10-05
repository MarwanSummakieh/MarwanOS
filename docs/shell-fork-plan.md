# Which shell survives — Godot + mowser, or Electron

> **Goal:** Decide whether MarwanOS keeps its Godot shell and finishes mowser, or
> adopts the Electron shell and apps already written for the PC1 project and
> deletes mowser. Both work. This document exists so the choice is made on a
> measurement rather than on momentum.

**Status:** proposed, undecided. Written 2026-08-26.

**Relates to:** [ADR 0005](adr/0005-compositor-decision.md) (gamescope — unaffected
either way), [ADR 0006](adr/0006-shell-skeleton.md) (the Godot skeleton — this
fork can supersede it), [`steam-removal-plan.md`](steam-removal-plan.md) (ADR 0013
has to answer "what is the browser for" and this question lands in the same place).

**This is a bigger decision than the Steam removal and it is deliberately not
filed inside it.** Discarding one of two working shells should not arrive as a
sub-bullet of something else.

---

## The two candidates, measured

| | Lines | What it already covers |
|---|---|---|
| **Godot shell** (this repo, `main`) | **11,018** across 45 `.gd`/`.tscn` files | rail, cards, settings, setup, power, services, window profiles, kiosk — wired into the bootc image, the gamescope session, `appscan` and `winrun` |
| **Electron shell + apps** (PC1 repo, `console/`) | **29,341** JS/CSS/HTML | home/library, Files, 11-pane Settings, browser with tuned spatial navigation, OSK |
| **mowser** (this repo, `no-steam-installer` branch only) | ~1,400 C++ + 445 GDScript | CEF linked into the shell, offscreen-rendered to a texture. **Not on `main`.** |

The Godot shell is smaller but is *integrated*: it is the thing the image
currently boots. The Electron shell is larger and covers more surface, but has
never run on this stack.

## Why this is being asked now

The PC1 project was building the same console on the Windows NT kernel. That
line is being wound down, which puts a mature, controller-driven, PS5-shaped
shell — with a Files app, a real Settings, and a browser — in the same future as
this repository's Godot shell. Two shells, one console.

Neither was a bad call. **Each project rejected the other's choice for a reason
the other one then went and solved:**

- PC1's fork 1 rejected Godot as *"best-in-class for 1:1 motion/animation, native
  pad input"* but with no clean non-Microsoft browser embed — `gdcef` was the
  only route. MarwanOS chose Godot and wrote **mowser**, which is that embed.
- MarwanOS never considered Electron, because the browser problem looked like it
  needed solving *inside* Godot. PC1 chose Electron precisely to make the browser
  stop being a separate problem.

So this is a genuine fork with two working answers, not a mistake to correct.

## What Electron buys

**It deletes mowser, and mowser's permanent cost with it.**

mowser exists because the owner asked for *"my own custom made chromium that is
only the engine inside my launcher."* Electron is that same sentence, with the
engine already drawing the shell — no GDExtension, no CEF helper process, no
offscreen render to texture, no `mowser-helper` binary.

And `mowser.h` states its own price plainly: a fatal CEF initialisation calls
`abort()`, which is not catchable, so a browser failure **kills the shell** —
a black television, the one failure this project is organised against. It has
happened once already (2026-08-11, `.pak` files under a `resources/`
subdirectory). That risk exists because `libcef` is linked into a host process
that has something to lose. In Electron the browser is the shell's own engine;
there is no second initialisation that can take the appliance down.

It also brings the browser work described in
[the browser section below](#what-comes-across-either-way) for free rather than
as a port.

## What Electron costs

- **11,018 lines of Godot shell**, and ADR 0006 with them.
- **Motion fidelity.** The brief is a PS5 console UI. Godot is a game engine and
  is better at 1:1 animation than a DOM. PC1's own fork sheet says so.
- **A second Chromium in the image** — though if mowser lands this repo ships
  CEF anyway, so it is closer to a wash than it first looks.

## The four things people trip on, and where this repo actually stands

None of these are blockers. They are listed so nobody re-discovers them.

| Concern | Standing |
|---|---|
| **`chrome-sandbox` needs SUID root** | Already a solved pattern here. The Containerfile does exactly this class of build-time fix for mowser's `chrome-sandbox` and gamescope's `CAP_SYS_NICE`, because `/usr` is composefs and read-only at runtime. |
| **Gamepad input is weaker in Electron** than Godot's native input | PC1 already does not rely on the web Gamepad API — `PC1Host.exe` reads the pad and feeds events over stdio. On Linux the host reads evdev and does the same, and `hid-playstation` makes that easier than the Windows path was. |
| **The gamescope `STEAM_GAME=769` main-application slot** | No difference. Electron claims it exactly as Godot would. |
| **NVIDIA + Wayland + Chromium** GPU and video-decode flags | Real and fiddly, but this project has already fought this driver harder than most (see `flicker-nvidia-610.md`). |

## The one real risk — and it is against a stated gate

**Phase 0's exit gate: cold boot to a gamepad-navigable grid in under 15 seconds,
zero frames of text on camera.**

A Godot binary starts fast. Electron has to bring up Chromium — V8, a renderer, a
GPU process. This is the single place where the shell choice meets a number this
project has already committed to in writing.

It is probably survivable: most of that 15 s is firmware, kernel and NVIDIA
driver rather than the shell. But "probably" is not how a gate gets cleared, and
**this is the only part of the fork that cannot be reasoned about from a desk.**

---

## The spike that decides it

**Cost: about a day. Until it runs, further work on either shell may be thrown
away.**

### Why it is cheap

PC1's Electron shell **runs standalone on mock data when the host IPC pipe is
absent** — `console/shell/electron/main.js` pushes `mock=1` when `HOST_IPC` is
unset. So the spike needs no host port, no evdev bridge, no `appscan` integration
and no library. The real shell UI boots against fixtures.

The Windows-specific code in that main process is roughly 50 lines of Steam
registry discovery, which the spike simply does not exercise.

### Build

- [ ] Package the PC1 `console/` tree as a Linux Electron app (`--ozone-platform=wayland`)
- [ ] Lay it into a throwaway image layer alongside the existing Godot shell — do
      **not** replace the session's shell yet
- [ ] Set the `chrome-sandbox` SUID bit at build time, the same way the
      Containerfile already does for mowser. **The sandbox stays on**; measuring
      with `--no-sandbox` measures a configuration that will never ship
- [ ] A boot-time switch selects which shell the session starts, so both are
      measured on one machine in one sitting

### Measure

On the bare-metal target (RTX 3070 clears the Turing+ baseline), same machine,
same boot, alternating:

- [ ] **Cold boot → first frame of a navigable grid**, filmed, counted in frames
      rather than reported by the shell about itself
- [ ] **Zero frames of text** through the whole sequence
- [ ] The same two numbers for the **Godot shell**, this run, this hardware — an
      Electron number without a same-day Godot baseline is not a comparison
- [ ] Five cold boots each, worst case recorded rather than the median

### The call

| Result | Decision |
|---|---|
| Electron clears 15 s **with margin** | Adopt Electron. Delete mowser. Supersede ADR 0006. |
| Electron lands **near or over** the gate | Godot stays. Land mowser on `main` and port `guest-preload.js` into it. |
| Electron clears it, but only with the sandbox off | Godot stays. That configuration is not shippable. |

### What this spike does **not** settle

Animation fidelity — the other half of the fork — cannot be measured with a
stopwatch. If the boot number comes back ambiguous, that judgement is the owner's
to make with a pad in hand and both shells on the television. The spike narrows
the fork to one axis; it does not close it by itself.

---

## What comes across either way

This is worth stating because it is true under **both** outcomes, and it is the
part of PC1 most worth keeping.

PC1's browser injects `inject/guest-preload.js` (533 lines) into every page:
spatial link navigation across `a[href]`, buttons, form controls, ARIA roles,
`[onclick]`, `video` and open shadow roots; geometry scoring by pressed direction
with a cross-axis-overlap penalty; the highlight drawn inside the page in a
**closed shadow root** so it tracks scroll and layout for free and the page
cannot restyle it; scroll-and-rescan when nothing lies in the pressed direction;
occlusion checked only on the winning candidate, because `elementFromPoint`
forces layout and 1,300 candidates would blow the frame budget.

**That file is page-context JavaScript. It does not know or care whether the
embedder is Electron or CEF.** It is the hard, already-tuned work, and mowser
does not have it.

- **Under Electron** it comes across as-is.
- **Under Godot + mowser** it ports, but needs a `CefRenderProcessHandler` to
  inject it — and `mowser/src/subprocess.cpp` is 30 lines whose entire body is
  `CefExecuteProcess`. Standard CEF, but new code in a file that currently does
  nothing else.

Also portable under either: PC1's pad control-scheme table
(`console/apps/browser/README.md`) is a finished spec, and `dev/probe.js` (417
lines, scripted runs against real pages writing screenshots and a log) is a test
discipline neither shell has an equivalent of — and which mowser needs more than
Electron does, for the `abort()` reason above.

## Risks

| Risk | Standing |
|---|---|
| **The spike measures a strawman.** A hastily packaged Electron app is slower than a tuned one. | Time-box tuning to what ships: production flags, no devtools, no unpacked asar. If it fails, record *what was and was not tuned* so the number can be re-read later. |
| **Adopting Electron restarts integration from zero.** The Godot shell is wired to `appscan`, `winrun`, the session and the window profiles; the Electron shell is wired to a Windows host that is being deleted. | Real, and larger than the 29,341 lines suggest. The spike deliberately does not test this — it tests the one thing that can veto the choice outright. |
| **Deciding nothing.** Two shells, both half-fed. | The worst outcome available. If the spike is ambiguous, pick on the animation axis and move — a decided fork beats a maintained one. |
| **PC1's shell has never run on Linux at all.** | The spike is the first time. Expect a day of packaging before any number is trustworthy. |

## Open questions

1. **Does the Electron shell still make sense with its host deleted?** Its Files
   app, Settings panes and library all speak to `PC1Host.exe` over stdio. On this
   stack that host is `appscan`, `winrun` and systemd. The stdio JSON contract
   survives; the implementation behind it does not.
2. **If Electron wins, what happens to the Godot shell's integration work** —
   window profiles, the kiosk seam, the session wiring? Some is shell-agnostic
   and some is not, and nobody has drawn that line.
3. **If Godot wins, does mowser land on `main` before or after the Steam
   removal?** `main` currently has no browser at all: `shipped-apps` removed the
   Chromium flatpak on the rationale that mowser replaces it, and mowser never
   merged.
