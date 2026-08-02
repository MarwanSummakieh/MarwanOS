#!/usr/bin/env bash
#
# Build the MarwanOS image and push it to GHCR.
# Runs on the Linux build host (see docs/dev-setup.md), not on the target.
#
#   ./scripts/build-push.sh              # build + push :latest
#   ./scripts/build-push.sh --no-push    # build only, for a syntax check
#   TAG=spike-gamescope ./scripts/build-push.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Defaulted rather than required. Relying on the environment meant the script
# broke depending on how the shell was invoked -- `bash -lc` is a login shell and
# does not read ~/.bashrc, and PowerShell mangles $VAR on its way to WSL. Override
# with GHCR_USER=... for a different account.
GHCR_USER="${GHCR_USER:-marwansummakieh}"
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-marwanos}"
TAG="${TAG:-latest}"

IMAGE_REF="${REGISTRY}/${GHCR_USER}/${IMAGE_NAME}:${TAG}"

PUSH=1
for arg in "$@"; do
    case "$arg" in
        --no-push) PUSH=0 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# Version metadata baked into /usr/share/marwanos/build-info. This is what you
# `cat` on the target to prove an upgrade actually landed.
COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)"
if ! git -C "$REPO_ROOT" diff --quiet 2>/dev/null; then
    COMMIT="${COMMIT}-dirty"
fi
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VERSION="${VERSION:-0.0.$(date -u +%Y%m%d%H%M)}"

echo "==> Building ${IMAGE_REF}"
echo "    version ${VERSION}  commit ${COMMIT}"

podman build \
    --file "${REPO_ROOT}/os/Containerfile" \
    --tag "${IMAGE_REF}" \
    --build-arg "MARWANOS_VERSION=${VERSION}" \
    --build-arg "MARWANOS_COMMIT=${COMMIT}" \
    --build-arg "MARWANOS_BUILD_DATE=${BUILD_DATE}" \
    "${REPO_ROOT}/os"

if [[ "$PUSH" -eq 0 ]]; then
    echo "==> Built ${IMAGE_REF} (push skipped)"
    exit 0
fi

# Log in only if we are not already authenticated, and never echo the token.
if ! podman login --get-login "${REGISTRY}" >/dev/null 2>&1; then
    TOKEN_FILE="${HOME}/.config/marwanos/ghcr-token"
    if [[ -r "$TOKEN_FILE" ]]; then
        echo "==> Logging in to ${REGISTRY} as ${GHCR_USER}"
        podman login --username "${GHCR_USER}" --password-stdin "${REGISTRY}" < "$TOKEN_FILE"
    else
        echo "Not logged in to ${REGISTRY} and no token at ${TOKEN_FILE}." >&2
        echo "See docs/dev-setup.md, section 'GHCR access'." >&2
        exit 1
    fi
fi

echo "==> Pushing ${IMAGE_REF}"
podman push "${IMAGE_REF}"

DIGEST="$(podman inspect --format '{{index .RepoDigests 0}}' "${IMAGE_REF}" 2>/dev/null || true)"

cat <<EOF

==> Pushed
    ${IMAGE_REF}
    ${DIGEST:-<digest unavailable>}

On the target:
    sudo bootc upgrade && sudo systemctl reboot
After reboot, confirm the new build landed:
    cat /usr/share/marwanos/build-info
To undo a bad build:
    sudo bootc rollback && sudo systemctl reboot
EOF
