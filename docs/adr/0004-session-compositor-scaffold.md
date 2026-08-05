# ADR 0004 — Session bring-up scaffold, and how the plan A/B decision gets made

**Status:** Proposed
**Date:** 2026-08-03
**Relates to:** D3, D4, D5, D6 in [phase-0-plan.md](../phase-0-plan.md); the "Note
for M1" in [ADR 0002](0002-nvidia-baseline-and-base-image.md); the bare-metal
role in [ADR 0003](0003-test-targets.md)

## Context

M1 asks one question — can gamescope take DRM master on the NVIDIA driver — and
that question cannot be answered anywhere except on the Predator with the TV
plugged in. Everything around the question can be built beforehand, and this ADR
records what was built, so the three days budgeted for the spike are spent
measuring rather than typing.

Nothing here decides D4. The status stays **Proposed** until the spike has run on
hardware, at which point this document is either accepted with plan A named, or
superseded by one that names plan B.

## What was scaffolded

| File | What it does |
|------|--------------|
| `os/Containerfile` | Installs `greetd`, `gamescope`, `cage`, `vulkan-tools`; wires the units and the user after `COPY files/ /` |
| `os/files/etc/greetd/config.toml` | Autologin `player` on tty1 into the session script (D3) |
| `os/files/usr/lib/marwanos/session/marwanos-session` | The session: plan A, fallback to plan B, D5's dev override, M3's supervision loop |
| `os/files/usr/lib/sysusers.d/50-marwanos.conf` | Declares `player`: uid 1000, no password, `nologin`, `video`/`render`/`input` |
| `os/files/usr/lib/systemd/system-preset/50-marwanos.preset` | `enable greetd.service`, `disable getty@tty1.service` |
| `os/files/usr/lib/tmpfiles.d/50-marwanos.conf` | `/var/marwanos`, `/var/marwanos/dev-shell`, `/var/home/player` on every boot |

All four packages are in Fedora 43 proper — `greetd` 0.10.3, `gamescope` 3.16.15,
`cage` 0.2.0, `vulkan-tools` 1.4.321.0 — checked against
`packages.fedoraproject.org` before any of them was named in a `dnf` line. **No
COPR is involved and none should be added without an ADR.** Bazzite's
`gamescope-session` is a COPR package upstream; this image does not use it, and
deliberately does not depend on the COPR that builds it.

## Findings that change the shape of the spike

These came out of reading upstream and the packaging, and each one is a day the
spike does not have to spend.

**1. `bazzite-org/gamescope-session` no longer exists.** Both the plan (M1) and
ADR 0002 instruct the reader to study that repository first. The `bazzite-org`
GitHub organisation is still there, describes itself as "Organization holding
bazzite-specific packages", and has **zero public repositories**. The session
bazzite forks is `ChimeraOS/gamescope-session`, which is live and was the source
mined for this scaffold. The instruction in the plan and ADR 0002 should be
re-pointed.

**2. The image may have no NVIDIA userspace driver, which would fail M1 for a
reason unrelated to M1.** The Containerfile installs `ublue-os-nvidia*.rpm` and
`kmod-nvidia*.rpm` from the akmods sidecar. Universal Blue's own installer
(`build_files/nvidia/nvidia-install.sh` in `ublue-os/akmods`) additionally
installs everything in `/rpms/nvidia/` from that same sidecar — `nvidia-driver`,
`nvidia-driver-libs`, `nvidia-driver-cuda-libs`, `libnvidia-*` — plus
`egl-wayland` and `libva-nvidia-driver`. Those packages are what provide the
Vulkan ICD, the GLX/EGL vendor libraries, and `nvidia-smi`.

M0 verified `nvidia.ko` and friends inside the initramfs, which is a kernel-side
check and cannot see this. A kernel module with no userspace driver produces
exactly the symptom the spike is looking for — a compositor that will not start
on the NVIDIA card — with a completely different cause. **This is step 0 of the
checklist below, and it is deliberately not fixed in the Containerfile**: adding
the NVIDIA userspace stack is a change to M0's driver decision and belongs in a
review, not in an M1 scaffold. There is a comment saying so at the relevant line.

**3. greetd's `default_session` is a D6 hole in the shipped default.** greetd
requires a `default_session`, and falls back to it the instant the initial
session exits. The rpm ships `agreety --cmd /bin/sh` there — a text login prompt
on tty1, appearing only after a failure, which is the one moment nobody is
watching. Our config points `default_session` back at the session script.
Sessions started that way are logind class `greeter` rather than `user`, which
matters because M1's acceptance criterion reads `loginctl`.

