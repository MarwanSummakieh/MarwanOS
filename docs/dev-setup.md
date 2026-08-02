# Dev setup — the MarwanOS factory

Everything here is M0. The goal is a loop you trust: change a file, build, push,
`bootc upgrade`, see the change, roll it back. No OS work starts until that works.

## The three machines

See [ADR 0003](adr/0003-test-targets.md) for why this is split rather than one VM.

| Role | What it is | What it proves |
|------|-----------|----------------|
| **Build host** | Fedora VM on the Predator | Builds and pushes. Never boots MarwanOS |
| **VM target** | Second VM, snapshotted | M0 in full. Most of M2. All of M3 |
| **Bare-metal target** | The Predator booted from a USB SSD | M1. The NVIDIA half of M2. Every filmed gate |

The short version of the split: a VM cannot show you an NVIDIA DRM device, and
M1 exists to ask a question about the NVIDIA DRM device. Use the VM for the fast
loop, hardware for anything that gets filmed.

Do not run both VMs at once — 16 GB and four physical cores will not enjoy it.
They do not need to overlap: the build host pushes to GHCR, then the target pulls.

---

## 1. Build host

Two of them, in practice. WSL2 builds and pushes and is much faster to reach;
the Fedora VM exists only because `bootc-image-builder` needs privileged
containers and loop devices. Start with WSL2 — you can get to a validated image
without touching Hyper-V.

### 1a. WSL2 (verified 2026-08-02 — this is the path that built the first image)

`FedoraLinux-43` matches the base image's Fedora version, which keeps `dnf`
behaviour and package names aligned with what the image sees.

```powershell
wsl.exe --install -d FedoraLinux-43 --no-launch
```

`--no-launch` matters: it skips the interactive first-run account setup, and you
can work as root instead, which is what the build wants anyway.

```powershell
wsl.exe -d FedoraLinux-43 -u root -- dnf install -y podman git
```

The repo is reachable at `/mnt/c/...` — the build context is a few KB, so the
slow Windows filesystem bridge does not matter here. Podman's own storage lives
inside the WSL ext4 filesystem, which is where the multi-GB layers actually go.

```powershell
wsl.exe -d FedoraLinux-43 -u root -- bash -lc "cd /mnt/c/Users/brain/Documents/repos/MarwanOS && podman build -f os/Containerfile -t localhost/marwanos:smoke os/"
```

> **Docker Desktop is not the path.** It is installed on this machine and it
> fails to start with a stale-socket error in its inference manager. It is also
> the wrong tool — it cannot run `bootc-image-builder`. Nothing in this project
> needs it; leave it stopped.

### 1b. There is no build VM

An earlier draft of this document specced a Hyper-V Fedora VM as the build host,
because `bootc-image-builder` needs loop devices, device-mapper and privileged
containers, and WSL2 was assumed not to have them. It does have them — plus
systemd as PID 1 — and bib built a 6.6 GB VHDX there in 299 seconds.

WSL2 is the whole build host. The only VM in this project is the *target*.

Podman remains non-optional. Docker can build the image — it is an ordinary OCI
image — but bib reads podman's container storage, so the installer step needs it.

### Get the repo onto it

```bash
git clone <your-remote> ~/marwanos && cd ~/marwanos
```

If you have not pushed this repo anywhere yet, a Hyper-V shared folder or plain
`scp` from the Windows side works just as well for now.

```bash
chmod +x scripts/*.sh
```

---

## 2. GHCR access

The image is `ghcr.io/marwansummakieh/marwanos`. Already persisted in the WSL
distro's `~/.bashrc`, but if you build anywhere else, set it there too:

```bash
echo 'export GHCR_USER=marwansummakieh' >> ~/.bashrc && source ~/.bashrc
```

> Note the case. The GitHub account is `MarwanSummakieh`, but container registry
> namespaces must be lowercase, so the image ref is `marwansummakieh`. GHCR will
> reject a push with capitals in the path.

