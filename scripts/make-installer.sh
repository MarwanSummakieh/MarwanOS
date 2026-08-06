#!/usr/bin/env bash
#
# Turn the pushed MarwanOS image into installable media with bootc-image-builder.
#
# This is the "last time installation media is ever used" step from M0. You run
# it once per target (VM, then the real box). After the install, every further
# change arrives via `bootc upgrade` and this script goes back in the drawer --
# with one exception: after a base bump, regenerating a fresh installer is often
# faster than nursing a broken target back to life.
#
#   ./scripts/make-installer.sh anaconda-iso   # bootable installer ISO
#   ./scripts/make-installer.sh qcow2          # disk image for QEMU/libvirt
#   ./scripts/make-installer.sh vhdx           # disk image for Hyper-V
#
# Requires an SSH public key: MarwanOS has no getty on tty1 by design (D6), so
# SSH is how you reach a target that has not got a working session yet.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Overridable because the output is 10+ GB. When the repo lives on a Windows
# drive seen through /mnt/c, writing that much through the filesystem bridge is
# glacial -- point OUT_DIR at the Linux filesystem and copy the finished artifact
# across once.
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/out}"

GHCR_USER="${GHCR_USER:-marwansummakieh}"
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-marwanos}"
TAG="${TAG:-latest}"
IMAGE_REF="${REGISTRY}/${GHCR_USER}/${IMAGE_NAME}:${TAG}"

ADMIN_USER="${ADMIN_USER:-marwan}"
SSH_KEY_FILE="${SSH_KEY_FILE:-${HOME}/.ssh/id_ed25519.pub}"

TYPE="${1:-anaconda-iso}"
# vhdx is not a bootc-image-builder output type; we build raw and convert.
BIB_TYPE="$TYPE"
[[ "$TYPE" == "vhdx" ]] && BIB_TYPE="raw"

case "$BIB_TYPE" in
    anaconda-iso|qcow2|raw|vmdk) ;;
    *) echo "unsupported type: ${TYPE}" >&2; exit 2 ;;
esac

if [[ ! -r "$SSH_KEY_FILE" ]]; then
    echo "No SSH public key at ${SSH_KEY_FILE}." >&2
    echo "Generate one with:  ssh-keygen -t ed25519" >&2
    echo "or point SSH_KEY_FILE at an existing .pub file." >&2
    exit 1
fi
# Key files authored on Windows carry CRLF, and a stray 0x0d inside the TOML
# string makes the config unparseable: bib fails with "TOML files cannot contain
# control characters: '0x0d'". Reading the key with $(<file) preserves it.
SSH_KEY="$(tr -d '\r\n' < "$SSH_KEY_FILE")"

mkdir -p "$OUT_DIR"

# Written into out/ (gitignored) rather than committed: it embeds a key and is
# per-machine, not a property of the OS.
CONFIG="${OUT_DIR}/bib-config.toml"
# Two users. The root entry is a deliberate fallback, not a fix for anything.
#
# osbuild gives a keyed-but-passwordless user '!' in the shadow password field,
# and non-root logins are refused outright while /run/nologin exists (a boot that
# never reached systemd-user-sessions). root is immune to both -- its field is
# '*' rather than '!', and pam_nologin exempts uid 0 -- so it is the account that
# still works when the machine is unhappy. Cheap insurance on a target whose
# whole design goal is having no terminal.
#
# Login stays key-only; no password is set anywhere unless ADMIN_PASSWORD_HASH
# is supplied below.
{
    printf '[[customizations.user]]\nname = "%s"\ngroups = ["wheel"]\nkey = "%s"\n' \
        "${ADMIN_USER}" "${SSH_KEY}"

    # Optional console password, supplied as an already-hashed value so no
    # plaintext secret is ever passed through this script or its environment.
    # Generate one with:  openssl passwd -6
    # Then:               ADMIN_PASSWORD_HASH='$6$...' ./scripts/make-installer.sh vhdx
    #
    # Worth setting: a key-only machine has no way in at the console, which is
    # exactly where you end up when SSH is the thing that is broken.
    if [[ -n "${ADMIN_PASSWORD_HASH:-}" ]]; then
        printf 'password = "%s"\n' "${ADMIN_PASSWORD_HASH}"
    fi

    printf '\n[[customizations.user]]\nname = "root"\nkey = "%s"\n' "${SSH_KEY}"
} > "$CONFIG"

echo "==> Building ${TYPE} from ${IMAGE_REF}"
echo "    users: ${ADMIN_USER} + root (SSH key only, no password set)"

# No --config flag exists; bib picks the config up from the /config.toml mount.
# --output must be explicit, its default is the container's working directory.
# The storage mount is what lets bib read an image that only exists locally,
# which is how this works before the first push to GHCR.
SUDO=""
[[ "$(id -u)" -eq 0 ]] || SUDO="sudo"

$SUDO podman run \
    --rm \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v "${OUT_DIR}":/output \
    -v "${CONFIG}":/config.toml:ro \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    build \
    --type "${BIB_TYPE}" \
    --no-default-kernel-args \
    --output /output \
    "${IMAGE_REF}"

# --no-default-kernel-args is what drops bib's console=ttyS0 (M2). On hardware
# with no serial port that karg makes serial-getty respawn forever, and it is a
# text-on-console risk for the silent-boot gate. The image masks the unit as a
# backstop, but the karg itself has no business on an appliance; a QEMU run that
# wants kernel output on the serial line can add console=ttyS0 back per-stick
# via make-usb.sh's EXTRA_KARGS.

# bib does exit non-zero on failure, and set -e would already catch that. This
# check stays as belt-and-braces: it turns "succeeded but produced nothing" into
# a loud failure, and names the artifact for the conversion step below.
ARTIFACT="$(find "${OUT_DIR}" -type f \( -name '*.iso' -o -name '*.qcow2' -o -name '*.vmdk' -o -name '*.raw' \) -newer "$CONFIG" | head -1)"
if [[ -z "$ARTIFACT" ]]; then
    echo >&2
    echo "bootc-image-builder produced no artifact. Do not trust its exit code --" >&2
    echo "read the output above for the real error." >&2
    exit 1
fi

if [[ "$TYPE" == "vhdx" ]]; then
    echo "==> Converting to VHDX for Hyper-V"
    qemu-img convert -f raw -O vhdx "$ARTIFACT" "${OUT_DIR}/marwanos.vhdx"
    rm -f "$ARTIFACT"
fi

echo
echo "==> Output in ${OUT_DIR}:"
find "${OUT_DIR}" -type f \( -name '*.iso' -o -name '*.qcow2' -o -name '*.vhdx' -o -name '*.vmdk' -o -name '*.raw' \) -printf '    %p (%s bytes)\n'
echo
echo "    Hyper-V wants the VHDX on a Generation 2 VM with Secure Boot OFF (D7)."
