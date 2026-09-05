# Windows installation

Files accepts ordinary Windows EXE and MSI installers without a recipe. Setup
runs interactively through umu/Proton in a separate managed prefix for each
attempt. This enables general installation; it does not guarantee compatibility
with every Windows program. Windows kernel drivers, some anti-cheat systems and
apps requiring unavailable Windows services remain incompatible.

## Controller flow

1. Select an `.exe` or `.msi` anywhere accessible in Files and press Cross/A.
2. Choose **Run Windows setup**. Keep any adjacent CAB/BIN installer files in
   the same folder. First-time runtime preparation can take several minutes.
3. Complete the Windows wizard using the controller pointer. Cross/A clicks;
   Home opens **Type** and **Close**. Close cancels the attempt.
4. After setup exits, choose the installed executable to add to the library.
   The list scans C: within that attempt, including Program Files and AppData,
   excluding Wine built-ins, linked directories and maintenance executables.
   Files installed outside the managed C: drive are not discovered.
5. Launch the new card. Back from the installation screen restores Files to
   the same folder. Failed setup does not automatically publish a card; if it
   left usable executables, explicit selection is still available.

For a standalone EXE, **Add as portable app** creates a card without running
setup. Keep its original file, folder and any removable drive available.

The top-bar Install screen also offers the optional automatic **7-Zip 26.03
x64** recipe. Recipe installs run in the background with hash verification and
known silent arguments. Back leaves those installs running; Cancel stops them.

## Interactive helper and data

The shell invokes `manager.py setup local-<unique-id> /absolute/source.exe` in
the player session. MSI uses `umu-run msiexec /i Z:\\...`; EXE receives no guessed
silent arguments. Argument arrays and the source folder preserve filenames and
multipart installers. File headers are checked before starting the runtime.

`jobs/<id>.json` stores progress and executable choices; `prefixes/<id>` retains
the attempt, including partial files after cancellation. `register <id> <choice>`
validates the choice again before committing `apps/<id>.json`. The shell reads
these manifests directly, so interactive installation needs no background worker.
Logs live in `logs/<id>.log`. Close verifies recorded process start times and
stops the setup wrapper and runtime process group. Prefixes are compatibility
environments, not security sandboxes.

## Automatic recipe worker and data contract

`marwanos-windows.service` runs `windows/manager.py daemon` as **player**.
It has a private `/tmp` and device namespace; each installer gets an Xvfb display
with TCP disabled. It does not inherit the shell's X11/Wayland display or Steam
window tags. GLX is disabled on the installer's Xvfb: the NVIDIA image's GLX
initialization crashed in the GPU-less acceptance container, while the installer's
2D UI needs no GLX. It does not affect the game's display or rendering runtime.
This prevents installer windows and runtime setup dialogs from
appearing on the TV. Wine prefixes themselves are not security sandboxes.

The default data root is `~player/.local/share/marwanos/windows`:

| Path | Contract |
|---|---|
| `requests/*.json` | Unique requests, published via `.tmp` then rename |
| `state.json` | Atomic state snapshot: status, detail, progress, job ID, heartbeat, recipes, source candidates and library |
| `prefixes/<recipe>-<uuid>/` | Separate prefix per attempt; failed/cancelled attempts removed |
| `apps/<recipe>.json` | Committed application manifest; contains prefix, executable and argument arrays |
| `logs/<recipe>.log` | Most recent installer/runtime output for developer diagnosis |
| `running/<recipe>.json` | Active process group and Linux process start time, checked before Close signals it |

Install requests are `{"verb":"install","recipe_id":"7zip","source_id":"download"}`.
For a local file, use its published candidate ID instead of `download`. Cancel
requests are `{"verb":"cancel","job_id":"<current job>"}`; a stale cancellation
cannot cancel a later installation. One installation runs at a time. Closing the
screen does not cancel it. Requests never contain shell commands or caller-chosen
installation destinations.

The worker scans Downloads and `/run/media/player` to depth three, at most 512
directories per root and 200 candidates. Filename matching identifies a possible
recipe; size and SHA-256 of the copied installer authorize execution. Copies go
to private temporary storage so ejecting/changing the source after verification
cannot replace the executable being run.

The shell treats a heartbeat older than 15 seconds as unavailable. Interrupted
active state becomes a retryable failure when the worker restarts. A hard power
loss may leave an uncommitted prefix; it is never published as installed, and
automated garbage collection of those prefixes is future work.

`manager.py launch <recipe>` uses the committed prefix and keeps a wrapper alive
to track the application. `stop <recipe>` signals its process group. Managed
entries carry argument arrays directly; they bypass the legacy whitespace-based
`apps.tsv` command encoding. Existing standalone executable discovery remains
separate.

## Recipe provenance and runtime

