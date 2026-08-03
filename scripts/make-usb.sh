#!/usr/bin/env bash
#
# Post-process a MarwanOS raw disk image into one the Predator's firmware will
# actually boot from USB.
#
# The problem, found on an Acer Predator PT314-51s (firmware V1.10): the
# firmware loads EFI binaries off a USB stick perfectly well, but GRUB, once
# running from that stick, cannot read the stick's own partition table. `ls
# (hd0)/` answers "unknown filesystem" and no (hd0,gptN) devices appear at all.
# A bootloader that cannot see a filesystem cannot find a kernel, so the normal
# shim -> GRUB -> BLS chain is dead on this machine. Nothing in the image fixes
# that, because the broken part is the firmware's block layer under GRUB.
#
# The way around it is to take the bootloader out of the path. A Unified Kernel
# Image is the kernel, the initramfs and the command line linked into a single
# EFI binary behind the systemd-boot stub. The firmware loads all ~350 MB of it
# as one file from the ESP and no bootloader filesystem access ever happens.
#
# This script builds that UKI from the image's own kernel, initramfs and BLS
# command line, drops it at EFI/BOOT/BOOTX64.EFI, and moves EFI/fedora aside so
# nothing can chain back into GRUB.
#
#   ./scripts/make-usb.sh                    # the single .raw in OUT_DIR
#   ./scripts/make-usb.sh /path/to/disk.raw
#   ./scripts/make-usb.sh --help
#
# The image is edited in place; write it to the stick afterwards exactly as
# before (Rufus in DD mode, or balenaEtcher). Re-running on an already-processed
# image is safe.
#
# The UKI is a *copy*. A `bootc upgrade` on the target writes a new kernel and
# initramfs to the stick's boot partition, and the firmware never looks there --
# so after an upgrade the stick still boots the old one until this script is run
# against a freshly built image. See docs/dev-setup.md, section 5.
#
# Needs root (loop devices), plus:  dnf install -y systemd-ukify systemd-boot-unsigned
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Same default as make-installer.sh, and overridable for the same reason: these
# artifacts are 15+ GB and do not belong on a /mnt/c filesystem bridge.
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/out}"

# bootc-image-builder's raw layout is 1 bios-boot, 2 ESP, 3 boot, 4 root.
# Overridable, but also verified after mounting rather than trusted -- if bib
# ever renumbers, this fails with a sentence instead of writing a UKI into the
# wrong filesystem.
ESP_PART="${ESP_PART:-2}"
BOOT_PART="${BOOT_PART:-3}"
ROOT_PART="${ROOT_PART:-4}"

UKIFY="${UKIFY:-/usr/lib/systemd/ukify}"
STUB="${STUB:-/usr/lib/systemd/boot/efi/linuxx64.efi.stub}"

# Slack on the ESP so a copy cannot fill it to the last byte.
ESP_SLACK_BYTES=$((4 * 1024 * 1024))

usage() {
    cat <<'EOF'
Usage: make-usb.sh [IMAGE.raw]

Rewrites a raw MarwanOS disk image so it boots on firmware that cannot run GRUB
from USB: builds a Unified Kernel Image from the image's own kernel, initramfs
and BLS command line, installs it as EFI/BOOT/BOOTX64.EFI on the ESP, and
renames EFI/fedora to EFI/fedora-off.

With no argument, uses the single *.raw file in OUT_DIR.

  IMAGE.raw   the image to edit, in place

Environment:
  OUT_DIR     where to look for the image   (default: <repo>/out)
  ESP_PART    ESP partition number          (default: 2)
  BOOT_PART   boot partition number         (default: 3)
  ROOT_PART   root partition number         (default: 4; read only, for the
              image's os-release so the UKI identifies as MarwanOS)
  UKIFY       path to ukify                 (default: /usr/lib/systemd/ukify)
  STUB        systemd-boot EFI stub         (default:
              /usr/lib/systemd/boot/efi/linuxx64.efi.stub)
  EXTRA_KARGS extra kernel arguments appended after the BLS command line,
              for per-stick hardware quirks. Example, a stick with broken
              UAS: EXTRA_KARGS="usb-storage.quirks=346d:5678:u"

Requires root for loop devices, and the systemd-ukify and
systemd-boot-unsigned packages.
EOF
}

die() {
    echo >&2
    echo "make-usb: $*" >&2
    exit 1
}

file_size() { stat -c '%s' "$1"; }

mib() { echo "$(( ${1} / 1024 / 1024 )) MiB"; }

# Pure bash, on purpose. The build host is a minimal WSL Fedora and this script
# has to work there without pulling in text-processing tools to read four lines
# of config.
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

IMAGE=""
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        -*) echo "unknown argument: $arg" >&2; exit 2 ;;
        *)
            [[ -z "$IMAGE" ]] || { echo "give at most one image" >&2; exit 2; }
            IMAGE="$arg"
            ;;
    esac
