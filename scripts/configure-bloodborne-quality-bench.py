#!/usr/bin/env python3
"""Configure Bloodborne for ultrawide output and the owner's frame-rate priority."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import pwd
import subprocess
import struct
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path('/var/home/player/.local/share/marwanos/bloodborne')
REVISION = '5f832e266a9c091b8303f8f1fcf1d4633e57539f'
URL = f'https://raw.githubusercontent.com/shadps4-emu/ps4_cheats/{REVISION}/PATCHES/Bloodborne.xml'
SHA256 = 'c48a4173ca9c1a2c8c3a120b334dbc05898eb05e219a6f7b3cbe576036f210a2'
NAMES = (
    'Resolution Patch 3440x1440 (21:9)',
    'Better AA',
    'Enable Screen Space Reflections (READ NOTE)',
    'Model LOD -2 (Highest model detail)',
    '90 FPS++',
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=('performance', 'native'), default='performance')
    args = parser.parse_args()
    performance = args.profile == 'performance'
    names = tuple(name for name in NAMES if not performance or name not in (
        'Enable Screen Space Reflections (READ NOTE)', 'Better AA', 'Model LOD -2 (Highest model detail)'))
    if performance:
        names = tuple(name.replace('3440x1440', '2560x1080') for name in names) + (
            'Disable Motion Blur (Perf Increase)', 'Disable SSAO')
    if os.geteuid() != 0:
        raise RuntimeError('run as root on the bench')
    running = subprocess.run(
        ['pgrep', '-u', 'player', '-f', '/usr/bin/shadps4|/runtime/0.19.0/Shadps4-sdl.AppImage'],
        capture_output=True,
    )
    if running.returncode == 0:
        raise RuntimeError('close Bloodborne before changing its profile')
    player = pwd.getpwnam('player')
    config_path = ROOT / 'user/config.json'
    config = json.loads(config_path.read_text())
    original_launcher = (ROOT / 'launch').read_text()
    if '--fullscreen true' not in original_launcher:
        raise RuntimeError('unexpected launcher; inspect before replacing')
    with urllib.request.urlopen(URL, timeout=30) as response:
        source = response.read()
    if hashlib.sha256(source).hexdigest() != SHA256:
        raise RuntimeError('pinned upstream patch checksum mismatch')
    upstream = ET.fromstring(source)
    selected = ET.Element('Patch')
    selected.append(copy.deepcopy(upstream.find('TitleID')))
    written = {}
    for name in names:
        matches = [m for m in upstream.findall('Metadata')
                   if m.get('Name') == name and m.get('AppVer') == '01.09'
                   and m.get('AppElf') == 'eboot.bin']
        if len(matches) != 1:
            raise RuntimeError(f'expected one version-matched patch: {name}')
        metadata = copy.deepcopy(matches[0])
        if performance and name.startswith('Resolution Patch'):
            # Scale the official 2560x1080 patch uniformly to 1920x810. Preserve
            # its 64:27 aspect/FOV and lock-on fixes, scaling render dimensions
            # and UI coordinates together rather than stretching a 16:9 image.
            width, height = 1920, 810
            for line in metadata.findall('PatchList/Line'):
                value = line.get('Value')
                if line.get('Type') == 'bytes32':
                    integer = int(value, 0)
                    opcode = integer & 255
                    if opcode in (0xb8, 0xb9, 0xbe) and integer >> 8 in (2560, 1080):
                        dimension = width if integer >> 8 == 2560 else height
                        line.set('Value', hex((dimension << 8) | opcode))
                    elif int(line.get('Address'), 16) in (0x04D26EA4, 0x04D26EA8):
                        dimension = width if int(line.get('Address'), 16) == 0x04D26EA4 else height
                        line.set('Value', hex(struct.unpack('<I', struct.pack('<f', dimension))[0]))
                    elif int(line.get('Address'), 16) in (0x04CF9A00, 0x04CF9A60, 0x04CF9AD0,
                                                        0x04CF9A10, 0x04CF9A70, 0x04CF9AE0):
                        old_float = struct.unpack('<f', struct.pack('<I', integer))[0]
                        line.set('Value', hex(struct.unpack('<I', struct.pack('<f', old_float * 0.75))[0]))
                elif int(line.get('Address'), 16) == 0x02594AA6:
                    if value.count('000A0000') != 1 or value.count('38040000') != 1:
                        raise RuntimeError('unexpected upstream HUD coordinate patch')
                    line.set('Value', value.replace('000A0000', '80070000').replace('38040000', '2A030000'))
            metadata.set('Name', 'Resolution Patch 1920x810 (21:9; derived)')
        metadata.set('isEnabled', 'true')
        for line in metadata.findall('PatchList/Line'):
            kind, value = line.get('Type'), line.get('Value')
            if kind == 'bytes':
                data = bytes.fromhex(value)
            elif kind in ('bytes16', 'bytes32', 'bytes64'):
                data = int(value, 0).to_bytes(int(kind[5:]) // 8, 'little')
            else:
                raise RuntimeError(f'unhandled patch type: {kind}')
            address = int(line.get('Address'), 16)
            for offset, byte in enumerate(data):
                key = address + offset
                if key in written and written[key][0] != name and written[key][1] != byte:
                    raise RuntimeError(f'conflicting patch byte: {key:#x}')
                written[key] = (name, byte)
        selected.append(metadata)
    ET.indent(selected)
    patch_content = ET.tostring(selected, encoding='unicode') + '\n'
    patch = ROOT / 'user/patches/bloodborne-quality.xml'
    config['GPU'].update({
        'internal_screen_width': 1920 if performance else 3440,
        'internal_screen_height': 810 if performance else 1440,
        'window_width': 3440, 'window_height': 1440,
        'full_screen': True, 'present_mode': 'Immediate',
        'fsr_enabled': performance, 'rcas_enabled': performance,
        'vblank_frequency': 90,
    })
    config['General'].update({'dev_kit_mode': True, 'extra_dmem_in_mbytes': 4000})
    config['Vulkan']['pipeline_cache_enabled'] = True
    # Use the timing-corrected 90 FPS patch. The upstream uncapped patch warns
    # that Havok breaks above 90 FPS. Resolution
    # requires the binary patch above; changing the output window alone is insufficient.
    launcher = original_launcher.replace(
        'exec "$runtime" --fullscreen true',
        'exec "$runtime" --patch "$root/user/patches/bloodborne-quality.xml" --fullscreen true',
    ) if '--patch ' not in original_launcher else original_launcher
    launcher = launcher.replace('bloodborne-3440x1440-quality.xml', 'bloodborne-quality.xml')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = ROOT / 'backups' / f'before-ultrawide-{stamp}'
    backup.mkdir(parents=True)
    (backup / 'config.json').write_bytes(config_path.read_bytes())
    (backup / 'launch').write_text(original_launcher)
    if patch.exists():
        (backup / patch.name).write_bytes(patch.read_bytes())
    legacy_patch = ROOT / 'user/patches/bloodborne-3440x1440-quality.xml'
    if legacy_patch.exists():
        (backup / legacy_patch.name).write_bytes(legacy_patch.read_bytes())

    def write(path, content, mode=0o644):
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.with_name(path.name + '.new')
        temp.write_text(content)
        temp.chmod(mode)
        os.chown(temp, player.pw_uid, player.pw_gid)
        temp.replace(path)
        os.chown(path.parent, player.pw_uid, player.pw_gid)

    write(patch, patch_content)
    write(config_path, json.dumps(config, indent=2) + '\n')
    write(ROOT / 'launch', launcher, 0o755)
    manifest = {
        'profile': args.profile, 'output_resolution': [3440, 1440], 'fullscreen': True,
        'render_resolution': [1920, 810] if performance else [3440, 1440],
        'fsr': performance,
        'patches': [m.get('Name') for m in selected.findall('Metadata')],
        'source': URL, 'source_sha256': SHA256,
        'patch_sha256': hashlib.sha256(patch_content.encode()).hexdigest(),
        'backup': str(backup), 'applied_at': stamp,
        'target_fps': 90, 'vsync': False, 'extra_dmem_mb': 4000,
        'title_menu_verified': False, 'gameplay_verified': False,
        'hardware_note': 'RTX 3070 8 GB; upstream ultrawide patch recommends at least 12 GB VRAM. World performance unverified.',
    }
    write(ROOT / 'quality-profile.json', json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
