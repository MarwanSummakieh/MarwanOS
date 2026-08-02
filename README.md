# MarwanOS

A Fedora-based, image-mode Linux distribution that boots straight into a
controller-navigable gaming shell. No desktop, no login screen, no terminal, no
visible text between the vendor logo and the shell.

Built on [bootc](https://containers.github.io/bootc/) and Universal Blue: the OS
is a container image, and every change ships as `bootc upgrade` with
`bootc rollback` as the undo.

## Where things are

| Path | What |
|------|------|
| [`os/Containerfile`](os/Containerfile) | The OS image |
| [`os/files/`](os/files/) | Files copied into the image root |
| [`scripts/`](scripts/) | Build, push, base bump, installer media |
| [`docs/phase-0-plan.md`](docs/phase-0-plan.md) | Current phase: milestones, decisions, gates |
| [`docs/dev-setup.md`](docs/dev-setup.md) | **Start here.** Machines, toolchain, the loop |
| [`docs/adr/`](docs/adr/) | Decisions that are settled and not relitigated |

## Status

**Phase 0, M0 — the factory.** Scaffolded, not yet run. Nothing is verified until
a build has succeeded and a change has been deployed and rolled back on a real
target.

Phase 0 ends when the machine cold-boots to a gamepad-navigable grid in under 15
seconds with zero frames of text on camera, and a bad build can be undone with
one command. Everything after that is features.

## Baseline

NVIDIA, Turing (RTX 20 / GTX 16) or newer, on the open kernel modules. This is a
floor rather than a preference — NVIDIA's 590 driver branch dropped Pascal and
older, and the open modules require the GSP coprocessor that Turing introduced.
See [ADR 0002](docs/adr/0002-nvidia-baseline-and-base-image.md).

## Quick start

Read [`docs/dev-setup.md`](docs/dev-setup.md) first — this only works from a
configured build host.

```bash
GHCR_USER=marwansummakieh ./scripts/build-push.sh
```
