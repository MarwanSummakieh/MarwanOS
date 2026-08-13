# ADR 0011 — Steam is baked into the image, not installed as a flatpak

Status: accepted, 2026-08-13
Supersedes [ADR 0010](0010-our-own-steam-client.md) entirely.
Adds the first third-party repository this image has ever carried.

## The decision

Steam arrives **in the image**, installed from RPM Fusion nonfree at build time,
rather than as `com.valvesoftware.Steam` installed into `/var` at first boot.

The owner's instruction (2026-08-13): *"flatpak is the worst place to get apps
because of their sandbox nature"*, and then *"let's try baking steam in with a
sign in flow while installing and if users don't want it then they should be
able to sign in again after the OS is installed"*.

## What this fixes, and what it does not

It is worth being exact, because most of what went wrong with Steam on this
machine was **not** the sandbox, and this ADR must not be read as reopening a
question that was closed for other reasons.

**Genuinely fixed by leaving flatpak:**

- **Environment no longer has to cross a sandbox.** `STEAM_MULTIPLE_XWAYLANDS`
  and `STEAM_GAME_DISPLAY_0` had to be passed with explicit `--env=` because
  `flatpak run` strips the host environment. A native client inherits them.
- **SELinux stops being a factor.** greetd leaves sessions in `xdm_t`, which
  cannot host bwrap's mount setup, so *every* flatpak died within seconds on a
  restarted session. That cost this project real time and needed a `runcon`
  escape in the session. No bwrap, no problem. (The runcon block stays: mowser
  and any future flatpak still need it.)
- **No filesystem grants.** `Games/SteamLibrary` is nested the way it is only
  because the sandbox must be granted the *parent* of a library folder — Valve
  issue #10487. A native client just writes to the path.
- **No 32-bit extension plumbing.** `org.freedesktop.Platform.Compat.i386`
  handling in flatpak-install exists solely for the sandbox.

**NOT fixed, and these are the reasons Steam was removed on 2026-08-13:**

- **gamescope's embedded mode has exactly one main-application slot**, keyed to
  `STEAM_GAME=769` — Valve's own value, which their client claims
  unconditionally. Native or sandboxed, it claims the same slot and contends
  with the shell identically. See [[gamescope-embedded-has-one-main-app]].
- **Steam Input reads the controller directly**, so Big Picture takes the Guide
  button either way.
- **Big Picture's own Power → Shut Down does nothing here**: it expects
  SteamOS's `steamos-manager` / `steamos-session-select`, which this image does
  not ship. Packaging is irrelevant to that.

So this ADR makes Steam *pleasanter to run*. It does not make Steam able to be
the machine and the shell at the same time, and nothing here should be taken as
a plan to try that again.

## The cost, stated plainly

- **A third-party repository.** The Containerfile says every package is in
  Fedora proper and that none should be added "without an ADR saying why". This
  is that ADR. RPM Fusion nonfree is the repository; `steam` is the only package
  taken from it, and that is asserted at build time so the repo cannot quietly
  become a source of anything else.
- **Image size.** Steam is 32-bit heavy and pulls a large multilib set. The
  image was 8.54 GB before this. A raw disk image is written to a 29 GB stick,
  so there is headroom, but it is not free and it should be measured rather
  than assumed.
- **The RPM is a bootstrap, not the client.** Steam self-updates into
  `~/.steam` on first run regardless. The image therefore pins how Steam
  *arrives*, never what it becomes — the same property `bootc upgrade` has for
  everything else, and a real limit on how reproducible this can be.

## Sign-in

Steam signs in through its own UI, launched as an application from the rail. The
QR flow this project wrote is **not** coming back: Valve's HTTPS token exchange
refused the tokens it minted (eresult 63, measured 2026-08-12), which is what
ADR 0010 died of.

The owner asked for a sign-in offered "while installing", with a way back for
somebody who skips it. This appliance has no installer — the raw-image route in
[ADR 0003](0003-test-targets.md) has none by design — so "while installing"
becomes **first boot**: a run-once prompt that offers to open Steam, skippable,
and reachable afterwards from the rail like any other application. Nothing
about the offer is load-bearing; skipping it must leave a working machine.

## Consequences

- `shipped-apps` and the flatpak-install unit stop being Steam's delivery path.
  Both stay for other apps.
- Steam becomes available on a machine with no network at first boot, which the
  flatpak never was.
- Removing Steam later means rebuilding the image, not uninstalling an app. That
  is the trade this whole OS already makes for everything else.
