#!/usr/bin/env bash
#
# Drive the MarwanOS shell invisibly under Xvfb and print its logs, so a UI
# flow can be asserted without touching the desktop the user is sitting at.
#
#   wsl -d FedoraLinux-43 -u root -e bash scripts/xvfb-shell-verify.sh Up Return Return
#
# Arguments are xdotool key names sent to the shell window in order (arrows for
# focus, Return for A / ui_accept, Escape for B / ui_cancel). A purely numeric
# argument is not a key but an extra sleep of that many seconds, for screens
# that need time to settle:
#
#   ... xvfb-shell-verify.sh Up Return 2 Return
#
# Everything the caller asserts on goes to STDOUT: exactly the container's
# logs, nothing else. Progress narration goes to stderr, so
#
#   out="$(wsl ... bash scripts/xvfb-shell-verify.sh Up Return)"
#   grep -q 'launch requested: store.steam' <<< "$out"
#
# is the whole harness. The shell's ShellLog lines are the assertion surface:
# `home rail ready with N cards`, `stores screen up with N tabs`, `settings
# opened`, `launch requested: <id>`, `install requested for <id>`. Counting a
# line before and after a key press proves a screen survived an action.
#
# Environment:
#   STATUS_DIR   directory of status-file fixtures, mounted read-only and
#                pointed at by MARWANOS_SHELL_STATUS_DIR -- same seam and same
#                file formats as run-shell-wsl.sh. Without it the shell makes
#                no claims about network or apps.
#   KEY_DELAY    seconds slept after every key (default 1).
#   SETTLE       seconds slept once the window exists, before driving (default 3).
#   SHOTS_DIR    if set, an ImageMagick `import` of the Xvfb root is written
#                there as final.png after the last key, for pixel assertions.
#   DISP         Xvfb display (default :99); RUNTIME_IMAGE, EXPORT_IMAGE and
#                BIN_OUT override the same knobs as run-shell-wsl.sh.
#
# Build and extraction mirror run-shell-wsl.sh: only the shell-export stage
# rebuilds, the binary is copied out, and it runs against the runtime image so
# "it started" is evidence about what the appliance ships.
#
# THREE TRAPS this script exists to remember, each of which has cost a session
# a round of debugging:
#
#   * WSLg owns /tmp/.X11-unix and Xvfb cannot create a unix socket there.
#     Xvfb listens on TCP only (-nolisten unix -listen tcp -ac) and the
#     container gets --network=host with DISPLAY=127.0.0.1:<display>.
#   * podman's journald log driver chokes on the shell's `<N>` priority
#     prefixes ("Failed parse journal entry"), so `podman logs` shows nothing
#     and the shell looks hung. --log-driver=k8s-file keeps the logs readable.
#   * Driving the visible WSLg desktop with SendKeys/AppActivate is unreliable
#     (Windows blocks focus-stealing; keys land in the foreground app) and
#     hostile to whoever is using the machine. This private display is the
#     only sanctioned way to press buttons in the shell.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_IMAGE="${RUNTIME_IMAGE:-ghcr.io/marwansummakieh/marwanos:latest}"
EXPORT_IMAGE="${EXPORT_IMAGE:-marwanos-shell-export:verify}"
BIN_OUT="${BIN_OUT:-/var/tmp/marwanos-shell-verify}"
DISP="${DISP:-:99}"
KEY_DELAY="${KEY_DELAY:-1}"
SETTLE="${SETTLE:-3}"
CTR="marwanos-verify-${DISP#:}"
BUILD_LOG="/tmp/marwanos-verify-build.log"

# stdout is reserved for the container logs; everything human goes here.
say() { echo "==> $*" >&2; }
die() { echo "xvfb-shell-verify: $*" >&2; exit 1; }

command -v podman  >/dev/null || die "no podman"
command -v Xvfb    >/dev/null || die "no Xvfb"
command -v xdotool >/dev/null || die "no xdotool"
podman image exists "$RUNTIME_IMAGE" \
    || die "no runtime image $RUNTIME_IMAGE -- build it first: scripts/build-push.sh --no-push"