Create a classic Personal Access Token at
`https://github.com/settings/tokens` with the `write:packages` scope, and store
it where `build-push.sh` will find it:

```bash
install -d -m 700 ~/.config/marwanos
```

Paste the token into `~/.config/marwanos/ghcr-token` with your editor, then lock
it down. The script reads this file and pipes it to `podman login` on stdin; it
is never passed as an argument and never echoed.

```bash
chmod 600 ~/.config/marwanos/ghcr-token
```

After the first push, **make the package public** in your GitHub package settings.
Nothing in an OS image is secret (D2), and a public package means the target can
`bootc upgrade` without carrying registry credentials.

---

## 3. The loop

This is the whole of M0. From the build host:

```bash
./scripts/build-push.sh
```

Then on the target, over SSH:

```bash
sudo bootc upgrade && sudo systemctl reboot
```

After it comes back:

```bash
cat /usr/share/marwanos/build-info
```

That file is regenerated on every build with a fresh version, commit and
timestamp, which is what makes "did the upgrade actually land" a one-line check
rather than a guess.

To undo a bad build:

```bash
sudo bootc rollback && sudo systemctl reboot
```

**Measured 2026-08-02:** a cold build is 515 s; a build where only the version
changed is **70 s**, with 8 of 12 steps served from cache. The first push is
~7 GB, but only the three small trailing layers change afterwards, so subsequent
pushes are quick. Comfortably inside M0's 15-minute budget — re-measure if it
ever stops feeling that way.

### Two ways to publish, and when to use each

| Route | Use it for | Cost |
|-------|-----------|------|
| `git push` → GitHub Actions | Canonical images the target consumes | Cold build every run; no upload from your machine, no PAT |
| `./scripts/build-push.sh` | Manual fallback, or pushing without a commit | ~70 s warm build, but a ~7 GB upload and a `write:packages` PAT |

Git carries the source; GHCR carries the image. The target builds nothing — it
only pulls — so a `git push` alone never updates a machine. It updates a machine
because the workflow it triggers pushes the image.

Iterate locally with `--no-push` and let CI produce anything a target will pull:

```bash
./scripts/build-push.sh --no-push
```

### Changing the base image

Never track a floating tag; an upstream rebuild landing mid-debug is
indistinguishable from your own change breaking the boot. Bump deliberately:

```bash
./scripts/bump-base.sh
```

```bash
./scripts/bump-base.sh --write
```

Deploy a base bump to the VM target before bare metal. It is exactly the class of
change that builds clean and boots black.

---

## 4. VM target

**Already done — `~/Hyper-V/marwanos.vhdx` (6.6 GB) is built and staged.** The
rest of this section is how to reproduce it.

MarwanOS has no getty on tty1 by design (D6), so SSH is the only way into a
target without a working session. Your existing `~/.ssh/id_ed25519.pub` is baked
in as the `marwan` user's key.

Build in the Linux filesystem, not `/mnt/c` — the artifact is ~7 GB and the
Windows filesystem bridge makes that crawl:

```bash
OUT_DIR=/var/tmp/marwanos-out SSH_KEY_FILE=/mnt/c/Users/brain/.ssh/id_ed25519.pub ./scripts/make-installer.sh vhdx
```

Then copy the result to the Windows side and create a Generation 2 VM around it,
**Secure Boot off** (D7 — the NVIDIA modules are unsigned).

> **These need an elevated PowerShell.** `brain` is a local administrator but
> Hyper-V cmdlets fail from an unelevated session with a permission error, and
> the `Hyper-V Administrators` group is empty. Run PowerShell as Administrator,
> or add yourself to that group once to avoid the prompt in future.

```powershell
New-VM -Name marwanos-target -Generation 2 -MemoryStartupBytes 4GB -VHDPath "$env:USERPROFILE\Hyper-V\marwanos.vhdx" -SwitchName "Default Switch"
```

```powershell
Set-VMFirmware -VMName marwanos-target -EnableSecureBoot Off
```

Snapshot it immediately, before the first boot. Testing `bootc rollback` is much
faster when a broken target is one checkpoint-restore away:

