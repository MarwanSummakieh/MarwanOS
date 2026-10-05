#!/usr/bin/env bash
# Stage the locally built FDM controller fork on the existing development bench.
set -euo pipefail
test "$(id -u)" = 0
package=/var/tmp/fdm-controller-bench.tar.gz
target=/var/home/player/.local/share/marwanos/portable/fdm-controller-20261005
base=/var/home/player/.local/share/marwanos/windows
key=local-fdm-controller-20261005
test -s "$package"
test ! -e "$target"
test ! -e "$base/prefixes/$key"
test ! -e "$base/apps/$key.json"
install -d -o player -g player -m 0755 "$target"
tar -xzf "$package" -C "$target" --no-same-owner
chown -R player:player "$target"
test -s "$target/FDM.exe"
test -s "$target/fdmbtsupp.dll"
test -s "$target/Language/eng.lng"
runuser -u player -- python3 - <<'PY'
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location('manager', '/usr/lib/marwanos/windows/manager.py')
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)
base = Path('/var/home/player/.local/share/marwanos/windows')
key = 'local-fdm-controller-20261005'
exe = Path('/var/home/player/.local/share/marwanos/portable/fdm-controller-20261005/FDM.exe')
prefix = base / 'prefixes' / key
prefix.mkdir(mode=0o700)
helper = '/usr/lib/marwanos/windows/manager.py'
entry = {'id': 'managed.' + key, 'recipe_id': key, 'title': 'FDM Controller',
         'prefix': str(prefix), 'executable': str(exe), 'portable': True,
         'input_mode': '', 'state': 'installed', 'subtitle': 'Controller download manager',
         'icon': str(exe.parent / 'icon.png') if (exe.parent / 'icon.png').is_file()
                 else manager.application_icon(base, key, exe),
         'exec': ['/usr/bin/env', 'FDM_CONTROLLER_PORTABLE=1', 'FDM_CONTROLLER_UI=1',
                  'FDM_NOTIFICATION_DIR=Z:\\var\\home\\player\\.local\\share\\marwanos\\notification-events',
                  'FDM_DOWNLOAD_DIR=Z:\\var\\home\\player\\Downloads\\', helper, 'launch', key],
         'stop_exec': [helper, 'stop', key]}
manager.atomic_json(base / 'apps' / (key + '.json'), entry)
print('Registered', entry['title'], 'with direct controller input')
PY
sha256sum "$target/FDM.exe" "$target/fdmbtsupp.dll"
