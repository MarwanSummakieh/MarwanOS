# ADR 0012 — A library of many sources

**Status:** Accepted — this one authorises an implementation, and the deletion
it justifies has already happened
**Date:** 2026-08-13
**Relates to:** the compositor decision in
[ADR 0005](0005-compositor-decision.md); the shell skeleton in
[ADR 0006](0006-shell-skeleton.md); the embedding refusal in
[ADR 0008](0008-embedding-a-client-surface.md); our own Steam client and its
deletion in [ADR 0010](0010-our-own-steam-client.md); Steam baked into the image
in [ADR 0011](0011-steam-baked-in-not-sandboxed.md)

## Context

The owner's statement of what this project is for, 2026-08-13, after two months
of building something else:

> I simply am not getting the experience I want from this entire project which
> is the same ease of use you get from PS5 ... I do not want to be locked with
> Steam ... I wanted playnite but as an OS where no matter where I get the games
> from they get organized

Two requirements, and the second is the one every previous decision here has
quietly violated:

1. **Console ease.** One surface, a controller, no desktop underneath.
2. **Source independence.** Steam is *a* place games come from, not *the* place.

### What was actually built instead

Measured on `main` at 0cf2245, before this ADR's deletion:

- 58 GDScript modules in the shell. **Eight of them were a file manager**
  (`files_screen.gd` alone was 1,532 lines), plus a standalone image viewer, a
  CEF browser linked into the Godot binary, and a terminal.
- The game library — the actual product — was five modules, and it existed
  **twice**: once in GDScript (`catalogue.gd`, `gamemeta.gd`, `gameart.gd`,
  `installed.gd`) and once in Python under `game-launcher/`, with its own
  database, metadata provider and installer.
- [`marwanos-session`](../../os/files/usr/lib/marwanos/session/marwanos-session)
  was 1,979 lines, **1,350 of them comments**.

A desktop environment in console clothing. The thing the owner asked for was a
minority of the code, implemented twice, and surrounded by surfaces a console
does not have. That is why it does not feel like a PS5: not because the
architecture was wrong, but because most of the code was not aimed at the goal.

### The Steam-shaped hole in every previous decision

ADR 0010 built our own Steam client. It was deleted at 1ae1a26 (−9,127 lines).
ADR 0011 baked Steam into the image. The window profile's default is
`no-bg-steam`, whose own comment says Steam "is an app on the rail that opens
into Big Picture when opened, like any other entry."

Every one of those is a decision about *Steam*. None is a decision about a
library. A person who buys a game on GOG, itch or Epic, or who has a folder of
ROMs, has never been modelled here at all — and "open Big Picture" hands the
whole screen to Valve's UI, which is precisely the lock-in the owner named.

## The constraint that shapes everything

The obvious design — the shell on one X display, games on a second, gamescope
switching between them — **was tried on 2026-08-13 and reverted the same day.**
From the window profile's own comment on `DEFAULT`:

> This was briefly `steam-split` on 2026-08-13 and reverted the same day —
> steam-split's `-e` excludes any window without a `STEAM_GAME` atom from focus,
> and the shell is such a window, so it made the rail unfocusable.

This is worth stating plainly because it is counter-intuitive and it has already
cost a day:

- `STEAM_MULTIPLE_XWAYLANDS=1` + `STEAM_GAME_DISPLAY_0` genuinely does give
  games their own X server inside the *single* gamescope. **No nesting is
  required**, and nesting is known-bad here — 33a28a4 retired nested gamescope
  after it aborted three minutes into a real game.
- But the window management that makes the split useful is gamescope's `-e`
  (`--steam`), and `-e` makes focus conditional on a `STEAM_GAME` atom that the
  shell's window does not carry.

So the split is not free, and this ADR does **not** authorise turning it on. It
records the mechanism, the cost, and the one open question: whether the shell
can carry a `STEAM_GAME` atom of its own without steamcompmgr then treating it
as the game. That is an empirical question for the bench, not a design question,
and it is deliberately left open rather than guessed at.

Until it is answered, the shell and any launched game share one display and one
main-app slot, which is the arrangement that ships today.

## Decision

### 1. A source is an adapter, and Steam is one of them

The library is not "Steam plus exceptions." It is a set of **source adapters**
behind one interface, each answering the same three questions: what do you have,
what is installed, and how do I start this. Steam implements that interface. So
does everything else.

Adapters, in the order they earn their place:

| Source | Mechanism | Why this one |
| --- | --- | --- |
| Steam | read `steamapps/*.acf` | no API, no auth, no network; works while Steam is not running |
| Standalone Windows | `umu-launcher` | Proton **outside** Steam — the whole of "no matter where I get them" (see the amendment below) |
| Epic / GOG / Amazon | `legendary` / `gogdl` / `nile` | headless CLIs with JSON output; what Heroic already wraps |
| Emulators | ROM directory scan | the conventions ES-DE already established |

The first two are what this ADR authorises building. The rest are shaped by the
same interface and added when there is something to test them against.

### 2. Steam is a dependency, and making it stop being the host is unfinished

The goal is unchanged: the shell launches a Steam title with
`steam://rungameid/<id>` and Valve's interface is never what a person lands in.
A Steam game genuinely requires the Steam client for auth and DRM; it does not
require Steam's *UI*. That distinction is what makes source independence
possible at all.

**But this ADR cannot honestly claim the goal is reachable today**, because all
three ways of getting there have already been tried and each failed differently:

