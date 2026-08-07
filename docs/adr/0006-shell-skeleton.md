# ADR 0006 — The shell skeleton, and where its binary comes from

**Status:** Accepted (2026-08-06, after the shell ran on hardware — see the
first amendment; a second, later that day, records the settings page; a third,
2026-08-07, records the PS5-shaped top bar and the stores screen; a fourth,
same day, retires the placeholder catalogue for a real app list; a fifth
**reverses the read-only rule** for Wi-Fi and adds an on-screen keyboard)
**Date:** 2026-08-05
**Relates to:** M3, and D5/D6 in [phase-0-plan.md](../phase-0-plan.md); the
supervision loop scaffolded in [ADR 0004](0004-session-compositor-scaffold.md);
the repo layout and the shell/daemon split in
[phase-1-plan.md](../phase-1-plan.md)

## Context

M3 is where the appliance stops rendering someone else's spinning cube and starts
rendering its own. Everything under it already exists: greetd autologs in, a
compositor takes the display, and `supervise_client` restarts whatever
`resolve_client` hands it. M3 changes exactly one value in that chain — which
executable the session runs — and then owes an answer to the question that value
raises: **where does that executable come from, and who is allowed to build it?**

That question is not a packaging detail here. D6 says no reachable terminal, no
reachable code path, nothing on the machine that can run arbitrary code. A Godot
editor binary is a GDScript interpreter with `--script` and `--headless`; it is
the same category of object as a shell, and putting one in the image to build the
UI would undo the milestone's own thesis in the name of convenience.

Nothing here has run on hardware. The status stays **Proposed** until the shell
comes up on the TV under whichever compositor M1 picks, at which point this is
either accepted or amended by what the run found. As with ADR 0004, the point of
writing it now is that the hardware time is spent measuring rather than deciding.

## Decisions

### 1. Pin an upstream Godot release by checksum. Do not `dnf install godot`

M3 builds against **Godot 4.7.1-stable**, downloaded from the `godot-builds`
release assets and verified against hardcoded SHA512 sums for both the editor zip
and the export-templates `.tpz`. The `GODOT_*` ARGs in `os/Containerfile` are the
source of truth for the numbers; this ADR records why they are pinned at all.

Fedora 43 packages Godot, and using it would remove a ~1.3 GB download from every
cold build. It was rejected for the reason the base image is pinned by digest:
**a distro package is a floating tag with better manners.** The two research
passes that fed this milestone read Fedora 43's `godot` as 4.4.1 and as 4.5 —
that is the argument in one line. An engine version that moves under you inside a
single Fedora release, in a repo where `bump-base.sh` hard-fails rather than let
a base image drift, is not a shortcut. It also does not actually save the
download: Fedora ships no export templates (prebuilt binaries are not
permissible), so the `.tpz` has to be fetched anyway, and pairing a
distro-patched editor with official templates is a version match nobody has
validated.

