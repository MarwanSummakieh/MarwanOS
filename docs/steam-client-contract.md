# The Steam client's seam contract

The single source of truth for how the shell half and the root half of the
in-shell Steam client talk to each other. Both sides are written against this
file; if the two ever disagree, this file is what is wrong and gets fixed first.

See [ADR 0010](adr/0010-our-own-steam-client.md) for why the client exists and
why Valve's own client is still installed underneath it.

## The rule that has not changed

The shell runs as `player`, opens no sockets, sees no URL, and never holds a
credential. It writes a one-line request into a player-owned `0700` directory;
the root service consumes it, does the network work, and writes back state the
shell reads. Requests are fire-and-forget: there is no correlation id, and the
answer to "did it work" is the state file changing.

## Paths

| Path | Owner | Mode | Direction |
|---|---|---|---|
| `/run/marwanos/steam/request` | `player:player` dir `0700`, file `0600` | shell writes, root consumes by `rename(2)` |
| `/run/marwanos/steam.queue` | `root:root` | `0600` | `steamd` appends, `steamdl` drains |
| `/run/marwanos/steam.state` | `root:root` | `0644` | root writes, shell polls |
| `/run/marwanos/steam.downloads.json` | `root:root` | `0644` | root writes, shell polls |
| `/var/marwanos/steam/{account,library,signin}.json` | `root:root` | `0644` | root writes, shell reads |
| `/var/marwanos/steam/qr.png` | `root:root` | `0644` | root writes, shell reads |
| `/var/marwanos/steam/art/` | `root:root` | `0644` files | root writes, shell reads |
| `/var/marwanos/secrets/` | `root:root` | `0700`, files `0600` | root only, never the shell |
| `/var/marwanos/steam/staging/` | `root:root` | `0700` | root builds temp files here |
| `/var/home/player/Games/SteamLibrary/steamapps/` | `player:player` | `0755` | the download destination |

Durable answers live under `/var` so a machine that has been online once still
draws its library after an offline boot. `/run` holds only what is true about
this boot.

**The queue is a sibling of the request directory, not a file inside it, and
that placement is a security property rather than a preference.**
`/run/marwanos/steam` is player-owned `0700` so the shell can create `request`
in it — which means the session user may unlink any name in that directory and
put a symlink there instead. A root process appending to a name inside it is a
write-anywhere primitive. The queue therefore lives in root-owned
`/run/marwanos`, beside `steam.state`, where both ends of it really are root.

## Requests

One line, `<verb>` or `<verb>TAB<arg>`, written temp-then-`rename(2)` at `0600`.

| Verb | Arg | What it does |
|---|---|---|
| `signin` | — | begin a QR session; re-publishes the current one if a job is live |
| `account` | — | who is signed in; local only, opens no socket |
| `library` | — | refresh the owned-games list and fetch a bounded page of art |
| `install` | `<appid>` | queue a download |
| `cancel` | `<appid>` | stop a running or queued download, remove partial files |
| `uninstall` | `<appid>` | delete an installed game and its manifest |

The shell **never names an account.** The active identity is the newest token
file, resolved root-side. A SteamID arriving in a request would be the
unprivileged half telling root whose data to fetch.

`appid` is validated as digits-only, at most 10 digits, at both ends.

## The state file

`/run/marwanos/steam.state`, one line, `<word>TAB<detail>`.

| Word | Meaning |
|---|---|
| `idle` | service started, nothing asked |
| `working` | a request is in flight |
| `done` | answered, from network or from cache |
| `offline` | could not refresh; stored results may still be on disk |
| `failed` | detail carries a short reason |

`detail` is the request name, or on `failed` a short reason: `no token`,
`sign in again`, `no answer`, `cannot write`, `not owned`, `no space`.

**One writer.** The async sign-in job and the download workers narrate through
their own files and must never write this one.

## Result files

```jsonc
// signin.json — the QR panel's whole story
{ "status": "starting|waiting|approved|expired|failed",
  "fetched": <epoch>, "persona": "", "client_signed_in": false }

// account.json
{ "signed_in": true, "steamid": "765611…", "persona": "…",
  "source": "web|client|", "client_signed_in": true, "fetched": <epoch> }

// library.json
{ "fetched": <epoch>, "items": [ { "appid": 620, "name": "Portal 2",
    "installed": false, "playtime": 1234, "native_linux": true } ] }

// steam.downloads.json  (in /run — it is only true about this boot)
{ "active": 620,
  "items": [ { "appid": 620, "name": "Portal 2", "state": "queued|downloading|installing|done|failed",
               "percent": 42, "detail": "3.1 GB of 7.4 GB", "error": "" } ] }
```

