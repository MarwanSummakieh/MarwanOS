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
release validation fails. Candidate11's targeted cleanup passes 11 ELF regressions
and exact SHA-pinned SRPM preparation with zero fuzz; production build and baked
normal-exit/reboot acceptance remain pending.
Nine tracked tasks remain. Bluetooth reports the missing dongle correctly;
physical checks and sleep testing are deferred under the owner's automated-only
instruction. Candidate10's passing installer-media evidence is scoped to its VM.

Development is organized through the [PC1 GitHub Project](https://github.com/users/MarwanSummakieh/projects/3)
and [six repositories](docs/repositories.md), with pinned component copies in
this OS integration repository.

## Current implementation

This is a bootable development distro. The current build runs in a UEFI VM
with its integrated browser, Files, controller input and Windows application
lifecycle verified. Physical NVIDIA/controller/TV acceptance remains necessary.
See the [current acceptance record](docs/acceptance-20261006.md) for software,
bench and candidate-image evidence, and the [earlier media record](docs/acceptance-2026-10-05.md)
for dated VM/USB artifact details. Historical observations in
other documents describe their dated builds.

| Area | State |
|---|---|
| OS | Fedora 43 / Universal Blue bootc image, pinned NVIDIA open-module sidecar, Plymouth splash, supervised gamescope session and Xorg/Openbox compatibility session for VMs |
| Shell | Godot 4.7.1, controller navigation, library rail, app overlay, compact movable keyboard with saved position, settings, Wi-Fi, updates, power and diagnostics |
| Controller ownership | Exclusive Linux input broker, four stable player slots, Linux rumble forwarding, all-pad Home/Share, gated game input and neutral handoff/disconnect; physical rumble/two-pad acceptance pending; see [controller routing](docs/controller-routing.md) |
| Library | Desktop applications, Steam libraries, standalone Windows executables and managed umu apps; automatic Steam Store metadata/artwork with persistent offline cache, a Play-only details page and separate Options → Metadata refresh/match page; see [metadata evidence](docs/game-metadata.md) |
| History and achievements | Persistent actual foreground sessions, totals and recent sorting; per-profile local/Steam achievement providers, automatic keyless Steam catalogs, progress, offline viewing and first-sync-safe unlock notifications. Unsupported schemas/profiles stay explicit; see [achievements](docs/achievements.md) |
| Bluetooth | Controller pairing page, BlueZ agent, codes/confirmation, trust/removal/reconnect; actual dongle acceptance pending; see [Bluetooth](docs/bluetooth.md) |
| Download automation | Browser/FDM completion receipts, controller setup and explicit game/app input profiles; confirmed successful setup-file cleanup, with torrent/multipart retention; see [download flow](docs/download-install-flow.md) |
| Windows installation | EXE/MSI setup from Files, portable apps, explicit program selection, launch, minimize/resume, close and confirmed managed-prefix removal. The final image's service and first-use runtime passed the real 7-Zip lifecycle; see [the contract and validation](docs/windows-installation.md) |
| Steam | Native client preferred, legacy Flatpak fallback, shared launch/stop helper and controller routing; account/game compatibility requires target validation |
| Browser and files | Embedded Chromium with tabs, history/bookmarks, downloads, controller file uploads and web dialogs; Files search/path/history, split view, previews, cancellable copy/move, rename, trash and restore. See [built-in tools](docs/built-in-tools.md). |
| Verification | Candidate10 runs 215 backend tests: 213 pass and two optional checks skip; integrated shell suites, real uinput multiplayer/rumble and Win32 setup-exit fixtures pass. Its initial PC1 compositor/postboot gates, full-journal Enforcing audit and normal updater execution pass, but subsequent normal SIGTERM exit produces retained NVIDIA core17178: release FAIL. Tekken launch/render/Close, metadata/history and genuine 2/47 persistence pass; candidate9's real earned toast/input/expiry/deduplication pass. Fresh candidate10 offline controller installation and USB-absent VM boot pass all 15 installed-health checks; this does not resolve the PC1 fault. Candidate11 passes 11 ELF regressions and exact SHA-pinned SRPM preparation with --fuzz=0; full production compile/image, baked normal SIGTERM/reboot, fresh media and physical acceptance remain pending. |

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
