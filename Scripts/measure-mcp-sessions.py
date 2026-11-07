#!/usr/bin/env python3
"""Runs many `parhelion mcp` sessions at once and measures their memory.

Usage: Scripts/measure-mcp-sessions.py PARHELION_EXECUTABLE [--sessions N]
           [--jobs J] [--stagger SECONDS] [--workdir DIR] [--keep]

Each session works in its own copy of a scaffold app, the size of an app
with a stub screen per tab and a fixture model of 1,535 songs, in its own
directory, like an agent in its own worktree. All sessions start together
(or --stagger seconds apart), build, and answer `get_view_tree`. The script
samples every process under each `parhelion mcp` every 100 ms and reports,
per session, the peak proportional set size of the build (swift and its
compilers and linker), the app, and the host (`parhelion` itself), and the
peak for all sessions together, plus the machine's lowest available memory.
Run it without a display, with SDL_VIDEODRIVER=offscreen.

The scaffold app depends on this checkout of Parhelion by path. The first
build of each session compiles Parhelion again in the session's own
.build directory, as a fresh worktree does.
"""

import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent

SCREENS = [
    "Collection",
    "NowPlaying",
    "Browse",
    "Search",
    "Album",
    "Artist",
    "Queue",
    "Settings",
]


LIST_SCREEN = """import SwiftUI

struct NAMEView: View {
    private let songs = FixtureModel.preview.songs

    var body: some View {
        NavigationStack {
            List {
                Section("NAME") {
                    ForEach(songs.prefix(40)) { song in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(song.title).font(.headline)
                                Text("\\(song.artist) · \\(song.album)").font(.subheadline)
                            }
                            Spacer()
                            Text("\\(song.seconds / 60):\\(song.seconds % 60)")
                        }
                    }
                }
            }
            .navigationTitle("NAME")
        }
    }
}

extension FixtureModel {
    @MainActor static let preview = FixtureModel()
}
"""

STUB_SCREEN = """import SwiftUI

struct NAMEView: View {
    @State private var count = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("NAME").font(.largeTitle)
                Text("Taps: \\(count)")
                Button("Tap") { count += 1 }
            }
            .padding()
            .navigationTitle("NAME")
        }
    }
}
"""


def scaffold(directory: pathlib.Path):
    """Writes a scaffold app: a library package with a tab and a stub screen
    per name in SCREENS and a fixture model."""
    sources = directory / "Sources/Scaffold"
    sources.mkdir(parents=True)
    (directory / "Package.swift").write_text(
        f"""// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scaffold",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Scaffold", targets: ["Scaffold"])],
    dependencies: [.package(name: "parhelion", path: {json.dumps(str(ROOT))})],
    targets: [
        .target(
            name: "Scaffold",
            dependencies: [
                .product(name: "SwiftUI", package: "parhelion", condition: .when(platforms: [.linux]))
            ])
    ]
)
"""
    )
    (directory / "xtool.yml").write_text("version: 1\nbundleID: dev.parhelion.Scaffold\n")
    (sources / "Model.swift").write_text(
        """import Foundation

struct Song: Identifiable, Hashable {
    let id: Int
    let title: String
    let artist: String
    let album: String
    let seconds: Int
}

@MainActor
protocol RustleModel: AnyObject {
    var songs: [Song] { get }
    var queue: [Song] { get }
    var nowPlaying: Song? { get }
    func play(_ song: Song)
}

@MainActor
final class FixtureModel: RustleModel {
    let songs: [Song] = (0..<1535).map { index in
        Song(
            id: index, title: "Song \\(index)", artist: "Artist \\(index % 97)",
            album: "Album \\(index % 211)", seconds: 120 + index % 240)
    }
    private(set) var queue: [Song] = []
    private(set) var nowPlaying: Song?

    func play(_ song: Song) {
        nowPlaying = song
        queue = Array(songs.prefix(12))
    }
}
"""
    )
    (sources / "ScaffoldApp.swift").write_text(
        """import SwiftUI

@main
struct ScaffoldApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
"""
        + "\n".join(
            f"""            {name}View().tabItem {{ Label("{name}", systemImage: "circle") }}"""
            for name in SCREENS
        )
        + """
        }
    }
}
"""
    )
    for name in SCREENS:
        body = LIST_SCREEN if name == SCREENS[0] else STUB_SCREEN
        (sources / f"{name}View.swift").write_text(body.replace("NAME", name))


