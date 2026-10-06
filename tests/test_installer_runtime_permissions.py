"""Exercise actual SquashFS extraction under a private caller umask."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/extract-installer-runtime.py"


@unittest.skipUnless(shutil.which("mksquashfs") and shutil.which("unsquashfs"),
                     "SquashFS tools required for runtime permission regression")
class InstallerRuntimePermissionsTests(unittest.TestCase):
    def fixture(self, directory, private_library=False):
        root = directory / "source"
        for name in ("etc", "usr/bin", "usr/lib", "usr/lib64", "usr/libexec", "usr/share"):
            (root / name).mkdir(parents=True, exist_ok=True, mode=0o755)
        (root / "root/.ssh").mkdir(parents=True, mode=0o700)
        (root / "root/.ssh").chmod(0o700)
        secret = root / "root/.ssh/authorized_keys"
        secret.write_text("public-key-fixture\n")
        secret.chmod(0o600)
        if private_library:
            (root / "usr/lib64").chmod(0o700)
        image = directory / "runtime.img"
        subprocess.run(["mksquashfs", str(root), str(image), "-noappend", "-processors", "1",
                        "-no-progress"], check=True, stdout=subprocess.DEVNULL)
        return image

    def run_extraction(self, image, destination):
        previous = os.umask(0o077)
        try:
            return subprocess.run([sys.executable, str(SCRIPT), str(image), str(destination)],
                                  capture_output=True, text=True)
        finally:
            os.umask(previous)

    def test_private_caller_umask_does_not_block_dbus_user_or_expose_private_files(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            image = self.fixture(directory)
            target = directory / "runtime"
            result = self.run_extraction(image, target)
            self.assertEqual(result.returncode, 0, result.stderr)
            for name in (".", "etc", "usr", "usr/lib64", "usr/share"):
                self.assertEqual((target / name).stat().st_mode & 0o005, 0o005, name)
            self.assertEqual((target / "root/.ssh").stat().st_mode & 0o777, 0o700)
            self.assertEqual((target / "root/.ssh/authorized_keys").stat().st_mode & 0o777, 0o600)

    def test_upstream_runtime_with_inaccessible_library_directory_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            image = self.fixture(directory, private_library=True)
            result = self.run_extraction(image, directory / "runtime")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("not publicly traversable: usr/lib64", result.stderr)


if __name__ == "__main__":
    unittest.main()
