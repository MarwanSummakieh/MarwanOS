# FDM Classic source build and torrent tests — 2026-10-05

The full open source Windows FDM Classic 3.9.7 application and its BitTorrent
DLL were built locally and tested successfully with synthetic torrent data.
This is a patched local build, not a clean build of the unmodified repository.
Torrent support remains enabled. The Ultra-Light fork was explored earlier,
but is not the tested deliverable because it removes BitTorrent support.

## Source and output

- Source: <https://github.com/svn2github/FreeDownloadManager>, commit
  `1bd57c2f5aef2a06ba51990a876aa3632071630c`.
- Application resource version: 3.9.7, build 1627.
- Torrent engine: bundled libtorrent 1.0.3.0, with Boost 1.65.1.
- Source license file: `out/fdm-classic/source/trunc/license.txt`, containing GPLv3.
- Runnable folder: `out/fdm-classic/test-app/`.
- Start from the repository root using `./scripts/run-fdm-classic-local.ps1`.
  The launcher enables the isolated portable test mode and starts the GUI.

The test mode gives this build a separate instance mutex, stores its settings
under the test folder, skips portable COM registration and registry migration,
and disables browser monitoring, automatic updating, DHT, local peer discovery,
UPnP and NAT-PMP. Do not double-click the EXE for isolated testing: the launcher
supplies the environment used by these safeguards. Existing installed FDM was
left running separately.

| Binary | SHA-256 |
| --- | --- |
| FDM.exe | `D2A1C2D51EB0C45043C11ECA03957C73F88A7F744BE844B64174078F4C542C88` |
| fdmbtsupp.dll | `657AC69D866B672812003970E748ACEE6CD1AC19A8E97C4154695CED98CFDE13` |

## Verification

Tests used a tracker bound to `127.0.0.1:18973`, a separate seed process using
the rebuilt FDM torrent DLL, and a two-file BitTorrent v1 fixture totaling
12,583,625 bytes in 49 pieces of up to 256 KiB. No public swarm was used.

| Check | Result |
| --- | --- |
| Full application starts | Pass; FDM GUI and Torrents workspace opened |
| GUI .torrent import and transfer | Pass; imported through the file picker, reached 100% |
| DLL .torrent transfer | Pass; downloaded both files from the local seed |
| DLL magnet metadata and transfer | Pass; metadata retrieved from the peer, both files completed |
| DLL explicit pause | Pass after the fix below; paused state remained true and bytes stayed unchanged |
| DLL resume across process restart | Pass; saved 1,174 bytes of resume data, fresh process started with 8 completed pieces and finished |
| SHA-256 integrity | Pass for both files in all three download directories |

The fixture hashes are:

- `alpha.bin`, 8,388,608 bytes:
  `ad8ae213f33b218b1eb413048c4b82389bbf5d0e2657281f52a1cfb10da95199`.
- `beta.bin`, 4,195,017 bytes:
  `f4e5f493e6a364431b2f0f7215ea17fbd020b9e5fced429d05f84b42ca226f27`.

The GUI and DLL tests exercise distinct paths. Magnet and pause/restart checks
were performed through the DLL API; GUI acceptance covered .torrent import,
download, completion and output integrity. Public DHT, UDP/HTTPS trackers,
private trackers, torrent v2, browser integration, HTTP/HTTPS downloading and
long-running stability were not verified in this run.

The temporary tracker and seed processes were stopped after verification.

## Build repairs

The checked-in solution expects VS2013 and external Boost. It also references
a NetworkMonitor project absent from the source mirror. The local build used
the VS2017 compiler 19.16 with MFC/ATL 14.16.27023, MSBuild 18.9 and Windows SDK
10.0.26100.0. Required Microsoft packages were downloaded into the workspace
and checked against the SHA-256 values in the installed VS catalog; no global
Visual Studio component installation was completed.

Repairs retained in `docs/fdm-classic-local-build-20261005/source.patch`:

- Remove the absent optional NetworkMonitor project from the solution.
- Update Boost config selector include paths and replace invalid string token
  pasting in the legacy video-site macro.
- Add required `noexcept` on four standard error-category overrides and fix
  InetFile Release debug information settings.
- Add the optional portable test mode and startup diagnostic log.
- Fix torrent `Pause()` by disabling automatic queue management before
  pausing. Before this fix the controlled partial download reported
  `paused=0`; after it the same test reported `paused=1`, with a stable byte count.

The bundled OpenSSL libraries were compiled against the older Windows CRT.
A narrow import library for existing `msvcrt.dll` exports resolves their
missing data/function imports without replacing libtorrent. This is sufficient
for these tests; the obsolete crypto dependencies should be rebuilt and updated
before treating the fork as a maintained distributable.

The release GUI additionally needs `Language/eng.lng`, MFC runtime DLLs and
`fdmcs.dat`. The source recognizes an eight-byte customization record as an
empty default, so that record was generated for the test package.

MSBuild pre/post-build events were disabled to avoid the legacy projects'
registration steps. The application target and torrent target both finished
with zero build errors. Build warnings remain.

The evidence folder contains the source patch, build/acquisition scripts,
test harness, synthetic fixture generator, manifest, hash results and test
logs. Scripts are copies of the local scripts: place them under
`out/fdm-classic/` to use their expected relative paths. Dependency archives
and toolchains remain there as well. The compiler script uses this machine's
Visual Studio path and needs adjustment on another machine.

## MarwanOS implications

The subsequent [controller build](fdm-classic-controller-20261005.md) replaces
the executable in the local test package. It adds a controller interface and
records fresh binary hashes and end-to-end torrent verification; the results
above describe the earlier baseline build.

This establishes that a modified FDM Classic build can run and download
BitTorrent v1 data on this Windows host. It does not establish a native Linux
build or Wine compatibility. MarwanOS is Linux; bundling this exact executable
would require testing a Windows compatibility layer or a substantial port.
It is separate from the modern Linux FDM already tested on the PC1 bench in
`docs/fdm-linux-bench-20261005.md`.
