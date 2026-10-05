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
    def test_fresh_bib_base_identity_and_storage_are_sanitized_together(self):
        source = "%include /run/install/repo/osbuild-base.ks\nautopart --nohome --type=plain --fstype=xfs\nreboot --eject\n"
        post = """%post --erroronfail
set -e
bootc switch --mutate-in-place --transport registry ghcr.io/example/pc1:release
# used during automatic image testing as finished marker
if [ -c /dev/ttyS0 ]; then
  echo "Install finished" > /dev/ttyS0 || true
fi
%end"""
        base = """ostreecontainer --url=/run/install/repo/container --transport=oci
user --name marwan --groups wheel
sshkey --username marwan "ssh-ed25519 existing"
user --name root
rootpw --lock
lang en_US.UTF-8
keyboard us
timezone UTC
clearpart --all
network --device=link --bootproto=dhcp --onboot=on --activate
""" + post + "\n"
        with tempfile.TemporaryDirectory() as directory:
            main_path, base_path = Path(directory) / "main.ks", Path(directory) / "base.ks"
            main_path.write_text(source)
            base_path.write_text(base)
            main, patched_base = MODULE.kickstart_pair(main_path, base_path)
        self.assertIn("graphical\n", main)
        self.assertIn("user --name marwan --groups wheel\n", main)
        self.assertIn("rootpw --lock\n", main)
        self.assertIn('sshkey --username marwan "ssh-ed25519 existing"', main)
        self.assertNotIn("user --", patched_base)
        self.assertIn("ostreecontainer --url=/run/install/repo/container --transport=oci\n", patched_base)
        self.assertIn("lang en_US.UTF-8\nkeyboard us\ntimezone UTC\n", patched_base)
        self.assertIn(post + "\n", patched_base)
        directives = [line.split()[0] for line in (main + patched_base).splitlines()
                      if line.strip() and not line.lstrip().startswith("#")]
        self.assertTrue(MODULE.STORAGE_COMMANDS.isdisjoint(directives))
        self.assertTrue(MODULE.COMPLETION_COMMANDS.isdisjoint(directives))

    def test_old_main_identity_is_kept_and_all_base_disk_directives_removed(self):
        source = """%include /run/install/repo/osbuild-base.ks
user --name=marwan --groups=wheel
rootpw --lock --allow-ssh
ignoredisk --only-use=sda
reboot
%post
touch /var/marwanos/devmode
%end
"""
        base = """ostreecontainer --url=/run/install/repo/container --transport=oci
clearpart --all
zerombr
part / --fstype=xfs --ondisk=sda
bootloader --boot-drive=sda
autopart
shutdown
"""
        with tempfile.TemporaryDirectory() as directory:
            main_path, base_path = Path(directory) / "main.ks", Path(directory) / "base.ks"
            main_path.write_text(source)
            base_path.write_text(base)
            main, patched_base = MODULE.kickstart_pair(main_path, base_path)
        self.assertIn("user --name=marwan --groups=wheel", main)
        self.assertIn("rootpw --lock --allow-ssh", main)
        self.assertNotIn("devmode", main + patched_base)
        self.assertEqual([line for line in patched_base.splitlines() if line and not line.startswith("#")],
                         ["ostreecontainer --url=/run/install/repo/container --transport=oci"])

    def test_unvalidated_base_include_or_post_storage_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            main_path, base_path = Path(directory) / "main.ks", Path(directory) / "base.ks"
            main_path.write_text("user --name=marwan\n")
            for unsafe in ("%include /unsafe.ks\n", "%pre\nchoose_disk\n%end\n",
                           "%post\nbootc switch --mutate-in-place --transport registry registry/pc1:latest\nreboot\n%end\n",
                           "%post\nbootc switch --mutate-in-place --transport registry registry/pc1:latest\nrm -rf /target\n%end\n"):
                base_path.write_text("ostreecontainer --url=/run/install/repo/container --transport=oci\n" + unsafe)
                with self.subTest(unsafe=unsafe), self.assertRaises(RuntimeError):
                    MODULE.kickstart_pair(main_path, base_path)

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

    def test_button_style_dpad_tracks_arrows_and_unplug_releases(self):
        bridge = CONTROLLER.Bridge.__new__(CONTROLLER.Bridge)
        events = []
        bridge.emit = lambda *args: events.append(args)
        device = {"held": set()}
        for code, arrow in ((544, 103), (545, 108), (546, 105), (547, 106)):
            bridge.event(device, 1, code, 1)
            self.assertEqual(device["held"], {arrow})
            bridge.event(device, 1, code, 0)
            self.assertEqual(device["held"], set())
        self.assertEqual(events, [(1, arrow, value) for arrow in (103, 108, 105, 106)
                                  for value in (1, 0)])
        bridge.event(device, 1, 545, 1)
        bridge.devices = {99: device}
        device["path"] = "fixture"
        from unittest.mock import patch
        with patch.object(CONTROLLER.os, "close") as close:
            bridge.remove(99)
        close.assert_called_once_with(99)
        self.assertEqual(events[-2:], [(1, 108, 1), (1, 108, 0)])


if __name__ == "__main__":
    unittest.main()
