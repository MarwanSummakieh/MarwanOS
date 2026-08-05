# Phase 0 — the spine

> **Goal:** Cold boot to a controller-navigable fullscreen shell with no text, no cursor, no login, no desktop, and no reachable escape hatch — plus a one-command path to deploy a new build. Nothing else. If this works, everything after it is features.

**Non-goals:** library, store, guide overlay, Proton, Bluetooth, sleep/resume, any settings UI. Updates happen via `bootc` CLI over SSH; that's fine for now.

## Hardware prerequisites

| Item | Requirement | Notes |
|------|-------------|-------|
| Target box | **Resolved: the Predator (RTX 3060 Laptop, Ampere), booted from an external USB SSD** | Baseline is Turing (RTX 20 / GTX 16) or newer on `nvidia-open` — NVIDIA's 590 branch dropped Pascal and older to a frozen legacy driver, so this is a floor, not a preference. Ampere clears it. No hardware purchase needed to start. [ADR 0002](adr/0002-nvidia-baseline-and-base-image.md) |
| VM target | Hyper-V VM, snapshotted | All of M0, most of M2, all of M3. **Cannot cover M1** — no NVIDIA DRM device exists in a VM. [ADR 0003](adr/0003-test-targets.md) |
| Build host | **Resolved: Fedora VM on the Predator**, 4 vCPU / 8 GB / 60 GB, `podman` | WSL2 is fine for build-and-push, but not for `bootc-image-builder`. Don't run both VMs at once on 16 GB |
| Controller | USB wired gamepad | Bluetooth is Phase 3; every console bootstraps pairing with a cable |
| Display | The actual TV over HDMI | TV quirks (overscan, HDMI-CEC weirdness, resolution handshakes) are part of what Phase 0 must survive |
| Dev access | Keyboard + SSH | Dev mode only — see M4 guardrails |

## Architecture

The boot chain, which is most of what Phase 0 builds:

```
UEFI firmware (vendor logo)
  └─ GRUB (hidden, timeout 0)
      └─ kernel + initramfs        ← nvidia-drm early KMS so plymouth can draw
          └─ plymouth splash       ← covers everything from here to first shell frame
              └─ systemd
                  └─ greetd        ← autologin as `player`, no password, tty1
                      └─ session script
                          └─ gamescope (plan A) or cage (plan B)   ← DRM master
                              └─ shell (Godot)                     ← splash drops on first frame
```

And the deploy loop, which comes first chronologically:

```
edit repo → podman build → push to registry → (on target) bootc upgrade → reboot
```

### Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| D1 | Base image | ~~Universal Blue NVIDIA base~~ **Revised: `ghcr.io/ublue-os/base-main:43` + `akmods-nvidia-open:main-43`, both pinned by digest** | `base-nvidia` is abandoned upstream (newest real tags are 2023). Universal Blue now ships NVIDIA as prebuilt akmods RPMs copied into a minimal base, which preserves the actual principle — never compile an NVIDIA module yourself. Tags are coupled (`43` ↔ `main-43`); `scripts/bump-base.sh` hard-fails on a mismatch. [ADR 0002](adr/0002-nvidia-baseline-and-base-image.md) |
| D2 | Image registry | GHCR (free, public repo is fine — nothing secret in an OS image) | A LAN registry is faster but needs insecure-registry config on the target; revisit if push/pull time hurts |
| D3 | Autologin | `greetd` with the session command directly in config | Purpose-built, tiny, no display-manager baggage; creates a proper logind session so the compositor can take DRM master |
| D4 | Compositor | Plan A: gamescope as session compositor. Plan B: cage + nested gamescope per app. **Timeboxed spike in M1 — 3 days, then decide and write an ADR** | gamescope-as-DRM-master is the least-tested path on NVIDIA. cage is a kiosk compositor that exists precisely to run one app fullscreen forever. Shell code is identical either way |
| D5 | Shell delivery | Baked into the image at `/usr/lib/marwanos/shell/`; session script prefers `/var/marwanos/dev-shell/` if present **and** dev mode is on | Image rebuild + reboot per UI tweak would kill iteration speed. `scp` a fresh Godot export to the dev path, restart the shell process, ~10-second loop |
| D6 | Escape hatches | No getty on tty1, ever. SSH and a tty2 getty exist only when `/var/marwanos/devmode` flag file is present | The "no reachable desktop/terminal" thesis, enforced from day zero, with a deliberate dev-mode bypass that a normal user would never trip |
| D7 | Secure Boot | Disable it on the target for Phase 0 | NVIDIA kernel modules + Secure Boot means key enrollment (ublue supports it via MOK). Real problem, wrong phase — revisit if MarwanOS ever ships to other people |

