# `shell/` — the MarwanOS shell

A Godot 4 project. M3's skeleton: a tile grid you drive with a controller, a
launch seam that swaps to a placeholder scene and comes back, and the TV-safe
layout rules baked in from the first commit rather than added as a polish pass.

It is the only thing the appliance draws. `marwanos-session` starts it in a
supervision loop and never lets it fall through to a console, so everything here
is written on the assumption that **nothing this program does can be seen except
on a television, and nothing it says can be read except in `journalctl`.**

---

## What is here

```
shell/
  project.godot          engine + window + autoload configuration
  export_presets.cfg     the `linux` preset the image build exports by name
  scenes/
    shell_root.tscn      the one scene file: an empty Control with a script
  src/
    shell_log.gd         journal-shaped logging          (autoload ShellLog)
    kiosk.gd             fullscreen, borderless, no cursor; logs the display
                         geometry it was actually handed (autoload Kiosk)
    shell_input.gd       the six actions, at device -1   (autoload ShellInput)
    player_one.gd        which pad is player one, hotplug (autoload PlayerOne)
    focus_repeat.gd      held-direction repeat for a pad (autoload FocusRepeat)
    system_status.gd     THE STATUS SEAM: renders state files the system
                         writes, probes nothing         (autoload SystemStatus)
    installed.gd         what is installed, from the system's own scan
                                                        (autoload Installed)
    launcher.gd          THE LAUNCH SEAM                 (autoload Launcher)
    launch_placeholder.gd  what "launch" shows in Phase 0
    settings.gd          THE SETTINGS SEAM               (autoload Settings)
    settings_screen.gd   the settings page (read-only except Wi-Fi)
    settings_row.gd      one row on it
    action_row.gd        a row that does something rather than answering
    wifi.gd              THE WIFI SEAM: the only one that also WRITES
                                                        (autoload Wifi)
    wifi_screen.gd       networks in range, and joining one
    keyboard.gd          on-screen keyboard, pad-driven
    stores.gd            THE STORES SEAM                 (autoload Stores)
    stores_screen.gd     side tabs + the store page they render
    store_tab.gd         one tab in that column
    glyphs.gd            the bar's icons, drawn with primitives
    icon_button.gd       a focusable icon (the store bag, the gear)
    shell_root.gd        the grid screen
    tile.gd              one tile
    catalogue.gd         the store list; Phase 1 replaces this
    tv_theme.gd          every number the shell draws with
```

Two properties of this layout are deliberate and worth not undoing:

**The UI is built in code, not in scene files.** There is exactly one `.tscn`, and
it is an empty `Control` with a script attached. The Godot editor is the first GUI
tool that authors files into this repo — it rewrites scenes on its own schedule,
in a format that is technically text and practically not reviewable. Phase 1 M2
replaces `catalogue.gd` with a live list from `marwand`, at which point the grid
has to be built at runtime anyway, so a hand-laid scene tree would be thrown away
at the first `LibraryChanged` event.

**The project imports zero resources.** No fonts, no images, no audio. The tiles
are flat colours and the type is Godot's bundled default font. Three things fall
out of that: `--import` in the image build is near-instant and cannot fail on an
asset, there is no binary blob in git for `.gitattributes` to get wrong, and the
shell does not need `fontconfig` at runtime — which matters because nothing in
`os/Containerfile` names it and Godot `dlopen`s it, so a missing one would
degrade silently rather than fail.

---

## Opening it in the editor

Open the `shell/` directory as a project with **the same Godot version the image
pins** (`GODOT_VERSION` in `os/Containerfile`). The match matters both ways: a
newer editor re-saves project files in a format the pinned exporter can refuse,
and the editor and the export template must be the same version or the export
fails outright. `docs/dev-setup.md` §6 has the full three-loop picture.

F5 runs it. The window comes up fullscreen and borderless with no cursor, because
`kiosk.gd` asserts that regardless of where it is running — alt-tab out or kill it
from the terminal you launched the editor from.

**The desk is not the target.** There is a mouse, the compositor is a normal
desktop one, and a pad plugged into a laptop can enumerate differently from one
plugged into the appliance. The editor loop is for layout, focus order and
anything judgeable on a monitor. Everything else belongs on the TV.

