#!/usr/bin/env bash
# Read-only postboot software checks. Physical acceptance is recorded separately.
set -euo pipefail
usage() {
    printf '%s\n' 'Usage: accept-pc1-image.sh --digest sha256:HEX --commit GIT_SHA [--host root@PC1] [--game-id ID]'
}
digest="" commit="" host="" game="managed.local-tekken8-fresh-1791234744"
while (($#)); do
    case "$1" in
        --digest|--commit|--host|--game-id)
            (($# >= 2)) || { usage >&2; exit 2; }
            case "$1" in
                --digest) digest="$2";;
                --commit) commit="$2";;
                --host) host="$2";;
                --game-id) game="$2";;
            esac
            shift 2;;
        --help|-h) usage; exit 0;;
        *) usage >&2; exit 2;;
    esac
done
[[ "$digest" =~ ^sha256:[a-f0-9]{64}$ && "$commit" =~ ^[a-f0-9]{7,40}$ && "$game" =~ ^[A-Za-z0-9._-]+$ ]] || { usage >&2; exit 2; }
[[ -z "$host" || "$host" =~ ^[A-Za-z0-9@._:-]+$ ]] || { printf '%s\n' 'Invalid SSH host.' >&2; exit 2; }
runner=(python3 - "$digest" "$commit" "$game")
if [[ -n "$host" ]]; then
    # All remote arguments above are restricted to shell-safe identifiers.
    runner=(ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" python3 - "$digest" "$commit" "$game")
fi
"${runner[@]}" <<'PY'
import hashlib
import json
import math
import os
from pathlib import Path
import pwd
import stat
import subprocess
import sys
import time

expected_digest, expected_commit, game_id = sys.argv[1:]
failures = []


def check(label, condition, detail=""):
    print(("PASS" if condition else "FAIL") + ": " + label + (" — " + detail if detail else ""))
    if not condition:
        failures.append(label)


def command(args):
    try:
        result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=20, check=False)
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as error:
        return 1, "", str(error)


