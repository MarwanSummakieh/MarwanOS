# Candidate11 offline media — October 7, 2026

Fresh raw USB media and a branded offline installer ISO were built from the
candidate11 image that passed the [PC1 teardown checks](candidate11-teardown-acceptance-20261007.md).
Offline installation and installed-disk boot acceptance for these new artifacts
remain pending; candidate10's VM acceptance does not transfer to them.

## Provenance

- OS source: `cc199319111e0fe7e52f558b2f04b8cfb7dbd53e`.
- Image: `ghcr.io/marwansummakieh/marwanos@sha256:a271f2ba2dedab79a5405c86e3a356dd4673208be468ec6a0afe62885623806b`.
- Builder: `quay.io/centos-bootc/bootc-image-builder@sha256:2b52843ea2bfda73b0a08d97e76b734393b1d3a804681b9fabb26723bd3a2f0b`.
- Clean isolated branding/source checkout: `/var/tmp/pc1-release-source-cc19931`.
- Build output in FedoraLinux-43 WSL: `/var/tmp/pc1-release-20261007-candidate11`.

The builder checked the image's baked source identity before building. Both raw
and Anaconda manifests use the exact digest-only image origin. The raw disk was
then prepared with the existing UKI USB boot helper; the installer was remastered
with the matching committed PC1 artwork and interactive setup policy. No new OS
image was published, and no physical USB was written. Concurrent controller
changes in the main working tree are not part of these candidate11 artifacts.

## Final artifacts

Paths below are relative to the WSL build output directory.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `raw/image/disk.raw` (UKI prepared) | 21,378,367,488 | `e422928c6f08b055b6e4704ac763f4db8feb2db8f19f0311c40428cc6d5f7f9e` |
| `iso/bootiso/install.iso` (source installer) | 6,000,252,928 | `1d788793d14b765e5e6c85e29035e23c4d176d98592d0006e3e81a784b1bd07c` |
| `pc1-final.iso` (branded offline installer) | 6,004,473,856 | `213fe6fdfb7e0fd158981092b1878a3949945f3d7f855d4728c993d85df8f78f` |

All three checksums are retained in
`out/release-20261007-candidate11/SHA256SUMS`.

The Windows installer copy is
`C:\Users\brain\Documents\repos\MarwanOS\out\release-20261007-candidate11\MarwanOS-candidate11.iso`,
with adjacent `MarwanOS-candidate11.iso.sha256`. The large media files and local
build evidence are intentionally ignored by Git; this record preserves the
final hashes in the pushed repository.

## Packaging checks and limits

Eight shutdown-verifier regressions and nine installer policy/controller
regressions pass. Both media builds completed successfully. The branded ISO's
GPT/appended EFI comparison and refreshed embedded media checksum pass.
Recomputed final SHA-256 hashes match the build record, and the raw disk's GPT
verification reports no problems. Runtime directory read/traverse permissions
pass, and the full Windows ISO copy's SHA-256 matches the branded ISO above.

Retained provenance includes the full build log, source/image/builder references,
both osbuild manifests, artifact sizes, checksums, boot records and
`media-summary.json` under `out/release-20261007-candidate11`.

The next acceptance step is an actual offline controller installation onto a
disposable VM disk, followed by a USB-absent boot and exact source/digest health
checks. Physical USB and broader release acceptance remain open. Suspend testing
remains separately deferred.
