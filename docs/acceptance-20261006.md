# PC1 acceptance evidence — 2026-10-06

This record separates source/fixture checks, the running bench machine and final
release acceptance. A passing build or synthetic controller is not proof of
physical sound, vibration, local multiplayer or a cold power-on.

## Confirmed evidence

- The user confirmed that Tekken 8 accepts the physical controller after its
  saved Windows input profile was changed from pointer emulation to native
  gamepad input and the game was relaunched. The profile correction preceded the
  new multiplayer/rumble broker; it does not certify the latter's hardware behavior.
- Tekken's installation is `managed.local-tekken8-fresh-1791234744`; metadata
  matches Steam game 1778820. Cover, background, logo and header were downloaded
  and cached. An offline worker run preserved the data. The user found the details
  screen through Down, reported cramped spacing/background, and the later bench
  changes enlarged the layout and made the background full screen. Only Play
  remains on that page as requested.
- Controller policy tests: **23 passed** in Fedora Linux WSL. These include held
  controls, queue overflow recovery, Linux face-button positions, slot assignment,
  rumble errors, effect translation and serial identity across USB/Bluetooth bus
  and version changes.
- The real Linux uinput acceptance fixture passed with two rumble-capable
  synthetic pads and one unsupported pad: exclusive grabs, independent virtual
  slots, first-pad shell navigation, all-pad menu/Home/lease gating, held-control
  suppression, upload/update/play/cancel/erase, driver errors and stable reconnect.
- The controller Godot suite and Tools Godot suite passed after integration.
  Tools drives both registration choices with controller A and checks the actual
  helper arguments, including an executable path with spaces: gamepad for a game,
  pointer for an application. This prevents the Tekken profile regression from
  being reintroduced through new library registration.
- Download/cleanup review found and corrected two data-loss cases: a prior job
  at the same pathname cannot authorize cleanup of a new receipt, and unrelated
  BIN/CAB files are retained because directory proximity is not package ownership.
  Torrent payloads are retained for seeding. Cleanup still requires successful
  setup, library registration, an installed executable and unchanged source
  identity, followed by the controller's explicit cleanup choice.

These are source/fixture results. The candidate boot evidence below is separate;
physical acceptance remains incomplete.

## Integrated bench deployment and real session

The tested `ac66747` source was deployed reversibly on the existing PC1 bench.
Prior shell, router, Windows worker and user units are backed up under
`/var/marwanos/features-bench-20261006/backup/`. The existing router bind inode
was preserved during replacement. The Windows worker and notification, audio,
achievements and Bluetooth user workers start successfully, with zero failed
player units. Metadata remains active. This still uses bench overrides.

Tekken was launched from its actual library card under the new broker. It reached
foreground after 11 seconds. Home paused time at 85.928 seconds; minimize kept
that value while the game process remained PID 339285. Resume continued the same
session/process. Closing the coordinator-launched test through Home persisted
one completed session with `end_reason=exited` and **122.453 seconds** total.
A subsequent shell restart preserved that session and recent ordering: Tekken,
Steam, FDM. FDM has no play-history record.

The live audio worker moved all **four** existing playback streams to NVIDIA
HDMI and then DualSense USB audio, acknowledging each default/mute change and
reporting the corresponding stream output. Original mute states and the original
DualSense default were restored. This confirms live routing on actual devices;
audible output and physical headset/hotplug remain unconfirmed.

A modest one-second rumble effect was uploaded to physical slot one's virtual
pad `/dev/input/event22`, played, stopped, erased and closed with Tekken foreground.
The upload succeeded; human confirmation of vibration remains pending. Four
virtual pads enumerate, and the physical DualSense identity persists in slot one.

The actual achievements worker identifies Tekken's RUNE profile and reports zero
observed unlocks with an unavailable total/schema, preserving an honest partial
state. No unlock was fabricated. The old image cannot activate BlueZ; the new
candidate installs/enables it. Physical Bluetooth remains dependent on the dongle.