The image owns `windows/recipes.json`. The 7-Zip installer comes from the
[publisher's 26.03 release](https://github.com/ip7z/7zip/releases/tag/26.03).
The size and SHA-256 were calculated from that release asset on 2026-09-05.
Version bumps must update the URL, filename, hash, size and validation evidence
together. There is no runtime “latest installer” lookup.

The [7-Zip FAQ](https://www.7-zip.org/faq.html) documents `/S` and `/D` for its
EXE installer. This recipe uses `/S` and `/D=C:\PC1\7-Zip` and verifies `7zFM.exe`,
`7z.exe` and `7z.dll`. 7-Zip's license and source are available from
[7-zip.org](https://www.7-zip.org/); PC1 downloads the unmodified installer on demand.

The existing umu runtime receives `WINEPREFIX`, `GAMEID=0`, and
`PROTON_VERB=waitforexitandrun`, following its
[documented invocation](https://github.com/Open-Wine-Components/umu-launcher/blob/main/docs/umu.1.scd).
umu may download Proton and the Steam Linux Runtime on first use, so first-time
installation needs network access and can take minutes. Runtime provisioning is
currently stage-based progress, not an invented percentage. The recipe pins the
installer; Proton selection still follows the existing umu default.

## Verification

```bash
python3 -m unittest discover -s tests -v
GODOT_BIN=/path/to/pinned/godot bash scripts/check-windows-shell.sh
```

Tests need Linux, Python 3 and Xvfb, with a writable X11 socket directory. Under
WSLg, run them inside a container so `/tmp/.X11-unix` is not WSLg's read-only
mount. The suite exercises the real worker and hidden display with a fake Windows
runtime: hashing, explicit argument boundaries, verification, timeout,
cancellation, retry state, duplicate installs, discovery, launch/close and stale
PID protection. These are not a Proton compatibility test.

Fixture overrides (development only): `MARWANOS_WINDOWS_HOME` for the state root,
`MARWANOS_WINDOWS_RECIPES` for the worker's recipe file, and
`MARWANOS_WINDOWS_RUNTIME` for its executable runner. Production uses the
image-owned recipe and umu. The shell and worker must share the same state root.
`MARWANOS_WINDOWS_HELPER` lets a bench shell use its matching staged helper.
`tests/test_windows_local.py` covers general setup arguments, session display,
multipart files, invalid files, selection, portable apps and cancellation.
The Files controller checks cover EXE/MSI routing, selection and focus restoration.

Before calling this slice appliance-verified, run the real pinned installer
on the target with only a controller:
install, return home during installation, launch from the new card, open overlay,
resume, close, unplug/replug the controller, cancel and retry. Verify that the
game/application does not also receive overlay button presses. Steam input
ownership and its background-client behavior are not solved by this installer.

### Evidence from 2026-09-05

- The general `setup` path opened the real 7-Zip wizard on the session display
  under Xvfb, completed with interactive input and no silent arguments, and
  offered the three installed 7-Zip executables. Explicitly selecting `7zFM`
  produced a manifest; launch mapped its real window and managed Close ended it.
  This used the cached umu/Proton runtime described below, not a recipe install.
- All 27 Python regression tests passed; the seven general setup tests passed
  again after the runtime-file filter. Both Godot controller suites passed with
  the final shell changes. The updated export started headlessly
  with its browser extension, and the staged bundle checksums passed.
- The pinned 7-Zip installer downloaded, passed its hash check and installed
  unattended through umu 1.4.4 in a disposable container based on the existing
  MarwanOS image, running as player. umu provisioned UMU-Proton-10.0-4 and
  Steam Linux Runtime sniper 3.0.20260805.254768. All three expected files were
  present and a library manifest was committed.
- The real installed `7zFM.exe` mapped a visible 7-Zip window under Xvfb, then
  the managed Close command ended the launch wrapper. A screenshot was inspected.
- The exported shell launched the real installed app, activated its controller
  pointer bridge, opened/resumed its overlay, and closed the managed app. Xvfb
  supplied the display and a fixture supplied gamescope's focus property; this
  verifies the connected code paths but not physical compositor/input behavior.
- The shell exported with Godot 4.7.1 and displayed the installation screen under
  Xvfb. The layout and installed state were inspected visually.
- `tests/windows_shell.gd` drives Godot joypad events through installation,
  cancellation, return-home, library publication and launch/overlay/close.
  Worker state and compositor handoff are fixtures in that test, not hardware
  evidence. The Python suite tests the actual worker with a fake runtime.

No new OS image was deployed to the physical appliance. Controller hotplug,
Steam ownership, real compositor handoff and TV behavior remain target checks.

## Upgrading a development bench

The `build` workflow publishes `ghcr.io/marwansummakieh/marwanos:latest` plus
a dated version tag. Wait for its Push step to succeed, then run
`sudo bootc upgrade` on the bench. Before rebooting, disable an existing
`/var/marwanos/dev-shell/marwanos-shell` override by removing its executable bit:
`sudo chmod a-x /var/marwanos/dev-shell/marwanos-shell` (only if that file exists).
The session then uses the shell and helper shipped together in the OS image.
Keep `/var/marwanos/devmode` if development SSH access is still needed.
After `sudo systemctl reboot`, `/usr/share/marwanos/build-info` identifies the
running build. The old override remains on disk and can be re-enabled explicitly.
