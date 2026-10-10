// MarwanOS: retain the diagnosed NVIDIA Vulkan dispatch owner through dlclose.
// Included only by gamescope, not injected into its clients or other processes.
#pragma once
#include <cstdint>
#include <cstring>
#include <dlfcn.h>
#include <cstdio>
#include <unistd.h>

enum class NvidiaDispatchLifetime { NotApplicable, Retained, UnexpectedOwner, PinFailed };

static inline NvidiaDispatchLifetime retain_nvidia_dispatch_owner(
    uint32_t vendor, const void *function)
{
    if (vendor != 0x10de)
        return NvidiaDispatchLifetime::NotApplicable;

    Dl_info owner = {};
    if (!function || !dladdr(function, &owner) || !owner.dli_fname)
    {
        std::fprintf(stderr, "marwanos: NVIDIA Vulkan dispatch owner unavailable; teardown protection inactive\n");
        return NvidiaDispatchLifetime::UnexpectedOwner;
    }
    const char *name = std::strrchr(owner.dli_fname, '/');
    name = name ? name + 1 : owner.dli_fname;
    constexpr const char prefix[] = "libnvidia-eglcore.so.";
    bool matching = std::strncmp(name, prefix, sizeof(prefix) - 1) == 0;
    if (matching)
    {
        // Match a real numbered NVIDIA core, never an arbitrary layer or path.
        const char *version = name + sizeof(prefix) - 1;
        bool digit = false;
        for (; *version; ++version)
        {
            if (*version >= '0' && *version <= '9')
                digit = true;
            else if (*version == '.' && digit)
                digit = false;
            else
            {
                matching = false;
                break;
            }
        }
        matching = matching && digit;
    }
    if (!matching)
    {
        std::fprintf(stderr, "marwanos: NVIDIA Vulkan dispatch owner %s is outside diagnosed eglcore scope; teardown protection inactive\n", owner.dli_fname);
        return NvidiaDispatchLifetime::UnexpectedOwner;
    }

    // NOLOAD uses the actual already-loaded version from dladdr. NODELETE pins
    // code through the driver's exit-handler dlclose, while normal process
    // destruction, driver finalizers, SIGTERM and core reporting remain intact.
    void *handle = dlopen(owner.dli_fname, RTLD_NOW | RTLD_LOCAL | RTLD_NOLOAD | RTLD_NODELETE);
    if (!handle)
    {
        std::fprintf(stderr, "marwanos: retaining NVIDIA Vulkan dispatch owner %s failed: %s\n", owner.dli_fname, dlerror());
        return NvidiaDispatchLifetime::PinFailed;
    }
    std::fprintf(stderr, "marwanos: retained NVIDIA Vulkan dispatch owner %s through compositor teardown pid=%ld\n", owner.dli_fname, static_cast<long>(getpid()));
    // NODELETE remains set after dropping the extra reference. Do not alter
    // symbol scope or leak this mechanism into any client environment.
    dlclose(handle);
    return NvidiaDispatchLifetime::Retained;
}
