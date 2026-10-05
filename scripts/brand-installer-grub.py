#!/usr/bin/env python3
"""Brand the pinned installer menu and explicitly autoboot graphical setup."""
import re
import sys
from pathlib import Path


def brand(source):
    if "inst.cmdline" in source or "inst.text" in source:
        raise ValueError("Unsupported non-graphical source boot configuration")
    # Anaconda's first top-level entry is normal setup. Fail if an upstream
    # menu changes that order instead of silently autobooting another action.
    first = re.search(r"(?ms)^menuentry[^\n]*\{\n(.*?)^\}", source)
    if first is None or "inst.ks=" not in first[1] or any(
            argument in first[1] for argument in ("rd.live.check", "inst.rescue", "nomodeset")):
        raise ValueError("First installer menu entry is not normal graphical setup")
    if re.search(r"(?m)^submenu\b", source[:first.start()]):
        raise ValueError("Unsupported submenu before normal installer entry")
    timeout = re.findall(r"(?m)^set timeout=[^\n]+$", source)
    if len(timeout) != 1:
        raise ValueError("Expected exactly one installer timeout")
    # Replace positive timeouts as well as -1. The current BIB ISO uses 60.
    source = re.sub(r"(?m)^set default=[^\n]+\n?", "", source)
    source = source.replace(timeout[0], "set default=0\nset timeout=3")
    searches = [line for line in source.splitlines() if line.startswith("search --no-floppy")]
    if len(searches) != 1:
        raise ValueError("Expected exactly one installer root search")
    source = source.replace(searches[0], searches[0] + """
insmod gfxterm
insmod png
loadfont /boot/grub2/pc1.pf2
set gfxmode=1280x720,auto
terminal_output gfxterm
background_image /boot/grub2/pc1.png
set theme=/boot/grub2/pc1-theme.txt
export theme""")
    for old, new in (
            ("Install MarwanOS 43 in basic graphics mode", "PC1 setup - compatibility graphics"),
            ("Test this media & install MarwanOS 43", "Check installer media and set up PC1"),
            ("Install MarwanOS 43", "Set up PC1 - Powered by MarwanOS"),
            ("Rescue a MarwanOS system", "Recover an existing PC1 installation")):
        source = source.replace(old, new)
    return source


if __name__ == "__main__":
    work = Path(sys.argv[1])
    grub = brand((work / "source/grub.cfg").read_text())
    for path in ("EFI/BOOT/grub.cfg", "boot/grub2/grub.cfg"):
        (work / "patch" / path).write_text(grub)
