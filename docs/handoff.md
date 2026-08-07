# Handoff — where MarwanOS is right now

**Written 2026-08-07.** This file is *current state*, not a record. It is meant to be
rewritten or deleted, unlike [phase-0-plan.md](phase-0-plan.md) and the ADRs, which
are the durable documents. If it disagrees with them, they win — and this file is
what is stale.

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
