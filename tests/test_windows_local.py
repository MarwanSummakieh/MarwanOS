"""General setup uses the session display and explicit library selection."""
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("local_manager", Path(__file__).resolve().parents[1] /
    "os/files/usr/lib/marwanos/windows/manager.py")
manager = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manager)


def pe():
    header = bytearray(64)
    header[:2] = b"MZ"
    struct.pack_into("<I", header, 60, 64)
    return header + b"PE\0\0"


class LocalSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="local setup spaces ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = self.root / "state"
        self.source = self.root / "Game $(literal) ' Setup.EXE"
        self.source.write_bytes(pe())
        (self.root / "setup.bin").write_bytes(b"multipart data")
        self.runner = self.root / "runner"
        self.runner.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys, time
p = pathlib.Path(os.environ['WINEPREFIX'])
(p / 'invocation.json').write_text(json.dumps({'argv': sys.argv[1:], 'cwd': os.getcwd(), 'display': os.getenv('DISPLAY'), 'wayland': os.getenv('WAYLAND_DISPLAY'), 'sibling': pathlib.Path('setup.bin').exists()}))
if os.getenv('HANG_SETUP'):
    subprocess = __import__('subprocess')
    child = subprocess.Popen(['/bin/sleep', '60'])
    (p / 'child.pid').write_text(str(child.pid))
    time.sleep(60)
if os.getenv('EMPTY_SETUP'):
    sys.exit(0)
for name in ['Program Files/Example/Game.exe', 'Program Files/Example/unins000.exe', 'windows/notepad.exe', 'users/steamuser/AppData/Local/Example/Client.exe']:
    exe = p / 'drive_c' / name
    exe.parent.mkdir(parents=True, exist_ok=True)
    exe.write_bytes(pathlib.Path(os.environ['FIXTURE_EXE']).read_bytes())
