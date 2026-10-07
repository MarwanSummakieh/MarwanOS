#!/usr/bin/env python3
"""Read-only PC1 prior-boot shutdown proof; JSON stdout, failure exit 1.

Queries an explicit _BOOT_ID, never relative boot -1. No controls, writes,
signals, resets, suspend, package changes or service operations. Exact compositor
exit status is reported unavailable unless the journal actually records it.
"""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import sys

MARKER = 'marwanos: released NVIDIA embedded Vulkan output and command buffers before backend teardown pid='


def journal(boot, *filters, limit=100, latest_only=False):
    argv = ['journalctl', '--no-pager', '--all', '-o', 'json',
            '_BOOT_ID=' + boot.replace('-', ''), '-n', str(limit if latest_only else limit + 1), *filters]
    process = subprocess.run(argv, capture_output=True, text=True, encoding='utf-8', timeout=20)
    if process.returncode not in (0, 1) or process.stderr.strip():
        raise ValueError('journal query failed: ' + process.stderr.strip()[:600])
    records = []
    for line in process.stdout.splitlines():
        row = json.loads(line)
        if not isinstance(row, dict):
            raise ValueError('journal record is not an object')
        if row.get('_BOOT_ID') != boot.replace('-', ''):
            raise ValueError('journal returned an unexpected boot ID')
        message = row.get('MESSAGE')
        if isinstance(message, list):
            message = bytes(message).decode('utf-8', errors='strict')
        if not isinstance(message, str):
            raise ValueError('journal message is unreadable')
        records.append({'time_usec': int(row['__REALTIME_TIMESTAMP']),
                        'pid': row.get('_PID'), 'comm': row.get('_COMM'),
                        'unit': row.get('_SYSTEMD_UNIT'),
                        'message': message[:5000]})
    if len(records) > limit:
        raise ValueError('journal evidence exceeded bounded query limit')
    return records


def normal_cleanup(cleanups, greetd, pid, after_usec):
    parsed = []
    for row in cleanups:
        match = re.fullmatch(re.escape(MARKER) + r'([1-9][0-9]*)', row['message'])
        if not match:
            raise ValueError('malformed compositor cleanup marker')
        parsed.append(dict(row, compositor_pid=int(match.group(1))))
    owned = [row for row in parsed if row['compositor_pid'] == pid]
    stops = [row for row in greetd if row['time_usec'] >= after_usec
             and re.match(r'Stopping greetd\.service\b', row['message'])]
    ends = [row for row in greetd if row['time_usec'] >= after_usec
            and re.match(r'Stopped greetd\.service\b', row['message'])]
    valid = len(owned) == 1 and len(stops) == 1 and owned[0]['time_usec'] > stops[0]['time_usec']
    if ends:
        valid = valid and len(ends) == 1 and owned[0]['time_usec'] < ends[0]['time_usec']
    return parsed, owned, stops, ends, valid


