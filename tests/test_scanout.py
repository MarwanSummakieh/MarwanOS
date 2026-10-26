"""Reject the real false-ready case where only fbcon is being scanned out."""
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('pc1_scanout', Path(__file__).resolve().parents[1] / 'scripts/inspect-pc1-scanout.py')
scanout = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scanout)

def state(owner='gamescope-xwm', modifier='0x0'):
    return f'''plane[54]: plane-0
\tcrtc=crtc-0
\tfb=846
\t\tallocated by = {owner}
\t\tformat=XR24 little-endian (0x34325258)
\t\tmodifier={modifier}
plane[194]: plane-1
\tcrtc=(null)
\tfb=0
crtc[200]: crtc-0
\tactive=1
'''

class ScanoutTests(unittest.TestCase):
    def test_console_framebuffer_is_not_a_compositor_pass(self):
        self.assertFalse(scanout.inspect_scanout(state('[fbcon]'), True)['passed'])

    def test_actual_linear_compositor_frame_is_required(self):
        result = scanout.inspect_scanout(state(), True)
        self.assertTrue(result['passed'], result)
        self.assertEqual(len(result['active']), 1)
        self.assertEqual(result['active'][0]['modifier'], 0)

    def test_tiled_output_is_valid_only_when_linear_is_not_required(self):
        tiled = state(modifier='0x300000000606014')
        self.assertTrue(scanout.inspect_scanout(tiled)['passed'])
        self.assertFalse(scanout.inspect_scanout(tiled, True)['passed'])

    def test_absent_or_unreadable_framebuffer_evidence_fails(self):
        self.assertFalse(scanout.inspect_scanout('plane[54]: plane-0\n\tcrtc=(null)\n\tfb=0\n')['passed'])
        self.assertFalse(scanout.inspect_scanout(state().replace('\t\tmodifier=0x0\n', ''), True)['passed'])

    def test_assigned_buffer_on_inactive_crtc_is_not_scanned_out(self):
        self.assertFalse(scanout.inspect_scanout(state().replace('active=1', 'active=0'))['passed'])

if __name__ == '__main__':
    unittest.main()
