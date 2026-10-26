# Candidate12 replacement image — October 7, 2026

Status: superseded by candidate13 after hardware boot acceptance found two
issues. Candidate12 is retained as failure evidence, not an accepted replacement.

The owner requested a replacement image incorporating the current NVIDIA
display and controller repairs, followed by full reboot and fresh-installation
verification. The source is `89b2f099c670bcd6d387d5be0624634117a97eb2`, from
`codex/automatic-game-metadata`. The build is
[GitHub Actions run 37654016101](https://github.com/MarwanSummakieh/MarwanOS/actions/runs/37654016101),
publishing candidate tag `candidate12-xorg-controller-20261007`.

## Included changes

- Accelerated Xorg on connected NVIDIA displays, with matching Xorg/GLX modules
  from the pinned NVIDIA 610.43.03 sidecar and the fastest advertised progressive
  refresh at the preferred resolution.
- Controller force-feedback callback handling, discovery deadlock avoidance,
  native application-device removal/recreation, physical model identities and
  exclusion of Steam Input's translated virtual pads from hardware capture.
- Steam shortcut deduplication and the native Big Picture launch helper.
- Candidate11's gamescope Vulkan teardown repair remains packaged for the
  backends that use gamescope.

## Source validation

CI ran 250 backend tests: 248 passed and two optional checks skipped. The
controller shell gate also passed before image compilation.
Exact-source component-pin verification passed. Real Linux uinput checks passed
for exclusive capture, independent player slots, input gating, held-control
suppression, rumble operations, retired callbacks, pending force-feedback during
discovery, game-visible disconnect/reconnect and continued input for another
player. Real SDL checks passed for DualSense, Xbox 360 and unknown-model mapping.

A separate Xorg reboot evidence helper rejects unchanged boot IDs, missing stop
completion, wrong image digests, kernel-only crashes, forced kills and missing,
mismatched or failed journal queries. This validates the helper, not a machine
reboot. An offscreen GLX renderer/pixel probe passed its local Mesa smoke test;
hardware acceleration still requires the actual NVIDIA result.

## Image, installation and reboot results

Published image:
`ghcr.io/marwansummakieh/marwanos@sha256:54a694afb4638d5f98f963f197db117e5c0b681130f69ec77e400a0b40160fb5`.

The registry manifest digest was independently recomputed. The image's controller
router, session, scanner, udev rule, refresh helper and NVIDIA Xorg configuration
all match their exact source hashes. The installed image packages are
`xorg-x11-nvidia-610.43.03-1.fc43`, `nvidia-driver-610.43.03-1.fc43` and
`gamescope-3.16.23-1.pc1.3.fc43`.

Raw and branded ISO generation completed. Checksums, raw GPT, appended EFI
partition, embedded ISO checksum and runtime directory permissions passed.
The offline installer booted with a private blank 80 GiB disk and controller
fixture. It was stopped before installation when the corrected candidate13
became the acceptance target.

PC1 received the immutable candidate12 image and rebooted from candidate11 into
boot `5ec09fe6-644a-49a5-8194-9e3e39ec93fa`. NVIDIA GLX reported direct RTX 3070
rendering with driver 610.43.03 and the expected rendered pixel. DP-2 selected
3440×1440 at 174.96 Hz. SDL saw one correctly identified routed DualSense and
excluded the physical input node. The image acceptance gate passed all checks
except an enforcing Plymouth `dac_override` denial.

The owner reported a maintenance/login prompt and pressed Enter to continue.
The journal showed `/boot` and `/home` device timeouts before emergency mode.
The obsolete machine-local `marwanos-nvidia-xorg-hotfix.service` ordered itself
after `local-fs.target` and before `systemd-udev-trigger.service`, delaying device
coldplug until the mount jobs timed out. Its image-hash ExecCondition skipped
the payload but did not remove its ordering dependency. Both obsolete hotfix
services were backed up under `/var/lib/marwanos/hotfixes/retired-20261007` and
disabled. A subsequent full reboot reached boot
`362864da-64dc-4873-bd48-328ab53478d6` without emergency mode or mount timeout;
system startup completed in 9.842 seconds.

The remaining Plymouth denial occurred when the old gamescope link-scrub
workaround ran against Xorg, needlessly restarting the session and waiting
20 seconds for gamescope. Commit `a38dce115dac453db2ffe35a38782492e02c7f60`
skips that workaround when no gamescope session is running. Regression tests
cover preserving Xorg, ordinary gamescope cleanup and cleanup failure recovery.
[Candidate13](candidate13-replacement-20261007.md) subsequently passed fresh
installation and full reboot acceptance. Candidate12's manually resumed first
boot is not a passing result.

Local evidence and acceptance helpers are retained under
`out/release-20261007-candidate12`. The exact clean Linux source checkout is
`/var/tmp/pc1-release-source-89b2f09`. No physical USB flash or physical-disk
reinstallation is part of the disposable VM installation test. Physical display
motion, game hotplug/rumble, Bluetooth, multiplayer and filmed power-on timing
retain their separately documented acceptance scopes.
