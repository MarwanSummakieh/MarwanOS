"""Configuration and settings for the game launcher.

Settings live in the SQLite `settings` table (editable from the UI) but every
key has a default here, and environment variables override the defaults on
first run. Nothing sensitive is hard-coded; API keys come from the environment.
"""
from __future__ import annotations

import os
from pathlib import Path

# --- Paths -------------------------------------------------------------------
# Everything is relative to the project root (the parent of this backend dir)
# so the app is fully portable / self-hosted.
ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = Path(os.environ.get("GL_DATA_DIR", ROOT / "data"))
LOG_DIR = Path(os.environ.get("GL_LOG_DIR", ROOT / "logs"))
FRONTEND_DIR = ROOT / "frontend"
DB_PATH = DATA_DIR / "games.db"

DATA_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)

# --- Default settings --------------------------------------------------------
# These seed the settings table the first time the app runs. After that the
# values in the DB win, so users edit them from the Settings page.
DEFAULT_SETTINGS: dict[str, str] = {
    # Where bottles-cli lives. "auto" means: try `flatpak run … bottles-cli`
    # then a bare `bottles-cli` on PATH.
    "bottles_cli": os.environ.get("GL_BOTTLES_CLI", "auto"),
    # Default bottle games get installed into.
    "default_bottle": os.environ.get("GL_DEFAULT_BOTTLE", "Gaming"),
    # Root folder the "Add installer" browser is confined to (no escaping it).
    "installer_root": os.environ.get("GL_INSTALLER_ROOT", str(Path.home())),
    # Where installed-game data / shortcuts get recorded.
    "install_root": os.environ.get("GL_INSTALL_ROOT", str(Path.home() / "Games")),
    # Bottle dependencies to install when preparing a gaming bottle.
    "gaming_deps": os.environ.get(
        "GL_GAMING_DEPS", "dxvk,vkd3d,vcredist2022,dotnet48"
    ),
    # Metadata provider for cover art: "none", "igdb", or "steamgriddb".
    "metadata_provider": os.environ.get("GL_METADATA_PROVIDER", "none"),
    # When true, no real bottles-cli calls are made — everything is simulated.
    # Great for developing the UI and for a first run before Bottles is set up.
    "test_mode": os.environ.get("GL_TEST_MODE", "true"),
    # Simple shared-secret auth. Empty string disables the login gate.
    "access_token": os.environ.get("GL_ACCESS_TOKEN", ""),
}

# API keys are read from the environment only — never stored in the DB.
IGDB_CLIENT_ID = os.environ.get("IGDB_CLIENT_ID", "")
IGDB_CLIENT_SECRET = os.environ.get("IGDB_CLIENT_SECRET", "")
STEAMGRIDDB_KEY = os.environ.get("STEAMGRIDDB_KEY", "")

HOST = os.environ.get("GL_HOST", "127.0.0.1")
PORT = int(os.environ.get("GL_PORT", "8770"))
