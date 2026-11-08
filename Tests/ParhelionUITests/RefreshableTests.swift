import Foundation
import Testing

@testable import ParhelionUI

/// A 300 × 400 screen with no safe-area insets.
private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 400),
    safeAreaInsets: EdgeInsets()
)

/// A gate that holds a refresh action until the test opens it.
@MainActor
private final class Gate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    var waiting: Int { continuations.count }

    func wait() async {
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        let waiting = continuations
        continuations = []
        for continuation in waiting { continuation.resume() }
    }
}

/// Counts runs of actions, which are `@Sendable` closures.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var runs: Int {
        get { lock.withLock { count } }
        set { lock.withLock { count = newValue } }
    }
}

private struct RefreshingList: View {
    let gate: Gate
    let counter: Counter

    var body: some View {
        List {
            ForEach(0..<3) { Text("Row \($0)") }
        }
        .refreshable {
            await gate.wait()
            counter.runs = counter.runs + 1
        }
    }
}

private struct RefreshingScrollView: View {
    let gate: Gate
    let counter: Counter

    var body: some View {
        ScrollView {
            ForEach(0..<30) { Text("Row \($0)").frame(height: 40) }
        }
        .refreshable {
            await gate.wait()
            counter.runs = counter.runs + 1
        }
    }
}

/// Reads the `refresh` environment value from inside the content.
private struct Reader: View {
    @Environment(\.refresh) private var refresh

    var body: some View {
        Text(refresh == nil ? "no refresh" : "has refresh")
            .task { await refresh?() }
    }
}

@MainActor
private func pulled(_ host: ViewHost, _ kind: String) throws -> ViewNode {
    try #require(host.root.allNodes.first { $0.kind == kind })
}

@MainActor
private func waitUntilRunning(_ gate: Gate) async {
    while gate.waiting == 0 { await Task.yield() }
}

