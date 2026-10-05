"""Application input must be neutral whenever the appliance owns the pad."""
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("controller_router", Path(__file__).resolve().parents[1] /
    "os/files/usr/lib/marwanos/controller/router.py")
router = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(router)


class ControllerGateTests(unittest.TestCase):
    def test_linux_face_buttons_match_controller_positions(self):
        self.assertEqual(router.BUTTONS[304], 0)  # BTN_SOUTH: Cross / A
        self.assertEqual(router.BUTTONS[305], 1)  # BTN_EAST: Circle / B
        self.assertEqual(router.BUTTONS[308], 2)  # BTN_WEST: Square / X
        self.assertEqual(router.BUTTONS[307], 3)  # BTN_NORTH: Triangle / Y

    def test_shell_mode_neutralizes_every_application_control(self):
        gate = router.Gate()
        self.assertEqual(gate.output([1] * 15, [1.] * 6), ([0] * 15, [0.] * 6))

    def test_resume_does_not_forward_held_menu_press_or_stick(self):
        gate = router.Gate()
        buttons, axes = [0] * 15, [0.] * 6
        buttons[0], axes[0] = 1, .9
        gate.set_active(True, buttons, axes)
        self.assertEqual(gate.output(buttons, axes), ([0] * 15, [0.] * 6))
        gate.output([0] * 15, [0.] * 6)
        self.assertEqual(gate.output(buttons, axes), (buttons, axes))

    def test_home_controls_never_reach_game(self):
        gate = router.Gate()
        gate.set_active(True, [0] * 15, [0.] * 6)
        buttons = [1] * 15
        output, _ = gate.output(buttons, [0.] * 6)
        self.assertEqual(output[4:6], [0, 0])
        self.assertEqual(output[0], 1)

    def test_overlay_and_reconnect_do_not_leave_stuck_keys(self):
        gate = router.Gate()
        gate.set_active(True, [0] * 15, [0.] * 6)
        gate.output([1] * 15, [.8] * 6)
        gate.set_active(False, [1] * 15, [.8] * 6)
        self.assertEqual(gate.output([1] * 15, [.8] * 6), ([0] * 15, [0.] * 6))


if __name__ == "__main__":
    unittest.main()