The floor is 4.5 regardless of preference, and it is set by CI bugs rather than
features. Headless export used to **exit 0 on failure** (godot#83042, fixed for
4.3), `--headless --import` used to exit 1 on success (godot#83449, 4.3), a
headless export could hang forever with no `.godot` cache (godot#95287, 4.4), and
one could crash with SIGILL while still writing a plausible-looking executable
(godot#99284, 4.5). Every one of those produces a green build and a black TV.
4.7.1 is well clear of all four; the assertions in the build stage exist because
being clear of the *known* four is not the same as immunity.

**Expect a bump inside M3.** 4.7.2-rc1 was tagged 2026-08-03. The editor and the
export template must be the same version — a mismatch is a hard export failure —
so a bump moves two URLs and two SHA512 sums together, exactly like the
base/akmods tag pair, and is a deliberate act rather than a hand-typed hash.

### 2. Export during the image build, in a stage that never ships

A separate builder stage downloads the editor and the templates, runs the
headless import and export, and hands the finished executable to the final image
through `COPY --from`. Neither the editor nor the ~1.19 GB of templates reaches a
layer that ships.

The size argument is the weaker one. The real argument is D6: an appliance whose
premise is that no code path is reachable does not get to carry a general-purpose
script interpreter for the convenience of its own build.

**The rejected alternative is committing the exported binary to git**, which is
the obvious way to skip all of this and is wrong four times over:

- `.gitignore` already refuses it, and the comment there already says why.
- `core.filemode` is false in this repo. A committed binary cannot carry its
  executable bit through a checkout, so it would arrive non-executable, fail
  `[ -x "$_client" ]` in `supervise_client`, and land in `hold_forever` — ADR
  0004 finding 6, one level down.
- A binary in git has no provenance. Nobody reviewing a diff can tell which
  project state, which engine version or which machine produced it, on a project
  whose entire discipline is that the image is a function of the repo.
- It grows the repo by ~100 MB per commit that touches the UI, over a bridge
  (`/mnt/c` via drvfs) that the build context already has to cross.

The second rejected alternative is running the export outside the image build —
a script on the build host that produces a binary the Containerfile then
consumes. That is the same problem with extra steps: the artefact's provenance
moves off the machine that builds the image, and the "no hand-exported binaries"
line in M3 stops being enforceable by anything.

### 3. One self-contained executable, because the session seam assumes one

The Linux export preset sets `binary_format/embed_pck = true`. The default is
off, which produces `marwanos-shell` plus a sibling `marwanos-shell.pck` that the
engine finds by matching basename.

This is not a preference. `BAKED_CLIENT` is a single path, `resolve_client` tests
a single path with `[ -x ]`, and D5's dev loop is one `scp` of one file to
`/var/marwanos/dev-shell/marwanos-shell`. A binary-plus-pack export satisfies
every one of those checks, starts, and then cannot find its own content — and
does it on a machine with no console, where the symptom is a black screen that
looks exactly like a compositor failure. Any other export shape (including
Fedora's `godot-runner --main-pack`) forces an edit to `resolve_client` and
breaks the D5 seam that the whole dev loop rests on.

The build asserts both halves: that the preset says `embed_pck=true` before the
export runs, and that no `.pck` exists beside the output afterwards. The second
guard is there because re-saving the preset in the Godot editor GUI can silently
flip it back to the default.

### 4. The binary lands at `/usr/lib/marwanos/shell/`, and its layer's position is load-bearing

D5 named `/usr/lib/marwanos/shell/` and it stays. The COPY that puts it there
sits **after** the session-wiring `RUN` and **before** the `MARWANOS_*` ARGs, and
both boundaries are constraints rather than taste:

- The session-wiring step runs `find … /usr/lib/marwanos … -type f -exec chmod
  0644 {} +`, and it recurses. Anywhere above that line, the executable bit is
  stripped and the session dies into `hold_forever`. The inverse of the usual
  rule applies here: new directories under `os/files/` must be *added* to that
  find list, and `/usr/lib/marwanos/shell/` must be kept *out* of it, which the
  correct placement achieves for free because the binary does not come from
  `os/files/` at all.
- The `MARWANOS_*` ARGs are timestamped and change on every build. Below them,
  this ~100 MB layer would be re-committed on every version bump and the measured
  70-second warm rebuild would go away.

Putting the binary under `os/files/` instead — the obvious-looking place — is
wrong twice: it would also invalidate the dracut layer on every UI tweak, which
is the exact cost the `COPY files/ /` comment already warns about.

### 5. Leave the display driver at its default, and do not add `--expose-wayland`

The export keeps Godot's default `linuxbsd` display driver (x11) and relies on
its documented two-way fallback. Under plan A the session exports `DISPLAY` and
not `WAYLAND_DISPLAY`, so the shell runs on gamescope's XWayland — the path
gamescope's window management, `--force-windows-fullscreen` included, actually
acts on. Under plan B there is no `DISPLAY` and cage sets `WAYLAND_DISPLAY` for
its child, so the same binary falls back to native Wayland on wlroots. One
export, correct under both plans, which is what D4 means by the shell code being
identical either way.

The corollary is recorded here so nobody adds it later as an improvement:
**gamescope's `--expose-wayland` is deliberately not used, and
`GAMESCOPE_WAYLAND_DISPLAY` is deliberately not copied into `WAYLAND_DISPLAY`.**
Native Wayland clients under gamescope are a long-standing broken area upstream,
and a kiosk client with no decorations, no second window and no clipboard gains
nothing by moving onto it. There is a comment saying so at the export site in
`marwanos-session`.

The shell nonetheless sets its own fullscreen mode and hides its own cursor
rather than leaning on `--force-windows-fullscreen` and `--hide-cursor-delay 1`.
Those are plan A flags; cage has no equivalent of either (ADR 0004 finding 9), so
a client that depends on them passes the gate under gamescope and fails it under
cage — which would read as "Godot is unusable under plan B" and is one of the
criteria ADR 0004 lists for flipping the decision.

## What was scaffolded

| File | What it does |
|------|--------------|
| `shell/` | The Godot 4 project: tile grid, focus navigation, the placeholder launch scene, the explicit input map |
| `os/Containerfile` | A builder stage that fetches a checksummed Godot, imports and exports headlessly with the network cut, asserts the output, and a `COPY --from` placed between the session wiring and the version ARGs |
| `os/files/usr/lib/marwanos/session/marwanos-session` | `BAKED_CLIENT` now points at the export; `GODOT_WAYLAND_DISABLE_LIBDECOR=1` added; the display-driver reasoning recorded at the export site |
| `.gitattributes` / `.gitignore` | LF and binary rules for the file types a Godot project introduces; `shell/.godot/` ignored |

The last row belongs in the same commit as the first file under `shell/`, not
after it. The Godot editor is a tool that re-saves `project.godot`,
`export_presets.cfg` and every scene on its own schedule, and a CRLF
`project.godot` or a heuristically-mangled binary resource is exactly the class
of failure `.gitattributes` was written to prevent — before any of those file
types existed in this repo.

Nothing in `os/files/usr/lib/tmpfiles.d/50-marwanos.conf` changed. The two
directories M3 needs under `/var` — the dev-override path and the session user's
home, where Godot writes `user://` state — were already declared for M1, and
neither may be created at build time: `/var` is populated once at install and
never updated by an image upgrade, so anything the build leaves there is a
first-boot-only default that drifts from the image forever.

## Findings that change the shape of the work

Each of these is a day the milestone does not have to spend rediscovering it.

**1. Godot's default input map cannot activate anything with a gamepad.** The
built-in `ui_left/right/up/down` actions do bind both the d-pad and the left
stick, so focus navigation is free. But `ui_accept` is ENTER, KP_ENTER and SPACE
and nothing else, and `ui_cancel` is ESCAPE and nothing else. The only joypad
action button bound anywhere in the defaults is `ui_select` on Y/Triangle. A
shell built on the defaults navigates with the pad and cannot activate a tile —
and "B backs out" silently does nothing. This is contrary to what almost every
secondary source says, and it is unchanged on current upstream. The shell defines
its six actions explicitly.

**2. The built-in bindings respond to joypad index 0 only.** Godot builds them
with `create_reference()`, which never calls `set_device()`, so they inherit
device 0, and an action only matches when the device is `-1` (all) or equal. If
the controller ever enumerates at index 1 — a hotplug race, a second pad, or one
of the open index-churn bugs upstream — focus navigation dies with no error
anywhere, on an appliance that cannot report it. Every joypad event the shell
defines sets device `-1` explicitly.

**3. There is no key repeat for a gamepad, in any Godot 4.x.** The keyboard path
allows OS key echo; the joypad path is gated on just-pressed. Holding the d-pad
or the stick moves focus exactly once. A grid that needs one press per tile reads
as broken from the couch while every line of code works as designed — and ADR
0004's step-4 script would never catch it, because `pkill` tests supervision, not
navigation. The shell implements its own repeat.

**4. Godot dlopens almost everything, so a missing library is a missing feature
rather than a link error.** Official builds are compiled with `use_sowrap=yes`:
X11 and its client libraries, Wayland, libdecor, ALSA, PulseAudio, D-Bus,
fontconfig, xkbcommon and libudev are all loaded at runtime. Nothing fails to
start. The dangerous one is `libudev`: without it, SDL falls back to polling and
gamepad **hotplug** stops working while a controller plugged in at boot still
works perfectly — a failure that passes every casual test and fails on the couch,
against an explicit M3 checklist item. The second is the X11 *client* libraries:
gamescope pulls in `xorg-x11-server-Xwayland`, which is the X server, not the
libraries a client dlopens. Both are asserted at build time rather than assumed.

**5. Gamepad input does not pass through the compositor.** Godot opens
`/dev/input/event*` directly (via SDL3 since 4.5); neither gamescope nor cage is
in that path and neither grabs the devices. Plan A and plan B are therefore
indistinguishable for controller input, and the only precondition is read access
to `/dev/input/event*` — which the `input` group membership the Containerfile
already materialises provides. A controller problem found in M3 is not evidence
about D4.

**6. The build context is `os/`, not the repo root.** Both `scripts/build-push.sh`
and `.github/workflows/build.yml` pass `os/`, so a Godot project at repo-root
`shell/` — which is what `phase-1-plan.md`'s layout diagram specifies — is
outside the context and cannot be copied into the image. Whichever way this is
resolved, the CI `paths:` filter has to be resolved with it: it currently matches
`os/**` only, so shell edits that build fine locally would silently never trigger
a CI build, and nothing would ever be pushed. That is the failure mode worth
naming, because it is the quiet one.

**7. A minimal compositor is where Godot's Wayland backend crashes rather than
degrades.** Missing Wayland globals are survivable — the backend null-checks
them — but a global at too *low* a version is a fatal protocol error, and that
class of bug is still live upstream (godot#90612 under Weston; godot#118157
killed both 4.6.2 and 4.7-dev3 at launch). If the shell dies instantly under cage
with a `wl_registry` protocol error in the journal, that is this family and not
the shell code. Under plan A the shell is on XWayland and never touches it.

## What M3 deliberately does not contain

The tile grid is a grid of nothing. That is the milestone, not an omission:

- **No library.** Nothing enumerates installed applications; the tiles are
  placeholders. Enumerating Flatpak refs is Phase 1 M2.
- **No store.** No AppStream catalog, no search, no install, no download
  progress. Phase 1 M3.
- **No real launching.** "Launch" swaps to a placeholder fullscreen scene and
  comes back. It exists to be the seam Phase 1's `Launch` RPC bolts into, and to
  prove focus survives the round trip. The shell never spawns a process — under
  Phase 1's architecture it never will, because the daemon is the single
  supervisor of foreign processes.
- **No daemon and no IPC.** There is no `marwand`, no WebSocket, no JSON-RPC and
  no `proto/`. The shell is a pure renderer with nothing to render from yet.
- **No icons, no artwork pipeline, no audio, no on-screen keyboard, ~~no
  settings~~.** Each has a phase. *(Amended 2026-08-06: a read-only settings
  page was pulled forward — see the second amendment below. Mutable settings
  keep their phase.)*

The reason for the discipline is that M3's acceptance criteria are about the
appliance, not the UI: navigate from the couch, and `kill -9` the shell over SSH
and be back at the grid in under three seconds with no text at any point. Both
are satisfied by an empty grid, and neither becomes easier with a full one.

## The dev loop this makes possible (D5)

`resolve_client` is re-resolved on **every** restart, not once at session start,
which is what turns the override into a loop rather than a boot-time switch:

1. Export or extract a fresh `marwanos-shell`.
2. `scp` it to `/var/marwanos/dev-shell/marwanos-shell` and `chmod 0755` it.
3. `pkill -9 -u player marwanos-shell`.

The supervision loop restarts, re-resolves, and comes back on the new binary in
about a second. No rebuild, no push, no `bootc upgrade`, no reboot. Both halves
of the override are required — the executable *and* `/var/marwanos/devmode` — so
a forgotten dev build cannot quietly become what the appliance ships.

Two silent failure modes are worth knowing before they cost an hour, and both are
documented in `dev-setup.md`: a dev binary that is not executable falls back to
the baked client without a word (`[ -x ]` fails and `resolve_client` returns
`BAKED_CLIENT`), and five restarts inside sixty seconds trips the crash guard, at
which point the compositor holds an empty screen until `greetd` is restarted. The
journal line `marwanos-session: starting client …` names which path was taken and
settles both.

## Consequences

- **The shell layer changes on every UI edit**, so a `bootc upgrade` after a UI
  tweak transfers ~100 MB rather than the few KB a version bump costs today. That
  is precisely the cost D5's override exists to avoid; the image path is for
  builds a target should keep, not for iteration.
- **A cold build now downloads ~1.3 GB from github.com.** The factory gains an
  external dependency beyond the registries M0 already needs, and CI is cold every
  time. Measure it on the first CI run and write the number down next to the
  existing 515 s / 70 s. If it hurts, the escalation in this repo's idiom is a
  separately-published toolchain image consumed by digest — but not before it is
  measured.
- **`vkcube` stays in the image.** It is the only way left to tell a compositor
  failure from a shell failure without a console, and ADR 0004's spike commands
  still use it. Its removal is an M4 escape-hatch audit question, not an M3 one.
- **ADR 0004's step-4 commands changed process name.** `pkill -9 -u player
  vkcube` kills nothing once the baked client is the shell — a test that reports
  a pass having done nothing. Updated in place there.
- **The Godot editor is the first GUI tool to author files into this repo.**
  `.gitattributes` was written for hand-authored text; a tool that re-saves
  `project.godot`, `export_presets.cfg` and every `.tscn` on its own schedule is a
  new CRLF vector and a new binary-corruption vector. Both rules extended.
- **An executable under `/usr/lib` gets the SELinux type `lib_t`, not `bin_t`.**
  The session script has been in that position since M1 and ran on hardware with
  SELinux Enforcing and no denials, so this is a known-good pattern rather than a
  new risk. If the session is ever confined — an M4 question — this directory
  needs a `file_contexts` drop-in or a move to `/usr/libexec/marwanos/`. D5 names
  `/usr/lib/marwanos/shell/` explicitly, so it does not move now.
- **Export output is not byte-reproducible.** The toolchain is pinned; the
  artefact is not guaranteed identical across builds. Do not build any
  verification story on comparing hashes of `marwanos-shell`. Verify the pin and
  the assertions.

## Open questions

1. ~~**Where does `shell/` live, and does CI notice it?**~~ Resolved: the build
   context moved to the repo root (`build-push.sh` and the workflow both pass it,
   with `--file os/Containerfile`), and the CI `paths:` filter covers `shell/**`.
   Finding 6's quiet failure mode is closed.
2. **4.7.1 or 4.7.2?** 4.7.2-rc1 exists as of 2026-08-03. Bumping mid-milestone
   costs two URLs and two sums; staying on 4.7.1 costs nothing until something
   fixed in 4.7.2 turns out to matter. Decide once, deliberately, and not while
   debugging something else.
3. ~~**Does the export actually run on this image?**~~ Resolved on hardware
   2026-08-05: the export ran inside the real session on the real GPU, drew,
   navigated, and survived `kill -9` with a 0.45 s respawn
   ([ADR 0005](0005-compositor-decision.md)).
4. ~~**Is `ENABLE_GAMESCOPE_WSI=1` safe on the cage path?**~~ Mooted by ADR 0005:
   the cage fallback and the compositor lever are removed from the session
   script, so there is no cage path left to be unsafe on. (For the record, the
   shell did run under cage on the boot-3 harness without a WSI-layer failure.)
5. **What does the shell do when the controller goes away?** M3 requires an
   explicit player-1 notion and hotplug survival, and Godot's hotplug signals have
   open upstream bugs (a disconnect that never fires when device 0 goes first; a
   reconnect that emits nothing at all). Keying the claim on the joypad GUID
   rather than the index survives both, but the fallback behaviour — poll the
   connected list, treat prolonged silence as a possible disconnect — is a
   hardware-run answer, not a desk one.

## Amendment (2026-08-06): accepted, with two changes the hardware run earned

**The decisions above survived contact with hardware unmodified.** The export
came up inside the real session on the real GPU on 2026-08-05, which is the
condition the header set for acceptance. The pinned-toolchain build, the
embedded-pck seam, the layer placement and the default display driver all
behaved as designed; findings 1–5 were each load-bearing at least once. What
changed afterwards is above this ADR's waterline, but is recorded here because
this document describes the scaffold it happened to:

- **The tile grid became a home rail.** The UI this ADR's scaffold table calls
  "tile grid, focus navigation" is now a console-style home: one horizontal rail
  of cards, one enlarged selection at a fixed x, a hero wash and title block
  behind it. Nothing in this ADR's decisions is disturbed — the binary, its
  provenance, its seam and its input findings are all layout-independent. The
  navigational argument for the change lives in `shell/src/shell_root.gd`'s
  header; the milestone record is in phase-0-plan.md M3. `tile.gd` keeps its
  name precisely so the prose trail (this ADR included) stays readable.
- **The crash guard now draws an error screen.** `show_error_screen` in the
  session script runs the baked client — never the dev override — with
  `MARWANOS_SHELL_ERROR_SCREEN=1`, and `error_screen.gd` draws a designed frame
  instead of the black TV the hold used to leave. One attempt, unsupervised; if
  the frame itself dies, the silent hold is exactly what it was. The residual
  case (a binary that fails before GDScript runs) is named in that file's
  header and deliberately not solved.

## Amendment (2026-08-06, later): the skeleton grew a settings page

Phase 0's non-goals excluded "any settings UI", and that exclusion was amended
in phase-0-plan.md the same day at the owner's request. What was added respects
this ADR's findings rather than stretching them:

- **A second seam, not a bigger launch seam.** `settings.gd` copies the launch
  seam's shape — one entry point, two signals, one surface at a time — and is a
  separate autoload precisely because Phase 1 rewires `launcher.gd` to marwand.
  A shell-internal screen swap sitting inside the launch seam would become an
  RPC by accident; kept apart, `Launcher.launch` remains the only call into the
  launch path. The home rail hands the screen over identically for both seams
  (`_hand_screen_over` / `_take_screen_back` in `shell_root.gd`).
- **Entered from the rail, not from a new button.** The one-axis argument
  holds: the settings card (`settings_tile.gd`, extending `tile.gd`) is the
  last card on the rail, shell furniture appended by `shell_root` rather than a
  catalogue entry, so it survives the catalogue's Phase 1 deletion. The input
  map still defines exactly six actions.
- **Read-only, as a decision.** `settings_screen.gd` shows os-release, engine,
  display server and mode, adapter, and the claimed controller — the things
  otherwise answerable only via journalctl on a machine with no terminal. A row
  that changed something would need somewhere to send the change; that
  somewhere is marwand, so mutable settings arrive with Phase 1. Rows log
  `read-only in Phase 0` on A rather than staying silent. Navigation is the
  rail rotated 90°: one axis, hard stops, perpendicular pointed at self.

## Amendment (2026-08-07): the top bar grew hands, and the shell grew a store

At the owner's request the home screen moved to the PS5's shape, and this
amendment records what that reversed, what it added, and where the honesty
line sits.

- **It reverses the second amendment's "entered from the rail, not from a new
  button."** Settings left the rail: the card is deleted
  (`settings_tile.gd`) and the entry point is now a gear icon in the top bar,
  next to a store icon — both focusable (`icon_button.gd`, glyphs drawn with
  primitives in `glyphs.gd` rather than shipped as the repo's first binary
  asset). The rail's one-axis purity yields ONE move: up from any card lands
  on the store icon, down from the bar returns to the selected card
  (`_scroll_to_selected` re-points the buttons' down-neighbour on every
  selection, so the round trip is not a teleport). Everything is still an
  explicit neighbour table.
- **The stores screen is the third fullscreen surface**, and it is the settings
  seam's pattern copied verbatim as that seam's header predicted: `stores.gd`
  (autoload `Stores`) with open/close signals, one surface at a time, mutual
  guards against settings and the launcher. Side tabs on the left
  (`store_tab.gd`, the settings row extended), the selected store's page on
  the right.
- **What "the page is rendered" means, honestly.** The page is drawn BY THE
  SHELL — wash, name, tagline, description, and the live install line from the
  status seam. It is not the store's own UI embedded in a pane: nesting a
  foreign client's window inside a Godot control is compositor work gamescope
  does not offer its clients, and a webview would be the first native
  extension. Pressing A launches the store app fullscreen through the launch
  seam — which is what the PS5's own store tile does — and quitting it lands
  back on the page (the rail's restore defers to open surfaces;
  `_on_launch_finished` checks `Stores.is_open()`).
- **Steam moved with it.** The rail carries no shell furniture and no store:
  its catalogue is placeholders until Phase 1's `ListInstalled` fills it with
  a library. Steam's launch entry and its install narration both live on the
  store page now, and the exec gained `steam://store` so A opens the client on
  its storefront.
- **The bar's indicators stay indicators.** The wifi glyph by the clock (fan
  when online, struck fan in alert amber when offline, absent when the system
  has made no claim) renders the status seam; it is not focusable. The
  settings screen gained Network/Connection/Wi-Fi rows from the same seam —
  read-only, like every row, because joining a network needs a keyboard UI and
  a write path to NetworkManager, and both are marwand's. The Wi-Fi row names
  the per-stick profile instead of pretending otherwise.

## Amendment (2026-08-07, later): the placeholders are gone, and the rail is real

The twelve placeholder entries were deleted at the owner's request. The rail
now lists what is actually installed, the way a desktop's app launcher does.

- **The scan is a system service, not shell code.** `marwanos-appscan` walks
  the XDG application directories, applies the freedesktop filter, resolves
  each icon to an absolute PNG, and writes `/run/marwanos/apps.tsv`;
  `installed.gd` (autoload `Installed`) polls it and hands the rail a list.
  This is the status seam's rule applied again — the shell walks no
  directories and parses no desktop entries — and it retires the same way:
  Phase 1's `ListInstalled` returns the same record shape, so the rail is
  rewired by replacing this one seam.
- **The filter is GNOME's, plus one subtraction.** `Type=Application`, not
  `NoDisplay`, not `Hidden`, `TryExec` must resolve — and *also* not
  `Terminal=true`, which GNOME does show. This appliance ships no terminal
  emulator, so an `htop` card would spawn a process with nowhere to draw: a
  card that does nothing when pressed. Everything else in the base image's
  `/usr/share/applications` is `NoDisplay` — the IBus setup tools, the portal,
  Xwayland — so on a fresh image the filter leaves **nothing**, and the apps
  that appear are the ones first boot installs.
- **Cards are also shown for apps that are still arriving.** The scanner emits
  a record per pending install (from `marwanos-flatpak-install`'s state files)
  carrying a name and no exec; the shell titles the card, narrates the state in
  its subtitle, and `tile.gd` refuses to launch it. That refusal lives in the
  card rather than in the seam on purpose: `Launcher.launch` stays the only
  call into the launch path and stays free of policy about what deserves
  launching. Without this the first boot would show an empty rail for the
  minutes a browser takes to download, with nothing anywhere saying why —
  which is the complaint that started this whole line of work.
- **Cards draw real icons now.** `tile.gd` loads the PNG at runtime (`Image` +
  `ImageTexture` — these files are on the running system, not in the export
  pack, so `preload` cannot reach them) and falls back to the wash on any
  failure. An enumerated app has no brand colour, so its wash is derived from
  a hash of its id: stable across rescans and reboots, which keeps the rail a
  place with a remembered shape.
- **The empty rail is a designed state, not a failure.** A fresh stick has
  nothing installed and says so — "No apps installed / Open the Store above to
  install something" — with the A hint hidden and focus falling to the store
  icon, so the empty state is a signpost rather than a dead end.
- **Steam's games are not applications.** They ship no desktop entries, so
  this rail will not list them however many are installed; that needs Steam
  library integration, which is marwand's. What this amendment delivers is
  honest about which of the two it is.

## Amendment (2026-08-07, fifth): settings stop being read-only, for Wi-Fi only

The second amendment made the settings page read-only and said why: "a row that
changed something would need somewhere to send the change, and building a
second, temporary path for that is exactly the growth launcher.gd's header says
belongs in the daemon." That reasoning was sound and it is now overridden,
because it had a consequence nobody priced in — **an appliance that cannot join
a network cannot be repaired from the couch at all.** Every recovery path this
project has (bootc upgrade, devmode ssh, the Flathub installs) needs a network,
and the only way to give it one was a second computer, a text editor and a
per-stick NetworkManager profile written by hand. On 2026-08-07 the radio
failed to appear and that price came due. The owner asked for the workflow.

What the reversal does and does not concede:

- **The shell still does not touch NetworkManager.** `marwanos-wifi` owns every
  `nmcli` call, every profile, and the passphrase's entire lifetime. The shell
  writes one small file — a verb and at most two arguments — into a directory
  that exists for that purpose. This is the same file-based seam as the status
  and app scanners, run backwards for the first time.
- **The reverse channel is deliberately not general.** Three verbs (`scan`,
  `connect`, `forget`), no "run this", and nothing the shell sends is ever
  interpolated into a command string. An SSID is attacker-chosen data — anyone
  in radio range can name an access point `; rm -rf /` — so it crosses into
  `nmcli` as an argv element and never as text in a command, and the script
  contains no `eval` and no `sh -c` — verified by inspection and by exercising
  the parser against a mocked `nmcli` during development, not by a committed
  test (this repo has no test runner).
- **The passphrase never reaches a command line either.** `nmcli device wifi
  connect … password …` would put it in `/proc/<pid>/cmdline`, which is mode
  0444 — readable by every process running as `player`, which is the shell,
  Steam and the browser. So `do_connect` writes the NetworkManager keyfile
  itself, 0600 root:root, and brings the profile up by id; the only thing that
  reaches an argv is the SSID, which was never secret. Bolting the request
  file shut and then handing the same secret to a world-readable interface
  would have been theatre.
- **The passphrase is handled honestly rather than hidden.** It sits in
  `/run/marwanos/wifi/request` (tmpfs, 0600, in a 0700 player-owned directory)
  for the moment between the shell writing it and the service consuming and
  deleting it. Nothing logs it: the shell logs the SSID and a character count,
  and the service truncates `nmcli`'s error text at the word `password`
  because some failure paths echo the secret back. A D-Bus secret agent would
  avoid the file entirely and is marwand's job; it is not a reason to leave the
  appliance unable to join a network.
- **`forget` exists for a specific failure.** A network saved with a wrong
  passphrase fails on every subsequent boot, and without a way to delete it
  from the couch the machine is stuck needing the second computer again — the
  exact thing this amendment removes.
- **The input map grew from six actions to eight.** `ui_shell_x` (Shift) and
  `ui_shell_y` (Delete/Forget) exist because typing a passphrase on a 5×10 grid
  with a thumbstick made every correction a journey. Both are shortcuts only:
  Shift and Delete are also on-screen keys, so a pad without those buttons
  loses convenience rather than the feature.
- **"No adapter" is a first-class screen, not an empty list.** This is the
  state this hardware actually has when Windows Fast Startup holds the CNVi
  radio, and an empty network list would send someone to stand closer to the
  router for a problem living in another operating system. The screen names the
  cause and the fix.

**What is still read-only:** everything else on the settings page. This is one
exception with a named justification, not the beginning of a mutable settings
surface. The next row that wants to change something should wait for marwand
unless it can make the same argument this one did.
