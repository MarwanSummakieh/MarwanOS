"""End-to-end smoke test that runs the full stack in test mode.

Exercises: create game -> list -> install (with live SSE progress) ->
verify it shows as installed -> launch -> uninstall -> history. No Bottles,
no network, no downloads. Run:  python test_smoke.py
"""
from __future__ import annotations

import json
import os
import tempfile

# Isolate the DB so the test never touches a real library.
_tmp = tempfile.mkdtemp(prefix="gl-test-")
os.environ["GL_DATA_DIR"] = _tmp
os.environ["GL_LOG_DIR"] = _tmp
os.environ["GL_TEST_MODE"] = "true"
os.environ["GL_ACCESS_TOKEN"] = ""  # no auth for the test

from fastapi.testclient import TestClient  # noqa: E402

import app as appmod  # noqa: E402

client = TestClient(appmod.app)


def _drain_sse(job_id: str) -> list[dict]:
    events = []
    with client.stream("GET", f"/api/jobs/{job_id}/stream") as r:
        for line in r.iter_lines():
            if line and line.startswith("data: "):
                events.append(json.loads(line[6:]))
                if events[-1].get("_done"):
                    break
    return events


def main() -> None:
    with TestClient(appmod.app) as c:
        # 1. Empty library
        assert c.get("/api/games").json() == [], "library should start empty"

        # 2. Add a game
        r = c.post("/api/games", json={"title": "Test Quest", "installer_path": "C:/fake/setup.exe", "genre": "RPG", "year": 2024})
        assert r.status_code == 200, r.text
        game_id = r.json()["id"]
        print(f"✓ created game id={game_id}")

        # 3. It appears in the listing, not installed
        games = c.get("/api/games").json()
        assert len(games) == 1 and games[0]["install_status"] is None
        print("✓ game listed as not-installed")

        # 4. Start install and stream progress
        job = c.post(f"/api/games/{game_id}/install", json={}).json()
        print(f"✓ install job {job['job_id']} started")

    # Re-open client for the streaming portion (lifespan already ran above).
    with TestClient(appmod.app) as c:
        r = c.post("/api/games", json={"title": "Stream Quest", "installer_path": "C:/fake/s.exe"})
        gid = r.json()["id"]
        job = c.post(f"/api/games/{gid}/install", json={}).json()
        events = _drain_sse(job["job_id"])
        assert events, "expected progress events"
        assert any(e.get("status") == "done" for e in events), f"install never finished: {events[-3:]}"
        fractions = [e.get("fraction", 0) for e in events if "fraction" in e]
        assert fractions[-1] >= 0.99, f"progress did not reach 100%: {fractions}"
        print(f"✓ streamed {len(events)} progress events, reached {int(max(fractions)*100)}%")

        # Installed listing
        installed = [g for g in c.get("/api/games").json() if g["install_status"] == "installed"]
        assert any(g["id"] == gid for g in installed), "game should be installed"
        print("✓ game shows as installed")

        # Launch (simulated)
        r = c.post(f"/api/games/{gid}/launch")
        assert r.status_code == 200 and "simulated" in r.json()["status"]
        print("✓ launch (simulated) ok")

        # Uninstall
        job = c.post(f"/api/games/{gid}/uninstall").json()
        _drain_sse(job["job_id"])
        installed = [g for g in c.get("/api/games").json() if g["install_status"] == "installed"]
        assert not any(g["id"] == gid for g in installed), "game should be uninstalled"
        print("✓ uninstall ok")

        # Bottles status + history + settings
        assert c.get("/api/bottles").json()["test_mode"] is True
        assert len(c.get("/api/history").json()) >= 2
        assert c.get("/api/settings").json()["access_token"] == ""  # unset -> empty
        print("✓ bottles/history/settings endpoints ok")

    print("\nALL SMOKE TESTS PASSED ✅")


if __name__ == "__main__":
    main()
