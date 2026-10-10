# PC1 / MarwanOS roadmap

Updated 2026-10-10 for release-candidate consolidation. This is the current backlog;
older phase plans and ADRs remain historical context where they disagree.
Steam embedding implemented and remotely tested on the PC1 bench on 2026-10-09.

## Product priority

A unified game library with Playnite's interface quality and ease of use,
operated entirely from a controller. Games from different sources should be
recognized, organized and presented consistently, with minimal manual work.
Automatic metadata, play history, controller support and achievements are core
features. An integrated Flathub store is removed from the roadmap.

## Remaining work

The [October 10 candidate record](release-candidate-20261010.md) supersedes older
image and hardware inventory below: candidate13 fresh installation/reboot passed,
two wireless controllers and a Bluetooth adapter are available, and display-only
Rest/PS wake has physical confirmation. The new candidate consolidates subsequent
source and bench work; its image and hardware gates must be recorded separately.

**Candidate14 is published; fresh-image and physical acceptance remain open.** Automatic metadata/presentation, installed
Tekken verification, persistent play history and achievements are complete.

| Priority | Work | Status / dependency |
| --- | --- | --- |
| Complete | Automatic game metadata and library presentation | Final candidate's real Tekken artwork, fullscreen Play-only Details, Options metadata refresh, offline cache and reboot persistence pass; prior physical controller gameplay confirmed |
| Complete | Play history and recently played ordering | Real Tekken foreground/Home/minimize/resume/exit session and recent ordering pass; the original 122.453-second session survives refresh/reboots. After subsequent genuine gameplay, candidate10 Details shows 52 minutes across three sessions |
| High | Controller rumble, multiplayer routing and reliable hotplug | Broker fixes cover force-feedback callbacks, discovery, native virtual hotplug, model identities and Steam Input recapture; 37 policy checks and the real Linux uinput fixture pass. Owner-confirmed Silksong menu controls pass with its official Steam Input layout. Tekken hotplug/rumble retesting and two-pad hardware acceptance remain open. See the [session record](physical-acceptance-20261007.md) and [latest investigation](steam-display-corruption-20261007.md) |
| Complete | Unified achievements | All 47 genuine definitions/icons, two naturally earned Tekken unlocks, native 2/47 page/Refresh and worker-restart deduplication pass. Candidate9's real in-game toast stays passive during guarded keyboard input, expires and preserves game focus; candidate10 reboot preserves 2/47 without notification replay. Physical controller acceptance remains separate |
| High, waiting | Controller-operated Bluetooth pairing | Controller page and BlueZ pairing agent implemented; real private D-Bus fixture passes; physical dongle acceptance pending |
| High | Download → install → cleanup | Final candidate's actual browser download, successful guided Close, app registration, explicit cleanup and installed-app lifecycle pass; torrent/multipart payloads retained; physical FDM lane pending |
| Release | Reliable suspend/resume | Sleep action and read-only evidence helper exist; testing explicitly deferred by the owner |
| Release | Silent boot, hardware and compatibility acceptance | Earlier audits found no NVMe/kernel hardware faults on PC1's RTX 3070/NVIDIA 610.43 setup. Two wireless DualSense controllers and a UGREEN adapter are now available; sustained multiplayer, rumble/hotplug, Bluetooth recovery, TV/audio recovery and three filmed cold boots remain open. Load/stress and firmware acceptance remain unclaimed. See the [current candidate record](release-candidate-20261010.md) and [historical physical session](physical-acceptance-20261007.md) |
| Release | Bake recent bench fixes into a release image | October 10 changes are consolidated on `codex/release-candidate-20261010` with 338 exports pinned to published component checkpoints. All 326 backend tests have no failures, both optional integrations pass separately, all 20 shell groups pass, and five native Chromium flows pass. Image publication, exact digest and fresh-image installation/reboot/update/rollback acceptance are recorded in the [candidate record](release-candidate-20261010.md). Candidate13 remains the separately accepted installation/reboot base |

### Experimental implementation: Steam inside Stores

The owner wants persistent MarwanOS navigation, a store selector on the left and
the live Steam client in a large pane on the right, operated entirely by a
controller. [ADR 0008](adr/0008-embedding-a-client-surface.md) now evaluates native
X11 window embedding first on PC1's accepted Xorg backend. Steam's Big Picture
interface supplies controller navigation within the pane; games remain
fullscreen and must return to the saved Stores surface on exit.

Status: the opt-in native pane is enabled on the bench. Controller-path browsing,
Silksong launches from both libraries, fullscreen return, minimize/resume and
host recovery pass remote checks. See the [screenshots and test report](steam-embedding-20261009.md).
Physical acceptance, popup/text entry and performance remain open before default enablement. The
current fullscreen Steam route remains available on unsupported backends or
embedding failure. This investigation does not change the release acceptance
claims above.

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
The controller page is baked and verified on candidate10. Physical release
acceptance remains open; see the current acceptance record for exact software
evidence and its limits.

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
- [x] Validate a real earned unlock end to end. Unsupported achievement sources must
      have an explicit unavailable state; identifying a game does not supply its
      player's unlock state.

Candidate9 verifies the actual Customize unlock after ordinary game Save, a
readable passive toast over Tekken with keyboard input/focus preserved, expiry,
the native 2/47 page and no notification replay after Refresh/worker restart.
See [achievement evidence](achievements.md). This completes the achievements
task without claiming unsupported providers or physical-controller testing.

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
