# Bloodborne bench deployment — 10 October 2026

PC1 (`192.168.50.206`) has Bloodborne GOTY CUSA03173 with update 01.09 installed
under `/var/home/player/.local/share/marwanos/bloodborne`. Only the direct
`bloodborne.desktop` game card was added. Emulator and installer tools remain
hidden; existing game cards were retained.

The official shadPS4 0.19.0 Linux SDL runtime is pinned to release archive SHA-256
`a6e3b83fd6c9ea7b29c37e77e1aa687802d4ecd98c2ea794ca9e1d97b24a0cf9`.
Hardware: RTX 3070 8 GB, i7-6700K and 32 GB system RAM.

## Current runtime: native bbport 0.4

After the owner supplied `https://github.com/Supermedo/bloodborne_pc`, the card
was switched to its native Linux upstream, `deadinside28/bloodborne_pc` release
0.4. The supplied repository is the Windows fork; MarwanOS uses the Linux build
directly. The pinned AppImage SHA-256 is
`b279fe5cd39651ce374d065a84de7dfacd5dda703874effc8c2d35f3fccc754c`.
The package's Vulkan diagnostic recognizes the RTX 3070 and host NVIDIA driver.

`scripts/prepare-bloodborne-native-bench.py --activate` reproduces the hidden
runtime and switches the existing card. It downloads no game content. The
native game view is an independent base-plus-update copy in `bbport/game`;
the original shadPS4 directories remain available. This bench filesystem does
not support reflinks, so the view occupies approximately 30 GB. The port links
the game's bundled `libc.prx` and `libSceFios2.prx` before execution.

The previous launcher is `launch-shadps4`; `launch` now runs `launch-bbport`
under a single-instance `flock`. No extra desktop/setup entry was installed.
The port uses `--play`, bypassing its GTK launcher. Settings are in
`~/.config/bbport-launcher/settings.json` and `bloodborne/bbport/bbport.ini`.
Saves were backed up after System → Exit Game, then copied from
`user/home/1000/savedata` to `bbport/user/savedata/1`. Native user ID 1 is
hardcoded upstream; title/save directory remains `CUSA00207/SPRJ0005`.
Subsequent preparation runs never overwrite the migrated native save.

Selected profile: uncapped simulation patch with 120 FPS presentation cap,
Sprint Fix (High FPS), FSR 3.1, Immediate presentation (VSync off), two-stage
GPU draw processing, and the default NVIDIA-compatible memory model. Motion
blur, SSAO and chromatic aberration are disabled; default model detail and
shadows remain. The port automatically applies its Intel tonemapping fix.
The experimental AMD-only memory mode is disabled. DLSS is a feature of the
Windows fork and is not used by this Linux configuration.

The port's UI offers only 16:9 presets, but its explicit render/output
overrides support custom dimensions. The wrapper sets `BB_RENDER_RES=1720x720`
and `BB_OUTPUT_RES=3440x1440`: the scene renders at half output dimensions and
FSR reconstructs it, while the port draws the HUD at output resolution. The
saved preset is superseded by these explicit dimensions. An external one-write
patch sets camera aspect at `0x0183A35D` to `3440/1440`, using the same address
as the existing upstream ultrawide patch. The port handles scene/UI dimensions;
the shadPS4 resolution patch is not applied to the native runtime.

Verified through the existing home card: no setup window, imported character
loads, controller is detected, and clinic gameplay fills the ultrawide screen
without the white geometry artifact present in the last shadPS4 screenshot.
Repeated 600-frame windows measured 103.1–104.6 FPS, median frame intervals
9.61–9.66 ms and p99 11.35–13.29 ms. These are stationary clinic samples,
not outdoor/combat or full-game performance guarantees. A temporary overlapping
shadPS4 session distorted intermediate results; final measurements use one
native process and no emulator process. The runtime remains experimental.
Frame CSV/verbose statistics and the small FPS indicator were enabled for
measurement and disabled for subsequent launches.

Rollback: save and close the native game, back up its latest save, and restore
`launch-shadps4` to `launch`. To retain progress made under bbport, copy its
`user/savedata/1/CUSA00207` into shadPS4's `user/home/1000/savedata/CUSA00207`
only while both runtimes are closed, retaining a backup of the destination.
Original switch backup: `backups/before-bbport-20261010T133427Z`.

## Previous shadPS4 setup and verification

The owner's existing Downloads task `5ab3526d0a62d0c9` completed. The hidden
installer extracted the base and update, checked executable/title metadata and
published the game card. It did not initiate that download.
`scripts/install-bloodborne-pkgs-bench.py` reproduces the installer. The player
user service `marwanos-bloodborne-install.service` uses `NoNewPrivileges`,
`PrivateTmp`, `ProtectSystem=strict` and limited writable paths. No security
policy was changed. Extractor 1.1 SHA-256:
`b360bc691aa3d89071aa707224155f6eade348d314cf7798ac550e31c11a7bcc`.

