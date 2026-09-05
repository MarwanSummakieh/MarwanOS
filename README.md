# PC1 / MarwanOS

PC1 is a console experience on PC hardware: boot into a custom Linux shell,
install and play games, browse the web, and manage files using **only a
controller**. MarwanOS is the operating-system image and Godot shell in this
repository. The product aims for the continuity of a PS5 experience; it is not
affiliated with Sony.

## Product requirements

- Every supported flow works without a keyboard or mouse, including sign-in,
  text entry, errors, cancellation, and recovery.
- Windows applications install through a managed compatibility runtime and
  appear in the library. Prefixes are managed automatically; ordinary EXE/MSI
  setup wizards use the controller pointer and on-screen keyboard.
- Known recipes can install unattended in the background. Other installers run
  interactively, followed by explicit selection of the installed program.
- Steam remains a supported source of games. PC1 must retain its home/overlay
  controls instead of surrendering the experience to Steam's interface.
- An integrated browser and file manager are required product features.
- Boot, application handoff, and recovery remain inside the console experience.

## Current implementation

This is an integrated prototype, not a finished console. The root README's
former “scaffolded, not yet run” status was obsolete. Historical development
and hardware observations live in `docs/`; they are not proof that every current
build passes the same checks.

| Area | State |
|---|---|
| OS | Fedora 43 / Universal Blue bootc image, pinned NVIDIA open-module sidecar, Plymouth splash, greetd session supervision |
| Shell | Godot 4.7.1, controller navigation, library rail, app overlay, on-screen keyboard, settings, Wi-Fi, updates, power and diagnostics |
| Library | Desktop application discovery, legacy Steam manifest discovery, standalone Windows executable discovery and umu launch wrapper |
| Windows installation | General EXE/MSI setup from Files, portable apps, program selection and library launch through umu; optional automatic 7-Zip recipe. Compatibility and hardware validation remain limited; see [the contract and validation](docs/windows-installation.md) |
| Steam | Image/session integration exists, but input ownership and native-versus-Flatpak integration need further work |
| Browser and files | Native file explorer with copy/move, rename, trash, split view and previews; embedded Chromium browser with controller navigation, address/search entry and on-screen typing. See [built-in tools](docs/built-in-tools.md). |
| Verification | Worker regression tests, controller-event shell checks, exported-shell smoke run and Xvfb inspection; real controller/TV validation still required |

## Architecture

The Godot shell owns navigation and presentation. Linux helpers perform system
operations and publish state files; the shell sends explicit requests and renders
the answers. The session supervises the compositor and shell. Application
launches pass through `shell/src/launcher.gd` so the library and overlay share
one lifecycle.

The OS ships as a container image. `bootc upgrade` stages an OS update and
`bootc rollback` selects the previous deployment. Application installs and user
data persist separately under `/var` and the player's home; OS rollback does
not undo those files.

| Path | Purpose |
|---|---|
| [os/Containerfile](os/Containerfile) | OS packages, pinned build inputs, shell export and image assertions |
| [os/files/](os/files/) | Helpers, systemd units, boot configuration and image-owned resources |
| [shell/](shell/) | Godot project and controller UI |
| [scripts/](scripts/) | Build, installer media, development and verification tooling |
| [docs/dev-setup.md](docs/dev-setup.md) | Existing build-host and hardware development setup |
| [docs/adr/](docs/adr/) | Historical architectural decisions; newer product requirements can supersede their scope |

## Development

The production target is x86-64 Linux with NVIDIA Turing or newer using the
pinned open-module stack. Linux/WSL with Podman is the build environment. Keep
the Godot editor and export templates aligned with `GODOT_VERSION` in the
Containerfile. Do not update the base/driver pair casually: the existing hardware
regression investigation is in [docs/flicker-nvidia-610.md](docs/flicker-nvidia-610.md).

```bash
# From a configured Linux/WSL build host, at the repository root:
./scripts/build-push.sh --no-push

# Export and exercise the shell against a locally built runtime image:
./scripts/xvfb-shell-verify.sh
```

See [shell/README.md](shell/README.md) for shell structure and verification.
Image publication and USB flashing are separate operations; inspect the relevant
script and target before using them.

## Documentation status

This README describes the current product direction. The phase plans, Steam
client contract, and handoff notes record earlier iterations, including removed
features. In particular, “a console has no browser” and removing Steam entirely
are not the current requirements. Proposed shell replacement or Steam removal
documents are not implementation instructions for this milestone.
