#!/usr/bin/env python3
"""Stage bbport 0.4 on the bench; --activate selects it for the existing game card.

Run as root with Bloodborne closed. Uses the already installed CUSA03173 and
1.09 update; downloads only the open-source runtime. Never overwrites native
saves on subsequent runs. The shadPS4 launcher remains available for rollback.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path('/var/home/player/.local/share/marwanos/bloodborne')
VERSION = '0.4'
SHA256 = 'b279fe5cd39651ce374d065a84de7dfacd5dda703874effc8c2d35f3fccc754c'
URL = ('https://github.com/deadinside28/bloodborne_pc/releases/download/0.4/'
       'Bloodborne-bbport-x86_64.AppImage')


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--activate', action='store_true')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('run as root on the MarwanOS bench')
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            # AppImage uses a private mount namespace: its executable target
            # need not exist in the host namespace, although /proc can name it.
            executable = Path(os.readlink(proc / 'exe')).name.removesuffix(' (deleted)')
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if executable in ('shadps4', 'bb-probe'):
            parser.error('save and close Bloodborne before changing its runtime')

    base, update = ROOT / 'games/CUSA03173', ROOT / 'games/CUSA03173-patch'
    for game in (base, update):
        if not (game / 'eboot.bin').is_file():
            parser.error(f'missing installed game executable: {game}')
    for name in ('libc.prx', 'libSceFios2.prx'):
        if not (base / 'sce_module' / name).is_file():
            parser.error(f'missing bundled game module: {name}')

    data = ROOT / 'bbport'
    data.mkdir(exist_ok=True)
    runtime = ROOT / 'runtime' / f'bbport-{VERSION}' / 'Bloodborne-bbport-x86_64.AppImage'
    runtime.parent.mkdir(parents=True, exist_ok=True)
    if not runtime.exists():
        partial = runtime.with_suffix('.partial')
        urllib.request.urlretrieve(URL, partial)
        if digest(partial) != SHA256:
            raise RuntimeError('native runtime release checksum mismatch')
        partial.replace(runtime)
    if digest(runtime) != SHA256:
        raise RuntimeError('cached native runtime checksum mismatch')
    runtime.chmod(0o755)

    game = data / 'game'
    marker = data / 'merged-game.json'
    expected = {'base_eboot_sha256': digest(base / 'eboot.bin'),
                'update_eboot_sha256': digest(update / 'eboot.bin')}
    if not marker.exists() or json.loads(marker.read_text()) != expected:
        game.mkdir(exist_ok=True)
        # These are independent copies. Reflinks are optional; hard links could
        # allow later writes in the port view to change the original game.
        with (data / 'copy.log').open('w') as log:
            for source in (base, update):
                subprocess.run(['cp', '--reflink=auto', '--remove-destination', '-a',
                                str(source) + '/.', str(game)], check=True,
                               stdout=log, stderr=log)
        marker.write_text(json.dumps(expected, indent=2) + '\n')
    if digest(game / 'eboot.bin') != expected['update_eboot_sha256']:
        raise RuntimeError('merged executable does not match the installed update')

    backup = ROOT / 'backups' / ('before-bbport-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    backup.mkdir(parents=True)
    for path in (ROOT / 'launch', ROOT / 'launch-bbport', data / 'bbport.ini'):
        if path.exists():
            shutil.copy2(path, backup / path.name)
    native_save = data / 'user/savedata/1'
    old_save = ROOT / 'user/home/1000/savedata'
    if not native_save.exists() and old_save.exists():
        shutil.copytree(old_save, backup / 'savedata')
        shutil.copytree(old_save, native_save)

    config = Path('/var/home/player/.config/bbport-launcher')
    config.mkdir(parents=True, exist_ok=True)
    settings = config / 'settings.json'
    if settings.exists():
        shutil.copy2(settings, backup / 'launcher-settings.json')
    settings.write_text(json.dumps({
        'game_dir': str(game), 'user_dir': str(data / 'user'), 'ui_language': 'en',
        'fullscreen': True, 'present_mode': 'Immediate', 'fps_mode': 'uncap',
        'fps_limit': 120, 'draw_pipe': '1', 'pc_model': False,
        'frame_stats': False, 'save_log': False,
    }, indent=2) + '\n')
    (data / 'bbport.ini').write_text(
        'menu_language=en\nupscaler=fsr3\npreset=2\noutput_res=2560x1440\n'
        'live_resolution=0\nsharpen=1\nsharpness=0.50\nobject_motion=1\n'
        'show_fps=0\neffect_motion_blur=0\neffect_ssao=0\n'
        'effect_chromatic_aberration=0\nmodel_lod=0\n')
    patches = data / 'patches'
    patches.mkdir(exist_ok=True)
    xml = ET.Element('Patch')
    ET.SubElement(xml, 'ID').text = 'CUSA03173'
    metadata = ET.SubElement(xml, 'Metadata', {
        'Title': 'Bloodborne', 'Name': 'MarwanOS ultrawide camera aspect',
        'AppVer': '01.09', 'AppElf': 'eboot.bin', 'isEnabled': 'true',
        'Author': 'Kyo; MarwanOS display ratio adjustment',
        'Note': 'Camera aspect address from the official 21:9 patch; native renderer handles scene/UI sizes.',
    })
    ET.SubElement(ET.SubElement(metadata, 'PatchList'), 'Line', {
        'Type': 'float32', 'Address': '0x0183A35D', 'Value': str(3440 / 1440),
    })
    ET.indent(xml)
    ET.ElementTree(xml).write(patches / 'marwanos-ultrawide.xml', encoding='unicode', xml_declaration=True)
    native_launch = ROOT / 'launch-bbport'
    native_launch.write_text(
        '#!/usr/bin/env bash\nset -euo pipefail\n'
        f'root={ROOT}\ncd "$root"\n'
        'export APPIMAGE_EXTRACT_AND_RUN=1 NO_CLEANUP=1\n'
        'export BB_RENDER_RES=1720x720 BB_OUTPUT_RES=3440x1440\n'
        'export TMPDIR="$HOME/.cache" BB_DATA_DIR="$root/bbport"\n'
        f'exec "$root/runtime/bbport-{VERSION}/Bloodborne-bbport-x86_64.AppImage" --play '
        '> "$root/bbport-launch.log" 2>&1\n')
    native_launch.chmod(0o755)
    if args.activate:
        previous = ROOT / 'launch-shadps4'
        if not previous.exists():
            shutil.copy2(ROOT / 'launch', previous)
        (ROOT / 'launch').write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            f'root={ROOT}\n'
            'exec flock -n "$root/bloodborne.lock" "$root/launch-bbport" "$@"\n')
        (ROOT / 'launch').chmod(0o755)
    subprocess.run(['chown', '-R', 'player:player', str(data), str(config),
                    str(runtime.parent), str(backup), str(native_launch)], check=True)
    player = pwd.getpwnam('player')
    if args.activate:
        os.chown(ROOT / 'launch', player.pw_uid, player.pw_gid)
        os.chown(ROOT / 'launch-shadps4', player.pw_uid, player.pw_gid)
    print(json.dumps({'runtime': VERSION, 'sha256': SHA256, 'backup': str(backup),
                      'active': args.activate, 'gameplay_verified': False}, indent=2))


if __name__ == '__main__':
    main()