**No URL of any kind appears in a result file.** The picture for an item is
`art/<appid>.jpg`, a path the shell derives from the appid it already has. A
live URL in a file the renderer reads is an invitation for a later change to
make it one that fetches.

`fetched` moves on every publish, including a re-publish of unchanged content —
that is what tells the shell a rotated QR is worth re-reading.

## Artwork

Written into `/var/marwanos/steam/art/`, skip-if-exists,
temp-then-rename, explicit `chmod 0644` (the reader is a different uid, so the
umask must not be trusted).

| File | Source |
|---|---|
| `<appid>.jpg` | `library_600x900_2x.jpg` → `library_600x900.jpg` → `header.jpg` |
| `<appid>.hero.jpg` | `library_hero.jpg` → `hero_capsule.jpg` → `capsule_616x353.jpg` |

**Two assets, and there was briefly a third.** `<appid>.logo.png` was specified
here and fetched for every game until an audit asked which surface drew it, and
the answer was none. It cost one request per game inside a budget of 24 games
per refresh, for a file that reached no screen. The capsule is the shelf tile
and the hero is the rail's card art (via `marwanos-appscan`'s fallback chain) —
**having a named reader is the test a third asset has to pass** before it earns
a request here.

Base URL, and the host/prefix pairing is not interchangeable:

```
https://shared.steamstatic.com/store_item_assets/steam/apps/<appid>/<file>
```

`shared.*` hosts **require** the `/store_item_assets/` prefix; the legacy
`cdn.*`, `steamcdn-a.akamaihd.net` and `media.steampowered.com` hosts use a bare
`/steam/apps/…`. Mixing the two yields 404s that look exactly like a game
having no artwork.

Requirements that hold for every fetch:

- **Host allow-list.** Only the hosts named above. Response-body URLs could
  otherwise point the fetcher anywhere on the internet.
- **Content check, not just status check.** JPEG must start `FF D8 FF`, PNG
  `89 50 4E 47`. `curl -f` keeps out 404s but not a CDN edge answering 200 with
  an error page.
- **Ask appinfo first.** If `common.library_assets_full` is absent for an
  appid, the library art does not exist and must not be requested — that
  correlation is exact, and it is how tools, DLC and delisted apps behave.
- **Bounded per request.** At most 24 new appids get art per `library`
  request. Each visit reaches further down the list; the first page is the
  games the person actually recognises.

## Sign-in

Full wire detail is in the protocol specification. The one thing that cannot be
got wrong, and which the deleted implementation got wrong by default:

**The QR session must be begun as `platform_type = SteamClient` with
`website_id = "Client"`.** SteamKit only submits a stored refresh token whose
audience includes `client`, so a `WebBrowser`-audience token — the natural
output of a flow designed around web API calls — is rejected at logon and the
downloader silently falls back to asking for a password nobody can type. A
`SteamClient` token carries `["web","client"]` and serves both our own API calls
and DepotDownloader, which is what makes one scan enough for the whole feature.

Tokens are stored `0600` under `/var/marwanos/secrets/`, written under
`umask 077` rather than chmod-after-write, one file per account, newest mtime
wins. They never appear in a log, a state file, an argv, or any path the session
uid can read.

## Downloads

`DepotDownloader` at **`/usr/lib/marwanos/steam/DepotDownloader`**, and that
path is frozen. Its credential cache lives in .NET isolated storage under a
directory named from a hash of the executable's own absolute path, so moving the
binary orphans every stored token in silence.

It is invoked with `-username <account> -remember-password` — without **both**,
the stored token is never read and it prompts for a password instead. Never run
it with stdin closed: some auth paths crash with an unhandled exception rather
than exiting cleanly, so treat any exit code other than 0 or 1 as "auth wedged".

**`-remember-password` reads a store nothing else on this appliance would ever
fill, so the root side fills it.** The flag means "look in .NET isolated storage
for a token you saved there yourself", and DepotDownloader only saves one after
DepotDownloader itself performed a login — which never happens here, because the
login is steamd's QR flow. Left alone, one scan produces a working shelf and an
install that fails with `sign in again` forever. So `steamdl` seeds
`<HOME>/.local/share/IsolatedStorage/<a>/<b>/Url.<hash>/AssemFiles/account.config`
from `secrets/steam-refresh.<steamid>.token` before every invocation:

