# Files controls and Trash bin — PC1, 10 October 2026

Deployed to the bench at `192.168.50.206` at 02:03 Copenhagen time.

Files omits the top Back, Search, View and Actions controls. Its footer maps
Circle to Back, Cross to Open, Square to Select and Triangle directly to Search.
Options includes file actions and view settings. Compact windows retain their
Places drawer, and Circle can still close Files from a location root.

Trash bin is a persistent left-hand location with an item count. Its listing
uses original names, supports search and selection, and restores files or
folders through Cross or Options. Options exposes Empty trash bin with a
confirmation whose initial selection is Cancel. File pickers omit Trash bin.

The build starts from the exact verified source matching the active bench
binary and changes only six Files/menu scripts. Browser, native engine, Home,
Steam, Downloads, keyboard and controller-broker updates are retained.

## Verification

- Pinned Godot 4.7.1 import and Linux export passed.
- Files layout/controller, Trash bin, shared design and Tools suites passed
  in an isolated Linux fixture, including symlinks, nested folders, hidden
  contents, metadata cleanup, restoration and cancelled empty confirmation.
- Exported startup passed separately as the session user. The supervised
  replacement reached Home with the existing native engine and no script,
  parse or resource-loading errors.
- The actual 3440×1440 Files screen was inspected. Live DualSense/broker
  software pulses checked Triangle Search, Square selection and the Trash bin
  location and Options menu. Live user files were not restored or emptied.
- Windows rendering checks covered desktop, ultrawide, compact, 720p and 4K
  layouts before the bench build. Physical controller feel remains for the user.

## Deployment and recovery

Active shell: `/var/marwanos/console-design-20261009/marwanos-shell`.
Manifest: `files-controls-deployment-20261010.json` in the same directory.
The main refinement manifest also references this build and its source.

Shell SHA-256:
`f08120f4b1c91adc9a8c5b22df4ed13ca1be59dcdbdebe565b9b1c9a43256a91`.

Source: `/var/tmp/pc1-files-controls-20261010/source.tar.gz`.
Source SHA-256:
`290f5be5a67fd8d712dff369612e96fb4edea11e2de685c16ef613de46a0cab8`.

The previous binary is retained beside the active binary as
`marwanos-shell.before-files-controls-20261010`. Activation checks the baseline
binary, engine, source manifest and absence of running games/installers before
replacing the shell, with rollback on failed startup. No OS image, native
engine, controller broker or player data was replaced. No reboot was needed.

Local build scripts, live captures and deployment evidence are under
`out/files-bench-20261010/`; matching Linux validation logs are under the source
directory on PC1.
