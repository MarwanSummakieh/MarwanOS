# Candidate11 NVIDIA teardown acceptance — October 7, 2026

**NVIDIA normal-exit blocker: PASS on PC1.** Candidate11 completes ordinary
SIGTERM both before and after real game/screenshot use, and normal shutdown
during a full reboot. Candidate10's failure remains preserved as historical
evidence. This result does not promote the whole OS to release-ready status.

## Image and hardware identity

- Source: `cc199319111e0fe7e52f558b2f04b8cfb7dbd53e`.
- Image: `ghcr.io/marwansummakieh/marwanos@sha256:a271f2ba2dedab79a5405c86e3a356dd4673208be468ec6a0afe62885623806b`.
- [Successful image build and publication](https://github.com/MarwanSummakieh/MarwanOS/actions/runs/37611772871).
- Patched compositor: `gamescope-3.16.23-1.pc1.3.fc43.x86_64`, with
  `cap_sys_nice=ep` preserved. The staged source, RPM and immutable digest were
  checked before booting.
- PC1 NVIDIA RTX 3070, selected Vulkan device `10de:2488`, driver `610.43.03`.
- First candidate11 boot: `7b684c07-e39b-42e4-b90e-a067df2847e1`.
- Boot after normal reboot: `d9a21db2-030d-4d5d-93f3-1e566fba7c05`.

The existing source fix drains privately memoized client textures after active
GPU owners are released and before backend/driver teardown. See
[the teardown investigation](display-teardown.md) for ownership and lock order.

## Runtime checks

| Check | Observed result |
| --- | --- |
| Image-owned initial display scrub | Initial compositor PID 1512 logs completed early cleanup; fresh compositor and shell recover; compositor gate has zero failures |
| Normal idle SIGTERM, 11:32:53 UTC | PID 2083 logs cleanup; replacement PID 5479 and fresh shell recover; no gamescope kernel fault or structured core |
| Existing Tekken installation | Image-owned managed launcher uses the live player's environment; genuine Tekken PID 18117 owns foreground XID 44040193; fresh native 3440×1440 capture contains the game's loading indicator; production Close returns launcher status 0 and the game process disappears |
| Normal postgame SIGTERM, 11:39:00 UTC | PID 5479 logs cleanup; replacement PID 19986 and fresh shell recover; compositor gate has zero failures and no fault/core |
| Full normal reboot, 11:39:56 UTC | Prior-boot journal records PID 19986's cleanup after the normal greetd stop request; all nine shutdown-verifier checks pass, including absence of kernel-only faults, structured cores, enforcing AVCs and GPU Xid/AER faults |
| Final boot | Same immutable source/image, image-owned startup scrub, compositor PID 1980 and fresh shell; compositor and full postboot gates have zero failures, including GRUB boot-success after its normal timer |

Signals use a PID handle after checking the booted source/digest and absence of
an active Tekken process. Ordinary exit handlers, coredump reporting and the
production supervisor remain enabled. No failed-state reset or journal/core
deletion was performed. Old candidate10 cores can still exist without being
misattributed to candidate11's explicit boot IDs.

The shutdown verifier does **not** infer an exact compositor exit status from
greetd recovery. The reboot pass establishes cleanup ordering and absence of
faults across the preserved prior-boot journal. The game capture establishes a
rendered loading frame; it does not certify new gameplay or controller input.
Probe setup was corrected to inherit the full player environment, wait through
black loading frames and wait for asynchronous game Close; these were harness
issues and are not product-fix claims.

## Regression and evidence

The published build passes 216 backend tests (214 passes, two optional skips)
and the integrated shell suites. Fresh local runs pass all 11 ELF teardown
regressions, eight tracked shutdown-verifier regressions and the existing 16
acceptance-helper fixtures. The real candidate10 prior-boot negative control
correctly returns failure for its kernel SEGV despite no stored reboot core.

The reusable read-only verifier is `scripts/verify-pc1-shutdown.py`; its
regressions are `tests/test_pc1_shutdown.py`. Local retained evidence includes:

- `out/candidate11-image-build.log` and `candidate11-image-build-proof.json`.
- `out/candidate11-staged-identity.json` and `candidate11-stage.log`.
- `out/candidate11-compositor-initial.json`, both
  `candidate11-sigterm-request-*.json` and `candidate11-compositor-after-sigterm-*.json`.
- `out/candidate11-game-cycle.json` and `pc1-candidate11-tekken.png`.
- `out/candidate11-reboot-request-1.json` and `candidate11-normal-reboot-1.json`.
- `out/candidate11-compositor-final.json` and `candidate11-postboot-final.log`.
- `out/candidate10-shutdown-negative-control.json`.
- `out/candidate11-live-validation.json`, validated against the collected records
  and retained screenshot SHA256.

Candidate11 fresh installation media, separate power-off/power-on observation,
physical controller/TV/audio acceptance and suspend remain outside this check.
The existing nine-task release backlog remains open.