### After the first editor session, look at what it did

```bash
git status --short shell/ && git diff --stat shell/
```

Expect, and check before committing:

- `shell/.godot/` — never commit it. It is the import cache and the build
  regenerates it. Already in `shell/.gitignore`.
- `*.gd.uid` sidecar files — Godot 4.4+ writes one per script. **Do** commit them;
  a missing uid makes the editor mint a new one and rewrite every file that
  referenced the old one.
- `project.godot` and `export_presets.cfg` rewritten with the comments stripped.
  Godot's config writer does not preserve comments. The reasoning that was in
  them is repeated below on purpose.
- `config/features` bumped to whatever version opened the project. It currently
  says `4.7`, tracking the Containerfile's pin. A diff there is the cheapest
  signal that the shell was edited with an engine the image does not ship.
- Line endings. `shell/.gitattributes` forces LF on every type a Godot project
  produces, but check anyway — the repo has lost days to CRLF twice.

Never put an absolute path in `custom_template/release`. It would be a path from
whoever last opened the editor, and it only fails on someone else's machine.

---

## The things that were decided, and why

These are the parts that will look arbitrary later. All of them are also in the
comments at the top of the file that implements them.

### The input map is defined in code, at device -1

`src/shell_input.gd` erases and rebuilds six actions at startup: `ui_up`,
`ui_down`, `ui_left`, `ui_right`, `ui_accept`, `ui_cancel`. Two reasons it cannot
just inherit the built-ins:

- Godot's built-in joypad bindings are created with `create_reference()`, which
  never sets a device, so they inherit `InputEvent`'s default `device = 0` and
  answer to joypad index 0 only. Godot has open bugs where a pad ends up on index
  1 after a hotplug. The result is a grid that renders perfectly and ignores the
  controller — on a machine with no terminal, indistinguishable from a hung shell.
- Whether `ui_accept` and `ui_cancel` carry joypad bindings at all in 4.x is
  reported differently by different sources. Binding A and B explicitly makes the
  question moot on every engine version, which is cheaper than being sure.

The startup check in `_verify()` logs an error if any of the six loses its joypad
half. It logs rather than aborts: a shell that refuses to start is a black TV,
and `assert()` is compiled out of the release export that is the only build the
appliance ever runs.

Stick deadzone is 0.5, matching what Godot registers the built-in directional
actions with. It is a number to tune from the couch — `ShellInput.STICK_DEADZONE`
and `FocusRepeat.STICK_DEADZONE` have to agree.

### A pad has no key repeat, so the shell implements one

`src/focus_repeat.gd`. The keyboard gets repeat free from OS key echo; a gamepad
cannot, because `InputEventJoypadButton` only fires on a state change and the
stick branch is gated on "just pressed". Without this file, holding a direction
moves focus exactly once and crossing the grid takes eleven presses.

This is worth stating loudly because it is invisible to every automated check.
Every line works as designed, and ADR 0004's step-4 script tests the supervision
loop with `pkill` and never touches navigation. The only test that catches it is a
person on a sofa.

400 ms before the first repeat, 120 ms between repeats. It polls the *claimed*
device's buttons and axes directly rather than `Input.is_action_pressed()`, so a
second controller cannot drive it past `PlayerOne`'s gate.

### Player one is a GUID, not an index

`src/player_one.gd`. Godot hands out joypad slots by lowest free index, so a pad
normally returns to the index it left — normally is not always. The claim is keyed
on `Input.get_joy_guid()` and re-attaches to whatever index the same controller
turns up on. A different controller re-claims rather than being refused: SDL's
HIDAPI path can change the reported GUID between runs, and an appliance that
ignores the only pad in the room because an identity moved is worse than one that
accepts it.

`joy_connection_changed` is the fast path and **not** the only path — Godot has
open bugs where a removal emits nothing. A once-a-second reconcile against
`Input.get_connected_joypads()` is the backstop, and the first joypad event seen
is the last resort.

Extra controllers are gated in `_input()` with `set_input_as_handled()`, which
runs before the GUI pass, rather than by device-scoping the actions. That keeps
every action at device -1, so no index change can brick the shell.

