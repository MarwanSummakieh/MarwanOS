"""Safety contract for interactive media transformation; never opens a disk."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "brand_installer", Path(__file__).resolve().parents[1] / "scripts/brand-installer.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
CONTROLLER_SPEC = importlib.util.spec_from_file_location(
    "installer_controller", Path(__file__).resolve().parents[1] / "os/installer/controller.py")
CONTROLLER = importlib.util.module_from_spec(CONTROLLER_SPEC)
CONTROLLER_SPEC.loader.exec_module(CONTROLLER)


class InteractiveMediaTests(unittest.TestCase):
    def test_unattended_source_cannot_select_disks_or_reboot(self):
        source = """%include /run/install/repo/osbuild-base.ks
user --name=marwan --groups=wheel
rootpw --lock --allow-ssh
sshkey --username=marwan "ssh-ed25519 example"
clearpart --all --initlabel
ignoredisk --only-use=sda
autopart --type=plain
reboot
%post
touch /var/marwanos/devmode
%end
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source.ks"
            path.write_text(source)
            output = MODULE.kickstart(path)
        self.assertIn("graphical\n", output)
        self.assertIn('sshkey --username=marwan "ssh-ed25519 example"', output)
        for command in ("clearpart", "ignoredisk", "autopart", "reboot", "%post", "devmode"):
            self.assertNotIn(command, output)

    def test_missing_identity_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source.ks"
            path.write_text("clearpart --all\n")
            with self.assertRaises(RuntimeError):
                MODULE.kickstart(path)

    def test_runtime_patch_rejects_unexpected_source(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source.py"
            path.write_text("different upstream implementation")
            with self.assertRaises(RuntimeError):
                MODULE.replace_once(path, "expected implementation", "replacement")
            self.assertEqual(path.read_text(), "different upstream implementation")

    def test_controller_releases_dpad_and_applies_stick_deadzone(self):
        bridge = CONTROLLER.Bridge.__new__(CONTROLLER.Bridge)
        events = []
        bridge.emit = lambda *args: events.append(args)
        device = {"held": set(), "ranges": {0: (-32768, 32767)}, "axes": {}}
        bridge.event(device, 3, 16, -1)
        bridge.event(device, 3, 16, 1)
        bridge.event(device, 3, 16, 0)
        self.assertEqual(events, [(1, 105, 1), (1, 105, 0), (1, 106, 1), (1, 106, 0)])
        self.assertEqual(device["held"], set())
        bridge.event(device, 3, 0, 100)
        self.assertEqual(device["axes"][0], 0)
        bridge.event(device, 3, 0, 32767)
        self.assertEqual(device["axes"][0], 1)

    def test_keyboard_button_never_submits_a_form(self):
        bridge = CONTROLLER.Bridge.__new__(CONTROLLER.Bridge)
        events = []
        bridge.emit = lambda *args: events.append(args)
        device = {"held": set()}
        bridge.event(device, 1, 307, 1)
        bridge.event(device, 1, 307, 0)
        self.assertEqual(events, [(1, 66, 1), (1, 66, 0)])


if __name__ == "__main__":
    unittest.main()
