# Phase 1 — the library

> **Goal:** From the couch, with only a controller: see installed apps in a grid, browse Flathub, install an app, watch it download, launch it fullscreen, quit back to the shell.

**Prerequisite:** Phase 0 complete — the bootc image boots silently into gamescope (or cage, per the plan A/B decision) running the Godot shell skeleton, and `bootc upgrade` deploys new builds.

**Non-goals (explicitly deferred):**
- Proton / Windows games via umu → Phase 2
- Guide overlay over running apps → Phase 2
- Full settings, Bluetooth pairing, polished on-screen keyboard → Phase 3
- Sleep/resume, background updates → Phase 4

---

## Architecture

Two processes, one contract:

```
┌─────────────────────┐    JSON-RPC over WebSocket     ┌──────────────────────┐
│  shell (Godot 4)    │◄──────── 127.0.0.1:7411 ──────►│  marwand (Rust)      │
│  grid, store UI,    │                                │  library daemon      │
│  focus, rendering   │                                └──────┬───────────────┘
└─────────────────────┘                                       │
                                              ┌───────────────┼────────────────┐
                                              ▼               ▼                ▼
                                        libflatpak      AppStream catalog   child processes
                                        (install/run)   (Flathub metadata)  (running apps)
```

### Why a separate daemon

- Godot has no native D-Bus or Unix-socket support. Rather than writing a GDExtension binding for libflatpak, keep the shell a pure renderer and put all system integration in a small Rust daemon.
- The daemon outlives shell crashes: if the shell restarts (Phase 0 supervision), a running install continues and state is re-synced on reconnect.
- Phase 2 (umu/Proton launching) and Phase 3 (settings backends) extend the same daemon with new modules — the shell/daemon contract is the permanent architecture of MarwanOS, not a Phase 1 hack.

### Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| D1 | Daemon language | Rust | `flatpak` crate (gir bindings to libflatpak) gives install progress callbacks; memory-safe long-running process |
| D2 | Flatpak installation | `--user` for the `player` user | No polkit prompts, no root, lives in `/var/home` (survives bootc image swaps) |
| D3 | Store metadata | Flathub AppStream catalog, synced locally via libflatpak | Offline-capable browse/search; no dependency on a web API for core function. Flathub REST API optional later for "popular/trending" rows |
| D4 | IPC | JSON-RPC 2.0 over WebSocket on `127.0.0.1:7411` | Godot 4 has `WebSocketPeer` built in — framing for free, no GDExtension. Auth via token file at `$XDG_RUNTIME_DIR/marwand.token`, mode 0600 |
| D5 | App model | Single `LaunchTarget` type: `{id, source, name, icon, categories, launch_spec}` | `source = "flatpak"` today; `"umu"`, `"emulator"` later slot in without UI changes. Browser and games are the same object — the core MarwanOS thesis |
| D6 | Launch mechanism | Daemon spawns `flatpak run <appid>`, tracks the process group, emits `AppExited` | Shell never spawns anything; the daemon is the single supervisor of foreign processes |

### IPC contract (v1)

Requests (shell → daemon):

| Method | Params | Returns |
|--------|--------|---------|
| `ListInstalled` | — | `LaunchTarget[]` |
| `Search` | `query, category?` | `StoreEntry[]` (from AppStream catalog) |
| `GetAppDetails` | `appid` | description, screenshots, download size, installed size |
| `Install` | `appid` | job id (progress via events) |
| `Uninstall` | `appid` | job id |
| `Launch` | `target_id` | run id |
| `Kill` | `run_id` | ok (SIGTERM, then SIGKILL after 5 s) |
| `ListRunning` | — | `RunningApp[]` |
| `GetUpdates` / `UpdateAll` | — | pending updates / job id |

Events (daemon → shell):

| Event | Payload |
|-------|---------|
| `InstallProgress` | job id, bytes done/total, stage (download/deploy) |
| `JobFinished` / `JobFailed` | job id, error string |
| `AppLaunched` / `AppExited` | run id, exit code |
| `LibraryChanged` | — (shell re-fetches `ListInstalled`) |

Schema lives in `proto/` as the single source of truth; both sides validate against it.

### Repo layout (established this phase)

```
gaming/
  os/         Containerfile, systemd units, session scripts   (Phase 0)
  shell/      Godot 4 project                                 (Phase 0+)
  daemon/     marwand — Rust workspace                        (Phase 1)
  proto/      JSON-RPC schema + shared types                  (Phase 1)
  docs/       plans, ADRs
```

---

## Milestones

### M1 — launch plumbing (~1–2 weeks)

The vertical slice: one hardcoded tile launches one pre-installed Flatpak and returns.

