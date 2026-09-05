#!/usr/bin/env python3
"""PC1's user-owned Windows install worker and managed application launcher.

Recipes provide optional unattended installs on a separate X server. General
EXE/MSI setup runs as the player on the shell's display, with explicit library
selection afterwards. Arguments are always passed as arrays, never shell code.
Wine prefixes are compatibility environments, not security sandboxes.
"""

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import stat
import struct
import subprocess
import tempfile
import threading
import time
import urllib.request
import uuid


BASE = Path(os.environ.get("MARWANOS_WINDOWS_HOME", str(Path.home() / ".local/share/marwanos/windows")))
RECIPES = Path(os.environ.get("MARWANOS_WINDOWS_RECIPES", str(Path(__file__).with_name("recipes.json"))))
RUNNER = os.environ.get("MARWANOS_WINDOWS_RUNTIME", "umu-run")
HELPER = str(Path(__file__).resolve())
ACTIVE = {"queued", "downloading", "verifying", "installing"}


def read_json(path, fallback):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return fallback


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        with temporary.open("x") as stream:
            os.chmod(temporary, 0o600)
            json.dump(value, stream)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


@contextlib.contextmanager
def exclusive(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


def runtime_env(prefix, installing=False):
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(("STEAM_", "Steam", "GAMESCOPE_")) or key in {
            "WINEPREFIX", "GAMEID", "PROTON_VERB", "ENABLE_GAMESCOPE_WSI"
        }:
            env.pop(key, None)
    env.update(WINEPREFIX=str(prefix), GAMEID="0", PROTON_VERB="waitforexitandrun")
    if installing:
        for key in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY"):
            env.pop(key, None)
        env.update(WINEDLLOVERRIDES="winemenubuilder.exe=d", WINEDEBUG="-all")
    return env


def stop_group(process):
    # Always sweep the group, even if its leader exited before its children.
    with contextlib.suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        pass
    with contextlib.suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGKILL)
    process.wait()


class Cancelled(Exception):
    pass


class InstallError(Exception):
    pass


@contextlib.contextmanager
def hidden_display(log):
    reader, writer = os.pipe()
    process = None
    try:
        process = subprocess.Popen(
            ["Xvfb", "-displayfd", str(writer), "-screen", "0", "1280x720x24", "-nolisten", "tcp", "-extension", "GLX"],
            pass_fds=(writer,), stdout=log, stderr=log, start_new_session=True,
        )
        os.close(writer)
        writer = -1
        with selectors.DefaultSelector() as selector:
            selector.register(reader, selectors.EVENT_READ)
            if not selector.select(timeout=15):
                raise InstallError("Could not prepare the background installer. Try again.")
        number = os.read(reader, 64).decode().strip()
        if not number.isdigit():
            raise InstallError("Could not prepare the background installer. Try again.")
        yield ":" + number
    finally:
        os.close(reader)
        if writer >= 0:
            os.close(writer)
        if process is not None:
            stop_group(process)


