# Physical acceptance session — October 7, 2026

**Status: IN PROGRESS; controller hotplug/force-feedback exposed a broker crash
and discovery deadlock. The revised broker now links physical and virtual device
lifetimes and preserves hardware model identities, and is temporarily active; native Tekken disconnect/pause acceptance
awaits physical retest. The superseded shell recovery prompt has been removed.
Physical acceptance is incomplete.** The owner requested
physical acceptance of rumble, two controllers, hotplug, Bluetooth, TV/audio,
Steam/game compatibility and cold boot. This supersedes the earlier automated-only
deferral for those checks. Suspend/resume remains separately deferred.

The owner clarified that only one physical controller is available and there is
no Bluetooth adapter. Two-controller and Bluetooth acceptance therefore remain
pending hardware; virtual application pads do not supply that evidence.

## Candidate and baseline

- Source: `cc199319111e0fe7e52f558b2f04b8cfb7dbd53e`.
- Image: `ghcr.io/marwansummakieh/marwanos@sha256:a271f2ba2dedab79a5405c86e3a356dd4673208be468ec6a0afe62885623806b`.
- Initial boot: `d9a21db2-030d-4d5d-93f3-1e566fba7c05`.
- Live read-only postboot gate: **PASS, zero failures**, retained locally as
  `out/physical-acceptance-20261007-preflight.log`.
- Initial input inventory: one physical USB Sony DualSense and four persistent
  PC1 virtual application controllers. Physical pad force-feedback capability is
  advertised. The owner subsequently felt vibration, but reliable in-game rumble
  and motor cancellation still need the controlled retest below.
- Bluetooth: no kernel HCI device; worker reports `no-adapter` without an error.
- HDMI audio is enumerated. Initial default output and shell stream destination
  are the DualSense audio sink. TV audio must be selected and heard physically.
- A subsequent snapshot shows NVIDIA HDMI/DisplayPort selected and the shell and
  three other streams routed to output 120, without an audio-worker error. This
  confirms software routing, not audible TV sound. The active display connector
  is `card0-DP-2`; HDMI connectors are disconnected. Target display identity and
  any adapter/cable arrangement still need the owner's description.

Local support snapshots are `out/physical-acceptance-20261007-baseline.json` and
`out/physical-acceptance-20261007-failure-snapshot.json`. They contain software
inventory, not physical pass results.

The candidate11 [NVIDIA teardown pass](candidate11-teardown-acceptance-20261007.md)
is established independently. Fresh candidate11 installation media remains
unvalidated; acceptance of this existing deployment does not certify that media.

## Results

The owner clarified the first report as **"this works fine but the controller
does not vibrate"**: sound, gameplay, physical input and Home/resume worked before
the later incident. The owner then felt vibration and reported a frozen Tekken
picture. USB disconnect/reconnect is logged at 11:58:11/11:58:15 UTC. At
11:59:54 UTC broker PID 1916 exits with `OSError: [Errno 22] Invalid argument`
in `Rumble.handle` → `struct_ioctl` while beginning a force-feedback callback;
its replacement appears at 11:59:55. The virtual pads are recreated. The exact
cause of the game's frozen frame is not proven solely by this timeline.

Tekken PID 32099 remains alive, compositor PID 1980 and shell PID 2059 remain
alive, and the inspected recent journal contains no NVIDIA fault or stored core.
`out/physical-acceptance-20261007-tekken-freeze.json` retains process samples and
USB/session evidence. Its attempted X11 focus queries failed authorization and
`xwininfo` was unavailable; those queries do not establish window focus.
The installation log tail in that file is historical and is not a fresh game
crash log. The owner confirmed **Home → Close → Play recovers responsive gameplay**.