| Approach | What happened | Recorded in |
| --- | --- | --- |
| Cold client, URL only, no flag | Steam comes up in **desktop mode** — a mouse UI on a machine whose only pointer is a thumbstick — and is left running behind the game | `appscan`, the `-gamepadui` comment |
| Warm background client, then URL | The screen "turns off for a second then starts flickering" the moment Steam runs in the background | the owner, 2026-08-11; `window/profile` |
| `-gamepadui` along with the URL | Works, and hands the screen to Valve's Big Picture — the lock-in this project is trying to escape | shipped today |

Today's behaviour is the third row, and it stays until one of the other two is
made to work. `-gamepadui` is therefore emitted from **exactly one place** in
the tree, named as a constant, so that the bench experiment is a one-line change
rather than an archaeology exercise.

**The untested fourth option**, and the cheapest thing to try next: start the
cold client with `-silent` *and* the URL in the same invocation, so the client
resolves the launch without ever presenting a UI. `-silent` is known to still
map windows here — the owner has said plainly that conflict was never fixed — so
this may only reduce the problem rather than remove it. It has not been measured,
and this ADR does not pretend otherwise.

Under the `no-bg-steam` default the client is not running, so the first launch
of a session pays Steam's startup either way. That cost is accepted.

### 3. Metadata is a cache, not a dependency

Art and descriptions come from IGDB and SteamGridDB, are cached on disk, and are
**never** on the path between pressing A and a game starting. A library with no
network shows names and starts games. This is not new policy — it is
`game-launcher`'s existing metadata-off-by-default stance, kept while the code
implementing it is discarded.

### 4. What was deleted, and what only looked deletable

Deleted: the file manager (9 modules), the image viewer, the CEF browser and
`mowser/`, the terminal row, both library implementations
(`catalogue.gd`, `gameart.gd`, `gamemeta.gd`, `tile.gd`, `details_panel.gd`,
and all of `game-launcher/`). 39 files, ~10,000 lines.

Kept, after a first pass wrongly cut them by filename:

- [`app_overlay.gd`](../../shell/src/app_overlay.gd) — the home-button overlay,
  composited over the *live* game via `GAMESCOPE_EXTERNAL_OVERLAY`. The single
  most console-like thing in the tree, and it was nearly deleted for having
  "app" in its name.
- [`launcher.gd`](../../shell/src/launcher.gd) — the launch seam, carrying the
  hard-won rule that a Steam wrapper exits in under a second, so the shell must
  watch the **window** rather than the pid to know a game ended. Every source
  above needs that, not just Steam.
- [`apps.gd`](../../shell/src/apps.gd), [`installed.gd`](../../shell/src/installed.gd)
  — the flatpak install/remove seam. That is how *any* source gets installed:
  Steam, Heroic, RetroArch, Bottles.

The lesson is recorded because it will recur: in this tree a file's name
describes what it was first used for, not what it is.

## Consequences

- `shell_root.gd` is rewritten rather than patched. About 1,100 of its 2,037
  lines were the old rail, hero art and details panel.
- The pad-to-keyboard bridge in [`pad_keys.gd`](../../shell/src/pad_keys.gd) is
  kept with an empty table. Nothing uses it today. An emulator's menus are
  keyboard-driven and a Windows game run outside Steam has no Steam Input
  translating a controller, so it is cheaper to keep the seam than to re-derive
  it.
- `Tile.load_icon_image` moved to [`icons.gd`](../../shell/src/icons.gd). It was
  never about cards: it is the only code here that knows an SVG must be measured
  before it is rasterised.
- The `-e` question above is the next thing to settle on hardware, and until it
  is settled the per-game display split stays off.

## Amendment, 2026-08-13 — umu-launcher is in the image

The Windows adapter shipped with its runtime deliberately absent: `winrun`
named it, failed loudly without it, and left the choice open. This amendment
closes it.

**Decision: umu-launcher 1.4.4, as a single pinned RPM.**

The alternative was `wine`, which is in Fedora's own repositories and costs
nothing new to trust. It was not chosen because it is not the same product:
Proton's patches and bundled DXVK are a large part of why a modern Windows
game runs at all, and shipping the weaker runtime to avoid a decision would
have quietly made "no matter where I get them" mean "as long as it is an old
game".

This is the **second third-party source** this image has carried, after Steam's
own repository in ADR 0011 — whose block says none should be added "without an
ADR saying why". This is that ADR, and the commitment is deliberately the
smaller of the two available shapes:

- A **single pinned RPM**, not a repository. Nothing refreshes behind our back;
  a version bump is a diff with a new hash in it.
- Fetched, then **verified against a recorded SHA-512 before dnf is allowed to
  look at it**. dnf will install a truncated download that still parses, and a
  game that fails six weeks later is not a failure anybody traces back to a bad
  byte in an image layer.
- Built by upstream **for fc43 specifically**, the same Fedora this image runs,
  so its dependencies resolve from Fedora's own repositories rather than
  travelling with it.

### What this costs, stated plainly

- **The first Windows game needs a network.** umu downloads a Proton build into
  the player's home on first run. That is upstream's design, not a choice
  available here, and there is nothing to pre-seed without shipping a Proton
  build this project does not control. `winrun` reports the failure; the second
  attempt, online, succeeds.
- **Upstream's release process is now in the trust path.** The hash pins the
  bytes, not the intent behind them.

`MARWANOS_WINDOWS_RUNTIME` overrides the runtime for a bench run or for a title
that behaves better under plain wine, without rebuilding an image.

## What this ADR does not decide

- Whether the shell can carry a `STEAM_GAME` atom without becoming the game.
- Suspend and resume. The PS5 experience the owner named includes instant
  resume; that is a hardware and hypervisor capability, and suspend-to-RAM is
  the nearest reachable thing. It is not promised here.
