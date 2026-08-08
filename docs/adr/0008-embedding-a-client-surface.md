# ADR 0008 — Putting a running client's pixels inside the shell

**Status:** Proposed — this ADR exists to scope a spike, not to authorise an
implementation
**Date:** 2026-08-08
**Relates to:** the compositor decision in [ADR 0005](0005-compositor-decision.md);
the shell and its XWayland reality in [ADR 0006](0006-shell-skeleton.md); the
stores screen added by 0006's third amendment; D4 in
[phase-0-plan.md](../phase-0-plan.md)

## Context

The request: render Steam's live UI inside the stores screen's page pane, so the
tab column on the left and Steam itself on the right are one surface — the shape
a console store has, rather than a page that describes Steam and a fullscreen
launch that replaces it.

Two places in the tree already say this cannot be done, and they were written
before anyone asked for it rather than in response to the asking:

- [`stores_screen.gd`](../../shell/src/stores_screen.gd) — "embedding a foreign
  client's window inside a Godot control is compositor work (XEmbed/subsurface
  composition) that gamescope does not offer a shell running as one of its
  clients, and a webview would be the project's first native extension."
- [`tv_theme.gd`](../../shell/src/tv_theme.gd) — the same point, shorter.

This ADR does not overturn those. It says what would actually have to be built,
because "not today" is a worse answer than "here is the shape of it and here is
what it costs."

### What the architecture is

Under plan A the layering is flat, and that is the whole difficulty:

- **gamescope** holds DRM master and is the session compositor.
- **The shell** is one XWayland client of it. Godot's linuxbsd driver order puts
  x11 first, `WAYLAND_DISPLAY` is deliberately not set, and the measured server
  name is `X11` — see `kiosk.gd`'s header.
- **A launched application** is a *sibling* client, not a child of the shell. The
  shell spawns the process; gamescope owns the window.

So the shell and Steam are peers. gamescope composites whole top-level windows
and forces them fullscreen. There is no parent-child surface relationship to
subordinate one to the other, and no sub-rectangle anywhere in the model.

### The one cross-client lever that exists

`GAMESCOPE_EXTERNAL_OVERLAY` (see `kiosk.gd`) makes gamescope composite one
window *over* the focused application instead of replacing it. It is what makes
the app menu possible. It operates on whole windows: the shell's window goes on
top, transparent where it wants the application to show through.

That is the inverse of what embedding needs. It can put the shell over Steam; it
cannot put Steam inside a 1200x800 rectangle of the shell.

## The three routes, and what each actually costs

Every route has the same first problem: **Godot 4 has no API to import an
external X pixmap, dmabuf or PipeWire buffer as a texture.** All three therefore
begin by making this project's first GDExtension, which is a line the codebase
has so far deliberately not crossed.

### 1. X11 Composite redirect + texture-from-pixmap

`XCompositeRedirectWindow` on Steam's window, take the offscreen pixmap, bind it
with `GLX_EXT_texture_from_pixmap`, hand the GL texture to Godot.

Against it:

- It is a **GLX** extension, so it presumes the OpenGL renderer. The appliance
  ships Forward+ (Vulkan). Either the shell moves to `gl_compatibility` on the
  target — a real regression in what the renderer can do — or this route needs a
  Vulkan dmabuf import instead, at which point it is route 3's machinery anyway.
- The shell would be redirecting a window belonging to a **peer client** inside
  gamescope's own nested XWayland, while gamescope is simultaneously trying to
  composite and fullscreen that same window. Two compositors wanting the same
  surface is not a configuration anyone tests.
- Steam remains a top-level. Keeping it from also appearing fullscreen is extra
  fighting with gamescope's window management.

### 2. gamescope's PipeWire output capture

gamescope can publish its composited output on PipeWire. Consume that, draw it
in the pane.

Against it: it captures **the whole gamescope output**, which includes the shell.
Embedding it in the shell renders the shell inside itself. It is the wrong
granularity, not merely an awkward one. It only becomes useful combined with
route 3, where the thing being captured is a *second* gamescope that has only
Steam in it.

### 3. A nested gamescope per app, captured into the shell

Run a second gamescope, headless, with Steam as its only client; capture that
instance's output; import it as a texture in the pane.

This is plan B (`cage` + nested gamescope per app) resurrected for one purpose
rather than as the session model — and it is the only one of the three whose
pieces are all doing what they were built to do. gamescope nests by design, and
its capture path exists.

Against it, honestly:

- An **extra compositor process per embedded app**, with its own GPU memory and
  its own copy of every frame. On a machine already software-composited in
  places and pushing a TV at native mode, that cost is measurable and unmeasured.
- **Input is the hard half, and it is easy to forget.** An embedded Steam that
  cannot be driven is an expensive screenshot. The shell would have to forward
  pad and keyboard events into the nested instance, decide when the pane has
  "focus" versus when the tab column does, and hand it back — a focus model the
  shell does not currently have, on top of `shell_input.gd`'s existing
  device-scoped map.
- Still needs the GDExtension for PipeWire → dmabuf → Godot texture.

## Recommendation

**Route 3, gated on a timeboxed spike that answers three questions before any
shell code changes:**

1. Does a nested, headless gamescope running the Steam flatpak on this NVIDIA
   box actually produce a capturable stream — and at what frame cost with the
   session gamescope also running?
2. Is there a working dmabuf-to-texture path into Godot 4.7 on the NVIDIA
   proprietary driver, from a minimal GDExtension?
3. What does input routing into the nested instance look like, concretely?

Question 3 is the one most likely to sink it, and it is the one a pixels-first
spike will discover last. It should be answered first.

**Until that spike reports, the stores page stays shell-drawn and A still opens
Steam fullscreen.** That is not a placeholder for embedding: for actually *using*
Steam it is the better behaviour, and it is what the PS5 does with its own store
tile. Embedding earns its cost for *browsing* and *preview*, not for use.

## Consequences

- The project acquires a GDExtension, a compiled artefact in an image whose whole
  build story is currently "one Godot export, one binary". The Containerfile's
  shell-export stage grows a toolchain.
- If the spike fails on any of the three questions, the honest outcome is that
  the stores pane stays as it is, and this ADR is the record of why — so it is
  not re-proposed from scratch in three months.

## Open questions

1. Is the goal *browsing Steam inside the shell*, or *the stores screen not
   feeling like a brochure*? The second is reachable without any of this — real
   key art in the hero band instead of a flat accent wash — and is hours rather
   than weeks. This ADR assumes the first because that is what was asked for.
2. Does embedding extend to launched **games**, or only to store clients? A game
   in a pane is a much harder performance argument, and if the answer is "only
   stores" the scope narrows considerably.