done

if [[ -z "$IMAGE" ]]; then
    # bib nests its output (OUT_DIR/image/disk.raw), so look one level down too.
    # Found the hard way: the first real run of this script missed the image it
    # was standing next to.
    shopt -s nullglob
    CANDIDATES=("${OUT_DIR}"/*.raw "${OUT_DIR}"/*/*.raw)
    shopt -u nullglob
    case "${#CANDIDATES[@]}" in
        1) IMAGE="${CANDIDATES[0]}" ;;
        0) die "no *.raw in ${OUT_DIR} (or one level below). Build one first:
    ./scripts/make-installer.sh raw" ;;
        *) die "more than one *.raw under ${OUT_DIR}; name the one you mean:
$(printf '    %s\n' "${CANDIDATES[@]}")" ;;
    esac
fi

[[ -f "$IMAGE" ]] || die "no such image: ${IMAGE}"
# bootc-image-builder writes its output as root, so this is normally the "you
# forgot sudo" message rather than a permissions problem.
[[ -w "$IMAGE" ]] || die "image is not writable: ${IMAGE}
    bib writes it as root. Run this with sudo."

SUDO=""
[[ "$(id -u)" -eq 0 ]] || SUDO="sudo"

# Everything this script needs, checked before it touches the image, so a
# missing package costs a sentence rather than a half-modified ESP.
command -v losetup >/dev/null 2>&1 || die "losetup not found (dnf install -y util-linux)"
command -v mount   >/dev/null 2>&1 || die "mount not found (dnf install -y util-linux)"
[[ -x "$UKIFY" ]] || die "no ukify at ${UKIFY}
    dnf install -y systemd-ukify"
[[ -r "$STUB" ]] || die "no systemd-boot stub at ${STUB}
    dnf install -y systemd-boot-unsigned"

LOOP=""
ESP_MNT=""
BOOT_MNT=""
WORK_DIR=""