## Milestones

### M0 — the build/deploy loop (~1 week)

No OS work until the factory works.

Scaffolded (2026-08-02) — everything below is written and unverified until it has run once:

- [x] `os/Containerfile`: base + akmods pinned by digest, initramfs regenerated for early-KMS plymouth, build-info stamp as the trivial-change target
- [x] `os/files/usr/lib/bootc/kargs.d/00-marwanos.toml`: NVIDIA kargs only; silent-boot args are M2's job
- [x] `scripts/build-push.sh`, `scripts/bump-base.sh`, `scripts/make-installer.sh`
- [x] `docs/dev-setup.md`: the loop, documented

Verified by a real build (2026-08-02, WSL2 `FedoraLinux-43` + podman 5.8.4):

- [x] **The image builds.** `bootc container lint`: 13 checks passed, 0 warnings
- [x] akmods RPM paths confirmed against reality — the assertion in STEP 6 passes
- [x] NVIDIA **610.43.03** open modules on kernel **7.1.5-101.fc43**, well clear of the 590 cutoff
- [x] `nvidia.ko`, `nvidia-drm.ko`, `nvidia-modeset.ko`, `nvidia-uvm.ko` are all **inside the initramfs** — the early-KMS precondition M2's silent boot depends on, confirmed now rather than discovered in M2
- [x] kargs file and build-info stamp land correctly in the image

- [x] `bootc-image-builder` runs in WSL2 — **the Fedora build VM is deleted from the plan** ([ADR 0003](adr/0003-test-targets.md))
- [x] `marwanos.vhdx` built (6.6 GB, 299 s) and staged at `~/Hyper-V/marwanos.vhdx`
- [x] `root-fs-type = xfs` declared by the image; the ublue base does not set it and bib refuses to build without it
- [x] **Loop time measured:** cold build 515 s, version-bump rebuild **70 s** with 8/12 steps cached. Comfortably inside the 15-minute budget

Deployment, in the order it actually happened:

- [x] Package public on GHCR; no PAT exists anywhere — CI pushes with its per-run token
- [x] Hyper-V target VM created and booted — **it failed**, dropping into dracut emergency mode
- [x] Root cause found: our initramfs regen silently dropped the `ostree` dracut module, so nothing could assemble `/sysroot`. Fixed with `--add ostree` plus a build-time assertion. Verified: `ostree` present, 7 hits, matching the base exactly
- [x] **The target boots and the system is healthy.** Verified from its own journal: SELinux policy loaded, **zero failed units**, no enforcing AVC denials, sshd listening, DHCP lease acquired
- [x] SSH "Permission denied" turned out to be entirely client-side — a passphrase-protected key plus `BatchMode=yes`. Nothing was ever wrong with the target. See the troubleshooting entry in [dev-setup.md](dev-setup.md) before ever debugging this again
- [x] **SSH into the target works.** Dedicated `marwanos-dev` key, loaded via `ssh-agent`
- [x] **Kernel args verified end-to-end on the running target.** `/proc/cmdline` carries all four: `nvidia-drm.modeset=1 nvidia_drm.fbdev=1 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau` — baked in the image, never set by hand. M0's karg mechanism is proven
- [x] Target state confirmed: `systemctl is-system-running` = **running**, zero failed units, SELinux **Enforcing**, root on **xfs** per our `root-fs-type`, persistent journal live (12.1 MB)
- [x] `bootc status` tracks `ghcr.io/marwansummakieh/marwanos:latest`; target has DNS and HTTPS egress to ghcr.io
- [x] **Pushed to GHCR via GitHub Actions.** Runners build and push, so the ~7 GB never crosses a home connection and no PAT exists to leak — `GITHUB_TOKEN` is injected per run and dies with the job. `scripts/build-push.sh` remains the manual fallback
- [x] **`bootc upgrade` verified.** `1.2.0-journal` (local) → `0.0.202608021759` / commit `efc77ba` (CI). Digest `cf30658…` → `1d791d2…`
- [x] **`bootc rollback` verified.** Back to `1.2.0-journal`, digest `cf30658…`. `systemctl is-system-running` = running and SELinux Enforcing at every step

