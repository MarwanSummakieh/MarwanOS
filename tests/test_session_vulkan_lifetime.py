"""Exercise the actual session launch seam with disposable child processes."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


SESSION = Path(__file__).resolve().parents[1] / 'os/files/usr/lib/marwanos/session/marwanos-session'
SETTING = 'VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING'


class SessionVulkanLifetimeTests(unittest.TestCase):
    def run_launch(self, device):
        source = SESSION.read_text()
        # Execute the production preamble and production launch function, without
        # entering the real session, invoking DRM or changing any user services.
        preamble = source[source.index('set -u\n'):source.index('readonly TAG=')]
        launch = re.search(r'(?ms)^launch_gamescope_process\(\) \{\n.*?^\}', source)
        self.assertIsNotNone(launch)
        self.assertIn('    launch_gamescope_process "$@"', source)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake = root / 'gamescope'
            fake.write_text(
                '#!/usr/bin/python3\nimport json, os, sys\n'
                'from pathlib import Path\n'
                'Path(os.environ["CAPTURE"]).write_text(json.dumps({'
                '"pid":os.getpid(), "args":sys.argv[1:], '
                f'"setting":os.environ.get("{SETTING}")' + '}))\n'
                'sys.exit(17)\n')
            fake.chmod(0o700)
            script = root / 'launch.sh'
            script.write_text(
                preamble + '\n' + launch.group() + '\n'
                'VK_DEVICE="$1"\nshift\n'
                'launch_gamescope_process "$@"\n'
                'wait "$GAMESCOPE_PID"\nstatus=$?\n'
                'printf "%s %s\\n" "$GAMESCOPE_PID" "$status"\n'
                # Two separately launched clients model the actual shell/Steam/
                # Proton sibling environment, not gamescope-owned Xwayland.
                f'/usr/bin/python3 -c \'import os; print(repr(os.environ.get("{SETTING}")))\'\n'
                f'/usr/bin/python3 -c \'import os; print(repr(os.environ.get("{SETTING}")))\'\n')
            environment = dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'],
                               CAPTURE=str(root / 'capture.json'))
            environment[SETTING] = 'inherited-poison'
            arguments = ['--backend', 'drm', '--ready-fd', '/tmp/path with spaces',
                         '--prefer-vk-device', device, '--force-composition']
            completed = subprocess.run(['/bin/sh', str(script), device, *arguments],
                                       env=environment, capture_output=True, text=True,
                                       timeout=10, check=True)
            capture = json.loads((root / 'capture.json').read_text())
            lines = completed.stdout.splitlines()
            self.assertEqual(lines, [f'{capture["pid"]} 17', 'None', 'None'])
            self.assertEqual(capture['args'], arguments)
            return capture['setting']

    def test_nvidia_receives_workaround_only_in_compositor(self):
        self.assertEqual(self.run_launch('10de:2488'), '1')

    def test_other_gpu_never_receives_inherited_workaround(self):
        self.assertIsNone(self.run_launch('1002:73bf'))

    def test_unselected_gpu_never_receives_inherited_workaround(self):
        self.assertIsNone(self.run_launch(''))


if __name__ == '__main__':
    unittest.main()