def tree_pss():
    """Returns {pid: (ppid, comm, pss in kB)} for every process."""
    result = {}
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        try:
            with open(f"/proc/{entry.name}/stat") as stat:
                text = stat.read()
            comm = text[text.index("(") + 1 : text.rindex(")")]
            ppid = int(text[text.rindex(")") + 2 :].split()[1])
            pss = None
            try:
                with open(f"/proc/{entry.name}/smaps_rollup") as rollup:
                    for line in rollup:
                        if line.startswith("Pss:"):
                            pss = int(line.split()[1])
                            break
            except OSError:
                pass
            if pss is None:
                with open(f"/proc/{entry.name}/status") as status:
                    for line in status:
                        if line.startswith("VmRSS:"):
                            pss = int(line.split()[1])
            result[int(entry.name)] = (ppid, comm, pss or 0)
        except (OSError, ValueError):
            continue
    return result


def available_kb():
    with open("/proc/meminfo") as meminfo:
        for line in meminfo:
            if line.startswith("MemAvailable:"):
                return int(line.split()[1])
    return 0


class Session:
    def __init__(self, index, executable, package, jobs):
        self.index = index
        self.package = package
        command = [executable, "mcp", "--package-path", str(package)]
        if jobs:
            command += ["--jobs", str(jobs)]
        self.process = subprocess.Popen(
            command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        self.next_id = 1
        self.errors = []
        self.peak = {"build": 0, "app": 0, "host": 0, "total": 0}
        self.started = time.monotonic()
        self.build_seconds = None
        self.answer_seconds = None
        self.stderr = []
        threading.Thread(target=self._drain, daemon=True).start()

    def _drain(self):
        for line in self.process.stderr:
            self.stderr.append(line.rstrip())

    def send(self, method, params=None, notification=False):
        message = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            message["params"] = params
        if not notification:
            message["id"] = self.next_id
            self.next_id += 1
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()
        if notification:
            return None
        line = self.process.stdout.readline()
        if not line:
            raise RuntimeError(f"the server exited while answering {method}")
        return json.loads(line)

    def run(self):
        try:
            self.send(
                "initialize",
                {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "measure", "version": "1"}},
            )
            self.send("notifications/initialized", notification=True)
            self.build_seconds = time.monotonic() - self.started
            asked = time.monotonic()
            response = self.send("tools/call", {"name": "get_view_tree", "arguments": {}})
            self.answer_seconds = time.monotonic() - asked
            result = response["result"]
            text = "\n".join(c["text"] for c in result["content"] if c["type"] == "text")
            if result["isError"] or "Taps:" not in text and "Song" not in text:
                self.errors.append(f"get_view_tree: {text[:300]}")
        except Exception as error:  # noqa: BLE001
            self.errors.append(str(error))

    def close(self):
        try:
            self.process.stdin.close()
            status = self.process.wait(timeout=30)
            if status != 0:
                self.errors.append(f"exit status {status}")
        except Exception as error:  # noqa: BLE001
            self.errors.append(f"close: {error}")
            self.process.kill()