**M0 COMPLETE (2026-08-02).** The factory works: source in git, image built by CI, deployed by `bootc upgrade`, and a bad build undone by `bootc rollback`. (Three stale checklist lines that previously sat below this banner — kargs, the anaconda-iso route, rollback — were removed 2026-08-03: two were already ticked above, and the installer-ISO route is superseded by the raw-image + UKI path in [ADR 0003](adr/0003-test-targets.md).)

**Acceptance:** bump `MARWANOS_VERSION`, build, push, `bootc upgrade`, reboot, `cat /usr/share/marwanos/build-info` shows the new value on the target. Then roll it back. Total loop time measured and written down (target: under 15 minutes; the shell dev loop in D5 is the fast path).

### M1 — session bring-up + the plan A/B decision (~1–2 weeks)

Scaffolded in the image (2026-08-03, unverified on hardware — see [ADR 0004](adr/0004-session-compositor-scaffold.md)):

- [x] `player` user (sysusers.d, uid 1000 pinned), `greetd` autologin on tty1, `getty@tty1`/`autovt@tty1` masked
- [x] Session script tries gamescope (plan A) and falls back to cage (plan B), with `vkcube` as placeholder, the D5 dev-override path, M3's supervision loop, and an A/B lever at `/var/marwanos/compositor`
- [x] NVIDIA **userspace** driver installed from the akmods sidecar — the image previously carried only kernel modules, which would have made every M1 gate fail in a way indistinguishable from a compositor problem

Still to do, on hardware:

