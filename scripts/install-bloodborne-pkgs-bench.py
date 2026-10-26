#!/usr/bin/env python3
"""One-time bench installer for the owner's existing Bloodborne download.

Run as player with --wait to wait for the Downloads service to report completion.
No download is initiated, and no emulator/setup desktop entry is registered.
"""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import time


ROOT = Path('/var/home/player/.local/share/marwanos/bloodborne')
QUEUE = Path('/var/home/player/.local/share/marwanos/downloads/queue.json')
TASK_ID = '5ab3526d0a62d0c9'
TITLE_ID = 'CUSA03173'
PACKAGES = {
    'Bloodborne.Game.of.the.Year.Edition.PS4-PRELUDE.pkg': (31351111680, 101),
    'CUSA03173-EUR-Update-v1.09-PRELUDE-[PS4ID].pkg': (181338112, 102),
}
EXTRACTOR = ROOT / 'tools/pkg-extractor-1.1.AppImage'
EXTRACTOR_SHA256 = 'b360bc691aa3d89071aa707224155f6eade348d314cf7798ac550e31c11a7bcc'
DESKTOP = Path('/var/home/player/.local/share/applications/bloodborne.desktop')
STATUS = ROOT / 'install-status.json'


def write_atomic(path, text):
    temporary = path.with_name(path.name + '.new')
    temporary.write_text(text)
    temporary.replace(path)


def status(state, **details):
    value = {'state': state, 'updated_at': time.time(), 'gameplay_verified': False, **details}
    write_atomic(STATUS, json.dumps(value, indent=2) + '\n')
    print(json.dumps(value), flush=True)


def completed_packages():
    queue = json.loads(QUEUE.read_text())
    task = next((task for task in queue['tasks'] if task['id'] == TASK_ID), None)
    if task is None:
        raise RuntimeError('The Bloodborne download is no longer in the queue')
    if task['status'] == 'error':
        raise RuntimeError('The Bloodborne download reports an error')
    percent = round(100 * task.get('received', 0) / max(task.get('total', 0), 1), 1)
    if task['status'] not in ('complete', 'seeding'):
        return None, percent
    download_root = Path(task['directory']).resolve()
    packages = []
    for name, (expected_size, _) in PACKAGES.items():
        matches = [file for file in task['files'] if Path(file['path']).name == name]
        if len(matches) != 1:
            raise RuntimeError(f'Expected exactly one package: {name}')
        entry = matches[0]
        path = Path(entry['path']).resolve()
        if not path.is_relative_to(download_root):
            raise RuntimeError('Package path escaped its download directory')
        if not entry['selected'] or entry['total'] != expected_size:
            raise RuntimeError('Package selection or expected length changed')
        if entry['received'] != expected_size or not path.is_file() or path.stat().st_size != expected_size:
            return None, percent
        packages.append(path)
    return packages, percent


def read_sfo(path):
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b'\x00PSF':
        raise RuntimeError('Invalid game metadata')
    _, _, keys, values, count = struct.unpack_from('<5I', data)
    if count > 4096 or 20 + count * 16 > len(data):
        raise RuntimeError('Invalid metadata entry table')
    result = {}
    for index in range(count):
        key_offset, fmt, length, maximum, value_offset = struct.unpack_from('<HHIII', data, 20 + index * 16)
        key_start = keys + key_offset
        key_end = data.find(b'\0', key_start)
        start = values + value_offset
        if key_start >= len(data) or key_end < key_start or start + length > len(data):
            raise RuntimeError('Metadata entry out of bounds')
        if fmt == 0x0204:
            result[data[key_start:key_end].decode('utf-8')] = data[start:start + length].rstrip(b'\0').decode('utf-8')
    return result


