#!/usr/bin/env python3
"""Drives `parhelion mcp` the way a coding agent does, and checks each answer.

Usage: Scripts/mcp-session.py PATH_TO_PARHELION_EXECUTABLE

The session works on a copy of the LibraryApp fixture in a temporary
directory. It starts the server with a compile error in the app, fixes the
error, rebuilds, and then uses the app: it reads the view tree, taps, takes a
screenshot and compares the screen with it, switches to dark at a large text size, and checks that @State and
the appearance survive a rebuild. Run it without a display, with
SDL_VIDEODRIVER=offscreen or no DISPLAY at all.
"""

import base64
import json
import os
import pathlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "Tools/parhelion-cli/Fixtures/LibraryApp"


class Session:
    def __init__(self, executable, package):
        self.process = subprocess.Popen(
            [executable, "mcp", "--package-path", str(package)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        )
        assert self.process.stdin and self.process.stdout
        self.input, self.output = self.process.stdin, self.process.stdout
        self.next_id = 1

    def send(self, method, params=None, notification=False):
        message = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            message["params"] = params
        if not notification:
            message["id"] = self.next_id
            self.next_id += 1
        self.input.write(json.dumps(message) + "\n")
        self.input.flush()
        if notification:
            return None
        line = self.output.readline()
        if not line:
            sys.exit(f"The server exited while answering {method}.")
        response = json.loads(line)
        require(response.get("id") == message["id"], f"the response to {method} has its id: {response}")
        return response

    def call(self, tool, arguments=None, expect_error=False):
        response = self.send("tools/call", {"name": tool, "arguments": arguments or {}})
        require(response and "result" in response, f"{tool} returned a result: {response}")
        result = response["result"]
        text = "\n".join(c["text"] for c in result["content"] if c["type"] == "text")
        require(
            result["isError"] == expect_error,
            f"{tool} {'failed' if expect_error else 'succeeded'}: {text}",
        )
        return result, text

    def close(self):
        self.input.close()
        status = self.process.wait(timeout=30)
        check(status == 0, f"the server exited with status {status}")


def require(condition, description):
    if not condition:
        sys.exit(f"FAIL: {description}")


def check(condition, description):
    if not condition:
        sys.exit(f"FAIL: {description}")
    print(f"ok: {description.splitlines()[0][:100]}")


def tiny_png():
    """A 1 x 1 white PNG."""
    import zlib

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(b"\x00\xff\xff\xff")) + chunk(b"IEND", b"")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    executable = os.path.abspath(sys.argv[1])

    with tempfile.TemporaryDirectory() as directory:
        package = pathlib.Path(directory) / "LibraryApp"
        shutil.copytree(FIXTURE, package, ignore=shutil.ignore_patterns(".build"))
        manifest = package / "Package.swift"
        manifest.write_text(manifest.read_text().replace('"../../../.."', json.dumps(str(ROOT))))
        source = package / "Sources/LibraryApp/LibraryApp.swift"
        working = source.read_text()
        source.write_text(working.replace("count += 1", "count += \"one\""))

        session = Session(executable, package)
        response = session.send(
            "initialize",
            {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "ci", "version": "1"}},
        )
        check(response and response["result"]["protocolVersion"] == "2025-11-25", "initialize")
        session.send("notifications/initialized", notification=True)
        response = session.send("tools/list")
        tools = [tool["name"] for tool in response["result"]["tools"]] if response else []
        check("get_view_tree" in tools and "rebuild" in tools, "tools/list")

        _, text = session.call("get_view_tree", expect_error=True)
        check("LibraryApp.swift" in text, "a failed build reports the compiler error")

        source.write_text(working)
        _, text = session.call("rebuild")
        check("Built and started" in text, "rebuild after fixing the error")

        _, text = session.call("get_view_tree")
        check('Text "Count: 0"' in text, "the view tree shows the initial state")
        check("accessibilityIdentifier=increase" in text, "the view tree shows the accessibility identifier")
        session.call("tap", {"label": "Increase"})
        _, text = session.call("tap", {"accessibility_identifier": "increase"})
        check("identified \"increase\"" in text, "tap takes an accessibility identifier")
        _, text = session.call("tap", {"label": "Nope"}, expect_error=True)
        check("No button" in text, "tapping a missing button is a tool error")
        _, text = session.call("tap", {"accessibility_identifier": "nope"}, expect_error=True)
        check("accessibility identifier \"nope\"" in text, "an unknown accessibility identifier is a tool error")
        _, text = session.call("type_text", {"text": "x", "accessibility_identifier": "increase"}, expect_error=True)
        check("not a text field" in text, "type_text into a button by accessibility identifier is a tool error")
        _, text = session.call("scroll_to", {"accessibility_identifier": "increase"}, expect_error=True)
        check("not a scroll view" in text, "scroll_to a button by accessibility identifier is a tool error")

        result, _ = session.call("screenshot")
        image = next(c for c in result["content"] if c["type"] == "image")
        check(base64.b64decode(image["data"])[:8] == b"\x89PNG\r\n\x1a\n", "the screenshot is a PNG")

        # The screenshot is a design board for the compare_image tool.
        board = pathlib.Path(directory) / "board.png"
        board.write_bytes(base64.b64decode(image["data"]))
        diff = pathlib.Path(directory) / "diff.png"
        result, text = session.call("compare_image", {"path": str(board), "diff_path": str(diff)})
        check("0.00% of pixels differ" in text, "compare_image finds no difference from an identical board")
        check(any(c["type"] == "image" for c in result["content"]) and diff.exists(), "compare_image writes a diff PNG")
        _, text = session.call("compare_image", {"path": str(pathlib.Path(directory) / "none.png")}, expect_error=True)
        check("Cannot read" in text, "a missing board is a tool error")
        # A 1 x 1 PNG is not the shape of the screen.
        tiny = pathlib.Path(directory) / "tiny.png"
        tiny.write_bytes(tiny_png())
        _, text = session.call("compare_image", {"path": str(tiny)}, expect_error=True)
        check("A board for this screen is" in text, "a board of the wrong size is a tool error")

        _, text = session.call("set_appearance", {"color_scheme": "dark", "dynamic_type_size": "accessibility2"})
        check("dark at Dynamic Type size accessibility2" in text, "set_appearance switches the device")
        _, text = session.call("get_view_tree")
        check("Root colorScheme=dark dynamicTypeSize=accessibility2" in text, "the view tree's root shows the appearance")
        _, text = session.call("compare_image", {"path": str(board), "diff_path": str(diff)})
        share = float(re.search(r"([0-9.]+)% of pixels differ", text).group(1))
        check(share > 10, f"compare_image finds the light board differs from the dark screen ({share}%)")
        _, text = session.call("set_appearance", {"color_scheme": "sepia"}, expect_error=True)
        check("color_scheme" in text, "an unknown color scheme is a tool error")

        _, text = session.call("set_appearance", {"reduce_motion": True})
        check("Reduce Motion is on" in text, "set_appearance switches Reduce Motion")
        _, text = session.call("get_view_tree")
        check("Root colorScheme=dark dynamicTypeSize=accessibility2 reduceMotion=true" in text, "the view tree's root shows Reduce Motion")
        _, text = session.call("get_sensory_feedback")
        check("No sensory feedback has played." in text, "get_sensory_feedback answers when no view played any")

        session.call("rebuild")
        _, text = session.call("get_view_tree")
        check('Text "Count: 2"' in text, "@State survives a rebuild")
        check("Root colorScheme=dark dynamicTypeSize=accessibility2 reduceMotion=true" in text, "the appearance and Reduce Motion survive a rebuild")

        # Without a window, `wait` moves the app's clock instead of sleeping.
        source.write_text(
            working.replace("@State private var count = 0", "@State private var count = 0\n    @State private var loaded = false")
            .replace(
                "Text(\"Count: \\(count)\")",
                "Text(\"Count: \\(count)\")\n            Text(loaded ? \"Loaded\" : \"Loading\")",
            )
            .replace(
                ".padding()",
                ".padding()\n        .task {\n            try? await Task.sleep(for: .seconds(5))\n            loaded = true\n        }",
            )
        )
        session.call("rebuild")
        _, text = session.call("get_view_tree")
        check('Text "Loading"' in text, "the task is sleeping after a rebuild")
        started = time.monotonic()
        _, text = session.call("wait", {"seconds": 10})
        elapsed = time.monotonic() - started
        check(elapsed < 1, f"a 10-second wait returns in under a second (took {elapsed:.2f} s)")
        _, text = session.call("get_view_tree")
        check('Text "Loaded"' in text, "the task that slept 5 seconds has finished")
        session.close()


if __name__ == "__main__":
    main()
