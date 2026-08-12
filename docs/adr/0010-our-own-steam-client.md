# ADR 0010 — The Steam client is ours; Valve's is the runtime underneath it

Status: accepted, 2026-08-12
Supersedes the client-facing half of [ADR 0008](0008-embedding-a-client-surface.md).

## The decision

The appliance ships **its own Steam client**, written in this repo. It signs in
by QR, lists the games the account owns, downloads them into a folder the owner
can point at, and launches them. Valve's client stays installed and stays
running, **windowless, as the thing that makes a game start** — and nothing in
this shell maps one of its windows any more.

On the owner's instruction (2026-08-12): remove every instance of Steam and
reimplement the flow as *my own client in the stores menu where I can sign in
and download my library games*, with *my own implementation and destination of
downloads eg the games folder in home so choose whatever gives me control*.

## What was removed, and why the removal was total

`steamfront` (a storefront fetcher), `steamproto` (its protobuf codec),
`storeart` (an artwork prefetcher) and the whole `stores_screen` storefront —
front page, search, wishlist, prices, the buy door that opened Valve's store in
mowser — are deleted rather than adapted. The owner asked for a rebuild from
zero including the QR sign-in that already worked.

That is a real cost and it is worth naming: the sign-in was the hardest thing in
the old tree, and the protocol it learned is preserved as a written
specification rather than as code. The rebuild is written against that
specification.

**The storefront is not coming back.** A store is where money changes hands, and
this appliance now has no surface where it can. Buying happens on a phone or a
desktop; this machine plays what the account already owns.

## What survived, and why that is not a contradiction

Valve's client is **still installed** and still supervised by the session, and a
reader who was told "remove every instance of Steam" deserves the reason.

A Steam game is frequently not a program you can run. Steam DRM wraps the
executable and it will refuse to start unless a signed-in Steam client is
running to answer it; Steamworks titles expect the same client for their
overlay, cloud saves, achievements and multiplayer. Downloading such a game
without a client gets a file that cannot be launched.

So the split is: **we own every pixel and every decision, Valve owns the
process that satisfies the DRM.** The client is a runtime dependency in the same
sense as a Proton build. It maps no window, it is reachable from no button, and
the only evidence of it on screen is the process pill saying something is
running in the background.

The tier below it is real and is drawn honestly: a game with no Steam DRM can be
launched directly, and if a title cannot start the UI says which of the two
reasons applies rather than blinking.

## The download path, and the three measured traps

Downloads are performed by **DepotDownloader** (SteamRE), driven by a root
helper in this repo. It speaks the real depot protocol through SteamKit, takes
an arbitrary destination directory, and can be handed a refresh token we minted
ourselves — which is what makes one sign-in serve the whole feature.

```
/var/home/player/Games/                 <- what the flatpak override exposes
└── SteamLibrary/                       <- what the client mounts as a library
    └── steamapps/
        ├── appmanifest_<appid>.acf     <- we write this
        ├── common/<installdir>/        <- DepotDownloader -dir points here
        └── compatdata/<appid>/         <- Proton prefixes, client-created
```

Three findings were measured on 2026-08-12 and each would have cost a build:

1. **The QR token must be minted for the Steam CLIENT, not the browser.**
   SteamKit stores a refresh token per account and will only submit one whose
   audience includes `client`. A token begun with `platform_type = WebBrowser`
   (which is what a sign-in designed around web API calls naturally produces,
   and what the deleted code produced) is rejected at logon. A `SteamClient`
   token carries `["web","client"]` and is what DepotDownloader needs.

   **Corrected the same evening (2026-08-12): the "one sign-in, not two"
   conclusion this finding originally drew was measured false.** The `web` in
   that audience is reachable only over a CM connection: Valve's HTTPS token
   exchange (`GenerateAccessTokenForApp`) serves web-platform tokens
   exclusively and refuses a SteamClient one outright — 200-empty with
   x-eresult 63, and every HTTPS side door refuses too (`finalizelogin`
   error 15, direct bearer 401). Community clients (SteamKit, steam-session,
   ASF) all route client-token derivation through the CM protocol, which this
   repo deliberately does not speak. So the sign-in is **two QR phases**: a
   SteamClient session for downloads, then a WebBrowser session whose token
   fills the library over plain HTTPS. One extra scan per ~200-day token
   lifetime, against a CM implementation nobody has to maintain. The wire
   detail lives in protocodec's token-req docstring; the seam vocabulary in
   the contract's sign-in section.

2. **The DepotDownloader binary path is pinned forever.** Its credential cache
   lives in .NET isolated storage under a directory named from a hash of the
   executable's own absolute path. Move the binary between image versions and
   every stored token is orphaned in silence — the symptom is a machine that
   asks for a fresh scan for no visible reason. It lives at
   `/usr/lib/marwanos/steam/DepotDownloader` and that path is asserted at build
   time.

3. **`StateFlags 4` does not stop the client re-downloading the game.** The
   client compares the manifest's `buildid` against the branch's current buildid
   and adds `UpdateRequired` on a mismatch. A believable manifest therefore
   needs the real `buildid`, `TargetBuildID 0`, and an `InstalledDepots` entry
   whose `manifest` id is the one actually pulled. Anything less produces a
   client that silently re-downloads what we just fetched, to the directory we
   were trying to own.

Two consequences follow from the sandbox: the override must expose the
**parent** (`Games`), because a client granted only the library root fails to
add it and reports nothing; and the client must be **stopped** while these files
are written, because it flushes in-memory state over them on exit.

## What the manifest buys, beyond the client

`appmanifest` is also how a download becomes visible. `marwanos-appscan`
already renders `StateFlags`, `BytesDownloaded` and `BytesToDownload` into a
rail card that says how far along a download is — written for Valve's client
writing those files. Our downloader writes the same keys into the same shape, so
a download this repo is performing shows a live percentage on the rail with no
second code path anywhere. The scanner now walks both libraries and emits one
row per appid.

## The seam

The unchanged rule: the shell opens no sockets, sees no URL and never holds a
credential. It writes a one-line request into a player-owned `0700` directory
and reads back root-written state — the sixth use of the pattern wifi
established.

```
the shell writes  /run/marwanos/steam/request        (0700 player)
root writes       /run/marwanos/steam.state          <word>TAB<detail>
                  /var/marwanos/store/front/*.json   account, library, signin
                  /var/marwanos/store/front/art/     capsules
                  /var/marwanos/secrets/             tokens, 0600, root-only
```

Requests: `signin`, `account`, `library`, `install <appid>`, `cancel <appid>`,
`uninstall <appid>`. The shell never names an account — the active identity is
the newest token file, resolved root-side.

## What is not proven

The old tree's sign-in was confirmed live only as far as **token storage**. The
refresh-to-access exchange and the owned-games call were never executed with a
real token, and the whole download and launch path is new. The first bench scan
is the real test, and the platform-type change in trap 1 means even the parts
that once worked are being exercised in a new configuration.

Nothing here has run on hardware yet.
