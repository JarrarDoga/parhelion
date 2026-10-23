import Foundation
import Observation
import Testing

@testable import ParhelionUI

@Observable
private final class Counter {
    var count = 0
    var unread = 0
    var showsDetail = false
}

private struct CounterView: View {
    let counter: Counter
    @State private var taps = 0

    var body: some View {
        VStack {
            Text("Count: \(counter.count)")
            Text("Taps: \(taps)")
            Button("Tap") { taps += 1 }
            Button("Increment") { counter.count += 1 }
            Button("Show") { withAnimation { counter.showsDetail = true } }
            if counter.showsDetail {
                Text("Detail")
            }
        }
    }
}

private struct OwningView: View {
    @State private var counter = Counter()

    var body: some View {
        VStack {
            Text("Count: \(counter.count)")
            Button("Increment") { counter.count += 1 }
        }
    }
}

private struct OwnerSwitch: View {
    @State private var isShown = true

    var body: some View {
        VStack {
            Button("Toggle") { isShown.toggle() }
            if isShown { OwningView() }
        }
    }
}

/// A model that a test changes from another thread.
@Observable
private final class SharedValue: @unchecked Sendable {
    var value = 0
}

private struct SharedValueView: View {
    let shared: SharedValue

    var body: some View {
        Text("Value: \(shared.value)")
    }
}

/// Makes the next evaluation of a body write to a model from another thread,
/// after the body read the model.
private final class MidEvaluationWrite: @unchecked Sendable {
    var isArmed = false
}

private struct RacingView: View {
    let shared: SharedValue
    let write: MidEvaluationWrite
    @State private var taps = 0

    var body: some View {
        let value = shared.value
        if write.isArmed {
            write.isArmed = false
            let done = DispatchSemaphore(value: 0)
            let shared = shared
            Thread {
                shared.value = 5
                done.signal()
            }.start()
            done.wait()
        }
        return VStack {
            Text("Value: \(value)")
            Button("Tap \(taps)") { taps += 1 }
        }
    }
}

@Observable
private final class Profile: Codable {
    var name = "Ada"

    enum CodingKeys: String, CodingKey {
        case _name = "name"
    }
}

private struct ProfileView: View {
    @State private var profile = Profile()

    var body: some View {
        VStack {
            Text(profile.name)
            Button("Rename") { profile.name = "Grace" }
        }
    }
}

private struct ProfileApp: App {
    @State private var profile = Profile()

    var body: some Scene {
        WindowGroup {
            VStack {
                Text(profile.name)
                Button("Rename") { profile.name = "Grace" }
                Button("Replace") { profile = Profile() }
            }
        }
    }
}

/// Waits until the main queue has run the work queued on it so far.
@MainActor
private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

@MainActor
@Suite("Observation")
struct ObservationTests {
    @Test("A change to a property that a body read updates the tree")
    func readPropertyInvalidates() {
        let counter = Counter()
        let host = ViewHost(CounterView(counter: counter))
        #expect(!host.needsUpdate)

        counter.count = 3
        #expect(host.needsUpdate)
        host.update()
        #expect(host.nodes(withText: "Count: 3").count == 1)
    }

    @Test("A change to a property that no body read does nothing")
    func unreadPropertyDoesNotInvalidate() {
        let counter = Counter()
        let host = ViewHost(CounterView(counter: counter))
        let revision = host.revision

        counter.unread = 7
        #expect(!host.needsUpdate)
        host.update()
        #expect(host.revision == revision)
    }

    @Test("A button that changes a model updates the tree")
    func actionChangesModel() throws {
        let counter = Counter()
        let host = ViewHost(CounterView(counter: counter))
        try host.tapButton(labeled: "Increment")
        try host.tapButton(labeled: "Increment")
        #expect(host.nodes(withText: "Count: 2").count == 1)
    }

    @Test("Tracking continues after updates that only @State caused")
    func trackingSurvivesStateUpdates() throws {
        let counter = Counter()
        let host = ViewHost(CounterView(counter: counter))
        for _ in 0..<5 { try host.tapButton(labeled: "Tap") }
        #expect(host.nodes(withText: "Taps: 5").count == 1)

        counter.count = 9
        #expect(host.needsUpdate)
        host.update()
        #expect(host.nodes(withText: "Count: 9").count == 1)
    }

    @Test("A model change inside withAnimation animates")
    func animatedModelChange() throws {
        let counter = Counter()
        let host = ViewHost(CounterView(counter: counter))
        try host.tapButton(labeled: "Show")
        #expect(host.nodes(withText: "Detail").count == 1)
        #expect(host.isAnimating)
    }

    @Test("@State keeps an observable object for as long as its view stays")
    func stateOwnsObject() throws {
        let host = ViewHost(OwnerSwitch())
        try host.tapButton(labeled: "Increment")
        try host.tapButton(labeled: "Increment")
        #expect(host.nodes(withText: "Count: 2").count == 1)

        try host.tapButton(labeled: "Toggle")
        try host.tapButton(labeled: "Toggle")
        #expect(host.nodes(withText: "Count: 0").count == 1)
    }

    @Test("A change on another thread marks the host on the main thread")
    func changeOffMainThread() async {
        let shared = SharedValue()
        let host = ViewHost(SharedValueView(shared: shared))
        await Task.detached { shared.value = 4 }.value
        await drainMainQueue()
        #expect(host.needsUpdate)
        host.update()
        #expect(host.nodes(withText: "Value: 4").count == 1)
    }

    @Test("A change on another thread in the middle of an evaluation is not lost")
    func changeDuringEvaluation() async throws {
        let shared = SharedValue()
        let write = MidEvaluationWrite()
        let host = ViewHost(RacingView(shared: shared, write: write))
        write.isArmed = true
        try host.tapButton(labeled: "Tap 0")
        #expect(shared.value == 5)
        await drainMainQueue()
        #expect(host.needsUpdate)
        host.update()
        #expect(host.nodes(withText: "Value: 5").count == 1)
    }

    @Test("An observable Codable model in @State survives a snapshot and restore")
    func codableModelSnapshot() throws {
        let first = ViewHost(ProfileView())
        try first.tapButton(labeled: "Rename")
        let snapshot = first.stateSnapshot()
        let values = try JSONDecoder().decode([String: String].self, from: snapshot)
        #expect(values["ProfileView._profile"] == #"{"name":"Grace"}"#)

        let second = ViewHost(ProfileView(), restoring: snapshot)
        #expect(second.nodes(withText: "Grace").count == 1)
    }

    @Test("An app's @State belongs to the host and survives a snapshot and restore")
    func appState() throws {
        let first = ViewHost(anyRootView: AppRoot(app: ProfileApp()))
        #expect(
            first.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "Ada"
                   ├─ Button
                   │  └─ Text "Rename"
                   └─ Button
                      └─ Text "Replace"
                """
        )
        try first.tapButton(labeled: "Rename")
        #expect(first.nodes(withText: "Grace").count == 1)
        let snapshot = first.stateSnapshot()
        let values = try JSONDecoder().decode([String: String].self, from: snapshot)
        #expect(values["ProfileApp._profile"] == #"{"name":"Grace"}"#)

        let second = ViewHost(anyRootView: AppRoot(app: ProfileApp()), restoring: snapshot)
        #expect(second.nodes(withText: "Grace").count == 1)
        try second.tapButton(labeled: "Replace")
        #expect(second.nodes(withText: "Ada").count == 1)
    }
}