- a protobuf-net contract, **raw DEFLATE** (RFC1951, no zlib header);
- field `2` `ContentServerPenalty`, field **`4` `LoginTokens`** —
  `map<string,string>` of account name to refresh token — field `5` `GuardData`;
- merged, never replaced: unrecognised records are preserved byte for byte, so
  a re-seed cannot discard what the downloader keeps there itself;
- `0600` at creation, and the token reaches the writer on **stdin**, never argv.

`Url.<hash>` is derived from the executable's absolute path and the other two
levels from .NET identity hashes, so the directory cannot be computed — it is
found after letting the tool build it (an anonymous `-app 480 -manifest-only`
run, once per machine). $HOME is therefore load-bearing twice over and must be a
directory the root service owns and can write.

The token must carry the `client` audience for this to work at all, which is
what the sign-in section below is about.

Progress on stdout is one line per completed file, cumulative and monotonic,
matching `^\s*(\d{2,3}\.\d{2})% (.+)$`. There is no ANSI on Linux and none when
stdout is redirected. `Total downloaded: 0 bytes` means already up to date.

### Making the client accept what we downloaded

The client must be **stopped** while these files are written — it flushes
in-memory state over them on exit — and started again afterwards.

`appmanifest_<appid>.acf` needs, at minimum, `appid`, `Universe 1`, `name`,
`StateFlags`, `installdir`, `LastUpdated`, `SizeOnDisk`, `buildid`, `LastOwner`,
`UpdateResult 0`, the four `Bytes*` counters, `TargetBuildID 0`,
`AutoUpdateBehavior 1`, and an `InstalledDepots` block.

**`StateFlags 4` alone does not stop the client re-downloading the game.** It
compares the manifest's `buildid` against the branch's current buildid and adds
`UpdateRequired` on a mismatch. A believable manifest needs the real `buildid`
(appinfo `depots.branches.<branch>.buildid`), `TargetBuildID 0`, and an
`InstalledDepots.<depotid>.manifest` equal to the manifest id actually pulled.
Never set bit 8 (`DataEncrypted`) — the payload is plaintext and the client
would redo everything.

**Never invoke "verify integrity of game files"**: it re-hashes against the
current branch manifest and pulls the whole delta.

`StateFlags` values that matter: `4` fully installed, `1026` (`1024|2`) update
required and started, `1048576` downloading.

### While a download is running

The same `appmanifest` carries `StateFlags` without bit 4 plus `BytesDownloaded`
and `BytesToDownload`. `marwanos-appscan` already turns exactly those into a
rail card that says how far along a download is, so writing them is what makes a
download this repo is performing show a live percentage on the rail with no
second code path. Rewrite the manifest as progress advances.

### The sandbox

The flatpak client is granted the **parent**, not the library root:

```sh
flatpak override --system com.valvesoftware.Steam --filesystem=/var/home/player/Games:create
```

A client granted only the library root fails to add it and reports nothing. Free
space is read from the containing directory, symlinks in a library path are
unsupported (which is why every path here is `/var/home`, not the `/home`
symlink), and a `noexec` mount breaks the client outright.

## Launching

Three tiers, chosen per game and drawn honestly rather than blinked:

1. **Steam DRM or Steamworks** — through the hidden client,
   `flatpak run com.valvesoftware.Steam -silent steam://rungameid/<appid>`.
   This is the tier the client exists for.
2. **Native Linux, DRM-free** — directly, or through
   `UMU_NO_PROTON=1 umu-run` for the Steam Linux Runtime sandbox.
3. **Windows, DRM-free** — `GAMEID=umu-<appid> PROTONPATH=GE-Proton umu-run`.
   `PROTONPATH=GE-Proton` is a token that triggers auto-provisioning; a pinned
   version name resolves as a directory and does not.

A title is native-Linux only if some appinfo `config.launch.<n>.config.oslist`
contains `linux`. The store-level `common.oslist` is a coarser claim and does
not guarantee a runnable Linux entry point.

**umu cannot launch a Steam-DRM'd game.** It provides identity, not
entitlement: it sets `SteamAppId` but ships no client, no session and no licence
data. Tier 2 and 3 are the DRM-free tiers and nothing else.

## The traps this seam has already paid for

- **Tab is IFS whitespace.** A TSV line with a leading empty field shifts every
  value one place left under `read`. This has broken two features in this tree,
  one of them the sign-in, on the single response that mattered. Every TSV parse
  site uses a hand-walked positional extractor, and producers strip `\t`, `\n`
  and `\r` from every field.
