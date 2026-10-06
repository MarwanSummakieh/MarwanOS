#!/usr/bin/env bash
# Evidence only: never suspends/wakes, changes audio, injects input or escalates.
# --before FILE exclusively creates the named JSON baseline; --after FILE reads
# that baseline and prints comparisons. No other files are written. Run directly
# on PC1 as the already-authorized root or player account. A PASS establishes
# software continuity/counters only, not visible video, audible sound, physical
# controls, controller wake support, game stability or cold-boot acceptance.
set -euo pipefail
[[ $# == 2 && ( "$1" == --before || "$1" == --after ) && -n "$2" ]] || {
    printf '%s\n' 'Usage: inspect-pc1-resume.sh --before FILE | --after FILE' >&2
    exit 2
}
python3 - "$1" "$2" <<'PY'
import datetime
import json
import math
import os
from pathlib import Path
import pwd
import re
import stat
import subprocess
import sys
import time

mode, filename = sys.argv[1:]
failures = []


def check(label, condition, detail=""):
    print(("PASS" if condition else "FAIL") + ": " + label + (" — " + detail if detail else ""))
    if not condition:
        failures.append(label)


def text(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ""


def json_file(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None


def command(args):
    try:
        result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=20, check=False)
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as error:
        return 1, "", str(error)


def counters():
    directory = Path("/sys/power/suspend_stats")
    if directory.is_dir():
        values = {path.name: text(path) for path in directory.iterdir() if path.is_file()}
        return {"source": str(directory), **values}
    for path in (directory, Path("/sys/kernel/debug/suspend_stats")):
        value = text(path)
        if value:
            rows = dict(re.findall(r"^\s*([a-z_]+)\s*:\s*(-?\d+)\s*$", value, re.MULTILINE))
            return {"source": str(path), **rows}
    return {}


def process_ids(pattern, uid):
    code, output, _error = command(["pgrep", "-u", str(uid), "-f", pattern])
    return sorted(int(line) for line in output.splitlines() if line.isdigit()) if code == 0 else []


def snapshot():
    player = pwd.getpwnam("player")
    if os.geteuid() not in (0, player.pw_uid):
        raise ValueError("Run as player or an already-authorized root; this helper never elevates privileges.")
    runtime = Path(f"/run/user/{player.pw_uid}")
    home = Path(player.pw_dir)
    user = ["env", f"XDG_RUNTIME_DIR={runtime}", f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime}/bus", "systemctl", "--user"]
    if os.geteuid() == 0:
        user = ["runuser", "-u", "player", "--", *user]
    units = {}
    for unit in ("greetd", "marwanos-windows", "marwanos-update"):
        code, value, error = command(["systemctl", "is-active", unit + ".service"])
        units[unit] = value if not error else value or error
    for unit in ("audio", "metadata", "achievements", "bluetooth", "notifications"):
        code, value, error = command([*user, "is-active", f"marwanos-{unit}.service"])
        units[unit] = value if not error else value or error
    heartbeat = runtime / "marwanos/shell.ready"
    try:
        heartbeat_mtime = heartbeat.stat().st_mtime
    except OSError:
        heartbeat_mtime = 0
    names = []
    for event in Path("/sys/class/input").glob("event*"):
        name = text(event / "device/name")
        if name.startswith("PC1 application controller"):
            names.append(name)
    endpoint = runtime / "marwanos/controller/endpoint.json"
    try:
        state = endpoint.stat()
        private_endpoint = state.st_uid == player.pw_uid and stat.S_IMODE(state.st_mode) == 0o600
    except OSError:
        private_endpoint = False
    return {"version": 1, "observed_at": time.time(), "boot_id": text("/proc/sys/kernel/random/boot_id"),
            "uptime": text("/proc/uptime"), "suspend": counters(),
            "power_state": text("/sys/power/state"), "mem_sleep": text("/sys/power/mem_sleep"),
            "nvidia": {path.parent.name: text(path) for path in Path("/proc/driver/nvidia/gpus").glob("*/information")},
            "processes": {"gamescope": process_ids(r"(^|/)gamescope( |$)", player.pw_uid),
                          "shell": process_ids(r"(^|/)marwanos-shell( |$)", player.pw_uid),
                          "session": process_ids(r"/session/marwanos-session", player.pw_uid),
                          "broker": process_ids(r"/controller/router\.py( |$)", player.pw_uid)},
            "units": units, "heartbeat_mtime": heartbeat_mtime,
            "audio": json_file(runtime / "marwanos/audio/state.json") or {},
            "controller_identities": json_file(home / ".local/state/marwanos/controller/slots.json"),
            "virtual_pads": sorted(names), "private_endpoint": private_endpoint}


def valid_count(value):
    return isinstance(value, (str, int)) and str(value).isdigit()


def health(state):
    now = time.time()
    age = now - state.get("heartbeat_mtime", 0)
    check("fresh shell frame heartbeat", math.isfinite(age) and 0 <= age < 5, f"age {age:.2f}s")
    audio = state.get("audio", {})
    try:
        age = now - float(audio.get("updated_at", 0))
    except (TypeError, ValueError):
        age = float("inf")
    check("fresh available audio state", audio.get("available") is True and not audio.get("error")
          and math.isfinite(age) and 0 <= age < 12)
    target = audio.get("default_output", "")
    check("default output still enumerated", bool(target)
          and any(item.get("name") == target for item in audio.get("outputs", [])), str(target))
    for unit, value in state.get("units", {}).items():
        check(unit + " worker active", value == "active", str(value))
    for label, pids in state.get("processes", {}).items():
        check(label + " process present", bool(pids), str(pids))
    check("NVIDIA GPU still exposed", bool(state.get("nvidia")))
    identities = state.get("controller_identities")
    check("physical controller slot identity present", isinstance(identities, list) and len(identities) == 4 and bool(identities[0]))
    expected = ["PC1 application controller", "PC1 application controller 2", "PC1 application controller 3", "PC1 application controller 4"]
    check("four virtual application pads present", state.get("virtual_pads") == expected)
    check("controller endpoint private", state.get("private_endpoint") is True)


def main():
    if mode == "--before":
        state = snapshot()
        check("boot ID available", bool(state["boot_id"]))
        check("suspend success/fail counters readable", all(valid_count(state["suspend"].get(key)) for key in ("success", "fail")),
              str(state["suspend"].get("source", "missing")))
        health(state)
        # Exclusive creation protects earlier evidence. Only this explicit file
        # is written; no directories or hidden snapshots are created.
        descriptor = os.open(filename, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            json.dump(state, stream, indent=2)
            stream.write("\n")
        print("Snapshot saved to " + filename)
        return
    baseline = json_file(filename)
    if not isinstance(baseline, dict) or baseline.get("version") != 1:
        check("valid before snapshot", False, filename)
        return
    observed = baseline.get("observed_at")
    if (not all(isinstance(baseline.get(key), dict) for key in ("suspend", "audio", "processes"))
            or not isinstance(observed, (int, float)) or isinstance(observed, bool)
            or not math.isfinite(observed) or not 0 < observed <= time.time()):
        check("valid before snapshot fields", False, filename)
        return
    state = snapshot()
    same_boot = bool(state["boot_id"]) and state["boot_id"] == baseline.get("boot_id")
    check("same boot ID (no intervening reboot)", same_boot)
    for key in ("success", "fail"):
        old, new = baseline.get("suspend", {}).get(key), state["suspend"].get(key)
        valid = valid_count(old) and valid_count(new)
        condition = valid and same_boot and (int(new) > int(old) if key == "success" else int(new) == int(old))
        check("successful suspend count increased" if key == "success" else "failed suspend count unchanged", condition, f"{old} → {new}")
    health(state)
    check("controller identity/slot assignment preserved", state["controller_identities"] == baseline.get("controller_identities"))
    check("default output preserved", state["audio"].get("default_output") == baseline.get("audio", {}).get("default_output"),
          "A deliberate route or hardware change needs separate assessment.")
    for label, pids in state["processes"].items():
        check(label + " survived without restart", bool(pids) and pids == baseline.get("processes", {}).get(label), str(pids))
    if isinstance(observed, (int, float)) and math.isfinite(observed):
        since = datetime.datetime.fromtimestamp(observed, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        code, output, error = command(["journalctl", "-b", "--since", since, "--no-pager", "-n", "60", "-g",
            "PM:|suspend|resume|NVRM|Xid|GPU has fallen|segfault|gamescope|Controller|marwanos-session"])
        print("Resume/session/GPU journal since baseline:")
        print(output or error or "No matching records (journal permissions may limit player access).")
        readable = code in (0, 1) and not error
        check("journal query completed without access errors", readable, error)
        gpu_fault = bool(re.search(r"NVRM:.*Xid|GPU has fallen|segfault", output))
        check("no recorded GPU/segfault pattern in displayed journal", readable and not gpu_fault,
              "Only the selected journal window is examined; review full logs for acceptance.")
    print("INFO: Physically verify the resumed screen, sound, fresh controller presses/Home and game launch separately.")


try:
    main()
except (OSError, ValueError, KeyError, TypeError, OverflowError) as error:
    check("evidence inspection completed", False, str(error))
print(f"Resume evidence checks: {len(failures)} failure(s)")
sys.exit(1 if failures else 0)
PY
