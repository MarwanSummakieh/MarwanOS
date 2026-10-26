#!/usr/bin/env python3
"""Read-only validation of actual DRM scanout, independent of ready handshakes."""
import argparse
import json
from pathlib import Path
import re
import sys


def inspect_scanout(state, require_linear=False):
    active = []
    errors = []
    blocks = re.split(r"(?m)^(?=plane\[|crtc\[|connector\[|colorop\[)", state)
    active_crtcs = set()
    for block in blocks:
        if block.startswith("crtc[") and re.search(r"(?m)^\s*active=1$", block):
            active_crtcs.add(block.splitlines()[0].split(": ", 1)[1])
    for block in blocks:
        if not block.startswith("plane["):
            continue
        crtc = re.search(r"(?m)^\s*crtc=(.+)$", block)
        fb = re.search(r"(?m)^\s*fb=(\d+)$", block)
        if not crtc or crtc[1] == "(null)" or not fb or int(fb[1]) == 0:
            continue
        owner = re.search(r"(?m)^\s*allocated by = (.+)$", block)
        modifier = re.search(r"(?m)^\s*modifier=(0x[0-9a-fA-F]+)$", block)
        pixel_format = re.search(r"(?m)^\s*format=(\S+)", block)
        item = {"plane": block.splitlines()[0], "crtc": crtc[1], "fb": int(fb[1]),
                "owner": owner[1] if owner else None,
                "format": pixel_format[1] if pixel_format else None,
                "modifier": int(modifier[1], 16) if modifier else None}
        active.append(item)
        if item["crtc"] not in active_crtcs:
            errors.append("Framebuffer CRTC is not active: " + item["crtc"])
        if not item["owner"] or not item["owner"].startswith("gamescope"):
            errors.append("Active framebuffer is not owned by gamescope: " + str(item["owner"]))
        if item["modifier"] is None:
            errors.append("Active framebuffer modifier is unavailable")
        elif require_linear and item["modifier"] != 0:
            errors.append("Active framebuffer is tiled, despite requested linear scanout")
    if not active:
        errors.append("No active DRM framebuffer")
    return {"passed": not errors, "active": active, "errors": errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--linear", action="store_true")
    parser.add_argument("--state", type=Path, default=Path('/sys/kernel/debug/dri/0/state'))
    args = parser.parse_args()
    try:
        result = inspect_scanout(args.state.read_text(), args.linear)
    except OSError as error:
        result = {"passed": False, "active": [], "errors": [str(error)]}
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == '__main__':
    sys.exit(main())
