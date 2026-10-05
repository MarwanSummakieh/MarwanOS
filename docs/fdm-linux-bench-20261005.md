# Linux FDM on the PC1 bench — 2026-10-05

The bench at `192.168.50.206` now runs Linux Free Download Manager from Flathub,
app ID `org.freedownloadmanager.Manager`. The installed commit is
`2f8fd9fa7e778c9bbf3ba8049d3d08a51c638afd8c1568c0d8a371d038b95c50`;
its commit subject records FDM 6.35.1.7021, although its AppStream version still
reports 6.34.2.6926. The runtime is `org.freedesktop.Platform/x86_64/25.08`.

Downloads go to `/var/home/player/Downloads`, on `/dev/nvme1n1p1`, the 477 GB
main storage drive. At verification, `df` reported 442 GiB available. The
player's persistent Flatpak override grants that exact path and sets
`QT_QPA_PLATFORM=xcb` for the gamescope XWayland session. Other home directories
and removable drives were not added to the override.

The Windows manager removed app `local-205653746-3820765781` and its managed
prefix after its process stopped. Its settings and download database were
retained on the bench at
`/home/player/.local/share/marwanos/backups/fdm-windows-20261005/settings`.
The old Windows download folder contained no files; its queue was not imported
into the Linux app. The original setup EXE remains available for acceptance work.

`Installed` now assigns the stable Linux FDM ID the controller pointer profile.
This activates the existing pointer bridge, overlay input gating and native
window sizing. The shell was exported using the pinned offline Godot 4.7.1
build runtime, preflighted on the bench, and activated in the existing
controller-setup override. Its previous executable is retained at
`/var/marwanos/controller-setup-20261005/marwanos-shell.before-fdm-linux`.
The existing override service restores the new executable at boot; no new
OS image was published and no reboot was performed.

## Verification

- Linux FDM completed a 40-byte HTTP download from a temporary localhost server
  into `/var/home/player/Downloads`. Its file matched the server fixture exactly,
  with SHA256 `40c878fc306d3f94897d7398a654b46ab6d208eba71af3a7fde76aea3e95c6ef`.
  The test server was stopped afterwards.
- The Flatpak sandbox resolved the download folder onto `/dev/nvme1n1p1` and
  confirmed it was writable.
- The library contains the Linux FDM card; the Windows manifest and prefix are
  absent. Launch from that card succeeded with a live Flatpak process.
- The active shell logged `pad bridge up in pointer mode` and resized the
  actual FDM backing window to 3440×1440. FDM was left running from its card.
- The controller shell fixture passed all 13 checks, including native FDM
  pointer classification and unchanged game controller routing. Export,
  bench preflight and `git diff --check` passed.

Screenshots are retained in `out/fdm-linux-verification.png`,
`out/fdm-linux-add-download.png` and `out/fdm-linux-download-complete.png`.
The blank Godot backing-window capture in `out/fdm-linux-library.png` is not
visual acceptance evidence; library launch was verified using the session log,
process state and X11 geometry.

The [Flathub package documentation](https://github.com/flathub/org.freedownloadmanager.Manager)
states that automatic browser integration does not work in this package.
Manual URL downloads were verified. Integrated Mowser downloads retain their
existing behavior; this change does not route them into FDM.

## Browse file-picker repair

FDM's Add download > Browse button initially did nothing because the image
masked `xdg-desktop-portal-gtk.service`. The active frontend repeatedly logged
`Backend call failed` because the GTK backend's activation unit was masked.
This button selects a local torrent file; the save-folder picker also uses the
portal backend.

The repository now supplies a D-Bus activated GTK backend unit using X11 and
removes the image mask. The session publishes `DISPLAY` and, when present,
`XAUTHORITY` to the user systemd manager after the compositor is ready, so an
activated picker can reach either gamescope XWayland or the VM Xorg session.
The greeter's separate portal mask remains appropriate to the login account.

On the live bench, a player-owned unit at
`~/.config/systemd/user/xdg-desktop-portal-gtk.service` overrides the old immutable
image mask. Its `50-pc1-bench-display.conf` drop-in supplies `DISPLAY=:0` for the
bench's existing session, including subsequent boots. This local override can
be removed when an image containing the session fix is deployed.

Clicking Browse opened the GTK picker. Pointer clicks selected Home and opened
Downloads; the test torrent was visible. During verification the user selected
their own torrent, and FDM received its document-portal URI and added it to the
download queue. Verification did not restart or stop that download. The local
fixture and temporary screenshots were removed from Downloads afterwards.

Both portal services are active, the unit passed `systemd-analyze verify`, the
session passed `bash -n`, and the portal journal showed no further backend
activation failures. Screenshots of the open picker and pointer navigation are
retained at `out/fdm-browse-picker.png`, `out/fdm-browse-home.png` and
`out/fdm-browse-downloads.png`. A hardware-controller selection and a reboot
were not performed in this repair.
