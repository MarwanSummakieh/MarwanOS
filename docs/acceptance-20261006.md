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

The genuine embedded-browser 7-Zip download then exposed a separate destination
gap: without `user-dirs.dirs`, Godot returned the player's home instead of
Downloads. CEF saved the correct installer there, and the worker correctly
rejected that path outside its Downloads boundary. The browser now uses the
same `HOME/Downloads` root as FDM and the installer worker, including Open Downloads.
Missing/custom desktop-folder checks pass, and the real CEF fixture passes with
correct downloaded bytes and no destination override. A final candidate must
include this shell correction before genuine download/setup/cleanup acceptance.

Candidate one's software timing was 12.910 seconds from kernel start through
systemd startup. The explicit first shell frame occurred at 14.545 seconds and
the three-card library at 16.480 seconds after kernel start. Firmware, bootloader
and physical power-button/display timing remain unmeasured; this does not pass
the original 15-second cold-boot requirement.

Image-owned offline metadata acceptance also passed on candidate one: with no
pending metadata requests, only its metadata unit was paused and the worker ran
once as player in an isolated network namespace, bounded to 45 seconds. It exited
successfully; provider 1778820, title, facts, full description and all artwork
hashes/paths/sizes stayed unchanged. Status remained `ready` through intentional
cache reuse. The normal worker was restored active, and host networking was
unchanged. This proves cached offline availability, not a forced network-refresh
failure. Sleep testing remains deferred at the owner's explicit request.

The current shell was also rendered locally with Tekken's actual PC1 metadata,
four hash-verified cached artwork files and recorded session at native 3440×1440
(canvas 2580×1080). Inspection confirmed an edge-to-edge dimmed backdrop, roomy
facts/artwork/history area, scrollable full description with L1/R1 hints and one
Play action. This is isolated Xvfb rendering evidence, separate from physical TV
observation. Screenshots are local ignored artifacts under
`out/tekken-current-render/`.

## Candidate three and remaining defects

The final-browser candidate was published and booted as
`ghcr.io/marwansummakieh/marwanos:pc1-candidate-20261006-3`, baked commit `b87b1ac`,
digest `sha256:74b1ec8df6c66572d1e76e2e2021b280ddd0ad6f0d243d042526e15629706a0b`,
OSTree `ce20b2f948eb964008fe8e822c3b61f9541720ffcc8bf6b58b365f363f20a576`.
The tightened postboot software gate passed with zero failures, including exact
identity, ancestor/exact/child mount override checks, image-owned unit/drop-in
configuration and actual shell/broker process paths. Bluetooth reports a fresh,
error-free `no-adapter`. The owner explicitly chose to continue without sleep
testing; no suspend was performed.

The embedded browser genuinely downloaded official 7-Zip 26.04 through its
controller keyboard to `HOME/Downloads` despite absent `user-dirs.dirs`.
The 1,664,082-byte installer has SHA-256
`d54bf805f9f3704d1e8db2fa3498ae7ef2df0312b40b558e7c71c734430a665d`.
Its real completion callback created a ready receipt, and Install opened guided
setup. Installing succeeded visibly, but Close destroyed the window while the
installer remained active. Its modeless GetMessage loop did not advance after
the bridge's synchronous foreign-thread BM_CLICK. The owned test was stopped
through Home → Setup options → Stop; job `local-134543796-912047650` reports exit
241, so its source remains retained and cannot authorize successful cleanup.
The queued-button correction and real modeless regression now pass on PC1's
installed UMU-Proton runtime in an isolated prefix/display, including the actual
production bridge's finished state and genuine child/bridge exit zero. The
successful browser/install/cleanup lane must still be repeated on its baked image.

Candidate four's pre-build Tools check exposed a fixture race: its fake native
pad was not registered with SDL, so normal PlayerOne reconciliation released it
before the keyboard-movement assertion. The production disconnect guard remains
intact. The fixture now uses real broker snapshot dispatch and explicitly checks
identity, held-axis movement/focus and release across the reconciliation interval.
The separate metadata page's heading was also checked visually at supported
resolutions and corrected before the replacement bake.

Candidate three also recorded gamescope PID 1527 SIGSEGV during the intentional
first-boot display link scrub at 20:29:55 UTC. The compositor had already reached
ready; the image-owned scrub stopped greetd, performed its Plymouth modeset and
restarted the session at 20:30:03. The core stack is in CVulkanDevice teardown/
exit handlers, matching an older boot's defect. Recovery produced a stable
3440×1440 session, but this remains a real release/hardware risk. The passing
read-only gate does not mean a fault-free cold boot.

