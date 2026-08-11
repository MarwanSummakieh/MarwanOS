# ADR 0009 — A terminal, behind the flag that already exists

**Status:** Accepted — implemented in the same change
**Date:** 2026-08-11
**Relates to:** D5 and D6 in [phase-0-plan.md](../phase-0-plan.md); the session's
dev override in [ADR 0004](0004-session-compositor-scaffold.md); the shell's
surfaces in [ADR 0006](0006-shell-skeleton.md); the launch seam in
[`launcher.gd`](../../shell/src/launcher.gd)

## Context

The owner asked for a terminal, reachable from the shell.

The tree says four times that there isn't one, and each of those sentences is
load-bearing rather than decorative:

- [`README.md`](../../README.md) — "no desktop, no login screen, no terminal".
- [`appctl`](../../os/files/usr/lib/marwanos/appctl) — the whole seam exists
  because removing a flatpak "meant a terminal, and this appliance has no
  terminal".
- [`settings_screen.gd`](../../shell/src/settings_screen.gd) — the Address row
  exists because "a box with no terminal has to be able to say its own address".
- [`marwanos-session`](../../os/files/usr/lib/marwanos/session/marwanos-session)
  and the journald drop-in — persistent logs were pulled forward into M0
  precisely because "on a machine whose entire premise is no visible text and no
  terminal, volatile logs are the only way any failure before login is knowable".

None of that changes here, because **D6 was never "no terminal"**. It reads:

> No getty on tty1, ever. SSH and a tty2 getty exist only when
> `/var/marwanos/devmode` flag file is present.

The thesis is *no reachable terminal on a machine somebody owns*. The dev-mode
bypass is part of the decision, not an exception to it. What was actually missing
is narrower and it has cost real days: **every escape hatch D6 allows requires a
second computer and a working network.**

The record on that is not hypothetical.

- 2026-08-08: the bench became unreachable over SSH and took its journal with it
  on shutdown, which is why journald persistence moved to M0.
- 2026-08-10: the sshd lockout that
  [`flightrec`](../../os/files/usr/lib/marwanos/flightrec) was written for — the
  post-mortem is now written into `~player/Downloads` so the *Files screen* can
  show it, because the journal could not be reached.
- The Wi-Fi screen's fifth-amendment exception, and the Display row, both exist
  because "an appliance that cannot be fixed from the couch cannot be fixed".

In every one of those the machine was drawing a perfectly good picture on the TV,
and the person in front of it had a controller and no way to type a command. The
shell has been growing single-purpose answers to that — a row that says the IP, a
row that cycles display profiles, a screen that shows a diagnostics file, a seam
that removes an app — each of them a hand-built substitute for one command.

## Decision

**Ship a real terminal emulator, launched from the settings screen through the
existing launch seam, gated on `/var/marwanos/devmode` — the same flag as sshd
and the tty2 getty.**

Four pieces, and the gate is checked on both sides of the privilege boundary:

1. **`xterm`** in the image, plus `dejavu-sans-mono-fonts` (named, so
   fontconfig cannot silently substitute a proportional face) and `sudo`.
2. **[`/usr/lib/marwanos/terminal`](../../os/files/usr/lib/marwanos/terminal)** —
   the wrapper. Refuses without the flag, then execs xterm with the shell's
   palette, a 64px internal border for overscan, and `-e /bin/bash --login`
   (the player account's login shell is `nologin`, so an xterm without that
   flag opens and exits instantly).
3. **[`marwanos-devmode-sudo.service`](../../os/files/usr/lib/systemd/system/marwanos-devmode-sudo.service)**
   — copies the sudoers rule from `/usr/lib` into `/etc/sudoers.d` on every boot
   where the flag exists, and deletes it on every boot where it does not.
4. **The shell** — `Catalogue.terminal_entry()`, a `Terminal` row built only when
   the flag is there, and `PAD_KEY_APPS["system.terminal"] = "keys"`.

### Why this is a narrowing of D6 and not a hole in it

- A shipped stick has no flag, so it has no row, no sudo rule, and a wrapper that
  refuses. The image is asserted at build time to contain no
  `/etc/sudoers.d/50-marwanos-devmode`.
