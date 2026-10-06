#!/usr/bin/env bash
# Restore the recorded working bench configuration before an approved rollback.
set -euo pipefail
[[ $# == 1 && "$1" =~ ^[a-f0-9]{7,40}$ ]] || {
    echo 'Usage: restore-pc1-bench.sh BAKED_COMMIT' >&2; exit 2;
}
test "$(id -u)" = 0
backup="/var/marwanos/candidate-boot-backup-$1"
test -d "$backup/user"
userdir=/var/home/player/.config/systemd/user
mkdir -p "$userdir/default.target.wants"
for location in user etc-user; do
    directory="$userdir"
    if [[ "$location" == etc-user ]]; then directory=/etc/systemd/user; fi
    for service in audio metadata achievements bluetooth notifications; do
        source="$backup/$location/marwanos-$service.service"
        if test -f "$source"; then mkdir -p "$directory"; cp -a "$source" "$directory/"; fi
        source="$backup/$location/$service.wants"
        if test -L "$source"; then
            mkdir -p "$directory/default.target.wants"
            cp -a "$source" "$directory/default.target.wants/marwanos-$service.service"
        fi
    done
done
if test -f "$backup/devmode"; then cp -a "$backup/devmode" /var/marwanos/devmode; fi
for service in marwanos-bench-fixes marwanos-app-icons; do
    if test -f "$backup/system/$service.service"; then
        cp -a "$backup/system/$service.service" /etc/systemd/system/
        if grep -qx enabled "$backup/system/$service.enabled"; then systemctl enable "$service.service"; fi
    fi
done
echo 'Working bench configuration restored. No image switch or reboot performed.'
