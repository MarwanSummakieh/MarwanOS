"""Real ELF lifetime regression for gamescope's exact production retention code."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest

if os.name == 'posix':
    import resource


ROOT = Path(__file__).resolve().parents[1]
HEADER = ROOT / 'os/gamescope/nvidia_dispatch_lifetime.hpp'
LIBRARY = r'''
#include <stdio.h>
int fixture_free_command_buffers(void) { return 42; }
__attribute__((destructor)) static void finalize(void) {
    fprintf(stderr, "library-finalizer\n");
}
'''
APPLICATION = r'''
#include "nvidia_dispatch_lifetime.hpp"
#include <cstdlib>
#include <cassert>
static void *driver;
static int (*dispatch)();
static bool call_after_close;
static bool expect_retained;
struct Device {
    ~Device() {
        Dl_info info = {};
        bool retained = dladdr(reinterpret_cast<const void *>(dispatch), &info);
        std::fprintf(stderr, "client-cleanup mapped=%d\n", retained);
        if (call_after_close) {
            int result = dispatch();
            assert(result == 42);
            std::fprintf(stderr, "client-cleanup result=%d\n", result);
        } else {
            assert(retained == expect_retained);
        }
    }
} device;
static void driver_exit() {
    std::fprintf(stderr, "driver-close\n");
    assert(dlclose(driver) == 0);
}
int main(int argc, char **argv) {
    assert(argc == 4);
    driver = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    assert(driver);
    dispatch = reinterpret_cast<int (*)()>(dlsym(driver, "fixture_free_command_buffers"));
    assert(dispatch && dispatch() == 42);
    int mode = std::atoi(argv[2]);
    // Registered after the global device destructor: this reproduces the
    // driver's earlier exit handler unloading a saved client dispatch pointer.
    assert(std::atexit(driver_exit) == 0);
    auto result = mode == 0 ? NvidiaDispatchLifetime::NotApplicable :
        retain_nvidia_dispatch_owner(std::strtoul(argv[3], nullptr, 16),
                                    reinterpret_cast<const void *>(dispatch));
    expect_retained = result == NvidiaDispatchLifetime::Retained;
    call_after_close = mode < 2;
    std::fprintf(stderr, "retention-result=%d\n", static_cast<int>(result));
    const char *ldpath = std::getenv("LD_LIBRARY_PATH");
    assert(ldpath && std::strcmp(ldpath, "/fixture/unchanged path") == 0);
    return 0;
}
'''


@unittest.skipUnless(sys.platform.startswith('linux') and shutil.which('c++') and shutil.which('cc'),
                     'requires Linux ELF C/C++ toolchain')
class GamescopeDriverLifetimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temporary.name)
        (cls.root / 'library.c').write_text(LIBRARY)
        (cls.root / 'application.cpp').write_text(APPLICATION)
        shutil.copyfile(HEADER, cls.root / HEADER.name)
        cls.normal = cls.root / 'libnvidia-eglcore.so.610.43.03'
        cls.other = cls.root / 'libother-driver.so.610.43.03'
        cls.malformed = cls.root / 'libnvidia-eglcore.so.610..43'
        for library in (cls.normal, cls.other, cls.malformed):
            subprocess.run(['cc', '-shared', '-fPIC', '-Wall', '-Wextra', '-Werror',
                            str(cls.root / 'library.c'), '-o', str(library)], check=True)
        cls.application = cls.root / 'application'
        subprocess.run(['c++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
                        str(cls.root / 'application.cpp'), '-ldl', '-o',
                        str(cls.application)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_fixture(self, library, mode, vendor='10de'):
        def fixture_limits():
            # The negative control intentionally faults in an isolated fixture;
            # no system core policy or real compositor setting is changed.
            resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        arguments = [str(self.application), str(library), str(mode), vendor]
        with subprocess.Popen(arguments,
                              env=dict(os.environ, LD_LIBRARY_PATH='/fixture/unchanged path'),
                              preexec_fn=fixture_limits, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True) as process:
            try:
                stdout, stderr = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
                raise
            result = subprocess.CompletedProcess(arguments, process.returncode, stdout, stderr)
            result.pid = process.pid
            return result

    def test_unretained_real_exit_faults_after_driver_close(self):
        result = self.run_fixture(self.normal, 0)
        self.assertEqual(result.returncode, -signal.SIGSEGV, result.stderr)
        self.assertIn('driver-close\nlibrary-finalizer\nclient-cleanup mapped=0', result.stderr)

    def test_retained_saved_dispatch_survives_real_exit_order(self):
        result = self.run_fixture(self.normal, 1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f'through compositor teardown pid={result.pid}\n', result.stderr)
        self.assertIn('retention-result=1', result.stderr)
        self.assertIn('driver-close\nclient-cleanup mapped=1\nclient-cleanup result=42\nlibrary-finalizer', result.stderr)

    def test_other_gpu_has_ordinary_unload(self):
        result = self.run_fixture(self.normal, 2, '1002')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('retention-result=0', result.stderr)
        self.assertIn('client-cleanup mapped=0', result.stderr)

    def test_unrelated_owner_is_not_retained(self):
        result = self.run_fixture(self.other, 2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('retention-result=2', result.stderr)
        self.assertIn('outside diagnosed eglcore scope', result.stderr)
        self.assertIn('client-cleanup mapped=0', result.stderr)

    def test_malformed_version_is_not_retained(self):
        result = self.run_fixture(self.malformed, 2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('retention-result=2', result.stderr)
        self.assertIn('client-cleanup mapped=0', result.stderr)


if __name__ == '__main__':
    unittest.main()
