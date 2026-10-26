# Test bench report — 7 October 2026

**Result: available local automated checks PASS; full physical-bench acceptance is BLOCKED.** PC1 at its documented address, `192.168.50.206`, could not be reached. Windows SSH timed out on initial and final attempts; WSL reported no route to host. No live PC1 checks, deployment, reboot, or physical acceptance were performed.

Source tested: `89b2f099c670bcd6d387d5be0624634117a97eb2`. The working tree was clean before testing and after execution, before adding this report. Test runners and evidence are under `out/full-bench-20261007*`; application source was not changed.

## Executed checks

| Area | Result | Evidence under `out/full-bench-20261007/` |
| --- | --- | --- |
| Backend discovery | 250 discovered: 249 passed, one opt-in notification-bus check skipped; zero failures/errors. Isolated real PipeWire test enabled and passed. | `backend.log`, `backend-exit.txt` |
| Supplemental notification integration | All 3 notification tests passed with a private D-Bus session, including the previously skipped test. Across both runs, all 250 distinct backend tests passed. | `notifications.log` |
| Full shell suite | All 12 scripts in `scripts/check-shell.sh` passed, exit 0. These include Windows wizard/layout subtests and two download-directory configurations. | `shell.log`, `shell-exit.txt` |
| Real Linux controller fixture | Passed exclusive grabs, multiplayer isolation, Home/menu gating, held-input suppression, force feedback, virtual-device removal/recreation, reconnect identity, callback recovery, and uninterrupted second-player input. Devices are synthetic uinput fixtures, not physical pads. | `controller-kernel.log` |
| SDL controller mappings | DualSense, Xbox 360, and unknown-model identity, face buttons, D-pad, sticks, and triggers passed. | `controller-sdl.log` |
| Browser engine | Rendering, controller input/text entry, keyboard contexts, clicking, navigation, and Files handoff passed. | `browser_engine.log` |
| Browser downloads | Real engine download completed, used canonical Downloads, and matched expected bytes. | `browser_downloads.log` |
| Browser workflows | Upload/file selection, dialogs, select controls, tabs, bookmarks, history, background downloads, and unsafe-address handling passed. | `browser_workflows.log` |
| Browser HTTPS | `https://example.com` loaded with normal certificate validation. | `browser_internet.log` |
| Native achievement notifications | Passed native window/focus/overlay/transparency/text checks at 1280×720, 1920×1080, and 3440×1440. | `native-toast/`, `native-toast-exit.txt` |
| Notification inbox UI | Persistent inbox, home alert, expiry, and controller-accessible Info history passed. | `notification-ui.log` |
| Window geometry | Native pixel sizing, minimize without close, same-instance resume, dialog sizing, and fullscreen behavior passed. | `check-window-geometry.log` |
| Keyboard preview | Text, moved, and numeric keyboard preview smoke completed with exit 0. This preview is not an assertion suite. | `check-keyboard-preview.log` |
| Component integration | All five pinned component copies verified: shell, installers, controllers, services, and FDM. | `components.log` |
| Syntax | 61 Bash scripts and 51 Python files checked; zero syntax failures. | `syntax.log` |

The shell suite covers Files operations and keyboard navigation, Windows installation/removal UI and setup wizard/layout, controller routing, audio UI, metadata/cache and metadata page, play history, achievements and passive toasts, Bluetooth UI, download-to-install handoff, and canonical browser download paths.

Backend checks include installation lifecycle and path safety, audio and Bluetooth logic, metadata/achievements, application scanning/icons, Steam integration, controller policy, installer branding/origin/permissions, display mode selection, scanout parsing, shutdown acceptance, and compiled compositor lifetime/cleanup regressions.

## Test environment and limitations

- FedoraLinux-43 WSL provided the Linux host, Xvfb, and uinput. Backend dependencies were installed in a disposable container based on `ghcr.io/ublue-os/base-main@sha256:0a7036f6c63744e974f022125e67fb03f892cd543ba54ec589cb38932a768997`. Package installation logs are retained. Godot reported `4.7.1.stable.official.a13da4feb`.
- A fresh browser extension build was attempted but stopped because the retained SDK cache lacks `libgodot-cpp*.a`. Browser execution therefore used current shell sources with the retained browser extension/helper/CEF payload from `/var/tmp/pc1-browser-complete`. Exact SHA-256 hashes are in `browser-artifacts.sha256`. These passes do not establish a successful clean build of current browser C++ source.
- Initial browser attempts failed before import because the container's `player` user could not traverse the new root-owned temporary directory. Correcting permissions on that disposable fixture allowed all four suites to pass. Initial logs and subsequent results are retained.
- The extra-check wrapper was edited while another invocation was still reading it, producing a wrapper syntax error after the geometry, keyboard, and syntax checks had completed. This was a test-orchestration error, not a repository-source failure. Browser verification subsequently ran from a separate wrapper.
- Chromium emitted missing container D-Bus/machine-ID diagnostics and dialog-cancellation messages during workflow teardown. No browser assertion failed. These container results do not certify production desktop-service integration.
- The browser/keyboard screenshot and the 720p native achievement-toast screenshot were visually inspected; content was rendered and the inspected keyboard/toast text was readable and contained.

## Still unverified in this run

1. **Live PC1 health and deployed versions:** SSH unavailable. The final failure is retained in `pc1-connectivity.log`. Source passes cannot establish that the physical bench runs this source or that temporary hotfixes persist after reboot.
2. **Physical controller/game acceptance:** actual input, rumble sensation/cancellation, Tekken disconnect/pause/reconnect, Steam-owned gameplay, two physical controllers, and Bluetooth transport. Earlier documentation says a second controller and Bluetooth adapter were unavailable; this run could not confirm current hardware inventory.
3. **Physical display/audio and power:** NVIDIA output stability, audible sound, cable/display recovery, ordinary shutdown/reboot, and three filmed cold boots.
4. **Fresh release installation:** candidate11/replacement media installation, USB-absent boot, installed-health gates, upgrade/rollback, and reboot persistence were not rerun.
5. **Fresh native browser build and actual Windows runtime lifecycle:** cached browser SDK libraries were incomplete; a new real Wine/Proton installation/launch/remove cycle was not executed. The backend and shell lifecycle regression checks passed.

The next step for completing the requested physical-bench test is restoring access to PC1 or supplying its current address. The passing software checks are not a release or hardware acceptance sign-off.

## Later follow-up

PC1 became reachable after sleep. The owner reported that the controller cannot wake it; a read-only investigation confirmed a completed kernel suspend/resume cycle but no advertised USB remote-wake capability on the connected DualSense. See [the controller-wake investigation](controller-wake-20261007.md). The full physical-bench checks listed above remain unverified.
