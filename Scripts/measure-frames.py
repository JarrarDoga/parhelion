#!/usr/bin/env python3
"""Measures the frames of the Rustle-shaped fixtures the way the preview presents them.

Usage: Scripts/measure-frames.py PATH_TO_PARHELION_EXECUTABLE

Runs each example under `parhelion mcp --window`, which builds it with Parhelion optimized,
as `parhelion run` does, at the preview's default scale of 2. The `tap` tool presses Play and
Pause on RustleNowPlaying, and the `drag` tool flings the list of RustleCollection. The display
is offscreen and assumes 120 Hz (PARHELION_REFRESH_RATE=120, PARHELION_DEBUG=1). For each
fixture the script prints how many refreshes (8.33 ms) lie between the frames the host
presented. A fixture reaches 120 Hz when every gap is one refresh.
"""

import collections
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
REFRESH = 1000 / 120
EXECUTABLE = ""


def summarize(name, log):
    presents = []
    for line in log.splitlines():
        match = re.search(r"present at ([\d.]+) ms \(\+[\d.]+ ms\)(, same frame)?", line)
        if match and not match.group(2):
            presents.append(float(match.group(1)))
    gaps = [b - a for a, b in zip(presents[3:], presents[4:]) if b - a < 100]
    refreshes = collections.Counter(round(gap / REFRESH) for gap in gaps)
    print(f"{name}: {len(gaps)} frames while moving")
    print("  refreshes between presented frames:", dict(sorted(refreshes.items())))
    if gaps:
        print(f"  median gap {sorted(gaps)[len(gaps) // 2]:.1f} ms; 120 Hz is {REFRESH:.1f} ms")


def environment():
    env = dict(os.environ)
    env.update(SDL_VIDEODRIVER="offscreen", PARHELION_REFRESH_RATE="120", PARHELION_DEBUG="1")
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("DISPLAY", None)
    return env


def run_session(product, name, actions):
    """Runs `parhelion mcp --window` on a product, calls `actions(call)`, and summarizes."""
    env = environment()
    with tempfile.TemporaryFile("w+") as log:
        process = subprocess.Popen(
            [EXECUTABLE, "mcp", "--package-path", str(ROOT), "--product", product,
             "--window", "--device", "iPhone 18 Pro Max", "-j", "4"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True, env=env,
        )
        next_id = 0

        def send(method, params=None, notification=False):
            nonlocal next_id
            message = {"jsonrpc": "2.0", "method": method, "params": params or {}}
            if not notification:
                next_id += 1
                message["id"] = next_id
            process.stdin.write(json.dumps(message) + "\n")
            process.stdin.flush()
            return None if notification else json.loads(process.stdout.readline())

        def call(tool, arguments=None):
            return send("tools/call", {"name": tool, "arguments": arguments or {}})

        send("initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
                            "clientInfo": {"name": "measure", "version": "1"}})
        send("notifications/initialized", notification=True)
        call("rebuild")
        actions(call)
        process.stdin.close()
        process.wait(timeout=30)
        log.seek(0)
        summarize(name, log.read())


def fling(call):
    for _ in range(3):
        call("drag", {"from_x": 220, "from_y": 800, "to_x": 220, "to_y": 200, "duration": 0.25})
        time.sleep(2)


def play_and_pause(call):
    for label in ["Play", "Pause", "Play", "Pause", "Play", "Pause"]:
        call("tap", {"label": label})
        time.sleep(1.5)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    global EXECUTABLE
    EXECUTABLE = os.path.abspath(sys.argv[1])
    run_session("RustleNowPlaying", "Now Playing", play_and_pause)
    run_session("RustleCollection", "Collection fling", fling)


main()