if [[ -n "${STATUS_DIR:-}" && ! -d "$STATUS_DIR" ]]; then
    die "STATUS_DIR=$STATUS_DIR is not a directory"
fi

say "Exporting the shell (only the shell-export stage rebuilds)"
podman build \
    --file "${REPO_ROOT}/os/Containerfile" \
    --target shell-export \
    --tag "$EXPORT_IMAGE" \
    "$REPO_ROOT" >"$BUILD_LOG" 2>&1 \
    || { tail -30 "$BUILD_LOG" >&2; die "export build failed (full log: $BUILD_LOG)"; }

say "Extracting the binary"
cid="$(podman create "$EXPORT_IMAGE" /bin/true)"
podman cp "${cid}:/out/usr/lib/marwanos/shell/marwanos-shell" "$BIN_OUT"
podman rm -f "$cid" >/dev/null
chmod 0755 "$BIN_OUT"

say "Xvfb on $DISP (TCP only -- WSLg owns /tmp/.X11-unix)"
pkill -f "Xvfb $DISP" 2>/dev/null || true
sleep 1
Xvfb "$DISP" -screen 0 1920x1080x24 -nolisten unix -listen tcp -ac \
    >/tmp/marwanos-verify-xvfb.log 2>&1 &
XVFB_PID=$!
trap 'podman rm -f "$CTR" >/dev/null 2>&1 || true; kill "$XVFB_PID" 2>/dev/null || true' EXIT
sleep 2

STATUS_ARGS=()
if [[ -n "${STATUS_DIR:-}" ]]; then
    STATUS_ARGS=(-e MARWANOS_SHELL_STATUS_DIR=/status -v "${STATUS_DIR}:/status:ro")
fi

say "Starting the shell container"
podman rm -f "$CTR" >/dev/null 2>&1 || true
podman run -d --name "$CTR" \
    --network=host --log-driver=k8s-file \
    -e DISPLAY="127.0.0.1${DISP}" \
    -e HOME=/godothome \
    -e XDG_RUNTIME_DIR=/godothome \
    -e MARWANOS_SHELL_WINDOWED=1 \
    "${STATUS_ARGS[@]}" \
    --tmpfs /godothome:rw,mode=1777 \
    -v "${BIN_OUT}:/usr/lib/marwanos/shell/marwanos-shell:ro" \
    --entrypoint /usr/lib/marwanos/shell/marwanos-shell \
    "$RUNTIME_IMAGE" \
    --rendering-method gl_compatibility --audio-driver Dummy --max-fps 30 \
    >/dev/null || die "container did not start"

say "Waiting for the shell window"
export DISPLAY="127.0.0.1${DISP}"
win=""
for _ in $(seq 1 30); do
    win="$(xdotool search --name 'MarwanOS Shell' 2>/dev/null | head -1)" || true
    [[ -n "$win" ]] && break
    sleep 1
done
if [[ -z "$win" ]]; then
    podman logs "$CTR" 2>&1 | tail -20 >&2
    die "shell window never appeared on $DISP"
fi
sleep "$SETTLE"

if (( $# > 0 )); then
    say "Driving: $*"
    xdotool windowactivate "$win" 2>/dev/null || true
    for key in "$@"; do
        if [[ "$key" =~ ^[0-9]+$ ]]; then
            sleep "$key"
        else
            xdotool key --window "$win" "$key"
            sleep "$KEY_DELAY"
        fi
    done
fi

if [[ -n "${SHOTS_DIR:-}" ]]; then
    command -v import >/dev/null || die "SHOTS_DIR set but ImageMagick import is missing"
    mkdir -p "$SHOTS_DIR"
    import -display "127.0.0.1${DISP}" -window root "${SHOTS_DIR}/final.png"
    say "Screenshot: ${SHOTS_DIR}/final.png"
fi

say "Container logs follow on stdout"
podman logs "$CTR" 2>&1
