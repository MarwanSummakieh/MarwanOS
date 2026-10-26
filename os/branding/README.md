# PC1 boot identity

The boot screen uses the first-party PC1 identity from
[`MarwanSummakieh/PC1`](https://github.com/MarwanSummakieh/PC1): the measured
PC1 wordmark geometry from `console/shell/src/surfaces/boot.js` and the original
MarwanOS tag from `console/shell/vendor/marwanos/MarwanOS.svg`.

`pc1-wordmark.svg` keeps the three filled letter paths editable. `MarwanOS.svg`
is entirely vector: the original graffiti outlines are unchanged, while the
psychedelic colour field and its transparency use continuous SVG gradients.
There are no embedded bitmaps, fonts, or external assets. The owner's original
soft paint texture is preserved; conversion cannot recover detail absent from
the original raster paint layer. Both marks are first-party artwork.

`reference/MarwanOS-source.svg` preserves the original hybrid export from the
owner's PSD for comparison and reproducibility. To rebuild the vector master,
run `python scripts/vectorize-marwanos.py` (requires Pillow and NumPy). The
gradient stops preserve source colours within 0.1 on their 8-bit channel scale.
The recreated SVG was compared at 419×139, 1257×417, and 3352×1112 pixels on
black, grey, and white backgrounds; the largest whole-frame mean absolute
channel difference was 0.23 out of 255 in the librsvg renderer. An additional
Edge browser comparison at 1257×417 measured 0.34 out of 255 on grey. It is
visually matched, with small renderer differences rather than a claim of
bit-for-bit equality.

`fonts/Inter-var-latin.woff2` and `fonts/Inter-OFL.txt` are the same font asset
and license shipped by PC1. Inter is used only for the “Powered by” caption.

Run `scripts/make-splash.sh` with ImageMagick 7 to regenerate
the Plymouth PNGs and the static UKI bitmap. The firmware frame shows PC1 on
the charcoal field. Plymouth holds that mark and reveals “Powered by” and MarwanOS
while the OS and shell finish starting.

The boot palette follows `shell/src/tv_theme.gd`: solid charcoal `BACKGROUND`
(`#11161C`), pale-blue `PRIMARY` PC1 lettering (`#BCD9EC`) and
`TEXT_SECONDARY` caption (`#B7C7D2`). The PC1 path
geometry, layout and reveal timing are unchanged, and the original full-colour
MarwanOS artwork is preserved.

Linux/WSL can use the bundled WOFF2 directly. Git Bash is also supported; if
the renderer's FreeType lacks WOFF2 support, use FontTools with its WOFF
dependencies to convert the same font to TrueType, then set `FONT_FILE` to
that `.ttf` when running the script. This changes the container format rather
than the font design.
