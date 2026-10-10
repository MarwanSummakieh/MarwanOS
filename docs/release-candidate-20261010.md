# Consolidated release candidate — 10 October 2026

Branch: `codex/release-candidate-20261010`.
Review: [draft PR #8](https://github.com/MarwanSummakieh/MarwanOS/pull/8).

This candidate consolidates the October 8–10 console interface and volume popup,
native Downloads, Chromium extensions and controller panel, Windows registration,
local users with shared Steam state, controller discovery/latency/battery,
process-group Close, display-only Rest and the solid boot splash on candidate13.
NVIDIA/base/Godot/CEF pins are unchanged. Game payloads, private accounts,
bench mount overrides and development data are excluded.

The source was frozen before additional browser-login work arrived in the active
checkout. Those later edits remain outside this candidate and its test results.

## Image and source provenance

- Image: `ghcr.io/marwansummakieh/marwanos:candidate14-20261010`
- Image digest: sha256:7cc2e27d916f519f1d15bb5acb7df29860a7c7b676ab64997beccb40d2b815ab
- Image version: 0.0.202610101505
- Exact image source: `23ef47c31b13fed62adb5dbedb0aefd54d4beb6c`
- [Image build and publication](https://github.com/MarwanSummakieh/MarwanOS/actions/runs/38061751758)
- [Passing source checks](https://github.com/MarwanSummakieh/MarwanOS/actions/runs/38061752374)
- Source archive SHA-256: `2dd587f117ebcffa56c592d412609a8133af47caa970a4437907c98e2201b749`

The report is a documentation-only follow-up to the exact image source above.
The build retains backend/shell logs in `release-checks-<source commit>` and
the image digest, version, source commit and component lock in
`release-image-<source commit>`. The two earlier build attempts were cancelled
before publication while correcting the CI gates; they are not candidate images.

## Component integrity and build gates

| Component | Published checkpoint | Exported files |
| --- | --- | ---: |
| Shell | `bf2f80cfefd625dabc889d5469bb50d398e3ec61` | 214 |
| Installers | `36cff99c6de822f0874728eca919c4c9553fee30` | 17 |
| Controllers | `a444e43e68627b5edf45d9280170f8af74fe10b1` | 8 |
| Services | `e932d27341acf88ad66ebdd87054378b344d1601` | 30 |
| Legacy FDM, unchanged | `1da6976d75f30907b967f4e9fd282d4507e86a7b` | 69 |

All 338 exported files match committed blobs in their owning repositories.
Previously unowned browser, profile, Downloads and shell exports are now included.
`scripts/components.py --verify` passes on the frozen candidate locally and in CI.

Both local image builds and publication verify component pins. Publication runs
backend and shell regressions before building, installs their native dependencies,
and preserves failure exit codes through `tee`. Steam native embedding and real
window geometry are now part of the standard shell suite. Missing `xprop` support
in CI was corrected by explicitly installing `x11-utils`.

## Verification results

| Check | Result and scope |
| --- | --- |
| Backend suite, final CI | **326 tests, zero failures, two opt-in skips**; includes real aria2 HTTP/resume/torrent and compiler-dependent ELF fixtures |
| PC1 backend suite | **326 tests, zero failures, 13 skips**; all eleven compiler-dependent skips separately passed in the existing compiler container |
| Optional integrations | **PipeWire: one test passed; notification bus: three tests passed**, covering both opt-in CI skips |
| Standard shell suite | **All 20 script groups passed** on PC1 and in final CI; includes controller routing/Home, launcher Close, display-only Rest, profiles, audio/volume, metadata/history/achievements, Bluetooth, Downloads, native text input, Steam embedding and window geometry |
| Native Chromium | **Five flows passed**: engine, downloads, dialogs/upload/tab workflows, extension setup/text entry and extension controller navigation |
| Static checks | Python AST parsing passed for 68 files; Bash syntax checks and `git diff --check` passed |
| PR checks | Component pins, Windows installation and controller-shell jobs all passed on the exact image source |
| Image packaging | Passed: fresh native engine compilation/export, image assertions, packaged headless shell startup, `bootc container lint`, publication and independent registry digest verification |
| Fresh-image lifecycle | Offline controller-operated VM installation, USB-absent boot, installed reboot, shipped-service candidate13 → candidate14 upgrade, explicit rollback and return passed; six boots passed 30 health checks each, with representative file and filesystem persistence. Separate machine-ID and initial update-check defects remain; see [acceptance evidence](candidate14-installation-acceptance-20261010.md) |

PC1 tests ran under `/var/tmp/pc1-rc-20261010` in disposable namespaces with
private state/network and hidden live homes, services and devices. They did not
replace the production OS, shell or controller broker, or touch game saves.
Native Chromium ran as the player UID with its renderer sandbox enabled.
Its complete source tree matched the existing compiled bench engine; the tested
engine SHA-256 is
`de9d689c9b55bf26af5906f03fc2a8968b6b7e94b50d0a0938066fde5025ce58`.
The image build compiles its own engine; native fixture results describe the
source-matched bench engine, not a booted candidate image.

Initial Xvfb failures came from NVIDIA EGL with GPU devices hidden; rerunning
with Mesa software EGL passed all three affected native X11 groups. The extension
controller fixture initially missed a hardcoded click at 1920×1080, then passed
on its intended 1600×900 display. Initial failures and successful reruns are
retained; the final standard CI suite passed without those harness adjustments.

`bootc container lint` exited successfully: **11 checks passed, one skipped,
two warnings**. The warnings are `nonempty-run-tmp` (runtime directory content)
and `var-tmpfiles` (image-owned `/var` state without tmpfiles entries, including
the systemd catalog and random-seed files). These remain image-hygiene findings
for release acceptance; they were not treated as failures by bootc.

Local evidence is under `out/release-candidate-20261010/`: `ci-final/`,
`evidence/`, `native-controller/`, `engine-provenance.json`,
`candidate-manifest.json` and the immutable `source-final.tar`.

## Remaining release acceptance

Candidate14's own offline VM installation, USB-absent boot, normal reboot,
candidate13 → candidate14 update, explicit rollback/return and representative
persistent-data checks passed. All six boots passed 30 health checks each.
See [the installation and lifecycle record](candidate14-installation-acceptance-20261010.md)
for exact boot IDs, media and evidence.

**Software release gates remain:** the installed machine ID changes to the
baked ID of each OS image across update/rollback, splitting journal history;
and the fresh offline installation initially reports an update for its already
running digest. The post-update no-change check passes. These findings require
fixes and a successor-image retest. The media build also exposed a missing font
prerequisite; the host dependency was corrected and the remastering helper now
rejects it explicitly. This tooling fix does not change the frozen OS image.

Physical acceptance remains open for sustained multiplayer, rumble/hotplug,
Bluetooth recovery, Steam login/popups/text entry and broader games, native
Downloads through setup/play/cleanup, actual per-user saves, TV/audio recovery
and three filmed cold boots. No fresh kernel uinput/SDL hardware fixtures were
run against the occupied target. Two wireless DualSense controllers and a UGREEN
adapter are available. Display-only Rest/PS wake has earlier owner confirmation;
true suspend/controller wake remains limited by the current adapter.

PR #8 remains draft pending software and physical acceptance gates. The running PC1 installation
and the production `latest` image tag were not changed by this release work.
