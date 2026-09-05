# Removing Steam — the plan

> **Goal:** Steam leaves the image entirely. Every Windows game runs through
> umu-run, which is already here. The appliance keeps one Windows runtime
> instead of two, gets the gamescope main-application slot back, gets the Guide
> button back, and drops the only third-party repository this image has ever
> carried.

**Status:** proposed, nothing implemented. Written 2026-08-26 on the owner's
instruction ("if I scrap steam completely from the plan this could work").

**Supersedes on acceptance:** [ADR 0011](adr/0011-steam-baked-in-not-sandboxed.md)
entirely. Amends [ADR 0012](adr/0012-a-library-of-many-sources.md) — one fewer
source. **An ADR 0013 is owed before any of this is merged**; this file is the
working-out, not the decision.

---

## Why now, when this was already tried once

Steam has been removed from this image before. On 2026-08-13 the owner said
"without steam I do not want to install steam anymore" and the flatpak came out
of [`shipped-apps`](../os/files/usr/lib/marwanos/shipped-apps) — the headstone
is still in that file. Steam then came *back* the same day, as an RPM in the
image, under ADR 0011.

What is different this time is [`winrun`](../os/files/usr/lib/marwanos/winrun)
and the umu-launcher RPM that landed with it (the Containerfile's `UMU_VERSION`
block, and the install at ~line 623). The first removal left the machine with
no way to run a Windows game at all, which is why Steam came back. That hole is
now filled by something this project controls. **The removal that failed in
August failed for a reason that no longer holds.**

## What Steam actually costs this image

Every item below is already written down in the tree; none of it is new
analysis. The Containerfile's own Steam block (~lines 589–613) is the primary
source.

| Cost | Where it is recorded |
|---|---|
| **RPM Fusion** — the first and only third-party repository this image carries. It was added for Steam and nothing else; a build assertion proves it (`RPM Fusion supplied more than steam`, ~line 1217). | `Containerfile` ~589, ~1202–1218 |
| **The gamescope main-application slot.** Embedded mode has exactly ONE, keyed to `STEAM_GAME=769` — Valve's own value, which Steam claims. The shell competes with Steam for the slot that decides what the compositor thinks the machine *is*. | `Containerfile` ~604–607 |
| **The Guide button.** Steam Input takes it. Commit `5c8ac4a` — *"Share opens the home menu, because Guide is not always ours"* — is a workaround for exactly this, and it is a worse home button. | `Containerfile` ~607, commit `5c8ac4a` |
| **Big Picture is a one-way door.** Its own Shut Down does nothing without SteamOS's session manager, and this image has no console login to escape to. | `shipped-apps`, ADR 0011 |
| **Four of seven window profiles.** `no-bg-steam`, `no-wsi`, `steam-split`, `steam-aware` out of `no-bg-steam no-wsi steam-split loose steam-aware yield plain` — pinned in two places, so they cost double to carry. | `Containerfile` ~1169–1171 |
| **A 20k-word client contract** describing a program we do not own. | [`steam-client-contract.md`](steam-client-contract.md) |
| **Half of `appscan`** — reading `appmanifest_*.acf`, the store-art choreography, the stores screen's "is Steam here yet" question. | `appscan` header |

There is also a **hypothesis, not a claim**: the flicker investigation in
[`flicker-nvidia-610.md`](flicker-nvidia-610.md) is 32k words, and the
Containerfile notes at ~line 1006 that the 2026-08-11 report describes *flicker
that starts when Steam does*. Removing Steam may close that investigation. It
may also prove Steam was only ever the trigger and not the cause. **Do not
count this as a benefit until M4 measures it.**

## What it takes with it — read this before agreeing

**Every Steam-DRM'd game stops working. Permanently. There is no workaround,
because the DRM is the Steam client.**

The library after this change is: Windows games that are DRM-free (GOG, itch,
bundles, disc), native Linux games, Flatpaks, and whatever emulation arrives
later. That is a real library and it is one this project can fully own. It is
also a *different* library from the one on the shelf today.

This is the whole decision. Everything else in this document is mechanics.

## The one thing that gets harder

**umu fetches Proton at first launch, over the network, into the player's home.**
This is upstream's design, recorded in the Containerfile (~86–89) and in
`winrun`'s own header: *"A machine that has never been online will fail its
first Windows game and succeed afterwards."*

