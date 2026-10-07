// MarwanOS: release Vulkan owners while the NVIDIA driver/backend are alive.
// This runs from the stopped compositor's ordinary shutdown path, not atexit.
#pragma once

template<typename Device, typename Output, typename ReleaseEffects>
static inline void release_nvidia_output_before_driver_exit(
    Device &device, Output &output, ReleaseEffects release_effects)
{
    // waitIdle resets completed command buffers but keeps them cached. Free
    // both caches explicitly so their global destructors make no driver calls.
    device.waitIdle();
    device.releaseCommandBuffers();
    release_effects();

    // Partial images can alias regular output memory; release those first.
    output.outputImagesPartialOverlay.clear();
    output.outputImages.clear();
    for (auto &image : output.pScreenshotImages)
        image = nullptr;
    output.temporaryHackyBlankImage = nullptr;
    output.tmpOutput = nullptr;
    output.nisScalerImage = nullptr;
    output.nisUsmImage = nullptr;
    output.swapchainHDRMetadata = nullptr;
}
