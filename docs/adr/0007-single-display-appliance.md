# ADR 0007 — One screen, and the lid panel genuinely off

**Status:** Proposed
**Date:** 2026-08-05
**Relates to:** M2 and M3 in [phase-0-plan.md](../phase-0-plan.md); D4, D6 and D7;
the scaffold and findings in [ADR 0004](0004-session-compositor-scaffold.md); the
shell in [ADR 0006](0006-shell-skeleton.md); the compositor decision that
[0005](../phase-0-plan.md) still reserves a number for

## Context

The first hardware run of the shell, on 2026-08-05, was filmed for 100 seconds and
read frame by frame. It proved exit criterion 2 — the grid draws, focus moves, **A**
opens the placeholder, **B** returns — and in the same hundred seconds it disproved
"fullscreen at the TV's native mode".

The shell was handed one surface covering **both** connected displays. The header
is a single `HBoxContainer`: the `MarwanOS` wordmark at one end, the controller
status at the other. The wordmark and the grid's first tile column rendered on the
laptop's internal panel; the status label and the remaining three columns rendered
on the external display, clipped at its left edge, with the external's right band
black. One row of one container, split across two panels.

That is not a Godot scaling failure. The scene is intact and `stretch/aspect="keep"`
did exactly what it promises. It is the compositor laying a canvas across an output
layout that spans every connected display.

The owner's requirement, stated after seeing the film, is sharper than "pin the
window to a screen":

> the target is one monitor console not a PC but having it close one of the
> monitors completely the lid one

So the lid panel is not a second screen to lay out around. It is a screen that must
not exist: dark from as early in boot as anything can reach, not mirroring, not
showing plymouth, not showing a lit black framebuffer. Fixing the *layout* while
leaving the panel enumerated would trade a visible failure for a silent one.

Two things are deliberately **not** settled here. Which compositor won on 2026-08-05
is still unread — the journal is on the stick and nobody has looked. And the
internal connector's real name is unknown, which is why the one change that depends
on it is held back (see decision 1 and the open questions).

## Decisions

### 1. The single screen is delivered in the kernel, not in the compositor

`video=<internal-connector>:d` in `os/files/usr/lib/bootc/kargs.d/00-marwanos.toml`.

The trailing lowercase `d` sets `connector->force = DRM_FORCE_OFF` at connector-init
time inside i915's probe. `drm_helper_probe_single_connector_modes()` then
short-circuits: the connector reports `disconnected`, its EDID property is cleared
and its mode list pruned, without detection ever running. From that instant the
panel is invisible to *everything downstream* — fbcon, plymouth's DRM renderer,
gamescope's connector selection, and wlroots' connector scan. The panel power
sequence never runs, so the backlight never comes up; this is stronger than
disabling a CRTC, because the pipe is never enabled in the first place.

It is in the kernel because that is the only layer that reaches the whole boot.
Every compositor-side fix leaves the panel showing plymouth for the entire boot —
on this machine, from t=0 to roughly t=74 s. gamescope additionally *cannot* turn
off the panel even in principle: it derives its DRM node from the chosen Vulkan
device, so with `--prefer-vk-device` pinned to NVIDIA it never opens the Intel node
the panel hangs off. cage has no output selector at all.

Syntax, because getting it wrong costs a rebuild and a reflash to discover:
lowercase `d` (uppercase `D` is force-enable-digital, the opposite); freestanding,
with no mode string required; one `video=` token per connector; two force flags in
one token is a parse failure that discards the whole option.

**Held back until the name is read off the target.** `video=` is a plain string
match against `connector->name` with no error path — a token naming a connector
that does not exist is a silent no-op, indistinguishable from never having shipped
the change. The name carries no card prefix (`connector->name` is `eDP-1` while
sysfs is `/sys/class/drm/cardN-eDP-1`) and it is matched across every DRM device in
the machine. **This technique must never be aimed at `HDMI-A-1` or `DP-1`:**
nvidia-drm honours `connector->force` too and uses the same standard names, so a
token meant for one card would take the appliance's only screen with it.

### 2. `marwanos-panel.service` is a re-enable policy, not a disable policy

The karg is unconditional, and unconditional on a laptop that is also the
development machine is the brick risk. `marwanos-panel.service` runs one-shot,
`Before=greetd.service`, and asserts the intended state from what the hardware
actually reports:

