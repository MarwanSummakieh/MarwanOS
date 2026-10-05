# PC1 system acceptance — 2026-10-05

This development run uses GPT-6.1 Sol agents for the browser, Files/keyboard,
and Windows lifecycle, with integration and OS boot verification in the parent
session. Changes remain local to the existing working tree.

## Verified behavior

| Area | Evidence |
|---|---|
| Files and keyboard | Controller shell suite passes search, folder history, copy/move, cancellation, collisions, symlink handling, trash/restore, upload selection, typing, movement, clamping and saved keyboard position |
| Chromium | Real CEF rendering/input, downloads, workflow and public HTTPS suites pass; includes controller upload, tabs, bookmarks/history, JavaScript dialogs and HTML select popup dismissal |
| Windows applications | The final VM's actual service provisions Proton and Steam Runtime from an empty cache, installs 7-Zip, publishes its library card, launches, minimizes/resumes four times with the same process identities, closes, cancels removal and completes confirmed removal under SELinux Enforcing; all 43 kernel-controller commands pass with no input leakage |
| Regressions | 55 Python tests pass in the Linux test image, alongside the Godot controller/Files/keyboard/lifecycle suites and actual CEF workflow checks |
| Input ownership | Linux kernel tests verify exclusive physical-device grabs, shell delivery, neutral application input in menus, held-control suppression, disconnect and lease expiry |
| Running OS | Final image `337e11badd5a` cold-boots in a KVM/UEFI VM into PC1, with SELinux enforcing, zero failed services, an active Windows worker and current shell heartbeat; physical appliances retain gamescope |
| USB installation | The final branded ISO boots as UEFI USB mass storage, accepts controller keyboard input and cancellation, installs offline onto an explicitly confirmed blank 80 GiB virtual disk, and reports completion. With the USB removed, the installed disk boots into PC1; the forwarded controller opens Files/Downloads, public HTTPS in Chromium, live keyboard typing and browser menus |
| Controller in the VM | 33 commands through an actual synthetic Linux evdev/uinput device exercise Home → Files → document browser → keyboard → Files → Home → public HTTPS browser; all succeed, with zero escaped physical events or application-pad events while PC1 owns input |
| Browser sandbox in the VM | Chromium renderers run as UID 1000 with NoNewPrivs=1, seccomp mode 2 and a separate user namespace |

The first VM acceptance used a disposable disk overlay. It identified and verified
source fixes for Xorg's inherited console descriptor, boot-success recording on
the read-only boot partition, and display blanking despite active controller use.
The final disk was subsequently cold-booted without overrides. Its baked Xorg
session has screen-saver timeout zero and DPMS disabled. The boot-success timer
automatically sets `boot_success=1` and `menu_auto_hide=1` while `/boot` stays
read-only in the main mount namespace. No development shell or local service
override is present.

Final image: `ghcr.io/marwansummakieh/marwanos:controller-20261005`, local ID
`337e11badd5a70eb08c515f13d8de505e8f47b116f8a31be651bf420111fde91`.
Build date: `2026-10-05T01:41:33Z`; version `0.1.20261005`.

## Local artifacts

| File | Bytes | SHA-256 |
|---|---:|---|
| `out/pc1-20261005.iso` | 5,877,071,872 | `00898f46492656aa0311bcd6eb75e95c730d38b82b4ef2490223173c0215c47b` |
| `out/pc1-20261005.qcow2` | 4,468,310,016 | `18d504f9606d0e98a2b7fe12bff0b7007ecff3605e20b842008c56b6dfb822f4` |

The ISO passes embedded media verification and GPT/appended-EFI consistency
checks. The standalone QCOW2 passes `qemu-img check` and is byte-identical to
the boot-tested raw disk. Both copies in `out/` were independently hashed after
copying from the Linux build host. `out/release-20261005/README.md` describes
how to use them. These local artifacts have not been published to the registry.

## Evidence locations

- `out/vm-controller-acceptance/`: screenshots, kernel input command log, renderer
  sandbox status, shell journal and display-idle diagnosis.
- `out/release-20261005/final-cold-boot.txt` and `final-cold-boot.png`: final
  image boot, security, service, read-only mount and display-idle evidence.
- `out/vm-windows-acceptance/README.md`: final image service and first-use runtime
  acceptance, with 15 screenshots, process identities and controller event logs.
- `out/vm-installer-acceptance/`: controller-only USB installation, completion,
  installed-disk integrity and cold-boot evidence.
- `/var/tmp/pc1-browser-complete/final-*.log`: actual CEF build and test results on
  the Fedora Linux build host.
- [Windows installation](windows-installation.md): lifecycle contract and real
  application acceptance details.
- [Controller routing](controller-routing.md) and [built-in tools](built-in-tools.md):
  architecture, controls and feature boundaries.

## Remaining hardware scope

The automated controller is a real kernel input device, not a physical USB or
Bluetooth controller. Physical DualSense/Xbox hotplug, NVIDIA/gamescope handoff,
TV behavior, suspend/resume, Steam account/game compatibility, and firmware USB
boot need target-machine acceptance. No physical disk has been flashed or changed.

Windows compatibility is application-specific; 7-Zip is the verified example.
Kernel anti-cheat and arbitrary Windows drivers are not promised. Browser DRM,
folder uploads, File System Access, and device/location permissions are unsupported.
Rumble and multiplayer controller routing are not implemented.

A small removal-confirmation menu currently scrolls its second action into view
when focused; both Cancel and confirmed removal pass. This presentation issue
is documented with exact dimensions in the Windows acceptance evidence.
