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
import re
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


def journal_messages(arguments):
    code, output, error = command(["journalctl", "-b", "--no-pager", "--all", "-o", "json", *arguments])
    # journalctl uses 1 for a successful grep with no matches, but subprocess
    # failures/timeouts also arrive as 1 with an error. Never treat those as an
    # empty journal: the release gate must fail when evidence is unavailable.
    if code not in (0, 1) or (code == 1 and error):
        raise ValueError("boot journal query failed: " + error)
    messages = []
    for line in output.splitlines():
        value = json.loads(line).get("MESSAGE", "")
        if isinstance(value, list):
            value = bytes(value).decode("utf-8", errors="replace")
        if not isinstance(value, str):
            raise ValueError("unreadable boot journal message")
        messages.append(value)
    return messages


def walk_mounts(values):
    for value in values:
        yield value
        yield from walk_mounts(value.get("children", []))


def application_override_mount(item):
    target = item.get("target", "").rstrip("/") or "/"
    if target == "/usr/lib/marwanos" or target.startswith("/usr/lib/marwanos/"):
        return True
    # / and conventional /usr filesystems belong to the OS. A distinct /usr/lib
    # mount, or a bind of a foreign subtree over /usr, can hide all our payloads.
    if target == "/usr/lib":
        return True
    if target != "/usr":
        return False
    options = set(item.get("options", "").split(","))
    fsroot = item.get("fsroot", "/")
    image_usr = re.fullmatch(r"(?:/sysroot)?/ostree/deploy/[^/]+/deploy/[a-f0-9]{64}\.\d+/usr", fsroot)
    return bool(options & {"bind", "rbind"}) or (fsroot != "/" and not image_usr)


def image_unit(prefix, unit, directory):
    code, output, error = command([*prefix, "show", unit,
                                   "--property=FragmentPath,DropInPaths"])
    properties = dict(line.split("=", 1) for line in output.splitlines() if "=" in line)
    fragment = properties.get("FragmentPath", "")
    dropins = properties.get("DropInPaths", "").split()
    valid = (code == 0 and fragment == f"{directory}/{unit}"
             and all(path.startswith(directory + "/") for path in dropins))
    check(unit + " uses image-owned unit configuration", valid,
          error or (f"fragment {fragment or 'missing'}; drop-ins {', '.join(dropins) or 'none'}"))


