# PC1 bench fixes — 2026-10-05

The physical NVIDIA bench was patched over SSH without replacing its OS image.
Its no-background-Steam gamescope 3.16.23 session uses a 3440×1440 display.

## Findings and changes

- DualSense input produced evdev `SYN_DROPPED` frames. The broker previously
  disconnected on those frames and reacquired the controller on its one-second
  scan. Recovery now retains the grab, discards the incomplete frame and queries
  current state at the next synchronization report. Empty nonblocking reads
  also retain the controller.
- FDM's files survived setup Close, but its job lost the executable choices and
  had no library manifest. The existing prefix was recovered and registered as
  **Free Download Manager**. Setup Close now preserves installed choices, and
  valid local Desktop/Start Menu shortcuts supply names and preferred targets.
- FDM's 950×610 backing window was stretched to the whole display. Pointer
  desktop windows now resize to native pixels on handover and resume; dialogs,
  transient windows and explicit fullscreen modes are excluded.
- Gamescope without Steam integration ignored the base-layer window override.
  Minimize now unmaps app windows while preserving the process; Resume remaps
  the same windows. This lets FDM continue in the background with home visible.

## Verification

The targeted Python run passed eight controller tests and 37 Windows helper
tests. The Godot controller and Windows shell fixtures reported zero failures.
The real X11 geometry fixture passed seven checks, including native backing
pixels, unmap/remap of the same instance, and dialog/fullscreen exclusions.
The shell exported with the pinned Godot editor and the bench's browser extension.

On the bench, FDM launched from its home card and measured 3440×1440. Minimize
returned compositor focus to home while preserving runtime PID/start identities;
Resume restored that same runtime at native dimensions. Close removed the
runtime record and ended FDM. The bench was left on home with its FDM card.

## Deployment and rollback

`/etc/systemd/system/marwanos-bench-fixes.service` is an enabled oneshot service
ordered before greetd and the Windows worker. It bind-mounts the staged router,
helper and shell from `/var/marwanos/bench-fixes-20261005` onto their image-owned
paths. The existing browser extension and installed app prefix are retained.
The shell executable's unmount uses `umount -l`, because the running shell can
keep the executable mount busy during refresh. Stop/start the unit to refresh
bind mounts after atomically replacing staged files.

For rollback, close any running Windows app, disable and stop
`marwanos-bench-fixes.service`, then terminate the shell and controller broker so
the session supervisors reload the image-owned versions. Stopping the service
removes its mounts; it does not delete the staged files or FDM's library entry.
Disable this override before switching to an OS image that includes the fixes.
This session did not publish a new image or perform a reboot acceptance test.
