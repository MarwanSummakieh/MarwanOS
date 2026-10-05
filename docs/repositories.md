# PC1 repositories and workspace

PC1 is the [GitHub Project](https://github.com/users/MarwanSummakieh/projects/3)
for the Linux console system. GitHub Projects link repositories and track their
issues; each repository remains owned by `MarwanSummakieh`.

| Repository | Ownership |
| --- | --- |
| [MarwanOS](https://github.com/MarwanSummakieh/MarwanOS) | OS image, boot/session, installer media, system integration and product roadmap |
| [pc1-shell](https://github.com/MarwanSummakieh/pc1-shell) | Godot shell, embedded Chromium/Mowser, Files, keyboard, controller UI and presentation tests |
| [pc1-installers](https://github.com/MarwanSummakieh/pc1-installers) | Windows/Proton installation worker, native setup bridge, recipes, launch helper and backend tests |
| [pc1-controllers](https://github.com/MarwanSummakieh/pc1-controllers) | Linux input broker, application-controller routing, kernel fixtures and controller backend tests |
| [pc1-services](https://github.com/MarwanSummakieh/pc1-services) | Audio, notifications, their session services, D-Bus registration and backend tests |
| [pc1-fdm](https://github.com/MarwanSummakieh/pc1-fdm) | GPLv3 FDM Classic fork, controller download manager, torrent/input fixtures and deployment tooling |

The existing [PC1 Windows shell](https://github.com/MarwanSummakieh/PC1) remains
intact as the earlier Windows implementation. The Linux integration repository
keeps its name and Git history, so existing image references and bench scripts
continue to resolve.

## Integration model

Component repositories are the development sources. MarwanOS carries pinned
integration copies at its existing build paths, rather than fetching mutable
branches during image builds. This preserves the current Containerfile, shell
scripts and offline build context while the sources are maintained separately.

`pc1-components.json` records each component's Git URL, exact commit and Git blob
IDs for every exported file. Component README/CI/build metadata and FDM's upstream
source tree stay in their own repositories; the lock covers only their OS exports.

From MarwanOS, check that the integrated files match the pinned sources:

```bash
python3 scripts/components.py --verify
```

To restore one component's integration copies from its exact pinned checkout:

```bash
python3 scripts/components.py --sync --component installers --source ../pc1-installers
```

An update is deliberate: commit changes in the component repository, update its
commit and exported blob IDs in the lock, sync the copies, review the diff and run
the OS regressions before committing the integration. The sync reads committed
blobs and does not publish, change runtime state or delete unrelated files.

## Local layout

The new workspace is `C:\Users\brain\Documents\repos\PC1-workspace`:

```text
PC1-workspace/
  PC1.code-workspace
  pc1-os/           Git worktree of MarwanOS on pc1/integration
  pc1-shell/        independent Git repository
  pc1-installers/   independent Git repository
  pc1-controllers/  independent Git repository
  pc1-services/     independent Git repository
  pc1-fdm/          independent Git repository, with upstream FDM history
```

The original `MarwanOS` checkout stays on `main`. The existing `PC1` Windows
checkout and older `.claude/worktrees` are retained. Use a component's own
repository for its source changes and the `pc1-os` worktree for OS integration.

Today's feature and acceptance inventory is in the
[development record](development-2026-10-05.md). Outstanding work stays in the
[roadmap](roadmap.md) and the linked PC1 project issues.
