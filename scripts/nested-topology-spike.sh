#!/usr/bin/env bash
#
# Answer ONE question, on the bench, before anybody rewrites a session:
#
#   does gamescope survive running NESTED inside a wlroots compositor on this
#   NVIDIA driver, past the three-minute mark?
#
# WHY THIS SCRIPT EXISTS AND WHY IT IS THIS SMALL. The proposed topology -- the
# shell on a plain compositor, one gamescope per game -- would fix the thing the
# owner has been fighting: gamescope's embedded mode has exactly ONE main-window
# slot, identified by STEAM_GAME=769, and that is Valve's own value which their
# client claims unconditionally. A shell and Valve's client on one embedded
# gamescope are not colliding by accident; they are claiming the same slot. Give
# Steam its own nested compositor and the fight has nowhere to happen.
#
# But nested gamescope HAS BEEN TRIED HERE AND WITHDRAWN. Commit 33a28a4 -- "One
# compositor is enough: the nested gamescope retires on its own coredump" --
# pulled it after the inner compositor aborted on this NVIDIA driver THREE
# MINUTES into the first real game. appscan still carries the scar in the comment
# above its exec line.
#
# That earlier attempt was gamescope inside GAMESCOPE. This is gamescope inside
# WLROOTS, which is a different parent and genuinely untested. The distinction is
# why the idea is not already dead -- and it is also exactly the kind of
# distinction that turns out not to matter, which is what this measures.
#
# So: no session changes, no image changes, nothing to roll back. If the answer
# is no, the topology is dead for the cost of one script and the bench is exactly
# as it was.
#
# THE DURATION IS THE WHOLE TEST. The recorded failure was at ~3 minutes. A spike
# that runs for thirty seconds and looks fine proves NOTHING, so the default is
# 300s and going below 240 is refused rather than silently allowed.
#
# vkcube IS THE CLIENT, NOT THE SHELL, and that is deliberate: the Containerfile
# keeps vulkan-tools precisely because vkcube "is the one client that can tell a
# compositor problem apart from a shell problem". If the shell were the client
# and the screen went black, this would have proved nothing about gamescope.
#
#   sudo bash scripts/nested-topology-spike.sh              # 300s, default
#   sudo bash scripts/nested-topology-spike.sh --seconds 420
#   sudo bash scripts/nested-topology-spike.sh --keep-greetd  # dry probe only
#
# RUN IT FROM THE TELEVISION'S OWN CONSOLE (a VT), not over SSH: cage needs a
# seat, and a seatless start fails in a way that looks like a driver problem and
# is not.
#
set -uo pipefail

SECONDS_TO_RUN=300
KEEP_GREETD=0
while [ $# -gt 0 ]; do
    case "$1" in
        --seconds) SECONDS_TO_RUN="${2:-}"; shift 2 ;;
        --keep-greetd) KEEP_GREETD=1; shift ;;
        -h|--help) sed -n '2,48p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

case "$SECONDS_TO_RUN" in
    ''|*[!0-9]*) echo "--seconds wants digits" >&2; exit 2 ;;
esac
if [ "$SECONDS_TO_RUN" -lt 240 ]; then
    # Not a style preference. The failure being looked for happened at ~180s;
    # a shorter run that passes is indistinguishable from one that never got
    # to the interesting part, and would be reported as a green.
    echo "refusing: the recorded coredump was at ~180s, so anything under 240s" >&2
    echo "cannot tell 'survived' from 'stopped watching too early'." >&2
    exit 2
fi

say() { printf '\n== %s\n' "$*"; }
LOG=/tmp/nested-spike.$$
mkdir -p "$LOG"
echo "logs: $LOG"

# ---------------------------------------------------------------- preconditions
say "what is installed"
for b in cage gamescope vkcube coredumpctl; do
    p="$(command -v "$b" 2>/dev/null)"
    printf '  %-12s %s\n' "$b" "${p:-MISSING}"
    [ -n "$p" ] || { echo "cannot run without $b" >&2; exit 1; }
done

# THE GPU PIN, and it is the reason cage was rejected as plan B in the first
# place. gamescope pins by PCI id with --prefer-vk-device; cage cannot, and
# wlroots' own wlr_session_find_gpus() puts the PCI boot_vga device at index 0 --
# which on this hybrid chassis is the INTEL iGPU. Composite there and the NVIDIA
# output is fed by cross-GPU blits, which would look like a performance problem
# and read as a verdict on nesting. WLR_DRM_DEVICES is wlroots' equivalent lever
# and the session deliberately stopped exporting it when plan B was dropped.
say "picking the NVIDIA DRM node"
NVIDIA_NODE=""
for dev in /sys/class/drm/card[0-9]*; do
    [ -e "$dev/device/vendor" ] || continue
    vendor="$(cat "$dev/device/vendor" 2>/dev/null)" || continue
    if [ "$vendor" = "0x10de" ]; then
        NVIDIA_NODE="/dev/dri/$(basename "$dev")"
        break
    fi
