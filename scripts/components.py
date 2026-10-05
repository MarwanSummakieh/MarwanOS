#!/usr/bin/env python3
"""Verify or refresh PC1's pinned component integration copies."""
import argparse
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "pc1-components.json"


def git(*args, cwd=ROOT):
    return subprocess.check_output(["git", *args], cwd=cwd)


def checked_path(relative):
    path = PurePosixPath(relative)
    if path.is_absolute() or not path.parts or ".." in path.parts or "\\" in relative:
        raise ValueError(f"Unsafe component path: {relative}")
    target = ROOT.joinpath(*path.parts)
    if not target.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError(f"Component path escapes repository: {relative}")
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--verify", action="store_true")
    action.add_argument("--sync", action="store_true")
    parser.add_argument("--component", help="Only process this component")
    parser.add_argument("--source", type=Path, help="Component checkout for --sync")
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    if lock.get("schema_version") != 1:
        parser.error("Unsupported component lock format")
    components = lock["components"]
    if args.component:
        if args.component not in components:
            parser.error("Unknown component")
        components = {args.component: components[args.component]}
    if args.sync and (not args.source or not args.component):
        parser.error("--sync requires --component and --source")
    owners = {}
    problems = []
    for name, component in lock["components"].items():
        if not re.fullmatch(r"[0-9a-f]{40}", component["commit"]):
            raise ValueError(f"Invalid commit for {name}")
        for relative, blob in component["files"].items():
            checked_path(relative)
            if relative in owners:
                raise ValueError(f"Duplicate ownership: {relative}")
            if not re.fullmatch(r"[0-9a-f]{40}", blob):
                raise ValueError(f"Invalid blob for {relative}")
            owners[relative] = name
    for name, component in components.items():
        if args.sync:
            revision = git("rev-parse", "HEAD", cwd=args.source).decode().strip()
            if revision != component["commit"]:
                parser.error("Source HEAD must equal the pinned component commit")
        for relative, blob in component["files"].items():
            target = checked_path(relative)
            if args.sync:
                actual = git("rev-parse", f"{component['commit']}:{relative}", cwd=args.source).decode().strip()
                if actual != blob:
                    raise ValueError(f"Pinned tree disagrees with lock: {relative}")
                data = git("show", f"{component['commit']}:{relative}", cwd=args.source)
                target.parent.mkdir(parents=True, exist_ok=True)
                with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as temp:
                    temp.write(data)
                    temporary = Path(temp.name)
                temporary.replace(target)
            if not target.is_file():
                problems.append(f"Missing: {relative}")
                continue
            actual = git("hash-object", "--path", relative, str(target)).decode().strip()
            if actual != blob:
                problems.append(f"Changed: {relative} (owned by {name})")
        print(f"{name}: {len(component['files'])} integration files at {component['commit'][:12]}")
    for problem in problems:
        print(problem, file=sys.stderr)
    return bool(problems)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