def collect(args):
    current = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    after = int(datetime.datetime.strptime(args.shutdown_after, '%Y-%m-%dT%H:%M:%SZ')
                .replace(tzinfo=datetime.timezone.utc).timestamp() * 1_000_000)
    checks = []
    result = {'prior_boot_id': args.prior_boot, 'current_boot_id': current,
              'expected_source_commit': args.commit, 'expected_digest': args.digest,
              'normal_shutdown_compositor_pid': args.compositor_pid,
              'shutdown_after_utc': args.shutdown_after, 'checks': checks}

    def check(name, passed, detail=None):
        item = {'name': name, 'pass': bool(passed)}
        if detail is not None:
            item['detail'] = detail
        checks.append(item)

    check('machine has completed a different boot', current != args.prior_boot)
    build = dict(line.split('=', 1) for line in Path('/usr/share/marwanos/build-info').read_text().splitlines()
                 if '=' in line)
    baked = build.get('MARWANOS_COMMIT', '')
    check('current boot has expected source commit',
          bool(re.fullmatch(r'[a-f0-9]{7,40}', baked)) and args.commit.startswith(baked), baked)
    deployment = subprocess.run(['rpm-ostree', 'status', '--json'], capture_output=True,
                                text=True, encoding='utf-8', timeout=20)
    if deployment.returncode or deployment.stderr.strip():
        raise ValueError('image identity query failed: ' + deployment.stderr.strip()[:600])
    booted = [row for row in json.loads(deployment.stdout).get('deployments', []) if row.get('booted')]
    check('current boot has expected immutable digest', len(booted) == 1 and
          booted[0].get('container-image-reference-digest') == args.digest)
    available = journal(args.prior_boot, limit=1, latest_only=True)
    # Availability query needs one record only, rather than a truncation check.
    check('explicit prior boot journal is available', bool(available))
    greetd = journal(args.prior_boot, '-u', 'greetd.service', limit=100)
    cleanups = journal(args.prior_boot, '--grep=' + MARKER, limit=20)
    parsed, owned, stops, ends, okay = normal_cleanup(cleanups, greetd, args.compositor_pid, after)
    result['all_cleanup_markers'] = parsed
    result['normal_shutdown_cleanup'] = owned
    result['late_greetd_stop_requests'] = stops
    result['late_greetd_stopped_records'] = ends
    result['greetd_records'] = greetd
    check('exactly one recovered-compositor cleanup follows late normal stop', okay)
    result['upper_bound_evidence'] = ('Stopped greetd.service after cleanup' if ends else
                                     'unavailable: no late Stopped greetd.service journal record')
    result['shutdown_context'] = journal(args.prior_boot,
        '--since=' + args.shutdown_after.replace('T', ' ').replace('Z', ' UTC'),
        '--grep=marwanos|cleanup|Stopping.*(graphical|session)|Stopped.*(graphical|session)|Reached target.*(Shutdown|Reboot)',
        limit=400)
    denials = journal(args.prior_boot, '--grep=avc:.*denied', limit=50)
    result['enforcing_avcs'] = [row for row in denials
                              if not re.search(r'\bpermissive=1\b', row['message'])]
    result['permissive_avc_count'] = len(denials) - len(result['enforcing_avcs'])
    check('all prior-boot journal transports have no enforcing AVC', not result['enforcing_avcs'])
    result['gamescope_coredumps'] = journal(args.prior_boot, 'COREDUMP_EXE=/usr/bin/gamescope', limit=20)
    result['gamescope_faults'] = journal(args.prior_boot,
        r'--grep=gamescope[^\n]*(segfault|dumped core)|Process [0-9]+ \(gamescope[^)]*\).*dumped core', limit=20)
    check('prior boot has no gamescope structured core or SEGV record',
          not result['gamescope_coredumps'] and not result['gamescope_faults'])
    result['gpu_faults'] = journal(args.prior_boot,
        '--grep=NVRM: Xid|GPU has fallen|AER:.*(error|fatal|corrected)', limit=30)
    check('all prior-boot transports have no GPU Xid/fallen/AER fault', not result['gpu_faults'])
    result['exact_compositor_exit_status'] = {'status': 'unavailable',
        'reason': 'greetd lifecycle/cleanup markers do not supply exact gamescope process exit status; no status is inferred.'}
    result['limits'] = ['First-scrub compositor cleanup is retained as context but cannot satisfy the recovered PID gate.',
                        'Expected source/digest independently identify the current boot; prior image identity must also be preserved in its pre-reboot gate evidence.',
                        'Normal stop and cleanup ordering is journal evidence; physical display behavior and suspend are not tested.',
                        'No prior-boot records or machine state were modified.']
    check('current boot remained unchanged during collection',
          Path('/proc/sys/kernel/random/boot_id').read_text().strip() == current)
    result['failure_count'] = sum(not row['pass'] for row in checks)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host')
    parser.add_argument('--commit', required=True)
    parser.add_argument('--digest', required=True)
    parser.add_argument('--prior-boot', required=True)
    parser.add_argument('--compositor-pid', required=True, type=int)
    parser.add_argument('--shutdown-after', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-f0-9]{40}', args.commit) or not re.fullmatch(r'sha256:[a-f0-9]{64}', args.digest):
        parser.error('exact full source SHA and immutable digest required')
    if not re.fullmatch(r'[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}', args.prior_boot):
        parser.error('invalid explicit prior boot ID')
    if args.compositor_pid < 1 or not re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z', args.shutdown_after):
        parser.error('invalid compositor PID or UTC shutdown boundary')
    if args.host:
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9@._:-]*', args.host):
            parser.error('invalid SSH host')
        try:
            process = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10',
                args.host, 'python3', '-', '--prior-boot', args.prior_boot,
                '--compositor-pid', str(args.compositor_pid), '--shutdown-after', args.shutdown_after,
                '--commit', args.commit, '--digest', args.digest],
                input=Path(__file__).read_text(encoding='utf-8-sig'), text=True,
                encoding='utf-8', capture_output=True, timeout=180)
            if process.returncode not in (0, 1) or process.stderr.strip():
                raise ValueError('SSH inspection failed: ' + process.stderr.strip()[:600])
            result = json.loads(process.stdout)
            print(json.dumps(result, indent=2))
            return 1 if process.returncode or result.get('failure_count', 1) else 0
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            print(json.dumps({'failure_count': 1, 'incomplete': True, 'error': str(error)}))
            return 1
    try:
        result = collect(args)
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        result = {'failure_count': 1, 'incomplete': True, 'error': str(error),
                  'prior_boot_id': args.prior_boot}
    print(json.dumps(result, indent=2))
    return 1 if result['failure_count'] else 0


if __name__ == '__main__':
    sys.exit(main())
