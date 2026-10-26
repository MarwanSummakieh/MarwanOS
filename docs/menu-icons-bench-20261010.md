# System-menu icons on PC1 — 2026-10-10

Removed the captions underneath system-menu icons in `shell/src/console_button.gd`.
Icons remain centered, and button tooltips and accessible names retain their
destination names. Existing focus outlines and navigation behavior are preserved.

The bench export was built from the verified source archive matching its live
binary, with only this script changed. Godot import, existing design checks,
wide/narrow software-rendered previews and the exported-binary startup check
passed. The live 3440×1440 screen was inspected with the dock open; the icons
have no captions and Home has a visible focus outline. Guide closed the dock
after verification.

Deployment manifest:
`/var/marwanos/console-design-20261009/icon-labels-deployment-20261010.json`.
Source archive: `/var/tmp/pc1-menu-labels-20261010/source.tar.gz`.

Binary SHA-256:
`7c696edfd3a979416e56087a163d62b14cb830602ea5ac268643c99d8530a602`.
Source SHA-256:
`9e8a76e418c3cef01a9d093a320012343788237c844bc99c7f180ad99cee090d`.

The previous binary is retained at
`/var/marwanos/console-design-20261009/marwanos-shell.before-icon-labels-20261010`.
The controller broker was not restarted; the input-latency repair is preserved.
