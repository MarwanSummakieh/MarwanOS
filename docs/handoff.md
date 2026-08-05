# Handoff — where MarwanOS is right now

**Written 2026-08-05.** This file is *current state*, not a record. It is meant to be
rewritten or deleted, unlike [phase-0-plan.md](phase-0-plan.md) and the ADRs, which
are the durable documents. If it disagrees with them, they win — and this file is
what is stale.

---

## The one thing that is waiting

**A USB stick is flashed and verified, sitting unplugged, waiting for one boot on the
Predator.** That boot is the bottleneck for everything below it, and it has been
deliberately loaded up so it answers four open questions at once rather than one per
trip. There is only one machine — the Predator is the build host, the test target and
the user's only computer — so a reboot costs them their working environment, and a
hardware boot has to be planned to collect every outstanding answer at once.

Image on the stick: `MarwanOS (Phase 0, 0.0.202608051352)`, built from `21151fc`.

```
GPT        : main + backup tables both intact
partitions : 4/4 visible to the Linux kernel
boot UUID  : 6487cf7d-409b-4d85-bcfe-581fac9f98ab
root UUID  : 010befbf-c39a-4792-8600-9fcd8b22929f
BOOTX64.EFI: checksum-identical to the image
```

### After the boot, read the journal off the stick

Plug the stick into the Windows side, then:

```powershell
& "C:\Program Files\usbipd-win\usbipd.exe" attach --wsl --hardware-id 346d:5678
```

It comes up as `/dev/sde` in WSL. Mount partition 4 read-only and read the persistent
journal out of the ostree deployment's `/var`:

```sh
journalctl -D <root>/ostree/deploy/*/var/log/journal -b -1 -t marwanos-session -o cat
journalctl -D <root>/ostree/deploy/*/var/log/journal -b -1 -u marwanos-panel.service -o cat
```

Four answers come out of those two commands:

| Question | The line to look for | What it unblocks |
|---|---|---|
| The internal panel's connector name | `marwanos-panel: connector card0-eDP-1 -> karg name 'eDP-1' …` | The `video=` karg — [ADR 0007](adr/0007-single-display-appliance.md) §7.4 |
| Which compositor won | `gamescope ready on DISPLAY=…` vs `starting cage …` | **M1's decision, and ADR 0005** |
| Whether the spanning defect is fixed | `marwanos-shell: screens: N` and `screen 0: size … pos …` | M3's "fullscreen at native mode" |
| What ate the 31-second black gap | timestamps across the session's own lines | M2, and exit criterion 1 |

`-t marwanos-session`, never `-u greetd`: greetd creates a logind session, so the
session's processes live in `session-cN.scope` and `-u greetd` matches none of them.
Everything the session, the compositor and the shell print carries that one tag,
because the session re-execs itself through `systemd-cat`.

---

## Milestone state

| | State |
|---|---|
| **M0** — build/deploy loop | **Complete** (2026-08-02), verified end to end including `bootc rollback` |
| **M1** — session + the plan A/B decision | Scaffolded and running on hardware. **Blocked only on reading the journal** to name the compositor, then ADR 0005 gets written |
| **M2** — silent boot | Partial. Zero text frames on the 2026-08-05 film, but not banked as 1 of 3: it booted from USB and `console=ttyS0` is still in the image. Two new items landed (panel policy, lid drop-in); the 31-second gap is the open one |
| **M3** — shell skeleton | Exit criterion 2 **passed on hardware**: grid, focus, A into the placeholder, B back. Fullscreen-at-native-mode failed and is what this build fixes. `kill -9` gate and the loop guard's error screen still outstanding |
| **M4** — guardrails + exit run | **Untouched.** `devmode` gating, escape-hatch audit, boot budget, filmed exit run, and the decision to mask `bootc-fetch-apply-updates.timer` |

## Deliberately not done, with the reason

- **The `video=<connector>:d` karg.** It is what makes the lid panel dark *during
  plymouth*; no compositor-level fix reaches before the compositor exists. Held back
  because `video=` is a plain name match with no error path — a wrong name is a silent
  no-op — and the command line lives inside a UKI that cannot be edited at boot. Ship
  it onto a **second** stick with the current one left untouched. Whole design in
  [ADR 0007](adr/0007-single-display-appliance.md).
- **ADR 0005, the compositor decision.** The geometry of the 2026-08-05 defect is a
  cage signature and the staggered blackout supports it, but ADR 0004 records plan A
  running two days earlier. Do not write the ADR from pixel measurements.
- **A PR for `m3-shell-skeleton`.** Branch is 2 commits ahead of origin and unpushed.
  The user's call.

---

## Environment cheat sheet

Everything Linux-side happens in the WSL distro **`FedoraLinux-43`**, which is not the
default — a bare `wsl -e bash` fails outright.

```
wsl -d FedoraLinux-43 -u root -e bash /path/to/script.sh
```

Put anything non-trivial in a script file first. PowerShell expands `$(...)`, `$VAR`
and `$?` before the string reaches WSL, and that has produced wrong diagnoses on this
project more than once.

Build artifacts go under `/var/tmp/`, never `/mnt/c` — 17 GB through the drvfs bridge
is glacial.

### The flash pipeline, in order

```sh
scripts/build-push.sh --no-push                       # Containerfile assertions are the first gate
OUT_DIR=/var/tmp/out SSH_KEY_FILE=/mnt/c/Users/brain/.ssh/id_marwanos.pub \
    scripts/make-installer.sh raw
EXTRA_KARGS="usb-storage.quirks=346d:5678:u console=tty0" OUT_DIR=/var/tmp/out \
    scripts/make-usb.sh                               # NOT optional -- see below
FLASH_CONFIRM=yes scripts/flash-usb.sh /var/tmp/out/image/disk.raw /dev/sde
```

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
| Piping `lsinitrd` into `grep -q` under `pipefail` exits 141 — grep leaves early, `lsinitrd` takes SIGPIPE. The assertions read from files instead | `os/Containerfile`, the initramfs assertions |
| `MARWANOS_*` ARGs must stay at the bottom, or a timestamped version invalidates dnf and dracut every build (515s vs 70s) | `os/Containerfile` |
| The Predator's wifi does not associate under MarwanOS, so root SSH recovery needs ethernet | [ADR 0004](adr/0004-session-compositor-scaffold.md) |

### VM harness

QEMU + OVMF inside WSL, booting the real raw image with a diagnostic unit injected
into the ostree deployment before boot. It proves everything except the two things a
VM structurally cannot: there is no NVIDIA DRM device and no eDP panel. The pattern —
loop-mount partition 4, write `/etc/marwanos/diag.sh` plus a `multi-user.target`
oneshot into the deployment, boot with `-serial file:` — is worth reusing verbatim.

---

## Two corrections a fresh session should not re-derive

- **The shell does not run native Wayland under cage.** cage ships Xwayland, Godot's
  linuxbsd driver order puts x11 first, and a VM run with cage demonstrably the
  compositor reported `X11`. The shell is on XWayland under both plans.
- **Therefore `DisplayServer.get_name()` does not name the compositor.** It says `X11`
  either way. The session script's own log line is the only oracle.

Both were stated confidently by research agents before anyone measured them. That is
the argument for keeping an adversarial verify stage on any fan-out, and for treating
a VM run as the arbiter over a well-sourced claim.
