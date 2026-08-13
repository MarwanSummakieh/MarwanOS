"""Optional cover-art / metadata lookup from *legitimate* providers.

Two providers are supported, both read from public APIs about games in general
(not from any file-sharing site):

  * IGDB          — needs IGDB_CLIENT_ID / IGDB_CLIENT_SECRET (Twitch dev app)
  * SteamGridDB   — needs STEAMGRIDDB_KEY

If no provider is configured (the default), lookups simply return empty results
and the UI falls back to a generated placeholder cover. The app is fully usable
with no API keys at all.
"""
from __future__ import annotations

import asyncio
from typing import Any

import httpx

import config
import database as db
from logger import get_logger

log = get_logger("metadata")

_igdb_token: dict[str, Any] = {"value": "", "expires": 0.0}


async def _igdb_headers(client: httpx.AsyncClient) -> dict[str, str] | None:
    if not (config.IGDB_CLIENT_ID and config.IGDB_CLIENT_SECRET):
        return None
    # Token caching is best-effort; we re-request if missing.
    if not _igdb_token["value"]:
        resp = await client.post(
            "https://id.twitch.tv/oauth2/token",
            params={
                "client_id": config.IGDB_CLIENT_ID,
                "client_secret": config.IGDB_CLIENT_SECRET,
                "grant_type": "client_credentials",
            },
        )
        resp.raise_for_status()
        _igdb_token["value"] = resp.json()["access_token"]
    return {
        "Client-ID": config.IGDB_CLIENT_ID,
        "Authorization": f"Bearer {_igdb_token['value']}",
    }


async def _lookup_igdb(title: str) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=15) as client:
        headers = await _igdb_headers(client)
        if headers is None:
            return {}
        body = (
            f'search "{title}";'
            "fields name,summary,first_release_date,genres.name,cover.image_id;"
            "limit 1;"
        )
        resp = await client.post(
            "https://api.igdb.com/v4/games", headers=headers, content=body
        )
        resp.raise_for_status()
        rows = resp.json()
        if not rows:
            return {}
        row = rows[0]
        cover = ""
        if row.get("cover", {}).get("image_id"):
            cover = (
                "https://images.igdb.com/igdb/image/upload/t_cover_big/"
                f"{row['cover']['image_id']}.jpg"
            )
        year = None
        if row.get("first_release_date"):
            year = 1970 + int(row["first_release_date"]) // 31_556_952
        return {
            "description": row.get("summary", "") or "",
            "image_url": cover,
            "genre": ", ".join(g["name"] for g in row.get("genres", [])),
            "year": year,
        }


async def _lookup_steamgriddb(title: str) -> dict[str, Any]:
    if not config.STEAMGRIDDB_KEY:
        return {}
    headers = {"Authorization": f"Bearer {config.STEAMGRIDDB_KEY}"}
    async with httpx.AsyncClient(timeout=15, headers=headers) as client:
        search = await client.get(
            f"https://www.steamgriddb.com/api/v2/search/autocomplete/{title}"
        )
        search.raise_for_status()
        data = search.json().get("data", [])
        if not data:
            return {}
        game_id = data[0]["id"]
        grids = await client.get(
            f"https://www.steamgriddb.com/api/v2/grids/game/{game_id}",
            params={"dimensions": "600x900", "limit": 1},
        )
        grids.raise_for_status()
        items = grids.json().get("data", [])
        return {"image_url": items[0]["url"]} if items else {}


async def lookup(title: str) -> dict[str, Any]:
    """Return best-effort metadata for a title; never raises."""
    provider = (db.get_setting("metadata_provider", "none") or "none").lower()
    try:
        if provider == "igdb":
            return await _lookup_igdb(title)
        if provider == "steamgriddb":
            return await _lookup_steamgriddb(title)
    except Exception as exc:  # metadata is a nicety, never fatal
        log.warning("metadata lookup failed for %r: %s", title, exc)
    return {}


async def enrich_game(game_id: int) -> dict[str, Any]:
    game = db.get_game(game_id)
    if not game:
        return {}
    meta = await lookup(game["title"])
    fields = {k: v for k, v in meta.items() if v}
    if fields:
        db.update_game(game_id, **fields)
    return fields


if __name__ == "__main__":  # tiny manual check
    import sys

    print(asyncio.run(lookup(" ".join(sys.argv[1:]) or "Hollow Knight")))