def sample(sessions, stop, lowest):
    while not stop.is_set():
        processes = tree_pss()
        children = {}
        for pid, (ppid, _, _) in processes.items():
            children.setdefault(ppid, []).append(pid)
        for session in sessions:
            root = session.process.pid
            if root not in processes:
                continue
            totals = {"build": 0, "app": 0, "host": processes[root][2]}
            stack = list(children.get(root, []))
            while stack:
                pid = stack.pop()
                _, comm, pss = processes[pid]
                stack.extend(children.get(pid, []))
                # The app is the product's executable; everything else under the
                # host is the build (swift, its compilers, the linker).
                if comm == "Scaffold" or comm.startswith("Scaffold"):
                    totals["app"] += pss
                else:
                    totals["build"] += pss
            totals["total"] = sum(totals.values())
            for key, value in totals.items():
                session.peak[key] = max(session.peak[key], value)
        lowest[0] = min(lowest[0], available_kb())
        time.sleep(0.1)


def mb(kb):
    return f"{kb / 1024:.0f}"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("executable")
    parser.add_argument("--sessions", type=int, default=1)
    parser.add_argument("--jobs", type=int, default=0, help="--jobs for each session; 0 leaves the default")
    parser.add_argument("--stagger", type=float, default=0, help="seconds between session starts")
    parser.add_argument("--workdir", default=None)
    parser.add_argument("--keep", action="store_true", help="keep the scaffold copies")
    args = parser.parse_args()

    workdir = pathlib.Path(args.workdir or tempfile.mkdtemp(prefix="parhelion-measure-"))
    workdir.mkdir(parents=True, exist_ok=True)
    executable = os.path.abspath(args.executable)
    sessions = []
    lowest = [available_kb()]
    baseline = lowest[0]
    stop = threading.Event()
    sampler = threading.Thread(target=sample, args=(sessions, stop, lowest), daemon=True)
    sampler.start()
    started = time.monotonic()
    threads = []
    for index in range(args.sessions):
        package = workdir / f"worktree-{index}" / "Scaffold"
        scaffold(package)
        session = Session(index, executable, package, args.jobs)
        sessions.append(session)
        thread = threading.Thread(target=session.run)
        thread.start()
        threads.append(thread)
        if args.stagger:
            time.sleep(args.stagger)
    for thread in threads:
        thread.join()
    elapsed = time.monotonic() - started

    # Idle memory once every session is up.
    time.sleep(1)
    idle = tree_pss()
    idle_totals = []
    children = {}
    for pid, (ppid, _, _) in idle.items():
        children.setdefault(ppid, []).append(pid)
    for session in sessions:
        stack = [session.process.pid]
        total = 0
        while stack:
            pid = stack.pop()
            if pid in idle:
                total += idle[pid][2]
                stack.extend(children.get(pid, []))
        idle_totals.append(total)
    for session in sessions:
        session.close()
    stop.set()
    sampler.join()

    print(f"{args.sessions} sessions, jobs={args.jobs or 'default'}, stagger={args.stagger}s, "
          f"{elapsed:.0f} s until all answered get_view_tree")
    print("session | first answer s | get_view_tree s | build MB | app MB | host MB | total peak MB | idle MB | errors")
    for session, idle_kb in zip(sessions, idle_totals):
        print(
            f"{session.index} | {session.build_seconds or 0:.0f} | {session.answer_seconds or 0:.2f} | "
            f"{mb(session.peak['build'])} | {mb(session.peak['app'])} | {mb(session.peak['host'])} | "
            f"{mb(session.peak['total'])} | {mb(idle_kb)} | {len(session.errors)}"
        )
        for error in session.errors:
            print(f"  error: {error}")
        if session.errors:
            for line in session.stderr[-10:]:
                print(f"  stderr: {line}")
    print(f"machine: {mb(baseline)} MB available before, lowest {mb(lowest[0])} MB during "
          f"(dropped {mb(baseline - lowest[0])} MB)")
    print(f"sum of session peaks: {mb(sum(s.peak['total'] for s in sessions))} MB; "
          f"sum of idle: {mb(sum(idle_totals))} MB")
    if not args.keep and not args.workdir:
        shutil.rmtree(workdir, ignore_errors=True)
    sys.exit(1 if any(s.errors for s in sessions) else 0)


if __name__ == "__main__":
    main()
