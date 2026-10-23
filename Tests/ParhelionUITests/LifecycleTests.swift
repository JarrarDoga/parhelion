import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

/// Records lifecycle events in order.
@MainActor
private final class EventLog {
    var events: [String] = []
}

private struct Appearing: View {
    let log: EventLog
    @State private var isShown = true
    @State private var appearances = 0

    var body: some View {
        VStack {
            Text("Appeared \(appearances) times")
                .onAppear { appearances += 1 }
            Button("Toggle") { isShown.toggle() }
            if isShown {
                Text("Child")
                    .onAppear { log.events.append("appear") }
                    .onDisappear { log.events.append("disappear") }
            }
        }
        .onAppear { log.events.append("parent appear") }
    }
}

private struct Pushing: View {
    let log: EventLog

    var body: some View {
        NavigationStack {
            NavigationLink("Next") {
                Text("Pushed")
                    .onAppear { log.events.append("pushed appear") }
                    .onDisappear { log.events.append("pushed disappear") }
            }
            .onAppear { log.events.append("root appear") }
            .onDisappear { log.events.append("root disappear") }
        }
    }
}

private struct Changing: View {
    let log: EventLog
    @State private var count = 0
    @State private var name = "a"

    var body: some View {
        VStack {
            Text("\(count) \(name)")
            Button("Count") { count += 1 }
            Button("Name") { name += "a" }
        }
        .onChange(of: count) { old, new in log.events.append("count \(old) → \(new)") }
        .onChange(of: count, initial: true) { log.events.append("count changed") }
        .onChange(of: name) { old, new in log.events.append("name \(old) → \(new)") }
    }
}

private struct Echo: View {
    @State private var count = 0
    @State private var echo = 0

    var body: some View {
        VStack {
            Text("\(count) \(echo)")
            Button("Count") { count += 1 }
        }
        .onChange(of: count) { _, new in echo = new * 10 }
    }
}

private struct Runaway: View {
    @State private var count = 0

    var body: some View {
        Text("\(count)")
            .onChange(of: count, initial: true) { count += 1 }
    }
}

/// Counts frames that another thread receives.
private final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }

    func add() {
        lock.lock()
        frames += 1
        lock.unlock()
    }
}

/// Lets a test decide when a task finishes.
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

private struct Loading: View {
    let gate: Gate
    let log: EventLog
    @State private var isShown = true
    @State private var text = "Loading"

    var body: some View {
        VStack {
            Button("Toggle") { isShown.toggle() }
            if isShown {
                Text(text)
                    .task {
                        await gate.wait()
                        if Task.isCancelled {
                            log.events.append("cancelled")
                            return
                        }
                        text = "Loaded"
                    }
            }
        }
    }
}

private struct Reloading: View {
    let log: EventLog
    @State private var query = "a"

    var body: some View {
        VStack {
            Text(query)
            Button("Search") { query += "a" }
        }
        .task(id: query) { [query] in
            log.events.append("start \(query)")
            await Task.yield()
            log.events.append(Task.isCancelled ? "cancelled \(query)" : "done \(query)")
        }
    }
}

private struct Restarting: View {
    let gate: Gate
    let log: EventLog
    @State private var query = "a"

    var body: some View {
        Button("Search \(query)") { query += "a" }
            .task(id: query) { [query] in
                await gate.wait()
                log.events.append("finished \(query)\(Task.isCancelled ? ", cancelled" : "")")
            }
    }
}

private let tinyScreen = Device(
    name: "Tiny", screenSize: CGSize(width: 20, height: 20), safeAreaInsets: EdgeInsets())

@MainActor
@Suite("Lifecycle")
struct LifecycleTests {
    @Test("A cancelled run counts as pending until it finishes, and waitForTasks waits for it")
    func cancelledRunPending() async throws {
        let gate = Gate()
        let log = EventLog()
        let host = ViewHost(Restarting(gate: gate, log: log))
        while gate.waiting == 0 { await Task.yield() }

        try host.tapButton(labeled: "Search a")
        #expect(host.pendingTaskCount == 2)
        while gate.waiting < 2 { await Task.yield() }
        gate.open()
        await host.waitForTasks()
        #expect(host.pendingTaskCount == 0)
        #expect(log.events.sorted() == ["finished a, cancelled", "finished aa"])
    }

    @Test("Actions that change state forever stop at the update limit, leaving no update waiting")
    func runawayStops() {
        let host = ViewHost(Runaway())
        #expect(!host.needsUpdate)
        let count = Int(host.root.allNodes.compactMap(\.text).first ?? "") ?? 0
        #expect(count == ViewHost.maximumUpdatePasses)
        host.update()
        #expect(!host.needsUpdate)
    }

