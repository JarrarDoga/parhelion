#!/usr/bin/env python3
"""Drives `parhelion mcp` on an app that links a Rust library through UniFFI.

Usage: Scripts/mcp-rust-session.py PATH_TO_PARHELION_EXECUTABLE

The session works on a copy of the RustApp fixture in a temporary directory.
It needs Rust: the first build compiles UniFFI, which takes a minute or two.
It checks that the app shows what the Rust library returns, that an error in
the Rust code reaches the agent like a Swift error, and that an edit to a
`.rs` file shows after a rebuild. Run it without a display, with
SDL_VIDEODRIVER=offscreen or no DISPLAY at all.
"""

import importlib.util
import json
import os
import pathlib
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "Tools/parhelion-cli/Fixtures/RustApp"

spec = importlib.util.spec_from_file_location("mcp_session", ROOT / "Scripts/mcp-session.py")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
check = base.check


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    executable = os.path.abspath(sys.argv[1])
    os.environ["PATH"] = str(pathlib.Path.home() / ".cargo/bin") + os.pathsep + os.environ["PATH"]

    with tempfile.TemporaryDirectory() as directory:
        package = pathlib.Path(directory) / "RustApp"
        shutil.copytree(
            FIXTURE,
            package,
            ignore=shutil.ignore_patterns(".build", "target", "Generated", "include"),
        )
        manifest = package / "Package.swift"
        manifest.write_text(manifest.read_text().replace('"../../../.."', json.dumps(str(ROOT))))
        library = package / "crates/fixture-backend/src/lib.rs"
        working = library.read_text()
        library.write_text(working.replace("Arc::new(Self {", "Arc::new(Self { missing: 1,"))

        session = base.Session(executable, package)
        session.send(
            "initialize",
            {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "ci", "version": "1"}},
        )
        session.send("notifications/initialized", notification=True)

        _, text = session.call("get_view_tree", expect_error=True)
        check("The pre-build command failed" in text, "a Rust error stops the first build")
        check("lib.rs" in text and "missing" in text, "the failure shows Cargo's error")

        library.write_text(working)
        _, text = session.call("rebuild")
        check("Built and started" in text, "rebuild after fixing the Rust error")
        _, text = session.call("get_view_tree")
        check('Text "Hello from Rust"' in text, "the app shows the greeting from Rust")
        check('Text "Parhelion by Sundog"' in text, "the app shows the tracks from Rust")

        library.write_text(working.replace("Hello from Rust", "Hello after an edit"))
        session.call("rebuild")
        _, text = session.call("get_view_tree")
        check('Text "Hello after an edit"' in text, "an edit to a .rs file shows after a rebuild")
        session.close()


if __name__ == "__main__":
    main()
