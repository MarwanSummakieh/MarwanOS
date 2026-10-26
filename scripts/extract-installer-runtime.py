#!/usr/bin/env python3
"""Extract an Anaconda runtime without inheriting private build-config modes."""
import os
from pathlib import Path
import subprocess
import sys


def extract(image, destination):
    destination = Path(destination)
    if destination.exists():
        raise RuntimeError("Installer extraction destination must be new")
    # unsquashfs creates writable parent directories using the process umask.
    # With 077, /usr and /usr/lib64 become 0700 and the system D-Bus broker
    # cannot execute after dropping privileges to the dbus account.
    os.umask(0o022)
    subprocess.run(["unsquashfs", "-d", str(destination), str(image)], check=True)
    for relative in (".", "etc", "usr", "usr/bin", "usr/lib", "usr/lib64",
                     "usr/libexec", "usr/share"):
        path = destination / relative
        if not path.is_dir() or path.stat().st_mode & 0o005 != 0o005:
            raise RuntimeError(f"Installer runtime directory is not publicly traversable: {relative}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: extract-installer-runtime.py install.img new-directory")
    extract(sys.argv[1], sys.argv[2])
