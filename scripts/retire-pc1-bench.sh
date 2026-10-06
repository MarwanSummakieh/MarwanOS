#!/usr/bin/env bash
# Preview by default. Apply only immediately before an approved candidate reboot.
set -euo pipefail
apply=0
if [[ "${1:-}" == --apply ]]; then apply=1; shift; fi
[[ $# == 1 && "$1" =~ ^[a-f0-9]{7,40}$ ]] || {
    echo 'Usage: retire-pc1-bench.sh [--apply] BAKED_COMMIT' >&2; exit 2;
}
expected="$1"
test "$(id -u)" = 0
staged="$(rpm-ostree status --json | python3 -c 'import json,sys; print(next((d["checksum"] for d in json.load(sys.stdin)["deployments"] if d.get("staged")), ""))')"
[[ "$staged" =~ ^[a-f0-9]{64}$ ]] || { echo 'No staged deployment; nothing changed.' >&2; exit 1; }
root="/sysroot/ostree/deploy/default/deploy/$staged.0"
test -d "$root/usr/lib/marwanos"
grep -qx "MARWANOS_COMMIT=$expected" "$root/usr/share/marwanos/build-info"
for file in shell/marwanos-shell shell/libmowser.so controller/router.py windows/manager.py windows/download_flow.py audio/manager.py metadata/manager.py achievements/manager.py bluetooth/manager.py notifications/server.py appscan; do
    test -s "$root/usr/lib/marwanos/$file" || { echo "Candidate lacks $file" >&2; exit 1; }
done
for service in audio metadata achievements bluetooth notifications; do
    test -f "$root/usr/lib/systemd/user/marwanos-$service.service"
    test -L "$root/usr/lib/systemd/user/default.target.wants/marwanos-$service.service"
done
if pgrep -u player -f 'TEKKEN 8.exe|TekkenGame|setup.exe|FDM.exe|manager.py (launch|guided|setup)' >/dev/null; then
    echo 'An application or installer is running; nothing changed.' >&2; exit 1
fi
userdir=/var/home/player/.config/systemd/user
for directory in "$userdir" /etc/systemd/user; do
    for service in audio metadata achievements bluetooth notifications; do
        file="$directory/marwanos-$service.service"
        if test -e "$file" || test -L "$file"; then
            test ! -L "$file"
            grep -q '/var/marwanos/' "$file" || { echo "Unrecognized $file override" >&2; exit 1; }
        fi
    done
done
printf 'Verified staged %s, baked commit %s.\n' "$staged" "$expected"
echo 'Plan: back up/disable bench bind units; retire development flag and five bench user overrides.'
echo 'Current services and mounts stay running until reboot. Games, profiles, artwork and history stay in place.'
if [[ "$apply" == 0 ]]; then
    echo 'Preview complete; nothing changed.'; exit 0
fi
backup="/var/marwanos/candidate-boot-backup-$expected"
test ! -e "$backup" && test ! -L "$backup"
install -d -m 0700 "$backup/system" "$backup/user" "$backup/etc-user"
for service in marwanos-bench-fixes marwanos-app-icons; do
    if test -f "/etc/systemd/system/$service.service"; then
        cp -a "/etc/systemd/system/$service.service" "$backup/system/"
        systemctl is-enabled "$service.service" > "$backup/system/$service.enabled" || true
        systemctl disable "$service.service"
    fi
done
if test -e /var/marwanos/devmode; then mv /var/marwanos/devmode "$backup/devmode"; fi
for location in user etc-user; do
    directory="$userdir"
    if [[ "$location" == etc-user ]]; then directory=/etc/systemd/user; fi
    for service in audio metadata achievements bluetooth notifications; do
        file="$directory/marwanos-$service.service"
        if test -e "$file"; then mv "$file" "$backup/$location/"; fi
        link="$directory/default.target.wants/marwanos-$service.service"
        if test -L "$link"; then mv "$link" "$backup/$location/$service.wants"; fi
    done
done
printf 'Bench configuration saved in %s. Candidate is ready for the approved reboot.\n' "$backup"
