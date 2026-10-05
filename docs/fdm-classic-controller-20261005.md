# FDM Classic controller build — 2026-10-05

This report records the initial Windows verification. The subsequent
[bench deployment](fdm-controller-bench-20261005.md) fixes flickering, removes the
desktop switch and routes notifications through the MarwanOS system inbox.

The locally built Windows FDM Classic now includes a controller view backed by
the original download manager and bundled torrent engine. The launcher opens
this view by default:

```powershell
pwsh -NoProfile -File scripts/run-fdm-classic-local.ps1
```

Use `-Desktop` to start in the classic interface. F10 switches between views;
F11 toggles fullscreen in the controller view. This is the isolated local source
build, separate from the installed modern FDM and the Linux FDM on the bench.

## Controls and features

| Control | Action |
| --- | --- |
| D-pad / left stick | Move the visible focus |
| A / Enter | Activate the focused control |
| B / Escape | Return to the previous screen |
| X / F5 | Browse local `.torrent` files |
| Y / F6 | Enter a magnet link or HTTP/HTTPS URL |
| LB / RB | Change queue filter, or page through folders/files |
| Start / Menu | Switch to the classic desktop view |
| Arrow keys / Tab | Navigate without a controller |

The link keyboard provides letters, numbers, URL punctuation, shift, backspace,
paste and a review step. In this keyboard, X erases, Y pastes and LB/RB change
case. A review screen lets the user choose a save folder and add a download
started or paused. The folder browser has separate Up, This PC and Back actions.

Downloads have large rows, progress, speed, status, pause/resume, file selection,
seeding controls and an open-folder action. The file selector prevents excluding
every file. Invalid sources and duplicate torrents produce a message within the
controller view. Advanced settings remain available in the classic view.

The UI polls XInput dynamically from the Windows system directory, without a new
third-party controller dependency. It ignores controller input when its window
is not in the foreground, suppresses held controls after reconnect/focus changes,
and requires a neutral state before accepting them again. Navigation repeats;
accept/back actions do not repeat. Guide is reserved for the OS.

## Verification

| Check | Result |
| --- | --- |
| Final Release/Win32 build | Passed, zero build errors; legacy warnings remain |
| Controller input state machine | 14 checks passed: edges, held buttons, focus, reconnect, dead zone, repeat, shortcut selection, maximum stick values |
| Local torrent browser and review | Passed; created a 12,583,625-byte, two-file torrent paused |
| File selection | Exclude/re-include passed; last included file guard passed |
| `.torrent` completion | Both files downloaded; SHA-256 hashes matched |
| Magnet keyboard and creation | Entered a distinct magnet, received metadata and transferred files |
| Pause while incomplete | Paused at 38%; both file hashes remained unchanged while paused |
| Resume after application restart | Paused state survived; resumed and completed 50,332,361 bytes |
| Magnet completion | Both files matched expected SHA-256 hashes |
| F10 view switch | Passed in both directions |
| Final browser Back | Returned directly to Downloads |
| Seeding control | Disabled seeding for a completed torrent; view changed to Complete |
| Fullscreen and windowed layouts | Inspected; focus and main controls visible |

Tests used synthetic files and a loopback tracker/seed. UI tests used keyboard
and native accessibility/coordinate actions; the shared controller state machine
was tested with synthetic samples. No XInput controller was connected, so physical
gamepad handling and device-specific mappings remain unverified. HTTP/HTTPS
creation is implemented but was not included in the transfer tests.
The temporary tracker and seed were stopped after verification. The final local
app remains open in its controller view.

## Source and reproduction

The [evidence folder](fdm-classic-controller-20261005/) includes the full source
patch against upstream commit `1bd57c2f5aef2a06ba51990a876aa3632071630c`, the new
controller source files, input tests, fixture generators, manifests, hash results,
build output and binary hashes. The patch also includes the prerequisite build
repairs and torrent pause fix documented in the
[original build report](fdm-classic-local-build-20261005.md). Its reverse application
was checked against the local source tree without modifying that tree.

The scripts expect the layout under `out/fdm-classic/`. To compile the input
tests, use `build-local.ps1 -Target controller-test`, then run
`controller-input-test.exe`. To rebuild the application, use
`build-local.ps1 -Target classic` and copy `source/trunc/bin/Release/FDM.exe` into
`test-app/` after closing the local app. The existing toolchain and dependency
requirements still apply.

Final `FDM.exe` SHA-256:
`883B403EFBFB17FBA1CB9164852F9F1D70A22B79E978271478DB263E32413814`.
The torrent DLL is unchanged from the validated previous build:
`657AC69D866B672812003970E748ACEE6CD1AC19A8E97C4154695CED98CFDE13`.

At this initial verification stage, the Windows build had not been installed in
MarwanOS or tested through its Linux controller broker/Wine. The portable test launcher disables DHT, LAN discovery,
UPnP/NAT-PMP, browser integration and automatic updates. The original legacy
dependency limitations remain; these results establish local functionality,
not a maintained native Linux distribution.