- **external display present** → write `off` to every internal connector
  (`eDP-*`, `LVDS-*`, `DSI-*`)
- **no external display** → write `detect`, clearing `connector->force` and bringing
  the panel back a few seconds into boot

The direction of the failure mode is the entire point. If the unit does not run, the
*appliance* is still correct — panel off — and only the *development* case degrades
to no picture, which is recoverable by pulling the stick. A unit that disabled the
panel instead would fail the other way round, and the other way round cannot be
undone from a machine with no console.

The `off` branch is not dead weight beside the karg. It globs by connector class
rather than trusting one name, which makes a karg that silently matched nothing
partially self-healing once the real root is mounted. It is also what makes this
unit useful *before* the karg ships at all: on its own it removes the lid panel
from the compositor's output layout, which is the filmed defect.

No `ConditionPathExists*` of any kind. A condition failure is logged at debug and
the unit is silently skipped, which on this appliance is indistinguishable from
success — and in the re-enable direction a skipped unit means a dark development
machine. The script reports what it found instead, and exits 0 unconditionally so a
failure here can never block greetd.

### 3. The lid never suspends, and all three logind keys say so

`os/files/usr/lib/systemd/logind.conf.d/50-marwanos-lid.conf`, setting
`HandleLidSwitch`, `HandleLidSwitchExternalPower` and `HandleLidSwitchDocked` all to
`ignore`.

logind picks exactly one of those three per lid event, so leaving any of them at its
default leaves one reachable path able to suspend the machine.

The tempting shortcut — "a TV is attached, so logind treats us as docked and does
nothing" — is the trap this file exists for. logind's external-display count
requires the HDMI connector's sysfs `enabled` attribute to read `enabled`, and that
is true only while some client holds an active modeset. Three windows where it is
false: before the compositor's first modeset (logind's holdoff expires 30 s into
boot; this machine's first frame lands at 74 s), during every greetd restart
including every cycle of the crash guard, and whenever the TV is powered off and
drops HPD. And logind acts on an already-closed lid rather than only on the closing
edge, because it reads the switch state when the input device is opened — so booting
with the lid shut, which is this appliance's normal case, is a live suspend path
today.

The drop-in goes in `/usr/lib`, not `/etc`. bootc three-way merges `/etc` on
upgrade, so a drop-in written there would be machine-local state that a later image
could not correct — the same trap `/etc/greetd/config.toml` already carries and
warns about in its own header.

This is independent of decision 1: logind counts only VGA/DVI/DP/HDMI/TV-style
connectors, never eDP, LVDS or DSI, so darkening the lid panel does not change the
count in either direction.

### 4. `--prefer-output` is unchanged, wildcard included

`HDMI-A-1,HDMI-A-2,DP-1,*` stays exactly as it is. The wildcard was suspected of
keeping the panel eligible; it does not. An unmatched connector falls through to a
finite priority equal to the map's size either way, so removing `*` produces an
identical ordering and buys nothing. It could not have prevented the filmed defect
regardless, because gamescope drives one connector and cannot span.

### 5. Plan B gets `WLR_DRM_DEVICES`, gated on the NVIDIA card having a display

cage has no `--prefer-output` and no `--prefer-vk-device`. wlroots underneath it
reads `WLR_DRM_DEVICES`, and the session now pins it to the NVIDIA primary node,
enumerated from sysfs rather than hardcoded as `/dev/dri/card1` — card numbering is
not stable across boots.

Two things this buys. It drops the Intel device, and with it the eDP panel, from
wlroots' enumeration entirely: one output, no layout to extend across, and a
deterministic name-independent backstop for a karg that matched nothing. And it
closes a door nobody had named: unpinned, wlroots reads the PCI `boot_vga` sysattr
and moves that device to index 0, which on a hybrid laptop is the iGPU — so the
shell would composite on Intel with the NVIDIA output fed by cross-GPU blits, the
long-broken wlroots multi-GPU path. That is the same wrong-card false green
[ADR 0003](0003-test-targets.md) warns about, arriving through a door plan B has no
flag to close.

