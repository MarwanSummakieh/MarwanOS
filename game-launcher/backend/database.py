"""SQLite persistence layer.

Tables
------
games            catalogue entries (a game the user owns, with an installer file)
installed        which games are installed, into which bottle, and their state
history          append-only log of install/uninstall/launch events
settings         key/value app settings (see config.DEFAULT_SETTINGS)

The DB is intentionally tiny and synchronous — SQLite is more than enough for a
single-user self-hosted launcher, and keeping it sync avoids an async-driver
dependency. Calls that could block the event loop are wrapped with
`asyncio.to_thread` at the call site in app.py.
"""
from __future__ import annotations

import sqlite3
import time
from contextlib import contextmanager
from typing import Any, Iterable, Iterator

from config import DB_PATH, DEFAULT_SETTINGS

SCHEMA = """
CREATE TABLE IF NOT EXISTS games (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    title         TEXT NOT NULL,
    installer_path TEXT,                 -- path to setup.exe / .msi the user owns
    description   TEXT DEFAULT '',
    image_url     TEXT DEFAULT '',       -- local /covers/… path or remote URL
    genre         TEXT DEFAULT '',
    year          INTEGER,
    size_bytes    INTEGER DEFAULT 0,
    source        TEXT DEFAULT 'local',  -- provenance label, informational
    added_at      INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS installed (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id      INTEGER NOT NULL,
    bottle_name  TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'installed',  -- installed | failed | removed
    exe_path     TEXT DEFAULT '',        -- resolved launch target inside the bottle
    install_date INTEGER NOT NULL,
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS history (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id    INTEGER,
    action     TEXT NOT NULL,            -- install | uninstall | launch | prepare
    status     TEXT NOT NULL,            -- ok | error
    detail     TEXT DEFAULT '',
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""


@contextmanager
def connect() -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(DB_PATH, timeout=15)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    with connect() as conn:
        conn.executescript(SCHEMA)
        # Seed any missing default settings without clobbering user changes.
        existing = {r["key"] for r in conn.execute("SELECT key FROM settings")}
        for key, value in DEFAULT_SETTINGS.items():
            if key not in existing:
                conn.execute(
                    "INSERT INTO settings (key, value) VALUES (?, ?)", (key, value)
                )


# --- Settings ----------------------------------------------------------------
def get_setting(key: str, default: str | None = None) -> str | None:
    with connect() as conn:
        row = conn.execute(
            "SELECT value FROM settings WHERE key = ?", (key,)
        ).fetchone()
    if row is not None:
        return row["value"]
    return DEFAULT_SETTINGS.get(key, default)


def get_settings() -> dict[str, str]:
    with connect() as conn:
        rows = conn.execute("SELECT key, value FROM settings").fetchall()
    merged = dict(DEFAULT_SETTINGS)
    merged.update({r["key"]: r["value"] for r in rows})
    return merged


def set_settings(items: dict[str, str]) -> None:
    with connect() as conn:
        for key, value in items.items():
            conn.execute(
                "INSERT INTO settings (key, value) VALUES (?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (key, str(value)),
            )


# --- Games -------------------------------------------------------------------
def add_game(**fields: Any) -> int:
    fields.setdefault("added_at", int(time.time()))
    cols = ", ".join(fields.keys())
    placeholders = ", ".join("?" for _ in fields)
    with connect() as conn:
        cur = conn.execute(
            f"INSERT INTO games ({cols}) VALUES ({placeholders})",
            tuple(fields.values()),
        )
        return int(cur.lastrowid)


def update_game(game_id: int, **fields: Any) -> None:
    if not fields:
        return
    assignments = ", ".join(f"{k} = ?" for k in fields)
    with connect() as conn:
        conn.execute(
            f"UPDATE games SET {assignments} WHERE id = ?",
            (*fields.values(), game_id),
        )


def delete_game(game_id: int) -> None:
    with connect() as conn:
        conn.execute("DELETE FROM games WHERE id = ?", (game_id,))


def get_game(game_id: int) -> dict[str, Any] | None:
    with connect() as conn:
        row = conn.execute("SELECT * FROM games WHERE id = ?", (game_id,)).fetchone()
    return dict(row) if row else None


def list_games(search: str | None = None) -> list[dict[str, Any]]:
    query = (
        "SELECT g.*, i.status AS install_status, i.bottle_name, i.exe_path "
        "FROM games g "
        "LEFT JOIN installed i "
        "  ON i.game_id = g.id AND i.status = 'installed' "
    )
    params: list[Any] = []
    if search:
        query += "WHERE g.title LIKE ? "
        params.append(f"%{search}%")
    query += "ORDER BY g.title COLLATE NOCASE"
    with connect() as conn:
        rows = conn.execute(query, params).fetchall()
    return [dict(r) for r in rows]


# --- Installed ---------------------------------------------------------------
def mark_installed(game_id: int, bottle_name: str, exe_path: str = "") -> None:
    with connect() as conn:
        # Keep a single live row per game.
        conn.execute(
            "UPDATE installed SET status = 'removed' "
            "WHERE game_id = ? AND status = 'installed'",
            (game_id,),
        )
        conn.execute(
            "INSERT INTO installed "
            "(game_id, bottle_name, status, exe_path, install_date) "
            "VALUES (?, ?, 'installed', ?, ?)",
            (game_id, bottle_name, exe_path, int(time.time())),
        )


def mark_uninstalled(game_id: int) -> None:
    with connect() as conn:
        conn.execute(
            "UPDATE installed SET status = 'removed' "
            "WHERE game_id = ? AND status = 'installed'",
            (game_id,),
        )


def get_installed(game_id: int) -> dict[str, Any] | None:
    with connect() as conn:
        row = conn.execute(
            "SELECT * FROM installed WHERE game_id = ? AND status = 'installed'",
            (game_id,),
        ).fetchone()
    return dict(row) if row else None


# --- History -----------------------------------------------------------------
def log_event(game_id: int | None, action: str, status: str, detail: str = "") -> None:
    with connect() as conn:
        conn.execute(
            "INSERT INTO history (game_id, action, status, detail, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (game_id, action, status, detail[:2000], int(time.time())),
        )


def list_history(limit: int = 100) -> list[dict[str, Any]]:
    with connect() as conn:
        rows = conn.execute(
            "SELECT h.*, g.title FROM history h "
            "LEFT JOIN games g ON g.id = h.game_id "
            "ORDER BY h.created_at DESC LIMIT ?",
            (limit,),
        ).fetchall()
    return [dict(r) for r in rows]