def read_json(path):
    try:
        value = json.loads(Path(path).read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def walk_mounts(values):
    for value in values:
        yield value
        yield from walk_mounts(value.get("children", []))


def main():
    if os.geteuid() != 0:
        check("run as root to read release/boot state", False)
        return
    try:
        player = pwd.getpwnam("player")
    except KeyError:
        check("player account exists", False)
        return
    home, runtime = Path(player.pw_dir), Path(f"/run/user/{player.pw_uid}")
    code, output, error = command(["rpm-ostree", "status", "--json"])
    try:
        deployments = json.loads(output).get("deployments", []) if code == 0 else []
    except (ValueError, AttributeError):
        deployments = []
    booted = next((item for item in deployments if item.get("booted")), {})
    actual_digest = booted.get("container-image-reference-digest", "")
    check("booted expected image digest", actual_digest == expected_digest, actual_digest or error or "no booted container deployment")
    try:
        build = dict(line.split("=", 1) for line in Path("/usr/share/marwanos/build-info").read_text().splitlines() if "=" in line)
    except OSError:
        build = {}
    actual_commit = build.get("MARWANOS_COMMIT", "")
    check("baked expected source commit", actual_commit == expected_commit and "dirty" not in actual_commit,
          actual_commit or "build-info missing")
    check("development shell disabled", not Path("/var/marwanos/devmode").exists())
    code, output, error = command(["findmnt", "--json", "--output", "TARGET,SOURCE"])
    try:
        mounts = list(walk_mounts(json.loads(output).get("filesystems", []))) if code == 0 else []
    except (ValueError, AttributeError):
        mounts = []
    overrides = [item.get("target", "") for item in mounts if item.get("target", "").startswith("/usr/lib/marwanos/")]
    check("baked application files have no bind overrides", code == 0 and not overrides,
          ", ".join(overrides) or error)
    code, output, _ = command(["systemctl", "is-active", "marwanos-bench-fixes.service"])
    check("bench bind service inactive", code != 0 and output in ("inactive", "unknown", "failed"), output)
    for unit in ["greetd.service", "marwanos-windows.service", "marwanos-update.service"]:
        code, output, error = command(["systemctl", "is-active", unit])
        check(unit + " active", code == 0 and output == "active", output or error)
    user_prefix = ["runuser", "-u", "player", "--", "env", f"XDG_RUNTIME_DIR={runtime}",
                   f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime}/bus", "systemctl", "--user"]
    for unit in ["marwanos-metadata.service", "marwanos-audio.service", "marwanos-achievements.service", "marwanos-bluetooth.service", "marwanos-notifications.service"]:
        code, output, error = command([*user_prefix, "is-active", unit])
        check(unit + " active", code == 0 and output == "active", output or error)
        code, output, error = command([*user_prefix, "show", unit, "--property=ExecStart", "--value"])
        check(unit + " executes image payload", code == 0 and "/usr/lib/marwanos/" in output and "/var/marwanos/" not in output,
              "override or missing payload" if code != 0 or "/var/marwanos/" in output else "")
    for prefix, label in [(["systemctl"], "system"), (user_prefix, "player")]:
        code, output, error = command([*prefix, "--failed", "--no-legend", "--no-pager"])
        check(label + " has no failed units", code == 0 and not output, output or error)
    marker = runtime / "marwanos/shell.ready"
    try:
        age = time.time() - marker.stat().st_mtime
        check("shell frame heartbeat fresh", 0 <= age < 5, f"age {age:.2f}s")
    except OSError:
        check("shell frame heartbeat fresh", False, "shell.ready missing")
    code, output, error = command(["grub2-editenv", "/boot/grub2/grubenv", "list"])
    check("GRUB records successful boot", code == 0 and "boot_success=1" in output.splitlines(), error or "wait for boot-success timer if just booted")
    audio = read_json(runtime / "marwanos/audio/state.json")
    try:
        audio_age = time.time() - float(audio.get("updated_at", 0))
    except (ValueError, TypeError):
        audio_age = float("inf")
    check("audio state fresh and available", audio.get("available") is True and 0 <= audio_age < 12)
    check("audio output is selectable", bool(audio.get("outputs")) and bool(audio.get("default_output")))
    bluetooth = read_json(runtime / "marwanos/bluetooth/state.json")
    try:
        bluetooth_age = time.time() - float(bluetooth.get("updated_at", 0))
    except (ValueError, TypeError):
        bluetooth_age = float("inf")
    check("Bluetooth state fresh without service errors", bluetooth.get("available") is True
          and bluetooth.get("status") in ("ready", "no-adapter") and not bluetooth.get("error")
          and 0 <= bluetooth_age < 12, str(bluetooth.get("status", "missing")))
    metadata = read_json(home / ".local/share/marwanos/metadata/state.json")
    record = metadata.get("games", {}).get(game_id, {})
    check("installed game metadata cached", record.get("status") in ("ready", "partial", "offline") and bool(record.get("provider_id")), game_id)
    assets = record.get("assets", {})
    for kind in ("cover", "background", "logo", "header"):
        asset = assets.get(kind, {})
        valid = False
        try:
            path = Path(asset["path"])
            cache_root = (home / ".local/share/marwanos/metadata/assets").resolve()
            valid = (not path.is_symlink() and path.resolve().is_relative_to(cache_root)
                     and path.stat().st_size == asset["bytes"]
                     and hashlib.sha256(path.read_bytes()).hexdigest() == asset["sha256"])
        except (OSError, KeyError, TypeError, ValueError):
            pass
        check("verified cached " + kind, valid)
    history = read_json(home / ".local/share/marwanos/play-history/state.json")
    played = history.get("games", {}).get(game_id, {})
    try:
        total = float(played.get("total_seconds", 0))
        last_played = float(played.get("last_played_at", 0))
    except (TypeError, ValueError):
        total, last_played = 0, 0
    check("real game history persists", history.get("schema_version") == 1 and math.isfinite(total)
          and total > 0 and math.isfinite(last_played) and last_played > 0 and bool(played.get("sessions")),
          "play/close the game once before this acceptance check if history is empty")
    achievements = read_json(home / ".local/share/marwanos/achievements/state.json")
    achievement = achievements.get("games", {}).get(game_id, {})
    check("achievement provider response exists", bool(achievement.get("status")),
          str(achievement.get("status", "not synchronized")))
    print("INFO: Achievement display/unlock notifications need genuine provider and controller acceptance.")
    endpoint_path = runtime / "marwanos/controller/endpoint.json"
    endpoint = read_json(endpoint_path)
    try:
        info = endpoint_path.stat()
        private = info.st_uid == player.pw_uid and stat.S_IMODE(info.st_mode) == 0o600
    except OSError:
        private = False
    check("controller endpoint private and present", private and isinstance(endpoint.get("port"), int)
          and 0 < endpoint["port"] < 65536 and len(str(endpoint.get("token", ""))) == 64)
    try:
        identities = json.loads((home / ".local/state/marwanos/controller/slots.json").read_text())
        valid_slots = (isinstance(identities, list) and len(identities) == 4 and all(isinstance(item, str) for item in identities)
                       and bool(identities[0]) and len([item for item in identities if item]) == len({item for item in identities if item}))
    except (OSError, ValueError):
        valid_slots = False
    check("four controller slot identities persist", valid_slots)
    virtual = []
    for event in Path("/sys/class/input").glob("event*"):
        try:
            name = (event / "device/name").read_text().strip()
            if name.startswith("PC1 application controller"):
                virtual.append(name)
        except OSError:
            pass
    expected_names = ["PC1 application controller", *[f"PC1 application controller {index}" for index in (2, 3, 4)]]
    check("four stable application pads enumerated", sorted(virtual) == sorted(expected_names), ", ".join(virtual))
    print("INFO: This read-only software gate does not certify physical sound, rumble, multiplayer, suspend/wake or cold power-on.")


try:
    main()
except Exception as error:
    check("validation completed", False, type(error).__name__ + ": " + str(error))
print(f"Postboot software checks: {len(failures)} failure(s)")
sys.exit(1 if failures else 0)
PY