Today that is survivable, because Steam is the main Windows path and umu is the
side path. **After this change umu is the only Windows path**, and a
first-boot-offline machine becomes an appliance that silently cannot run any
game it owns — on a device whose Phase 0 gate is *zero frames of text on
camera*. There is no console to explain the failure.

This promotes the runtime fetch from a known wart to a **blocking prerequisite**.
M1 exists to fix it, and nothing downstream should start until it is done.

---

## Architecture after

```
                       ┌──────────────────────┐
                       │  shell (Godot)       │
                       │  rail, cards, launch │
                       └──────────┬───────────┘
                                  │ apps.tsv / windows.tsv
                       ┌──────────┴───────────┐
                       │  appscan             │  no .acf reading,
                       │  (desktop entries +  │  no store art,
                       │   Windows index)     │  no Steam question
                       └──────────┬───────────┘
                                  │ win.<slug>
                       ┌──────────┴───────────┐
                       │  winrun <slug>       │  the ONE place the
                       └──────────┬───────────┘  runtime is named
                                  │
                       ┌──────────┴───────────┐
                       │  umu-run → Proton    │  pre-seeded in the image
                       └──────────────────────┘
```

One Windows runtime. One launch seam. The compositor's main-application slot
belongs to the shell.

### Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| D1 | Steam's delivery | Removed entirely — RPM, RPM Fusion, and the flatpak path that is already gone | Half-measures were tried twice. A machine with "Steam not installed but installable" keeps every cost in the table above and adds a code path nobody exercises. |
| D2 | Windows runtime | `umu-run`, unchanged, still named in exactly one place (`winrun`'s `RUNTIME`) | ADR 0012's rule. `winrun` already isolates this correctly; this change does not touch its shape. |
| D3 | Proton delivery | **Pre-seed a pinned Proton build into the image**, alongside the pinned umu RPM | Closes the offline-first-boot hole above. Costs image size and a second version pin to bump. The alternative — first-boot download — is not compatible with a silent appliance. |
| D4 | `i686` userspace | **Stays.** | Containerfile ~326 carries it for Proton's 32-bit titles, not for Steam. Removing it alongside Steam would break umu quietly. Assert it stays. |
| D5 | Window profiles | Delete the four Steam-shaped ones; keep `loose`, `yield`, `plain` | They exist to negotiate with a program that will not be running. Keeping them means keeping their assertions and both pin sites. |
| D6 | `STEAM_GAME=769` | The shell claims the slot | The reason it could not before is leaving. This is the largest single win and it should be M2's acceptance test. |
| D7 | Guide button | Reclaimed; revert `5c8ac4a`'s Share-as-home workaround | Guide is the home button on every console the brief references. Share was a compromise with Steam Input. |
| D8 | `steam-client-contract.md` | Moved to a history note, not deleted | It documents why two Steam approaches failed. Deleting it invites a third attempt. |

---

## Milestones

### M1 — Proton in the image (blocking prerequisite)

Nothing else starts until a Windows game launches on a machine that has never
been online.

- [ ] Pick and pin a Proton build (version + sha512) the way `UMU_VERSION` is pinned
- [ ] Lay it down where umu looks for it, at image build time, with no runtime fetch
- [ ] Confirm umu uses the seeded build and does **not** reach the network
- [ ] Build assertion: the Proton directory exists and is non-empty, in the same
      style as the existing `command -v umu-run` check (~line 1272)
- [ ] `scripts/bump-base.sh` (or a sibling) learns to bump the Proton pin

**Acceptance:** a freshly flashed stick, **network cable out from the moment it
first boots**, launches a DRM-free Windows game from the rail. No text on screen
at any point.

### M2 — Steam leaves the image

- [ ] `Containerfile`: drop the Steam block (~589–620) and the RPM Fusion enablement
- [ ] Invert the Steam-presence assertions (~1197–1251): they now assert **absent**,
      and RPM Fusion asserts absent rather than "supplied nothing but steam"
- [ ] Delete the four Steam window profiles and both of their pin sites (~1169–1171)
- [ ] Claim `STEAM_GAME=769` for the shell in the session
- [ ] Revert `5c8ac4a` — Guide opens the home menu
- [ ] `shell/src/window_profile.gd` (8 refs) follows the profile deletion
- [ ] Keep `i686` and assert it (D4)

**Acceptance:** the image builds with **zero third-party repositories**. The
shell holds the compositor's main-application slot. Guide opens home. A Windows
game still launches (M1's test, re-run).

### M3 — the library forgets Steam

- [ ] `appscan`: remove the `.acf` reading, `steam_art()`, the store-art seam and
      the stores-screen question; the Windows index and desktop-entry walk stay
- [ ] Retire `/run/marwanos/gameart.tsv` if store art was its only producer —
      **verify before deleting**
- [ ] Shell pass over the 165 `steam` references across 10 files.
      `system_status.gd` (22) and `settings_screen.gd` (9) are the substantial
      ones; `card.gd`, `launcher.gd`, `services.gd`, `setup.gd`,
      `setup_screen.gd`, `kiosk.gd`, `tv_theme.gd` are likely one-liners but
      none are assumed
- [ ] First-boot flow: `beb5378` *"offers Steam once"* — that offer goes
- [ ] `shipped-apps`: add the headstone. The file stays empty of ids, which it
      already documents as a valid state
- [ ] `steam-client-contract.md` → history note (D8)

**Acceptance:** `grep -ri steam shell/src os/files` returns only headstones and
history. The rail shows the real library from real sources. An empty library
draws the empty state, not an error.

### M4 — measure what was claimed

The only milestone that can invalidate the others.

- [ ] Re-run the flicker reproduction from `flicker-nvidia-610.md` on a
      Steam-free image. **Record the result whichever way it goes** and amend
      that document
- [ ] Cold-boot timing against the Phase 0 gate (< 15s, zero frames of text) —
      Steam's absence should help; confirm rather than assume
- [ ] Ten launch/quit cycles of a Windows game: no zombies, no focus loss, shell
      never visible behind the game

**Acceptance:** Phase 0's exit gate still passes, with the flicker question
answered either way.

---

## Risks

| Risk | Standing |
|---|---|
| **The library is smaller than the owner expects.** Every Steam-DRM'd title is gone. | Not a risk to mitigate — it is the decision. Stated here so it is never a surprise. |
| **Pre-seeded Proton drifts from what umu expects.** umu is built against Proton versions; a pinned pair can desync on the next umu bump. | Bump them together, assert both at build time. D3 accepts this cost knowingly. |
| **Image size** grows by a Proton build. | Measure in M1. If it is unacceptable the fallback is a first-boot fetch *with a visible progress screen*, which costs the silent-boot property — a worse trade, but a real one. |
| **Flicker was never Steam's fault.** | M4 exists to find out. This plan claims no flicker benefit. |
| **165 shell references** is a survey, not a count of edits; some will be load-bearing in ways grep does not show. | M3 is sized as a pass, not a sweep. Do not batch it with M2. |
| **A third Steam attempt.** This project has reversed on Steam twice. | D8 keeps the contract document; ADR 0013 must record *why*, not just *what*. |

## Open questions

1. **Does anything the owner actually plays survive?** This plan does not know
   the shelf. Before ADR 0013 is written, list the titles that matter and check
   each for a DRM-free source. If the answer is "none of them", the decision is
   different and this file is wrong.
2. **Emulation** — is it in the library after this, or still later? It is the
   obvious way the library gets big again without Steam, and `winrun`'s slug
   model would extend to it, but nothing in the tree commits to it.
3. **Does `marwanos-storeart` have a job left?** Its Flathub icon prefetch may
   outlive its Steam CDN half. M3 says verify; this is where the answer goes.
4. **`phase-1-plan.md` has drifted.** It still lists umu as a Phase 2 non-goal
   and describes a Rust `marwand` that does not exist — `appscan` and TSVs do
   that job today. Out of scope here, but it should not be read as current.
5. **What is the browser *for*, once Steam is gone?** `mowser.h`'s own crash
   story is *"the shell died the first time somebody pressed Buy"* — and that
   Buy button is the Steam store checkout, the use case ADR 0010 was built
   around. Removing Steam removes the browser's headline justification. Real
   uses remain (GOG and itch purchases, documents from the Files screen, the
   open web), but ADR 0013 has to restate the case or mowser becomes unowned
   work. Note also that `main` has **no browser at all** today: `shipped-apps`
   dropped the Chromium flatpak on the rationale that mowser replaces it, and
   mowser never merged — it exists only on `no-steam-installer` and some
   `claude/*` branches.
6. **Which shell survives?** Larger than this plan and filed separately in
   [`shell-fork-plan.md`](shell-fork-plan.md): keep the Godot shell and finish
   mowser, or adopt PC1's Electron shell and delete mowser. It is independent of
   the Steam decision — you face it either way — but it lands in the same ADR
   window, and if Electron wins then question 5 answers itself.