def image_session_processes(player_uid):
    candidates = {"shell": [], "controller broker": []}
    expected_shell = "/usr/lib/marwanos/shell/marwanos-shell"
    expected_router = "/usr/lib/marwanos/controller/router.py"
    for process in Path("/proc").glob("[0-9]*"):
        try:
            if process.stat().st_uid != player_uid:
                continue
            args = [value.decode(errors="replace") for value in
                    (process / "cmdline").read_bytes().split(b"\0") if value]
            if not args:
                continue
            executable = os.readlink(process / "exe")
            if Path(args[0]).name == "marwanos-shell" or Path(executable).name == "marwanos-shell":
                valid = args[0] == expected_shell and os.path.samefile(process / "exe", expected_shell)
                candidates["shell"].append((process.name, valid, args[0]))
            if len(args) > 1 and Path(args[1]).name == "router.py":
                valid = (args[1] == expected_router and os.path.samefile(process / "exe", "/usr/bin/python3"))
                candidates["controller broker"].append((process.name, valid, args[1]))
        except (OSError, ValueError):
            # A process may exit while /proc is read; a missing live owner still
            # fails below. No process is signalled or endpoint lease refreshed.
            continue
    for label, processes in candidates.items():
        check(label + " runs the image payload as player", len(processes) == 1 and processes[0][1],
              "; ".join(f"PID {pid}: {path}" for pid, _, path in processes) or "no live process; rerun after startup settles")


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
    check("baked expected source commit", 7 <= len(actual_commit) <= 40
          and all(character in "0123456789abcdef" for character in actual_commit)
          and expected_commit.startswith(actual_commit),
          actual_commit or "build-info missing")
    check("development shell disabled", not Path("/var/marwanos/devmode").exists())
    code, output, error = command(["findmnt", "--json", "--output", "TARGET,SOURCE,FSTYPE,FSROOT,OPTIONS"])
    try:
        mounts = list(walk_mounts(json.loads(output).get("filesystems", []))) if code == 0 else []
    except (ValueError, AttributeError):
        mounts = []
    overrides = [item.get("target", "") for item in mounts if application_override_mount(item)]
    check("baked application files have no bind overrides", code == 0 and not overrides,
          ", ".join(overrides) or error)
    code, output, _ = command(["systemctl", "is-active", "marwanos-bench-fixes.service"])
    check("bench bind service inactive", code != 0 and output in ("inactive", "unknown", "failed"), output)
    for unit in ["greetd.service", "marwanos-windows.service", "marwanos-update.service"]:
        code, output, error = command(["systemctl", "is-active", unit])
        check(unit + " active", code == 0 and output == "active", output or error)
        image_unit(["systemctl"], unit, "/usr/lib/systemd/system")
    user_prefix = ["runuser", "-u", "player", "--", "env", f"XDG_RUNTIME_DIR={runtime}",
                   f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime}/bus", "systemctl", "--user"]
    for unit in ["marwanos-metadata.service", "marwanos-audio.service", "marwanos-achievements.service", "marwanos-bluetooth.service", "marwanos-notifications.service"]:
        code, output, error = command([*user_prefix, "is-active", unit])
        check(unit + " active", code == 0 and output == "active", output or error)
        image_unit(user_prefix, unit, "/usr/lib/systemd/user")
        code, output, error = command([*user_prefix, "show", unit, "--property=ExecStart", "--value"])
        check(unit + " executes image payload", code == 0 and "/usr/lib/marwanos/" in output and "/var/marwanos/" not in output,
              "override or missing payload" if code != 0 or "/var/marwanos/" in output else "")
    image_session_processes(player.pw_uid)
    for prefix, label in [(["systemctl"], "system"), (user_prefix, "player")]:
        code, output, error = command([*prefix, "--failed", "--no-legend", "--no-pager"])
        check(label + " has no failed units", code == 0 and not output, output or error)
    code, output, error = command(["getenforce"])
    check("SELinux remains enforcing", code == 0 and output == "Enforcing", output or error)
    # Audit records can arrive through journald's audit transport rather than
    # the kernel transport. A kernel-only query missed a real Plymouth denial.
    denied = journal_messages(["--grep=avc:.*denied"])
    enforcing_denials = [message for message in denied if not re.search(r"\bpermissive=1\b", message)]
    check("full boot journal has no enforcing SELinux denial", not enforcing_denials,
          " | ".join(enforcing_denials)[:1800])
    cores = journal_messages(["COREDUMP_EXE=/usr/bin/gamescope"])
    faults = journal_messages([r"--grep=gamescope[^\n]*(segfault|dumped core)|Process [0-9]+ \(gamescope[^)]*\).*dumped core"])
    check("current boot has no gamescope SIGSEGV or core", not cores and not faults,
          " | ".join(faults)[:1000])
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
    print("INFO: Audio enumeration does not certify audible output, recording or saved-choice recovery.")
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
    if game_id.startswith("managed."):
        installed = read_json(home / ".local/share/marwanos/windows/apps" / (game_id.removeprefix("managed.") + ".json"))
        check("reference Windows game retains native controller profile",
              installed.get("state") == "installed" and installed.get("input_mode") in ("", "gamepad")
              and isinstance(installed.get("executable"), str) and Path(installed["executable"]).is_file())
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
            physical = (event / "device/phys").read_text().strip()
            if physical.startswith("pc1/application/slot"):
                virtual.append(physical)
        except OSError:
            pass
    remembered_names = {f"pc1/application/slot{index + 1}"
                        for index, identity in enumerate(identities if valid_slots else []) if identity}
    check("connected application pads use remembered player slots",
          "pc1/application/slot1" in virtual and len(virtual) == len(set(virtual))
          and set(virtual).issubset(remembered_names), ", ".join(virtual))
    print("INFO: This read-only software gate does not certify physical sound, rumble, multiplayer, suspend/wake or cold power-on.")


try:
    main()
except Exception as error:
    check("validation completed", False, type(error).__name__ + ": " + str(error))
print(f"Postboot software checks: {len(failures)} failure(s)")
sys.exit(1 if failures else 0)
PY
