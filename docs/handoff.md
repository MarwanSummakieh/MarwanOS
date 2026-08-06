# Handoff — where MarwanOS is right now

**Written 2026-08-06.** This file is *current state*, not a record. It is meant to be
rewritten or deleted, unlike [phase-0-plan.md](phase-0-plan.md) and the ADRs, which
are the durable documents. If it disagrees with them, they win — and this file is
what is stale.

---

## The one thing that is waiting

**A rebuild, and a boot of it.** The 2026-08-05 stick answered its four questions
(see "what the boots settled" below) and since then rebuild-only changes have
stacked up in the image, none of which can be checked without burning a new stick:

| Change | What the boot should show |
|---|---|
| `setcap cap_sys_nice+ep` on gamescope | The `No CAP_SYS_NICE` line gone from the journal, and the perceptible lag with it |
| `video=eDP-1:d` karg ([ADR 0007](adr/0007-single-display-appliance.md)) | Lid panel dark from the first modeset — plymouth included, which no service could reach |
| `console=ttyS0` dropped (`--no-default-kernel-args`) | No `serial-getty` respawn noise; M2's three-boot count may start |
| Portal mask | The eleven `xdg-desktop-portal-gtk` failures gone from `journalctl -p err` |
| Session script: no cage fallback, no compositor lever (ADR 0005 consequences) | `cage` appears nowhere; a gamescope failure holds rather than silently switching |
| The error screen | `pkill -9` the shell five times inside a minute → a designed frame, not a black TV |
| The home rail (replaced the grid) | The couch test M3 still owes |

The build is the standard pipeline below. Per ADR 0007, the `video=` karg goes onto
a **second** stick with the current known-good one left untouched — the cmdline
lives inside a UKI and cannot be edited at boot, and `video=` fails silently if the
token is wrong.

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

## Milestone state

| | State |
|---|---|
| **M0** — build/deploy loop | **Complete** (2026-08-02) |
| **M1** — session + the A/B decision | **Complete** (2026-08-05). gamescope, [ADR 0005](adr/0005-compositor-decision.md) |
| **M2** — silent boot | Partial. Both pending kargs are now in the repo (`console=ttyS0` dropped, `video=eDP-1:d` added), neither booted. The three-boot camera count starts on the next stick. The 31-second black gap is diagnosed-adjacent (compositor handover) but not formally closed |
| **M3** — shell skeleton | Exit criteria 2 and 3 **passed on hardware** (as the grid). The home rail and the error screen are built and desk-verified only. Outstanding: couch test, controller hotplug, a real guard-trip of the error screen |
| **M4** — guardrails + exit run | **Untouched** |

## The current stick

Flashed and verified with the pre-rail image `MarwanOS (Phase 0, 0.0.202608051352)`
(built from `21151fc`), image file at `/var/tmp/panel-out/image/disk.raw`. It is the
known-good fallback — leave it as it is and burn the next build onto a different
stick. Identify any stick by UUIDs, not by memory:

```
boot UUID  : 6487cf7d-409b-4d85-bcfe-581fac9f98ab
root UUID  : 010befbf-c39a-4792-8600-9fcd8b22929f
```

```sh
VERIFY_ONLY=yes scripts/flash-usb.sh /var/tmp/panel-out/image/disk.raw /dev/sde
```

**Pull sticks physically while still attached to WSL.** Windows rewrites the GPT of
any removable disk it enumerates; it has corrupted this stick once already
(recovered with `sgdisk -e`, no reflash needed — both GPT entry-array copies
survive that failure).

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
| The Predator's wifi does not associate under MarwanOS, so root SSH recovery needs ethernet | [ADR 0004](adr/0004-session-compositor-scaffold.md) |

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