def extract(package, staging, label):
    env = {**os.environ, 'APPIMAGE_EXTRACT_AND_RUN': '1'}
    check = subprocess.run([str(EXTRACTOR), str(package), '--check-type'], cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)
    expected_type = PACKAGES[package.name][1]
    if check.returncode != expected_type:
        raise RuntimeError(f'{label}: package type check failed ({check.returncode})')
    log = ROOT / f'extract-{label}.log'
    status(f'extracting-{label}')
    with log.open('w') as output:
        result = subprocess.run([str(EXTRACTOR), str(package), str(staging)], cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=14400)
    text = log.read_text(errors='replace')
    extracted = re.findall(r'Extracting file (\d+) of (\d+) to ', text)
    if result.returncode or 'Cannot ' in text or not extracted or extracted[-1][0] != extracted[-1][1]:
        raise RuntimeError(f'{label}: extraction failed; see {log.name}')


def install(packages):
    if hashlib.sha256(EXTRACTOR.read_bytes()).hexdigest() != EXTRACTOR_SHA256:
        raise RuntimeError('Extractor checksum mismatch')
    staging = ROOT / 'install-staging'
    destination = ROOT / 'games'
    if staging.exists() or destination.exists() or DESKTOP.exists():
        raise RuntimeError('Installation output already exists; inspect it before retrying')
    # Leave room for the unpacked base game, patch, and temporary metadata.
    needed = sum(path.stat().st_size for path in packages) * 2 + 4 * 1024**3
    if shutil.disk_usage(ROOT).free < needed:
        raise RuntimeError('Insufficient free storage for safe staged extraction')
    staging.mkdir()
    for package, label in zip(packages, ('base', 'update')):
        extract(package, staging, label)
    base = staging / TITLE_ID
    patch = staging / (TITLE_ID + '-patch')
    base_sfo = read_sfo(base / 'sce_sys/param.sfo')
    patch_sfo = read_sfo(patch / 'sce_sys/param.sfo')
    if base_sfo.get('TITLE_ID') != TITLE_ID or patch_sfo.get('TITLE_ID') != TITLE_ID:
        raise RuntimeError('The base game and update title IDs do not match')
    if 'Bloodborne' not in base_sfo.get('TITLE', '') or patch_sfo.get('APP_VER') != '01.09':
        raise RuntimeError('Expected Bloodborne and its 1.09 update')
    for folder in (base, patch):
        executable = folder / 'eboot.bin'
        with executable.open('rb') as stream:
            magic = stream.read(4)
        if magic not in (b'\x7fELF', b'O\x15=\x1d'):
            raise RuntimeError('The game executable format is unsupported')
    staging.rename(destination)
    game = destination / TITLE_ID
    write_atomic(ROOT / 'game-path', str(game) + '\n')
    icon = game / 'sce_sys/icon0.png'
    desktop = f'[Desktop Entry]\nType=Application\nName=Bloodborne\nExec={ROOT}/launch\nTerminal=false\nCategories=Game;\n'
    if icon.is_file():
        desktop += f'Icon={icon}\n'
    write_atomic(DESKTOP, desktop)
    manifest_path = ROOT / 'deployment.json'
    manifest = json.loads(manifest_path.read_text())
    manifest.update(game_path=str(game), game_version='01.09', card_exists=True, gameplay_verified=False)
    write_atomic(manifest_path, json.dumps(manifest, indent=2) + '\n')
    status('installed-awaiting-gameplay-check', game_path=str(game), game_version='01.09', card_exists=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wait', action='store_true')
    args = parser.parse_args()
    if os.geteuid() != 1000:
        parser.error('run as the bench player, never as root')
    lock = (ROOT / 'install.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    if STATUS.exists():
        previous = json.loads(STATUS.read_text())
        if previous.get('state') == 'installed-awaiting-gameplay-check':
            game = ROOT / 'games' / TITLE_ID
            if (game / 'eboot.bin').is_file() and DESKTOP.exists():
                print('Bloodborne is already installed; gameplay check remains pending.', flush=True)
                return
    last_percent = None
    try:
        while True:
            packages, percent = completed_packages()
            if packages:
                install(packages)
                return
            if percent != last_percent:
                status('waiting-for-download', percent=percent, card_exists=False)
                last_percent = percent
            if not args.wait:
                return
            time.sleep(30)
    except Exception as exc:
        status('failed', error=str(exc), card_exists=DESKTOP.exists())
        raise


if __name__ == '__main__':
    main()
