"""Native resolution and advertised refresh selection, independent of hardware."""
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "os/files/usr/lib/marwanos/display/x11-mode"
SPEC = importlib.util.spec_from_loader("x11_mode", importlib.machinery.SourceFileLoader("x11_mode", str(PATH)))
mode = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mode)


class X11ModeTests(unittest.TestCase):
    def test_pc1_uses_175_at_native_resolution_instead_of_preferred_60(self):
        query = """DP-2 connected 3440x1440+0+0 (normal)
   3440x1440 59.96*+ 174.96 119.96
   2560x1440 174.97 120.00 59.95
"""
        self.assertEqual(mode.selections(query), [("DP-2", "3440x1440", 174.96)])

    def test_inactive_outputs_are_not_enabled(self):
        self.assertEqual(mode.selections("DP-0 connected (normal)\n   1920x1080 60.00+\nHDMI-0 disconnected\n"), [])

    def test_no_preference_retains_current_resolution_and_excludes_interlaced(self):
        query = """HDMI-0 connected primary 1920x1080+0+0
   3840x2160 120.00
   1920x1080 60.00* 120.00 144.00i
"""
        self.assertEqual(mode.selections(query), [("HDMI-0", "1920x1080", 120.0)])


if __name__ == "__main__":
    unittest.main()
