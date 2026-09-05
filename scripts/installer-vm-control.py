#!/usr/bin/env python3
"""Small QMP inspection helper for the disposable installer validation VM."""
import json
import socket
import sys
import time

with socket.socket(socket.AF_UNIX) as connection:
    connection.connect(sys.argv[1])
    stream = connection.makefile("rwb", buffering=0)
    stream.readline()

    def command(name, arguments=None):
        stream.write(json.dumps({"execute": name, "arguments": arguments or {}}).encode() + b"\n")
        while True:
            response = json.loads(stream.readline())
            if "error" in response:
                raise RuntimeError(response)
            if "return" in response:
                return response["return"]

    command("qmp_capabilities")
    if sys.argv[2] == "shot":
        command("screendump", {"filename": sys.argv[3]})
    elif sys.argv[2] == "key":
        command("human-monitor-command", {"command-line": "sendkey " + sys.argv[3]})
    elif sys.argv[2] == "type":
        special = {" ": "spc", "/": "slash", "-": "minus", ".": "dot",
                   "_": "shift-minus", ":": "shift-semicolon", "|": "shift-backslash",
                   ">": "shift-dot", "=": "equal", "'": "apostrophe", '"': "shift-apostrophe"}
        for character in sys.argv[3]:
            key = special.get(character, "shift-" + character.lower() if character.isupper() else character)
            command("human-monitor-command", {"command-line": "sendkey " + key})
            time.sleep(0.06)
    elif sys.argv[2] == "click":
        x, y, width, height = map(int, sys.argv[3:7])
        command("input-send-event", {"events": [
            {"type": "abs", "data": {"axis": "x", "value": int(x * 32767 / width)}},
            {"type": "abs", "data": {"axis": "y", "value": int(y * 32767 / height)}}]})
        command("input-send-event", {"events": [{"type": "btn", "data": {"down": True, "button": "left"}}]})
        time.sleep(0.08)
        command("input-send-event", {"events": [{"type": "btn", "data": {"down": False, "button": "left"}}]})
    else:
        print(command(sys.argv[2], json.loads(sys.argv[3]) if len(sys.argv) > 3 else None))
