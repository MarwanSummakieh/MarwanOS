# NVIDIA compositor teardown

PC1's gamescope 3.16.23 crashes in its Vulkan device destructor when the first
boot's link-scrub stops the compositor. The subsequent display reset and session
recovery succeed, but recovery does not establish a clean compositor exit.

Candidate10 also crashes during ordinary SIGTERM and reboot after passing its
initial boot checks. Its retained core identifies
`CBufferMemoizer::~CBufferMemoizer` → `CVulkanTexture::~CVulkanTexture` → NVIDIA
eglcore/glsi after the early output cleanup. The memo cache privately retains
imported client textures until static destruction, after the driver's exit
handler has already destroyed internal state. Keeping the driver library mapped
does not keep that state alive.

Candidate11 (`gamescope-3.16.23-1.pc1.3.fc43`) adds explicit memo-cache cleanup
after GPU work, command buffers, effects and output textures are released, before
backend teardown. `CBufferMemoizer::Clear()` acquires the Wayland lock before the
memo-map mutex and destroys the memo entries, detaching their buffer listeners
before dropping the private texture references. Ordinary signals, exit handlers
and coredump reporting remain active. The baked NVIDIA normal-exit test remains
the deciding evidence; the earlier source-only trials below document why both
dispatch-code retention and early resource release are necessary.

`scripts/verify-pc1-shutdown.py` checks the explicit prior boot's normal reboot
journal against the recorded compositor PID and shutdown time, independently of
the initial link scrub. It rejects kernel-reported gamescope faults even when no
structured coredump was stored. It also checks cleanup ordering, current image
identity, enforcing AVCs and GPU faults. It never clears evidence or infers an
exact compositor exit status from service recovery. For example, after recording
the source SHA, digest, boot ID, recovered compositor PID and UTC boundary before
a normal reboot:

```sh
python3 scripts/verify-pc1-shutdown.py --host root@192.168.50.206 \
  --commit "$source_sha" --digest "$image_digest" \
  --prior-boot "$prior_boot" --compositor-pid "$compositor_pid" \
  --shutdown-after "$shutdown_after_utc"
```

Eight offline verifier regressions cover the failed-kernel/no-core case, wrong
boot, unavailable evidence, duplicate cleanup and cleanup order. Running the
verifier against candidate10's preserved normal reboot returns failure for its
actual gamescope fault (`out/candidate10-shutdown-negative-control.json`).

Candidate11's published image now passes the real PC1 NVIDIA normal-exit checks:
idle and postgame SIGTERM, full normal reboot shutdown, and final boot gates.
See the [runtime acceptance record](candidate11-teardown-acceptance-20261007.md)
for exact image identity, process IDs and retained evidence.

## Earlier dispatch-lifetime trial

The backtrace matches the open upstream [DRM exit issue #1526](https://github.com/ValveSoftware/gamescope/issues/1526).
[Upstream's October 4 suggestion](https://github.com/ValveSoftware/gamescope/issues/1526#issuecomment-5980390505)
is to test `VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1`.
[Khronos documents](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md)
that this retains dynamic libraries through instance destruction; it is supported
since loader 1.3.259. PC1 has loader 1.4.341 and its binary contains the option.

That historical trial assigned the setting only to NVIDIA gamescope and removed
it from clients. It is now retired: the production session launches gamescope
normally and leaves existing client loader environments intact.

The loader-only trial **failed on the real candidate6 boot**. The first
compositor's core confirms the flag was present. Its saved `FreeCommandBuffers`
pointer is `0x7f8b3acd1d40`, which was unmapped at the fault; the return address is
the matching binary's `CVulkanCmdBuffer` destructor. In the recovered compositor,
the equivalent dispatch pointer belongs to `libnvidia-eglcore.so.610.43.03`.
The 32 bytes at that address match the installed library at file offset
`0xbd0d40`. The initial core lacks that mapping while the Vulkan loader and
other NVIDIA libraries remain mapped. This identifies the dispatch owner
unloading; retaining only the loader's ICD handles did not retain it.

`os/gamescope/gamescope-3.16.23-nvidia-lifetime.patch` adds a gamescope-only
retention call immediately after its Vulkan device dispatch table is populated.
For vendor `0x10de`, the helper uses `dladdr(FreeCommandBuffers)` to identify the
already-loaded owner, accepts only the diagnosed numbered NVIDIA eglcore library,
and promotes it with `RTLD_NOLOAD | RTLD_NODELETE`. The extra reference is closed;
NODELETE keeps the code available through subsequent driver `dlclose` calls.
Unexpected owners or retention failures emit a warning and remain visible to
ordinary core reporting. This does not fix an invalid driver-internal object
state, if a subsequent real boot reveals one.

This retention-only change was a source-owned trial pending a baked real boot.
Acceptance requires the retention log (with its actual PID) from the first compositor, no compositor
SEGV/core, normal DRM release, successful splash/session return, fresh shell and
controller workers, and gameplay regression. Physical flicker and cold-boot timing
require separate observation. No suspend testing is performed.

The original retention-only patch used the exact Fedora `gamescope-3.16.23-1.fc43.src.rpm`
source, its dependency pins and packaging, with release `1.pc1.1.fc43`. The current
memo-cleanup build retains that source pin with release `1.pc1.3.fc43`. The build helper
fetches it from [Fedora Koji](https://kojipkgs.fedoraproject.org/packages/gamescope/3.16.23/1.fc43/src/gamescope-3.16.23-1.fc43.src.rpm)
and verifies SHA256 `d224583dc3e62752f0e74afd19631742a173f18d3b42277b2af5ba6b459427ee`.
This source RPM has no package signature; the pin and HTTPS provenance are the
source integrity evidence. Fedora's build dependencies and their normal repository
verification stay in a disposable build stage. The final image installs the RPM
and retains `cap_sys_nice=ep`. That capability makes an ordinary `LD_PRELOAD`
wrapper unsuitable because secure execution strips the preload setting.

The helper follows the [glibc/Linux dynamic loading contract](https://man7.org/linux/man-pages/man3/dlopen.3.html).
It adds no client environment variables or dynamic-loader configuration and
changes no SIGTERM, link-scrub, core policy or process-exit behavior.

`tests/test_session_vulkan_lifetime.py` now verifies ordinary launch behavior
with a disposable executable: arguments containing spaces, tracked child PID,
actual exit status, and preservation of an existing loader environment in the
compositor and separately launched clients. The failed environment-trial checks
were retired. This establishes launch behavior, not physical Vulkan teardown.

`tests/test_gamescope_driver_lifetime.py` builds a tiny real ELF library and client
using the production retention header. A driver's exit handler closes the library
before a global client destructor invokes a saved function pointer. The unretained
negative control exits with SIGSEGV; the retained case reaches actual exit 0, calls
the saved function, and still runs the library finalizer. Other GPUs, unrelated
libraries and malformed version names retain ordinary unloading. These tests
prove the dynamic-loader lifetime mechanism, not NVIDIA hardware correctness.