    @Test("A preview session does not spin on a view that changes state forever")
    func runawaySession() throws {
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        nonisolated(unsafe) let reader = hostEnd
        let frames = FrameCounter()
        let readerThread = Thread {
            while let message = try? reader.receiveAppMessage(timeout: 2) {
                if case .frame = message { frames.add() }
            }
        }
        readerThread.start()
        let host = ViewHost(Runaway(), device: tinyScreen)
        Thread {
            Thread.sleep(forTimeInterval: 0.3)
            try? reader.send(.close)
        }.start()
        try PreviewSession(host: host, channel: appEnd, scale: 1, appName: "Runaway").run()
        #expect(frames.count <= 2)
    }

    @Test("Lifecycle modifiers do not change the tree")
    func outline() {
        let host = ViewHost(
            Text("Hello")
                .onAppear {}
                .onDisappear {}
                .onChange(of: 1) {}
                .task {}
        )
        #expect(
            host.root.outline() == """
                Root
                └─ Text "Hello"
                """
        )
    }

    @Test("onAppear runs before the first tree; onDisappear when the view leaves")
    func appearAndDisappear() throws {
        let log = EventLog()
        let host = ViewHost(Appearing(log: log))
        #expect(host.nodes(withText: "Appeared 1 times").count == 1)
        #expect(log.events == ["parent appear", "appear"])

        try host.tapButton(labeled: "Toggle")
        #expect(log.events == ["parent appear", "appear", "disappear"])
        try host.tapButton(labeled: "Toggle")
        #expect(log.events == ["parent appear", "appear", "disappear", "appear"])
        #expect(host.nodes(withText: "Appeared 1 times").count == 1)
    }

    @Test("A pushed view covers the view beneath it, which disappears")
    func navigation() throws {
        let log = EventLog()
        let host = ViewHost(Pushing(log: log))
        #expect(log.events == ["root appear"])
        try host.tapButton(labeled: "Next")
        #expect(log.events == ["root appear", "root disappear", "pushed appear"])
        try host.tapButton(labeled: "Back")
        #expect(
            log.events == [
                "root appear", "root disappear", "pushed appear", "pushed disappear",
                "root appear",
            ])
    }

    @Test("onChange runs with the old and new values after an update")
    func change() throws {
        let log = EventLog()
        let host = ViewHost(Changing(log: log))
        #expect(log.events == ["count changed"])

        try host.tapButton(labeled: "Count")
        #expect(log.events.dropFirst().sorted() == ["count 0 → 1", "count changed"])
        try host.tapButton(labeled: "Name")
        #expect(log.events.count == 4)
        #expect(log.events.last == "name a → aa")
    }

    @Test("A change that onChange makes is in the tree after the update")
    func changeInOnChange() throws {
        let host = ViewHost(Echo())
        try host.tapButton(labeled: "Count")
        #expect(host.nodes(withText: "1 10").count == 1)
        #expect(!host.needsUpdate)
    }

    @Test("A task runs on the main actor, and waitForTasks waits for it")
    func task() async {
        let gate = Gate()
        let log = EventLog()
        let host = ViewHost(Loading(gate: gate, log: log))
        #expect(host.pendingTaskCount == 1)
        #expect(host.execute(.inspect(json: false)).message.hasPrefix("revision"))
        #expect(host.execute(.inspect(json: false)).message.contains("· 1 task running"))
        #expect(host.execute(.inspect(json: false)).pendingTasks == 1)

        while gate.waiting == 0 { await Task.yield() }
        gate.open()
        await host.waitForTasks()
        #expect(host.pendingTaskCount == 0)
        #expect(host.nodes(withText: "Loaded").count == 1)
        #expect(host.execute(.inspect(json: false)).pendingTasks == 0)
    }

    @Test("A task is cancelled when its view leaves the screen")
    func taskCancelled() async throws {
        let gate = Gate()
        let log = EventLog()
        let host = ViewHost(Loading(gate: gate, log: log))
        while gate.waiting == 0 { await Task.yield() }

        try host.tapButton(labeled: "Toggle")
        // Cancelled, but still pending until it returns.
        #expect(host.pendingTaskCount == 1)
        gate.open()
        await host.waitForTasks()
        #expect(host.pendingTaskCount == 0)
        #expect(log.events == ["cancelled"])
    }

    @Test("task(id:) starts again when its id changes, cancelling the last run")
    func taskID() async throws {
        let log = EventLog()
        let host = ViewHost(Reloading(log: log))
        await host.waitForTasks()
        #expect(log.events == ["start a", "done a"])

        try host.tapButton(labeled: "Search")
        try host.tapButton(labeled: "Search")
        await host.waitForTasks()
        while log.events.count < 6 { await Task.yield() }
        #expect(
            log.events.dropFirst(2).sorted() == [
                "cancelled aa", "done aaa", "start aa", "start aaa",
            ])
    }
}
