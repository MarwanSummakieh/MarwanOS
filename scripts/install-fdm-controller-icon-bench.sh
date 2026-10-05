#!/usr/bin/env bash
# Install the requested custom artwork without interrupting the application.
set -euo pipefail
test "$(id -u)" = 0
stage=/var/tmp/fdm-controller-icon-20261005.png
app=/var/home/player/.local/share/marwanos/portable/fdm-controller-20261005
manifest=/var/home/player/.local/share/marwanos/windows/apps/local-fdm-controller-20261005.json
test -s "$stage"
test -s "$app/FDM.exe"
test -s "$manifest"
python3 - "$stage" <<'PY'
import sys
from PIL import Image
with Image.open(sys.argv[1]) as image:
    image.verify()
with Image.open(sys.argv[1]) as image:
    assert image.format == 'PNG' and image.mode == 'RGBA'
    assert image.width == image.height and image.width <= 4096
    assert image.getchannel('A').getextrema()[0] == 0
    print('Verified transparent PNG:', image.size)
PY
if test ! -e "$manifest.before-icon-20261005"; then
    cp -a "$manifest" "$manifest.before-icon-20261005"
fi
install -o player -g player -m 0644 "$stage" "$app/icon.png"
runuser -u player -- python3 - <<'PY'
import json
from pathlib import Path
manifest=Path('/var/home/player/.local/share/marwanos/windows/apps/local-fdm-controller-20261005.json')
entry=json.loads(manifest.read_text())
entry['icon']='/var/home/player/.local/share/marwanos/portable/fdm-controller-20261005/icon.png'
temporary=manifest.with_suffix('.tmp')
with temporary.open('w') as stream:
    import os
    os.chmod(temporary,0o600)
    json.dump(entry,stream,indent=2)
temporary.replace(manifest)
print('Updated FDM Controller artwork')
PY
sha256sum "$app/icon.png"
