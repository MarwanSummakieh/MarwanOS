# Accessible release testing — 8 October 2026

The owner requested testing the accessible parts of the six remaining release
areas. PC1 was reachable at `192.168.50.206`. This run performs read-only live
checks and automated regressions against a separate temporary source copy;
physical release acceptance remains incomplete.

## Identity and evidence

- Local source: `60f1af99fb7b14a0474eacbe3f7affcc1b0e4054` plus the existing
  uncommitted library repair and documentation changes. The tested files are
  recorded in `out/release-checks-20261008/source-hashes.json`; working-tree
  status and diff statistics are retained beside it.
- PC1 image: `0.0.202610071750`, source `a38dce1`, digest
  `sha256:fe77aebbd90092e61a2120a5a01326c4c2ea43d2d4b6abe75f1cb09b84c162fd`.
- PC1 boot ID: `697406c6-9ec5-4328-9708-308b0b3e7f55`.
- Local raw evidence: `out/release-checks-20261008/` (ignored build/test output).
- Remote test copy: `/var/tmp/pc1-release-checks-20261008`. Tests run at reduced
  CPU priority. No game launch, controller disconnection, service restart,
  suspend, reboot, upgrade or rollback was initiated.

## Results

| Check | Result | Scope |
| --- | --- | --- |
| Focused backend regressions | PASS: 143 tests, no failures, errors or skips | Windows setup/registration/icons, download receipts/cleanup, controller policy, Bluetooth, Steam integration, audio and display-mode selection; synthetic fixtures do not prove physical gameplay or actual Wine/Proton compatibility |
| Shell regression suite | PASS: all 12 scripts, exit 0 | Checksum-pinned Godot 4.7.1 in a device/state-isolated sandbox; includes Windows wizard/layout, controller, audio, metadata/history/achievements, Bluetooth and download flows |
| Live postboot software gate | FAIL: one check | Windows and shell bind overrides remain active; the other reported checks pass |
| Component integration pins | FAIL: 11 changed files | Existing working-tree fixes differ from the pinned shell, installer and service component copies; refresh pins from the corresponding component checkpoints before release |
| Bluetooth/controller inventory | Both physical DualSense pads and their application devices present | Both remembered player slots pass the postboot gate; `UserspaceHID=false` remains active after the owner's earlier reboot |
| Adapter wake capability | No advertised USB remote wake | UGREEN `33fa:0012`, USB `3-2`, reports `bmAttributes 0xc0` without Remote Wakeup and has no `power/wakeup` attribute; physical controller wake remains untested |
| Audio routing | HDMI/DisplayPort selected, unmuted | Default output and shell stream use NVIDIA HDMI audio; this does not establish audible sound or cable-reconnection recovery |
| Startup | Software startup reports 9.064 seconds | 0.808-second kernel, 4.081-second initrd, 4.175-second userspace; this excludes physical power-on/firmware and usable-Home timing, so it does not pass the three cold-boot gate |

The live gate verifies image/commit identity, active image-owned service
configuration, no failed system/player units, enforcing SELinux without a logged
enforcing denial, no recorded gamescope fault/core, shell heartbeat, boot-success
state, fresh audio/Bluetooth state, cached Tekken metadata, native input profile,
history, achievement response and controller-slot consistency. Its override
failure is expected from the documented [library repair](windows-library-20261008.md),
and remains a release failure until the repair is baked and the override retired.

The UGREEN adapter's upstream PCI wake controls are enabled, while USB root hub
`usb3` wake is disabled. These settings do not supply missing adapter wake
capability. No wake policy was changed. The current boot also records two
Bluetooth `Unexpected continuation: 1 bytes` warnings; their cause and impact
are not established by this run. Sustained two-player gameplay remains open.

Before/after snapshots span 20:52:24–20:57:10 UTC (22:52:24–22:57:10 in
Copenhagen). They retain the same boot ID and both physical/application pad
pairs; no failed system units are reported. The live Windows manager's SHA-256
matches the current local source. This short interval without induced hotplug
or gameplay does not establish long-session controller reliability.

## Execution notes

The documented `FedoraLinux-43` WSL distribution was unavailable on this host;
the installed WSL inventory contained only `docker-desktop`. PC1 already had
Python, Xvfb, D-Bus, GI, PE and controller dependencies, allowing the focused
backend checks in a temporary source copy without package installation.

An initial shell-suite invocation used isolated XDG directories but retained
visibility of PC1's live devices and installed state. The Tools test failed
when opening Browser from the top bar, then dereferenced its absent screen
and reached the test timeout. The original log is retained as `shell.log`.
A rerun uses bubblewrap to hide live input devices, runtime services, the
player's home and `/var/marwanos`, with a writable temporary test directory.
All 12 scripts pass in that environment, including the earlier failing Tools
check. This establishes environment dependence of the first failure, without
isolating which live device or saved state caused it. Final evidence is
`shell-isolated.log` and `shell-isolated-exit.txt`; the editor archive passed
the SHA-512 pinned in `os/Containerfile`. Neither run tests the real browser
engine. Godot ran headless as root in the temporary fixture, so this pass does
not establish production player-session, graphics or audio behavior.

## Remaining physical and image acceptance

| Area | Next acceptance |
| --- | --- |
| Sleep/resume and controller wake | Actual button-wake trial with this adapter; recover picture, audible sound and an existing game. The observed descriptor limitation remains unresolved |
| Controller reliability | Sustained two-player play, disconnect/reconnect each pad without player swaps, and physical rumble cancellation in Home |
| Download → install → play | Physical FDM completion through setup, automatic registration, gameplay and installer cleanup; retain torrent/multipart payloads according to policy |
| Steam compatibility | Controller-only account sign-in and more owned titles through gameplay, Home, minimize/resume and normal Close |
| TV/audio and startup | Display cable/TV reconnection, audible output and saved output persistence, then three filmed physical cold boots at or below 15 seconds |
| Release packaging | Checkpoint component copies and pins; bake the library repair and account for the installation-local Bluetooth setting; retire the library override on the replacement image; verify fresh installation, USB-absent boot, update and rollback with user data preserved |

The Bluetooth transport change is still an installation-local configuration,
not a repository-wide image default. Its scope and recovery evidence are in
[the incident record](bluetooth-controller-recovery-20261008.md). The prior
[October 7 full-bench report](full-bench-test-20261007.md) remains dated evidence;
its missing-hardware inventory does not describe the current two-pad bench.