The gate is card-scoped and that is load-bearing. A glob over all HDMI connectors
would answer yes for an HDMI port on the Intel card while the NVIDIA card has
nothing attached — and pinning wlroots to a device with zero connectors is the worst
outcome available: wlroots' DRM backend starts and returns success with no connector
count check, cage has no zero-output check, and cage only terminates on losing an
output that was nested. The result is a live compositor, a running client, no
picture, and no nonzero exit for greetd to react to. A silent hang is worse than a
black screen that ends.

### 6. `cage -m last` is rejected

It exists, and it really does disable an output. It is rejected for three reasons.
It selects by enumeration order rather than by name — "whichever output wlroots
happened to add before this one" — which nothing in this image controls across two
DRM devices. Its hotplug behaviour is wrong for an appliance: plug a second display
in mid-session and cage switches to it and disables the TV. And after decisions 1
and 5 there is one output, so it has nothing to choose between.

This also corrects the second half of [ADR 0004](0004-session-compositor-scaffold.md)
finding 9: `-m last` and `WLR_DRM_DEVICES` both exist, and neither is an
output selector by name.

### 7. The shell is instrumentation only; it cannot pin its own screen

`Kiosk` gains logging and no behaviour. The plan previously said the shell would
have to choose its own screen under plan B; it does not, because the screen is
delivered below it, and that is the layer that also covers plymouth. Every
client-side fix leaves the lid panel lit for the whole boot.

Two claims that were about to justify this decision were **disproved by the VM run
of 2026-08-05** and are recorded here so nobody re-derives them. The first: "the
shell runs native Wayland under cage, where `window_set_current_screen` is an empty
function." It does not run native Wayland. cage ships with Xwayland, Godot's
linuxbsd driver order puts x11 first, and the measured run — with cage
demonstrably the compositor, after gamescope failed its handshake — reported server
`X11`. The shell is on XWayland under **both** plans. The second follows from it and
is in the next paragraph.

What survives regardless: there is no `DisplayServer.screen_get_name()` in Godot
4.7.1, so the shell cannot map `HDMI-A-1` to a screen index even in principle, and
picking by index is picking by enumeration order — the same coin flip that makes
cage's `-m last` unusable (decision 6).

What it logs instead: the display server name, the adapter, the screen count, every
screen's size and position, the window size and mode, the viewport and stretch
settings, the pillarbox the stretch is about to produce, and — at `<3>` — a line
naming the defect outright when the window matches no single screen. Twice: at
startup, and again after the first frame, because a Wayland compositor's first
configure can arrive after `_ready`.

The second disproved claim was that `DisplayServer.get_name()` would name the
compositor and give the shell a free second oracle for D4. It does not: it says
`X11` under both plans, for the reason above. The session script's own line remains
the only oracle. `get_name()` is still logged, because it is precisely the value that
would change if the driver order or cage's Xwayland support ever moved, and a shell
that has quietly switched to native Wayland is a different program from the one these
notes describe.

On 2026-08-05 the only evidence of the spanning defect was a phone camera pointed at
a laptop. One boot with these lines in it settles the geometry permanently, and the
`<3>` line fires by itself if it ever recurs.

### 8. The gamescope readiness timeout is 20 s, and cage's floor is a separate constant

The old 5 s was measured against nothing. gamescope writes its ready fd very late —
after Vulkan and ICD enumeration, after the DRM open and initial modeset, after
wlserver, and after every Xwayland server is up — and the film's own timings say
this machine is slow in exactly that window. A plan A that was merely slow, scored
as a plan A that failed, would decide D4 wrongly, and getting D4 right is the whole
of M1. The cost is a black screen for 20 s instead of 5 on a genuine failure, and
this appliance's criterion is "no text", not "fast".

`CAGE_MIN_RUNTIME` is split out at 5 s rather than reusing the raised constant,
because it answers a different question — whether cage got far enough that its exit
represents a session ending rather than a compositor that never came up. Raising it
to 20 would silently turn a cage that ran fifteen seconds and died from "restart it"
into "hold a black screen forever".

The handshake-failure branch now distinguishes a gamescope that is still running
from one that is already gone, because only the first says raising the timeout again
would help.

## Consequences