All five component/integration PR CI checks pass. Candidate build for `ac66747`:
[GitHub build](https://github.com/MarwanSummakieh/MarwanOS/actions/runs/37516255658),
tag `pc1-candidate-20261006`. Its publication/boot status must be checked separately
before claiming release acceptance.

The candidate build completed successfully. The exact installed FDM Controller
fork was then launched through PC1, reached foreground in seven seconds, opened
Home, minimized, resumed with the same PID 363128 and closed through Home. Tekken's
single 122.453-second history record remained unchanged throughout FDM activity.
These actions used the shell's keyboard equivalent for lifecycle verification;
physical button-by-button FDM navigation and minimized download continuation remain
pending. The read-only release gate correctly rejects the old booted image and
active overrides, while passing live artwork, history, audio and four-pad checks.

The published candidate was staged and booted after the user approved the reboot:

- Source/build commit: `ac66747` (later documentation/helpers do not change its payload).
- Image: `ghcr.io/marwansummakieh/marwanos:pc1-candidate-20261006`.
- Immutable digest: `sha256:0ae9a9c19e5d10d96ac4dc306c254b07f4695cdde28e23aa429f8d602e7e9673`.
- Staged OSTree checksum: `7c206512db997b5774ea5cc7c78e37faaabe11cc5cd954a031c0950a04e6c52d`.

The staged root's build-info, shell/browser library, controller, Windows/download,
audio, metadata, achievements, Bluetooth, notification and appscan payloads exist.
All five image-owned user service units/default-wants links are present. The
[retirement helper](../scripts/retire-pc1-bench.sh) passed its actual target preview
without changing anything. It defaults to read-only; `--apply ac66747` backs up
and disables bench startup configuration while retaining current running services.
Use only immediately before the approved candidate reboot. The
[restore helper](../scripts/restore-pc1-bench.sh) restores those recorded overrides
before an approved rollback if needed. The candidate reboot completed at approximately
19:34 UTC. An additional old notification override under `/etc/systemd/user` was
backed up to `candidate-boot-backup-ac66747/etc-user` and retired; the worker then
ran `/usr/lib/marwanos/notifications/server.py`. Retirement/restoration helpers now
cover both user-local and `/etc` user units.

The original read-only postboot gate passed with **zero failures** after the
boot-success timer elapsed: exact digest/build-info, no application bind mounts,
development flag absent, image-owned workers, no failed system/player units,
fresh shell/audio state, all four artwork hashes, Tekken's single 122.453-second
session, partial achievement provider state and four persistent controller slots.
The RTX 3070 runs gamescope at 3440×1440; this boot has no controller failures,
GPU fault matches or coredumps. This was a reboot, not a physical cold power-on.

Further inspection found a Bluetooth no-dongle edge case: BlueZ's hardware
condition skips its system service, and the pairing worker reports D-Bus service
activation failure instead of `no-adapter`. The software gate now checks Bluetooth
freshness/errors too. The backend correction passes all 15 Bluetooth tests,
including actual private-D-Bus pairing and missing-service/hotplug regression
coverage. The complete backend suite passes **175 tests**, with two optional skips.
It must be baked into a replacement candidate before the extended gate
can pass. Hardware pairing still waits for the dongle.

## Read-only hardware inspection

The physical PC1 at `192.168.50.206` was inspected without deployment, reboot,
suspend, changing audio routes, or sending synthetic controller input.

| Area | Observed state | Acceptance implication |
| --- | --- | --- |
| Controller | One USB DualSense, Sony 054c:0ce6, unique MAC exposed through evdev, FF capabilities present | A real rumble pulse and two physical controllers remain to test. A unique ID supports stable reattachment; Bluetooth behavior is not yet measured. |
| Audio | NVIDIA HDMI output, DualSense USB audio/headset, built-in IEC958 output; DualSense currently default with the shell stream attached | Enumeration and routing state are confirmed. Audible HDMI/USB/headset output, microphone recording and unplug/replug behavior remain pending. |
| Audio service | No `marwanos-audio.service` user unit and no runtime audio state on the old image | The new audio worker and unit must be present before Settings audio acceptance. |
| Sleep | `freeze mem disk`, with `deep` selected; suspend counters success=0/fail=0 | Deep suspend is available, but no cycle was tested during this boot. |
| Wake | ACPI XHC wake enabled; the attached DualSense USB device exposes no `power/wakeup` attribute | Use the front power button for the first wake test. Controller wake must be physically established. |
| NVIDIA | PreserveVideoMemoryAllocations=1, UseKernelSuspendNotifiers=1; gamescope running on DRM at 3440×1440 | This is configuration evidence, not resume validation. Inactive/missing NVIDIA suspend units alone do not establish a defect with kernel notifiers. |
| Boot heartbeat | Fresh `shell.ready`, boot-success service conditions passed, GRUB `boot_success=1` and `menu_auto_hide=1` | The existing session reached its frame loop. A final-image cold boot remains pending. |
| Image | Old booted `controller-20261005` image, build `d85a24e-dirty`, version 0.1.20261005 | Bench evidence must not be described as final-release acceptance. |
| Overrides | Active controller, Windows worker directory and shell bind mounts, plus a development shell path/flag | Final acceptance must run image-owned payloads after retiring overrides safely. |
| Failed unit | `rpm-ostreed-automatic.service`: old controller-20261005 GHCR manifest unknown | Move to a published supported image reference; do not hide the failure to claim a clean release. |
| Earlier boot log | Initial gamescope core dump, successful later DRM session; old Avahi/shipped-apps warnings | Inspect the new image's boot journal and distinguish recovered/obsolete bench errors from current failures. |

The bind sources are `/var/marwanos/bench-fixes-20261005/router.py`,
`/var/marwanos/controller-setup-20261005/windows` and
`/var/marwanos/controller-setup-20261005/marwanos-shell`. Replacing a backing file
by rename does not refresh an existing bind-mounted inode. Deployments must account
for those mounts instead of assuming the visible `/usr/lib` file changed.

## Required physical acceptance

1. **Rumble:** with the new broker running, launch Tekken with native input and
   obtain a game event that produces rumble. Confirm the physical vibration, then
   open Home and confirm it stops. Resume, close and unplug/replug without a stuck
   motor. A backend callback success alone cannot prove vibration.
2. **Local multiplayer:** attach a second physical pad. Verify distinct controls
   in a local multiplayer game, first-pad-only ordinary shell navigation and Home
   from either pad. Unplug/replug each pad and confirm slot ownership and no held
   buttons or rumble leak. Only one physical pad is currently attached.
3. **Audio:** after the audio worker is installed, use controller Settings → Audio
   to select HDMI; check an existing stream follows it and physically hear sound.
   Verify volume/mute, then USB/headset output and microphone capture where
   hardware is attached. Unplug the selected device, check fallback, replug it and
   verify saved choice and stream routing. Repeat after sleep and boot.
4. **Suspend/resume:** save and close applications first. Use Power → Sleep, wake
   with the front power button and verify SSH, full-screen GPU output, fresh
   controller navigation/Home, audio and game launch. Compare `/sys/power/suspend_stats`
   and the journal before/after. Repeat three cycles for hardware repeatability.
   Controller wake remains a separate test.
   The read-only [resume evidence helper](../scripts/inspect-pc1-resume.sh) passed
   its actual target preflight with zero failures. Before an approved sleep,
   `--before FILE` creates a private, exclusive baseline; after physical wake,
   `--after FILE` compares suspend counters, boot continuity, GPU/session processes,
   fresh workers, audio and controller slots without changing them. A baseline
   alone does not establish any successful sleep/wake cycle.
5. **Cold boot/release:** build and publish a candidate tied to the final commit
   and immutable digest, stage it, and retire bench overrides only once replacement
   payloads and a recovery route are available. Physically power off/on. Verify
   booted digest, build-info, frame heartbeat, successful-boot flags, services,
   installed Tekken metadata/art, persisted play history and controller slots.
   Check startup and gameplay using the controller, and current boot journal.
6. **FDM and installation:** complete the physical controller download, minimize,
   Files/setup, game/app registration and explicit cleanup flow. Test cancellation,
   a failed setup and torrent retention. Retained multipart payloads need their
   owner-aware manifest before broader automatic cleanup can be enabled.
7. **Achievements/history:** confirm real Tekken foreground time survives app/shell
   restart, menus and recently played sorting. Use a genuine supported achievement
   source to verify progress and one newly earned unlock notification; cached or
   fixture unlocks do not establish that a real game event was detected.
8. **Bluetooth:** pairing and controller reattachment wait for the dongle. The
   unavailable-adapter state can be source-tested now; physical pairing cannot.

## Read-only release gate

Run [accept-pc1-image.sh](../scripts/accept-pc1-image.sh) on the target as root, or
from a Linux shell with `--host root@192.168.50.206`. Supply the actual published
digest and baked source commit:

```bash
bash scripts/accept-pc1-image.sh \
  --host root@192.168.50.206 \
  --digest sha256:REPLACE_WITH_64_HEX_DIGITS \
  --commit REPLACE_WITH_BAKED_GIT_SHA
```

The default reference game is the installed Tekken entry above; `--game-id` selects
another reference installation with cover/background/logo/header acceptance assets.
Play and close the game once before the gate if its history is empty. Wait for the
boot-success timer after a fresh boot. The helper reads image identity, overrides,
services/failed units, frame/audio state, metadata asset hashes, real play history,
achievement provider response and stable controller slot files/devices. It never
changes audio, sends controller heartbeats, modifies files, stages images or restarts
services. It exits nonzero on missing or mismatched evidence. Its success certifies
the listed software checks only; the physical checklist remains independently
pending until observed.