Unplugging does **not** reset the UI. The header says "Reconnect the controller"
and focus stays where it was, because the person is reaching for a cable and the
screen they come back to should be the one they left.

### Gamepad input never touches the compositor

Godot reads `/dev/input/event*` directly — SDL3 since 4.5, evdev before that — and
neither gamescope nor cage grabs those devices. So everything in `player_one.gd`
and `focus_repeat.gd` behaves identically under plan A and plan B. The only
precondition is read access to `/dev/input`, which `os/Containerfile` secures by
putting `player` in the `input` group.

### The display driver is left at its default

`display/display_server/driver.linuxbsd` is deliberately **absent** from
`project.godot`. Godot falls back in both directions — an X11 project uses Wayland
when X11 is unavailable, and vice versa — so one export is correct under both
plans D4 is still choosing between:

| | gamescope (plan A) | cage (plan B) |
|---|---|---|
| session exports | `DISPLAY`, no `WAYLAND_DISPLAY` | `WAYLAND_DISPLAY` |
| Godot lands on | XWayland | **XWayland, measured** — see below |
| why that is the good path | it is the path `--force-windows-fullscreen` manages, and the one Steam games take | it is the same path, which at least means one tested code path rather than two |

**The plan B column used to say "native Wayland", and a VM run on 2026-08-05
disproved it.** With cage demonstrably the compositor — gamescope had failed its
readiness handshake and the session had logged the fallback — the shell reported
`DisplayServer.get_name() == "X11"`. cage ships with Xwayland and Godot's linuxbsd
driver order puts x11 first, so `DISPLAY` exists and wins. The shell therefore runs
on XWayland under **both** plans.

Two consequences worth carrying. The good one: there is one display-server code
path in production, not two, so a Godot Wayland-backend bug cannot be what
distinguishes the plans. The bad one: `get_name()` is not the free D4 oracle it
looked like — it says `X11` either way, and the session script's own log line is
what names the compositor.

Pinning the driver would still break whichever plan it was not pinned for. Re-check
this on every Godot bump: upstream pressure to default `linuxbsd` to Wayland is
increasing, and a future 4.x could flip it under us — at which point `Kiosk`'s
`display ...: server ...` line is what says so.

### Fullscreen, borderless and no cursor are asserted by the client

`src/kiosk.gd`, as well as in `project.godot`. gamescope covers most of it with
`--force-windows-fullscreen` and `--hide-cursor-delay 1`; cage 0.2.0 has neither
flag and no cursor option at all (ADR 0004 finding 9). D4 says the shell code is
identical either way, so the shell has to be the thing that makes that true.

Window mode is `MODE_FULLSCREEN`, not `MODE_EXCLUSIVE_FULLSCREEN`: exclusive asks
for a videomode change, which under either compositor is not the client's job —
gamescope has already negotiated a mode with the TV and written it to `modes.cfg`.

**Which screen is not the client's job either, and it cannot be.** The 2026-08-05
hardware run found the shell laid out across two displays at once, and the obvious
fix — have the shell pick a screen — does not exist. Godot's Wayland
`window_set_current_screen` is an empty function whose body is a comment saying the
protocol does not support it; Godot's Wayland fullscreen request passes a null
output; cage discards the output argument and sizes to the bounding box of every
output anyway; and under gamescope's XWayland there is exactly one screen. There is
no `DisplayServer.screen_get_name()` in 4.7.1 either, so the shell could not map
`HDMI-A-1` to an index in principle. The single screen is delivered below the
shell — see [ADR 0007](../docs/adr/0007-single-display-appliance.md).

What `kiosk.gd` does instead is **measure**, twice — at startup and again after the
first frame, because a Wayland compositor's first configure can arrive after
`_ready`. It logs the display server name, the adapter, the screen count, every
screen's size and position, the window's size and mode, the viewport and stretch
settings, the pillarbox the stretch is about to produce, and at `<3>` a line naming
the fault outright when the window matches no single screen. `DisplayServer.get_name()`
is `X11` under gamescope's XWayland and `Wayland` under cage, which makes the shell
a second, independent witness for D4 at the cost of one log line. On 2026-08-05 the
only evidence of the defect was a phone camera pointed at a laptop; that is the
thing these lines exist to make unnecessary.