@MainActor
@Suite("refreshable")
struct RefreshableTests {
    @Test("A refreshable list and scroll view are marked in the tree")
    func outline() {
        let host = ViewHost(
            List { Text("One") }.refreshable {},
            device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ List contentOffset=0, 0 contentSize=300 × 72 refreshable=true
                   └─ Section
                      └─ Text "One" listRow
                """)
        let scroll = ViewHost(ScrollView { Text("One") }.refreshable {}, device: screen)
        #expect(
            scroll.root.outline() == """
                Root
                └─ ScrollView axes=vertical contentOffset=0, 0 contentSize=32.3 × 22 \
                refreshable=true
                   └─ Text "One"
                """)
    }

    @Test("Without the modifier, and on a horizontal scroll view, nothing is refreshable")
    func notMarked() {
        let plain = ViewHost(List { Text("One") }, device: screen)
        #expect(!plain.root.allNodes.contains { $0.isRefreshable })
        let horizontal = ViewHost(
            ScrollView(.horizontal) { Text("One") }.refreshable {}, device: screen)
        #expect(!horizontal.root.allNodes.contains { $0.isRefreshable })
    }

    @Test(
        "Pulling a list past the threshold runs the action and holds the spinner until it returns")
    func pullList() async throws {
        let gate = Gate()
        let counter = Counter()
        let host = ViewHost(RefreshingList(gate: gate, counter: counter), device: screen)
        let id = try pulled(host, "List").id
        let resting = try #require(host.root.node(withID: id)?.children.first?.frame?.minY)

        host.drag(from: CGPoint(x: 150, y: 100), to: CGPoint(x: 150, y: 300))

        let list = try #require(host.root.node(withID: id))
        #expect(list.isRefreshing)
        #expect(list.children.first?.frame?.minY == resting + RefreshMetrics.holdHeight)
        #expect(host.pendingTaskCount == 1)
        #expect(counter.runs == 0)
        #expect(host.isAnimating)

        await waitUntilRunning(gate)
        gate.open()
        await host.waitForTasks()

        let done = try #require(host.root.node(withID: id))
        #expect(!done.isRefreshing)
        #expect(done.attributes["refreshPull"] == nil)
        #expect(done.children.first?.frame?.minY == resting)
        #expect(counter.runs == 1)
        #expect(host.pendingTaskCount == 0)
    }

    @Test("A context menu around a refreshable list keeps the pull")
    func contextMenuKeepsPull() async throws {
        let gate = Gate()
        let counter = Counter()
        let host = ViewHost(
            RefreshingList(gate: gate, counter: counter)
                .contextMenu { Button("Share") {} },
            device: screen)
        host.drag(from: CGPoint(x: 150, y: 100), to: CGPoint(x: 150, y: 300))
        #expect(try pulled(host, "List").isRefreshing)
        await waitUntilRunning(gate)
        gate.open()
        await host.waitForTasks()
        #expect(counter.runs == 1)
    }

    @Test("Pulling a scroll view does the same")
    func pullScrollView() async throws {
        let gate = Gate()
        let counter = Counter()
        let host = ViewHost(RefreshingScrollView(gate: gate, counter: counter), device: screen)
        host.drag(from: CGPoint(x: 150, y: 100), to: CGPoint(x: 150, y: 300))
        #expect(try pulled(host, "ScrollView").isRefreshing)
        await waitUntilRunning(gate)
        gate.open()
        await host.waitForTasks()
        #expect(try !pulled(host, "ScrollView").isRefreshing)
        #expect(counter.runs == 1)
    }

    @Test("A short pull shows the spinner and then lets go without refreshing")
    func shortPull() async throws {
        let gate = Gate()
        let counter = Counter()
        let host = ViewHost(RefreshingList(gate: gate, counter: counter), device: screen)
        let id = try pulled(host, "List").id
        let resting = try #require(host.root.node(withID: id)?.children.first?.frame?.minY)

        host.pointerDown(at: CGPoint(x: 150, y: 100))
        host.pointerMoved(to: CGPoint(x: 150, y: 120))
        host.pointerMoved(to: CGPoint(x: 150, y: 180))
        let pulling = try #require(host.root.node(withID: id))
        let pull = try #require(pulling.attributes["refreshPull"].flatMap(Double.init))
        #expect(pull > 0 && pull < RefreshMetrics.threshold)
        #expect(!pulling.isRefreshing)
        let moved = try #require(pulling.children.first?.frame?.minY)
        #expect(abs(moved - (resting + pull)) < 0.01)
        host.pointerUp(at: CGPoint(x: 150, y: 180))

        #expect(host.pendingTaskCount == 0)
        #expect(try pulled(host, "List").children.first?.frame?.minY == resting)
        #expect(counter.runs == 0)
    }

    @Test("Dragging down a scrolled list scrolls it instead of pulling")
    func notAtTop() throws {
        let gate = Gate()
        let host = ViewHost(RefreshingScrollView(gate: gate, counter: Counter()), device: screen)
        let id = try pulled(host, "ScrollView").id
        try host.scroll(id, to: CGPoint(x: 0, y: 300))
        host.drag(from: CGPoint(x: 150, y: 100), to: CGPoint(x: 150, y: 200))
        #expect(try !pulled(host, "ScrollView").isRefreshing)
        #expect(host.pendingTaskCount == 0)
        #expect((host.scrollOffset(of: id)?.y ?? 0) < 300)
    }

    @Test("The pull that comes back up scrolls the rest")
    func pullBackScrolls() throws {
        let host = ViewHost(RefreshingScrollView(gate: Gate(), counter: Counter()), device: screen)
        let id = try pulled(host, "ScrollView").id
        host.pointerDown(at: CGPoint(x: 150, y: 200))
        host.pointerMoved(to: CGPoint(x: 150, y: 215))
        host.pointerMoved(to: CGPoint(x: 150, y: 260))
        #expect(try pulled(host, "ScrollView").attributes["refreshPull"] != nil)
        host.pointerMoved(to: CGPoint(x: 150, y: 100))
        #expect(try pulled(host, "ScrollView").attributes["refreshPull"] == nil)
        #expect((host.scrollOffset(of: id)?.y ?? 0) > 0)
        host.pointerUp(at: CGPoint(x: 150, y: 100))
        #expect(host.pendingTaskCount == 0)
    }

    @Test("The refresh environment value runs the action, and is nil outside")
    func environment() async throws {
        let counter = Counter()
        let host = ViewHost(
            VStack {
                Reader().refreshable { counter.runs = counter.runs + 1 }
                Reader()
            },
            device: screen)
        #expect(host.nodes(withText: "has refresh").count == 1)
        #expect(host.nodes(withText: "no refresh").count == 1)
        await host.waitForTasks()
        #expect(counter.runs == 1)
    }

    @Test("A refreshable closer to the scroll view takes precedence")
    func nested() async throws {
        let counter = Counter()
        let host = ViewHost(
            ScrollView { Text("One") }
                .refreshable { counter.runs = counter.runs + 10 }
                .padding()
                .refreshable { counter.runs = counter.runs + 1 },
            device: screen)
        host.drag(from: CGPoint(x: 150, y: 100), to: CGPoint(x: 150, y: 300))
        await host.waitForTasks()
        #expect(counter.runs == 10)
    }

    @Test("The spinner draws in the gap above the content")
    func spinner() async throws {
        let gate = Gate()
        let host = ViewHost(RefreshingList(gate: gate, counter: Counter()), device: screen)
        let before = host.render(scale: 1)
        host.drag(from: CGPoint(x: 150, y: 100), to: CGPoint(x: 150, y: 300))
        host.advanceTime(by: 2)
        let list = try pulled(host, "List")
        let top = try #require(list.attributes["refreshTop"].flatMap(Double.init))
        let y = top + RefreshMetrics.holdHeight / 2 - 8
        let after = host.render(scale: 1)
        // The top spoke is above the center, and no spoke is at the left.
        #expect(after.color(at: CGPoint(x: 150, y: y)) != after.color(at: CGPoint(x: 20, y: y)))
        #expect(before.color(at: CGPoint(x: 150, y: y)) == before.color(at: CGPoint(x: 20, y: y)))
        await waitUntilRunning(gate)
        gate.open()
        await host.waitForTasks()
    }
}
