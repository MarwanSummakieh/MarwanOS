# Browser extension installation crash — 2026-10-10

Applied directly to PC1 (`192.168.50.206`) at 23:35 UTC on October 9
(01:35 October 10 in Copenhagen). The shell and `libmowser.so` were replaced
together, and the shell supervisor restarted the shell. The user explicitly
approved applying the replacement while The Witcher 3 was running.

The running bench still had the earlier extension implementation and native
engine. Its NordVPN Web Store installation crashed while Chromium tried to
create a native permission dialog for the embedded Alloy browser. The captured
stack includes `ChromeConstrainedWindowViewsClient::GetModalDialogHost`,
`AlloyConstrainedWindowViewsClient::GetModalDialogHost` and
`constrained_window::CreateBrowserModalDialogViews`.

The replacement routes Web Store pages and `chrome://extensions/` to an owned,
fullscreen Chrome-style CEF window sharing the embedded browser's persistent
profile. Chromium supplies the normal Add to Chrome → Add extension permission
flow. The browser's puzzle button opens Chrome Web Store or Manage extensions.
A compact toolbar returns to the embedded browser. Native windows and
extension-created tabs close before engine shutdown; the ZIP installer is no
longer exposed by the browser. See [implementation and earlier validation](browser-compact-20261009.md).

## Validation

- A real NordVPN Web Store installation completed in a private PC1 profile as
  `player`, with Chromium's sandbox enabled. Chromium registered extension
  `fjoaledfpmneenckfbpdfhkmimnjocfa`, version `6.1.1_0`, with
  `from_webstore: true`. The store changed to Remove from Chrome. The native
  installer and manager stayed alive, then exited cleanly with status 0.
  This verifies installation; account sign-in and VPN connections were not tested.
- The prepared source passed 59 browser layout/controller checks and 11
  extension menu/lifecycle checks.
- Eight native extension-window checks passed under private Xvfb/Openbox using
  the exact prepared shell source and engine as `player`, with the sandbox
  enabled. These cover opening the manager, toolbar hit testing, return/input
  restoration, Web Store URL routing and closing when leaving the browser.
- The exported release executable passed a separate startup check. Release
  templates ignore the test harness's `--script` argument, so the native test
  suite ran through the pinned editor against the prepared source.
- After activation, the new process loaded the replacement engine inode,
  announced `home rail ready`, refreshed `shell.ready`, and remained running.
  No script, parse or resource-loading errors occurred during the health check.
- The user's subsequent live bench retry opened the NordVPN Web Store page in
  the same replacement process. A read-only check of the live profile confirmed
  NordVPN `6.1.1_0` registered with `from_webstore: true` and no disable reasons.
  The shell was still process `456938`, and no new shell coredump was present.

The shell build starts from the exact deployed refinement source and changes
only `browser_screen.gd`, adds `browser_extension_toolbar.gd`, and replaces the
engine. The complete replacement source archive preserves the baseline `tests`
and `os` directories and includes the tested engine source.

## Deployed artifacts and rollback

Active directory: `/var/marwanos/console-design-20261009`.

| Artifact | SHA-256 |
| --- | --- |
| Shell | `15d41f6359e129646c21d5d774fa681c7d156846045caa5b572d6985023542fc` |
| Native engine | `6c5f61e620f70a51edfd91934e98db6c69607c236b04837e4608ce1f1f9c6f5d` |
| Source archive | `d89700759310be68f10819b95cfddf7c744598fab5f02be67693d8f7f559ad4e` |

The source archive is
`/var/tmp/marwanos-browser-install-fix-20261010/browser-fixed-source.tar.gz`.
The active directory contains `browser-extensions-deployment-20261010.json`;
`refinement-deployment-20261010.json` now references the replacement source and
binary while preserving the other deployed UI metadata.

Saved previous files, to be restored together if rollback is needed:

- `marwanos-shell.before-native-extensions-20261010`
- `libmowser.so.before-native-extensions-20261010`

The deployment checked both baseline hashes before replacing files and had
automatic rollback for startup failure. Local ignored deployment artifacts are
under `out/browser-install-fix-20261010`; the isolated NordVPN test log is
`/var/tmp/marwanos-browser-compact-check/nordvpn-sandbox.log` on PC1.