The engine's boot splash is off. It is a Godot logo on a white field, and M2's
acceptance test is a frame-by-frame camera recording with zero frames of anything
but the plymouth splash and the shell.

### Logging is shaped for the journal

`ShellLog.info/warn/error` prefix every line with `<6>`/`<4>`/`<3>`.
`marwanos-session` re-execs itself through `systemd-cat --level-prefix=true`, the
client inherits those descriptors, and systemd parses the prefix as a syslog
priority. So `journalctl -p err -t marwanos-session` surfaces a shell problem instead of
burying it under engine chatter, and the shell's lines look like the session
script's. In the editor the prefixes are visible noise in the Output panel; that is
the right trade, because the desk has a console and the appliance does not.

`application/run/flush_stdout_on_print` is forced on. stdout is a pipe into the
journal and a pipe is block-buffered; without it a release build holds log lines
until the buffer fills or the process dies.

### TV-safe layout, in numbers

All in `src/tv_theme.gd`, all against a fixed 1920×1080 design surface that the
project's `canvas_items` stretch scales to whatever the TV negotiated.

| | value | where it comes from |
|---|---|---|
| safe-area inset | 96 px horizontal, 54 px vertical | 5% each edge; Microsoft, Android TV and tvOS all land within a few px of this |
| tile title | 34 px | above Microsoft's 30 px floor for reading content |
| supplemental | 26 px | above the 24 px floor |
| interactive height | ≥ 200 px | floor is 64 px |
| columns | 4 | Microsoft caps edge-to-edge traversal at six clicks, so 6 is the ceiling |
| colour range | RGB 16–235 | TVs band and bloom at the extremes |
| focus indicator | ring + brighter surface + 1.05× scale | three channels, because colour alone is unreliable on a TV; the ring carries WCAG 2.2 SC 2.4.13's ≥ 3:1 state change |

5% is a floor, not a guarantee — individual TVs overscan more. `SAFE_MARGIN_X` and
`SAFE_MARGIN_Y` are the one knob, and M2's camera test is the arbiter, the same
way it is for the silent boot.

### Focus neighbours are explicit on every tile

With `focus_neighbor_*` empty, Control falls back to a geometric search over a
direction band. At the end of a row the nearest control in the `+x` band is not the
first tile of the next row, and the answer it does give is hard to predict from
the code. `shell_root.gd` builds the whole table instead. Edges are hard stops —
a tile at the left of a row points its left neighbour at itself — because on a grid
this small a cursor that teleports across the screen reads as a glitch.

### B at the grid does nothing, on purpose

There is nowhere to back out to, and **nothing in this project ever calls
`get_tree().quit()`**. An exit would be a client exit as far as `marwanos-session`
is concerned: the supervision loop counts it as a crash, restarts it, and five
inside sixty seconds trips the guard and leaves the compositor holding an empty
screen.

---

## The launch seam

`src/launcher.gd` is the file Phase 1 replaces. Everything the shell knows about
running something other than itself goes through `Launcher.launch(entry)` and the
two signals; nothing else in the project reaches into the launch path.

```
tile pressed
  └─ Launcher.launch(entry)
       ├─ emits launch_started(entry)   → grid saves focus and hides
       └─ _run(entry)                   ← Phase 1 changes this line
            └─ launch_placeholder scene, until B
                 └─ Launcher._on_closed  ← Phase 1 changes this line
                      └─ emits launch_finished(entry) → grid shows, focus restored
```

In Phase 1, `_run()` sends `Launch { target_id }` to `marwand` over the WebSocket
and returns without waiting, and `_on_closed()` becomes the handler for marwand's
`AppExited` event. Nothing else moves: the grid, the tiles and the hint row only
ever see `launch_started` and `launch_finished`, so they do not care whether the
thing that started was a placeholder scene or a Flatpak.

It is deliberately single-purpose — no queue, no retry, no state machine beyond
"one at a time". If something wants to grow there, that is the signal it belongs
in the daemon instead. The shell is a renderer.