class Manager:
    def __init__(self, base=BASE, recipes_path=RECIPES, roots=None):
        self.base = Path(base)
        self.base.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.requests = self.base / "requests"
        self.requests.mkdir(exist_ok=True)
        self.recipes = {r["id"]: r for r in json.loads(Path(recipes_path).read_text())}
        for key, recipe in self.recipes.items():
            if not re.fullmatch(r"[a-z0-9-]+", key) or not re.fullmatch(r"[a-f0-9]{64}", recipe["sha256"]):
                raise ValueError("Invalid recipe identifier or checksum")
            for relative in [recipe["executable"], *recipe["verify_files"]]:
                if Path(relative).is_absolute() or ".." in Path(relative).parts:
                    raise ValueError("Recipe path escapes the application prefix")
        self.roots = roots if roots is not None else [Path.home() / "Downloads", Path("/run/media/player")]
        self.state = read_json(self.base / "state.json", {})
        if not isinstance(self.state, dict):
            self.state = {}
        if self.state.get("status") in ACTIVE:
            self.state.update(status="failed", detail="Installation was interrupted. Select the installer to retry.")
        self.state.setdefault("status", "idle")
        self.state.setdefault("detail", "Choose an app to install.")
        self.cancel = threading.Event()
        self.thread = None
        self.guard = threading.Lock()
        self.sources = {}
        self.scan()

    def update(self, **values):
        with self.guard:
            self.state.update(values)

    def scan(self):
        sources = {}
        # Bounded traversal: removable storage may contain millions of files.
        for root in self.roots:
            root = Path(root)
            if not root.is_dir():
                continue
            visited = 0
            for directory, folders, files in os.walk(root, followlinks=False):
                visited += 1
                if visited > 512:
                    break
                if len(Path(directory).relative_to(root).parts) >= 3:
                    folders[:] = []
                folders[:] = sorted(f for f in folders if not f.startswith("."))
                for name in sorted(files):
                    if not name.lower().endswith((".exe", ".msi")):
                        continue
                    path = Path(directory) / name
                    if path.is_symlink() or not path.is_file():
                        continue
                    if not path.resolve().is_relative_to(root.resolve()):
                        continue
                    recipe = next((r for r in self.recipes.values() if r["filename"] == name), None)
                    source_id = hashlib.sha256(str(path).encode()).hexdigest()
                    sources[source_id] = {
                        "id": source_id, "path": str(path), "name": name,
                        "recipe_id": recipe["id"] if recipe else "",
                        "location": root.name,
                    }
                    if len(sources) >= 200:
                        break
                if len(sources) >= 200:
                    break
        self.sources = sources

    def library(self):
        result = []
        for path in sorted((self.base / "apps").glob("*.json")):
            entry = read_json(path, {})
            if isinstance(entry, dict) and isinstance(entry.get("executable"), str) and entry.get("id") and Path(entry["executable"]).is_file():
                result.append(entry)
        return result

    def publish(self):
        with self.guard:
            snapshot = dict(self.state)
        snapshot.update(
            heartbeat=time.time(), library=self.library(), candidates=list(self.sources.values()),
            recipes=[{k: r[k] for k in ("id", "title", "version", "filename")} for r in self.recipes.values()],
        )
        atomic_json(self.base / "state.json", snapshot)

    def check_cancel(self):
        if self.cancel.is_set():
            raise Cancelled()

    def handle(self, request):
        if not isinstance(request, dict):
            return
        verb = request.get("verb")
        if verb == "cancel":
            if request.get("job_id") == self.state.get("job_id"):
                self.cancel.set()
            return
        if verb != "install" or self.thread is not None and self.thread.is_alive():
            return
        key = request.get("recipe_id")
        source = request.get("source_id", "download")
        if not isinstance(key, str) or key not in self.recipes:
            self.update(status="failed", detail="This installer is not supported yet.")
            return
        if source != "download" and (not isinstance(source, str) or source not in self.sources or self.sources[source]["recipe_id"] != key):
            self.update(status="failed", detail="The installer is no longer available. Reconnect the drive and try again.")
            return
        if any(e.get("recipe_id") == key for e in self.library()):
            self.update(status="done", detail="Already installed. Open it from the library.")
            return
        self.cancel.clear()
        self.update(status="queued", detail="Preparing installation", recipe_id=key, progress=-1, job_id=uuid.uuid4().hex)
        path = None if source == "download" else Path(self.sources[source]["path"])
        self.thread = threading.Thread(target=self.install, args=(self.recipes[key], path), daemon=False)
        self.thread.start()

    def consume(self):
        for path in sorted(self.requests.glob("*.json"))[:32]:
            try:
                if not path.is_symlink() and path.is_file() and path.stat().st_size <= 4096:
                    self.handle(read_json(path, {}))
            except FileNotFoundError:
                pass
            finally:
                path.unlink(missing_ok=True)

    def copy_installer(self, recipe, source, target):
        self.update(status="downloading" if source is None else "verifying",
                    detail="Downloading installer" if source is None else "Checking installer", progress=0)
        digest = hashlib.sha256()
        if source is None:
            if not recipe["url"].startswith("https://"):
                raise InstallError("The download source is invalid.")
            stream = urllib.request.urlopen(recipe["url"], timeout=15)
            if not stream.geturl().startswith("https://"):
                stream.close()
                raise InstallError("The download source is invalid.")
        else:
            stream = source.open("rb")
        count = 0
        deadline = time.monotonic() + 300
        with stream, target.open("xb") as output:
            while True:
                self.check_cancel()
                if time.monotonic() > deadline:
                    raise InstallError("The download took too long. Check your connection and retry.")
                chunk = stream.read(65536)
                if not chunk:
                    break
                count += len(chunk)
                if count > recipe["size"]:
                    raise InstallError("This installer does not match the supported version.")
                output.write(chunk)
                digest.update(chunk)
                self.update(progress=int(count * 100 / recipe["size"]))
        self.check_cancel()
        if count != recipe["size"] or digest.hexdigest() != recipe["sha256"]:
            raise InstallError("This installer does not match the supported version. Download a fresh copy and retry.")

    def run_installer(self, recipe, installer, prefix, log):
        env = runtime_env(prefix, installing=True)
        with hidden_display(log) as display:
            env["DISPLAY"] = display
            process = subprocess.Popen([RUNNER, str(installer), *recipe["arguments"]],
                                       env=env, cwd=installer.parent, stdout=log, stderr=log, start_new_session=True)
            deadline = time.monotonic() + recipe["timeout_seconds"]
            try:
                while process.poll() is None:
                    self.check_cancel()
                    if time.monotonic() >= deadline:
                        raise InstallError("Installation took too long. Select the installer to retry.")
                    time.sleep(0.2)
                if process.returncode != 0:
                    raise InstallError("Installation failed. Check your connection and free space, then retry.")
            finally:
                stop_group(process)

    def install(self, recipe, source):
        attempt = self.base / "prefixes" / (recipe["id"] + "-" + uuid.uuid4().hex)
        committed = False
        try:
            attempt.mkdir(parents=True)
            if shutil.disk_usage(self.base).free < 2 * 1024**3:
                raise InstallError("At least 2 GB of free space is needed. Free some space and retry.")
            with tempfile.TemporaryDirectory(prefix="pc1-install-") as work:
                installer = Path(work) / recipe["filename"]
                self.copy_installer(recipe, source, installer)
                self.check_cancel()
                self.update(status="installing", detail="Installing in the background. First-time setup may take several minutes.", progress=-1)
                logs = self.base / "logs"
                logs.mkdir(exist_ok=True)
                with (logs / (recipe["id"] + ".log")).open("wb") as log:
                    self.run_installer(recipe, installer, attempt, log)
                self.check_cancel()
                for relative in [recipe["executable"], *recipe["verify_files"]]:
                    installed = attempt / relative
                    if not installed.is_file() or installed.stat().st_size == 0 or not installed.resolve().is_relative_to(attempt.resolve()):
                        raise InstallError("Installation did not finish correctly. Select the installer to retry.")
                executable = attempt / recipe["executable"]
                entry = {
                    "id": "managed." + recipe["id"], "recipe_id": recipe["id"],
                    "title": recipe["title"], "version": recipe["version"],
                    "prefix": str(attempt), "executable": str(executable),
                    "input_mode": recipe["input_mode"], "state": "installed",
                    "exec": [HELPER, "launch", recipe["id"]],
                    "stop_exec": [HELPER, "stop", recipe["id"]],
                    "subtitle": "Windows app", "icon": "",
                }
                atomic_json(self.base / "apps" / (recipe["id"] + ".json"), entry)
                committed = True
                self.update(status="done", detail=recipe["title"] + " is ready in your library.", progress=100)
        except Cancelled:
            self.update(status="cancelled", detail="Installation cancelled. You can start it again whenever you like.", progress=-1)
        except Exception as error:
            print("Windows installation failed:", repr(error), flush=True)
            detail = str(error) if isinstance(error, InstallError) else "Could not install. Check your connection and free space, then retry."
            self.update(status="failed", detail=detail, progress=-1)
        finally:
            if not committed and attempt.exists():
                # attempt is created by this worker, beneath its own prefixes root.
                try:
                    shutil.rmtree(attempt)
                except OSError as error:
                    print("Could not remove incomplete prefix:", repr(error), flush=True)

    def serve(self):
        stopping = threading.Event()
        def stop(_signum, _frame):
            stopping.set()
            self.cancel.set()
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        next_scan = 0
        try:
            while not stopping.is_set():
                if time.monotonic() >= next_scan:
                    self.scan()
                    next_scan = time.monotonic() + 5
                self.consume()
                self.publish()
                stopping.wait(0.5)
        finally:
            self.cancel.set()
            if self.thread:
                self.thread.join()
            self.publish()


