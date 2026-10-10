# Windows games missing from home — 8 October 2026

Fixed in source and applied to PC1 at `192.168.50.206`. The running shell and
a captured native home screen both show **The Witcher 3 - Remastered**.

## Cause

The installation `local-5273110-2361620743` had extracted the game into its
managed Games folder. Its job remained `select`, with exit code 241 and the
detail “Setup was closed. Choose an installed program to add to your library.”
The retained controller page showed the bundled DirectX installer. No app
manifest existed, so home had nothing to display. This was an explicit
registration requirement, not an artwork or scanner-cache failure.

The original choice list mixed REDprelauncher, witcher3.exe, crash-reporting
tools, D3D12 support tools and redistributable installers.

## Behavior

- Successful interactive setup automatically registers a unique shortcut target
  or a single launchable executable. A unique executable named by a vendor
  prelauncher's shortcut is preferred; unrelated and duplicate renderer choices
  remain ambiguous. Support directories and maintenance executables are excluded.
- Interrupted, failed or ambiguous jobs with usable programs appear on home as
  Finish adding cards. Accept or Down opens that installation's program choices
  without restarting setup; Options uses the existing confirmed discard flow.
- Managed application changes notify the installed library immediately after
  the half-second installation poll. The installed list also polls every half
  second. Publication does not depend on network artwork.
- The existing Witcher install was explicitly registered against
  `bin/x64_dx12/witcher3.exe`, retaining the friendly shortcut title, extracted
  icon, existing prefix and native controller input. No game files were moved
  and no installer was rerun.

## Validation and deployment

All 63 Windows backend tests and the full 12-script shell suite passed. The
new tests exercise automatic original/guided completion, failed-install behavior,
the Witcher prelauncher/support-tool layout, ambiguous choices and the pending
home card's controller flow. A metadata test now checks exact request membership
instead of assuming unpadded numeric filenames sort chronologically.

Evidence is under `out/windows-auto-*` and `out/witcher-home-20261008.png`.
Initial test runs exposed missing Xvfb/pefile fixture dependencies; the final
backend run used a disposable container with the required dependencies.

The installed immutable image is `0.0.202610071750 (a38dce1)`. The repair is a
separate persistent override in `/var/marwanos/windows-library-20261008`, mounted
by the enabled `marwanos-windows-library.service` before the session and Windows
worker. The older controller bench override remains disabled. Staged binaries
passed live headless preflight, their hashes matched the local artifacts, and
the restarted shell logged the installed Witcher card with no script errors.
The native screenshot confirms its visible title and icon. Game launch and a
reboot were not performed. Retire this override when installing an image that
contains the source fix; it must not mask later image versions indefinitely.
