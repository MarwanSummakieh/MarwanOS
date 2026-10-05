# PC1 / MarwanOS roadmap

Updated 2026-10-05 from the owner's priorities. This is the current backlog;
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
| High | Automatic game metadata and library presentation | Pending; Tekken 8 is the next real-game acceptance case after its installation finishes |
| High | Play history and recently played ordering | Not implemented |
| High | Controller rumble, multiplayer routing and reliable hotplug | Rumble/multiplayer not implemented; physical acceptance also required |
| High | Unified achievements | Research and implementation required; choose integrations supported by each game/source |
| High, waiting | Controller-operated Bluetooth pairing | Waiting for the owner's Bluetooth dongle to arrive |
| Release | Reliable suspend/resume | Sleep action exists; target NVIDIA/gamescope acceptance pending |
| Release | Silent boot, hardware and compatibility acceptance | Current-image TV/controller/audio/Steam/game testing and original boot-time gate remain incomplete |
| Release | Bake recent bench fixes into a release image | Some latest fixes use bench overrides; rebuild, reboot-test and publish the validated image |

### Metadata and Tekken 8 acceptance

- [ ] After Tekken 8 finishes installing, confirm its library entry and launch
      target are correct, including its actual installation source.
- [ ] Trace which providers supply its metadata and verify actual downloads and
      persisted cache files. Cached Steam artwork or an extracted EXE icon alone
      does not prove automatic metadata enrichment.
- [ ] Check title, cover, background/hero, icon/logo where available, description,
      release date, genres, developer/publisher and source/platform information.
- [ ] Compare the controller interface and effort required with Playnite: import
      should enrich the game automatically, without visiting a desktop or manually
      collecting artwork. Provide controller-accessible refresh and match correction.
- [ ] Verify metadata survives reboot and remains usable offline; failed downloads
      offer retry and do not prevent launching the game. Preserve manual corrections.
- [ ] Implement missing provider/download/cache or presentation behavior discovered
      by this check, and extend the same flow to games from other sources.

This is a pending acceptance task, not a claim that the installation has finished
or that its metadata has been verified. The inspected `appscan` helper discovers
local icons and cached Steam art; no general Playnite-style metadata provider
pipeline was established by the source inspection on 2026-10-05.

Playnite's documented model uses metadata providers and automatically enriches
games on import, with later refresh and editing. Use that behavior as the baseline:
[Playnite metadata documentation](https://api.playnite.link/docs/manual/library/games/metadata.html).

### Play history

- [ ] Persist last played, session history and total play time under stable game IDs.
- [ ] Offer recently played ordering and show play time in game details.
- [ ] Record actual game sessions; failed launches and installer activity must not
      count. Minimize/resume must retain one session rather than create duplicates.
- [ ] Define idle/suspend accounting and recover history safely after shell crashes
      or reboot, without resetting history when metadata changes.

### Controllers

- [ ] Forward supported game rumble through the virtual controller to its physical pad.
- [ ] Route multiple pads to distinct player slots for local multiplayer, retaining
      PC1's Home controls and preventing application input while menus own the pad.
- [ ] Validate physical disconnect/reconnect, held-button suppression and stable
      player assignment. Use Tekken 8 as a two-player acceptance case when ready.
- [ ] Once the Bluetooth dongle arrives, implement and verify controller-operated
      discovery, pairing, removal, connection status and reconnect after reboot.

### Achievements

- [ ] Investigate available achievement data for the installed Tekken 8 edition and
      other supported sources, including authentication and refresh requirements.
- [ ] Define a provider interface and persistent per-game, per-profile achievement
      cache. Evaluate Steam first for Steam-owned games; investigate other sources
      and supported local game data separately.
- [ ] Add a controller-accessible game achievements page with names, descriptions,
      icons, locked/unlocked state, completion totals and unlock times when supplied.
- [ ] Show newly observed unlock notifications without replaying the entire history
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
