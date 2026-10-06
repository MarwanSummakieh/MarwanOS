# NVIDIA compositor teardown

PC1's gamescope 3.16.23 crashes in its Vulkan device destructor when the first
boot's link-scrub stops the compositor. The subsequent display reset and session
recovery succeed, but recovery does not establish a clean compositor exit.

The backtrace matches the open upstream [DRM exit issue #1526](https://github.com/ValveSoftware/gamescope/issues/1526).
[Upstream's October 4 suggestion](https://github.com/ValveSoftware/gamescope/issues/1526#issuecomment-5980390505)
is to test `VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1`.
[Khronos documents](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md)
that this retains dynamic libraries through instance destruction; it is supported
since loader 1.3.259. PC1 has loader 1.4.341 and its binary contains the option.

The session removes any inherited setting before launching clients, then assigns
it only to gamescope when the selected GPU is NVIDIA. Shell, Steam and Proton
launched by the session retain their ordinary environment. SIGTERM, core capture
and the link-scrub display-reset sequence stay intact. Driver libraries can remain
mapped until compositor process exit.

This is a **trial workaround until the baked image's real boot proves it**.
Acceptance requires no compositor SEGV/core, normal DRM release, successful
splash/session return, fresh shell/controller workers and gameplay regression.
Physical flicker and cold-boot timing require separate observation. If the fault
persists, preserve its core and inspect mapped libraries and Vulkan function
pointers with matching debug symbols before attempting a cleanup-order patch.

`tests/test_session_vulkan_lifetime.py` exercises the production launch function
with disposable executables. It checks NVIDIA/non-NVIDIA/unselected GPU handling,
arguments containing spaces, tracked child PID and exit status, and removal of an
inherited setting from separately launched clients. It establishes environment
scope and launch behavior, not physical Vulkan teardown correctness.