`ui_cancel` is the only way out of the placeholder. Adding `ui_accept` as a second
exit would be forgiving and would also let M3's acceptance test pass with B doing
nothing at all — which is exactly the silent failure the input map exists to
prevent.

---

## The settings seam

`src/settings.gd` is the launch seam's shape — one entry point, two signals, one
at a time — pointed at a shell-internal screen instead of an app, and kept
**separate from `launcher.gd` on purpose**: Phase 1 rewires the launch seam to
`marwand`, and a screen swap that lives inside it would become an RPC by
accident. The last card on the rail (`settings_tile.gd`, shell furniture rather
than catalogue content, so it survives the catalogue's Phase 1 deletion) opens
it; B closes it.

```
settings card pressed
  └─ Settings.open()
       ├─ emits settings_opened     → rail saves focus and hides
       └─ settings_screen, until B
            └─ Settings._on_closed
                 └─ emits settings_closed → rail shows, focus restored
```

The screen is **read-only in Phase 0**, and that is a decision rather than a gap:
a row that changed something would need somewhere to send the change, and the
shell is a renderer — mutable settings arrive when `marwand` does. What the rows
show is the answers this project has so far had to fish out of `journalctl`:
os-release, engine version, display server and mode, video adapter, and the
claimed controller (live — it tracks hotplug through `PlayerOne`'s signals).
On an appliance with no terminal, that screen is a diagnostic surface, not
filler.

Navigation is the rail's argument rotated 90°: one axis, hard stops at the ends,
the perpendicular directions pointed at self. Pressing A on a row logs
`read-only in Phase 0` rather than doing nothing silently — a press that
vanishes is indistinguishable from broken input on this machine.

`shell_root.gd` treats "something fullscreen is up" as one state however it was
reached: the launch and settings seams share `_hand_screen_over()` /
`_take_screen_back()`, so a third surface (the store, a guide overlay) has a
pattern to copy rather than a precedent to untangle.

---

## Exporting

The image build does this; the commands are here so the same thing can be done by
hand when the editor is not what should produce the binary.

```bash
# Import first. --export-release does NOT imply --import (only --export-debug and
# --export-pack are documented as doing so), and without a .godot cache the export
# fails with "make sure resources have been imported by opening the project in the
# editor at least once".
godot --headless --path /abs/path/to/shell --import

godot --headless --path /abs/path/to/shell \
      --export-release "Linux" /abs/path/to/out/marwanos-shell.x86_64
```

- `"Linux"` here is the **preset name** in `export_presets.cfg`, which happens to
  equal the platform name. Renaming the preset breaks the image build — loudly,
  because the Containerfile asserts `^name="Linux"$` in the file before running
  the export.
- The `.x86_64` extension is what Godot's Linux exporter expects on the output
  path. Rename after exporting, not before.
- `binary_format/embed_pck=true` is what makes the output a single self-contained
  executable. Off, it is a binary plus a sibling `.pck`, and both places the shell
  is consumed — `BAKED_CLIENT` in `marwanos-session`, and D5's `scp` of one file —
  want one file. Re-saving the preset in the editor GUI can silently flip it back
  to the default of `false`, at which point the appliance ships a binary whose pck
  was never copied and the TV goes black with nothing in the journal. Check it
  before committing a preset change:

  ```bash
  grep embed_pck shell/export_presets.cfg   # must say true
  ```

- Check the export is not silently a failure. Godot's headless export has a
  history of exiting 0 on a failed export (fixed in 4.3) and of crashing while
  still writing a plausible-looking executable (fixed in 4.5), which is why 4.5 is
  the floor and why the build asserts on the output rather than on the exit code.

Never commit the exported binary. `/out/` is gitignored at the repo root, and M3's
checklist is explicit: no hand-exported binaries in git.

---

## The D5 dev-override loop

The reason this project exists as a separate artefact from the image: an image
rebuild plus `bootc upgrade` plus a reboot per UI tweak would kill iteration. D5
says the session prefers a binary at `/var/marwanos/dev-shell/marwanos-shell` when
`/var/marwanos/devmode` exists, and `resolve_client()` re-runs on **every** restart
rather than once at session start — so replacing the file and killing the process
is the whole loop, about ten seconds.

`docs/dev-setup.md` §6 is the authority. The short version:

```bash
# 1. get a binary — export as above, or pull the one the image ships
podman create --name marwanos-extract ghcr.io/marwansummakieh/marwanos:latest
podman cp marwanos-extract:/usr/lib/marwanos/shell/marwanos-shell ./marwanos-shell
podman rm marwanos-extract

# 2. push it
scp marwanos-shell root@<target>:/var/marwanos/dev-shell/marwanos-shell

# 3. make it executable and restart the client
ssh root@<target> 'chmod 0755 /var/marwanos/dev-shell/marwanos-shell; \
                   touch /var/marwanos/devmode; \
                   pkill -9 -u player marwanos-shell'
```

Nothing appears on the screen while that happens. Both halves of the override are
required — an executable at the path **and** the devmode flag — so a dev build left
on a target cannot quietly become what the appliance ships.

**Three ways this looks like "my change did not deploy", all silent:**

1. **The binary is not executable.** `resolve_client()` tests `[ -x ]` and returns
   the baked client when it fails, without a word. `scp` does not reliably preserve
   the mode. `chmod 0755` every time.
2. **`/var/marwanos/devmode` is missing.** Same fallback, same symptom.
3. **You iterated too fast.** Five client exits inside sixty seconds trips the
   crash guard, and the session then holds the compositor up with an empty screen
   rather than respawning at boot speed. `systemctl restart greetd` clears it.

One line settles all three, because the session logs which path it took:

```bash
ssh root@<target> "journalctl -b -t marwanos-session -o cat | grep -F 'starting client'"
```

And to tell a shell problem from a compositor problem, push `vkcube` through the
same seam — the process name comes from the file, so the restart command does not
change:

```bash
ssh root@<target> 'cp /usr/bin/vkcube /var/marwanos/dev-shell/marwanos-shell; \
                   pkill -9 -u player marwanos-shell'
```

A spinning cube means the compositor took the display and the shell is the
problem. No cube means the fault is below the shell.

---

## Getting closer to the target without leaving the desk

Run the *exported* binary under nested gamescope on any Linux machine:

```bash
gamescope -W 1920 -H 1080 -f -- ./marwanos-shell
```

That reproduces focus handling and fullscreen behaviour. It does not reproduce the
TV, DRM master, or the NVIDIA driver.

Test the **exported binary**, never the editor, when the question is about input.
Godot 4.5 moved the Linux controller backend to SDL3, official export templates
vendor SDL3 statically, and a distro-packaged editor unbundles it — so the editor
on your desktop and the binary on the appliance can be running different SDL
versions with different DualSense handling.

---

## What to watch on the first run under the real session

ADR 0004 step 6 schedules this, and it is worth doing before any more UI is built
on top. In this order:

1. Does the window come up fullscreen at the TV's native mode? On 2026-08-05 it did
   not — it spanned both displays. `Kiosk` now logs the geometry, so read
   `journalctl -b -t marwanos-session -o cat | grep marwanos-shell` rather than
   judging this by eye.
2. Does the gamepad enumerate, and does it survive an unplug/replug? The header
   status line and the `player one` lines in the journal answer this without
   guessing.
3. Does `pkill -9` the shell bring it back inside three seconds, with no text at
   any point?
4. Any Wayland protocol error in the journal? Godot's Wayland backend crashes on
   protocol *version* mismatches rather than degrading — a `wl_registry ... error
   0` or an "invalid version for global" line at launch is that bug family, not
   this code. It is a reason to bump Godot, not to debug the shell.

One more suspect worth knowing about: `marwanos-session` exports
`ENABLE_GAMESCOPE_WSI=1` unconditionally, including on the cage path where no
gamescope is running. `vkcube` may tolerate the implicit Vulkan layer where a full
Godot client does not. If the shell misbehaves under plan B and `vkcube` did not,
try unsetting it before concluding anything about Godot under cage — that
conclusion is currently one of ADR 0004's stated criteria for flipping plan A to
plan B, so it is worth being right about.
