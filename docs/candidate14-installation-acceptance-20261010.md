# Candidate14 installation, update and rollback — October 10, 2026

Status: VM installation, boot, upgrade, explicit rollback and return passed;
release acceptance remains blocked. Candidate14 remains a draft: a machine-ID
persistence defect and a fresh-install update-check defect were found. Physical
acceptance remains separate. The running PC1 installation and public image tags
were not changed.

## Exact inputs and isolation

The tested OS is `ghcr.io/marwansummakieh/marwanos:candidate14-20261010`, version
`0.0.202610101505`, built from `23ef47c31b13fed62adb5dbedb0aefd54d4beb6c`:

`sha256:7cc2e27d916f519f1d15bb5acb7df29860a7c7b676ab64997beccb40d2b815ab`.

The update/rollback baseline is candidate13, source
`a38dce115dac453db2ffe35a38782492e02c7f60`:

`sha256:fe77aebbd90092e61a2120a5a01326c4c2ea43d2d4b6abe75f1cb09b84c162fd`.

An offline Anaconda installer was built using immutable bootc-image-builder
`sha256:2b52843ea2bfda73b0a08d97e76b734393b1d3a804681b9fabb26723bd3a2f0b`.
It was branded with the exact image-source scripts. The original test ISO SHA-256
is `15372ffac307cdc03dd7774a2a347ce01bc3ea8f680d5f9d794e4179dc88c9ed`.
EFI GPT/appended-partition validation and the embedded media checksum passed.

Tests ran in QEMU/KVM under an isolated Fedora 43 WSL environment on the Windows
build host: q35, UEFI with Secure Boot disabled, four virtual CPUs, 4 GiB RAM and
an initially blank 80 GiB qcow2 disk. Both pre-setup and pre-Begin-Installation
disk maps reported the entire disk unallocated. The installer had no network;
the sole target disk and read-only virtual USB were its only storage inputs.
All setup input came through a forwarded synthetic uinput controller and the
shipped installer bridge. QMP provided observation and VM lifecycle control.

The installer reached **Complete / Ready to play**. It powered off cleanly, and
the installed disk passed `qemu-img check`. Subsequent testing used an overlay
backed by that retained fresh installation, with no installer USB/ISO attached.

Test media enabled SSH with a disposable key for diagnostics; it is not a
production distribution artifact. Installed-VM networking supplied localhost
SSH and a private registry. No live PC1 storage, homes, controllers or services
were attached. Development mode and image-payload bind overrides were absent.

## Installed lifecycle results

Each recorded boot ran 30 health checks after at least 130 seconds uptime:
exact image digest/source, running system, active image-owned session/update and
player services, no failed units, fresh rendered-frame heartbeat, enforcing
SELinux without enforcing denials, no current-boot cores, installed filesystem
UUIDs and GRUB boot-success/hidden-menu markers. These health checks do not
include machine-identity persistence; its separate failure is recorded below.

| Phase | Boot ID | Result |
| --- | --- | --- |
| Fresh candidate14, USB absent | `cad672e8-bfed-4583-9fe8-dfb63727854f` | 30/30 health checks passed |
| Normal candidate14 reboot | `aaf8b131-79e1-44b1-b884-f992a564fa9a` | 30/30 health checks passed |
| Candidate13 update baseline | `5a4f163c-5799-409e-b455-c3a3b22c1639` | 30/30 health checks passed |
| Upgrade to candidate14 | `86a54922-2fd3-4510-baf7-1c230de3a26b` | 30/30 health checks passed |
| Rollback to candidate13 | `d5eef475-a489-4c7a-bbcd-5c0a1850edce` | 30/30 health checks passed |
| Return to candidate14 | `52bc742d-37d6-4e4a-b02e-d097b604b314` | 30/30 health checks passed |

The private registry preserved the original manifests/digests. Its test-only
`track` tag first pointed to candidate13, then to candidate14; no public tag was
moved. The shipped `marwanos-update.service` consumed player-owned `check`,
`apply` and explicit `restart` requests. Check found the newer digest without
staging it. Apply staged candidate14 while candidate13 kept running, including
a further ten-second no-reboot observation. Only restart activated it.

`bootc rollback` queued the previous deployment without immediately changing the
running image. Explicit restart booted candidate13; a second rollback and restart
returned to candidate14. Both passed health and persistence checks. The final
update check correctly returned `up-to-date`, with no staged deployment.

Four representative persistence fixtures cover a player Downloads payload,
player save-like file, `/var/lib` state and `/etc` configuration. Their contents,
SHA-256 hashes, ownership and modes survived reboot, rebase, upgrade, rollback
and return to candidate14.
The `/sysroot`, `/boot` and `/boot/efi` UUIDs and `/etc/fstab` hash also remain
unchanged. This is filesystem evidence, not acceptance of actual game saves,
Steam accounts or profile isolation.

Installed shell rendering and synthetic-controller profile selection passed.
VirGL QMP screendump has no surface; screenshots use the VM's private Xvfb/SDL
window. Those screenshots do not establish NVIDIA/TV performance or physical
controller behavior.

## Software findings

