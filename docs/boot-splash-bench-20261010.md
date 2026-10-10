# Boot splash — PC1, 10 October 2026

The PC1 bench at `192.168.50.206` has the updated splash installed for its next
boot: solid charcoal `#11161C`, pale-blue `#BCD9EC` PC1 lettering and the
original full-colour MarwanOS artwork below “Powered by”. Background lines
have been removed. The PC1 geometry, typography, layout and reveal timing
are preserved. The MarwanOS SVG and PNG are byte-for-byte unchanged.

The bench uses the immutable bootc image and BIOS GRUB. A reversible
`marwanos-splash-bench.service` binds the updated theme read-only over
`/usr/share/plymouth/themes/marwanos`. Its source assets, deployment receipts
and rollback helper are in `/var/marwanos/boot-splash-20261010`.

The active deployment's BLS entry `/boot/loader.0/entries/ostree-2.conf` points
to a separately built `initramfs-7.1.5-101.fc43.x86_64-splash-20261010-solid.img`
in its existing `/boot/ostree/default-f7c79bfdfb1364d735059acab2b742ba69c75ff9f1955ffc9cce44cf14c04721/`
directory. The original initramfs and rollback deployment's entry remain
unchanged. The bench's BIOS boot does not use the UKI BMP; that updated solid
frame is also stored with the deployed assets for media builds.

Verification:

- All seven live theme files and the same files extracted from the new
  initramfs match the uploaded SHA-256 manifest.
- The background contains exactly one colour. The original MarwanOS PNG
  retains SHA-256 `5f6b915b15be53fa20c491b522009a3363fcb90df781d0671b71f20bc4d59dc2`.
- The new initramfs is 244,750,459 bytes, below the image's 262,144,000-byte
  boot budget. It contains OSTree, NVIDIA and USB-storage support; nouveau
  remains excluded.
- New initramfs SHA-256:
  `b29df034c6fe4be7d88c591ce78aef0b9598e0d630815d229ec9873949463547`.
- The splash service is active and enabled. The bench has no failed system
  units. Its GRUB environment has no alternate saved entry.

No reboot was performed. Physical boot appearance and the splash-to-shell
handoff still need observation on the next boot. This is a bench override;
the corresponding source assets are updated for the next OS image build.

To restore the original splash without rebooting immediately, run as root on
the bench:

```sh
bash /var/marwanos/boot-splash-20261010/rollback.sh
```

Local deployment evidence is in `out/splash-scheme-20261010/bench-deployment.json`.
