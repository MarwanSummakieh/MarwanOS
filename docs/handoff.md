# Handoff — where MarwanOS is right now

**Written 2026-08-07.** This file is *current state*, not a record. It is meant to be
rewritten or deleted, unlike [phase-0-plan.md](phase-0-plan.md) and the ADRs, which
are the durable documents. If it disagrees with them, they win — and this file is
what is stale.

---

## The Steam client is OURS now, and Valve's is the runtime underneath (2026-08-12)

**On the owner's word:** *"remove every instance of steam currently and
reimplement the flow ... implementing my own steam client in the stores menu
where I can sign in and download my library games"*, and on downloads:
*"I would like to have my own implementation and destination of downloads eg
the games folder in home so choose whatever gives me control."*

**What went.** `steamfront` (Valve's storefront, fetched and re-rendered),
`steamproto` (its protobuf codec), `storeart` (an artwork prefetcher), their
three units, and the whole storefront UI — `stores_screen.gd` at 2217 lines,
`steamfront.gd`, `store_front_tile.gd`, `store_tab.gd`. Search, wishlist,
prices and the buy door that opened Valve's store in mowser are all gone. The
owner asked for a rebuild from zero *including* the QR sign-in that already
worked; what survives of it is a written protocol specification, not code.

**What stayed, and it is not a contradiction.** The Valve flatpak is still
installed and still supervised windowless by the session. A Steam-DRM'd game
will not start without a signed-in client answering it, so the client is a
runtime dependency in the same sense as a Proton build: it maps no window, no
button reaches it, and the only sign of it is the process pill. See
[ADR 0010](adr/0010-our-own-steam-client.md) for the argument, and
[the seam contract](steam-client-contract.md) for every path and verb.

**What is new.** Four programs under `/usr/lib/marwanos/steam` — `protocodec`
(protobuf), `steamd` (sign-in, tokens, library, art), `steamdl` (the download
queue) and `steamlaunch` (three launch tiers) — plus DepotDownloader 3.4.0
pinned into the image, two units, and a shell screen that is a library and
nothing else. Downloads land in `~player/Games/SteamLibrary`.

**Three traps, each measured rather than reasoned about, each now asserted at
build time:**

- **The old sign-in minted the wrong kind of token.** It began the QR session
  as `WebBrowser`, whose token Steam accepts for web calls and *refuses* at
  client logon. The library would have drawn perfectly while every download
  fell back to asking for a password nobody can type on a television. The
  rebuild begins it as `SteamClient`, whose token carries both audiences — one
  scan for the whole feature.
- **DepotDownloader's path is frozen.** Its credential cache lives in a
  directory named from a hash of its own absolute path, so moving the binary in
  a later image silently signs out every machine that upgrades.
- **`StateFlags 4` does not stop the client re-downloading a game.** It also
  compares build ids. A believable manifest needs the real `buildid`,
  `TargetBuildID 0` and an `InstalledDepots` manifest matching what was pulled.

**What was proven, and how.** The DepotDownloader layer builds and passes its
assertions. The shell exports (Godot's exporter fails on any parse error in a
packed script). The screen was driven under Xvfb against fixtures: three valid
tiles from five rows — the blank name and the zero appid correctly dropped —
sign-in read, a download rendered, and A on an installed game producing exactly
`flatpak run com.valvesoftware.Steam -silent steam://rungameid/620`. A
screenshot then caught what the log could not: at 220 px the state line read
*"Downloading 4..."*, the ellipsis eating the one number somebody watching a
download is looking at. Tiles are 260 px now.

Running DepotDownloader against Spacewar also settled the manifest question:
`-manifest-only` really does write `manifest_<depot>_<manifest>.txt` carrying
`Total bytes on disk`, which is what the downloader's parser is built on.

**What is NOT proven.** Nothing has touched Valve with a real token, and
nothing has run on the bench. The `SteamClient` change means even the parts
that worked before are being exercised in a new configuration. Unresolved: the
appinfo sidecar that supplies `buildid` has no producer yet, so an install
today commits with `buildid 0` and walks into the third trap; and
`/var/marwanos/store/meta` lost its only writer with `storeart`, so the details
panel has no Steam description to draw until something fills it.

---

## The browser is MOWSER: Chromium's engine inside the shell (2026-08-11/12)

**On the owner's word:** *"I wanted to fork it and make my own custom made
chromium that is only the engine inside my launcher aka mowser."* The kiosk
Chromium below lasted about a day. Kiosk mode is a *flag* on somebody else's
program — their profile, their updates, their crash dialogs, one changed
default away from a window this machine cannot dismiss. Mowser is the engine
as a **library**: CEF (Chromium Embedded Framework, the same thing Steam's own
UI is built on) linked into the shell binary, rendering off-screen into a Godot
texture, with every pixel around the page drawn by this repo.

- **`mowser/`** — a GDExtension. `MowserView` is a `Control`: it navigates,
  paints and takes input, and deliberately does nothing else. No cursor, no
  error page, no keyboard, no key bindings — those are `browser_screen.gd`'s,
  in the rail's theme.
- **The pad drives it by method call.** `pad_keys.gd` exists because the shell
  could not reach inside a foreign X client; it spawns an xdotool process per
  event. A page in this process needs none of that, so `PAD_KEY_APPS` is down
  to the terminal and the `"pointer"` dialect is now dead code (kept: the next
  mouse-first foreign app is one line from needing it).
- **The payload is 294 MB** — stripped `libcef.so` (256 MB from 1.4 GB), V8
  snapshot, resource packs, ICU, one locale, the sandbox helper. For scale,
  this image *deleted* Firefox at 344 MB for being dead weight.
- **The sandbox stays on**: `chrome-sandbox` ships SUID root, set at build time
  because `/usr` is composefs and read-only later.

**Things that cost a build each, all now commented where they bite:**

| Trap | Symptom |
|---|---|
| CEF 151 headers need **C++20** | `cef_scoped_refptr.h` won't parse |
| godot-cpp has no 4.6/4.7 branch | built from the engine's own `--dump-extension-api` instead |
| Godot's exporter **copies** the `.so` beside the binary | path must be `res://`, but the rpath must be absolute `/usr/lib/marwanos/mowser` |
| The `/usr/lib/marwanos` chmod sweep | strips SUID off `chrome-sandbox` unless the payload is pruned |
| CEF wants its data **flat** beside `libcef.so` | a `resources/` subdir aborts with `Invalid file descriptor to ICU data` |
| An in-process CEF `abort()` | kills the **shell** — a black TV. Pre-flight checks are load-bearing |
| Chromium refuses to sandbox **root** | harness only: `MARWANOS_MOWSER_NO_SANDBOX`, honoured solely at euid 0 |
| `CreateBrowser` is **async** | anything asked for before `OnAfterCreated` must be replayed |
| OSR `background_color` defaults to **transparent** | an opaque page draws as nothing |
| `String.join` needs a **PackedStringArray** | handed an `Array` it returns `""` — silently |

**Status: rendering, end to end, under the invisible harness.** A local page
opened from the Files screen draws inside the shell — heading, text and an RGB
gradient in the right channel order (which is the swizzle proving itself) with
the shell's own hint row composited over it. The chain is Files → browser
screen → `file://` → CEF renderer → `OnPaint` → `ImageTexture` → `_draw`.

**The last bug was aliasing, and it is worth remembering.** `sink_browser_ready`
replayed the pending URL as `load_url(pending_url_)` — the member passed *by
reference* into a method whose first statement is `pending_url_ = url`. The
string arrived empty, the browser stayed on `about:blank`, and three rounds of
diagnostics all reported success because every stage genuinely was succeeding.
Passing a copy fixed it.

**Still unproven: hardware.** No boot on the bench, so the sandbox path (the
harness runs as root and skips it), the real GPU, gamescope and a live network
have never seen this. That is the next thing.
---

## Steam on the appliance: the crash-loop was SELinux, and the session now heals it (2026-08-12)

**The symptom** (bench, 2026-08-11 22:22–22:25): background Steam exited with
status 1 five times in 150 seconds and the supervisor "gave up until the next
boot". The owner pressed Start on the service row at 22:27:46 and nothing
happened — the supervisor had already returned. Its output went to /dev/null,
so the journal held the counting and not the cause.

**The cause, measured on one boot of one image:** greetd's PAM stack runs
`pam_selinux`, which selects `unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023`
(`res=success` in the audit log) — and greetd 0.10.3 never applies it. The
first session of a boot went through the login lane and ran Steam fine; every
**restarted** session comes from the greeter lane (`default_session`), lands in
`xdm_t`, and under enforcing policy `xdm_t` may not `remount` `device_t` or
`dosfs_t` — which bwrap must do to build any flatpak sandbox. So on any session
after the first, **every** `flatpak run` — which since mowser landed means Steam
and every game, i.e. everything this appliance is for — died in ~2s:
`bwrap: Can't bind mount /oldroot/dev on /newroot/dev: … Permission denied`.
The gamescope-was-down confound was resolved against it: the 22:23 session's
crashes all happened with its compositor up (pid 76908, still alive at 22:39).

**The fixes (this build):**

- **The session leaves xdm_t itself.** After the systemd-cat re-exec,
  marwanos-session checks `id -Z`, probes `runcon` with a throwaway child, and
  re-execs into the exact context pam_selinux already selected. Probed before
  committed, env-guarded against loops, degrades loudly to today's behaviour.
  `setexec`, the `xdm_t → unconfined_t` transition, and the two remounts
  (denied to `xdm_t`, allowed to `unconfined_t`) were all confirmed read-only
  against the bench's live enforcing policy via `/sys/fs/selinux/access`.

  **And the first version of it would have bricked the boot.** A domain
  transition needs `entrypoint` on the file being `execve`'d, and the draft
  wrote `exec runcon "$CON" "$SELF"` while probing with `/bin/sh`. Those are
  two different files with two different types, and the bench says they answer
  differently:

  | file | type | `unconfined_t … entrypoint` |
  |---|---|---|
  | `/usr/lib/marwanos/session/marwanos-session` | `lib_t` | **DENIED** |
  | `/bin/sh` | `bin_t` | ALLOWED |
  | `/usr/bin/bash` | `shell_exec_t` | ALLOWED |

  So the probe would have said yes and the real `exec` would have failed — and
  a failed `exec` exits a non-interactive shell, greetd respawns the session,
  and the env guard does not survive the process: a respawn loop at boot speed
  with nothing on the television. The shipped line is
  `exec runcon "$CON" /bin/sh "$SELF" "$@"`, which makes the file the kernel
  checks the same `bin_t` interpreter the probe just proved and carries the
  script as data. Everything under `/usr/lib` is `lib_t`, so the alternative
  was relabelling. **If you ever add another `runcon`/`setexeccon` exec in this
  tree, exec the interpreter by name.**
- **Steam's last words survive.** `flatpak run` now writes through a
  `tail -n 40` co-process into tmpfs; an un-asked nonzero exit logs the last
  20 lines at warning level (first failure and guard-trip only). The quiet
  path stays quiet.
- **"Giving up until the next boot" is gone.** Five consecutive fast failures
  now mean a `crashed` state the shell draws (amber dot on the processes pill,
  "Crashed" on the row), retries that back off 60s→30min, and a couch retry:
  the processes menu's A press rewrites the wish file and the supervisor treats
  the fresh mtime as permission to retry immediately with a clean slate. A run
  that survives 5 minutes clears the counter. (The pill and its menu were the
  notification bell and the service menu until the 2026-08-12 menu rewrite —
  same seam, same words, renamed for what is actually behind them.)

---

## The QR sign-in was broken by a tab, and could never have worked (2026-08-12)

The store's sign-in got its first real phone approval on the bench at 22:31:38
and died one line later: *"an approved sign-in carried a token this machine
could not read"*. Everything up to that point works and is bench-confirmed —
`signin` request heard, challenge fetched, **qr.png rendered** (329 bytes,
22:31:25), shell drew *"sign-in is waiting"* then *"code on screen"*, phone
scanned, Valve returned an approval in 13 seconds.

**The cause is one shell rule.** `steamproto poll-resp` writes
`<new_challenge>\t<refresh_token>\t<account_name>`, and on an approval Valve
sends **no** new challenge — so the line starts with a tab. Tab counts as IFS
*whitespace* in the shell's field-splitting rules even when IFS holds nothing
else, so `IFS=$'\t' read -r new_challenge refresh account_name` **discards the
leading empty field and shifts everything left**: the refresh token landed in
`new_challenge`, the account name landed in `refresh`, and
`signin_store_token` was handed the string `bronzefesta` as the credential.
`jwt-sub` refused it — correctly; it is not a JWT — and the real token was
thrown away with the variable.

Two shapes hid it for a whole shipped feature: a *rotation* response puts its
value first, and `begin-resp`'s first field is a `%d` client_id that is never
empty. So the QR appeared, the QR rotated every 30s, and **only the approval**
was broken.

**This is the second time this exact trap has cost this tree a feature** —
`marwanos-storeart` hit it in its own way and already carried a hand-walked
`tsv_field`. steamfront now carries the same helper, both parse sites use it,
and the Containerfile greps both files for it plus the absence of the
collapsing `read`.

Proven without spending another scan: a synthetic approval body (field 3 =
Valve-shaped JWT, field 6 = account name, field 2 absent) through the real
`steamproto` and the real `tsv_field` yields `refresh` = the token and
`jwt-sub` = `76561198257799568`; the old parse yields `bronzefesta` and
`jwt-shape` prints `length=11 parts=1`. Rotation, empty-body and `begin-resp`
shapes all still parse.

Also from this: a refused token now logs a **shape-only** diagnosis (lengths,
part count, claim names — never material) via the new `jwt-shape` subcommand,
and `jwt-sub` accepts any SteamID-sized digit string rather than exactly 17
(explicitly *not* the fix — Valve re-validates the subject on every use).

---

## What is actually confirmed, for both of the above (2026-08-12)

Read this before trusting either section. Nothing in this build has booted on
the bench: it is **pinned** on a good deployment while the tearing
investigation owns its boot schedule, so this work was deliberately shipped
without a `bootc upgrade`.

**And then the bench confirmed it a second time, by accident.** Mid-session
somebody upgraded and rebooted it onto `ac909b1` (the mowser image; the pinned
610.57.04 deployment is now the *rollback*, and the booted one runs 610.43.03 —
flagged for whoever owns the driver pin). On that fresh boot the session and the
shell are **`unconfined_t`**, there is exactly **one** `xdm_t` denial in the
whole boot against 87 on the old one, **Steam is `running`**, and a stop/start
from the service menu at 08:29 worked. That is the same claim from the opposite
side: a **first** session comes through greetd's login lane, gets pam's context,
and everything works — which is precisely why this bug reads as intermittent and
why it went a day misattributed. The 22:03 boot's session was a *restarted* one
(greetd at pid 76800, session at 76818, nineteen minutes into a boot) and it was
`xdm_t`. Nothing else distinguishes the two.

**Measured on the bench (read-only, gamescope up, sibling session undisturbed;
deployment `a2bddec9`, now the rollback):**

- the old crash-loop and give-up, with its compositor **up** — the
  gamescope-was-down confound is dead
- the session, the shell and greetd all sitting in `xdm_t`, enforcing on
- 29 × `xdm_t → device_t remount` and 29 × `xdm_t → dosfs_t remount` denials
  this boot, plus 29 × `xdm_t → unconfined_t : system { start }` (flatpak's
  per-app scope, denied the same way)
- every permission the walk needs: ALLOWED. Every permission bwrap needs:
  DENIED to `xdm_t`, ALLOWED to `unconfined_t`
- the `lib_t` entrypoint refusal that killed the draft's `exec` line
- the QR rendering, the phone approving, and the exact refusal message

**Proven off-hardware, deterministically:** the tab-shift (real `steamproto` +
real `tsv_field`, synthetic approval body, both parses side by side); the
`crashed` row and its couch retry (real shell binary under Xvfb with a seeded
services seam — screenshot shows the amber bell badge and *Steam — Crashed*,
and A on the row writes the start wish); a full image build with the verify
block, which now also greps the two `STATE_WORDS` copies and both ends of the
tab-split contract. (That screenshot predates the 2026-08-12 menu rewrite: the
bell is now the processes pill, and the second `STATE_WORDS` copy the build
compared against no longer exists — the build asserts there is exactly one.)

**Not verified, and needs one live scan on an image carrying this:** that the
library *fills* after a good sign-in, and Install-from-the-shelf. The path
after `signin_store_token` (refresh→access exchange, GetOwnedGames,
cache-bust) has never run with a real token, and no fixture can stand in for it
— only Valve can mint the token. Also unverified: that a restarted session
really does keep its flatpaks alive now. That is the one thing only a boot can
answer.

When it is tested, note that **Install from the shelf is two presses**, not
one: A on a library tile opens the game's storefront page
(`storefront page opened for appid N`) and A on that page's action does the
install (`apps: install requested for …`). A shelf tile that seems not to
install on the first press is behaving as designed.

**One flag for mowser, untested and worth knowing before its first boot.**
Until this change the shell itself ran in `xdm_t` — measured, not inferred:
`/proc/<shell pid>/attr/current` said so on the bench. CEF's sandbox does the
same class of namespace and mount work bwrap does, and `xdm_t` is precisely the
domain that was denied it; an in-process CEF `abort()` takes the shell down
with it, which is the black TV the mowser section warns about. After this
change the session (and therefore the shell, and therefore CEF) runs as
`unconfined_t`, which is strictly more permissive — so this fix plausibly
removes a first-boot failure mowser has never had the chance to hit. **Nobody
has measured what CEF's sandbox actually needs from policy**, so treat that as
a lead, not a result: if the shell dies on mowser's first hardware boot,
`journalctl | grep denied` and the shell's own domain are the first two things
to read.

---

## The browser is Chromium in kiosk mode, and Zen is gone (2026-08-11)

**On the owner's word:** *"zen is not a controller friendly browser so we need a
replacement... we use chromium because it is simply more performant"* — plus the
standing *"this is a pure console system."* The replacement is not another
browser UI but the absence of one: the appliance ships
`org.chromium.Chromium` (Flathub) and every launch the shell makes is
**kiosk mode** — one page, full screen, no chrome — driven by the pad bridge's
pointer dialect (right stick as cursor, A clicks, shoulders scroll, home-menu
Type for text). Steam's own client is CEF, i.e. this same engine wearing
Valve's face, which is the measure of how little a checkout needs a browser's
furniture.

- **One spelling of the launch**: `Catalogue.browser_exec(target)` builds
  `flatpak run org.chromium.Chromium --kiosk --no-first-run
  --no-default-browser-check --hide-crash-restore-bubble --noerrdialogs
  <target>`. Every flag is a dialog nobody on a sofa can dismiss; the
  crash-restore one exists because the shell closes apps with `flatpak kill`,
  so every session after the first would otherwise open on a Restore bubble.
- **The store's buy door** (`store.steam.buy`) opens Valve's store page in it;
  **documents from Files** (pdf/html/txt/md/json/xml/csv/log) open in it via
  `open.org.chromium.Chromium`; both ids plus the rail card are "pointer" in
  `PAD_KEY_APPS` — which also settles the long-noted gap where Zen's rail card
  was never bridged at all.
- **Zen is out of the image entirely**: shipped-apps, the installer's
  display-name table and `:ro` grants, the `.wants` symlink, and the
  Containerfile's verify block all moved to Chromium, and the build now
  asserts Zen's id and unit are absent (same headstone pattern as Kodi).
- **Found while doing it:** the verify block's `! grep -q 'kodi'` matched the
  owner's own quoted words in shipped-apps' comments — a latent build breaker
  on main since the Kodi removal. Both absence greps are id-anchored now
  (`^tv\.kodi\.Kodi$`, `^app\.zen_browser\.zen$`).
- **Profile persistence**: the flatpak's per-app home is the browser profile,
  so a Steam checkout stays signed in across purchases; kiosk hides the
  session, it does not discard it.

---

## THE 2026-08-07 BOOT RAN, AND THE WIFI ASSOCIATED

**First journal off a stick in four attempts, and it closes the oldest open
question in the project.** Two boots that evening (`0.0.202608071627`, commit
`92535a5`, root `4f118398…`). What the journal shows:

```
marwanos-shell: wifi state: connected (Marwan 5)
```

**ADR 0004's "the Predator's wifi does not associate under MarwanOS" is dead.**
It was misdiagnosed as a hardware limitation, re-diagnosed on 2026-08-07 as
Windows Fast Startup holding the CNVi radio, and is now *demonstrated* fixed:
the radio came up, NetworkManager saw it, and the shell's new Wi-Fi seam
reported an association to a real network. `wpa_supplicant` appears in the
journal for the first time.

Everything else in the new stack also ran:

| | Evidence |
|---|---|
| netcheck | `network is online`, and it caught two real drops and recoveries |
| appscan | `scan found 2 application(s), including pending installs` |
| the rail | `installed applications: 2`, `home rail ready with 2 cards` |
| the store page | `steam install state: downloading` |
| both installers | Flathub reachable after 12 attempts; 2.6 GB pulled |

**Nothing failed. It still looked broken, and that is the finding.** The two
pending cards said *"Installing — downloading from Flathub, give it minutes"*
and then said exactly that for half an hour. A multi-gigabyte download with a
static sentence is indistinguishable from a hung machine to the only person who
can see it. Three defects behind that, all now fixed:

- **No progress.** The installer rewrites its state every 10 s with
  `1240 MB fetched, 4100 MB free` (measured by watching the filesystem —
  `flatpak install --noninteractive` prints nothing useful), logs it every
  2 minutes so the *journal* can prove afterwards that it moved, and the rail
  and store page render it live.
- **The two installs ran concurrently and fought.** Both pulled the same
  runtimes minutes apart, contending for one USB stick and flatpak's repo lock.
  Serialised behind a `flock` now.
- **Steam was a rail card AND a store page.** `pending()` did not apply the
  store exclusion the installed scan does.

**The disk is the next thing that will bite.** At shutdown: 5.3 GB free, 2.6 GB
of flatpak repo, and **neither app deployed yet**. Steam + Zen + the NVIDIA GL
runtimes may not fit in a 16 GB root. The free-space check is now re-run inside
the lock and a genuinely full disk reports `no-space` with a physical remedy —
but if it runs out, the answer is a bigger root partition, not code.

**The GPT was corrupt again when the stick came back to Windows** (fifth
occurrence, same signature). Repaired losslessly with `sgdisk -e` to read the
journal. Note this happened *after* the boot and had nothing to do with it.

---

## Where this got to (before the 2026-08-07 boot)

**The 2026-08-06 reflash never booted.** It went to a dracut emergency shell, and
the stick's own filesystems say why: nothing on any partition had been written
since the flash, `/var/log` was empty, and the XFS log was clean enough to mount
`norecovery` — so root was never mounted read-write and the failure was in the
initramfs. The GPT was corrupt in exactly the documented Windows-mid-rewrite
signature (main partition table CRC bad, backup fine, the sector-1-to-2016 gap),
with the kernel enumerating zero partitions while `blkid` still saw `PTTYPE=gpt`.
The attach had lapsed on its own again. **There was no journal to read** — that
absence is the whole finding, and it means the seven-change questions below are
still open, now three days old.

**Everything is merged into `main` (`53aab6d`).** `main` had been seven commits
behind since the PR #2 merge; it is now current, and branching off it is correct
again. Three things landed on top of the rail work:

- **A settings page**, behind its own seam (`settings.gd`), entered from the last
  card on the rail. Read-only by design — os-release, engine, display server and
  mode, adapter, claimed controller — because a row that changed something would
  need marwand to send the change to. Phase 0's "any settings UI" non-goal is
  struck through in phase-0-plan.md and ADR 0006 carries the second amendment.
- **The rail's resting position is arithmetic, not a measurement.** The old code
  waited a frame and read the focused card's live position; under held repeat
  (0.12 s) the neighbours were still shrinking (0.18 s), so the target came out
  short and the end card settled hard against the screen edge — outside the safe
  area the rail-bleed fix exists to protect.
- **The card focus ring had never drawn a single pixel.** It was a Button "focus"
  stylebox, and the full-bleed art child painted over it. It is an overlay child
  now, which is also the version that survives Phase 1's real textures.

All three were verified together on an Xvfb harness (invisible, no desktop
involvement): 13 cards, ring at 4914 px where it drew 0, the selection resting at
the safe margin under 60 ms traversal bursts, and the settings flow opening and
closing with focus restored. **None of it has been seen on the TV.**

So these are still open, and one journal read closes most of them:

| Change | What to look for |
|---|---|
| `setcap cap_sys_nice+ep` on gamescope | The `No CAP_SYS_NICE` line gone, and the perceptible lag with it |
| `video=eDP-1:d` karg ([ADR 0007](adr/0007-single-display-appliance.md)) | Lid panel dark from the first modeset — plymouth included, which no service could reach |
| `console=ttyS0` dropped | No `serial-getty` respawn noise; M2's three-boot count may start |
| Portal mask | The eleven `xdg-desktop-portal-gtk` failures gone from `journalctl -p err` |
| No cage fallback, no compositor lever | `cage` appears nowhere in the journal |
| The error screen | Untested: needs `pkill -9` five times inside a minute |
| Boot time | Exit criterion 1 is ≤15 s, and the last measured first frame was at 74 s |

The rail-bleed fix on the current stick also adds a `rail band:` / `first card
rests at x` pair to the journal, which says in numbers whether the layout landed
where it was supposed to. On this build expect `home rail ready with 13 cards`
(twelve placeholders plus settings) and `first card rests at x 96`.

**Pull the stick physically while it is still attached to WSL, and go straight to
the boot.** The 2026-08-06 stick was verified clean and then never booted,
because the attach lapsed while it sat and Windows rewrote its GPT unprompted.
That is now three corruptions from the same cause. If the flash and the pull
cannot be one continuous action, hold a distro up across the gap and re-run
`VERIFY_ONLY=yes` before trusting it.

**ADR 0007's "use a second stick" advice was deliberately set aside**, and the
reason is worth recording rather than quietly ignoring. That advice protects
against a wrong `video=` token producing a machine with no picture and no way to
edit the command line. It assumed losing the known-good *media* meant losing the
recovery path. It does not: the Predator boots Windows off its internal drive, so
a stick that does not work costs a reflash, not a machine — which is what ADR 0007
decision 2 already says when it calls the failure "recoverable by pulling the
stick". What actually had to be protected was the known-good **image**, and that
is now preserved read-only on the SSD (see below). One stick, one rollback
artifact.

## What the 2026-08-05 boots settled

Three boots, unattended oneshot harness, journal read back off the stick. Full
record in [ADR 0005](adr/0005-compositor-decision.md), which is **Accepted**:

- **gamescope is the compositor** (D4 closed). Takes DRM master on the RTX 3060,
  selects the right connector at native 3440×1440, survives screen off/on, input
  switch, and four HDMI replug cycles — the client kept the same PID across two.
- **The spanning defect is fixed**: `screens: 1`. The 2026-08-04 split-across-two-
  panels boot was cage's doing, exactly as the mechanism argument predicted.
- **Respawn after `kill -9` is 0.45 s** against a 3-second budget. The crash guard
  trips correctly at 5-in-60. D5's dev override works under gamescope.
- Two things measured and not fixed: `No CAP_SYS_NICE` on every boot (fix is in
  the image now, unbooted), and the panel runs at 60 Hz despite being
  240 Hz-capable (ADR 0005 open question 4).
- **Parked, deliberately:** a replug flicker seen once, unreproduced, outside the
  usage envelope (nobody unplugs HDMI in normal use). ADR 0005 records it. The one
  measurement that would settle it — a replug under cage — is gone with the cage
  path unless someone resurrects it for diagnosis.

## The wifi was never a driver problem (2026-08-07)

Everything written before today assumed this chassis simply does not do wifi
under MarwanOS, and treated ethernet as the only way in. That was a symptom
recorded as a hardware limitation. The 2026-08-07 journal says otherwise:

```
iwlwifi 0000:00:14.3: probe with driver iwlwifi failed with error -110
```

`-110` is `ETIMEDOUT` — the radio never answered the driver. It is not a missing
module and not missing firmware: the image carries **189 iwlwifi firmware
files**, `iwlwifi-mvm-firmware`, `wpa_supplicant`, and NetworkManager's wifi
plugin, all confirmed present by inspecting the runtime image directly. Nothing
needs adding.

`0000:00:14.3` is Intel CNVi wifi integrated into the PCH, and the host Windows
install has **`HiberbootEnabled = 1`** — Fast Startup on. Windows "Shut down" is
then a hybrid shutdown that hibernates the kernel session rather than powering
off, and the device is still claimed when MarwanOS boots. NetworkManager never
gets a wifi interface at all, which is exactly what the journal shows.

Two consequences worth carrying:

- **The fix is on the Windows side, not in the image.** `powercfg /h off`, or
  untick Fast Startup in Power Options. "Restart" also does a genuine power
  cycle where "Shut down" does not, which is a useful one-off.
- **Credentials are a separate gap.** Even with a working radio there is no
  connection profile anywhere in the image, and there is no keyboard UI to enter
  one. A profile is written per-stick into the deployment's
  `/etc/NetworkManager/system-connections/` after flashing, `0600 root:root`, and
  deliberately never committed or baked into an image.

**Not yet proven.** Fast Startup is the best-supported explanation and fits all
the evidence, but the arbiter is a boot that shows a wifi device appearing. If
it still fails, the next suspects are the Acer WMI killswitch NetworkManager
spotted (`rfkill0` on `acer-wmi`) and wifi disabled in firmware setup. USB
tethering from a phone needs no credentials and no settings change, and remains
the zero-setup fallback.

## The shell now says whether it is online, and what Steam is doing (2026-08-07)

"Steam closes immediately" off the couch decodes to: the card runs
`flatpak run com.valvesoftware.Steam`, the flatpak is not installed yet (the
first-boot download never ran, or is still running, or found no network — see
the wifi section above), so the process exits in under a second and the rail
comes back. Nothing on the TV said any of that. Now it does, without bending
the shell-is-a-renderer rule:

- **System services write one-word state files; the shell only reads them.**
  A new `marwanos-netcheck` loop probes Flathub — the download source, not a
  generic beacon — every 15 s and writes `online`/`offline` to
  `/run/marwanos/network.state` (file rewritten every cycle so a lost file
  heals; journal logs transitions only). The Flathub installer narrates itself
  into `/run/marwanos/install.<app-id>.state` (`waiting-network`,
  `no-network`, `downloading`, `no-space`, `failed`; removed on success, when
  the stamp takes over). *Those paths were `steam-install.state` until the
  installer was generalised later the same session — see below.*
- **A new `SystemStatus` autoload** (the STATUS SEAM) polls the files every
  2 s and makes no claims when the files make none — a desk run under
  `--network=none` stays clean. netcheck also writes `network.info` (one line:
  `wifi HomeNet`, `ethernet …`, `link eth0`, `none`) for the settings rows.
- Fixture lever for desk runs: `STATUS_DIR=/some/dir scripts/run-shell-wsl.sh`
  bind-mounts fixture files and sets `MARWANOS_SHELL_STATUS_DIR` (same shape
  as `MARWANOS_SHELL_WINDOWED`); edits to the fixtures show up live.

## The home screen moved to the PS5 shape (2026-08-07, same session)

At the owner's request, and recorded properly in ADR 0006's **third
amendment** (which also amends phase-0-plan's "store" non-goal):

- **Top bar, right side:** store icon and gear icon (focusable — up from any
  rail card lands on the store, down returns to the selected card), then a
  **wifi glyph next to the clock** rendering the status seam: fan when online,
  struck amber fan when offline, absent when no claim.
- **Settings left the rail** (`settings_tile.gd` deleted); the gear opens it.
  The settings screen gained live **Network / Connection / Wi-Fi rows** from
  the status seam. Read-only like every row: joining a network needs a
  keyboard UI and a write path, both marwand's; the Wi-Fi row names the
  per-stick profile instead of pretending.
- **Steam left the rail too, into the stores screen** (`Stores` seam, the
  settings pattern copied verbatim; side tabs left, page right). The page is
  rendered BY THE SHELL — wash, name, description, live install line in
  `TEXT_ALERT` for actionable failures — and **A launches Steam fullscreen on
  its storefront** (`steam://store`). Embedding the store's own UI in a pane
  is compositor work gamescope does not offer; the PS5's store tile opens a
  fullscreen app too. Quitting Steam lands back on the store page (the rail's
  restore defers to open surfaces).
- The rail is now the library alone — and, as of the fourth amendment below,
  a real one.

## The rail lists what is actually installed (2026-08-07, same session)

The twelve placeholders are **deleted**. `marwanos-appscan` enumerates desktop
entries the way GNOME's app launcher does and writes `/run/marwanos/apps.tsv`;
the `Installed` autoload polls it and the rail renders it, with **real PNG
icons** loaded off the running system. ADR 0006's **fourth amendment** has the
reasoning.

- **The filter** is `Type=Application`, not `NoDisplay`, not `Hidden`,
  `TryExec` resolves — plus **not `Terminal=true`**, which GNOME does show but
  which here would be a card that spawns something with nowhere to draw. The
  base image's own entries are all `NoDisplay` or terminal apps, so what
  appears on the rail is what first boot installs.
- **An empty rail is a designed state**: "No apps installed / Open the Store
  above to install something", A-hint hidden, focus falling to the store icon.
  That is what a fresh stick shows, and it is correct.
- **Rescans are live** — the scan re-runs when a watched directory's mtime
  moves, so an install appears without a reboot, and the rail re-focuses the
  same app **by id** rather than by index.
- **Steam's games will not appear here.** They ship no desktop entries. This
  is an *application* launcher; a Steam *library* needs marwand. Worth saying
  out loud because "only installed games should appear" is the ask, and this
  delivers installed applications — the part that is honestly reachable in
  Phase 0.

## The browser is Zen, and the installer is now generic (2026-08-07, same session)

- **Firefox is removed from the image.** The ublue base ships it — 295 MB plus
  49 MB of langpacks — and nothing here asked for it. It had to go rather than
  be hidden: `marwanos-appscan` lists what is installed with no deny-list for
  "things we would rather you did not see", so an image carrying Firefox would
  put it on the rail. `firefox-langpacks` is named explicitly in the removal
  because it requires `firefox`; nothing else does.
- **Zen installs from Flathub on first boot**, as `app.zen_browser.zen`, the
  same way Steam does.
- **`marwanos-steam-install` is gone**, replaced by
  `marwanos-flatpak-install@.service` — a **template**, instanced per app id,
  with the script taking the id as its argument. Two apps made the choice
  explicit: either a near-copy of a 100-line installer with one identifier
  changed, or the identifier becomes a parameter. Adding an app is now one
  `.wants` symlink in the Containerfile.
- **State file names changed with it**: `/run/marwanos/install.<id>.state`
  (now `<state>TAB<display-name>`) and the stamp `/var/marwanos/installed.<id>`.
  No migration concern — no stick has ever booted with Steam installed.
- **Pending installs now show as rail cards** so a first boot explains itself
  during a multi-hundred-MB download: the scanner emits a record per pending
  install, the card carries the app's name and narrates the state, and
  `tile.gd` refuses to launch it (the launch seam stays policy-free).

**A launch from the store page while Steam is not ready still blink-launches**
— `flatpak run` starts, exits inside a second, the page returns. Left that way
on purpose: the launch seam stays policy-free in Phase 0 (launcher.gd's
header), the narration is the line directly under the person's focus, and
refusing launches is marwand's job when it owns install state in Phase 1.

**Unbooted, like everything else this session** — needs a rebuild and a
reflash. Verified on the Xvfb harness instead (status files, live flips, the
top-bar walk, stores open/close, settings rows). Phase 1 retires the files:
marwand pushes the same states over the WebSocket and the `SystemStatus`
signals survive the rewiring.

## Milestone state

| | State |
|---|---|
| **M0** — build/deploy loop | **Complete** (2026-08-02) |
| **M1** — session + the A/B decision | **Complete** (2026-08-05). gamescope, [ADR 0005](adr/0005-compositor-decision.md) |
| **M2** — silent boot | Partial. Both pending kargs are now **on the stick** (`console=ttyS0` dropped, `video=eDP-1:d` added) and verified in the UKI's command line, but unbooted. The three-boot camera count can start on this stick. The 31-second black gap is diagnosed-adjacent (compositor handover) but not formally closed |
| **M3** — shell skeleton | Exit criteria 2 and 3 **passed on hardware** (as the grid). The home rail ran on hardware 2026-08-06 — it drew and navigated. Since then, all desk-verified and **unbooted**: the crop fix, a settings page, the rail resting-position fix, and a focus ring that had never drawn. Outstanding: couch test, controller hotplug, a real guard-trip of the error screen |
| **M4** — guardrails + exit run | **Untouched** |

## The current stick

**Reflashed 2026-08-07 from `main` @ `53aab6d` and VERIFIED.** It carries
`MarwanOS (Phase 0, 0.0.202608070940)` — the rail-bleed fix plus the settings
page, the rail resting fix and the focus ring. Image file at
`/var/tmp/settings-out/image/disk.raw`. Not yet booted.

```
boot UUID  : 29a49b23-a3d0-40d8-b4ee-2f637bdcd022
root UUID  : 87325747-0665-470c-adb9-ec808bdf081d
```

Identify a stick by UUIDs, never by memory — every build has had its own, and
there are now four sets in play:

| UUIDs | Build | Where |
|---|---|---|
| `29a49b23…` / `87325747…` | `0.0.202608070940`, settings + rail resting + ring | **on the stick now** |
| `808ec849…` / `6710ff47…` | `0.0.202608060857`, rail bleed fixed — **never booted**, GPT corrupted before it could | `/var/tmp/rail2-out/image/disk.raw` |
| `37b88f9d…` / `01c4b345…` | `0.0.202608052341`, booted and ran, cards cropped at the sides | `/var/tmp/rail-out/image/disk.raw` |
| `6487cf7d…` / `010befbf…` | `0.0.202608051352`, the 2026-08-05 known-good | `/var/lib/marwanos-images/` |

The command line baked into its UKI, which is the thing that cannot be edited at
boot and therefore the thing worth reading before blaming anything else:

```
… quiet splash loglevel=3 rd.udev.log_level=3 systemd.show_status=false
plymouth.ignore-serial-consoles vt.global_cursor_default=0 video=eDP-1:d
ostree=… usb-storage.quirks=346d:5678:u console=tty0
```

Read it back out of the stick itself with:

```sh
objcopy -O binary --only-section=.cmdline /path/to/esp/EFI/BOOT/BOOTX64.EFI /dev/stdout
```

```sh
VERIFY_ONLY=yes scripts/flash-usb.sh /var/tmp/rail-out/image/disk.raw /dev/sde
```

### The rollback artifact

`/var/lib/marwanos-images/known-good-0.0.202608051352-from-21151fc.raw` — the exact
image that booted successfully three times on 2026-08-05, kept read-only (0444) so
no build can point `OUT_DIR` at it. It is **already UKI-processed**, so putting it
back is a plain write with no `make-usb.sh` step:

```sh
FLASH_CONFIRM=yes scripts/flash-usb.sh \
    /var/lib/marwanos-images/known-good-0.0.202608051352-from-21151fc.raw /dev/sde
```

**Pull sticks physically while still attached to WSL.** Windows rewrites the GPT of
any removable disk it enumerates; it has now corrupted this stick **twice**
(2026-08-05 and again on 2026-08-06, minutes after a clean verify). Both times
`sgdisk -e` repaired it in place with no reflash — both GPT entry-array copies
survive that failure, and the filesystems are never touched.

The second time taught the thing the first one did not. **The attach lapses on its
own.** `usbipd attach --wsl` holds only while a WSL 2 distribution is *running*,
and WSL shuts its distros down when idle; when the last one goes, the stick
reverts to `Shared` and Windows enumerates it with nobody having touched
anything. So it is not only `usbipd detach` that hands the stick back — walking
away does too.

Treat a flash and the physical pull as one continuous action. If they cannot be,
pin a distro open across the gap:

```powershell
Start-Process wsl.exe -ArgumentList "-d","FedoraLinux-43","-e","sleep","14400" -WindowStyle Hidden
```

and re-verify before booting regardless. The signature to recognise, from
`sgdisk -v`, is a gap between the main metadata at sector 1 and the main
partition table at sector 2016 — that is Windows caught mid-rewrite, not a dying
stick.

### Reading a journal off a stick after a boot

```powershell
& "C:\Program Files\usbipd-win\usbipd.exe" attach --wsl --hardware-id 346d:5678
```

```sh
journalctl -D <root>/ostree/deploy/*/var/log/journal -b -1 -t marwanos-session -o cat
```

`-t marwanos-session`, never `-u greetd`: the session's processes live in
`session-cN.scope` and everything they print carries that one tag.

## The desk loop

`scripts/run-shell-wsl.sh` runs the real export (real toolchain, real runtime
image, containerised) in a window on WSLg. `ERROR_SCREEN=1` draws the error frame
instead. It answers layout/focus/theming questions only — it renders on llvmpipe
with no `/dev/dri`, so it says **nothing** about performance, fullscreen behaviour,
or anything in ADR 0005's territory.

```
wsl -d FedoraLinux-43 -u root -e bash scripts/run-shell-wsl.sh
```

## Environment cheat sheet

Everything Linux-side happens in the WSL distro **`FedoraLinux-43`**, which is not
the default — a bare `wsl -e bash` fails outright.

```
wsl -d FedoraLinux-43 -u root -e bash /path/to/script.sh
```

Put anything non-trivial in a script file first. PowerShell expands `$(...)`,
`$VAR` and `$?` before the string reaches WSL, and that has produced wrong
diagnoses on this project more than once.

Build artifacts go under `/var/tmp/`, never `/mnt/c` — 17 GB through the drvfs
bridge is glacial.

### The flash pipeline, in order

```sh
scripts/build-push.sh --no-push                       # Containerfile assertions are the first gate
OUT_DIR=/var/tmp/out SSH_KEY_FILE=/mnt/c/Users/brain/.ssh/id_marwanos.pub \
    scripts/make-installer.sh raw
EXTRA_KARGS="usb-storage.quirks=346d:5678:u console=tty0" OUT_DIR=/var/tmp/out \
    scripts/make-usb.sh                               # NOT optional -- see below
FLASH_CONFIRM=yes scripts/flash-usb.sh /var/tmp/out/image/disk.raw /dev/sde
```

`OUT_DIR` is per-build by convention (`m1-out`, `m3-out`, `panel-out`, …) — write
down which directory a stick came from at flash time, or be reduced to matching
UUIDs later.

`make-usb.sh` is the step that is easy to skip and fatal to skip: this Predator's
firmware cannot run GRUB from USB, so a raw bootc image boots perfectly in QEMU and
does nothing on the target. It builds a UKI at `EFI/BOOT/BOOTX64.EFI` and renames
`EFI/fedora` away.

### Traps that have already cost days

Each of these is documented at length where it bites; this is only the index.

| Trap | Where it is written up |
|---|---|
| Writing a GPT image to a larger stick leaves an invalid partition table — boots, then dracut times out on a root UUID that is present | `scripts/flash-usb.sh` header |
| Windows rewrites the GPT of any removable disk it enumerates. **Pull the stick physically; never `usbipd detach`** | same |
| `bootc upgrade` does not change what a stick boots — the UKI's baked cmdline wins | `scripts/make-usb.sh` header, `dev-setup.md` §5 |
| No boot menu exists on this target, so a bad karg cannot be edited at boot | [ADR 0007](adr/0007-single-display-appliance.md) §4 |
| `/opt` and `/usr/local` are ostree symlinks into `/var`; installing there fails at build time | `os/Containerfile` (the Godot toolchain lives at `/godot`) |
| `usermod -aG` silently no-ops when the group is only in `/usr/lib/group` | `os/Containerfile`, the sysusers block |
| Piping `lsinitrd` into `grep -q` under `pipefail` exits 141 | `os/Containerfile`, the initramfs assertions |
| `MARWANOS_*` ARGs must stay at the bottom, or a timestamped version invalidates dnf and dracut every build (515s vs 70s) | `os/Containerfile` |
| ~~The Predator's wifi does not associate under MarwanOS~~ — **misdiagnosed; see below** | [ADR 0004](adr/0004-session-compositor-scaffold.md) |
| Windows Fast Startup leaves the CNVi wifi claimed, so `iwlwifi` probe times out — **confirmed and cleared 2026-08-07: with Fast Startup off the radio associates** | this file, 2026-08-07 |
| A download with no visible progress reads as a hung machine; narrate bytes, not phases | `os/files/usr/lib/marwanos/flatpak-install`, `progress_ticker` |

### VM harness

QEMU + OVMF inside WSL, booting the real raw image with a diagnostic unit injected
into the ostree deployment before boot. It proves everything except the two things
a VM structurally cannot: no NVIDIA DRM device, no eDP panel. The pattern —
loop-mount partition 4, write `/etc/marwanos/diag.sh` plus a `multi-user.target`
oneshot into the deployment, boot with `-serial file:` — is worth reusing verbatim.
Note the image no longer carries `console=ttyS0`; add it back per-run via
`EXTRA_KARGS` if serial capture is wanted.

---

## Corrections a fresh session should not re-derive

- **The shell does not run native Wayland in the session.** gamescope's XWayland
  is the path; `DisplayServer.get_name()` says `X11` and is not evidence about
  the compositor. The session script's own log line is the only oracle.
- **Gamepad input does not pass through the compositor** (ADR 0006 finding 5), so
  a controller failure is never evidence about the compositor decision.
- Both of the above were stated confidently — and wrongly — by research agents
  before anyone measured them. Keep the adversarial verify stage on any fan-out,
  and treat a measured run as the arbiter over a well-sourced claim.

## Wi-Fi can be set up from the couch now (2026-08-07, same session)

The 2026-08-07 boot failed to bring the radio up, and that exposed the real
cost of "settings are read-only": **the appliance could not be repaired from
itself.** Every recovery path needs a network, and giving it one meant a second
computer and a hand-written NetworkManager profile. ADR 0006's **fifth
amendment** reverses that, for Wi-Fi only.

- **`marwanos-wifi`** (new service) owns every `nmcli` call. It writes
  `/run/marwanos/wifi.state` (`no-device`, `rf-killed`, `idle`, `scanning`,
  `connecting`, `connected`, `failed` + detail) and `/run/marwanos/wifi.networks`
  (`ssid TAB signal TAB security TAB in-use`, deduped by SSID keeping the
  strongest, sorted by signal).
- **The shell asks by writing a file** — `/run/marwanos/wifi/request`, three
  verbs (`scan`, `connect`, `forget`), one field per line. This is the first
  seam here that goes both ways. It is deliberately narrow: no "run this", and
  the SSID reaches `nmcli` as an argv element, never interpolated — anyone in
  radio range can name an AP `; rm -rf /`.
- **Passphrase handling**, stated plainly: it lives in that request file
  (tmpfs, 0600, 0700 player-owned dir) between the shell writing it and the
  service consuming and deleting it. Nothing logs it — the shell logs the SSID
  and a character count; the service truncates nmcli's error text at the word
  `password` because some failure paths echo it back.
- **On-screen keyboard** (`keyboard.gd`): 5×10 grid plus Shift/Space/Delete/Done,
  every key a real focusable Button with an explicit neighbour table. Moving
  between rows of different widths maps by proportion, not index. Masked entry.
  The input map grew from six actions to **eight** — `ui_shell_x` (Shift) and
  `ui_shell_y` (Delete, and Forget on the network list), both shortcuts for
  on-screen keys rather than requirements.
- **`no-device` is a first-class screen**, not an empty list: it names Windows
  Fast Startup as the likely cause and says what to do. That is this machine's
  actual failure, and an empty list would send someone toward the router.
- **`forget`** exists because a network saved with a wrong passphrase otherwise
  fails on every boot with no way to clear it from the couch.

Still read-only: every other settings row. This is one exception with a named
justification, not a mutable settings surface.