**Machine identity changes across OS deployments — release blocker.**
Candidate14's `/etc/machine-id` equals its image-owned `/usr/etc/machine-id`:
`1fe5446338ee47dd8febe6d602dead0b`. Candidate13 has
`2c6732795598451888ff453b7f9333e4`. Switching to candidate13 changed the installed
machine ID to the latter; upgrading to candidate14 restored the former, and
rollback selected candidate13's ID again. `/var/lib/dbus/machine-id` follows it.
This is an image-derived identity, rather than a stable host-generated identity.
Future image cleanup and migration must preserve existing installed identities;
fresh-install uniqueness and update/rollback identity need explicit regression
gates before a successor candidate is accepted.

This also split persistent journals into two machine-ID directories. A default
`journalctl -b -1` on candidate13 initially could not find the previous
candidate14 boot. The journals were retained, not lost: directory-specific
reads recovered both histories. Completed shutdowns have normal shutdown-target
and journal-stop records, without segfault/core, forced-SIGKILL or stop-timeout
matches in all five completed prior boots. The final running boot was exported
before poweroff; its final shutdown journal was not read back offline.

**Fresh-install update check reports an update for the running digest.**
On the fresh offline installation, `bootc upgrade --check` itself reported
“Update available” with candidate14's exact running digest. The shipped worker
therefore published `available` instead of the expected `up-to-date`; no staged
deployment resulted. The raw bootc output and failed expectation are retained.
The post-update no-change check passed after the registry upgrade/rollback
sequence. The initial offline-install false positive still requires a software
fix or normalization of the offline import, followed by a fresh-image retest.

**Installer font prerequisite corrected.** The new build host initially lacked
`dejavu-sans-fonts`. `grub2-mkfont` nevertheless exited successfully with a
150-byte empty font, producing a nonfatal GRUB “invalid font file” warning.
Installation still completed. Installing that build-host dependency generated
the real font; remastering only that file produced corrected test media SHA-256
`b65b1542177b0148498e73610e9ee5d52ffabd359fbed14afdb232c53b55067b`.
Its EFI layout and refreshed embedded checksum passed, and a second UEFI VM
boot reached the branded installer GUI without the font warning. Only the font
was remastered; installation/lifecycle testing used the original ISO above.
`make-branded-installer.sh` now rejects a missing/empty/unreadable source font
before remastering. A private mount-namespace negative check and Bash syntax
check passed. This media-tool change does not change the candidate14 OS image.

The earlier two nonfatal bootc lint warnings (`nonempty-run-tmp`,
`var-tmpfiles`) remain recorded in the [candidate report](release-candidate-20261010.md).

## Still requires physical acceptance

| Area | Required physical checks |
| --- | --- |
| Installation and boot | Real USB/firmware boot and removal, spare-disk installation, normal shutdown/reboot, three filmed cold boots and silent display transitions |
| NVIDIA and TV | RTX 3070 acceleration, TV modes/refresh, no corruption or flicker, game/Home/Steam handoffs and display reconnect |
| Controllers | Sustained two-wireless-pad multiplayer, player ownership, all-pad Home, latency/battery, rumble, hotplug/reconnect and Steam Input recapture |
| Bluetooth and wake | UGREEN pairing/trust/codes/removal/recovery, reconnect and PS wake; true system-suspend wake remains limited by the adapter and unaccepted |
| Audio | Audible HDMI/TV output, volume/mute/default-device persistence and recovery after disconnect/rest/wake |
| Steam and games | Real account login/popups/text entry, embedded Stores route, representative game compatibility, focus/minimize/resume/Close and sustained gameplay |
| Downloads and profiles | Real download → EXE/MSI setup → play → cleanup, interruption recovery, actual per-profile saves and Steam/account isolation |
| Hardware endurance | Thermal/load/stress and firmware acceptance |

Earlier owner-confirmed display-only Rest/PS wake does not establish fresh
candidate14 hardware acceptance. Later browser-login work in the active checkout
was excluded from this frozen image and is not covered by these results.

## Evidence and disposition

Local evidence is under
`out/release-candidate-20261010/installation/evidence/`: disk maps, installer and
installed screenshots, synthetic input trace, per-boot health JSON, stage/check/
rollback logs, file persistence checks, identity/journal findings and media
provenance. Exported media logs omit repetitive checksum progress only; the
export manifest retains raw-log hashes/sizes. Original logs, test media and VM
disks remain under `/var/tmp/pc1-candidate14-acceptance` in the Fedora WSL lab.
The disposable private SSH key is excluded from exported evidence.

The exported evidence/harness bundle is
`installation/candidate14-installation-evidence.zip` (2,286,195 bytes), SHA-256
`df960f75f8635fa00854059f76e60892fcd027dca306f9b51091c6a6ed7bba1b`.

The installed VM powered off through the shipped worker, QEMU exited zero, and
the final qcow2 passed consistency checking. The corrected-media boot VM,
synthetic controller fixture and private registry were also stopped.
The retained VM still references
the private test registry; it is not a deployable production installation.
[PR #8](https://github.com/MarwanSummakieh/MarwanOS/pull/8)
stays draft. The software findings must be resolved and retested before release;
physical testing remains necessary after that.