```powershell
Checkpoint-VM -Name marwanos-target -SnapshotName "clean-install"
```

The NVIDIA driver will not load in here and that is expected — the VM has no
NVIDIA card. M0 is about the deploy loop, not the GPU. Do not spend time
debugging `nvidia-smi` on the VM target; it is supposed to fail.

### Turn off automatic checkpoints

Windows client Hyper-V enables **automatic checkpoints** by default and snapshots
the VM every time it starts. The VM then writes to a `.avhdx` differencing disk
rather than the base VHDX — so mounting `marwanos.vhdx` offline shows you a
pristine pre-boot image with no journal, no logs, and none of the state you were
trying to inspect. Turn it off on every target:

```powershell
Set-VM -Name marwanos-target -AutomaticCheckpointsEnabled $false
```

To read a target's disk offline, stop it and merge any existing checkpoint back
into the base first, otherwise you are reading the wrong file:

```powershell
Stop-VM -Name marwanos-target
Get-VMSnapshot -VMName marwanos-target | Remove-VMSnapshot
```

### Replacing a target's disk

Once a checkpoint exists the VM runs off `.avhdx` differencing disks stacked on
the base VHDX, so you cannot just overwrite the file. Tear the VM down and
rebuild it — the disk regenerates in about five minutes, so it is never worth
nursing a broken one:

```powershell
Stop-VM -Name marwanos-target -TurnOff -Force -ErrorAction SilentlyContinue
Remove-VM -Name marwanos-target -Force
Remove-Item "$env:USERPROFILE\Hyper-V\marwanos.vhdx","$env:USERPROFILE\Hyper-V\marwanos_*.avhdx" -Force -ErrorAction SilentlyContinue
```

Take the pre-boot checkpoint only once the image is known to boot. Checkpointing
a disk you have not booted yet buys nothing and gets in the way of swapping it.

---

## 5. Bare-metal target

The Predator, booted from an external USB SSD. Windows is never repartitioned.
Use a real USB 3.x SSD — a flash stick will make boot times meaningless and M2
has a 15-second budget.

```bash
./scripts/make-installer.sh anaconda-iso
```

Write `out/*.iso` to a USB stick, boot the Predator from it, and install **to the
external SSD** — check the target disk twice, this is the one destructive step in
the whole setup.

In the Predator's firmware:
- **Secure Boot: off** (D7)
- Boot the SSD via the one-time boot menu (F12) rather than making it default, so
  removing the SSD returns the laptop to Windows with nothing to undo

Then connect the TV over HDMI. Before trusting any M1 result, confirm which GPU
actually owns that output — on a hybrid-graphics laptop this is a real question,
and if gamescope grabs the Intel iGPU the spike is measuring the wrong card:

```bash
sudo dnf install -y drm_info && drm_info | grep -A2 'Driver:'
```

```bash
nvidia-smi
```

---

## Troubleshooting

**Build fails at the `ls -1 /tmp/rpms/...` check.** Upstream changed the akmods
layout. Inspect it and update the Containerfile paths:

```bash
podman run --rm ghcr.io/ublue-os/akmods-nvidia-open:main-43 find /rpms -name '*.rpm'
```

**A script "succeeded" but did nothing, when driven from PowerShell.** PowerShell
expands `$VAR` and `$?` inside strings *before* they reach WSL, so a command like

```powershell
wsl -d FedoraLinux-43 -u root -- bash -lc 'thing; echo "RC=$?"'
```

reports a status PowerShell invented, not the one bash produced. This cost real
debugging time here — it manufactured a phantom "bib exits 0 on failure" bug that
does not exist (bib exits 1, correctly). **Put anything containing `$` in a
script file and run that file**, as `scripts/` and the examples above do.

Related: `bash -lc` is a *login* shell. It reads `/etc/profile`, not `~/.bashrc`,
which is why exports added to `~/.bashrc` are invisible to it. `GHCR_USER` is now
defaulted inside the scripts so neither trap can break a build.