**4. Enabling greetd does not start greetd.** Its entire `[Install]` section is
`Alias=display-manager.service`. That is only reached because systemd's
`graphical.target` carries `Wants=display-manager.service`; an image that stops
at `multi-user.target` would enable greetd successfully and boot to nothing. The
Containerfile creates `multi-user.target.wants/greetd.service` directly. It could
not be shipped as a tracked symlink — see finding 6.

**5. A preset file cannot mask a unit.** `systemd.preset(5)` understands `enable`
and `disable` and nothing else, and `disable` does not remove the
`getty.target.wants/getty@tty1.service` symlink systemd itself ships. D6 says no
getty on tty1 ever, so the Containerfile runs `systemctl mask` on both
`getty@tty1.service` and `autovt@tty1.service` — separately, because
`autovt@.service` is its own alias of `getty@.service` and is what logind starts
on VT activation, so masking one does not mask the other. greetd's
`Conflicts=getty@tty1.service` is a race resolved at runtime; a mask is the unit
not existing.

**6. This repo cannot carry executable bits or symlinks.** `core.filemode` and
`core.symlinks` are both `false`, and every blob in the index is mode `100644` —
`scripts/*.sh` included. A session script checked out on Windows arrives
non-executable, and greetd's `exec` of it fails with EACCES on tty1, where
nothing can report it. The Containerfile `chmod`s it after `COPY`. This is the
same family of problem `.gitattributes` exists to solve for line endings, and it
should be assumed for every future artefact under `os/files/`.

**7. `nologin` is safe for the session user.** greetd never consults the passwd
shell: it execs `/bin/sh -c "exec <command>"` itself and only exports the shell
as `$SHELL`. So `player` can have `/usr/sbin/nologin` and a locked password,
which closes `su`, `ssh` and every other login path into the account at no cost
to the session. `initial_session` is unauthenticated by design, so the lock does
not block autologin.

**8. The session user has to be declared, not `useradd`ed.** `bootc container
lint` carries a `sysusers` check that warns on any `/etc/passwd` or `/etc/group`
entry with no corresponding `/usr/lib/sysusers.d` declaration, and M0's build
currently records zero warnings. The reasoning behind the lint is the real point:
`/etc` is three-way merged on upgrade, so a user written straight into
`/etc/passwd` by a later image can fail to appear on a machine whose `/etc` has
already diverged — on an appliance with no console, an account that quietly does
not exist is a machine that quietly does not boot to anything. `player` is
therefore declared in `sysusers.d` and the Containerfile runs `systemd-sysusers`
against that one file at build time, so the account is in the image *and*
re-asserted on every upgrade.