- **A root temp file never goes in a player-owned directory.** The queue
  paragraph's argument is not only about the queue. `> "$dest.tmp"` followed by
  `chown` — the obvious way to write the appmanifest, `libraryfolders.vdf` or a
  session wish file — lets the session uid pre-create `<name>.tmp` as a symlink
  and have root truncate, rewrite and then hand over whatever it points at;
  `chown` dereferences by default and `rename(2)` erases the evidence. Build in
  root-owned `steam/staging` and `rename(2)` across; where the destination is on
  another filesystem (`/run/user/<uid>` is its own tmpfs) use `set -C`, whose
  `O_EXCL` cannot follow a symlink. Mode comes from `umask`, never from a
  `chmod` after the fact, and `chown -h`, never bare `chown`. The same applies
  to directories: `install -d` accepts an existing symlink-to-directory as
  success, so a component check plus `mkdir` is what a library path needs.
- **Temp-then-rename on both sides.** The service polls twice a second and
  deletes what it finds; a poll landing inside a truncating `open()` reads an
  empty file, discards it, and the real write goes to an unlinked inode — a
  button that does nothing, with nothing anywhere to say why.
- **`chmod` before the rename.** Godot's `FileAccess` uses `fopen()` and does
  not chmod, so a request would otherwise land `0644` under systemd's umask.
- **`rename(2)` the request aside, never test-then-read.** The request directory
  is player-owned, so between any test and any read the file could become a
  symlink or a FIFO — the latter blocking a single-threaded loop forever with
  the unit still reporting `active (running)`.
- **Re-read state on any transition, not only on `done`.** The service writes
  the result file before the state word, and a repeated request answered from
  cache may change no byte at all — so consumers load results at startup and
  render synchronously rather than waiting for a signal that will not come.
- **No octal literals in GDScript.** `0o600` is a parse error that takes the
  whole autoload down while the shell still starts and looks fine. Write `384`.
- **Logging functions write to stderr**, because data crosses function
  boundaries by command substitution and a log line on stdout becomes data.
- **`read` assigns and then returns 1 at an unterminated EOF.** Every credential
  and sidecar here is written with `printf '%s'` and no trailing newline, on
  purpose, so `read -r v < file || v=""` throws away the value it just read
  correctly. Use `|| true`. This turned a perfectly good persona sidecar into an
  empty account name, which turned a working sign-in into `sign in again`.
- **Two `local` lines when one builds a path from another.** Bash expands every
  word of a `local` before running any of its assignments, so
  `local appid="$1" file="…/$appid.acf"` reads the *caller's* `appid` under
  dynamic scoping — which usually exists and usually holds the right value, so
  the fault hides everywhere except the one caller that differs.

## The buildid problem, and where the answer actually lives

Measured 2026-08-12, so nobody has to rediscover it:

- DepotDownloader **does** tell us the depot and manifest ids. Run against
  Spacewar (app 480, anonymous) on 2026-08-12, `-manifest-only` produced
  exactly:

  ```
  out/manifest_481_3183503801510301321.txt
  out/.DepotDownloader/481_3183503801510301321.manifest
  ```

  and the `.txt` opens with `Content Manifest for Depot 481`, a
  `Manifest ID / date` line, and `Total bytes on disk : 1906055`. So the
  filename shape `manifest_<depot>_<manifest>.txt` and the `Total bytes on
  disk` line are both **measured**, not assumed — which matters, because the
  downloader's manifest parser is built entirely on them. Exit code was 0.
  `InstalledDepots` and `BytesToDownload` are therefore solvable from what we
  already run.
- DepotDownloader **never prints the buildid**. It resolves one internally
  (`Using app branch: 'public'.`) and keeps it.
- `ISteamApps/UpToDateCheck` is not a substitute: it answers only for
  dedicated-server apps. Probed live — `480` answers, `620` and `271590` both
  return `Couldn't get app info for the app specified`.
- `ISteamApps/GetAppList` is gone entirely (404, "Method not found"), and its
  replacement `IStoreService/GetAppList` requires a Web API key.

That leaves PICS appinfo over Steam's CM protocol, which is a large thing to
implement — or **the appinfo cache the hidden client already maintains**:

```
~/.var/app/com.valvesoftware.Steam/.local/share/Steam/appcache/appinfo.vdf
```

Binary VDF, holding `depots.branches.<branch>.buildid` for every app the client
knows about, kept current by the client itself as a side effect of running. It
is local, needs no network, no key and no protocol implementation — and this
appliance ships the client precisely so that it is always there.

That is the intended source. Until it is implemented, a manifest written with
no buildid hits ADR 0010's third trap and the client re-downloads what we
just fetched.
