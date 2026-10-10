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
  interactively, then identifiable programs appear on home automatically;
  ambiguous or interrupted installs offer program selection in Downloads.
- Steam remains a supported source of games. PC1 must retain its home/overlay
  controls instead of surrendering the experience to Steam's interface.
- An integrated browser and file manager are required product features.
- The unified game library prioritizes Playnite-style ease of use, automatic
  metadata, persistent play history, controller features and achievements.
- Bluetooth pairing is required; sustained two-pad hardware acceptance remains
  open. An integrated Flathub store is outside the product scope.
- Boot, application handoff, and recovery remain inside the console experience.

The October 10 release candidate consolidates the console UI, embedded browser,
native Downloads, controller recovery/latency/battery, display-only Rest,
managed Windows installation and local-user work. Component exports are
checkpointed in their owning repositories and pinned by exact commit and blob.
See [the candidate record](docs/release-candidate-20261010.md) for source identity,
checks, image provenance and remaining acceptance.

Candidate13 is the accepted base: its PC1 reboot and offline controller-operated
VM installation, USB-absent boot and installed reboot passed. Later bench/source
changes require their own candidate acceptance. PC1 now has two wireless
DualSense controllers and a UGREEN Bluetooth adapter. Display-only Rest and
wireless PS wake have physical confirmation; true system-suspend wake does not.

Development is organized through the [PC1 GitHub Project](https://github.com/users/MarwanSummakieh/projects/3)
and [six repositories](docs/repositories.md), with pinned component copies in
this OS integration repository.

## Current implementation

This is a bootable development distro. Candidate13 has verified UEFI VM
installation and PC1 reboot evidence. The October 10 candidate has its own
source checks and image build; fresh-image boot and physical acceptance remain
necessary. See [the candidate record](docs/release-candidate-20261010.md) for
current results. The [candidate11 teardown](docs/candidate11-teardown-acceptance-20261007.md),
[earlier acceptance record](docs/acceptance-20261006.md) and
[media record](docs/acceptance-2026-10-05.md) describe their dated builds.

| Area | State |
|---|---|
| OS | Fedora 43 / Universal Blue bootc image, pinned NVIDIA open-module sidecar, Plymouth splash, accelerated Xorg/Openbox on connected NVIDIA displays and VMs, gamescope on other GPUs; see [ADR 0013](docs/adr/0013-nvidia-xorg-display.md) |
| Shell | Godot 4.7.1, controller navigation, library rail, app overlay, compact movable keyboard with saved position, settings, Wi-Fi, updates, power and diagnostics |
| Controller ownership | Exclusive Linux input broker, four remembered player slots with virtual devices only for attached pads, hardware model identities, native virtual-device hotplug, Linux rumble forwarding, Steam Input recapture protection, all-pad Home and gated game input; physical Tekken hotplug/rumble and two-pad acceptance pending; see [controller routing](docs/controller-routing.md) |
| Library | Desktop applications, Steam libraries, standalone Windows executables and managed umu apps; automatic Steam Store metadata/artwork with persistent offline cache, continuous Home game actions and Options → Metadata refresh/match; Settings refreshes all games; see [metadata evidence](docs/game-metadata.md) |
| History and achievements | Persistent actual foreground sessions, totals and recent sorting; per-profile local/Steam achievement providers, automatic keyless Steam catalogs, progress, offline viewing and first-sync-safe unlock notifications. Unsupported schemas/profiles stay explicit; see [achievements](docs/achievements.md) |
| Bluetooth | Controller pairing page, BlueZ agent, codes/confirmation, trust/removal/reconnect; actual dongle acceptance pending; see [Bluetooth](docs/bluetooth.md) |
| Downloads | Native shell queue for HTTP/HTTPS, torrents and browser progress, persistent Linux transfer service, pause/resume, file selection and installer receipts; source integration, target acceptance pending. See [native Downloads](docs/native-downloads.md) and [download flow](docs/download-install-flow.md). |
| Windows installation | EXE/MSI setup from Files, portable apps, explicit program selection, launch, minimize/resume, close and confirmed managed-prefix removal. The final image's service and first-use runtime passed the real 7-Zip lifecycle; see [the contract and validation](docs/windows-installation.md) |
| Steam | Native client preferred, legacy Flatpak fallback, shared launch/stop helper and controller routing; account/game compatibility requires target validation |
| Browser and files | Embedded Chromium with tabs, history/bookmarks, downloads, controller file uploads and web dialogs; Files search/path/history, split view, previews, cancellable copy/move, rename, trash and restore. See [built-in tools](docs/built-in-tools.md). |
| Verification | Candidate13 PC1 reboot and offline VM installation/USB-absent boot pass. The October 10 candidate consolidates subsequent source and bench work; see its candidate record for current checks, image identity and acceptance limits. |

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

# Controller, Files, keyboard and lifecycle regressions (pinned editor):
bash scripts/check-shell.sh
python3 -m unittest discover -s tests -v

# Export and exercise the shell against a locally built runtime image:
./scripts/xvfb-shell-verify.sh
```

See [shell/README.md](shell/README.md) for shell structure and verification.
Image publication and USB flashing are separate operations; inspect the relevant
script and target before using them.

## Documentation status

This README and the [current roadmap](docs/roadmap.md) describe the current product
direction. The phase plans, Steam
client contract, and handoff notes record earlier iterations, including removed
features. In particular, “a console has no browser” and removing Steam entirely
are not the current requirements. Proposed shell replacement or Steam removal
documents are not implementation instructions for this milestone.
