"""Real ELF regression: mapped NVIDIA code is insufficient after driver exit."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest

if os.name == "posix":
    import resource

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = r'''
#include <cstdio>
#include <cstdlib>
#include <cstring>
struct State { unsigned commands = 0, textures = 0, metadata = 0; };
static State *state;
static void driver_exit() {
    std::fprintf(stderr, "driver-finalize commands=%u textures=%u metadata=%u\n",
                 state->commands, state->textures, state->metadata);
    delete state;
    state = nullptr;
}
extern "C" void fixture_start() {
    state = new State;
    if (std::atexit(driver_exit)) std::abort();
}
extern "C" void fixture_release(const char *kind) {
    // Actual mapped code still faults after its driver state has been finalized,
    // matching candidate9's mapped glsi dereference of a null state + 0x40.
    if (!state) {
        std::fprintf(stderr, "late-driver-call %s\n", kind);
        *reinterpret_cast<volatile unsigned *>(0x40) = 1;
    }
    if (!std::strcmp(kind, "command")) ++state->commands;
    else if (!std::strcmp(kind, "metadata")) ++state->metadata;
    else ++state->textures;
    std::fprintf(stderr, "release %s\n", kind);
}
__attribute__((destructor)) static void library_exit() {
    std::fprintf(stderr, "normal-library-finalizer\n");
}
'''
APPLICATION = r'''
#include "nvidia_dispatch_lifetime.hpp"
#include "nvidia_output_cleanup.hpp"
#include <array>
#include <cassert>
#include <cstdlib>
#include <memory>
#include <vector>
static void (*release_resource)(const char *);
struct Texture { ~Texture() { release_resource("texture"); } };
struct Metadata { ~Metadata() { release_resource("metadata"); } };
struct Command {
    std::shared_ptr<Texture> texture;
    ~Command() { release_resource("command"); }
};
struct Output {
    std::vector<std::shared_ptr<Texture>> outputImages, outputImagesPartialOverlay;
    std::array<std::shared_ptr<Texture>, 2> pScreenshotImages;
    std::shared_ptr<Texture> temporaryHackyBlankImage, tmpOutput, nisScalerImage, nisUsmImage;
    std::shared_ptr<Metadata> swapchainHDRMetadata;
} output; // Same global registration order as gamescope's g_output/g_device.
struct Device {
    std::vector<std::unique_ptr<Command>> pending, unused;
    bool waited = false;
    void waitIdle() {
        waited = true;
        std::fprintf(stderr, "gpu-drained\n");
        for (auto &command : pending) {
            command->texture.reset();
            unused.push_back(std::move(command));
        }
        pending.clear(); // waitIdle keeps cached commands, as in production.
    }
    void releaseCommandBuffers() {
        assert(waited);
        pending.clear();
        unused.clear();
    }
} device;
static std::shared_ptr<Texture> effect, upscale;
static void cleanup() {
    release_nvidia_output_before_driver_exit(device, output, []() {
        effect.reset(); upscale.reset();
    });
    assert(device.pending.empty() && device.unused.empty());
    assert(output.outputImages.empty() && output.outputImagesPartialOverlay.empty());
    assert(!output.pScreenshotImages[0] && !output.pScreenshotImages[1]);
    assert(!output.temporaryHackyBlankImage && !output.tmpOutput);
    assert(!output.nisScalerImage && !output.nisUsmImage && !output.swapchainHDRMetadata);
    std::fprintf(stderr, "early-cleanup-complete\n");
}
int main(int argc, char **argv) {
    assert(argc == 3);
    void *driver = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    assert(driver);
    auto start = reinterpret_cast<void (*)()>(dlsym(driver, "fixture_start"));
    release_resource = reinterpret_cast<void (*)(const char *)>(dlsym(driver, "fixture_release"));
    assert(start && release_resource);
    start(); // Driver state finalizer registers after global client destructors.
    assert(retain_nvidia_dispatch_owner(0x10de, reinterpret_cast<const void *>(release_resource))
           == NvidiaDispatchLifetime::Retained);
    assert(dlclose(driver) == 0);
    bool empty = !std::strcmp(argv[2], "empty");
    bool output_only = !std::strcmp(argv[2], "late-output");
    if (!empty) {
        output.outputImages.push_back(std::make_shared<Texture>());
        output.outputImagesPartialOverlay.push_back(std::make_shared<Texture>());
        for (auto &image : output.pScreenshotImages) image = std::make_shared<Texture>();
        output.temporaryHackyBlankImage = std::make_shared<Texture>();
        output.tmpOutput = std::make_shared<Texture>();
        output.nisScalerImage = std::make_shared<Texture>();
        output.nisUsmImage = std::make_shared<Texture>();
        if (!output_only) output.swapchainHDRMetadata = std::make_shared<Metadata>();
        if (!output_only) {
            effect = std::make_shared<Texture>(); upscale = std::make_shared<Texture>();
            auto command = std::make_unique<Command>();
            command->texture = output.outputImages[0];
            device.pending.push_back(std::move(command));
            device.unused.push_back(std::make_unique<Command>());
        }
    }
    if (!std::strcmp(argv[2], "early") || !std::strcmp(argv[2], "twice") || empty) {
        cleanup();
        if (!std::strcmp(argv[2], "twice")) cleanup();
    }
    return 0; // Ordinary exit handlers and library finalizers remain enabled.
}
'''


@unittest.skipUnless(sys.platform.startswith("linux") and shutil.which("c++"),
                     "requires Linux ELF C++ toolchain")
class GamescopeOutputCleanupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temporary.name)
        for name in ("nvidia_dispatch_lifetime.hpp", "nvidia_output_cleanup.hpp"):
            shutil.copyfile(ROOT / "os/gamescope" / name, cls.root / name)
        (cls.root / "driver.cpp").write_text(LIBRARY)
        (cls.root / "application.cpp").write_text(APPLICATION)
        cls.library = cls.root / "libnvidia-eglcore.so.610.43.03"
        cls.application = cls.root / "application"
        common = ["c++", "-std=c++17", "-Wall", "-Wextra", "-Werror"]
        subprocess.run([*common, "-shared", "-fPIC", str(cls.root / "driver.cpp"),
                        "-o", str(cls.library)], check=True)
        subprocess.run([*common, str(cls.root / "application.cpp"), "-ldl",
                        "-o", str(cls.application)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def fixture(self, mode):
        def limits():
            # Negative controls fault only in this isolated regression process.
            resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        return subprocess.run([str(self.application), str(self.library), mode],
                              capture_output=True, text=True, timeout=5, preexec_fn=limits)

    def test_retained_code_still_faults_after_driver_state_exit(self):
        result = self.fixture("late")
        self.assertEqual(result.returncode, -signal.SIGSEGV, result.stderr)
        self.assertIn("driver-finalize commands=0 textures=0 metadata=0", result.stderr)
        self.assertIn("late-driver-call texture", result.stderr)

    def test_global_output_reproduces_candidate9_without_commands(self):
        result = self.fixture("late-output")
        self.assertEqual(result.returncode, -signal.SIGSEGV, result.stderr)
        self.assertIn("driver-finalize", result.stderr)
        self.assertIn("late-driver-call texture", result.stderr)

    def test_early_release_precedes_normal_driver_finalization(self):
        result = self.fixture("early")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("driver-finalize commands=2 textures=10 metadata=1", result.stderr)
        self.assertLess(result.stderr.index("gpu-drained"), result.stderr.index("release command"))
        self.assertLess(result.stderr.index("early-cleanup-complete"), result.stderr.index("driver-finalize"))
        self.assertIn("normal-library-finalizer", result.stderr)
        self.assertNotIn("late-driver-call", result.stderr)

    def test_cleanup_can_repeat_without_double_release(self):
        result = self.fixture("twice")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr.count("early-cleanup-complete"), 2)
        self.assertIn("driver-finalize commands=2 textures=10 metadata=1", result.stderr)

    def test_initialized_device_without_output_is_safe(self):
        result = self.fixture("empty")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("driver-finalize commands=0 textures=0 metadata=0", result.stderr)
        self.assertIn("normal-library-finalizer", result.stderr)


if __name__ == "__main__":
    unittest.main()