cleanup() {
    set +e
    if [[ -n "$ESP_MNT" ]]; then
        $SUDO umount "$ESP_MNT" 2>/dev/null
        rmdir "$ESP_MNT" 2>/dev/null
    fi
    if [[ -n "$BOOT_MNT" ]]; then
        $SUDO umount "$BOOT_MNT" 2>/dev/null
        rmdir "$BOOT_MNT" 2>/dev/null
    fi
    if [[ -n "$LOOP" ]]; then
        $SUDO losetup -d "$LOOP" 2>/dev/null
    fi
    if [[ -n "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}
trap cleanup EXIT

# The UKI is ~350 MB, and /tmp is tmpfs on a systemd host -- default to /var/tmp,
# which is real disk. TMPDIR still wins if you want it elsewhere.
WORK_DIR="$(mktemp -d "${TMPDIR:-/var/tmp}/marwanos-uki.XXXXXX")"

echo "==> Image: ${IMAGE} ($(mib "$(file_size "$IMAGE")"))"

LOOP="$($SUDO losetup --find --show --partscan "$IMAGE")"
[[ -n "$LOOP" ]] || die "losetup produced no device for ${IMAGE}"
echo "    attached as ${LOOP}"

ESP_DEV="${LOOP}p${ESP_PART}"
BOOT_DEV="${LOOP}p${BOOT_PART}"

wait_for_part() {
    local dev="$1" i
    for (( i = 0; i < 20; i++ )); do
        [[ -b "$dev" ]] && return 0
        sleep 0.25
    done
    return 1
}

# --partscan asks the kernel to scan the table, but the /dev nodes are created by
# udev, which a minimal WSL distro may not be running. partx pokes the kernel
# directly and is the fallback that makes this work there.
if ! wait_for_part "$ESP_DEV" || ! wait_for_part "$BOOT_DEV"; then
    $SUDO partx -a "$LOOP" >/dev/null 2>&1 || true
    wait_for_part "$ESP_DEV" || die "no partition node at ${ESP_DEV}.
    The image does not have the expected layout, or partition nodes are not
    being created. Check with:  fdisk -l ${LOOP}
    Override with ESP_PART= / BOOT_PART= if bib renumbered the partitions."
    wait_for_part "$BOOT_DEV" || die "no partition node at ${BOOT_DEV}."
fi

ESP_MNT="$(mktemp -d)"
BOOT_MNT="$(mktemp -d)"

# boot is mounted read-only: this script only ever reads from it, and a
# read-only mount makes that a property of the system rather than a promise.
$SUDO mount -o ro "$BOOT_DEV" "$BOOT_MNT" \
    || die "could not mount ${BOOT_DEV} (expected the boot partition)"
$SUDO mount "$ESP_DEV" "$ESP_MNT" \
    || die "could not mount ${ESP_DEV} (expected the ESP)"

[[ -d "${BOOT_MNT}/loader/entries" ]] \
    || die "partition ${BOOT_PART} has no loader/entries, so it is not the boot
    partition. Check the layout with:  fdisk -l ${LOOP}"
[[ -d "${ESP_MNT}/EFI" ]] \
    || die "partition ${ESP_PART} has no EFI directory, so it is not the ESP.
    Check the layout with:  fdisk -l ${LOOP}"

# ---------------------------------------------------------------------------
# 1. Read the BLS entry the image would have booted
# ---------------------------------------------------------------------------

shopt -s nullglob
ENTRIES=("${BOOT_MNT}/loader/entries"/*.conf)
shopt -u nullglob
(( ${#ENTRIES[@]} > 0 )) || die "no BLS entries in ${BOOT_MNT}/loader/entries"

# ostree numbers the default deployment 1, and glob expansion is sorted, so the
# first entry is the one the machine would boot. A fresh image only ever has one.
ENTRY="${ENTRIES[0]}"
if (( ${#ENTRIES[@]} > 1 )); then
    echo "    ${#ENTRIES[@]} BLS entries found; using the first: $(basename "$ENTRY")"
fi

BLS_LINUX=""
BLS_VERSION=""
BLS_CMDLINE=""
BLS_INITRDS=()

# Pure bash line parsing. A BLS entry is "key value" per line; initrd may appear
# more than once. The \r strip is defensive: nothing should ever write CRLF into
# one of these, but a stray one would end up inside a kernel argument.
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    case "$line" in
        linux[[:space:]]*)   BLS_LINUX="$(trim "${line#linux}")" ;;
        initrd[[:space:]]*)  BLS_INITRDS+=("$(trim "${line#initrd}")") ;;
        options[[:space:]]*) BLS_CMDLINE="$(trim "${line#options}")" ;;
        version[[:space:]]*) BLS_VERSION="$(trim "${line#version}")" ;;
    esac
done < "$ENTRY"

[[ -n "$BLS_LINUX" ]] || die "no 'linux' line in $(basename "$ENTRY")"
[[ -n "$BLS_CMDLINE" ]] || die "no 'options' line in $(basename "$ENTRY")"
(( ${#BLS_INITRDS[@]} > 0 )) || die "no 'initrd' line in $(basename "$ENTRY")"

# BLS paths are relative to the boot partition's root.
KERNEL="${BOOT_MNT}${BLS_LINUX}"
[[ -s "$KERNEL" ]] || die "kernel from the BLS entry is missing or empty: ${BLS_LINUX}"

INITRD_ARGS=()
INITRD_BYTES=0
for rel in "${BLS_INITRDS[@]}"; do
    path="${BOOT_MNT}${rel}"
    [[ -s "$path" ]] || die "initramfs from the BLS entry is missing or empty: ${rel}"
    INITRD_ARGS+=("--initrd=${path}")
    INITRD_BYTES=$(( INITRD_BYTES + $(file_size "$path") ))
done

echo "==> BLS entry $(basename "$ENTRY")"
echo "    kernel    ${BLS_LINUX} ($(mib "$(file_size "$KERNEL")"))"
echo "    initramfs ${BLS_INITRDS[*]} ($(mib "$INITRD_BYTES"))"
echo "    cmdline   ${BLS_CMDLINE}"

# ---------------------------------------------------------------------------
# 2. Build the UKI
# ---------------------------------------------------------------------------

# Brand the UKI itself. The systemd-boot stub embeds an os-release section
# (.osrel) that firmware boot managers and the stub's own console output
# display; without this, ukify falls back to the BUILD HOST's os-release and
# the boot binary introduces itself as the builder's Fedora rather than
# MarwanOS. The image's own identity lives on its root partition, so borrow it
# from there. Best-effort: a UKI with the wrong nameplate still boots.
ROOT_DEV="${LOOP}p${ROOT_PART}"
OSREL=""
if wait_for_part "$ROOT_DEV"; then
    ROOT_MNT="$(mktemp -d)"
    if $SUDO mount -o ro "$ROOT_DEV" "$ROOT_MNT" 2>/dev/null; then
        shopt -s nullglob
        DEPLOYS=("$ROOT_MNT"/ostree/deploy/*/deploy/*.0/usr/lib/os-release)
        shopt -u nullglob
        if (( ${#DEPLOYS[@]} > 0 )) && [[ -r "${DEPLOYS[0]}" ]]; then
            cp "${DEPLOYS[0]}" "${WORK_DIR}/os-release"
            OSREL="${WORK_DIR}/os-release"
            echo "    identity  $(grep '^PRETTY_NAME=' "$OSREL" | cut -d= -f2- | tr -d '"')"
        fi
        $SUDO umount "$ROOT_MNT"
    fi
    rmdir "$ROOT_MNT" 2>/dev/null || true
fi
[[ -n "$OSREL" ]] || echo "    identity  WARNING: could not read the image's os-release; the UKI will carry the build host's"

# EXTRA_KARGS exists for per-stick kernel arguments that belong to the hardware
# rather than the image -- the founding example being a stick whose UAS
# implementation is broken and needs usb-storage.quirks=<VID>:<PID>:u to force
# the bulk-only transport (the Predator's first stick: 346d:5678). Appended
# last so it can also override anything the BLS supplied.
if [[ -n "${EXTRA_KARGS:-}" ]]; then
    echo "    extra     ${EXTRA_KARGS}"
    BLS_CMDLINE="${BLS_CMDLINE} ${EXTRA_KARGS}"
fi

# Via a file rather than an argument: the command line contains '=' and spaces
# and is the one thing here that must survive verbatim -- it carries root=UUID
# and the ostree= deployment path, and there is no bootloader left to supply
# them if they are wrong.
printf '%s\n' "$BLS_CMDLINE" > "${WORK_DIR}/cmdline"

UKI="${WORK_DIR}/BOOTX64.EFI"

UKIFY_ARGS=(build --linux="$KERNEL" "${INITRD_ARGS[@]}"
    --cmdline="@${WORK_DIR}/cmdline"
    --stub="$STUB"
    --output="$UKI")
[[ -n "$BLS_VERSION" ]] && UKIFY_ARGS+=(--uname="$BLS_VERSION")
[[ -n "$OSREL" ]] && UKIFY_ARGS+=(--os-release="@${OSREL}")

echo "==> Building the UKI with ${UKIFY}"
"$UKIFY" "${UKIFY_ARGS[@]}"

[[ -s "$UKI" ]] || die "ukify exited 0 but produced no output at ${UKI}"
UKI_SIZE="$(file_size "$UKI")"

# The UKI embeds the initramfs, so anything smaller than it means ukify wrote
# something that is not what we asked for -- a green exit code is not evidence.
(( UKI_SIZE > INITRD_BYTES )) \
    || die "UKI is $(mib "$UKI_SIZE") but the initramfs alone is $(mib "$INITRD_BYTES").
    ukify did not embed what it was given."

echo "    ${UKI_SIZE} bytes ($(mib "$UKI_SIZE"))"

# ---------------------------------------------------------------------------
# 3. Install it on the ESP
# ---------------------------------------------------------------------------

$SUDO mkdir -p "${ESP_MNT}/EFI/BOOT"

FALLBACK="${ESP_MNT}/EFI/BOOT/BOOTX64.EFI"
# bib puts shim here. Keep it -- it is ~1 MB, it is inert unless the firmware
# loads it, and it is the only copy of what the normal boot path looked like.
# The guard matters on a second run: without it, the UKI written last time would
# be stashed as "the original".
if [[ -f "$FALLBACK" && ! -f "${FALLBACK}.orig" ]]; then
    echo "==> Keeping the original EFI/BOOT/BOOTX64.EFI as BOOTX64.EFI.orig"
    $SUDO mv "$FALLBACK" "${FALLBACK}.orig"
fi

# Anything still sitting at BOOTX64.EFI is a UKI from a previous run, and cp
# will reclaim its blocks. Counting it is what stops a second run failing the
# space check on an ESP that already holds a UKI of the same size.
RECLAIM=0
[[ -f "$FALLBACK" ]] && RECLAIM="$(file_size "$FALLBACK")"

ESP_AVAIL_KB=""
{ read -r _; read -r ESP_AVAIL_KB; } < <(df -k --output=avail "$ESP_MNT")
[[ -n "$ESP_AVAIL_KB" ]] || die "could not read free space on the ESP"
ESP_AVAIL=$(( ESP_AVAIL_KB * 1024 + RECLAIM ))

if (( ESP_AVAIL < UKI_SIZE + ESP_SLACK_BYTES )); then
    die "the ESP has $(mib "$ESP_AVAIL") usable and the UKI needs $(mib "$UKI_SIZE").
    The whole kernel and initramfs live in that one file, so an initramfs that
    grows eventually stops fitting in bib's 500 MB ESP. Trim dracut modules, or
    build the image with a larger ESP."
fi

echo "==> Installing the UKI as EFI/BOOT/BOOTX64.EFI"
$SUDO cp "$UKI" "$FALLBACK"
$SUDO sync

COPIED_SIZE="$($SUDO stat -c '%s' "$FALLBACK")"
(( COPIED_SIZE == UKI_SIZE )) \
    || die "short copy: ${COPIED_SIZE} bytes on the ESP, ${UKI_SIZE} expected.
    The ESP is probably full. The image is now half-written -- fix the space
    problem and run this again."

# ---------------------------------------------------------------------------
# 4. Take GRUB out of the picture
# ---------------------------------------------------------------------------

# Renamed rather than deleted: it stays inspectable, and on a machine where the
# firmware *can* run GRUB it is one mv away from working again. Leaving it in
# place is the risk -- a firmware or an NVRAM entry that prefers the vendor path
# would boot straight back into the GRUB that cannot read this stick.
if [[ -d "${ESP_MNT}/EFI/fedora" && -d "${ESP_MNT}/EFI/fedora-off" ]]; then
    die "both EFI/fedora and EFI/fedora-off exist on the ESP. Sort out by hand
    which one is real before running this again."
elif [[ -d "${ESP_MNT}/EFI/fedora" ]]; then
    echo "==> Renaming EFI/fedora to EFI/fedora-off"
    $SUDO mv "${ESP_MNT}/EFI/fedora" "${ESP_MNT}/EFI/fedora-off"
elif [[ -d "${ESP_MNT}/EFI/fedora-off" ]]; then
    echo "==> EFI/fedora already renamed"
else
    echo "==> No EFI/fedora on this ESP, nothing to disable"
fi

$SUDO sync

cat <<EOF

==> Done
    ${IMAGE}
    UKI $(mib "$UKI_SIZE") at EFI/BOOT/BOOTX64.EFI, kernel ${BLS_VERSION:-unknown}

Write it to the stick with Rufus in DD mode or balenaEtcher. Rename it to .img
first -- neither tool recognises .raw. Secure Boot must be off: the UKI is
unsigned (D7).

This UKI is a copy of the kernel, initramfs and command line as they are today.
A \`bootc upgrade\` on the target rewrites those on the boot partition and the
firmware never reads it, so the stick keeps booting the old one. Rebuild the
image and re-run this script after an upgrade you want the stick to keep.
EOF
