# FDM controller bench deployment — 2026-10-05

FDM Controller is installed on the bench at `192.168.50.206`, using the locally
built FDM Classic fork under UMU-Proton 10.0-4. The old system Flatpak
`org.freedownloadmanager.Manager` was uninstalled after backing up its settings
and queue. Download files and the separate running game installer were retained.

The controller interface is the bench default. The desktop button, F10 switch
and controller Menu shortcut were removed. Closing the controller window sends
the application close request rather than revealing the classic window. The
legacy frame remains hidden as part of the original download engine.

The library card now uses the custom mint download icon in
`assets/fdm-controller/icon.png`. Its bench copy is `icon.png` beside the portable
executable, and the manifest references that path so automatic icon extraction
does not overwrite it. The former manifest is backed up with
`.before-icon-20261005`. The transparent PNG and refreshed live library icon path
were verified without restarting the download manager. A direct capture of the
shell returned its transparent surface, so the card itself was not visually
verified on the active display during this icon update.

The flicker fix buffers button drawing and changes text, layout and fonts only
when needed. A six-second idle check captured 120 identical button frames.
The user also confirmed the view looked stable. Wine uses Arial for this view.

## Torrent and notification verification

Three synthetic, loopback-only torrents each downloaded two files totaling
1,311,433 bytes. All six resulting SHA-256 comparisons passed. The final build
downloaded `fdm-notification-fixture-v2` and delivered a `Download complete`
notification containing its name to the shared system inbox.

FDM's floating progress window, custom completion windows, tray balloons and
sounds are disabled in the controller portable mode. Its completion and status
events use atomic UTF-8 JSON files in the player's shared home directory;
Proton does not expose the host runtime directory that was initially tried.

The new user service implements `org.freedesktop.Notifications` on the session
bus, so ordinary Linux notifications and Wine bridge events share one persistent
inbox. It retains up to 50 messages; the latest ten appear at the top of the
shell's Info page, reached through the clock/status control. New notifications
use the existing brief home-screen alert and do not activate the shell over a
running application. This version has no notification action buttons or popup
overlay over games. Notification history remains available after service restart.

Validation:

- FDM build: zero compile errors; existing legacy dependency warnings remain.
- Controller input checks: 15 passed, including Menu never opening desktop view.
- F10 followed by torrent browsing kept the controller window visible on Wine.
- Two Python checks passed using an isolated real D-Bus session: notification
  delivery, Wine spool consumption, replacement, closing, bounded history,
  Unicode, persistence and ignoring partially written files.
- Godot notification checks: zero failures, checking the shared home alert,
  expiry timer and controller-accessible Info history.
- The Info page was rendered and inspected on a separate Xvfb display without
  disturbing the bench display; no script errors occurred in the final checks.
- The final torrent completion kept FDM focused, produced the system inbox entry,
  and left only the controller and shell windows visible. All temporary tracker,
  seed and preview display services were stopped.

Physical controller input is detected as connected through Wine. Button-by-button
hardware acceptance and shell launch/minimize/overlay routing were not verified:
the shell still owns the separately running minimized game setup. FDM was launched
through a targeted validation service. Its registered library card uses the same
portable executable, prefix and notification environment for normal future launches.
The earlier Windows report separately verifies magnet metadata, pause and restart
resume; those scenarios were not repeated on this bench deployment.

## Installed files and recovery

Bench paths:

- App: `/var/home/player/.local/share/marwanos/portable/fdm-controller-20261005`
- Prefix: `/var/home/player/.local/share/marwanos/windows/prefixes/local-fdm-controller-20261005`
- Card: `/var/home/player/.local/share/marwanos/windows/apps/local-fdm-controller-20261005.json`
- Downloads: `/var/home/player/Downloads`
- Old FDM backup: `/var/home/player/.local/share/marwanos/backups/fdm-linux-20261005/settings-and-queue.tar.gz`
- Notification history: `/var/home/player/.local/state/marwanos/notifications.json`
- Notification bridge: `/var/home/player/.local/share/marwanos/notification-events`
- Bench service source: `/var/marwanos/notifications-20261005/server.py`

The old Flatpak's application data also remains in `.var/app`. Its queue was not
imported into the Classic fork. Prior FDM executables and the prior shell export
were retained as named backup files. The synthetic downloads remain as test
entries, approximately 3.9 MB total.

Final `FDM.exe` SHA-256:
`A551809D77C5D1EC3D11002EC98B36DE88721F9B86A54DF8A66AA9E956887A4A`.
Torrent DLL SHA-256, unchanged:
`657AC69D866B672812003970E748ACEE6CD1AC19A8E97C4154695CED98CFDE13`.

The [evidence folder](fdm-controller-bench-20261005/) includes the complete source
patch against upstream commit `1bd57c2f5aef2a06ba51990a876aa3632071630c`, controller
sources, build scripts/log, fixture generators, deployment scripts, app manifest,
hash and notification results, render results and screenshots. Reverse patch
application was checked against the source tree without modifying it. The package
at `out/fdm-classic/fdm-controller-bench.tar.gz` was refreshed with the final binary.

The notification service, D-Bus activation file, shell inbox integration and image
dependencies are also present in the tracked OS source for subsequent image builds.
The legacy torrent engine and dependency maintenance limitations documented in the
original build report still apply.
