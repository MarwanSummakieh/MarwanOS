import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("normal", ROOT / "scripts/verify-pc1-shutdown.py")
normal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(normal)
PRIOR = "5b5693c6-bb56-4b85-b7d5-527c013e653b"
CURRENT = "b92e5954-341e-4c95-be9d-419bb39f8e09"
COMMIT = "a" * 40
DIGEST = "sha256:" + "b" * 64

def row(message, when=150):
    return {"message": message, "time_usec": when, "pid": "inherited-stream-pid"}


class NormalShutdownTests(unittest.TestCase):
    def setUp(self):
        self.start = row('Stopping greetd.service - Greeter daemon...', 100)
        self.end = row('Stopped greetd.service - Greeter daemon.', 300)
        self.initial = row(normal.MARKER + '1514', 20)
        self.late = row(normal.MARKER + '2067', 200)

    def test_late_owner_is_separate_from_initial_scrub(self):
        self.assertTrue(normal.normal_cleanup([self.initial, self.late],
                                             [self.start, self.end], 2067, 90)[-1])
        self.assertFalse(normal.normal_cleanup([self.initial], [self.start, self.end], 2067, 90)[-1])

    def test_duplicates_and_out_of_order_markers_fail(self):
        for rows in ([self.late, self.late], [row(normal.MARKER + '2067', 90)],
                     [row(normal.MARKER + '2067', 310)]):
            with self.subTest(rows=rows):
                self.assertFalse(normal.normal_cleanup(rows, [self.start, self.end], 2067, 90)[-1])
        with self.assertRaises(ValueError):
            normal.normal_cleanup([row(normal.MARKER + 'bad')], [self.start], 2067, 90)

    def fixture(self, fault=None, denial=None, same_boot=False):
        args = argparse.Namespace(prior_boot=PRIOR, compositor_pid=2067,
                                  shutdown_after='2026-10-07T02:16:45Z', commit=COMMIT, digest=DIGEST)
        after = 1791339405000000
        def read(path, *unused, **kwargs):
            if str(path).endswith('boot_id'):
                return PRIOR if same_boot else CURRENT
            if str(path).endswith('build-info'):
                return 'MARWANOS_COMMIT=' + COMMIT[:7]
            raise AssertionError(str(path))
        def journal(boot, *filters, **kwargs):
            self.assertEqual(boot, PRIOR)
            if '-u' in filters:
                return [row(self.start['message'], after + 100), row(self.end['message'], after + 300)]
            if '--grep=' + normal.MARKER in filters:
                return [self.initial, row(normal.MARKER + '2067', after + 200)]
            if 'COREDUMP_EXE=/usr/bin/gamescope' in filters:
                return []
            if any('segfault|dumped core' in item for item in filters):
                return [row(fault)] if fault else []
            if '--grep=avc:.*denied' in filters:
                return [row(denial)] if denial else []
            if kwargs.get('latest_only'):
                return [row('boot available')]
            return []
        deployed = {'deployments': [{'booted': True, 'container-image-reference-digest': DIGEST}]}
        with patch.object(normal.Path, 'read_text', read), patch.object(normal, 'journal', journal), \
             patch.object(normal.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, json.dumps(deployed), '')):
            return normal.collect(args)

    def test_clean_normal_shutdown_passes_with_exit_status_unavailable(self):
        result = self.fixture()
        self.assertEqual(result['failure_count'], 0)
        self.assertEqual(result['exact_compositor_exit_status']['status'], 'unavailable')

    def test_kernel_segfault_without_structured_core_is_failure(self):
        result = self.fixture(fault='gamescope-wl[2067]: segfault at 40 ip 123 in driver')
        self.assertEqual(result['gamescope_coredumps'], [])
        self.assertEqual(result['failure_count'], 1)
        self.assertTrue(result['gamescope_faults'])

    def test_enforcing_avc_fails_and_permissive_is_reported(self):
        self.assertEqual(self.fixture(denial='avc: denied { open } permissive=0')['failure_count'], 1)
        result = self.fixture(denial='avc: denied { open } permissive=1')
        self.assertEqual(result['failure_count'], 0)
        self.assertEqual(result['permissive_avc_count'], 1)

    def test_same_boot_cannot_claim_completed_reboot(self):
        self.assertGreater(self.fixture(same_boot=True)['failure_count'], 0)

    def test_explicit_prior_boot_query_and_no_match(self):
        with patch.object(normal.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', '')) as command:
            self.assertEqual(normal.journal(PRIOR, '--grep=gamescope'), [])
        argv = command.call_args.args[0]
        self.assertIn('_BOOT_ID=' + PRIOR.replace('-', ''), argv)
        self.assertNotIn('-b', argv)
        self.assertNotIn('-1', argv)

    def test_query_failure_missing_binary_timeout_and_bad_json_fail_closed(self):
        for code in (0, 1, 2):
            with patch.object(normal.subprocess, 'run', return_value=subprocess.CompletedProcess([], code, '', 'query failed')):
                with self.assertRaises(ValueError):
                    normal.journal(PRIOR)
        for error in (FileNotFoundError('journalctl'), subprocess.TimeoutExpired(['journalctl'], 20)):
            with patch.object(normal.subprocess, 'run', side_effect=error), self.assertRaises(type(error)):
                normal.journal(PRIOR)
        for output in ('not json', '[]', json.dumps({'MESSAGE': 123, '_BOOT_ID': PRIOR.replace('-', ''), '__REALTIME_TIMESTAMP': '1'})):
            with patch.object(normal.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, output, '')):
                with self.assertRaises(ValueError):
                    normal.journal(PRIOR)


if __name__ == "__main__":
    unittest.main()