**A build re-runs `dnf` and `dracut` when only the version changed.** It should
not — the version `ARG`s are declared *after* those layers in the Containerfile
precisely so a version bump cannot invalidate them. If you add an `ARG` near the
top of the Containerfile, you will silently undo this and roughly triple the
loop time. Check with:

```bash
podman build -f os/Containerfile -t test os/ 2>&1 | grep -c 'Using cache'
```

**`dracut[E]: FAILED: ... dracut-install ... -f /root` during the build.** Cosmetic,
and expected. Dracut carries on, exits 0, and the resulting initramfs is correct —
verify rather than trust it:

```bash
podman run --rm ghcr.io/marwansummakieh/marwanos:latest bash -c 'KV=$(rpm -q --qf "%{VERSION}-%{RELEASE}.%{ARCH}" kernel-core | tail -1); lsinitrd /lib/modules/$KV/initramfs.img | grep nvidia'
```

You should see `nvidia.ko`, `nvidia-drm.ko`, `nvidia-modeset.ko` and
`nvidia-uvm.ko`. If they are there, ignore the error.

**SSH says "Server accepts key" and then "Permission denied".** This cost most of
a day here, so read it before touching the target.

`Server accepts key` means the server found your key in `authorized_keys` and
authorized it. **It is evidence the server is fine**, not evidence of a server
bug. Do not go looking for one.

The real cause was a **passphrase-protected private key combined with
`BatchMode=yes`**. The client offers the public key, the server says yes, the
client then has to sign a challenge — and cannot, because the key is encrypted
and `BatchMode` forbids prompting. It disconnects without ever sending the signed
request, so the server never records an authentication failure at all.

The server-side signature of this is unmistakable once you know it:

```
sshd-session[...]: Connection reset by authenticating user root <ip> [preauth]
audit: op=PAM:bad_ident grantors=? acct="?" ... res=failed
```

Note what is *absent*: no `Failed publickey`, no `Accepted publickey`. If auth had
genuinely been rejected you would see `Failed publickey`. `acct="?"` means PAM
never even received a username.

Check the key before anything else:

```powershell
ssh-add -l
```

If the agent is empty or not running, load the key once and everything works:

```powershell
Set-Service ssh-agent -StartupType Manual; Start-Service ssh-agent; ssh-add $env:USERPROFILE\.ssh\id_ed25519
```

Only after ruling this out is it worth looking at the account: a shadow password
field of `!` (locked), or `/run/nologin` blocking every non-root login when the
boot did not complete. root sidesteps both — its field is `*` and `pam_nologin`
exempts uid 0 — which is why the installer adds your key to root as well.

**Target drops into dracut emergency mode ("Entering emergency mode", repeating).**
The initramfs cannot assemble the root filesystem. On a bootc/ostree system the
usual cause is a missing `ostree` dracut module: its `check()` looks for a live
ostree deployment, finds none inside a container build, and dracut silently omits
it. The result passes `bootc container lint`, converts to a disk image fine, and
cannot boot. `os/Containerfile` forces it with `--add ostree` and asserts on it.

Compare against the base image — the module lists should differ only by what you
deliberately added:

```bash
podman run --rm ghcr.io/ublue-os/base-main:43 bash -c 'lsinitrd --mod /lib/modules/$(rpm -q --qf "%{VERSION}-%{RELEASE}.%{ARCH}" kernel-core | tail -1)/initramfs.img | sort'
```

**Target boots to a black screen after a base bump.** Almost always a base/akmods
mismatch — `bootc rollback`, then confirm `BASE_TAG` and `AKMODS_TAG` are a
matched pair (`43` ↔ `main-43`).

**`bootc upgrade` reports no change.** The tag moved but the target cached the
old digest, or the push silently went to a different repo. Check what the target
believes it is running:

```bash
sudo bootc status
```

**Kernel args did not take effect.** They are baked into the image, not set on
the target, and they only apply after the reboot following the upgrade:

```bash
cat /proc/cmdline
```
