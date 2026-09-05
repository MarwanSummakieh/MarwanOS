# PC1 boot identity

The boot screen uses the first-party PC1 identity from
[`MarwanSummakieh/PC1`](https://github.com/MarwanSummakieh/PC1): the measured
PC1 wordmark geometry from `console/shell/src/surfaces/boot.js` and the original
MarwanOS tag from `console/shell/vendor/marwanos/MarwanOS.svg`.

`pc1-wordmark.svg` keeps the three filled letter paths editable. `MarwanOS.svg`
is copied without visual changes; it is a hybrid vector/raster export from the
owner's original PSD. Both are first-party artwork.

`fonts/Inter-var-latin.woff2` and `fonts/Inter-OFL.txt` are the same font asset
and license shipped by PC1. Inter is used only for the “Powered by” caption.

Run `scripts/make-splash.sh` from Linux or WSL with ImageMagick 7 to regenerate
the Plymouth PNGs and the static UKI bitmap. The firmware frame shows PC1 on
the pale field. Plymouth holds that mark and reveals “Powered by” and MarwanOS
while the OS and shell finish starting.