def proc_start(pid):
    try:
        return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19]
    except (OSError, IndexError):
        return None


def windows_file(source):
    """Validate a local Windows file, without a recipe or location allowlist."""
    path = Path(source)
    if not path.is_absolute() or path.suffix.lower() not in {".exe", ".msi"}:
        raise InstallError("Choose a Windows EXE or MSI file.")
    path = path.resolve(strict=True)
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NONBLOCK), "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise InstallError("Choose a regular installer file.")
        header = stream.read(64)
        if Path(source).suffix.lower() == ".msi":
            valid = header[:8] == bytes.fromhex("d0cf11e0a1b11ae1")
        else:
            valid = False
            if len(header) == 64 and header[:2] == b"MZ":
                stream.seek(struct.unpack_from("<I", header, 60)[0])
                valid = stream.read(4) == b"PE\0\0"
        if not valid:
            raise InstallError("This file is incomplete or is not a Windows installer. Download it again.")
    return path


def local_candidates(prefix):
    """Discover launch targets only inside C:, excluding Wine and maintenance tools.

    Never follow drive links into the player's home or Z:. Return relative names
    so a library choice cannot become an arbitrary command or escape the prefix.
    """
    drive = prefix / "drive_c"
    if drive.is_symlink() or not drive.is_dir():
        return []
    result = []
    for directory, folders, files in os.walk(drive, followlinks=False):
        relative = Path(directory).relative_to(drive)
        folders[:] = sorted(f for f in folders if not (Path(directory) / f).is_symlink()
                            and f.lower() not in {"windows", "$recycle.bin", "temp", "installer"})
        for name in sorted(files):
            if not name.lower().endswith(".exe") or re.match(r"(?i)(unins|uninstall|setup|vcredist|vc_redist)", name):
                continue
            path = Path(directory) / name
            if path.is_symlink() or not path.resolve().is_relative_to(drive.resolve()):
                continue
            try:
                windows_file(path)
                # Proton seeds programs such as WordPad and Internet Explorer
                # outside C:\windows too. They are runtime files, not installs.
                with path.open("rb") as stream:
                    if b"Wine builtin DLL" in stream.read(128):
                        continue
            except (OSError, InstallError):
                continue
            result.append({"id": str(path.relative_to(prefix)), "title": Path(name).stem,
                           "detail": str(relative / name)})
    return result


