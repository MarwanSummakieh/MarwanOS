"""FastAPI application: REST API, SSE progress stream, and static frontend.

Run with:  uvicorn app:app --host 127.0.0.1 --port 8770
or simply: python app.py
"""
from __future__ import annotations

import asyncio
import secrets
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import bottles_manager as bm
import config
import database as db
import metadata
from installer import JOBS
from logger import get_logger

log = get_logger("app")

app = FastAPI(title="Game Launcher", version="1.0.0")

# Session tokens minted at login. In-memory is fine for a single-user host.
_sessions: set[str] = set()


@app.on_event("startup")
async def _startup() -> None:
    db.init_db()
    log.info("Game Launcher started (test_mode=%s)", db.get_setting("test_mode"))


# --- Auth --------------------------------------------------------------------
def _auth_required() -> bool:
    return bool((db.get_setting("access_token") or "").strip())


async def require_auth(request: Request) -> None:
    if not _auth_required():
        return
    token = request.headers.get("X-Session") or request.query_params.get("session")
    if token not in _sessions:
        raise HTTPException(status_code=401, detail="Authentication required")


class LoginBody(BaseModel):
    token: str


@app.post("/api/login")
async def login(body: LoginBody) -> dict[str, Any]:
    expected = (db.get_setting("access_token") or "").strip()
    if not expected:
        return {"session": "", "auth": False}
    if not secrets.compare_digest(body.token, expected):
        raise HTTPException(status_code=401, detail="Invalid access token")
    session = secrets.token_urlsafe(24)
    _sessions.add(session)
    return {"session": session, "auth": True}


@app.get("/api/auth-status")
async def auth_status() -> dict[str, Any]:
    return {"auth_required": _auth_required()}


# --- Games -------------------------------------------------------------------
class GameBody(BaseModel):
    title: str
    installer_path: str = ""
    description: str = ""
    image_url: str = ""
    genre: str = ""
    year: int | None = None
    size_bytes: int = 0
    source: str = "local"


@app.get("/api/games", dependencies=[Depends(require_auth)])
async def get_games(search: str | None = None) -> list[dict[str, Any]]:
    return await asyncio.to_thread(db.list_games, search)


@app.post("/api/games", dependencies=[Depends(require_auth)])
async def create_game(body: GameBody) -> dict[str, Any]:
    fields = body.model_dump()
    # If the installer file is real, record its size automatically.
    p = Path(fields["installer_path"])
    if fields["installer_path"] and p.is_file():
        fields["size_bytes"] = p.stat().st_size
    game_id = await asyncio.to_thread(db.add_game, **fields)
    # Fire-and-forget metadata enrichment if a provider is configured.
    if (db.get_setting("metadata_provider", "none") or "none") != "none":
        asyncio.create_task(metadata.enrich_game(game_id))
    return await asyncio.to_thread(db.get_game, game_id)


@app.put("/api/games/{game_id}", dependencies=[Depends(require_auth)])
async def edit_game(game_id: int, body: GameBody) -> dict[str, Any]:
    await asyncio.to_thread(
        db.update_game, game_id, **body.model_dump(exclude_unset=True)
    )
    game = await asyncio.to_thread(db.get_game, game_id)
    if not game:
        raise HTTPException(404, "Game not found")
    return game


@app.delete("/api/games/{game_id}", dependencies=[Depends(require_auth)])
async def remove_game(game_id: int) -> dict[str, str]:
    await asyncio.to_thread(db.delete_game, game_id)
    return {"status": "deleted"}


@app.post("/api/games/{game_id}/refresh-metadata", dependencies=[Depends(require_auth)])
async def refresh_metadata(game_id: int) -> dict[str, Any]:
    fields = await metadata.enrich_game(game_id)
    return {"updated": fields}


# --- Install / uninstall / launch -------------------------------------------
class InstallBody(BaseModel):
    bottle_name: str | None = None


@app.post("/api/games/{game_id}/install", dependencies=[Depends(require_auth)])
async def install_game(game_id: int, body: InstallBody) -> dict[str, Any]:
    game = await asyncio.to_thread(db.get_game, game_id)
    if not game:
        raise HTTPException(404, "Game not found")
    if JOBS.active_for_game(game_id):
        raise HTTPException(409, "An install is already running for this game")
    bottle = body.bottle_name or db.get_setting("default_bottle", "Gaming")
    job = JOBS.start_install(game_id, bottle)
    return job.snapshot()


@app.post("/api/games/{game_id}/uninstall", dependencies=[Depends(require_auth)])
async def uninstall_game(game_id: int) -> dict[str, Any]:
    job = JOBS.start_uninstall(game_id)
    return job.snapshot()


@app.post("/api/jobs/{job_id}/cancel", dependencies=[Depends(require_auth)])
async def cancel_job(job_id: str) -> dict[str, str]:
    job = JOBS.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    job.cancel.set()
    return {"status": "cancelling"}