The original card launch failed because `fusermount` was unavailable in the
shell environment. The launcher now sets `APPIMAGE_EXTRACT_AND_RUN=1`. Startup
then encountered an unnecessary first-run save-migration dialog; cancelling
that initialized the fresh portable profile. The preparation script precreates
`user/home/1000` to avoid that prompt. Settings and saves live in `bloodborne/user`.
`--override-root` controls the game mount root, not emulator user data.

The owner selected 3440×1440 ultrawide, then requested higher frame rates and
reported input lag. Native maximum quality measured about 25 FPS at 99% GPU
load. The owner chose smoother gameplay with upscaling, requested a higher
90/120 FPS limit, and then explicitly asked to reduce quality further.
The final shadPS4 profile enabled:

- A 1920×810 ultrawide patch derived by uniformly scaling the official 2560×1080
  patch's render dimensions and HUD coordinates. The game aligns its allocated
  framebuffer to 1920×812. The original ultrawide aspect/FOV remains.
- 90 FPS++, including its animation/timing changes.
- Disable Motion Blur (Perf Increase).
- Disable SSAO.

Source: official `shadps4-emu/ps4_cheats` revision
`5f832e266a9c091b8303f8f1fcf1d4633e57539f`, `PATCHES/Bloodborne.xml`, SHA-256
`c48a4173ca9c1a2c8c3a120b334dbc05898eb05e219a6f7b3cbe576036f210a2`.
`scripts/configure-bloodborne-quality-bench.py` creates a minimal version-matched
XML, checks cross-patch byte conflicts and supplies it explicitly with `--patch`.

Fullscreen/output dimensions are 3440×1440. FSR upscaling, RCAS sharpening and
pipeline caching are enabled. Presentation is `Immediate` (VSync off), with
90 Hz guest vblank. The upstream uncapped patch warns that Havok breaks above
90 FPS, so the supported 90 FPS patch is used instead.
Developer-kit mode adds 4000 MB direct memory for the resolution patch. Original
bloom, shadows and depth of field remain. Model detail and AA use the game
defaults. Added reflections, doubled AA and highest-LOD overrides are off.
The separate HD motion-blur patch conflicts with resolution/SSR writes and is
excluded. No overlapping generic performance preset is enabled.

The script backs up `launch`, `user/config.json` and an existing selected XML
under `backups/before-ultrawide-<UTC timestamp>`. Restore the relevant files
while the game is closed to roll back. `quality-profile.json` records the backup
path, exact hashes and validation scope. The upstream ultrawide patch recommends
at least 12 GB VRAM, exceeding this card's 8 GB. The selected ceiling is a target,
not a guarantee of sustained 90 FPS. `--profile native` reproduces maximum native
quality; default `performance` reproduces the owner's final smoothness choice.

Verification: the home card launched the title/offline flow without a setup
window. Logs confirm the quality patches and a real 3440×1440 video framebuffer.
The opening rendered scene and clinic gameplay fill the ultrawide display;
some title/setup artwork remains centered. GPU memory was about 5077 MiB of
8192 MiB during the opening scene. The direct window close request returned to
the selected Bloodborne home card. The owner authorized an immediate restart;
subsequent card launches applied the higher-frame-rate profiles. Later restarts
used the game's System → Exit Game flow to save and return to title first.
Final short outdoor samples showed 53 and 63 FPS. GPU utilization fell to 64–73%
while the emulator GPU-command thread used about 97% of one CPU core. Further
graphics reductions have limited headroom against this CPU-side bottleneck.
These are short samples, not a complete-game or sustained frame-time benchmark.

Official PlayStation cover/background artwork and descriptive metadata are
cached and visible on the home card. `scripts/metadata/bloodborne.json` is the
curated record. The metadata worker supports future installed direct game cards
via `metadata/custom/<library-id>.json`; refresh/offline reuse preserve the
launcher. All 20 backend regression tests pass.

Use the window-manager close request or the configured quit hotkey
Ctrl+Shift+End after System → Exit Game to exit. The F4 hotkey removes a virtual
user, so Alt+F4 is
unsuitable on this minimal window-manager session.

`scripts/prepare-bloodborne-bench.py` reproduces the hidden runtime and launcher;
optional `--game /path/to/CUSAxxxxx` registers the supplied game. Apply the
quality script after initial setup and extraction. Later preparation runs retain
an existing quality XML. These preparation/quality scripts download no game
content or firmware.

Bench evidence: `deployment.json`, `installer-deployment.json`,
`install-status.json`, `quality-profile.json`, `launch.log`, `extract-base.log`
and `extract-update.log` beneath the Bloodborne root. Source/setup evidence is
in `/var/tmp/pc1-bloodborne-20261010`; local diagnostics and screenshots are in
the ignored `out/bloodborne-20261010` directory.