def local_setup(base, key, source, portable=False):
    """Called by Launcher in the player session, never by the hidden daemon."""
    job_path = base / "jobs" / (key + ".json")
    prefix = base / "prefixes" / key
    job = {"id": key, "source": source, "created_at": time.time(), "status": "preparing", "choices": [],
           "detail": "Preparing Windows setup. First-time setup may take several minutes."}
    with exclusive(base / "local-setup.lock"):
        # A new key per attempt preserves partial installations and previous apps.
        if job_path.exists() or prefix.exists():
            raise InstallError("This installation attempt already exists. Start a new attempt.")
        atomic_json(job_path, job)
        try:
            installer = windows_file(source)
            prefix.mkdir(parents=True)
            if portable:
                if Path(source).suffix.lower() != ".exe":
                    raise InstallError("Portable apps must be EXE files.")
                job.update(status="select", portable=str(installer), choices=[{
                    "id": "portable", "title": installer.stem, "detail": str(installer)}])
                atomic_json(job_path, job)
                return register_local(base, key, "portable")
            env = runtime_env(prefix)
            env.update(WINEDLLOVERRIDES="winemenubuilder.exe=d")
            # Keep adjacent CAB/BIN files in place: multipart installers need them.
            args = [RUNNER, str(installer)]
            if Path(source).suffix.lower() == ".msi":
                args = [RUNNER, "msiexec", "/i", "Z:" + str(installer).replace("/", "\\")]
            logs = base / "logs"
            logs.mkdir(exist_ok=True)
            with (logs / (key + ".log")).open("wb") as log:
                process = subprocess.Popen(args, env=env, cwd=installer.parent,
                                           stdout=log, stderr=log, start_new_session=True)
                running = base / "running" / (key + ".json")
                # Record the wrapper too: Close must stop discovery/publication,
                # as well as every installer process in the runtime group.
                atomic_json(running, {"pid": process.pid, "start": proc_start(process.pid),
                                     "owner": os.getpid(), "owner_start": proc_start(os.getpid())})
                cancelled = threading.Event()
                def stop(_signum, _frame):
                    cancelled.set()
                    with contextlib.suppress(ProcessLookupError):
                        os.killpg(process.pid, signal.SIGTERM)
                old_signals = {sig: signal.signal(sig, stop) for sig in (signal.SIGTERM, signal.SIGINT)}
                job.update(status="installing", detail="Complete the Windows setup window, then close it to continue.")
                atomic_json(job_path, job)
                try:
                    while process.poll() is None and not cancelled.wait(0.2):
                        pass
                finally:
                    stop_group(process)
                    running.unlink(missing_ok=True)
                    for sig, handler in old_signals.items():
                        signal.signal(sig, handler)
                choices = local_candidates(prefix)
                if cancelled.is_set():
                    job.update(status="cancelled", detail="Setup was closed. You can start it again.", choices=[])
                elif process.returncode not in (0, 3010):
                    job.update(status="failed", detail="Windows setup exited with an error (%s). You can retry." % process.returncode,
                               choices=choices)
                else:
                    job.update(status="select" if choices else "empty", choices=choices,
                               detail="Choose the program to add to your library." if choices else
                               "No installed program was found. Retry setup, or use Add as portable app for a standalone EXE.")
                job["exit_code"] = process.returncode
                atomic_json(job_path, job)
                return 0
        except (OSError, InstallError) as error:
            job.update(status="failed", detail=str(error), choices=[])
            atomic_json(job_path, job)
            return 1