- [ ] `marwand` skeleton: WebSocket server, JSON-RPC dispatch, token auth, structured logging
- [ ] systemd user service `marwand.service` for the `player` user; add to the os/ image
- [ ] `Launch`: spawn `flatpak run`, own the process group, reap children, emit `AppLaunched`/`AppExited`
- [ ] Shell: WebSocket client with auto-reconnect + state re-sync on connect
- [ ] Shell: on `Launch`, pause rendering/input; on `AppExited`, restore focus and resume
- [ ] Verify focus handoff in the real session (gamescope gives focus to the new client and back on exit) — and in the nested-gamescope dev rig
- [ ] Dev rig documented in `docs/dev-setup.md`: shell + daemon under nested gamescope on any Linux desktop — Phase 1 needs no console hardware

**Acceptance:** from the grid, launch Firefox (pre-installed via CLI), use it, quit; back at the grid with focus. Ten times in a row: no zombie processes, no focus loss, shell never visible behind the app.

### M2 — the installed library (~1–2 weeks)

The grid becomes real.

- [ ] Enumerate installed refs via libflatpak (user + system installations), filter runtimes/BaseApps — apps only
- [ ] Join refs against AppStream data: display name, summary, icon
- [ ] Icon pipeline: extract to a PNG cache dir; shell loads textures asynchronously, placeholder tile while loading
- [ ] Watch `FlatpakInstallation` for changes → `LibraryChanged` → grid updates live
- [ ] Grid UI: dynamic tiles from `ListInstalled`, controller focus navigation at any grid size, empty-state screen
- [ ] Sort: most-recently-played first (play history stored by daemon in a state file — begins now)

**Acceptance:** `flatpak install --user flathub org.videolan.VLC` over SSH → VLC appears in the grid within seconds, with icon, no shell restart. Uninstall → tile disappears.

### M3 — the store (~2–4 weeks, the big one)

Browse and install without touching a keyboard.

- [ ] AppStream catalog sync on schedule + on demand (equivalent of `flatpak update --appstream`); parse the compressed catalog into a local index
- [ ] Store home: curated category rows — Games, Browsers, Media, Emulators — populated by AppStream category + a hand-maintained curation list in the daemon (MarwanOS's opinion; this is the anti-bloat filter)
- [ ] App detail page: screenshots, description, download/installed size, install/uninstall button
- [ ] Search with a minimal in-shell keyboard widget (grid-of-letters; throwaway quality is fine — Phase 3 replaces it)
- [ ] Install queue: one job at a time, progress bar on the tile and detail page from `InstallProgress`, cancel support
- [ ] Free-space check before install; readable error if insufficient
- [ ] Updates row: pending updates via `GetUpdates`, one-button `UpdateAll`

**Acceptance:** keyboard unplugged. Using only the controller: find a game in the store, read its page, install it, watch progress, launch it when done. Also: search for "firefox" via the letter grid and install from a search result.

### M4 — lifecycle polish (~1–2 weeks)

The difference between a demo and a console.

- [ ] Launch feedback: immediate "starting…" state on the tile; guard against double-launch
- [ ] Launch-failure detection: process exits nonzero or produces no window within timeout → readable error toast, log captured to journal
- [ ] Kill path: from the shell, force-quit a hung app (`Kill` → SIGTERM → SIGKILL); becomes a guide-menu item in Phase 2
- [ ] Controller-in-sandbox audit: verify gamepad input works inside sandboxed Flathub games (`--device=input` vs `--device=all`); daemon applies a per-category Flatpak override policy where needed
- [ ] Toast/notification component in the shell (reused forever after)
- [ ] State file hardening: play history and settings survive crash mid-write (write-temp-then-rename)

**Acceptance:** launch a game, SIGSTOP it over SSH → force-quit from the shell works. Launch an app that instantly exits 1 → clear error, shell fine. Fill the disk → install fails with a readable message. Cold boot → full loop works from scratch.

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Focus handoff quirks between shell and launched app under gamescope | Core UX broken | M1 exists to hit this first; nested-gamescope rig reproduces it on a desktop; plan B (cage + nested gamescope) changes the details, so lock plan A/B before M1 |
| Flatpak sandbox blocks controller input in some apps | Games unplayable | M4 audit + override policy; test with a real Flathub game during M1, not M4 |
| AppStream metadata quality varies (missing icons, bad screenshots) | Store looks broken | Placeholder assets; curation list favors well-maintained apps |
| libflatpak Rust bindings gaps | Blocked daemon work | Fallback: shell out to `flatpak` CLI with `--noninteractive`; progress parsing is uglier but proven |
| Godot WebSocket reconnect edge cases | Shell/daemon desync | State re-sync on every connect (daemon is the source of truth; shell holds no authoritative state) |

## Phase 2 hooks (build now, use later)

- `LaunchTarget.source` field — `"umu"` targets appear in the same grid with zero UI work
- Daemon owns all process supervision — the guide overlay's "quit game" is just `Kill`
- Toast component and letter-grid keyboard — reused/replaced in Phases 2–3
