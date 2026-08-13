"""Install-job orchestration and live progress.

A "job" is one install (or uninstall/launch) of one game. Each job owns an
asyncio Queue of progress events; the SSE endpoint in app.py drains that queue
to the browser. Jobs are cancellable via an asyncio.Event.

The pipeline for an install is deliberately simple and legal:
  1. ensure the target bottle exists (create with Gaming preset if not)
  2. install gaming dependencies (DXVK/VKD3D/vcredist/…)
  3. run the *user-supplied* installer executable inside the bottle
  4. record the game as installed

There is no download step: the installer file already exists on the user's
disk (a GOG offline installer, an itch.io setup, a backup they own, …).
"""
from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import bottles_manager as bm
import database as db
from logger import get_logger

log = get_logger("installer")


@dataclass
class Job:
    id: str
    game_id: int
    kind: str  # install | uninstall | launch
    status: str = "running"  # running | done | error | cancelled
    fraction: float = 0.0
    message: str = "Queued"
    error: str = ""
    started_at: float = field(default_factory=time.time)
    queue: "asyncio.Queue[dict[str, Any]]" = field(default_factory=asyncio.Queue)
    cancel: asyncio.Event = field(default_factory=asyncio.Event)

    def snapshot(self) -> dict[str, Any]:
        return {
            "job_id": self.id,
            "game_id": self.game_id,
            "kind": self.kind,
            "status": self.status,
            "fraction": round(self.fraction, 3),
            "message": self.message,
            "error": self.error,
        }


class JobManager:
    def __init__(self) -> None:
        self._jobs: dict[str, Job] = {}
        self._by_game: dict[int, str] = {}
        self._seq = 0

    def get(self, job_id: str) -> Job | None:
        return self._jobs.get(job_id)

    def active_for_game(self, game_id: int) -> Job | None:
        job_id = self._by_game.get(game_id)
        job = self._jobs.get(job_id) if job_id else None
        return job if job and job.status == "running" else None

    async def _emit(self, job: Job, fraction: float, message: str) -> None:
        job.fraction = max(job.fraction, min(1.0, fraction))
        job.message = message
        await job.queue.put(job.snapshot())
        log.info("job=%s %3.0f%% %s", job.id, job.fraction * 100, message)

    def _new_job(self, game_id: int, kind: str) -> Job:
        self._seq += 1
        job = Job(id=f"job-{self._seq}", game_id=game_id, kind=kind)
        self._jobs[job.id] = job
        self._by_game[game_id] = job.id
        return job

    # --- Install -------------------------------------------------------------
    def start_install(self, game_id: int, bottle_name: str) -> Job:
        job = self._new_job(game_id, "install")
        asyncio.create_task(self._run_install(job, bottle_name))
        return job

    async def _run_install(self, job: Job, bottle_name: str) -> None:
        game = db.get_game(job.game_id)
        try:
            if not game:
                raise RuntimeError("Game not found")
            installer = (game.get("installer_path") or "").strip()
            if not installer:
                raise RuntimeError("This game has no installer file set.")
            if not bm._test_mode() and not Path(installer).is_file():
                raise RuntimeError(f"Installer file not found: {installer}")

            await self._emit(job, 0.01, "Preparing bottle…")
            await bm.ensure_bottle(
                bottle_name, lambda f, m: self._emit(job, f, m)
            )
            await bm.install_dependencies(
                bottle_name, lambda f, m: self._emit(job, f, m)
            )

            if job.cancel.is_set():
                raise asyncio.CancelledError()

            result = await bm.run_installer(
                bottle_name,
                installer,
                progress=lambda f, m: self._emit(job, f, m),
                cancel=job.cancel,
            )

            db.mark_installed(job.game_id, bottle_name, exe_path="")
            db.log_event(job.game_id, "install", "ok", f"{bottle_name}: {result}")
            await self._emit(job, 1.0, "Installation complete")
            job.status = "done"
        except asyncio.CancelledError:
            job.status = "cancelled"
            job.message = "Cancelled"
            db.log_event(job.game_id, "install", "error", "cancelled")
        except Exception as exc:  # surface a clean message to the UI
            job.status = "error"
            job.error = str(exc)
            job.message = f"Failed: {exc}"
            log.exception("install failed for game=%s", job.game_id)
            db.log_event(job.game_id, "install", "error", str(exc))
        finally:
            await job.queue.put(job.snapshot())
            await job.queue.put({"_eof": True})

    # --- Uninstall -----------------------------------------------------------
    def start_uninstall(self, game_id: int) -> Job:
        job = self._new_job(game_id, "uninstall")
        asyncio.create_task(self._run_uninstall(job))
        return job

    async def _run_uninstall(self, job: Job) -> None:
        try:
            await self._emit(job, 0.3, "Removing from library…")
            db.mark_uninstalled(job.game_id)
            db.log_event(job.game_id, "uninstall", "ok", "")
            await self._emit(job, 1.0, "Uninstalled")
            job.status = "done"
        except Exception as exc:
            job.status = "error"
            job.error = str(exc)
            db.log_event(job.game_id, "uninstall", "error", str(exc))
        finally:
            await job.queue.put(job.snapshot())
            await job.queue.put({"_eof": True})


JOBS = JobManager()