def register_local(base, key, choice):
    job_path = base / "jobs" / (key + ".json")
    job = read_json(job_path, {})
    try:
        if job.get("status") not in {"select", "failed"}:
            raise InstallError("Finish setup before adding a program.")
        prefix = base / "prefixes" / key
        candidates = job.get("choices", []) if job.get("portable") else local_candidates(prefix)
        selected = next((item for item in candidates if item["id"] == choice), None)
        if not selected:
            raise InstallError("That program is no longer available. Run setup again.")
        executable = windows_file(job["portable"] if job.get("portable") else prefix / choice)
        entry = {"id": "managed." + key, "recipe_id": key, "title": selected["title"],
                 "prefix": str(prefix), "executable": str(executable), "input_mode": "pointer",
                 "state": "installed", "subtitle": "Windows app", "icon": "",
                 "exec": [HELPER, "launch", key], "stop_exec": [HELPER, "stop", key]}
        atomic_json(base / "apps" / (key + ".json"), entry)
        job.update(status="done", detail=entry["title"] + " is ready in your library.", choices=[])
        atomic_json(job_path, job)
        return 0
    except (OSError, InstallError) as error:
        job.update(status="failed", detail=str(error))
        atomic_json(job_path, job)
        return 1


def launch(base, key):
    entry = read_json(base / "apps" / (key + ".json"), {})
    executable = Path(entry.get("executable", ""))
    if not executable.is_file():
        raise InstallError("Application is missing. Install it again.")
    with exclusive(base / "running" / (key + ".lock")):
        process = subprocess.Popen([RUNNER, str(executable)], env=runtime_env(Path(entry["prefix"])),
                                   cwd=executable.parent, start_new_session=True)
        running = base / "running" / (key + ".json")
        atomic_json(running, {"pid": process.pid, "start": proc_start(process.pid)})
        def stop(_signum, _frame):
            stop_group(process)
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        try:
            return process.wait()
        finally:
            stop_group(process)
            running.unlink(missing_ok=True)


def stop_app(base, key):
    state = read_json(base / "running" / (key + ".json"), {})
    pid = state.get("pid", 0)
    if not isinstance(pid, int) or pid <= 1 or not state.get("start"):
        return
    if proc_start(pid) != state["start"]:
        return
    owner = state.get("owner", 0)
    if isinstance(owner, int) and owner > 1 and state.get("owner_start") and proc_start(owner) == state["owner_start"]:
        with contextlib.suppress(ProcessLookupError):
            os.kill(owner, signal.SIGTERM)
    with contextlib.suppress(ProcessLookupError):
        os.killpg(pid, signal.SIGTERM)
    deadline = time.monotonic() + 5
    while proc_start(pid) == state["start"] and time.monotonic() < deadline:
        time.sleep(0.1)
    if proc_start(pid) == state["start"]:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(pid, signal.SIGKILL)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["daemon", "launch", "stop", "setup", "portable", "register"])
    parser.add_argument("app", nargs="?")
    parser.add_argument("source", nargs="?")
    args = parser.parse_args()
    os.umask(0o077)
    if args.command == "daemon":
        with exclusive(BASE / "worker.lock"):
            Manager().serve()
        return 0
    if not args.app or not re.fullmatch(r"[a-z0-9-]+", args.app):
        parser.error("a recipe identifier is required")
    if args.command in {"setup", "portable", "register"}:
        if not re.fullmatch(r"local-[a-z0-9-]+", args.app) or not args.source:
            parser.error("a local attempt identifier and source are required")
        if args.command == "register":
            return register_local(BASE, args.app, args.source)
        return local_setup(BASE, args.app, args.source, portable=args.command == "portable")
    if args.command == "launch":
        return launch(BASE, args.app)
    stop_app(BASE, args.app)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
