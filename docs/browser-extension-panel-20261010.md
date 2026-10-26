# Bench browser extension panel — 2026-10-10

Applied to Bench (`192.168.50.206`) at 00:16 UTC on October 10
(02:16 in Copenhagen). This follows the
[native installation fix](browser-install-crash-20261010.md).

The browser's extension button now opens a right-side panel. **Manage** opens
Chromium's installed-extension manager, **Store** opens Chrome Web Store, and
**Open extension** lists enabled extensions with an action or options page.
The current browser tab remains behind the panel. **Close**, Escape, or clicking
outside the panel returns to that tab. **Type** opens the controller keyboard
for the focused native field.

The previous native window filled the screen and did not expose an accessible
way to open an installed extension's action page. Extension-created setup tabs
were also closed immediately. The replacement hosts Chrome-style CEF content
in a frameless panel, reads installed action/options pages from the existing
profile, and redirects setup tabs into the panel before releasing the auxiliary
browser. Native X input delivers controller keyboard edits to the focused field.

CEF's custom Chrome BrowserView crashed in the actor overlay's
`OnWebContentsAttached` callback because it lacks the expected `TabInterface`.
The runtime disables `GlicActorUi` alongside the existing reading-mode
workaround. The browser and native panel continue to use the same persistent
profile and Chromium sandbox.

## Validation

All 94 assertions passed on Bench using the pinned Godot 4.7.1 editor:

- 59 browser layout, navigation, and controller checks.
- 15 extension shell lifecycle and panel geometry checks.
- 15 native panel checks under private Xvfb/Openbox as `player`, with Chromium's
  sandbox enabled. These verify the installed NordVPN action page, panel
  placement, keyboard opening, input restoration, Web Store routing, and close.
- 5 real Manifest V3 fixture checks covering action-page opening,
  `chrome.tabs.create` setup navigation, native text delivery, and Backspace.

The copied isolated NordVPN installation reached its privacy/setup screen in
the panel. Account sign-in and VPN connections were not tested. The user's
live profile was not changed by the isolated checks.

The release export passed an isolated startup check. After activation, shell
PID `153383` loaded the replacement engine inode, refreshed `shell.ready`,
announced `home rail ready`, and remained running without script, parse, or
resource-loading errors. The replacement preserves the latest deployed Home
card scale, game splash, and Files controls.

Latest isolated run:
`/var/tmp/marwanos-browser-extension-panel-20261010/check-06f9ws12`.
Local ignored screenshots, logs, and deployment record are saved under
`out/browser-extension-panel-20261010/`.

## Artifacts and rollback

Active directory: `/var/marwanos/console-design-20261009`.

| Artifact | SHA-256 |
| --- | --- |
| Shell | `b58d4c575465a4dedce792e44613de54b7a9d8dd1252ff56e2b4aa031a7307f7` |
| Native engine | `de9d689c9b55bf26af5906f03fc2a8968b6b7e94b50d0a0938066fde5025ce58` |
| Source archive | `f8e86dad768b4b809eb1546f09e33379b485e9bd00fbafc5701a116682258e63` |

Source archive:
`/var/tmp/marwanos-browser-extension-panel-20261010/browser-panel-source.tar.gz`.
The active directory contains `browser-extension-panel-deployment-20261010.json`;
`refinement-deployment-20261010.json` references the new source and paired
binaries while retaining the other deployment metadata.

The installer verified the current baseline hashes before replacing either
file and included automatic rollback for startup failure. Saved previous files
must be restored together:

- `marwanos-shell.before-extension-panel-20261010`
- `libmowser.so.before-extension-panel-20261010`

The preserved baseline source is
`/var/tmp/pc1-larger-cards-20261010/validated-source.tar.gz`.