sys.exit(int(os.getenv('SETUP_EXIT', '0')))
''')
        self.runner.chmod(0o755)
        self.env = dict(os.environ, MARWANOS_WINDOWS_HOME=str(self.base),
                        MARWANOS_WINDOWS_RUNTIME=str(self.runner), FIXTURE_EXE=str(self.source),
                        DISPLAY=":fixture-tv", WAYLAND_DISPLAY="wayland-fixture")

    def run_setup(self, key="local-test", source=None, command="setup", **env):
        return subprocess.run([sys.executable, str(manager.__file__), command, key, str(source or self.source)],
                              env=dict(self.env, **env), capture_output=True, text=True, timeout=15)

    def job(self, key="local-test"):
        return manager.read_json(self.base / "jobs" / (key + ".json"), {})

    def test_unknown_exe_session_display_siblings_selection_and_library(self):
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        job = self.job()
        self.assertEqual(job['status'], 'select')
        self.assertEqual(len(job['choices']), 2)
        self.assertFalse(list((self.base / 'apps').glob('*.json')))
        invocation = manager.read_json(self.base / 'prefixes/local-test/invocation.json', {})
        self.assertEqual(invocation['argv'], [str(self.source)])
        self.assertEqual(invocation['cwd'], str(self.root))
        self.assertEqual(invocation['display'], ':fixture-tv')
        self.assertEqual(invocation['wayland'], 'wayland-fixture')
        self.assertTrue(invocation['sibling'])
        choice = next(c for c in job['choices'] if c['title'] == 'Game')
        self.assertEqual(manager.register_local(self.base, 'local-test', choice['id']), 0)
        entry = manager.read_json(self.base / 'apps/local-test.json', {})
        self.assertEqual(entry['title'], 'Game')
        self.assertEqual(entry['exec'], [manager.HELPER, 'launch', 'local-test'])
        self.assertEqual(entry['prefix'], str(self.base / 'prefixes/local-test'))

    def test_msi_uses_msiexec_and_argument_boundaries(self):
        source = self.root / 'installer with spaces.MSI'
        source.write_bytes(bytes.fromhex('d0cf11e0a1b11ae1') + b'fixture')
        result = self.run_setup(source=source)
        self.assertEqual(result.returncode, 0, result.stderr)
        invocation = manager.read_json(self.base / 'prefixes/local-test/invocation.json', {})
        self.assertEqual(invocation['argv'], ['msiexec', '/i', 'Z:' + str(source).replace('/', '\\')])

    def test_invalid_file_and_fifo_never_run(self):
        self.source.write_bytes(b'not a windows file')
        self.assertEqual(self.run_setup().returncode, 1)
        self.assertEqual(self.job()['status'], 'failed')
        fifo = self.root / 'fifo.exe'
        os.mkfifo(fifo)
        self.assertEqual(self.run_setup('local-fifo', fifo).returncode, 1)
        self.assertFalse((self.base / 'prefixes/local-fifo/invocation.json').exists())

    def test_failure_and_empty_setup_do_not_publish(self):
        self.run_setup(SETUP_EXIT='1')
        self.assertEqual(self.job()['status'], 'failed')
        self.assertFalse(list((self.base / 'apps').glob('*.json')))
        self.run_setup('local-empty', EMPTY_SETUP='1')
        self.assertEqual(self.job('local-empty')['status'], 'empty')
        self.assertFalse(list((self.base / 'apps').glob('*.json')))

    def test_selection_rejects_traversal_and_symlinks(self):
        self.run_setup()
        prefix = self.base / 'prefixes/local-test'
        (prefix / 'drive_c/linked.exe').symlink_to(self.source)
        (prefix / 'drive_c/outside').symlink_to(self.root, target_is_directory=True)
        builtin = prefix / 'drive_c/Program Files/Internet Explorer/iexplore.exe'
        builtin.parent.mkdir(parents=True)
        builtin.write_bytes(pe() + b'Wine builtin DLL')
        self.assertEqual(manager.register_local(self.base, 'local-test', '../../bad.exe'), 1)
        self.assertEqual(manager.register_local(self.base, 'local-test', 'drive_c/linked.exe'), 1)
        self.assertEqual(len(manager.local_candidates(prefix)), 2)

    def test_portable_keeps_original_folder_and_does_not_execute(self):
        result = self.run_setup(command='portable')
        self.assertEqual(result.returncode, 0, result.stderr)
        entry = manager.read_json(self.base / 'apps/local-test.json', {})
        self.assertEqual(entry['executable'], str(self.source))
        self.assertFalse((self.base / 'prefixes/local-test/invocation.json').exists())

    def test_close_cancels_setup_and_keeps_partial_prefix(self):
        process = subprocess.Popen([sys.executable, str(manager.__file__), 'setup', 'local-test', str(self.source)],
                                   env=dict(self.env, HANG_SETUP='1'))
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        child_path = self.base / 'prefixes/local-test/child.pid'
        for _ in range(200):
            if child_path.exists():
                break
            time.sleep(.02)
        self.assertTrue(child_path.exists())
        manager.stop_app(self.base, 'local-test')
        process.wait(timeout=10)
        self.assertEqual(self.job()['status'], 'cancelled')
        self.assertFalse(list((self.base / 'apps').glob('*.json')))
        self.assertTrue(child_path.parent.exists())
        self.assertFalse((self.base / 'running/local-test.json').exists())

    def test_remove_managed_app_deletes_only_its_prefix(self):
        self.run_setup()
        choice = self.job()['choices'][0]['id']
        manager.register_local(self.base, 'local-test', choice)
        unrelated = self.base / 'prefixes/local-other'
        unrelated.mkdir()
        manager.remove_app(self.base, 'local-test')
        self.assertFalse((self.base / 'prefixes/local-test').exists())
        self.assertFalse((self.base / 'apps/local-test.json').exists())
        self.assertFalse((self.base / 'jobs/local-test.json').exists())
        self.assertTrue(self.source.exists())
        self.assertTrue(unrelated.exists())

    def test_remove_portable_preserves_original_files(self):
        self.run_setup(command='portable')
        manager.remove_app(self.base, 'local-test')
        self.assertEqual(self.source.read_bytes(), pe())
        self.assertTrue((self.root / 'setup.bin').exists())

    def test_remove_rejects_external_prefix_and_symlink(self):
        self.run_setup(command='portable')
        entry_path = self.base / 'apps/local-test.json'
        entry = manager.read_json(entry_path, {})
        entry['prefix'] = str(self.root)
        manager.atomic_json(entry_path, entry)
        with self.assertRaises(manager.InstallError):
            manager.remove_app(self.base, 'local-test')
        entry['prefix'] = str(self.base / 'prefixes/local-test')
        manager.atomic_json(entry_path, entry)
        (self.base / 'prefixes/local-test').rmdir()
        (self.base / 'prefixes/local-test').symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(manager.InstallError):
            manager.remove_app(self.base, 'local-test')
        self.assertTrue(self.source.exists())
        self.assertTrue(entry_path.exists())

    def test_discard_partial_setup_keeps_installer(self):
        self.run_setup(EMPTY_SETUP='1')
        manager.discard_setup(self.base, 'local-test')
        self.assertFalse((self.base / 'prefixes/local-test').exists())
        self.assertFalse((self.base / 'jobs/local-test.json').exists())
        self.assertTrue(self.source.exists())

    def test_interrupted_local_setup_becomes_discardable_with_choices(self):
        self.run_setup()
        job = self.job()
        job.update(status='installing', created_at=time.time() - 60)
        manager.atomic_json(self.base / 'jobs/local-test.json', job)
        manager.cleanup_orphans(self.base)
        self.assertEqual(self.job()['status'], 'failed')
        self.assertEqual(len(self.job()['choices']), 2)

    def test_missing_prefix_metadata_cannot_leave_removal_in_progress(self):
        manager.atomic_json(self.base / 'apps/local-test.json', {'id': 'managed.local-test'})
        with self.assertRaises(manager.InstallError):
            manager.remove_app(self.base, 'local-test')

    def test_orphan_cleanup_signals_only_verified_runtime(self):
        process = subprocess.Popen(['/bin/sleep', '60'], start_new_session=True)
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        running = self.base / 'running/local-orphan.json'
        manager.atomic_json(running, {'pid': process.pid, 'start': manager.proc_start(process.pid),
                                     'owner': 2147483647, 'owner_start': 'missing'})
        manager.cleanup_orphans(self.base)
        process.wait(timeout=10)
        self.assertFalse(running.exists())
        self.assertNotEqual(process.returncode, 0)

    def test_orphan_cleanup_does_not_race_launch_record_replacement(self):
        process = subprocess.Popen(['/bin/sleep', '60'], start_new_session=True)
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        running = self.base / 'running/local-orphan.json'
        manager.atomic_json(running, {'pid': process.pid, 'start': manager.proc_start(process.pid),
                                     'owner': 2147483647, 'owner_start': 'missing'})
        with manager.exclusive(running.with_suffix('.lock')):
            manager.cleanup_orphans(self.base)
            self.assertTrue(running.exists())
            self.assertIsNone(process.poll())
        manager.cleanup_orphans(self.base)
        process.wait(timeout=10)
        self.assertFalse(running.exists())

    def test_stop_signals_live_owner_even_when_leader_already_exited(self):
        manager.atomic_json(self.base / 'running/local-test.json',
                            {'pid': 2147483647, 'start': 'gone', 'owner': 567,
                             'owner_start': 'owner-start'})
        with patch.object(os, 'kill') as kill, patch.object(os, 'killpg') as killpg, \
                patch.object(manager, 'proc_start', side_effect=lambda pid: 'owner-start' if pid == 567 else None):
            manager.stop_app(self.base, 'local-test')
        kill.assert_called_once_with(567, manager.signal.SIGTERM)
        killpg.assert_not_called()

    def test_orphan_cleanup_reaps_descendant_after_group_leader_exits(self):
        prefix = self.base / 'prefixes/local-orphan'
        prefix.mkdir(parents=True)
        leader = subprocess.Popen([sys.executable, '-c',
            'import subprocess,time; p=subprocess.Popen(["/bin/sleep", "60"], stdout=subprocess.DEVNULL); print(p.pid, flush=True); time.sleep(.2)'],
            env=dict(os.environ, WINEPREFIX=str(prefix)), stdout=subprocess.PIPE, text=True, start_new_session=True)
        started = manager.proc_start(leader.pid)
        child = int(leader.stdout.readline())
        self.addCleanup(lambda: os.kill(child, manager.signal.SIGKILL) if manager.proc_start(child) else None)
        leader.wait(timeout=5)
        leader.stdout.close()
        running = self.base / 'running/local-orphan.json'
        manager.atomic_json(running, {'pid': leader.pid, 'start': started, 'owner': 2147483647,
                                     'owner_start': 'missing', 'prefix': str(prefix)})
        manager.cleanup_orphans(self.base)
        self.assertFalse(running.exists())
        for tick in range(50):
            state = Path(f'/proc/{child}/stat')
            if not state.exists() or state.read_text().rsplit(')', 1)[1].split()[0] == 'Z':
                break
            time.sleep(.02)
        else:
            self.fail('Orphan descendant remained alive')


if __name__ == '__main__':
    unittest.main()
