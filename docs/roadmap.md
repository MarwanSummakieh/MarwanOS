# PC1 / MarwanOS roadmap

Updated 2026-10-06 from the owner's priorities and installation record. This is the current backlog;
older phase plans and ADRs remain historical context where they disagree.

## Product priority

A unified game library with Playnite's interface quality and ease of use,
operated entirely from a controller. Games from different sources should be
recognized, organized and presented consistently, with minimal manual work.
Automatic metadata, play history, controller support and achievements are core
features. An integrated Flathub store is removed from the roadmap.

## Remaining work

| Priority | Work | Status / dependency |
| --- | --- | --- |
| Complete | Automatic game metadata and library presentation | Final candidate's real Tekken artwork, fullscreen Play-only Details, Options metadata refresh, offline cache and reboot persistence pass; prior physical controller gameplay confirmed |
| Complete | Play history and recently played ordering | Real Tekken foreground/Home/minimize/resume/exit session and recent ordering pass; final candidate reboot and actual metadata refresh preserve the single 122.453-second session |
| High | Controller rumble, multiplayer routing and reliable hotplug | Four slots and real force-feedback forwarding implemented; kernel/controller checks pass; physical rumble/two-pad acceptance pending |
| High | Unified achievements | Persistent local/Steam providers, progress and unlock notifications implemented; automatic public catalog supplies Tekken's 47 genuine definitions without credentials; baked-image catalog and earned-unlock acceptance pending |
| High, waiting | Controller-operated Bluetooth pairing | Controller page and BlueZ pairing agent implemented; real private D-Bus fixture passes; physical dongle acceptance pending |
| High | Download → install → cleanup | Final candidate's actual browser download, successful guided Close, app registration, explicit cleanup and installed-app lifecycle pass; torrent/multipart payloads retained; physical FDM lane pending |
| Release | Reliable suspend/resume | Sleep action and read-only evidence helper exist; testing explicitly deferred by the owner |
| Release | Silent boot, hardware and compatibility acceptance | Current-image TV/controller/audio/Steam/game testing and original boot-time gate remain incomplete |
| Release | Bake recent bench fixes into a release image | Final candidate 0be4ae6 passes override-free postboot, metadata refresh and real browser-install-cleanup/app lifecycle checks; media installation underway; physical gates and compositor teardown defect remain |

### Metadata and Tekken 8 acceptance

- [x] Verify the completed Tekken 8 installation's library entry and launch
      target are correct, including its actual installation source.
- [x] Trace which providers supply its metadata and verify actual downloads and
      persisted cache files. Cached Steam artwork or an extracted EXE icon alone
      does not prove automatic metadata enrichment. The 2026-10-06 implementation
      verified real Steam Store downloads; see [metadata evidence](game-metadata.md).
- [x] Check title, cover, background/hero, icon/logo where available, description,
      release date, genres, developer/publisher and source/platform information.
- [x] Compare the controller interface and effort required with Playnite: import
      should enrich the game automatically, without visiting a desktop or manually
      collecting artwork. The owner requested Play as the only details action;
      Options opens a separate controller refresh/matching page.
- [x] Verify metadata survives reboot and remains usable offline; failed downloads
      offer retry and do not prevent launching the game. Preserve manual corrections.
- [x] Implement missing provider/download/cache or presentation behavior discovered
      by this check, and extend the same flow to games from other sources.

The 2026-10-06 [completion record](fitgirl-controller-bench-20261005.md) reports
successful installation, verification of all 533 files and library registration.
Image-owned reboots and an isolated offline worker preserve the metadata/artwork.
The older inspected `appscan` helper discovered local icons and cached Steam art;
the new metadata worker now provides the automatic provider/download pipeline.
The [2026-10-06 metadata implementation](game-metadata.md) now supplies automatic
matching, downloads, persistent cache and spacious controller details. The owner
confirmed actual controller gameplay after the saved native-input profile repair.
Physical release acceptance and the separate controller-page final bake remain
open; see the current acceptance record for exact software evidence and defects.

Playnite's documented model uses metadata providers and automatically enriches
games on import, with later refresh and editing. Use that behavior as the baseline:
[Playnite metadata documentation](https://api.playnite.link/docs/manual/library/games/metadata.html).

### Play history

- [x] Persist last played, session history and total play time under stable game IDs.
- [x] Offer recently played ordering and show play time in game details.
- [x] Record actual game sessions; failed launches and installer activity must not
      count. Minimize/resume must retain one session rather than create duplicates.
- [x] Define idle/suspend accounting and recover history safely after shell crashes
      or reboot, without resetting history when metadata changes.

### Controllers

- [x] Forward supported game rumble through the virtual controller to its physical pad.
- [x] Route multiple pads to distinct player slots for local multiplayer, retaining
      PC1's Home controls and preventing application input while menus own the pad.
- [ ] Validate physical disconnect/reconnect, held-button suppression and stable
      player assignment. Use Tekken 8 as a two-player acceptance case when ready.
- [ ] Verify the implemented controller-operated discovery, pairing, removal,
      connection status and reconnect after reboot once the dongle arrives.

### Achievements

- [x] Investigate available achievement data for the installed Tekken 8 edition and
      other supported sources, including authentication and refresh requirements.
- [x] Define a provider interface and persistent per-game, per-profile achievement
      cache. Evaluate Steam first for Steam-owned games; investigate other sources
      and supported local game data separately.
- [x] Add a controller-accessible game achievements page with names, descriptions,
      icons, locked/unlocked state, completion totals and unlock times when supplied.
- [x] Show newly observed unlock notifications without replaying the entire history
      during the first sync; support offline cached viewing and later synchronization.
- [ ] Validate a real earned unlock end to end. Unsupported achievement sources must
      have an explicit unavailable state; identifying a game does not supply its
      player's unlock state.

Steam exposes player achievements and game schemas through its documented
[ISteamUserStats Web API](https://partner.steamgames.com/doc/webapi/ISteamUserStats).
Availability for the actual account and game edition must be verified before
selecting an integration. The shell displays earned achievements; provider support
and game compatibility determine how they can be observed.

## Existing foundation and release checks

The OS already has the library, browser, Files, Windows installation, Home overlay,
keyboard, Wi-Fi, audio controls and manual OS updates. These remain part of the
product. The Flathub store decision removes store development from this backlog;
existing Flatpak application compatibility remains supported.

Keep the remaining [system acceptance](acceptance-2026-10-05.md) work: physical
TV/HDMI and controller/audio behavior, Steam and real-game compatibility,
firmware USB boot, suspend/resume, and three filmed current-image cold boots
against the original <=15-second, no-text/no-cursor gate. Preserve the recent
[bench fixes](bench-fixes-20261005.md) when building the next image.
