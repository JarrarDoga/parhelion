#!/usr/bin/env python3
"""Drives `parhelion mcp` the way a coding agent does, and checks each answer.

Usage: Scripts/mcp-session.py PATH_TO_PARHELION_EXECUTABLE

The session works on a copy of the LibraryApp fixture in a temporary
directory. It starts the server with a compile error in the app, fixes the
error, rebuilds, and then uses the app: it reads the view tree, taps, takes a
screenshot, and checks that @State survives a rebuild. Run it without a
display, with SDL_VIDEODRIVER=offscreen or no DISPLAY at all.
"""

import base64
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

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
        session.call("tap", {"label": "Increase"})
        session.call("tap", {"label": "Increase"})
        _, text = session.call("tap", {"label": "Nope"}, expect_error=True)
        check("No button" in text, "tapping a missing button is a tool error")

        result, _ = session.call("screenshot")
        image = next(c for c in result["content"] if c["type"] == "image")
        check(base64.b64decode(image["data"])[:8] == b"\x89PNG\r\n\x1a\n", "the screenshot is a PNG")

        session.call("rebuild")
        _, text = session.call("get_view_tree")
        check('Text "Count: 2"' in text, "@State survives a rebuild")
        session.close()


if __name__ == "__main__":
    main()
