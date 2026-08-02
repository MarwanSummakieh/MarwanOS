# ADR 0002 — NVIDIA baseline is Turing+, and the base image changes accordingly

**Status:** Accepted
**Date:** 2026-08-02
**Supersedes:** the base-image half of D1 in [phase-0-plan.md](../phase-0-plan.md)

## Context

Two of Phase 0's open questions were "which GPU generation" and "which base
image". They turned out to be the same question, because upstream answered both.

**The driver floor moved.** NVIDIA's 580 branch was the last to support Maxwell,
Pascal and Volta; the 590 branch dropped them to a frozen legacy driver. Separately,
the open kernel modules have always required Turing or newer, because they depend
on the GSP coprocessor that Turing introduced. As of 590 those two lines converged:
current drivers are Turing-and-newer, and open modules are the default path
everywhere. Pascal is not a "works but slower" option, it is a dead end that
receives no new driver work.

**The base image we planned to use is abandoned.** D1 named
`ghcr.io/ublue-os/base-nvidia`. Its newest real tags are from early 2023. Universal
Blue restructured: NVIDIA is no longer a prebuilt base variant, it is prebuilt
akmods RPMs you copy into a minimal base from a sidecar image.

## Decision

**Baseline: Turing (RTX 20 / GTX 16) or newer, using `nvidia-open`.** This is the
floor MarwanOS targets and tests. It is not a preference; below it there is no
supported driver.

**Base: `ghcr.io/ublue-os/base-main:43` + `ghcr.io/ublue-os/akmods-nvidia-open:main-43`,**
both pinned by digest, bumped together by `scripts/bump-base.sh`.

We considered basing on `ghcr.io/ublue-os/bazzite-deck-nvidia` instead, which is
actively maintained and already ships a working `gamescope-session` on NVIDIA.
Rejected: it brings a full KDE desktop, Steam, and a desktop-mode switch — which
is a pile of exactly the escape hatches D6 and M4 exist to eliminate. Subtracting
a desktop from a bootc base is far more fragile than not adding one. We take
bazzite's *knowledge* instead of its image; see the M1 note below.

## Consequences

- We keep D1's actual principle — never compile an NVIDIA module ourselves. The
  akmods RPMs are prebuilt upstream; we only install them.
- The base and akmods tags are coupled (`43` ↔ `main-43`). A mismatch builds
  cleanly and boots to a black screen, so `bump-base.sh` hard-fails on it.
- The image must regenerate its initramfs after installing the kmod, or plymouth
  has no NVIDIA driver in early boot. That is an M2 problem we would rather not
  discover in M2, so the Containerfile does it now.
- **The RTX 3060 Laptop in the Predator is Ampere — comfortably above the floor.**
  No hardware purchase is required to start, and none should be made until M1
  has produced a compositor decision.
- If a dedicated box is bought later, "most performant" means Blackwell (RTX 50)
  and Ada (RTX 40) is the lower-risk pick with more driver history behind it.
  Either satisfies the baseline; neither changes a line of this repo, which is
  the point of pinning to an architecture floor rather than a specific card.

## Note for M1

The gamescope-on-NVIDIA spike is no longer open-ended research. `gamescope-session`
is reported working as a DRM-master session on NVIDIA (RTX 4060, driver 565.77),
and `bazzite-deck-nvidia` ships it. The spike's job is now **porting a known-good
configuration into a minimal image**, not discovering whether the thing is possible.
Read `bazzite-org/gamescope-session` and the bazzite COPR packaging first; budget
the 3 days against integration, and keep cage as plan B for the same reasons.
