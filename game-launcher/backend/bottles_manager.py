"""Thin, honest wrapper around `bottles-cli`.

Design notes
------------
* Every method reports progress through an async callback so the caller can
  stream it to the browser. The callback receives (fraction: float, message).
* `test_mode` (from settings) short-circuits every real subprocess call with a
  believable simulation. This lets the whole UI run on a machine that has never
  seen Bottles, and powers the "Test mode" toggle in the spec.
* We resolve the CLI once: if the setting is "auto" we try the flatpak entry
  point first (that is how Bottles ships on most immutable/atomic distros,
  MarwanOS included) and then a bare binary on PATH.

Nothing here shells out to a warez source or fetches a game — the installer
path is supplied by the user and always points at software they own.
"""
from __future__ import annotations

import asyncio
import shlex
import shutil
from typing import Awaitable, Callable

import database as db

# Progress callback: (fraction 0..1, human-readable message) -> awaitable
Progress = Callable[[float, str], Awaitable[None]]


async def _noop(_frac: float, _msg: str) -> None:
    return None


class BottlesError(RuntimeError):
    pass


def _resolve_cli() -> list[str]:
    """Return the argv prefix used to invoke bottles-cli, or raise."""
    setting = db.get_setting("bottles_cli", "auto") or "auto"
    if setting != "auto":
        # Allow a full command line, e.g. "flatpak run --command=bottles-cli com.usebottles.Bottles"
        return shlex.split(setting)

    if shutil.which("bottles-cli"):
        return ["bottles-cli"]
    if shutil.which("flatpak"):
        # The canonical flatpak invocation for the CLI entry point.
        return [
            "flatpak",
            "run",
            "--command=bottles-cli",
            "com.usebottles.Bottles",
        ]
    raise BottlesError(
        "bottles-cli not found. Install Bottles, or set the CLI path in Settings, "
        "or enable Test mode."
    )


def _test_mode() -> bool:
    return (db.get_setting("test_mode", "true") or "true").lower() in (
        "1",
        "true",
        "yes",
    )


async def _run(args: list[str], timeout: float = 900.0) -> tuple[int, str, str]:
    """Run a bottles-cli command, returning (returncode, stdout, stderr)."""
    argv = _resolve_cli() + args
    proc = await asyncio.create_subprocess_exec(
        *argv,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        raise BottlesError(f"Command timed out: {' '.join(shlex.quote(a) for a in argv)}")
    return proc.returncode or 0, out.decode(errors="replace"), err.decode(errors="replace")


# --- Public API --------------------------------------------------------------
async def is_available() -> bool:
    """True if we can talk to Bottles (or we're simulating)."""
    if _test_mode():
        return True
    try:
        rc, _out, _err = await _run(["--version"], timeout=30)
        return rc == 0
    except BottlesError:
        return False


async def list_bottles() -> list[str]:
    if _test_mode():
        return ["Gaming", "Default"]
    rc, out, err = await _run(["list", "bottles"], timeout=60)
    if rc != 0:
        raise BottlesError(err.strip() or "Failed to list bottles")
    names: list[str] = []
    for line in out.splitlines():
        line = line.strip("-• \t")
        if line and not line.lower().startswith(("found", "bottles")):
            names.append(line.split(":")[0].strip())
    return [n for n in names if n]


async def ensure_bottle(name: str, progress: Progress = _noop) -> None:
    """Create the bottle with the Gaming preset if it does not exist."""
    await progress(0.02, f"Checking for bottle '{name}'…")
    if _test_mode():
        await asyncio.sleep(0.4)
        await progress(0.10, f"[test] bottle '{name}' ready")
        return

    if name in await list_bottles():
        await progress(0.10, f"Bottle '{name}' already exists")
        return

    await progress(0.04, f"Creating bottle '{name}' (Gaming preset)…")
    rc, _out, err = await _run(
        ["new", "--bottle-name", name, "--environment", "gaming"], timeout=600
    )
    if rc != 0:
        raise BottlesError(f"Could not create bottle '{name}': {err.strip()}")
    await progress(0.10, f"Bottle '{name}' created")


async def install_dependencies(name: str, progress: Progress = _noop) -> None:
    """Install the configured gaming dependencies (DXVK, VKD3D, vcredist, …)."""
    deps = [
        d.strip()
        for d in (db.get_setting("gaming_deps", "") or "").split(",")
        if d.strip()
    ]
    if not deps:
        return
    for i, dep in enumerate(deps):
        frac = 0.10 + 0.15 * (i + 1) / len(deps)
        await progress(frac, f"Installing dependency: {dep}")
        if _test_mode():
            await asyncio.sleep(0.3)
            continue
        rc, _out, err = await _run(
            ["dependency", "install", "--bottle", name, "--name", dep], timeout=1200
        )
        # A dependency that is already present should not abort the whole install.
        if rc != 0 and "already" not in err.lower():
            await progress(frac, f"⚠ dependency '{dep}' failed: {err.strip()[:120]}")


async def run_installer(
    name: str,
    installer_path: str,
    progress: Progress = _noop,
    cancel: asyncio.Event | None = None,
) -> str:
    """Run a setup executable inside the bottle.

    Returns a short status string. Progress is streamed while the installer
    runs; because GUI installers give no machine-readable progress, we report a
    slow indeterminate crawl and then completion on exit.
    """
    await progress(0.30, f"Launching installer in '{name}'…")

    if _test_mode():
        for pct in range(30, 100, 7):
            if cancel and cancel.is_set():
                raise BottlesError("Cancelled")
            await asyncio.sleep(0.25)
            await progress(pct / 100, f"[test] installing… {pct}%")
        return "installed (simulated)"

    argv = _resolve_cli() + ["run", "-b", name, "-e", installer_path]
    proc = await asyncio.create_subprocess_exec(
        *argv,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )

    # Crawl progress from 30%→90% while the installer is alive; jump to done on exit.
    crawl = 0.30
    while True:
        if cancel and cancel.is_set():
            proc.kill()
            raise BottlesError("Cancelled by user")
        try:
            await asyncio.wait_for(proc.wait(), timeout=2.0)
            break
        except asyncio.TimeoutError:
            crawl = min(0.90, crawl + 0.03)
            await progress(crawl, "Installer running… (complete it in the window)")

    out = b""
    if proc.stdout:
        out = await proc.stdout.read()
    if proc.returncode not in (0, None):
        raise BottlesError(
            f"Installer exited with code {proc.returncode}. "
            f"Output: {out.decode(errors='replace')[-400:]}"
        )
    return "installed"


async def list_programs(name: str) -> list[str]:
    if _test_mode():
        return ["Example Game.exe", "Config.exe"]
    rc, out, _err = await _run(["programs", "-b", name], timeout=120)
    if rc != 0:
        return []
    return [ln.strip("-• \t") for ln in out.splitlines() if ln.strip()]
