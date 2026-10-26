"""Run the actual installer entrypoint; replace only its privileged BIB boundary."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/make-installer.sh'
DIGEST = 'sha256:' + '1234abcd' * 8


@unittest.skipUnless(sys.platform.startswith('linux') and shutil.which('bash'),
                     'installer entrypoint requires Linux bash/find')
class InstallerImageOriginTests(unittest.TestCase):
    def invoke(self, tag, expected=None, registry='ghcr.io', namespace='marwansummakieh'):
        with tempfile.TemporaryDirectory(prefix='installer origin ') as temporary:
            root = Path(temporary)
            tools = root / 'bin'
            tools.mkdir()
            capture = root / 'bib-argv.json'
            output = root / 'media output'
            public_key = root / 'fixture.pub'
            public_key.write_text('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA fixture\n')
            # No privilege escalation or real container process can occur. On
            # non-root CI the script's normal sudo boundary reaches this stub.
            sudo = tools / 'sudo'
            sudo.write_text('#!/bin/sh\n[ "$1" = podman ] || exit 90\nexec "$@"\n')
            sudo.chmod(0o700)
            podman = tools / 'podman'
            podman.write_text(f'#!{sys.executable}\n' + '''
import json, os, pathlib, sys
args = sys.argv[1:]
assert args[0] == 'run'
builder = args.index('quay.io/centos-bootc/bootc-image-builder:latest')
assert args[builder + 1] == 'build'
assert args[args.index('--type') + 1] == 'qcow2'
assert '--no-default-kernel-args' in args
pathlib.Path(os.environ['BIB_CAPTURE']).write_text(json.dumps(args))
# A labeled fixture artifact satisfies the entrypoint's real artifact check;
# this test proves BIB invocation, not an actual installed image manifest.
output = pathlib.Path(os.environ['OUT_DIR'])
artifact = output / 'fixture.qcow2'
artifact.write_bytes(b'BIB boundary fixture only; not a bootable image')
stamp = (output / 'bib-config.toml').stat().st_mtime_ns + 1_000_000
os.utime(artifact, ns=(stamp, stamp))
''')
            podman.chmod(0o700)
            environment = dict(os.environ, PATH=str(tools) + ':' + os.environ['PATH'],
                               TAG=tag, REGISTRY=registry, GHCR_USER=namespace,
                               IMAGE_NAME='marwanos', OUT_DIR=str(output),
                               SSH_KEY_FILE=str(public_key), BIB_CAPTURE=str(capture),
                               BENCH='no', ADMIN_PASSWORD_HASH='', ADMIN_USER='fixture')
            result = subprocess.run(['bash', str(SCRIPT), 'qcow2'], env=environment,
                                    capture_output=True, text=True, timeout=10)
            if expected is None:
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn('Invalid pinned TAG', result.stderr)
                self.assertFalse(capture.exists())
                self.assertFalse(output.exists())
            else:
                self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                arguments = json.loads(capture.read_text())
                self.assertEqual(arguments[-1], expected)
                self.assertIn('from ' + expected, result.stdout)
                self.assertTrue((output / 'bib-config.toml').is_file())
                self.assertTrue((output / 'fixture.qcow2').is_file())

    def test_tag_only_origin_unchanged(self):
        self.invoke('pc1-candidate-20261006-9',
                    'ghcr.io/marwansummakieh/marwanos:pc1-candidate-20261006-9')

    def test_pinned_candidate_passes_digest_only_to_actual_bib_command(self):
        self.invoke('pc1-candidate-20261006-9@' + DIGEST,
                    'ghcr.io/marwansummakieh/marwanos@' + DIGEST)

    def test_registry_port_and_nested_namespace_preserved(self):
        self.invoke('release-9@' + DIGEST,
                    'registry.example.test:5443/dept/team/marwanos@' + DIGEST,
                    registry='registry.example.test:5443', namespace='dept/team')

    def test_bad_digest_rejected_before_privileged_boundary(self):
        for digest in ('sha256:1234', 'sha256:' + 'G' * 64, DIGEST + '@extra'):
            with self.subTest(digest=digest):
                self.invoke('release-9@' + digest)

    def test_bad_tag_rejected_before_privileged_boundary(self):
        for tag in ('', '-bad', 'bad:tag', 'bad tag'):
            with self.subTest(tag=tag):
                self.invoke(tag + '@' + DIGEST)


if __name__ == '__main__':
    unittest.main()
