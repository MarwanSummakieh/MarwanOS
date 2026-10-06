"""Exercise display recovery across terminal ownership and cleanup failure."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "os/files/usr/lib/marwanos/display/link-scrub"

# Model the measured tty lifecycle: greetd owns tty1 as player/0600 once back.
# Plain quit reopens that tty through the detailed theme; retained quit exits
# the deactivated daemon directly. The native SELinux comparison is documented
# separately, so this fixture does not pretend to emulate SELinux itself.
COMMAND = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ['SCRUB_STATE'])
s = json.loads(p.read_text())
name, args = Path(sys.argv[0]).name, sys.argv[1:]
s['calls'].append([name, *args])
status = 0
if name == 'systemctl':
    if args[0] == 'is-active': status = 0 if s['greetd'] else 3
    elif args[0] == 'stop': s['greetd'] = False; s['tty_owner'] = 'root'
    elif args[0] == 'start': s['greetd'] = True; s['tty_owner'] = 'player'
elif name == 'pgrep':
    status = 0 if (s['daemon'] if args[-1] == 'plymouthd' else s['greetd']) else 1
elif name == 'plymouthd': s['daemon'] = True
elif name == 'plymouth':
    if args == ['--ping']: status = 0 if s['daemon'] else 1
    elif args == ['deactivate']: s['deactivated'] = True
    elif args[0] == 'quit':
        if s['greetd'] and '--retain-splash' not in args:
            s['denied_reopen'] = True; status = 13
        elif s['fail_cleanup']: status = 7
        else: s['daemon'] = False
p.write_text(json.dumps(s))
sys.exit(status)
'''


@unittest.skipUnless(shutil.which("bash"), "bash is required for display lifecycle regression")
class LinkScrubCleanupTests(unittest.TestCase):
    def run_scrub(self, *, fail_cleanup=False, old_cleanup=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            commands = root / "bin"
            commands.mkdir()
            for name in ("systemctl", "pgrep", "plymouth", "plymouthd", "sleep"):
                executable = commands / name
                executable.write_text(COMMAND)
                executable.chmod(0o755)
            state = root / "state.json"
            state.write_text(json.dumps({"greetd": True, "daemon": False,
                                         "tty_owner": "player", "deactivated": False,
                                         "denied_reopen": False, "fail_cleanup": fail_cleanup,
                                         "calls": []}))
            source = SCRIPT.read_text().replace("/run/marwanos", str(root / "runtime"))
            if old_cleanup:
                source = source.replace("plymouth quit --retain-splash", "plymouth quit")
            script = root / "link-scrub"
            script.write_text(source)
            result = subprocess.run([shutil.which("bash"), str(script)], capture_output=True,
                                    text=True, timeout=10,
                                    env={**os.environ, "PATH": str(commands) + os.pathsep + os.environ["PATH"],
                                         "SCRUB_STATE": str(state)})
            return result, json.loads(state.read_text())

    def test_cleanup_exits_without_reopening_players_terminal(self):
        old, old_state = self.run_scrub(old_cleanup=True)
        self.assertNotEqual(old.returncode, 0)
        self.assertTrue(old_state["denied_reopen"])
        result, state = self.run_scrub()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(state["greetd"])
        self.assertEqual(state["tty_owner"], "player")
        self.assertTrue(state["deactivated"])
        self.assertFalse(state["denied_reopen"])
        self.assertFalse(state["daemon"])

    def test_cleanup_error_is_reported_without_losing_restored_session(self):
        result, state = self.run_scrub(fail_cleanup=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not quit the deactivated plymouthd", result.stdout)
        self.assertNotIn("plymouthd reaped", result.stdout)
        self.assertTrue(state["greetd"])
        self.assertEqual(state["tty_owner"], "player")


if __name__ == "__main__":
    unittest.main()