done
if [ -z "$NVIDIA_NODE" ]; then
    echo "no NVIDIA DRM node found; this spike would measure the iGPU" >&2
    exit 1
fi
echo "  WLR_DRM_DEVICES=$NVIDIA_NODE"

say "connected connectors on that card"
for st in /sys/class/drm/card[0-9]*-*/status; do
    [ -e "$st" ] || continue
    printf '  %-28s %s\n' "$(basename "$(dirname "$st")")" "$(cat "$st")"
done

# A baseline, so a coredump that was already there is not blamed on this run.
say "coredumps BEFORE (anything here is pre-existing)"
coredumpctl list --since -2h 2>/dev/null | tail -5 || echo "  none"

if [ "$KEEP_GREETD" -eq 1 ]; then
    say "--keep-greetd: stopping here, nothing was started"
    exit 0
fi

# ------------------------------------------------------------------- the run
# ALWAYS PUT THE TELEVISION BACK. The trap is unconditional and covers the
# script being killed, the run timing out, and every early exit below. SSH is
# not a reliable way back into this machine (port 22 has been refused more than
# once), so a spike that leaves greetd stopped is a spike that bricks the couch.
restore() {
    say "restoring greetd"
    systemctl start greetd 2>/dev/null || echo "  could not start greetd -- run: systemctl start greetd"
}
trap restore EXIT INT TERM

say "stopping greetd so the DRM master is free"
systemctl stop greetd || { echo "could not stop greetd" >&2; exit 1; }
sleep 2

# gamescope inside cage. --backend wayland is explicit rather than inferred:
# gamescope picks a backend from the environment and an inference that silently
# chose drm would be measuring the OLD topology while claiming to measure this
# one. -W/-H are passed because gamescope's NESTED surface defaults to 1280x720
# regardless of the output -- the trap that had everything on this machine
# rendering at 720p and being upscaled.
say "running cage > gamescope(nested) > vkcube for ${SECONDS_TO_RUN}s"
echo "  (expect the cube on the television; the failure being hunted is an"
echo "   abort/coredump partway through, not a black screen at the start)"

W=1920; H=1080
modes="$(cat /sys/class/drm/card[0-9]*-HDMI*/modes 2>/dev/null | head -1)" || modes=""
case "$modes" in
    [0-9]*x[0-9]*) W="${modes%%x*}"; H="${modes##*x}" ;;
esac
echo "  nested size: ${W}x${H}"

start="$(date +%s)"
WLR_DRM_DEVICES="$NVIDIA_NODE" \
    timeout --signal=TERM "$SECONDS_TO_RUN" \
    cage -- gamescope --backend wayland -W "$W" -H "$H" -w "$W" -h "$H" -- vkcube \
    > "$LOG/run.out" 2>&1
rc=$?
end="$(date +%s)"
elapsed=$(( end - start ))

# ------------------------------------------------------------------- verdict
say "it ran for ${elapsed}s (exit $rc)"
echo "--- last 25 lines ---"
tail -25 "$LOG/run.out"

say "coredumps AFTER"
coredumpctl list --since -2h 2>/dev/null | tail -8 || echo "  none"

say "VERDICT"
# 124 is timeout's "I had to stop it" -- which here is the SUCCESS case: the
# stack was still running when the clock ran out.
if [ "$rc" -eq 124 ] && [ "$elapsed" -ge "$SECONDS_TO_RUN" ]; then
    echo "  SURVIVED ${elapsed}s. Nested gamescope on a wlroots parent did NOT"
    echo "  reproduce the 33a28a4 coredump within this window."
    echo "  NOT YET PROVEN: a real game (vkcube is a trivial client) and input"
    echo "  routing. This clears the blocker only."
    echo "  (An earlier draft said 'Steam's hidraw grab' here. That was wrong:"
    echo "   Steam Input does not EVIOCGRAB, the physical evdev node keeps"
    echo "   delivering, and this image ships no steam-devices udev rules.)"
elif grep -qiE 'coredump|assert|abort|Segmentation' "$LOG/run.out"; then
    echo "  DIED at ${elapsed}s with an abort in the log -- the 33a28a4 failure"
    echo "  reproduces on a wlroots parent too. The topology is dead; do not"
    echo "  spend a rewrite on it."
else
    echo "  INCONCLUSIVE: exited at ${elapsed}s (exit $rc) without an obvious"
    echo "  abort. Read $LOG/run.out before concluding anything. An immediate"
    echo "  exit usually means cage found no seat -- run this from the TV's own"
    echo "  console, not over SSH."
fi
echo
echo "full log kept at $LOG/run.out"