**Panel-only boot is worse than it is today, in one specific way.** Today a machine
with no external display shows a picture on the lid. With the karg it shows nothing
until `marwanos-panel.service` writes `detect`, and if that unit does not run, nothing
at all — and under plan A a *green-looking* nothing, because gamescope reports
success on a virtual screen when the device it opened has no connected connector.
That is the trade for the acceptance criterion. It is survivable because MarwanOS
boots from removable media and never repartitions Windows: pull the stick and the
laptop is back.

**There is no boot menu to edit.** `make-usb.sh` bakes the command line into a UKI
and renames `EFI/fedora` away, so the "hold shift, press `e`, delete the argument"
recovery that exists on every other Fedora machine does not exist here. `bootc
upgrade` does not change what the stick boots either — the UKI's baked cmdline wins.
Correcting a wrong karg means rebuild, `make-installer.sh raw`, `make-usb.sh`,
reflash. That is why the discovery step in the open questions is mandatory rather
than advisory, and why the karg lands on a *second* stick with the current one left
untouched.

**Root SSH becomes a real dependency, and it needs a cable.** `echo detect >
/sys/class/drm/cardN-eDP-1/status` clears the force live with no reboot, and root's
key is baked into the image with a `*` shadow field precisely so root survives a
broken machine. But ADR 0004 records wifi failing to associate on this chassis, so
this path is ethernet-only. Verify `ssh root@<target> true` from a cold boot
*before* the first karg build.

**The panel-goes-dark claim is source reasoning, not a measurement.** The residual
case is a pipe the firmware left programmed that i915's takeover readout does not
tear down, which would show as black-but-backlit. That is a camera question, in a
dark room, not a journal question.

**Nothing here covers the firmware window.** Before i915 binds, the framebuffer
belongs to simpledrm, whose connector is named `Unknown-1` and which no `video=eDP-*`
token can match; and systemd-stub paints the UKI's splash on whatever output the
firmware chose, before any kernel argument is parsed. If the lid panel must be dark
in those first frames too, the levers are building the appliance stick without a
stub splash and setting the firmware's primary display to HDMI.

**Hotplug is unaddressed, everywhere.** The `WLR_DRM_DEVICES` gate and the panel
policy are each evaluated once, at start. Plug the TV in after boot and neither
re-runs. And a mid-session HDMI unplug under plan B is now sharper: with one pinned
output, losing it leaves cage with an empty output list, no nested output to trigger
termination, and therefore a hung session with no exit for greetd to react to.
Pre-existing rather than created here, and not solvable in this change.

**Thermals.** An RTX 3060 laptop running an appliance workload with the lid shut and
lid handling ignored restricts airflow on most Predator chassis, and nothing here
watches temperature. Soak it at load, lid closed, before calling this shipped.

**Two changes at once make one hardware run uninterpretable.** Decisions 2, 3, 5, 7
and 8 are VM-testable and carry no display risk; they land first and they are what
give the journal the lines that decide everything else. Decision 1 lands alone,
afterwards, on its own stick.

## Open questions

1. **What is the internal connector actually called on this chassis?** `eDP-1` is a
   guess until read off the target. The discovery command, and the three checks that
   confirm the karg took (`/proc/cmdline`, `dmesg | grep -i forcing`, and the
   connector's sysfs `status`), are in [dev-setup.md](../dev-setup.md).
2. **Which compositor ran on 2026-08-05?** Still unread. The geometry is a cage
   signature — gamescope holds a single connector and CRTC and has no output-layout
   concept, while cage maximises its view to the bounding box of every output — and
   the staggered blackout in the film (external at t=43 s, panel at t=59 s) fits two
   DRM devices being taken sixteen seconds apart. But ADR 0004 records plan A
   starting and rendering on 2026-08-03, so both can be true of different boots.
   `journalctl -b -t marwanos-session -o cat` settles it, and that is what ADR 0005
   should cite rather than any reading of pixels.
3. **Dark, or black-but-backlit?** Camera, dark room, first three seconds and again
   once the shell is up.
4. **Is `acpid` installed and a second lid consumer?** One `rpm -q` away.
5. **Does `EXTRA_KARGS` reliably override a baked `video=` token?** The kernel's
   option lookup reassigns on every match with no early exit, so the last token for
   a given connector should win — which would make a rescue stick trivial. Worth
   confirming once with `dmesg | grep -i forcing`, and worth not depending on until
   then.