@app.get("/api/jobs/{job_id}/stream")
async def stream_job(job_id: str, request: Request) -> StreamingResponse:
    """Server-Sent Events stream of progress for one job."""
    job = JOBS.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found")

    async def event_gen():
        # Replay the current state immediately so late subscribers are correct.
        yield _sse(job.snapshot())
        while True:
            if await request.is_disconnected():
                break
            try:
                item = await asyncio.wait_for(job.queue.get(), timeout=15.0)
            except asyncio.TimeoutError:
                yield ": keep-alive\n\n"
                continue
            if item.get("_eof"):
                yield _sse({"_done": True})
                break
            yield _sse(item)

    return StreamingResponse(event_gen(), media_type="text/event-stream")


def _sse(payload: dict[str, Any]) -> str:
    import json

    return f"data: {json.dumps(payload)}\n\n"


@app.post("/api/games/{game_id}/launch", dependencies=[Depends(require_auth)])
async def launch_game(game_id: int) -> dict[str, Any]:
    game = await asyncio.to_thread(db.get_game, game_id)
    inst = await asyncio.to_thread(db.get_installed, game_id)
    if not game or not inst:
        raise HTTPException(404, "Game is not installed")
    bottle = inst["bottle_name"]
    if bm._test_mode():
        db.log_event(game_id, "launch", "ok", "[test] launch")
        return {"status": "launched (simulated)", "bottle": bottle}
    # List programs and launch the first game-like entry, or the recorded exe.
    programs = await bm.list_programs(bottle)
    db.log_event(game_id, "launch", "ok", f"programs={len(programs)}")
    return {"status": "launched", "bottle": bottle, "programs": programs}


# --- Bottles / system --------------------------------------------------------
@app.get("/api/bottles", dependencies=[Depends(require_auth)])
async def bottles() -> dict[str, Any]:
    available = await bm.is_available()
    names = await bm.list_bottles() if available else []
    return {"available": available, "test_mode": bm._test_mode(), "bottles": names}


# --- Filesystem browser (confined to installer_root) -------------------------
@app.get("/api/browse", dependencies=[Depends(require_auth)])
async def browse(path: str | None = None) -> dict[str, Any]:
    """List directories and installer files under the configured root only."""
    root = Path(db.get_setting("installer_root", str(Path.home()))).resolve()
    target = Path(path).resolve() if path else root
    # Prevent escaping the sandbox root via ../ etc.
    if root not in target.parents and target != root:
        target = root
    if not target.is_dir():
        raise HTTPException(400, "Not a directory")
    entries = []
    exts = {".exe", ".msi", ".bat", ".sh", ".bin"}
    try:
        for child in sorted(target.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower())):
            if child.name.startswith("."):
                continue
            is_dir = child.is_dir()
            if not is_dir and child.suffix.lower() not in exts:
                continue
            entries.append(
                {
                    "name": child.name,
                    "path": str(child),
                    "is_dir": is_dir,
                    "size": child.stat().st_size if not is_dir else 0,
                }
            )
    except PermissionError:
        raise HTTPException(403, "Permission denied")
    return {
        "root": str(root),
        "cwd": str(target),
        "parent": str(target.parent) if target != root else None,
        "entries": entries,
    }


# --- Settings & history ------------------------------------------------------
@app.get("/api/settings", dependencies=[Depends(require_auth)])
async def get_settings() -> dict[str, str]:
    s = await asyncio.to_thread(db.get_settings)
    # Never leak the access token to the client; expose only whether it's set.
    s = dict(s)
    s["access_token"] = "set" if s.get("access_token") else ""
    return s


@app.put("/api/settings", dependencies=[Depends(require_auth)])
async def put_settings(body: dict[str, str]) -> dict[str, str]:
    # Only allow known keys; ignore the masked token unless a real value is sent.
    allowed = set(config.DEFAULT_SETTINGS.keys())
    updates = {k: v for k, v in body.items() if k in allowed}
    if updates.get("access_token") in ("set", None):
        updates.pop("access_token", None)
    await asyncio.to_thread(db.set_settings, updates)
    return {"status": "saved"}


@app.get("/api/history", dependencies=[Depends(require_auth)])
async def history(limit: int = 100) -> list[dict[str, Any]]:
    return await asyncio.to_thread(db.list_history, limit)


@app.get("/api/export", dependencies=[Depends(require_auth)])
async def export_library() -> list[dict[str, Any]]:
    return await asyncio.to_thread(db.list_games, None)


@app.post("/api/import", dependencies=[Depends(require_auth)])
async def import_library(games: list[GameBody]) -> dict[str, int]:
    count = 0
    for g in games:
        await asyncio.to_thread(db.add_game, **g.model_dump())
        count += 1
    return {"imported": count}


# --- Static frontend ---------------------------------------------------------
@app.get("/")
async def index() -> FileResponse:
    return FileResponse(config.FRONTEND_DIR / "index.html")


app.mount("/", StaticFiles(directory=str(config.FRONTEND_DIR)), name="static")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=config.HOST, port=config.PORT)
