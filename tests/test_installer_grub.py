"""Autoboot policy and media-check preservation for the actual BIB menu layout."""
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location(
    "brand_installer_grub", Path(__file__).resolve().parents[1] / "scripts/brand-installer-grub.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SOURCE = """set timeout=60
search --no-floppy --set=root -l 'Fedora-S-dvd-x86_64-43'
menuentry 'Install MarwanOS 43' --class fedora {
 linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-43 inst.ks=hd:LABEL=Fedora-S-dvd-x86_64-43:/osbuild.ks quiet
 initrd /images/pxeboot/initrd.img
}
menuentry 'Test this media & install MarwanOS 43' --class fedora {
 linux /images/pxeboot/vmlinuz inst.ks=hd:LABEL=Fedora-S-dvd-x86_64-43:/osbuild.ks rd.live.check quiet
 initrd /images/pxeboot/initrd.img
}
submenu 'Troubleshooting -->' {
 menuentry 'Install MarwanOS 43 in basic graphics mode' {
  linux /images/pxeboot/vmlinuz inst.ks=hd:LABEL=Fedora-S-dvd-x86_64-43:/osbuild.ks nomodeset quiet
 }
}
"""


class InstallerBootTests(unittest.TestCase):
    def test_normal_setup_autoboots_and_media_check_is_preserved(self):
        branded = MODULE.brand("set default=1\n" + SOURCE)
        self.assertEqual(branded.count("set default="), 1)
        self.assertIn("set default=0\nset timeout=3\n", branded)
        self.assertNotIn("set timeout=60", branded)
        self.assertIn("menuentry 'Set up PC1 - Powered by MarwanOS'", branded)
        self.assertIn("menuentry 'Check installer media and set up PC1'", branded)
        self.assertEqual(branded.count("rd.live.check"), 1)
        # Root/payload labels and kernel command lines must remain byte-for-byte.
        before = [line for line in SOURCE.splitlines() if line.lstrip().startswith("linux ")]
        after = [line for line in branded.splitlines() if line.lstrip().startswith("linux ")]
        self.assertEqual(before, after)

    def test_indefinite_timeout_is_also_replaced(self):
        self.assertIn("set timeout=3", MODULE.brand(SOURCE.replace("timeout=60", "timeout=-1")))

    def test_non_graphical_or_media_check_default_is_rejected(self):
        for argument in ("inst.text", "inst.cmdline", "rd.live.check", "inst.rescue", "nomodeset"):
            with self.subTest(argument=argument), self.assertRaises(ValueError):
                MODULE.brand(SOURCE.replace("/osbuild.ks quiet", "/osbuild.ks " + argument + " quiet", 1))

    def test_ambiguous_timeout_or_root_search_is_rejected(self):
        for suffix in ("set timeout=2\n", "search --no-floppy --set=root -l other\n"):
            with self.assertRaises(ValueError):
                MODULE.brand(SOURCE + suffix)


if __name__ == "__main__":
    unittest.main()
