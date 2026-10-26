# Consolidated release candidate — 10 October 2026

Branch: `codex/release-candidate-20261010`. Candidate image tag:
`ghcr.io/marwansummakieh/marwanos:candidate14-20261010`.

This candidate captures the October 8–10 source and bench improvements on top
of candidate13, including the console interface and volume popup, native
Downloads, Chromium extensions and controller panel, Windows registration,
local users with shared Steam state, controller discovery/latency/battery,
process-group Close, display-only Rest and the solid boot splash.
Game payloads, private accounts, bench mount overrides and development data
are not part of the image. NVIDIA/base/Godot/CEF pins are unchanged.

## Component integrity and build gates

Shell, installers, controllers and services have separate committed candidate
checkpoints in their owning repositories. The integration lock records exact
commits and exported blobs, including previously unowned browser, profile,
Downloads and shell files. The legacy FDM checkpoint is unchanged.
Exported bytes were compared against the committed component blobs before
updating the lock. Component-pin verification passes.

Both local image builds and the publication workflow now check component pins.
The publication workflow installs the native text-input, aria2 and X11 test
dependencies, runs backend and shell regressions before building, and retains
test logs plus source/image/component provenance as GitHub artifacts.
Steam native embedding and real-window geometry checks are included in the
standard shell suite.

## Verification in progress

The captured source is tested under `/var/tmp/pc1-rc-20261010` on PC1. Bubblewrap
hides the live player home, runtime services, device nodes and bench overrides;
tests have a private network namespace and writable disposable state.
The production OS, shell, controller broker and game saves are not replaced.

Initial backend run: **326 tests, zero failures, 13 skips**. Eleven skips need
the ELF C/C++ toolchain unavailable in the installed OS; two are opt-in audio
and notification integrations. Real aria2 HTTP/resume/torrent checks ran.
Seventeen shell-script groups passed. Three native X11 groups initially could
not start Xvfb because host NVIDIA EGL crashed with hidden graphics devices;
they are being rerun with Mesa software EGL in the isolated test namespace.
These initial failures are retained in the evidence directory.

Image publication, final CI results and additional checks will be recorded
here after completion. Building does not establish hardware release acceptance.

## Remaining acceptance

The consolidated image needs its own fresh offline installation, USB-absent
boot, reboot, update/rollback and persistent-data checks. Candidate13 passed
those installation/reboot checks within its separately recorded VM scope;
that evidence is not transferred to this candidate.

Physical acceptance still includes sustained multiplayer, rumble/hotplug,
Bluetooth recovery, Steam login/popups/text entry and broader games, native
Downloads through setup/play/cleanup, actual per-user saves, TV/audio recovery
and three filmed cold boots. Display-only Rest/PS wake has owner confirmation;
true suspend/controller wake remains limited by the current adapter.