## Candidate five: final postboot and metadata acceptance

The replacement build succeeded in [run 37529881962](https://github.com/MarwanSummakieh/MarwanOS/actions/runs/37529881962).
The published and booted image is
`ghcr.io/marwansummakieh/marwanos:pc1-candidate-20261006-5`, source
`0be4ae6b5ccef16a13691644c0e9cbf5da66c648`, immutable digest
`sha256:f37a5d2ed8fa795dde5fc1235e19da5d76d7deeaae9bf8c6bd6bc767d44c0cbd`,
OSTree `422e9bd8f2f5810c9ec863fdf99be7e711a0a2c70df6e580796781f4eb3ff513`.
After the already-approved idle reboot, boot ID was
`3491f18f-b63f-47d0-ae9c-2ba908c23638`; shell PID 2107 and controller broker
PID 1963 execute their image-owned files. The tightened postboot gate passed
with **zero failures**. The initial check preceded the normal boot-success
timer and reported only pending GRUB success; the completed timer check passed.
All workers, their unit configuration, cached assets, native Tekken input,
history and four virtual controller identities passed without bench overrides.
Bluetooth correctly reports `no-adapter`. No suspend was performed; the owner
explicitly deferred that test.

Native gamescope output captures at **3440 × 1440** were inspected on this
actual image. Tekken's library and Details show the cached artwork and history;
the backdrop fills the screen, facts have room, and **Play is the sole Details
action**. Options opens the separate **TEKKEN 8 · Metadata** page, displaying
Steam Store app 1778820 and a focused Refresh action. The heading and controls
are visible; Back restores the Play action and then the same library card.
These are actual PC1 rendered frames, observed using keyboard-equivalent input
through the controller-oriented UI, rather than a new physical-pad test.

Activating Refresh created actual atomic request `2107-158876926.json` for
`managed.local-tekken8-fresh-1791234744`. The read-only observer captured that
request and the transition from loading (`attempted_at` 1791321468.7333775)
to ready (`fetched_at` 1791321469.755908). The image-owned worker freshly fetched
the provider data and four artwork files; all recorded sizes and SHA-256 values
matched. Provider 1778820, the full native-controller Windows manifest and the
one completed **122.453-second** session remained unchanged. The reboot and
manual refresh therefore preserve the installed game's identity and history.

Ignored evidence files are `out/candidate5-postboot-gate.log`,
`out/candidate5-metadata-refresh.log` and the
`out/pc1-candidate5-*-native.png` / `*-restored.png` captures. The earlier offline
cache reuse and supported-resolution render tests remain separate evidence.
The passing software gate does not certify the known compositor teardown
defect or the remaining physical release gates.

The existing teardown defect reproduced on this boot: first gamescope PID 1513
segfaulted at 21:14:59.934 UTC after link-scrub stopped greetd. Its stack again
contains the Vulkan-device destructor and exit handlers. The scrub completed
and the replacement session returned at 21:15:09.204. No failed units or kernel
GPU Xid/fallen/AER errors were observed in the independent 21:20:39 inspection.
This recovered boot is not a crash-free or physically timed cold-boot pass.

## Candidate five: genuine download, installation and cleanup

The actual embedded browser received the official 7-Zip 26.04 installer URL
through its controller-oriented keyboard UI using keyboard-equivalent input.
With no `user-dirs.dirs` workaround, its genuine completion callback saved
`/var/home/player/Downloads/7z2604-x64 (1).exe`, preserving the cancelled
canonical download. The new file was 1,664,082 bytes with official SHA-256
`d54bf805f9f3704d1e8db2fa3498ae7ef2df0312b40b558e7c71c734430a665d`.
Receipt `37812078250bcea37eb0fe46eaae6b7339e431976b3e19bd72ddfc63aa3677da`
was created at 1791321617.4770527. The real Download ready → Install choice
started new guided job `local-396346430-3825640790` at 1791321705.4516664.

The actual setup Install button reached 107/107 progress. Close then returned
the genuine installer exit **0**; the same-job bridge published
`finished=true`, `exit_code=0`, without a blank-window success heuristic or
process kill. The controller setup offered its three executables. Explicit
**Add 7zFM as app** registered an application with pointer input in the new
isolated prefix, and the receipt became installed with that new job ID.

Returning Home offered **Keep downloaded files** by default. The distinct
**Remove downloaded installer files** action was selected and explicitly
confirmed through the UI. Read-only verification passed with **zero failures**:
the exact new source was removed, while the installed `7zFM.exe`, old cancelled
canonical installer and all recorded Tekken/FDM files remained intact. The
historical exit-241 job stayed distinct and unsuccessful; it never authorized
cleanup. Tekken kept its native controller profile and exact one-session
122.453-second history; the 7-Zip application created no game-history record.

After cleanup, the registered app launched through its library card into a
real foreground 7-Zip window. Home → Minimize preserved `7zFM.exe` PID 27646;
the card resumed the same process, and Home → Close ended launch wrapper
PID 27319 and returned to the shell. The pointer bridge activated for this
application. Preservation and history checks passed again after that cycle.
The installed test app remains available in the library for review.

Evidence is under ignored `out/candidate5-browser-keyboard-download.log`,
`candidate5-genuine-setup-close.log`, `candidate5-genuine-download-cleanup.log`,
`candidate5-post-cleanup-app-lifecycle.log`,
`candidate5-cleanup-after-lifecycle.log` and native setup/registration/cleanup
captures. This validates the actual **browser** lane on the baked image.
FDM's physical-button completion/continuing-transfer lane remains separate;
no physical controller, sound or suspend acceptance is inferred from these
keyboard-equivalent events. Final media installation is recorded separately.

## Candidate six preparation: source checks, not runtime acceptance

The official anonymous Steam catalog returned Tekken's 47 unique internal IDs,
names, descriptions and colored/gray icons. The automatic fallback validates
complete rows and declared per-group totals, caches the catalog, and keeps public
bounds separate from genuine personal progress. PC1's schema cache remained absent
before this change; its real RUNE record still contained only `Count=0`. No schema
or earned achievement was seeded. The next image must fetch it automatically and
prove the page's names/icons/total; an earned unlock remains a separate test.

The NVIDIA-only gamescope launch now trials the upstream loader-library lifetime
option. The session removes it from inherited client environments, preserves
ordinary SIGTERM/core reporting and leaves the display reset intact. Three real
child-process tests pass. This establishes scope and argument/PID handling, not a
successful physical Vulkan teardown. See [display teardown](display-teardown.md).

The candidate-five branded installer VM exposed inaccessible runtime directories:
a private builder-config umask leaked into SquashFS extraction, making shared
directories mode 0700 and preventing D-Bus startup after privilege dropping.
The failed ISO, journal and VM evidence are retained. Remastering now uses 022 and
rejects inaccessible critical directories while preserving private SSH modes.
Two tests using actual SquashFS tools pass, including an intentionally inaccessible
source. CI installs those tools before running the regressions. A corrected
diagnostic remaster and final committed-source media still need real installation
and installed-disk boot acceptance.

The integrated Linux backend suite passes **192 tests, with two optional skips**.
These source checks do not replace the pending next-image runtime/media checks.
Suspend/resume testing remains explicitly deferred by the owner.

## Candidate six: automatic catalog passes; NVIDIA teardown still fails

The actual PC1 reboot booted source `70faf40b94991afd88b3574ffe803cb5e5b85bb2`,
version `0.0.202610062158`, from candidate6 digest
`sha256:c0f9eea14bcfafe507bacf745644f8d041cf627474e605acfaf406572fea6f47`.
Its OSTree checksum is
`a739cb941d07239b24afcee224443cc9d868c4ec670b34a6d11633427a44ac56`.
The tightened postboot software gate passes with zero failures after the boot
success timer. The gate compares the embedded short source literally: use
`--commit 70faf40`; the full commit is independently tied to the published build.
No application overrides, development flags or failed units are present.

From an observed absent schema cache, the image-owned achievement worker
automatically fetched Tekken's 47 official definitions during its normal retry.
No explicit UI Refresh or schema seeding supplied them. Verification compares
all 47 unique IDs, names/descriptions and decoded cached icons with the genuine
official response. The existing RUNE `Count=0` save is byte-for-byte unchanged;
there are zero observed unlocks and no schema-only achievement notifications.
Actual 3440×1440 captures show the separate **0/47 unlocked · RUNE local** page,
All/Locked/Unlocked filters, and the roomy Play-only Details page. The earned
unlock check below followed this silent catalog baseline.

Ordinary keyboard gameplay then dealt **2,020 actual damage** in offline Practice.
At **22:57:33 UTC**, Tekken itself wrote `Practicedamage` with `Achieved=1` and
`UnlockTime=1791327453`; its indexed RUNE count changed from zero to one. The
image-owned worker detected **No pain, no gain!** at 22:57:35 and the normal
notification service persisted exactly one achievement notification, ID2.
Actual native captures show **1/47 · RUNE local · Unlocked**, its genuine colored
icon, description and matching timestamp. Controller-equivalent Refresh and an
ordinary image-owned achievement worker restart preserve the record and single
notification without replay. No achievement/save/event was injected or edited.
The temporary keyboard advertised no joystick capabilities, enforced the actual
focused Tekken process/window, bounded every hold, and released/destroyed itself.
The coordinator-owned Practice test was normally closed through the shell.

This uncovered a real presentation gap: the shell deliberately suppresses
notifications while an application owns the screen. The earned event and durable
inbox pass, but **in-game toast presentation fails** on candidate6. A passive,
non-focusable native overlay correction needs source and baked acceptance before
the achievements issue can close. Replaying the earned notification is not a
substitute for another genuinely earned event after that correction.

The scoped Vulkan-loader environment trial **failed**. Original gamescope
PID1468 had the flag set but produced a SIGSEGV/core at 22:20:01 UTC during the
first link scrub. Display release, splash and replacement PID2035 succeeded.
There are no NVIDIA Xid/fallen-off-bus/AER matches. Recovery and the normal
software gate do not certify a crash-free boot.

Matching executable disassembly and core/live mappings identify the saved
`FreeCommandBuffers` target in NVIDIA's `libnvidia-eglcore.so.610.43.03`; that
library had disappeared from the first process at the fault. The next source
patch retains that specific already-loaded dispatch owner inside gamescope
using `dladdr` and `RTLD_NOLOAD | RTLD_NODELETE`. It removes the failed loader
environment trial, keeps file capabilities, normal shutdown and core reporting,
and changes no client loader environment. Five real ELF regressions pass,
including a negative control that actually faults after library unload and a
retained case that exits normally. Exact Fedora source RPM preparation applies
the patch with zero fuzz. A new baked NVIDIA boot is still required; see
[the teardown investigation](display-teardown.md).

The separately labeled corrected candidate5 diagnostic installer completed an
actual offline installation through evdev controller input and booted its
installed target with the USB/ISO absent. Its 13 runtime checks pass with SELinux
enforcing, zero failed units, image-owned workers, a fresh shell and successful
boot flags. This validates the installer permission remedy on that diagnostic
build. Its earlier kernel-only AVC query is insufficient to establish a clean
full-journal AVC gate; preserved candidate5 evidence now marks that claim
unverified. Candidate6 raw/ISO media were generated from a clean exact `70faf40`
checkout and immutable image. Their actual offline controller installation,
USB-absent installed-disk boot, exact identity, fresh shell/Settings, healthy
workers and GRUB successful-boot flags pass. Full audit review caught an enforcing
Plymouth `dac_override` denial, so its final media health gate is **12 pass / 1
fail**, not a validated release. The normal final quit reopens `/dev/tty1` after
greetd changes its owner to player/0600. An actual Enforcing VM comparison proves
`quit --retain-splash` exits without that terminal reopen or new denial, while
preserving greetd/readiness. The narrow source change and two lifecycle regressions
require a new baked image; no terminal permission or SELinux policy is loosened.
See [Plymouth cleanup](plymouth-cleanup.md). None of these VM checks establishes NVIDIA physical
teardown, physical vibration/audio, cold-power timing or Secure Boot acceptance.

The fully compiled production gamescope helper subsequently passed all 287
compile/link targets, RPM packaging and exact version checks in a bounded
disposable Fedora build container. No resulting RPM was installed on PC1.
Candidate7's image build failed before compilation because `.containerignore`
excluded the new helper; a real tiny Podman build confirms the corrected context
now includes both new COPY inputs. Candidate8's superseded build was cancelled.
The next image combines dispatch retention, Plymouth cleanup and passive
achievement toast presentation. No new baked-runtime pass is claimed yet.

The release gate now checks SELinux Enforcing and all journal transports for
enforcing denials, plus the current boot's gamescope SIGSEGV/core records. Earlier
zero-failure results apply to the checks in their dated versions; they did not
certify these newly explicit gates. Permissive-domain audit records are distinct
from denied enforcing accesses and are not silently turned into policy grants.

Suspend/resume remains explicitly deferred: the owner chose **Continue without
sleep testing**. No sleep cycle was performed or reported as passing.

## Earlier read-only hardware inspection

Before candidate deployment, the physical PC1 at `192.168.50.206` was inspected without deployment, reboot,
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
services/failed units, full-journal enforcing AVCs/compositor crashes, frame/audio state, metadata asset hashes, real play history,
achievement provider response and stable controller slot files/devices. It never
changes audio, sends controller heartbeats, modifies files, stages images or restarts
services. It exits nonzero on missing or mismatched evidence. Its success certifies
the listed software checks only; the physical checklist remains independently
pending until observed.

## Candidate9 outcome and candidate10 cleanup preparation

A later read of candidate6 accepted its full source SHA while correctly reporting
three failures: the existing compositor core, the enforcing Plymouth denial, and
a newly failed `rpm-ostreed-automatic.service`. The latter failed at 23:27:04 UTC
because its saved container origin combined a tag and digest, a form rejected by
the container parser. No failed state was cleared to obtain a passing gate.

`make-installer.sh` now passes digest-only pinned references to the image builder.
Five regressions run its actual entrypoint with a disposable image-builder boundary;
they verify the resulting arguments, registry ports/namespaces, unchanged tag-only
behavior and rejection of malformed pins before privileged operations. These tests
passed, but alone do not establish an installed image's origin. Candidate9 was
subsequently staged with a digest-only reference; actual updater-stage execution
passed. Future staging and fresh release media must preserve this origin form.

The postboot helper now also rejects journal-query errors and timeouts instead of
mistaking them for an empty fault list. Eight focused regressions exercise its
actual embedded journal functions, legitimate no-match results, unreadable records,
retained AVC/core evidence and full source-SHA matching. All eight passed locally.

Candidate9 source `3ff89cfeb569ba7bf85624ba84c232dbe5242853` published digest
`sha256:e7c02f596fa3909c8e4a30de35ab477fcf158439ed3644014de6c409b2c6fc6d`.
Its [image build](https://github.com/MarwanSummakieh/MarwanOS/actions/runs/37551813075)
succeeded and [source checks](https://github.com/MarwanSummakieh/MarwanOS/actions/runs/37551809873)
passed 210 backend tests with two optional skips, all headless shell fixtures and
component pins (148/17/7/23/69). Actual postboot full-journal SELinux audit and
updater-stage execution pass. The strict gate still fails one check: current-boot
NVIDIA gamescope teardown core1508. Dispatch retention succeeded, but the new
stack faults in mapped `glsi+0x402cd` at null state + 0x40, through eglcore,
`CVulkanTexture` and global `VulkanOutput_t` destruction during exit handlers.
The shell recovered; no core or failed state was cleared to produce a pass.
Candidate9 release media is on hold.

The automated candidate9 hardware audit reports both NVMe SMART checks passing
and zero kernel hardware-fault matches. Recorded software boot time is 9.922
seconds, without establishing a filmed physical cold-boot measurement. NVIDIA
probe remains partial because `nvidia-smi` is unavailable. The passive toast's
local headless and native tests pass at 1280×720, 1920×1080 and 3440×1440; genuine
baked foreground-game toast QA is still pending. The prior actual 1/47 unlock,
single persistent notification and restart deduplication evidence remain valid.

Candidate10's released `.pc1.2` cleanup header/patch targets NVIDIA on the DRM
session backend. It runs in ordinary compositor shutdown after commit/LUT/focus
cleanup and before backend removal: drain submitted work, free pending and
cached command buffers, then release upscale/effect and output texture owners
while driver state is alive. Normal signals, return and finalizers remain; the
change adds no Vulkan device/instance destruction. Ten focused regressions and
exact official SRPM preparation with `--fuzz=0` pass. Full candidate10 compilation,
exact integrated source/publication, baked NVIDIA boot and fresh release media
acceptance remain pending. The owner requested automated checks only; no further
physical or sleep testing is requested, and physical acceptance remains unclaimed.
