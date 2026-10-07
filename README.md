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
- The unified game library prioritizes Playnite-style ease of use, automatic
  metadata, persistent play history, controller features and achievements.
- Bluetooth pairing is required; hardware validation is waiting for the Bluetooth
  dongle. An integrated Flathub store is outside the product scope.
- Boot, application handoff, and recovery remain inside the console experience.

See the [current roadmap](docs/roadmap.md) for priorities, dependencies and
remaining hardware acceptance. Tekken installation, metadata/cache verification
and user-confirmed physical controller gameplay completed on 2026-10-06;
the final candidate's actual Metadata Refresh and image-owned reboot preserve
its native input profile, artwork and history. Genuine achievements now pass
end to end, including a passive gameplay toast and persistent 2/47 progress.
Candidate10 passed its initial PC1 compositor/postboot gates and offline VM
installation, but later normal compositor exit reproduces an NVIDIA fault;
release validation fails for that candidate. Candidate11's targeted cleanup is
now published and verified on real PC1 NVIDIA hardware: idle and postgame normal
SIGTERM, full reboot shutdown, and final compositor/postboot gates pass without
a compositor fault. Its build passes 214 backend tests with two optional skips
and the shell suites; all 11 focused ELF regressions pass. Candidate11 raw media
and its branded offline ISO are built and checksum-verified; fresh installation
and broader release acceptance remain open. See the
[candidate11 evidence](docs/candidate11-teardown-acceptance-20261007.md) and
[status checkpoint](docs/status-2026-10-07.md).
The latest source checkpoint adds NVIDIA Xorg display selection and automatic
175 Hz startup, native virtual-controller hotplug and hardware identities,
Steam Input recapture protection, and duplicate Steam-card merging. The owner
confirmed smooth Steam display and Silksong menu controls on PC1. These changes
still need a replacement image and full reboot validation. Current source
validation passes 248 backend tests with two optional skips; see the
[display investigation](docs/steam-display-corruption-20261007.md).
Nine tracked tasks remain. The owner has requested physical acceptance; the
[session record](docs/physical-acceptance-20261007.md) tracks pending observations.
Only one physical controller is available and there is no Bluetooth adapter, so
two-pad and Bluetooth checks await hardware. Sleep testing remains deferred.
Candidate10's passing installer-media evidence is scoped to its VM.

Development is organized through the [PC1 GitHub Project](https://github.com/users/MarwanSummakieh/projects/3)
and [six repositories](docs/repositories.md), with pinned component copies in
this OS integration repository.

## Current implementation

This is a bootable development distro. The current build runs in a UEFI VM
with its integrated browser, Files, controller input and Windows application
lifecycle verified. Physical NVIDIA/controller/TV acceptance remains necessary.
See the [current teardown acceptance](docs/candidate11-teardown-acceptance-20261007.md)
and [detailed acceptance record](docs/acceptance-20261006.md) for software,
bench and candidate-image evidence, and the [earlier media record](docs/acceptance-2026-10-05.md)
for dated VM/USB artifact details. Historical observations in
other documents describe their dated builds.

| Area | State |
|---|---|
| OS | Fedora 43 / Universal Blue bootc image, pinned NVIDIA open-module sidecar, Plymouth splash, accelerated Xorg/Openbox on connected NVIDIA displays and VMs, gamescope on other GPUs; see [ADR 0013](docs/adr/0013-nvidia-xorg-display.md) |
| Shell | Godot 4.7.1, controller navigation, library rail, app overlay, compact movable keyboard with saved position, settings, Wi-Fi, updates, power and diagnostics |
| Controller ownership | Exclusive Linux input broker, four remembered player slots with virtual devices only for attached pads, hardware model identities, native virtual-device hotplug, Linux rumble forwarding, Steam Input recapture protection, all-pad Home/Share and gated game input; physical Tekken hotplug/rumble and two-pad acceptance pending; see [controller routing](docs/controller-routing.md) |
| Library | Desktop applications, Steam libraries, standalone Windows executables and managed umu apps; automatic Steam Store metadata/artwork with persistent offline cache, a Play-only details page and separate Options → Metadata refresh/match page; see [metadata evidence](docs/game-metadata.md) |
| History and achievements | Persistent actual foreground sessions, totals and recent sorting; per-profile local/Steam achievement providers, automatic keyless Steam catalogs, progress, offline viewing and first-sync-safe unlock notifications. Unsupported schemas/profiles stay explicit; see [achievements](docs/achievements.md) |
| Bluetooth | Controller pairing page, BlueZ agent, codes/confirmation, trust/removal/reconnect; actual dongle acceptance pending; see [Bluetooth](docs/bluetooth.md) |
| Download automation | Browser/FDM completion receipts, controller setup and explicit game/app input profiles; confirmed successful setup-file cleanup, with torrent/multipart retention; see [download flow](docs/download-install-flow.md) |
| Windows installation | EXE/MSI setup from Files, portable apps, explicit program selection, launch, minimize/resume, close and confirmed managed-prefix removal. The final image's service and first-use runtime passed the real 7-Zip lifecycle; see [the contract and validation](docs/windows-installation.md) |
| Steam | Native client preferred, legacy Flatpak fallback, shared launch/stop helper and controller routing; account/game compatibility requires target validation |
| Browser and files | Embedded Chromium with tabs, history/bookmarks, downloads, controller file uploads and web dialogs; Files search/path/history, split view, previews, cancellable copy/move, rename, trash and restore. See [built-in tools](docs/built-in-tools.md). |
| Verification | Candidate11 passes NVIDIA normal shutdown/reboot and final compositor/postboot gates. Its raw media and branded ISO are built and checksum-verified; fresh offline installation and USB-absent boot remain pending. Latest source passes 248 backend tests with two optional skips, controller shell checks and component-pin verification; 37 controller policy checks and the real Linux uinput fixture pass. The latest display/controller changes are not baked into candidate11. Candidate10 remains release FAIL despite its separate 15/15 VM installation pass. Broader physical acceptance remains open. |

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
