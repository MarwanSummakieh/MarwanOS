#!/usr/bin/env bash
#
# Generate the PC1 boot identity from its first-party source artwork, so the
# committed bitmaps are reproducible rather than mystery binaries.
#
# Produces:
#   os/files/usr/share/plymouth/themes/marwanos/pc1.png        PC1 mark
#   os/files/usr/share/plymouth/themes/marwanos/powered-by.png caption
#   os/files/usr/share/plymouth/themes/marwanos/marwanos.png   original tag
#   os/files/usr/share/plymouth/themes/marwanos/field.png      solid charcoal field
#   os/files/usr/share/plymouth/themes/marwanos/splash.png     final stack preview
#   os/branding/splash.bmp                                     early UKI frame
#
# The composition follows PC1's own boot screen with the current shell palette:
# a charcoal field, the exact heavy PC1 geometry in pale blue, a quiet
# "Powered by" caption, and the owner's original colour MarwanOS tag.
# The static UKI frame carries the PC1
# mark alone. Plymouth starts on the same frame and reveals the two lower
# layers. That avoids a branded frame disappearing during the firmware-to-
# userspace handoff.
#
# Requires ImageMagick 7.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Native Windows ImageMagick also needs the BMP3: filename in Windows form;
# MSYS does not translate a path preceded by an ImageMagick format prefix.
if command -v cygpath >/dev/null; then REPO_ROOT="$(cygpath -m "$REPO_ROOT")"; fi
THEME_DIR="${REPO_ROOT}/os/files/usr/share/plymouth/themes/marwanos"
OUT_PC1="${THEME_DIR}/pc1.png"
OUT_POWERED="${THEME_DIR}/powered-by.png"
OUT_MARWANOS="${THEME_DIR}/marwanos.png"
OUT_FIELD="${THEME_DIR}/field.png"
OUT_PNG="${THEME_DIR}/splash.png"
OUT_BMP="${REPO_ROOT}/os/branding/splash.bmp"
# A lossless TrueType conversion of this same font can be supplied to builds
# whose FreeType lacks WOFF2 support (for example, portable Windows builds).
FONT_FILE="${FONT_FILE:-${REPO_ROOT}/os/branding/fonts/Inter-var-latin.woff2}"
PC1_SOURCE="${REPO_ROOT}/os/branding/pc1-wordmark.svg"
MARWANOS_SOURCE="${REPO_ROOT}/os/branding/MarwanOS.svg"

[ -r "$FONT_FILE" ] || { echo "missing $FONT_FILE" >&2; exit 1; }
[ -r "$PC1_SOURCE" ] || { echo "missing $PC1_SOURCE" >&2; exit 1; }
[ -r "$MARWANOS_SOURCE" ] || { echo "missing $MARWANOS_SOURCE" >&2; exit 1; }

# Keep these in sync with shell/src/tv_theme.gd: TEXT_SECONDARY and BACKGROUND.
# The PC1 source uses PRIMARY; the original MarwanOS art stays
# in full colour.
CAPTION="#B7C7D2"
FIELD="#11161C"

echo "==> PC1 wordmark"
magick -background none "$PC1_SOURCE" -resize 2352x708 -strip "$OUT_PC1"

echo "==> Powered by caption"
# This is the only typeset layer. It uses the exact Inter subset bundled by PC1;
# the copy and the expressive vector artwork above and below it also stay fixed.
magick -background none -font "$FONT_FILE" -pointsize 100 \
    -fill "$CAPTION" "label:Powered by" \
    -bordercolor none -border 8 -strip "$OUT_POWERED"

echo "==> MarwanOS tag"
# Rasterize the vector master at the full output resolution. Rendering at the
# SVG's 419x139 nominal size and then enlarging would blur the vector outlines.
magick -background none -density 288 "$MARWANOS_SOURCE" -resize 1257x417 -strip "$OUT_MARWANOS"

echo "==> background field"
magick -size 1672x941 xc:"$FIELD" -strip "$OUT_FIELD"

echo "==> composed reference frame"
magick "$OUT_FIELD" \
    \( "$OUT_PC1" -resize 936x \) -gravity north -geometry +0+179 -composite \
    \( "$OUT_POWERED" -resize 150x \) -gravity north -geometry +0+505 -composite \
    \( "$OUT_MARWANOS" -resize 502x \) -gravity north -geometry +0+575 -composite \
    -strip "$OUT_PNG"

echo "==> UKI stub bitmap"
# The firmware stub can only show a static BMP. It gets the opening frame: the
# same field and PC1 position that Plymouth inherits, before the lower identity
# layers animate in.
magick "$OUT_FIELD" \
    \( "$OUT_PC1" -resize 936x \) -gravity north -geometry +0+179 -composite \
    -type TrueColor -strip BMP3:"$OUT_BMP"

echo "==> done"
magick identify "$OUT_PC1" "$OUT_POWERED" "$OUT_MARWANOS" "$OUT_FIELD" \
    "$OUT_PNG" "$OUT_BMP"