**9. cage cannot be told which output or which GPU to use.** cage 0.2.0's entire
CLI is `-d -h -m extend|last -s -v`. There is no equivalent of gamescope's
`--prefer-output` or `--prefer-vk-device`. On a hybrid laptop driving a TV that
is a real difference between the plans, not a detail, and it belongs in the
decision. (`-s` is cage's "allow VT switching" and is deliberately never passed.)

**10. The wlroots-on-NVIDIA workarounds are probably obsolete.** Universal Blue
deleted its `WLR_NO_HARDWARE_CURSORS=1` / `WLR_RENDERER=vulkan` environment file
in December 2025, in the same release that added driver 590 support. The session
script therefore does not set them. They remain the first thing to try if cage
misbehaves during the spike — first thing to try, not first thing to ship.

## The spike, as commands to run on the target

Bare metal only (ADR 0003). The TV must be on HDMI, and the internal panel must
not be what any result is measured against.

### Step 0 — prove the driver stack before judging the compositor

Finding 2 is the reason this is step 0. If any of it comes back empty, stop:
the spike has not started yet.

```sh
cat /proc/cmdline                                  # the four kargs M0 verified
cat /sys/module/nvidia_drm/parameters/modeset      # must be Y
lsmod | grep -E '^nvidia'
ls -l /usr/share/vulkan/icd.d/                     # an nvidia_icd*.json must be here
rpm -qa | grep -E 'nvidia|vulkan' | sort
vulkaninfo --summary                               # must list the NVIDIA device
nvidia-smi                                         # absent => userspace driver missing
```

### Step 1 — establish which card owns the HDMI output

The plan requires this before any result is trusted, and it needs no extra
packages:

```sh
for c in /sys/class/drm/card*-HDMI-A-*; do
    printf '%s %s\n' "$c" "$(cat "$c/status")"
done
for c in /sys/class/drm/card[0-9]; do
    printf '%s -> %s\n' "$c" "$(basename "$(readlink -f "$c/device/driver")")"
done
cat /sys/class/drm/card*-HDMI-A-1/modes | head -5   # the TV's native mode first
```

`drm_info` gives a richer picture and is what the plan names, but it is not in
the image. Either install it on the target for the spike or accept the sysfs view
above — see open questions.

### Step 2 — the session starts at all

```sh
systemctl status greetd.service
systemctl is-system-running                        # expect: running
loginctl list-sessions
loginctl show-session "$(loginctl list-sessions --no-legend | awk 'NR==1{print $1}')" \
    -p Name -p Class -p Type -p Active -p Seat -p VTNr
journalctl -b -u greetd -o cat | grep -F 'marwanos-session:'
journalctl -b -p err -u greetd
```

Expect one session, `Name=player`, `Class=user`, `Seat=seat0`, `VTNr=1`,
`Active=yes`. `Class=greeter` means the session already restarted at least once,
which is itself a finding.

### Step 3 — the acceptance gate

Power on cold. A fullscreen spinning cube on the TV, at the TV's native mode, no
cursor, no text at any point. Then:

```sh
cat /var/home/player/.config/gamescope/modes.cfg    # what mode was negotiated
```

### Step 4 — the parts a first boot does not test

These are the ones that decide D4, because starting once is the easy half.

```sh
# mode switches: do them physically, then re-read the journal each time
#   - TV off and on at the remote
#   - TV input switched away and back
#   - HDMI unplugged and replugged
journalctl -b -u greetd -o cat | tail -50

# the supervision loop (M3's exit criterion 3)
#
# The process name is the client file's basename. From M3 that is
# marwanos-shell; on an image built before M3 it is vkcube (updated 2026-08-05
# with the baked client -- see ADR 0006). Match whichever the image has: a pkill
# that hits nothing exits nonzero and looks exactly like a pass.
pkill -9 -u player marwanos-shell  # expect: the client back in under 3 s, no text
for i in 1 2 3 4 5 6; do pkill -9 -u player marwanos-shell; sleep 1; done
journalctl -b -u greetd -o cat | grep -F 'not respawning'   # guard must trip

# D5's override path. The override keeps the same basename, so whatever is
# copied in still runs as marwanos-shell and the restart command is unchanged.
mkdir -p /var/marwanos/dev-shell
cp /usr/bin/vkcubepp /var/marwanos/dev-shell/marwanos-shell
touch /var/marwanos/devmode
pkill -9 -u player marwanos-shell  # expect: vkcubepp comes back instead
```

### Step 5 — plan B, measured the same way

```sh
echo cage > /var/marwanos/compositor
systemctl restart greetd
# repeat steps 3 and 4, then:
rm /var/marwanos/compositor
systemctl restart greetd
```

### Step 6 — the Godot check the risk table asks for in week 1

Export the M3 skeleton headlessly, drop it at
`/var/marwanos/dev-shell/marwanos-shell`, and run it under whichever plan is
winning. Focus, scaling and gamepad input under the real session are what the
risk table calls out, and finding them broken in M3 is far more expensive than
finding them broken now.

The skeleton exists as of 2026-08-05 and the image bakes it — see
[ADR 0006](0006-shell-skeleton.md), which also names what to watch for: a
`wl_registry` protocol error in the journal is a known Godot-on-minimal-Wayland
crash family rather than a shell bug, and gamepad input bypasses the compositor
entirely, so a controller failure here is not evidence about D4.

## What the first hardware run found (2026-08-03)

Steps 0–3 only; step 4 has not been run, so **D4 is not decided yet**.

**Plan A started and rendered.** gamescope ran as `player` for ~75 s and put the
`vkcube` placeholder on the TV. The evidence is indirect but consistent: an
`ANOM_ABEND` record naming `exe="/usr/bin/gamescope"`, the cube on the external
display in video, and the cursor appearing on movement and vanishing — which is
`--hide-cursor-delay 1`, a flag plan B has no equivalent of. There is no
"chose connector X, vk device Y" line to cite, for the reason below.

**Connecting the TV is a precondition, not a detail.** On a panel-only boot the
dGPU logged `[drm] Cannot find any crtc or sizes` and got no framebuffer; with
HDMI connected it came up as `fb1: nvidia-drmdrmfb`. Plan A pins gamescope to the
NVIDIA device, so on the internal panel alone it has no display to drive and
falls back to cage. This is the trap the last bullet of "what would not flip it"
already names, and it cost a boot to walk into anyway.

**The session's log output never reached the journal.** The header of
`marwanos-session` asserted that greetd's inherited descriptors made the journal
the only debugging surface. False: `config.toml` sets `vt = 1`, and greetd opens
that VT and hands it to the session as fds 0, 1 and 2. Every line the script and
gamescope wrote went to the laptop's internal panel — a wall of scrolling text on
a machine whose acceptance gate is "no text at any point" — while `journalctl -u
greetd` held none of it. Both halves are one bug, and it is why the paragraph
above has to argue from a phone video. Fixed by re-exec'ing through `systemd-cat`
in the session script; a greetd drop-in cannot fix it, because greetd reopens the
tty for the child itself.

**`serial-getty@ttyS0` respawned every ~10 s.** `console=ttyS0` is on the kernel
command line for QEMU's benefit, systemd-getty-generator instantiates a serial
getty for it, and this chassis has no serial port — `restart counter is at 7`
inside a 75-second session, each failure logged at err priority into the one
command the appliance offers for triage. Masked alongside the tty1 gettys.

Still open, neither of them blocking D4:

- gamescope segfaults during teardown (SIGSEGV at 95.08 s, *after* the power key
  at 94.16 s and after greetd stopped). It does not affect a running session. A
  coredump was captured on the target.
- `iwlwifi ... probe with driver iwlwifi failed with error -110` — no wifi, which
  matters because devmode ssh over the network is the escape hatch D6 allows and
  this chassis cannot currently reach it without ethernet.

## What would flip plan A to plan B

Any one of these, reproduced across three cold boots on the Predator with the TV
on HDMI:

- gamescope never reports ready on `--backend drm` — the handshake in the session
  script times out — after step 0 has passed and the arguments have been run by
  hand to rule out an unrecognised flag.
- gamescope takes DRM master and the TV stays black, and no combination of
  `--prefer-output`, `--generate-drm-mode` and `-W/-H` produces a picture.
- The session survives a first boot but not a mode switch: TV off/on, input
  change or HDMI replug leaves a dead session or a black screen that does not
  recover on its own.
- gamescope composites on the Intel iGPU despite `--prefer-vk-device` naming the
  NVIDIA device, i.e. the compositor cannot be pinned to the card the project is
  about.
- The Godot export is unusable under gamescope and fine under cage.

And what would **not** flip it, because it is not evidence about gamescope:

- A missing NVIDIA userspace driver (finding 2). Fix that and re-run.
- gamescope exiting during argument parsing on an unknown flag.
- Anything measured in the Hyper-V VM — there is no NVIDIA DRM device there
  (ADR 0003).
- Anything measured on the laptop's internal panel rather than the TV.

Plan B winning is not a failure. The shell is identical either way (D4), and the
session script already runs both, so the decision costs an edit and a rebuild,
not a rewrite.

## Consequences

- The session falls back to cage automatically when gamescope does not report
  ready. That is right for a spike and wrong for a product: an appliance that
  silently changes compositor is an appliance whose behaviour cannot be reasoned
  about from the image. When M1 decides, the fallback and
  `/var/marwanos/compositor` both go away.
- `getty@tty1`, `autovt@tty1` and `serial-getty@ttyS0` are masked from this image
  onward, which pulls one item out of M2 and makes D6 true from the first session
  rather than the third milestone. tty2 is untouched, so devmode's getty remains
  possible — though note that nothing can currently log in on it: `root` is
  passwordless (`*`) and `player` is `!*` with `/usr/sbin/nologin`. Both recovery
  paths the session script's comments name, tty2 and devmode ssh, are aspirational
  as of M1. Giving the appliance a way back in is real work, not a flag.
- `player` is uid 1000, pinned, and declared in `sysusers.d` rather than created
  with `useradd`. `/var` is machine-local and outlives image upgrades, so a uid
  that drifted between builds would orphan everything the session had written to
  `/var/home/player`.
- `/etc/greetd/config.toml` is a file in `/etc`, which bootc three-way merges.
  A copy edited on a target will not be replaced by `bootc upgrade`. Check the
  target rather than assuming an upgrade delivered a change to it.

## Open questions

1. **Does this image have an NVIDIA userspace driver?** Finding 2. This is the
   only one that blocks the spike, and it is answerable in one command on the
   existing target — no rebuild needed.
2. **Install `drm_info` for the spike?** The plan names it. It is a debugging
   tool that would otherwise live in the appliance forever. The sysfs commands in
   step 1 cover most of what it is wanted for.
3. **Which boot target?** greetd is wired into `multi-user.target` as well as
   reachable through `graphical.target`'s `display-manager` alias, so it starts
   either way and the default target was left alone. Whether an appliance should
   boot to `graphical.target` at all is an M4 audit question (D6, escape hatches),
   not an M1 one.
4. **The plymouth handoff.** greetd's unit ships `After=plymouth-quit-wait.service`,
   which tears the splash down *before* the session starts — the opposite of M2's
   requirement that plymouth holds until the compositor's first frame. It is left
   alone here because changing it without a camera test is guessing, but M2 should
   expect to override it rather than discover it.
5. **ADR numbering.** M1's checklist says the compositor decision is recorded in
   `docs/adr/0001-session-compositor.md`. There is no ADR 0001 in this repo — the
   series starts at 0002 — and 0003 is already taken. This file is 0004. The plan
   should be corrected to point at whichever number the accepted decision lands on.
