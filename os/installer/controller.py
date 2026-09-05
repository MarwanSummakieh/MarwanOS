#!/usr/bin/env python3
"""Installer-only standard Linux gamepad to pointer/keyboard bridge.

No device grabbing: keyboard/mouse remain usable. Device removal releases held
keys. No storage commands or installation decisions are made here.
"""
import array
import fcntl
import glob
import os
import select
import struct
import subprocess
import time

EVENT = struct.Struct("llHHi")
BUTTONS = {304: 272, 305: 1, 307: 66, 308: 57, 310: 42, 311: 15, 315: 28}
# A/cross: click; B/circle: Escape; Y/triangle: keyboard; X/square: Space.
# RB/R1: Tab; hold LB/L1 with RB/R1: previous control.


class Bridge:
    def __init__(self):
        subprocess.run(["modprobe", "uinput"], check=True)
        self.output = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        for kind in (1, 2):
            fcntl.ioctl(self.output, 0x40045564, kind)  # UI_SET_EVBIT
        for key in {*range(1, 128), *BUTTONS.values()}:
            fcntl.ioctl(self.output, 0x40045565, key)
        for axis in (0, 1):
            fcntl.ioctl(self.output, 0x40045566, axis)
        setup = struct.pack("HHHH80sI", 3, 0x1209, 1, 1, b"PC1 installer controller", 0)
        fcntl.ioctl(self.output, 0x405c5503, setup)
        fcntl.ioctl(self.output, 0x5501)
        self.devices = {}

    def emit(self, kind, code, value):
        os.write(self.output, EVENT.pack(0, 0, kind, code, value))
        os.write(self.output, EVENT.pack(0, 0, 0, 0, 0))

    def scan(self):
        existing = {item["path"] for item in self.devices.values()}
        for path in glob.glob("/dev/input/event*"):
            if path in existing:
                continue
            fd = None
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                bits = bytearray(96)
                fcntl.ioctl(fd, 0x80604521, bits)  # EVIOCGBIT(EV_KEY, 96)
                if not bits[304 // 8] & (1 << (304 % 8)):
                    os.close(fd)
                    continue
                ranges = {}
                for axis in (0, 1):
                    values = array.array("i", [0] * 6)
                    fcntl.ioctl(fd, 0x80184540 + axis, values)
                    ranges[axis] = (values[1], values[2])
                self.devices[fd] = {"path": path, "ranges": ranges, "axes": {}, "held": set()}
            except OSError:
                if fd is not None:
                    os.close(fd)

    def remove(self, fd):
        device = self.devices.pop(fd)
        for key in device["held"]:
            self.emit(1, key, 0)
        os.close(fd)

    def event(self, device, kind, code, value):
        if kind == 1 and code in BUTTONS:
            key = BUTTONS[code]
            self.emit(1, key, value)
            if value:
                device["held"].add(key)
            else:
                device["held"].discard(key)
        elif kind == 3 and code in (0, 1):
            low, high = device["ranges"][code]
            span = max(1, high - low)
            normalized = (value - low) / span * 2 - 1
            device["axes"][code] = normalized if abs(normalized) > 0.18 else 0
        elif kind == 3 and code in (16, 17):
            for key, active in zip((105, 106) if code == 16 else (103, 108), (value < 0, value > 0)):
                if active != (key in device["held"]):
                    self.emit(1, key, int(active))
                    if active:
                        device["held"].add(key)
                    else:
                        device["held"].discard(key)

    def run(self):
        next_scan = 0
        while True:
            now = time.monotonic()
            if now >= next_scan:
                self.scan()
                next_scan = now + 2
            ready, _, _ = select.select(list(self.devices), [], [], 0.016)
            for fd in ready:
                try:
                    data = os.read(fd, EVENT.size * 64)
                    if not data:
                        self.remove(fd)
                        continue
                    for _, _, kind, code, value in EVENT.iter_unpack(data):
                        self.event(self.devices[fd], kind, code, value)
                except OSError:
                    self.remove(fd)
            for device in self.devices.values():
                for axis, value in device["axes"].items():
                    if value:
                        self.emit(2, axis, round(value * 12))


if __name__ == "__main__":
    Bridge().run()
