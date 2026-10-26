#!/usr/bin/env python3
"""Prepare a hidden, pinned shadPS4 runtime; optionally register Bloodborne.

Run as root on the MarwanOS bench. The game is supplied separately:
    python3 prepare-bloodborne-bench.py --game /path/to/CUSAxxxxx
Without --game, no home card is created. No game or PS4 firmware is downloaded.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import subprocess
import urllib.request
import zipfile


VERSION = "0.19.0"
SHA256 = "a6e3b83fd6c9ea7b29c37e77e1aa687802d4ecd98c2ea794ca9e1d97b24a0cf9"
URL = f"https://github.com/shadps4-emu/shadPS4/releases/download/v.{VERSION}/shadps4-linux-sdl-{VERSION}.zip"
ROOT = Path("/var/home/player/.local/share/marwanos/bloodborne")
DESKTOP = Path("/var/home/player/.local/share/applications/bloodborne.desktop")


def write_owned(path, content, player, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".new")
    temporary.write_text(content)
    temporary.chmod(mode)
    os.chown(temporary, player.pw_uid, player.pw_gid)
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path)
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("run as root on the MarwanOS bench")
    game = args.game.resolve() if args.game else None
    if game:
        if not (game / "eboot.bin").is_file() or not (game / "sce_sys/param.sfo").is_file():
            parser.error("game folder must contain eboot.bin and sce_sys/param.sfo")
        if b"Bloodborne" not in (game / "sce_sys/param.sfo").read_bytes():
            parser.error("the supplied folder does not identify Bloodborne")

    player = pwd.getpwnam("player")
    staging = Path("/var/tmp/pc1-bloodborne-20261010")
    staging.mkdir(exist_ok=True)
    archive = staging / f"shadps4-linux-sdl-{VERSION}.zip"
    if not archive.exists():
        temporary = archive.with_suffix(".partial")
        urllib.request.urlretrieve(URL, temporary)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != SHA256:
            raise RuntimeError("official release checksum mismatch")
        temporary.replace(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise RuntimeError("cached release checksum mismatch")

    runtime = ROOT / "runtime" / VERSION
    runtime.mkdir(parents=True, exist_ok=True)
    executable = runtime / "Shadps4-sdl.AppImage"
    with zipfile.ZipFile(archive) as bundle:
        if bundle.namelist() != ["Shadps4-sdl.AppImage"]:
            raise RuntimeError("unexpected archive layout")
        payload = bundle.read("Shadps4-sdl.AppImage")
    if executable.exists() and executable.read_bytes() != payload:
        raise RuntimeError("existing runtime differs; preserve and inspect it first")
    if not executable.exists():
        executable.write_bytes(payload)
    executable.chmod(0o755)
    (ROOT / "user").mkdir(exist_ok=True)
    # A fresh portable profile has no previous saves to migrate. Precreate its
    # home so shadPS4's first-run migration dialog does not cover the console.
    for directory in ('savedata', 'trophy', 'inputs'):
        (ROOT / 'user' / 'home' / '1000' / directory).mkdir(parents=True, exist_ok=True)

    launcher = f'''#!/usr/bin/env bash
set -euo pipefail
root={ROOT}
cd "$root"
runtime="$root/runtime/{VERSION}/Shadps4-sdl.AppImage"
export APPIMAGE_EXTRACT_AND_RUN=1
if [[ "${{1:-}}" == --check-runtime ]]; then
    exec "$runtime" --help
fi
[[ -r "$root/game-path" ]] || exit 66
IFS= read -r game < "$root/game-path"
[[ -f "$game/eboot.bin" ]] || exit 66
patch_args=()
if [[ -f "$root/user/patches/bloodborne-quality.xml" ]]; then
    patch_args=(--patch "$root/user/patches/bloodborne-quality.xml")
elif [[ -f "$root/user/patches/bloodborne-3440x1440-quality.xml" ]]; then
    patch_args=(--patch "$root/user/patches/bloodborne-3440x1440-quality.xml")
fi
exec "$runtime" "${{patch_args[@]}}" --fullscreen true "$game/eboot.bin" > "$root/launch.log" 2>&1
'''
    write_owned(ROOT / "launch", launcher, player, 0o755)
    for directory, dirs, files in os.walk(ROOT):
        os.chown(directory, player.pw_uid, player.pw_gid)
        for name in files:
            path = Path(directory) / name
            if not path.is_symlink():
                os.chown(path, player.pw_uid, player.pw_gid)

    check = subprocess.run(
        ["runuser", "-u", "player", "--", "env", "HOME=/var/home/player", str(ROOT / "launch"), "--check-runtime"],
        cwd=ROOT, capture_output=True, text=True, timeout=30, check=True,
    )
    if "Emulator CLI" not in check.stdout:
        raise RuntimeError("emulator CLI preflight did not succeed")
    write_owned(staging / "runtime-help.txt", check.stdout, player)

    if game:
        accessible = subprocess.run(["runuser", "-u", "player", "--", "test", "-r", str(game / "eboot.bin")])
        if accessible.returncode:
            raise RuntimeError("player cannot read the supplied game")
        write_owned(ROOT / "game-path", str(game) + "\n", player)
        icon = game / "sce_sys/icon0.png"
        desktop = f"[Desktop Entry]\nType=Application\nName=Bloodborne\nExec={ROOT}/launch\nTerminal=false\nCategories=Game;\n"
        if icon.is_file():
            desktop += f"Icon={icon}\n"
        if DESKTOP.exists() and DESKTOP.read_text() != desktop:
            raise RuntimeError("existing Bloodborne shortcut differs; preserve and inspect it first")
        write_owned(DESKTOP, desktop, player)

    manifest = {
        "runtime_version": VERSION, "archive_sha256": SHA256, "source": URL,
        "runtime_preflight": "passed", "game_path": str(game) if game else None,
        "gameplay_verified": False, "card_exists": DESKTOP.exists(),
    }
    write_owned(ROOT / "deployment.json", json.dumps(manifest, indent=2) + "\n", player)
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
