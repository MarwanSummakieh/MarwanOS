# 🎮 Game Launcher

A self-hosted web app for cataloguing your Windows games and installing/launching
them through [Bottles](https://usebottles.com/) (Wine) on Linux — with a modern
dark-theme UI, live install progress, and a one-command test mode.

> **Scope / legality.** This tool installs **Windows game installers that you
> already have on disk** — GOG offline installers, itch.io / Humble setups, your
> own backups, or any `setup.exe` / `.msi` you legally own. It does **not**
> scrape, search, download, or obtain games from anywhere. You point it at a
> file; it runs that file inside a Bottle and tracks the result. Only install
> software you have the right to install.

---

## Features

- **Library** — grid of cover art, instant search with auto-suggest, filters by
  genre / year / installed-state.
- **Add a game** — type a title and pick an installer with the built-in file
  browser (sandboxed to a folder you configure).
- **One-click install** — prepares a Bottle (Gaming preset), installs
  dependencies (DXVK, VKD3D, vcredist, .NET…), then runs your installer inside
  it. Live progress streams to the browser over **Server-Sent Events**, with a
  **Cancel** button.
- **Installed tab / Play / Uninstall** — launch installed games via
  `bottles-cli`, or remove them from your library.
- **History** — every install / launch / uninstall is logged to SQLite and to
  `logs/game-launcher.log`.
- **Settings** — Bottles CLI path, default bottle, dependency list, browse root,
  metadata provider, optional access token.
- **Optional cover art** — IGDB or SteamGridDB (needs your own free API key); the
  app is fully usable with no keys.
- **Import / export** your library as JSON.
- **Test mode** — simulates the whole Bottles pipeline so you can run and demo
  the app on any machine, even one without Bottles installed. **On by default.**

## Architecture

```
game-launcher/
├── backend/
│   ├── app.py             FastAPI: REST API, SSE progress, static hosting, auth
│   ├── bottles_manager.py bottles-cli wrapper (+ test-mode simulation)
│   ├── installer.py       async install jobs, progress queue, cancel
│   ├── database.py        SQLite schema + helpers
│   ├── metadata.py        optional IGDB / SteamGridDB cover art
│   ├── config.py          settings + defaults + env-var overrides
│   ├── logger.py          rotating file + stderr logging
│   ├── test_smoke.py      end-to-end test (no Bottles, no network)
│   └── requirements.txt
├── frontend/
│   ├── index.html         single-page UI
│   ├── styles.css         dark gaming theme, responsive
│   └── app.js             vanilla JS (no build step)
├── data/                  games.db (created on first run)
└── logs/                  game-launcher.log
```

Frontend is plain HTML/CSS/JS — no bundler, no npm. The backend serves it.

## Requirements

- **Python 3.10 – 3.14**
- **[Bottles](https://usebottles.com/)** installed (Flatpak or native) — *only
  needed once you turn test mode off.* The app auto-detects the Flatpak CLI
  (`flatpak run --command=bottles-cli com.usebottles.Bottles`) or a
  `bottles-cli` on your PATH.

## Setup

```bash
cd game-launcher
python -m venv .venv
. .venv/bin/activate           # Windows: .venv\Scripts\activate
pip install -r backend/requirements.txt
```

## Run

```bash
cd backend
python app.py                  # or: uvicorn app:app --host 127.0.0.1 --port 8770
```

Open **http://127.0.0.1:8770**. It starts in **test mode**, so you can add a game
and watch a simulated install immediately.

### Going live with Bottles

1. Install Bottles and confirm the CLI works:
   `flatpak run --command=bottles-cli com.usebottles.Bottles --version`
2. In **Settings**, set **Test mode → false**. Leave **bottles-cli → auto** for
   auto-detection, or paste a full command.
3. Add a game, pick its `setup.exe`, and click **Install**. The app creates the
   `Gaming` bottle if it does not exist, installs the dependency list, then runs
   your installer. Complete any GUI installer prompts in the window that opens.

## Configuration

Everything is editable in the **Settings** page. Defaults can also be seeded from
environment variables on first run:

| Setting | Env var | Default | Notes |
|---|---|---|---|
| Test mode | `GL_TEST_MODE` | `true` | Simulate everything; no Bottles needed |
| bottles-cli | `GL_BOTTLES_CLI` | `auto` | `auto`, or a full command line |
| Default bottle | `GL_DEFAULT_BOTTLE` | `Gaming` | |
| Gaming deps | `GL_GAMING_DEPS` | `dxvk,vkd3d,vcredist2022,dotnet48` | comma-separated |
| Installer root | `GL_INSTALLER_ROOT` | your home dir | file browser is sandboxed here |
| Metadata provider | `GL_METADATA_PROVIDER` | `none` | `none` / `igdb` / `steamgriddb` |
| Access token | `GL_ACCESS_TOKEN` | *(empty)* | set to require login |
| Host / Port | `GL_HOST` / `GL_PORT` | `127.0.0.1` / `8770` | |

**API keys** (metadata only) are read from the environment and never stored:
`IGDB_CLIENT_ID`, `IGDB_CLIENT_SECRET`, `STEAMGRIDDB_KEY`.

### Authentication

Set an **Access token** in Settings (or `GL_ACCESS_TOKEN`). When set, the UI
shows a login gate and every API call requires the token. Leave it blank for an
open, LAN-only instance. Bind to `127.0.0.1` (the default) unless you intend to
expose it; put a reverse proxy with TLS in front if you do.

## Testing

```bash
cd backend
python test_smoke.py
```

Runs the full pipeline in memory (create → install with streamed progress →
installed → launch → uninstall → history) with no Bottles, no network, and an
isolated temp database. Prints `ALL SMOKE TESTS PASSED ✅`.

## Troubleshooting

- **"bottles-cli not found"** — install Bottles, or set the exact CLI command in
  Settings, or keep Test mode on. Verify with
  `flatpak run --command=bottles-cli com.usebottles.Bottles --version`.
- **Installer opens but nothing installs** — many Windows installers are GUI
  apps; complete them in the window Bottles opens. Progress crawls while the
  installer is alive and completes when it exits.
- **A dependency fails** — the install continues; check
  `logs/game-launcher.log`. Some games only need a subset of the default deps.
- **Installer misbehaves under Wine** — try a different bottle, adjust the
  dependency list, or consult the game's ProtonDB / Bottles notes. Wine
  compatibility varies per title.
- **Port already in use** — change `GL_PORT`.

## API reference (quick)

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/games?search=` | list library |
| POST | `/api/games` | add game |
| PUT/DELETE | `/api/games/{id}` | edit / remove |
| POST | `/api/games/{id}/install` | start install job |
| GET | `/api/jobs/{id}/stream` | SSE progress |
| POST | `/api/jobs/{id}/cancel` | cancel job |
| POST | `/api/games/{id}/launch` | launch via Bottles |
| POST | `/api/games/{id}/uninstall` | uninstall |
| GET | `/api/bottles` | Bottles status + list |
| GET/PUT | `/api/settings` | settings |
| GET | `/api/history` | event log |
| GET/POST | `/api/export` `/api/import` | library JSON |