- The flag is root-owned under `/var`. The shell runs as `player` and cannot
  create it. Setting it requires the access it grants.
- Removing it revokes on the next boot — including the sudo rule, which is why
  that unit is deliberately *not* `ConditionPathExists`-gated: the boot where the
  flag has just gone is the one that has to run.
- It is reachable only from the settings screen, four presses in, on a machine
  that already announced itself as a development target.

### Why a real emulator and not a shell-drawn console

The alternative considered was a Godot screen with the on-screen keyboard on top
and command output rendered as text — no new packages, controller-native, and it
would have looked more like the rest of the shell.

It was rejected because it is not a terminal. Godot has no PTY, so it can only
run one non-interactive command at a time: no `vim`, no `top`, no `less`, no
password prompt, no `bootc upgrade` progress, no long-running command you can
watch and interrupt. The situations this exists for — a machine that will not
come up, a network that will not associate — are exactly the ones that need an
interactive shell. Building a fake one would have been a second half-answer of
the kind this ADR exists to stop adding.

### Input, which is the half that is easy to forget

The appliance has no keyboard, and the terminal is a foreign X client the shell
cannot see inside. Both halves of the answer already existed and neither is new
code:

- **`pad_keys.gd`'s "keys" dialect** — arrows, Return on **A**, BackSpace on
  **B**, injected with `xdotool` through XTEST. The dialect was built for
  Dolphin, has had no member since the Files screen replaced it, and fits a
  prompt better than it ever fitted a file manager.
- **The app menu's Type** — press home, choose Type, use the on-screen keyboard,
  and the string goes in through the same XTEST path. **A** then runs it.

A USB keyboard is the better experience and works with no shell involvement at
all. The pad path is what makes the terminal usable on the day the keyboard is in
another room and the machine will not boot.

## Consequences

- The image grows xterm, a monospace font, fontconfig and sudo. The Containerfile
  note saying fontconfig was deliberately not added is now qualified rather than
  wrong: it was about Godot never needing it.
- `sudo` on a devmode machine means the `player` account can become root
  locally. On a machine whose flag is set, root over SSH with baked-in keys is
  already open; this is the same door reachable from the sofa. On a machine
  without the flag, nothing changed.
- The settings screen can now start a launch, so it hides itself for the
  duration — both because the pad reaches shell UI while another client owns the
  screen, and because the app menu makes the shell's window transparent and an
  opaque screen behind it would paint over the application.
- Phase 1 does not delete this. When marwand owns launching, the row becomes one
  more `Launch` call; the wrapper, the flag and the sudo unit are unaffected.
- The README's "no terminal" line now carries "on a machine that is not in dev
  mode", which is what it always meant.

### Two things the first live run corrected

Both found by running the wrapper against an Xvfb display with the built image,
and both are the kind of defect no static check catches:

- **The locale is nobody's default.** greetd exports none, so bash emitted UTF-8
  and xterm decoded Latin-1: Fedora's own prompt drew its ostree hexagon as
  `â¬¢`. The journal this terminal exists to read is full of typographic quotes
  and arrows, so a console that mangles them is worse than no console. Fixed
  with `-u8` *and* `LANG=${LANG:-C.UTF-8}` — the decoding half and the emitting
  half, neither implying the other.
- **The shell renames the window.** Fedora's prompt writes the title escape
  sequence every time it draws, so within a second the window was called
  `root@<hostname>:/` and `xdotool search --name 'MarwanOS Terminal'` found
  nothing. Nothing shipped searches by name, but a bench that cannot find the
  window by name is a bench where every command starts with a guess, so
  `allowTitleOps: false` pins it.

## Open questions

1. Should the terminal be reachable from anywhere other than settings — a
   button combination on the rail, say? Deliberately not, for now: a hidden
   combination is a thing that gets pressed by accident and cannot be found on
   purpose.
2. Does the pad's "keys" dialect want a terminal-specific dialect later
   (Tab for completion, **Y** for Ctrl-C)? Wait for the bench to say so.
