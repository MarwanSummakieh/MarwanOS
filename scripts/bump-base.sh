#!/usr/bin/env bash
#
# Re-resolve the base and akmods digests in os/Containerfile.
#
# D-note: we pin by digest and bump deliberately (never track a floating tag),
# because an upstream rebuild landing mid-debug is indistinguishable from your
# own change breaking the boot. This script is the deliberate bump.
#
# The two images must be bumped together: base-main:<F> pairs with
# akmods-nvidia-open:main-<F>. A mismatched pair builds cleanly and then boots
# to a black screen, so this script refuses to update one without the other.
#
#   ./scripts/bump-base.sh          # show what would change
#   ./scripts/bump-base.sh --write  # apply to os/Containerfile
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINERFILE="${REPO_ROOT}/os/Containerfile"

WRITE=0
[[ "${1:-}" == "--write" ]] && WRITE=1

resolve_digest() {
    local repo="$1" tag="$2" token
    token="$(curl -fsSL "https://ghcr.io/token?scope=repository:${repo}:pull&service=ghcr.io" \
        | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
    [[ -n "$token" ]] || { echo "could not get pull token for ${repo}" >&2; return 1; }

    curl -fsSI -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json" \
        "https://ghcr.io/v2/${repo}/manifests/${tag}" \
        | tr -d '\r' | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: //p'
}

current_arg() {
    sed -n "s/^ARG $1=\"\(.*\)\"$/\1/p" "$CONTAINERFILE"
}

BASE_TAG="$(current_arg BASE_TAG)"
AKMODS_TAG="$(current_arg AKMODS_TAG)"
OLD_BASE="$(current_arg BASE_DIGEST)"
OLD_AKMODS="$(current_arg AKMODS_DIGEST)"

# main-43 must pair with 43. Catch the mismatch here, not on a dark TV.
if [[ "main-${BASE_TAG}" != "$AKMODS_TAG" ]]; then
    echo "Tag mismatch: BASE_TAG=${BASE_TAG} does not pair with AKMODS_TAG=${AKMODS_TAG}." >&2
    echo "Expected AKMODS_TAG=main-${BASE_TAG}. Fix os/Containerfile before bumping." >&2
    exit 1
fi

echo "==> Resolving digests for Fedora ${BASE_TAG}"
NEW_BASE="$(resolve_digest ublue-os/base-main "$BASE_TAG")"
NEW_AKMODS="$(resolve_digest ublue-os/akmods-nvidia-open "$AKMODS_TAG")"

[[ -n "$NEW_BASE" && -n "$NEW_AKMODS" ]] || { echo "digest resolution failed" >&2; exit 1; }

printf '\n    base-main:%s\n      old %s\n      new %s\n' "$BASE_TAG" "$OLD_BASE" "$NEW_BASE"
printf '\n    akmods-nvidia-open:%s\n      old %s\n      new %s\n\n' "$AKMODS_TAG" "$OLD_AKMODS" "$NEW_AKMODS"

if [[ "$NEW_BASE" == "$OLD_BASE" && "$NEW_AKMODS" == "$OLD_AKMODS" ]]; then
    echo "==> Already current, nothing to do."
    exit 0
fi

if [[ "$WRITE" -eq 0 ]]; then
    echo "==> Dry run. Re-run with --write to apply."
    exit 0
fi

sed -i \
    -e "s|^ARG BASE_DIGEST=\".*\"$|ARG BASE_DIGEST=\"${NEW_BASE}\"|" \
    -e "s|^ARG AKMODS_DIGEST=\".*\"$|ARG AKMODS_DIGEST=\"${NEW_AKMODS}\"|" \
    "$CONTAINERFILE"

echo "==> Updated os/Containerfile. Build, deploy to the VM target, and only"
echo "    then to bare metal -- a base bump is exactly the kind of change that"
echo "    breaks boot rather than build."
