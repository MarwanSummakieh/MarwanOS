#!/usr/bin/env bash
#
# Generate the boot splash artwork from a recipe, so the committed bitmaps are
# reproducible rather than mystery binaries.
#
# Produces:
#   os/files/usr/share/plymouth/themes/marwanos/splash.png   wordmark, TRANSPARENT
#   os/files/usr/share/plymouth/themes/marwanos/spinner.png  ring the script rotates
#   os/branding/splash.bmp                                   wordmark ON BLACK, for the UKI stub
#
# THE LOOK IS PLAIN, on purpose. An earlier version drew each letter tilted with
# outlines, drips and splatter -- a graffiti tag. The owner asked for that to be
# replaced with just the comic font, so this is the wordmark set once in Comic
# Neue Bold, near-white, on a transparent ground. No field, no rectangle, no
# per-letter theatrics. The one moving thing is the spinner, drawn separately
# and rotated by the plymouth script.
#
# The font is vendored at os/branding/fonts/ComicNeue-Bold.ttf (SIL OFL, hash in
# that directory) rather than assumed present: the build container ships no
# comic face, so relying on fontconfig to find one would render a different
# font on the machine that has one and a fallback on the one that does not.
#
# Requires ImageMagick 7.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_PNG="${REPO_ROOT}/os/files/usr/share/plymouth/themes/marwanos/splash.png"
OUT_SPINNER="${REPO_ROOT}/os/files/usr/share/plymouth/themes/marwanos/spinner.png"
OUT_BMP="${REPO_ROOT}/os/branding/splash.bmp"
FONT_FILE="${REPO_ROOT}/os/branding/fonts/ComicNeue-Bold.ttf"

[ -r "$FONT_FILE" ] || { echo "missing $FONT_FILE" >&2; exit 1; }

POINT=300
FILL="#E8EAEE"      # FOCUS_RING, near-white -- matches the shell's own text
ACCENT="#EBB05C"    # TEXT_ALERT amber -- the spinner, the one accent

echo "==> wordmark"
# Passing the ttf by PATH via -font, so the vendored file is used regardless of
# whether fontconfig knows about it. A subtle drop shadow lifts near-white off
# black without the outline/drip machinery the old version had.
magick -background none -font "$FONT_FILE" -pointsize "$POINT" \
    -fill "$FILL" "label:MarwanOS" \
    \( +clone -background "#000000" -shadow 55x10+0+8 \) \
    +swap -background none -layers merge +repage \
    -bordercolor none -border 40 "$OUT_PNG"

echo "==> spinner"
# A 300-degree amber arc; the plymouth script rotates it. The gap is what makes
# the rotation visible.
magick -size 120x120 xc:none \
    -stroke "$ACCENT" -strokewidth 10 -fill none \
    -draw "arc 12,12 108,108 0,300" \
    "$OUT_SPINNER"

echo "==> UKI stub bitmap (flattened onto black)"
# The systemd-boot stub renders BMP only, and BMP has no alpha, so black is
# baked in -- which is also the point: the field IS black.
magick -size 1672x941 xc:black \
    \( "$OUT_PNG" -resize 1200x \) -gravity center -composite \
    -type TrueColor BMP3:"$OUT_BMP"

echo "==> done"
magick identify "$OUT_PNG" "$OUT_SPINNER" "$OUT_BMP"
