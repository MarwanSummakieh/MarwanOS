# Input latency — PC1, 10 October 2026

The owner reported delayed letter selection, menu navigation and Hollow Knight
Silksong input, including over USB. Two fixes are installed on the bench and
present in source. Physical controller feel after the update remains for the
owner to confirm.

## Findings and changes

The controller broker rescanned `/dev/input/event*` once per second, opening and
closing every unclaimed physical input node to check its capabilities. These
included audio jack events, power buttons and the DualSense sensor/touchpad
nodes. Sampling the actual broker's kernel stack caught `close()` blocked in
`evdev_release` → `synchronize_rcu_normal`. Because discovery runs on the input
thread, this stopped both shell UDP reports and game-visible controller updates.

An eight-second live observation measured controller-report gaps up to
317.6 ms. The shell continued redrawing at 175.0 Hz, with a maximum redraw gap
of 6.2 ms in that observation. This identifies a controller delivery stall,
independently of total physical button-to-pixel latency.

Discovery now reads `device/capabilities/key` and `abs` from sysfs before opening
evdev. Devices without BTN_SOUTH and both left-stick axes are excluded before an
open/close cycle. The existing virtual-device exclusions, actual evdev checks,
exclusive grab, identity, hotplug and rumble handling remain in place. Sysfs
bitmaps are decoded as separate unpadded kernel-long words. Missing or malformed
capabilities are skipped until a later scan.

Eight isolated scans of the same non-gamepad nodes took a median 214.4 ms with
the original discovery code and 5.25 ms with the repair; maxima were 259.0 and
5.33 ms. This probe excluded all gamepads and did not claim a physical device.

The keyboard also used Godot's default release activation, delaying each letter
by however long Cross was held. Its shared key factory now selects
`ACTION_MODE_BUTTON_PRESS`. Draft, live and numeric inputs enter one letter
before release; holding and releasing Cross do not duplicate it. Mouse selection
uses the same timing. See the [Godot button activation contract](https://docs.godotengine.org/en/stable/classes/class_basebutton.html#class-basebutton-property-action-mode).

## Verification

- All 40 controller policy/regression tests passed, including repeated scans of
  non-gamepads, malformed/disappearing sysfs capabilities and Bluetooth sources.
- The real Linux evdev/uinput suite passed: multiplayer, exclusive grabs,
  Home/lease gating, held suppression, hotplug/reconnect and rumble lifecycle.
- The new keyboard timing test reproduced the release delay on the deployed
  source and passed all 17 checks with the fix. It uses routed controller events
  through Godot's actual GUI handling and mouse events, rather than calling the
  character handler directly. It runs from `scripts/check-tools-shell.sh`.
- Current-source Tools, Browser, browser-extension and keyboard timing shell
  suites passed, plus 14 browser-extension and 10 native-text-input Python tests.
- The deployed-source keyboard, controller, Rest and design checks passed with
  pinned Godot 4.7.1. Exported-binary startup preflight reached the Home rail.
- The first eight-second observation after installation measured a maximum
  controller-report gap of 23.5 ms and shell redraws at 174.9 Hz. Six seconds of
  broker stack sampling found no blocked RCU/evdev-close samples. These are
  bounded software measurements, not a camera measurement or gameplay sign-off.

## Bench installation

Silksong was closed by the owner before restarting the broker and shell. The
shell was built from the exact latest deployed console-refinement source
(`fed5bdb8bf203ef94ec5bf8ebf56b2f66151c09d81914e2f143767d88a523fcc`), with only
the keyboard timing change applied. Its display, Steam, Downloads and Rest
changes are preserved. A stale-base deployment guard prevented installing an
earlier build after the refinement update arrived during the investigation.

The shell remains at
`/var/marwanos/console-design-20261009/marwanos-shell`; its SHA-256 is
`2026d355f5bddd8a047b474418cd20c68f57bdecfb20e44d999d2896fef88437`.
The previous binary is `marwanos-shell.before-input-latency-20261010` beside it.

`marwanos-input-latency.service` is enabled and active. It bind-mounts
`/var/marwanos/input-latency-20261010/router.py` over the installed broker only
when the underlying original broker has SHA-256
`535de60b6cb122aa7b5d82b48b0f8ba4eb391c7ee5437c07aa9f8ea28205894a`.
Its guarded unmount removes only its own mount. The installed repair SHA-256 is
`f5ed6370224318d6a7b3c1cb5ae24f4d392c0274237f21604d922b69879ba561`.
The supervisor restarted the repaired broker and retained the remembered
DualSense slot. No OS image or driver was replaced and no reboot was performed.

Build scripts, source archives, deployment manifest, raw timing/stack evidence
and test logs are under `/var/tmp/pc1-input-latency-20261010/` on PC1. Local copies
are under `out/input-latency-20261010/`. The persistent manifest is
`/var/marwanos/input-latency-20261010/deployment.json`.

To revert with games closed, disable/stop `marwanos-input-latency.service`,
restore the saved shell binary via a separate replacement inode, and terminate
the shell and broker normally so their supervisors restart them. The service
restores the underlying broker when stopped; player data and bonds are retained.
