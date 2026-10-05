#!/usr/bin/env bash
set -euo pipefail
test "$(id -u)" = 0
stage=/var/tmp/fdm-notifications-20261005
target=/var/marwanos/notifications-20261005
shell=/var/marwanos/controller-setup-20261005/marwanos-shell
app=/var/home/player/.local/share/marwanos/portable/fdm-controller-20261005
test -s "$stage/server.py"
test -s "$stage/marwanos-shell"
test -s "$stage/FDM.exe"
test ! -e "$shell.before-notifications"
test ! -e "$app/FDM.before-controller-only.exe"
chmod 0755 "$stage/marwanos-shell"
runuser -u player -- env MARWANOS_MOWSER_ROOT=/usr/lib/marwanos/mowser \
    LD_LIBRARY_PATH=/usr/lib/marwanos/mowser XDG_RUNTIME_DIR=/run/user/1000 \
    "$stage/marwanos-shell" --headless --audio-driver Dummy --quit-after 4 \
    > "$stage/shell-preflight.log" 2>&1
! grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource' "$stage/shell-preflight.log"
grep -q 'home rail ready' "$stage/shell-preflight.log"
install -d -m 0755 "$target" /etc/systemd/user
install -m 0644 "$stage/server.py" "$target/server.py"
python3 -m py_compile "$target/server.py"
sed "s@/usr/lib/marwanos/notifications/server.py@$target/server.py@" \
    "$stage/marwanos-notifications.service" > /etc/systemd/user/marwanos-notifications.service
systemctl --global enable marwanos-notifications.service
runuser -u player -- env XDG_RUNTIME_DIR=/run/user/1000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus systemctl --user daemon-reload
runuser -u player -- env XDG_RUNTIME_DIR=/run/user/1000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus systemctl --user start marwanos-notifications.service
runuser -u player -- python3 - <<'PY'
import json
from pathlib import Path
path=Path('/var/home/player/.local/share/marwanos/windows/apps/local-fdm-controller-20261005.json')
entry=json.loads(path.read_text())
entry['exec'].insert(3, 'FDM_NOTIFICATION_DIR=Z:\\var\\home\\player\\.local\\share\\marwanos\\notification-events')
temporary=path.with_suffix('.tmp')
temporary.write_text(json.dumps(entry,indent=2))
temporary.replace(path)
PY
systemctl stop fdm-controller-validation-20261005.service
cp -a "$app/FDM.exe" "$app/FDM.before-controller-only.exe"
install -o player -g player -m 0644 "$stage/FDM.exe" "$app/FDM.exe"
cp -a "$shell" "$shell.before-notifications"
install -m 0755 "$stage/marwanos-shell" "$shell.new"
chcon --reference="$shell" "$shell.new"
mv "$shell.new" "$shell"
umount -l /usr/lib/marwanos/shell/marwanos-shell
mount --bind "$shell" /usr/lib/marwanos/shell/marwanos-shell
pkill -TERM -u player -f '^/usr/lib/marwanos/shell/marwanos-shell$'
systemd-run --unit=fdm-controller-validation-20261005 --uid=player \
    --working-directory="$app" --setenv=HOME=/var/home/player --setenv=DISPLAY=:0 \
    --setenv=XDG_RUNTIME_DIR=/run/user/1000 \
    --setenv=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    --setenv=FDM_CONTROLLER_PORTABLE=1 --setenv=FDM_CONTROLLER_UI=1 \
    --setenv='FDM_DOWNLOAD_DIR=Z:\var\home\player\Downloads\' \
    --setenv='FDM_NOTIFICATION_DIR=Z:\var\home\player\.local\share\marwanos\notification-events' \
    /usr/lib/marwanos/windows/manager.py launch local-fdm-controller-20261005
sha256sum "$app/FDM.exe" "$app/fdmbtsupp.dll"