The source fix ignores only `EINVAL` from a missing/retired uinput FF begin/end
request; other ioctl failures remain visible. This matches the kernel's
[uinput request lifecycle](https://github.com/torvalds/linux/blob/master/drivers/input/misc/uinput.c),
which can retire a request while its notification is still queued. All 26
controller regressions and the Linux kernel fixture pass, including real
missing-request begin callbacks, ordinary FF operations and identity reconnect.

With the owner's game closed, a **reboot-volatile single-file bind override** was
activated. Broker PID 50064 was replaced by PID 61470. Original file SHA256 is
`a68111ee38cb71e391c9aac8ad397f0d267f4b58390d8a63d24c5295453202b9`;
patched SHA256 is
`fe65c2d366d31254029284cc87538f0123c95b3fec9864e1220d9e5fbb05252a`.
Evidence: `out/physical-acceptance-20261007-bench-patch.json`.
The published image remains unchanged. This override is not baked-image release
acceptance and disappears on reboot.

### First patch retest and discovery deadlock

The owner reports that Tekken freezes after controller disconnection and becomes
laggy on reconnect even with the first patch. That patch prevents the broker
crash, but does not resolve the stall. Broker PID 61470 remains alive. The USB
disconnect/reconnect is logged at 12:09:48/12:10:00 UTC, but the broker does not
report reconnection until 12:10:51. These journal timestamps are observations,
not a precise input-latency benchmark.

Live `/proc/61470/syscall` reads show ioctl `0x81004506` (`EVIOCGNAME`) on fd 10;
that fd points to `/dev/input/event22`, whose sysfs name is **PC1 application
controller**. The kernel wait is `evdev_ioctl`. The broker's discovery loop is
probing its own virtual pad before servicing the FF request that holds that
pad's evdev mutex. The kernel [evdev ioctl locking](https://github.com/torvalds/linux/blob/master/drivers/input/evdev.c)
and [uinput request lifecycle](https://github.com/torvalds/linux/blob/master/drivers/input/misc/uinput.c)
explain this circular wait and the subsequent expired callbacks. The failing
first-patch retest is retained in
`out/physical-acceptance-20261007-patched-retest-failure.json`.

The revised source skips PC1 virtual pads using their sysfs names **before
opening or issuing any evdev ioctl**, and retains the retired-callback guard.
All **28 controller regressions** and the actual Linux kernel fixture pass.
The new fixture deliberately queues a FF request while discovery scans its
virtual node: the original implementation blocks, the revised code returns
promptly, and cleanup completes the request without waiting for its timeout.
Both original-code negative controls are retained in
`out/physical-acceptance-20261007-kernel-negative.json` and
`out/physical-acceptance-20261007-discovery-negative.json`.

The full disposable Fedora suite passes **229 tests: 227 passed, two optional
skips**, in `out/physical-acceptance-20261007-backend-container-v2.log`.
An earlier direct WSL run lacked the documented installer test environment and
failed ten unrelated installer cases; that failed log is preserved. The first
patch's configured container run separately passed 225 tests with two skips.

Tekken was closed with its normal image-owned managed stop helper before the
temporary file override was replaced. Normal SIGTERM of the old broker was
delayed in its discovery stall; it finally exited and the supervisor started
**broker PID 86469 at 12:17:39 UTC**. A guarded force-stop attempt found the old
PID already absent and **sent no SIGKILL**. The revised runtime source SHA256 is
`0ad2558a01ee83378286a7f2e0f04cc708329b4ab40c4c3297fc167662c3a5be`.
`out/physical-acceptance-20261007-v2-baseline.json` preserves the revised bench
state. Physical retest is pending. This remains a reboot-volatile override;
corrected image publication and cold-boot acceptance are not established.

### Superseded shell recovery prompt

The owner clarified that the standalone Tekken installation shows no controller
disconnect message and leaves them effectively AFK. This report is distinct from
the earlier frozen-frame incidents; it does not establish fresh input failure
after reconnect. PC1's persistent virtual application pads hide physical USB
removal from the game.

A read-only check at 13:25 UTC confirms revised broker PID 86469 and its expected
source hash remain active. It reports player-one disconnections/reattachments at
13:17:11/13:17:26, 13:18:54/13:19:00 and 13:19:02/13:19:07 UTC. The recorded
DualSense identity remains in slot one. The broker is waiting in its normal poll
loop, with no recorded crash or discovery-ioctl stall in that sample. This proves
broker recovery, not observed game controls or rumble. Evidence:
`out/physical-acceptance-20261007-v2-hotplug-diagnostic.log`.

An initial shell workaround opened **Controller disconnected** over an on-screen application,
gates application input, and requires all controls neutral plus explicit Resume
after reconnection. It preserves an existing app menu and its keyboard/audio
children, and removes both overlays when the app exits. The prompt explicitly
says the game may keep running: this does not suspend game simulation or pause
an online match. All integrated shell suites pass, including the new recovery,
held-input, duplicate-disconnect, Back and app-exit regressions. The disconnected
and reconnected screens were rendered and inspected; the disconnected layout
was verified at actual 1280×720 and 2560×1080 viewport sizes.

A guarded, reboot-volatile single-file shell bind override was activated, replacing
shell PID 2059 with PID 270106 only after checking no managed game was running.
The original shell binary is preserved in
`/var/tmp/pc1-controller-reconnect-20261007/marwanos-shell.original`.
Original shell SHA256:
`01fe8d5db259fe84786a29aaaefe8ff7fe1b158cbfeef0ea5de8c79d689b461b`.
Replacement shell SHA256:
`edd4e8321daf650b269b4160d3b7e75d312e95e7eea6ccc087f704ab4aaceb1b`.
The native browser library is unchanged, verified by checksum. An isolated
headless preflight and fresh live shell-ready heartbeat passed. Evidence:
`out/controller-reconnect-shell.log`, `out/controller-reconnect-all-shell.log`,
`out/controller-reconnect-bench-patch.json` and
`out/controller-reconnect-live-validation.log`.
The owner clarified that physical removal must disconnect the corresponding
virtual controller so Tekken can pause itself. The shell workaround did not meet
that requirement and has been removed from source and the live session. Its
screens and test logs above are historical evidence, not current acceptance.

### Native virtual-controller removal and reconnect

The broker retains four player-slot identities but creates application uinput
devices only for attached physical pads. Physical disconnect neutralizes and
destroys the matching virtual device, clears its old force-feedback effects and
leaves other players' devices intact. Reconnection creates a fresh application
device with the same player-slot name, USB identity and physical slot label;
held controls remain gated until released. Tekken can now receive native device
removal; its actual disconnect/pause behavior is still pending physical observation.

All **32 controller policy regressions** and the real Linux uinput fixture pass.
The kernel fixture verifies removal returns `ENODEV` through the old evdev handle,
pending force-feedback uploads finish promptly with `ENODEV`, reconnect creates
a new virtual device, other players keep receiving input, and fresh input and
rumble recover without inheriting old effects. The full configured disposable
Fedora backend suite passes **233 tests: 231 passed, two optional skips**.
Evidence: `out/controller-hotplug-policy.log`, `out/controller-hotplug-kernel.log`
and `out/controller-hotplug-backend.log`.

PC1 rebooted into boot `077cbe6f-26e2-4c32-a2be-ea7830e169eb`, removing the earlier
temporary overrides. With no managed game running, the corrected broker was
activated through a reboot-volatile bind override and normal supervisor restart:
PID 2183 was replaced by **PID 9585**. Router SHA256 is
`e5f90934ffe698e0bb6f848bfa2a8bb47b3f279c9e016ddbf935b9001e5ffe02`.
The original image shell remains PID 2653 with SHA256
`01fe8d5db259fe84786a29aaaefe8ff7fe1b158cbfeef0ea5de8c79d689b461b`.
The 14:12 UTC live check finds one physical DualSense gamepad and exactly one
application controller, a normally polling broker and no broker errors in its
current-process journal. Evidence: `out/controller-hotplug-bench-patch.json` and
`out/controller-hotplug-live-validation.json`. The owner has been asked to retest
Tekken's own disconnect/pause screen and controls after reconnecting. Physical
pass, baked-image publication and reboot persistence remain unestablished.

### Correct hardware model identity

The owner requested that the virtual device identify the connected controller
type. The broker now forwards the physical model name and vendor/product/version
IDs, with Linux `BUS_VIRTUAL` as the transport. Discovery identifies its own
devices by `pc1/application/slotN` before any evdev ioctl, so preserving model names
does not reintroduce the force-feedback discovery deadlock. Sony and Xbox-style
face-button conventions are handled independently. Reconnect retains the slot;
a different attached model gets its own identity.

The session's fixed generic SDL allowlist/mapping is removed. Udev hides physical
joysticks from application enumeration, including SDL2's legacy class fallback,
and exposes only routed pads. All **35 controller regressions**, the real Linux
kernel fixture and real SDL control-mapping checks pass. SDL identifies synthetic
DualSense as PS5, Xbox 360 as Xbox 360, and leaves unknown hardware's IDs intact;
face buttons, D-pad, sticks and triggers work in each case. The configured Fedora
backend suite passes **236 tests: 234 passed, two optional skips**. Evidence:
`out/controller-type-policy.log`, `out/controller-type-kernel.log`,
`out/controller-type-sdl.log` and `out/controller-type-backend.log`.

With no managed game running, reboot-volatile router, session and udev rule
overrides were activated and greetd was normally restarted. The fresh shell-ready
heartbeat passed; broker PID is **80787**, shell PID **80905**. Source hashes and
the unchanged boot ID are retained in `out/controller-type-bench-patch.json`.
At 14:27 UTC, SDL running as player enumerates exactly one routed pad named
**Sony Interactive Entertainment DualSense Wireless Controller**, vendor/product
`054c:0ce6`, SDL type **7 (PS5)**, on `/dev/input/event22`. The real physical node
is excluded from SDL application enumeration while remaining available to the
broker. Evidence: `out/controller-type-live-validation.json`. Tekken's own button
prompts, physical input/rumble and native pause/reconnect behavior still require
physical observation; software type detection does not establish those passes.

| Check | Result | Evidence still needed |
| --- | --- | --- |
| Single-pad input/Home/resume | Owner-confirmed initial pass and game recovery | Repeat after patch/hotplug; full held-control suppression remains unverified |
| USB rumble | Vibration felt; reliable game rumble pending retest | Identify ordinary game event; stops in Home and after disconnect |
| Single-pad USB hotplug | FAIL on original broker and first patch; native virtual hotplug implemented, physical retest pending | Game receives disconnect and shows its own pause/recovery behavior; reconnect to same slot, fresh input and rumble recover |
| Two-controller multiplayer | Pending hardware | Distinct physical players and rumble destinations; stable reconnect of either pad |
| Bluetooth dongle/pairing | Pending hardware | Actual adapter discovery, controller-only pairing and wireless input/rumble/reconnect |
| Display/audio | Owner-confirmed initial sound/picture pass | Target TV identity/connection, mute/output persistence and cable/power recovery remain unverified |
| Steam compatibility | Pending account/title selection | Actual Steam-owned title launch, physical input, Home/resume, Close and persistence |
| Tekken compatibility | FAIL: frozen picture during session; normal Close/relaunch recovers | Retest after fix with physical input, rumble, hotplug and clean Close |
| Three filmed cold boots | Pending observation | Each power-button-to-usable-Home time <=15 seconds; no console text or cursor |

## Sequence and pass criteria

1. **TV/audio and single-pad game.** Record TV model, connection and controller
   model. Use the controller to select HDMI/DisplayPort in Settings → Audio.
   Hear sound from the TV, check volume/mute/unmute, then launch Tekken 8 from
   the library. Enable game vibration and play briefly. Confirm input, rumble,
   readable picture and game audio. Open Home during play: no game input may
   leak through the menu and active motors must stop. Resume and confirm held
   controls stay suppressed until released; fresh input and rumble work again.
   Close through PC1 and verify the shell returns.
2. **Single-pad USB hotplug.** Launch the game again. Disconnect the USB pad
   while holding a direction or button. Confirm the game does not keep moving
   or pressing it and rumble stops. Verify Tekken shows its own controller
   disconnect/pause screen. Reconnect in the same USB port, release all
   controls, and verify the same player responds to new input. Repeat from Home
   and verify controller navigation recovers. Record any duplicates, stuck input,
   lost Home access or lost rumble. Preserve before/after slot identities and
   broker journal entries. With one pad this cannot certify multiplayer routing.
3. **Two pads, when available.** Label the physical pads P1/P2 and record models
   and transport. In Tekken local versus, each pad must control only its player.
   Check each player's rumble destination. Home from either pad must open PC1
   and neutralize both game pads/motors. Disconnect/reconnect each pad in turn;
   the other player's assignment must remain stable. Repeat after reboot.
4. **Bluetooth, when available.** Record dongle model and USB VID/PID. Attach it
   while PC1 runs and use Settings → Bluetooth to discover/pair a controller,
   completing any confirmation using the controller. Remove the paired pad's
   USB cable to prove wireless transport. Check input, Home, rumble, controller
   power-cycle, dongle unplug/replug and cold-boot reconnect. Test removal through
   its confirmation, then pair again. Use an existing wired pad to navigate
   pairing when the wireless pad is disconnected. Sleep is outside this session.
5. **Steam and games.** Select an already owned, installed Steam title; record its
   name/App ID and actual runtime/source. Use normal controller sign-in if needed;
   retain no passwords or tokens in evidence. Verify launch into actual gameplay,
   physical controller input, TV sound, Home/minimize/resume and normal Close back
   to PC1. Check history/persistence after boot. Test online/offline behavior only
   where the title supports it and record exact limitations. Tekken's existing
   standalone installation does not establish Steam account/DRM compatibility.
6. **TV connection recovery.** With work saved, power-cycle the TV and reconnect
   its display cable. Verify picture and audible audio recover, the chosen output
   remains correct, and the controller can still reach Home. Record resolution,
   overscan/clipping, flicker/blanking and any visible text/cursor.
7. **Three cold boots, last.** Save/close games. Before each shutdown, retain the
   current image, boot ID, compositor PID and UTC shutdown boundary. Use PC1's
   ordinary Power → Shut down and wait for full power-off. Film the physical
   power-button press through usable Home; record each elapsed time separately
   and check the <=15-second/no-text/no-cursor gate. Verify controller navigation,
   TV sound/output selection and available wireless reconnect on each boot.
   After SSH returns, save the new boot ID, run the read-only postboot gate and
   `scripts/verify-pc1-shutdown.py` against the explicit prior boot. Software
   boot timing, reboot and SSH reachability do not substitute for filmed timing.

Record observations with candidate/boot identity, test step, observer and evidence
path. Leave failures and missing observations visible; preserve journals and cores.
Update results only after the relevant physical observation and supporting checks.
