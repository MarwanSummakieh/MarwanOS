# PC1 development record: 5 October 2026

The work continued into 6 October. This record distinguishes implementation,
bench deployment and pending acceptance; the detailed reports retain their
original dates and evidence.

| Implementation | Delivered | Verification / boundary |
| --- | --- | --- |
| Controller Windows setup | Native setup bridge, shell-rendered actual pages, options, keyboard and navigation, executable discovery and registration | Real FDM setup on the bench and controller/helper suites; unsupported controls retain original setup fallback |
| FitGirl setup | Scrollable options, RAM/component/language controls, music action and writable Games destination selected before the destination page | Native Tekken 8 music/destination checks and fixtures; fresh game install completion remains pending |
| FDM Controller | Modified GPLv3 Classic source, controller download/torrent UI, magnet keyboard, file/folder selection, pause/resume and seeding | Local transfer/hash/restart checks and bench torrent completion; full physical controller/overlay acceptance remains pending |
| System notifications | Persistent Linux D-Bus inbox and Wine/FDM completion bridge; controller-visible history | Real D-Bus and FDM bench delivery plus shell fixtures; no in-game action buttons or popup overlay |
| Audio manager | Device/port selection, volume, microphone, application mixer and reconnect handling | Service/controller/private PipeWire checks; ready for image integration, physical audio acceptance pending |
| Library cards | Official application icons, EXE icon decoding, rounded cards and custom FDM Controller artwork | Icon regressions and live bench data; no general automatic game-metadata enrichment confirmed |
| Runtime handoff | Native pointer-window dimensions, same-process minimize/resume and close | Real NVIDIA/gamescope FDM bench checks |
| Controller broker | SYN_DROPPED recovery and nonblocking-read handling without disconnect loops | Controller regressions and bench diagnosis |
| OS/USB installation | Branded media, controller keyboard/cancel, disk confirmation, offline install and installed-disk boot | UEFI/kernel-controller VM acceptance; physical firmware/media acceptance remains separate |

Browser, Files and keyboard workflows were also exercised through the current
integrated OS. The initially installed Linux FDM was subsequently replaced by
the custom FDM Controller build; these reports describe successive deployments.

Automatic download-to-install-to-cleanup is proposed, not implemented. Play
history, general game metadata, achievements, rumble/multiplayer and Bluetooth
pairing are tracked in the [roadmap](roadmap.md). Bluetooth hardware is pending.

Sources: [system acceptance](acceptance-2026-10-05.md),
[bench fixes](bench-fixes-20261005.md), [controller setup](windows-installation.md),
[FitGirl deployment](fitgirl-controller-bench-20261005.md),
[FDM source build](fdm-classic-local-build-20261005.md),
[FDM controller deployment](fdm-controller-bench-20261005.md),
[audio](audio-manager.md), [icons](app-card-icons-bench-20261005.md).