- [ ] **Plan A spike (3 days max), on bare metal only:** gamescope as DRM-master session on the NVIDIA driver — does it start, render, survive mode switches, handle the TV's native resolution? **Scope narrowed:** this is porting a known-good config into a minimal image, not proving feasibility. The session mined `ChimeraOS/gamescope-session` — the upstream bazzite forks; the `bazzite-org/gamescope-session` repo this plan previously named no longer exists publicly
- [ ] Confirm which card owns the HDMI output before trusting any result — the session script pins gamescope to the NVIDIA device by PCI id and logs what it found; verify with `nvidia-smi` and the sysfs checks in ADR 0004 (`drm_info` is not in the image, deliberately — see the ADR's open questions)
- [ ] **Plan B fallback:** `echo cage > /var/marwanos/compositor && systemctl restart greetd` — no rebuild needed
- [ ] Decision recorded in `docs/adr/0005-session-compositor-decision.md` (0004 is the scaffold; the plan's original `0001` reference predated the ADR series)
- [ ] No desktop environment, no display manager, no portal packages in the image at all

**Acceptance:** power on → autologin → fullscreen placeholder renders on the TV at native resolution. `loginctl` shows one session for `player`; nothing else owns the display.

### M2 — silent boot (~1–2 weeks, fiddly by nature)

- [ ] Kernel args: `quiet`, `splash`, `vt.global_cursor_default=0`, `nvidia-drm.modeset=1`, `nvidia_drm.fbdev=1`, plus log-level suppression
- [ ] GRUB menu hidden, timeout 0 (rescue entry reachable via held key — that's firmware-level, acceptable)
- [ ] Plymouth with a plain dark theme (MarwanOS logo art is a later luxury); NVIDIA module in initramfs early enough that plymouth draws on the real display
- [ ] `getty@tty1` masked; no console text on any hotplug/error path
- [ ] **Drop `console=ttyS0`** — `bootc-image-builder` adds it by default, and on hardware with no serial port it makes `agetty` fail and respawn every 10 seconds forever (`failed to get terminal attributes: Input/output error`, observed continuously in the M0 target's journal). Wasteful, noisy in the logs, and a text-on-console risk for the silent-boot gate. `--no-default-kernel-args` is the lever
- [ ] Flash hunt: plymouth must hold the splash until the compositor's first frame (`plymouth deactivate` sequencing in the session script)
- [x] ~~Journald persistent logging on, so silence never costs debuggability~~ **Pulled forward into M0.** A target became unreachable over SSH and took its journal with it on shutdown, making the failure undiagnosable. On a machine whose entire premise is no visible text and no terminal, volatile logs are not a Phase-2 nicety — they are the only way any failure before login is knowable. Shipped as `/usr/lib/systemd/journald.conf.d/10-marwanos-persistent.conf`

- [ ] **Close the 31-second black gap between the splash ending and the shell's first frame.** Measured off the 2026-08-05 film: splash reaches the external display at t=15 s, that display goes black at t=43 s, the laptop panel keeps the splash until t=59 s, the grid draws at t=74 s. The blackout is *staggered* — one display taken, then the other sixteen seconds later — which is the shape of a handover that happened twice, i.e. what a gamescope readiness timeout followed by a cage start would look like from a camera. Exit criterion 1 allows 15 s for the whole boot, so this gap alone is twice the budget. Diagnose it from the journal, not the film

**Acceptance:** film the boot with a phone camera. Frame-by-frame: vendor logo → splash → shell, zero frames of text, cursor, or console. Same result on three consecutive cold boots.

The 2026-08-05 run had zero frames of text, cursor or console across all 100 seconds — the silent-boot gate itself held. It is **not** banked as 1 of the 3, for two reasons: it booted from the USB stick rather than an installed target, and `console=ttyS0` is still in the image. Start counting the three after that karg is dropped.

### M3 — shell skeleton (~1–2 weeks)

Scaffolded (2026-08-05, unverified anywhere — see [ADR 0006](adr/0006-shell-skeleton.md)):

- [x] Godot 4 project in `shell/`: tile grid, gamepad focus navigation (d-pad + left stick), A activates, B backs out. All six actions are defined explicitly at device `-1`: Godot's defaults bind no joypad button to `ui_accept` or `ui_cancel` at all, and its directional defaults answer only joypad index 0
- [x] Focus repeat implemented in the shell. There is no key repeat for a gamepad in any Godot 4.x — a held d-pad moves focus exactly once — so a grid without it reads as broken from the couch while every line of code works as designed
- [x] TV-safe margins (~5% inset: 96 px horizontal, 54 px vertical at 1080p) and 10-foot type sizes from the first commit
- [x] "Launch" swaps to a placeholder fullscreen scene and returns — the seam where Phase 1's real launching bolts in
- [x] Headless Godot export in the image build, from a checksummed upstream release (4.7.1; the `GODOT_*` ARGs in `os/Containerfile` are the source of truth) in a builder stage that never ships. No hand-exported binaries in git, and no Godot editor in the appliance — it is a GDScript interpreter, which is the same category of object D6 exists to keep off the machine
- [x] Single self-contained executable (`embed_pck=true`), so `BAKED_CLIENT` and D5's override path both stay one `[ -x ]` check and the session script needs no restructuring
- [x] Session script: `BAKED_CLIENT` now points at `/usr/lib/marwanos/shell/marwanos-shell`. The supervision loop, crash-window guard and dev override were scaffolded in M1 and are unchanged
- [x] The shell sets its own fullscreen mode and hides its own cursor rather than relying on `--force-windows-fullscreen` and `--hide-cursor-delay 1`, which are plan A only — cage has no equivalent of either ([ADR 0004](adr/0004-session-compositor-scaffold.md) finding 9)

Still to do, on hardware:

- [ ] **The shell comes up at all, inside the real session.** This is [ADR 0004](adr/0004-session-compositor-scaffold.md)'s step 6 and it should run before any more UI is built on top: fullscreen at the TV's native mode, correct scaling, no Wayland protocol error in the journal
- [ ] Controller hotplug: unplug/replug mid-session keeps working; explicit player-1 notion, keyed on the joypad GUID rather than the index. Godot's hotplug signals have open upstream bugs in both directions, so the fallback behaviour is a hardware answer
- [ ] Navigate the grid from the couch — the one gate no automated check can stand in for. Focus visibility and the ~5% inset are judged against the TV, like M2's camera test
- [ ] `kill -9` the shell over SSH → back at the grid in under 3 seconds, no text at any point
- [ ] D5 dev override exercised end to end on a running target: `scp`, restart, iterate in seconds
- [ ] Loop guard's error screen. The guard itself works — 5 crashes in 60 s stops the respawn — but it holds an empty screen rather than drawing anything. A plymouth-style error frame is still outstanding, and it is the last thing between a broken shell and a black TV with no explanation

Most of this is VM-testable ([ADR 0003](adr/0003-test-targets.md)), and the supervision and `kill -9` gates should be run there first. The couch test is not: it needs the TV over HDMI and a real pad.

**First hardware run (2026-08-05), filmed for 100 s and read frame by frame:**

- [x] **The shell comes up inside the real session, on the real GPU.** The grid draws, the header reads `Player 1  DualSense Wireless Controller`, focus moves between tiles, **A** swaps to the placeholder scene and **B** returns to the grid. That is exit criterion 2 demonstrated on hardware for the first time. Nothing crashed in 100 seconds and no frame of the film contains console text
- [ ] **Fullscreen at native resolution is NOT met, and the cause is not the desk setup.** The shell was handed one surface covering *both* connected displays and laid itself out across the pair: the header's left end — the `MarwanOS` wordmark from `_build_header()` in `shell/src/shell_root.gd` — rendered on the laptop panel, while the right end of that same `HBoxContainer` (`Player 1  DualSense Wireless Controller`) rendered on the external display, with the grid's first column falling in the gap between the two panels. One row of one container, split across two screens, is not a Godot scaling failure: the scene is intact and `stretch/aspect="keep"` did exactly what it promises. It is the compositor handing the client an output layout spanning every connected display. This is also the strongest evidence available for M1's decision, because the two plans cannot both produce it — gamescope is given `--prefer-output` and drives exactly one connector, while cage has no output selection at all and wlroots enables every output it finds. Confirm against the journal before writing ADR 0005; do not infer the compositor from geometry alone
- [ ] **Pin the shell to one output.** Two monitors on a gaming machine is the normal case, so this is a defect to fix rather than a configuration to avoid. Under plan A `--prefer-output` already covers it; under plan B there is no compositor-side lever, so the shell has to choose its own screen. `Kiosk._assert_display_policy()` currently sets `MODE_FULLSCREEN` and never touches `Window.current_screen`, and it logs neither the screen count nor the size it ended up with — which is why the geometry above had to be reconstructed from a phone video instead of read out of `journalctl`. Instrument first, then pin

**Acceptance:** navigate the grid from the couch; `kill -9` the shell over SSH → back at the grid in under 3 seconds with no text visible at any point.

### M4 — guardrails + exit run (~a few days)

- [ ] **Decide the automatic-update policy, and mask the timer if the answer is no.** The base image ships an update timer that is *on*: during M0 it fetched and staged a CI build with nothing asked of it, and the next reboot silently changed the running OS. For an appliance that is meant to boot into a game, an unattended OS swap between sessions is a behaviour to choose deliberately, not inherit. `systemctl mask bootc-fetch-apply-updates.timer` in the image if updates should only ever be operator-initiated
- [ ] `/var/marwanos/devmode` flag: gates sshd and the tty2 getty; absent by default in a fresh image
- [ ] Audit the image for accidental escape hatches: no display manager, no desktop session files, no VT-switch into a getty that shouldn't exist
- [ ] `systemd-analyze` boot-time budget recorded; obvious offenders (NetworkManager-wait-online and friends) deferred out of the boot path
- [ ] Full exit-criteria run, filmed

**Exit criteria (the gate to Phase 1):**
1. Power on → shell in ≤15 s, zero text/cursor frames, verified by camera
2. USB controller navigates; A launches placeholder; B returns
3. `kill -9` the shell → restarts into the grid, silently
4. `bootc upgrade` + reboot deploys a new build; `bootc rollback` recovers a bad one
5. With devmode off: no TTY, desktop, or terminal reachable from controller, keyboard, or VT switching

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| gamescope won't run as DRM-master session on NVIDIA | Blocks plan A | **Downgraded:** known working upstream on NVIDIA; bazzite ships it. Timeboxed spike remains, but as integration work. Plan B (cage) still a same-week pivot |
| Hybrid graphics on the laptop makes M1 measure the Intel iGPU | False green on the project's central question | Drive the TV over HDMI (dGPU-routed on this chassis) and verify with `drm_info`/`nvidia-smi` before recording any M1 result. [ADR 0003](adr/0003-test-targets.md) |
| Base/akmods tag drift (`43` vs `main-43`) | Builds clean, boots black | `bump-base.sh` hard-fails on a mismatched pair; base bumps go to the VM target before bare metal |
| Regenerating the initramfs drops the `ostree` dracut module | **Hit on the first boot attempt.** Dracut emergency mode; lint and image build both pass | `--add ostree` plus a build-time `lsinitrd` assertion in the Containerfile. General lesson: a green build says nothing about a bootable image — boot the VM target after any initramfs change |
| GPT image written to larger media | **The real cause of the bare-metal boot failures (2026-08-03), after two wrong convictions** (missing initramfs drivers; the stick's UAS implementation — both disproved by test). Image-sized GPT on a bigger stick = backup header mid-disk + undersized protective MBR: firmware and Windows tolerate it, **GRUB and the Linux kernel reject the whole partition table**, and Windows' auto-"repair" then corrupts the main table CRC. QEMU can never reproduce it: virtual disks are exactly image-sized | `scripts/flash-usb.sh`: write from WSL over usbipd, `sgdisk -e`, then verify partitions/UUIDs/boot-binary checksum before any reboot. Never flash with Rufus alone. Diagnostic signature: `blkid` sees `PTTYPE=gpt` but `lsblk` shows zero partitions |
| First boot after an upgrade wedges in early userspace | **Seen once during M0.** Hung just after `modprobe@loop.service`, with no "A start job is running" line — so not a unit timeout. A hard power-cycle booted the same deployment cleanly with SELinux still Enforcing | Unexplained and unreproduced; recorded rather than diagnosed. If it recurs, capture it properly — the working theory that it was SELinux labelling from the non-SELinux CI runner was **disproved**, since the CI image boots Enforcing without `enforcing=0`. Matters far more on bare metal, where a wedged boot has no `vmconnect` to inspect it |
| Plymouth→compositor handoff flashes text/black | Fails the silent-boot gate | Known-fiddly; budgeted in M2; camera test is the arbiter, not eyeballs |
| Godot Wayland quirks under gamescope/cage (focus, scaling, gamepad) | Shell unusable in session though fine on desktop | Test the Godot export inside the real session in M1 week 1, before building UI on top. **Narrowed by M3:** the export keeps Godot's default x11 driver and relies on its documented two-way fallback, so it runs on XWayland under plan A and native Wayland under plan B with no per-compositor code. Gamepad input bypasses the compositor entirely, so a controller failure is never evidence about D4 ([ADR 0006](adr/0006-shell-skeleton.md)) |
| ublue base image churn breaks a build | Deploy loop breaks randomly | Pin by digest; bump deliberately, never track `latest` |
| Boot >15 s on the actual hardware | Fails exit criterion 1 | `systemd-analyze blame` early (M2), not at the end; NVMe target box if possible |
| 326 MB initramfs (measured) eats the boot budget | Seconds of decompression before anything draws | `--no-hostonly` is correct for a portable image, but M2 should measure the cost and consider trimming dracut modules. Do not switch to hostonly — it would bake the build machine's hardware into the image |
| Secure Boot silently blocks NVIDIA modules | Black screen, confusing | D7: disabled for Phase 0, documented |

## Open questions

Resolved 2026-08-02:

1. ~~GPU generation of the target box~~ → **RTX 3060 Laptop (Ampere)**, above the `nvidia-open` Turing floor. Baseline is Turing+, not a specific card, so no purchase is needed and none should be made before M1 produces a compositor decision. [ADR 0002](adr/0002-nvidia-baseline-and-base-image.md)
2. ~~Build host~~ → **Fedora VM on the Predator.** Split into three roles, because a VM cannot answer M1's question. [ADR 0003](adr/0003-test-targets.md)

3. ~~GHCR account/repo name~~ → **`ghcr.io/marwansummakieh/marwanos`**. Lowercase namespace; the GitHub account itself is `MarwanSummakieh`.

All three are answered. The only thing still gating the first push is a
`write:packages` token, which is yours to create — see [dev-setup.md](dev-setup.md).

## Phase 1 hooks

- The session script's supervision loop is where `marwand` gets added as a second supervised process
- The shell's placeholder "launch a scene" seam becomes `Launch` over JSON-RPC
- The dev override path (D5) carries the whole project — it's how shell and daemon iterate forever after
