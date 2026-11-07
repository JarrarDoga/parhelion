import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 200, height: 100),
    safeAreaInsets: EdgeInsets()
)

/// A screen whose frames are small enough that a session can send several
/// before anything reads them.
private let tiny = Device(
    name: "Tiny",
    screenSize: CGSize(width: 20, height: 20),
    safeAreaInsets: EdgeInsets()
)

/// 2026-01-01 12:00:00 UTC.
private let noon = Date(timeIntervalSince1970: 1_767_268_800)

/// Counts how often a timeline view builds its content.
@MainActor
private final class Counter {
    var builds = 0
    var dates: [Date] = []
}

/// The seconds from `noon` as text.
private func secondsFromNoon(_ date: Date) -> String {
    String(format: "%.3f", date.timeIntervalSince(noon))
}

@MainActor
@Suite("TimelineView")
struct TimelineViewTests {
    @Test("A periodic timeline view shows the date of its latest entry, and the schedule")
    func periodicOutline() {
        let host = ViewHost(
            TimelineView(.periodic(from: noon, by: 2)) { context in
                Text(secondsFromNoon(context.date))
            }, device: screen, referenceDate: noon)
        #expect(
            host.root.outline() == """
                Root
                └─ TimelineView date=2026-01-01T12:00:00.000Z schedule=periodic(by: 2)
                   └─ Text "0.000"
                """)
        // The node takes the size of what it shows, centered like a ZStack.
        let node = host.root.children[0]
        let text = node.children[0]
        #expect(text.frame?.size == node.frame?.size)
        #expect((text.frame?.width ?? 0) > 0 && (text.frame?.width ?? 0) < 100)
    }

    @Test("It updates once per period as the clock advances, and not between")
    func oncePerPeriod() {
        let counter = Counter()
        let host = ViewHost(
            TimelineView(.periodic(from: noon, by: 1)) { context in
                let _ = counter.record(context.date)
                Text(secondsFromNoon(context.date))
            }, device: screen, referenceDate: noon)
        let initial = counter.builds
        #expect(initial >= 1)

        host.advanceClock(by: 0.4)
        host.advanceClock(by: 0.4)
        #expect(counter.builds == initial)
        #expect(host.root.outline().contains("Text \"0.000\""))

        host.advanceClock(by: 0.2)
        #expect(counter.builds == initial + 1)
        #expect(host.root.outline().contains("Text \"1.000\""))

        // Three periods in one advance: the content is built for each date.
        host.advanceClock(by: 3)
        #expect(counter.builds == initial + 4)
        #expect(counter.dates.suffix(3).map(secondsFromNoon) == ["2.000", "3.000", "4.000"])
        #expect(host.root.outline().contains("Text \"4.000\""))
    }

    @Test("advanceTime in one step shows the latest date that passed, once")
    func coalesced() {
        let counter = Counter()
        let host = ViewHost(
            TimelineView(.periodic(from: noon, by: 1)) { context in
                let _ = counter.record(context.date)
                Text(secondsFromNoon(context.date))
            }, device: screen, referenceDate: noon)
        let initial = counter.builds
        host.advanceTime(by: 3.5)
        #expect(counter.builds == initial + 1)
        #expect(host.root.outline().contains("Text \"3.000\""))
        #expect(host.date == noon.addingTimeInterval(3.5))
        #expect(host.secondsUntilNextTimelineUpdate.map { abs($0 - 0.5) < 1e-6 } == true)
    }

    @Test("A schedule that starts at Date.now updates once per second of the host's clock")
    func startsNow() {
        let counter = Counter()
        let host = ViewHost(
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let _ = counter.record(context.date)
                Text("tick")
            }, device: screen)
        let initial = counter.builds
        for _ in 0..<5 { host.advanceClock(by: 1) }
        #expect(counter.builds == initial + 5)
        host.advanceClock(by: 0.9)
        #expect(counter.builds == initial + 5)
    }

    @Test("Fractions of a second add up to the period")
    func fractions() {
        let counter = Counter()
        let host = ViewHost(
            TimelineView(.periodic(from: noon, by: 0.3)) { context in
                let _ = counter.record(context.date)
                Text(secondsFromNoon(context.date))
            }, device: screen, referenceDate: noon)
        let initial = counter.builds
        host.advanceTime(by: 0.1)
        host.advanceTime(by: 0.2)
        #expect(counter.builds == initial + 1)
        #expect(host.root.outline().contains("Text \"0.300\""))
    }

    @Test("The animation schedule follows the frames the host advances")
    func animation() {
        let counter = Counter()
        let host = ViewHost(
            TimelineView(.animation) { context in
                let _ = counter.record(context.date)
                Text(secondsFromNoon(context.date))
            }, device: screen, referenceDate: noon)
        #expect(host.isAnimating)
        #expect(host.secondsUntilNextTimelineUpdate == nil)
        #expect(host.root.children[0].attributes["schedule"] == "animation")
        let initial = counter.builds
        for frame in 1...3 { host.advanceTime(by: 1.0 / 60); _ = frame }
        #expect(counter.builds == initial + 3)
        #expect(host.root.outline().contains("Text \"0.050\""))
        let revision = host.revision
        host.advanceTime(by: 1.0 / 60)
        #expect(host.revision > revision)
    }

    @Test("minimumInterval holds frames back, and a paused animation stops")
    func animationOptions() {
        let counter = Counter()
        let paused = Box(false)
        let host = ViewHost(
            PausableTimeline(paused: paused, counter: counter), device: screen,
            referenceDate: noon)
        #expect(host.isAnimating)
        let initial = counter.builds
        host.advanceTime(by: 0.05)
        #expect(counter.builds == initial)
        host.advanceTime(by: 0.06)
        #expect(counter.builds == initial + 1)
        #expect(host.root.children[0].attributes["schedule"] == "animation(minimumInterval: 0.1)")

        paused.value = true
        host.advanceTime(by: 1)
        host.update()
        #expect(!host.isAnimating)
        #expect(host.root.children[0].attributes["schedule"] == "animation(paused)")
        let shown = host.root.children[0].attributes["date"]
        host.advanceTime(by: 5)
        #expect(host.root.children[0].attributes["date"] == shown)
    }

    @Test("everyMinute updates at the start of each minute")
    func everyMinute() {
        let counter = Counter()
        let host = ViewHost(
            TimelineView(.everyMinute) { context in
                let _ = counter.record(context.date)
                Text(secondsFromNoon(context.date))
            }, device: screen, referenceDate: noon.addingTimeInterval(30))
        // The view shows the date it appeared at until the first minute.
        #expect(host.root.children[0].attributes["date"] == "2026-01-01T12:00:30.000Z")
        #expect(host.root.children[0].attributes["schedule"] == "everyMinute")
        let initial = counter.builds
        host.advanceClock(by: 29)
        #expect(counter.builds == initial)
        host.advanceClock(by: 1)
        #expect(counter.builds == initial + 1)
        #expect(host.root.children[0].attributes["date"] == "2026-01-01T12:01:00.000Z")
        host.advanceClock(by: 120)
        #expect(counter.builds == initial + 3)
        #expect(host.root.children[0].attributes["date"] == "2026-01-01T12:03:00.000Z")
    }

    @Test("An explicit schedule shows the latest date that passed")
    func explicit() {
        let dates = [5.0, 10, 20].map { noon.addingTimeInterval($0) }
        let counter = Counter()
        let host = ViewHost(
            TimelineView(.explicit(dates)) { context in
                let _ = counter.record(context.date)
                Text(secondsFromNoon(context.date))
            }, device: screen, referenceDate: noon)
        let initial = counter.builds
        #expect(host.root.children[0].attributes["schedule"] == "explicit(3)")
        #expect(host.root.outline().contains("Text \"0.000\""))
        host.advanceClock(by: 12)
        #expect(counter.builds == initial + 2)
        #expect(host.root.outline().contains("Text \"10.000\""))
        host.advanceClock(by: 100)
        #expect(host.root.outline().contains("Text \"20.000\""))
        // No dates are left.
        #expect(host.secondsUntilNextTimelineUpdate == nil)
        #expect(!host.isAnimating)
    }

    @Test("The context says how often the view updates")
    func cadence() {
        func cadence<S: TimelineSchedule>(_ schedule: S) -> TimelineView<S, Text>.Context.Cadence {
            let seen = Box<TimelineView<S, Text>.Context.Cadence>(.minutes)
            _ = ViewHost(
                TimelineView(schedule) { context -> Text in
                    seen.value = context.cadence
                    return Text("x")
                }, device: screen, referenceDate: noon)
            return seen.value
        }
        #expect(cadence(.periodic(from: noon, by: 0.25)) == .live)
        #expect(cadence(.periodic(from: noon, by: 1)) == .seconds)
        #expect(cadence(.periodic(from: noon, by: 90)) == .minutes)
        #expect(cadence(.everyMinute) == .minutes)
        #expect(cadence(.animation) == .live)
        #expect(TimelineView<PeriodicTimelineSchedule, Text>.Context.Cadence.live < .seconds)
        #expect(TimelineViewDefaultContext.Cadence.seconds < .minutes)
    }

    @Test("A view that follows the date: a clock in a stack")
    func clock() {
        let host = ViewHost(
            VStack {
                Text("Now playing")
                TimelineView(.periodic(from: noon, by: 1)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(noon))
                    Text("\(elapsed / 60):" + String(format: "%02d", elapsed % 60))
                }
            }, device: screen, referenceDate: noon)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "Now playing"
                   └─ TimelineView date=2026-01-01T12:00:00.000Z schedule=periodic(by: 1)
                      └─ Text "0:00"
                """)
        host.advanceClock(by: 75)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "Now playing"
                   └─ TimelineView date=2026-01-01T12:01:15.000Z schedule=periodic(by: 1)
                      └─ Text "1:15"
                """)
    }

    @Test("A timeline view that leaves the tree stops updating")
    func leavesTree() {
        let shown = Box(true)
        let host = ViewHost(Switchable(shown: shown), device: screen, referenceDate: noon)
        #expect(host.secondsUntilNextTimelineUpdate != nil)
        shown.value = false
        host.advanceClock(by: 1)
        host.update()
        #expect(host.secondsUntilNextTimelineUpdate == nil)
        #expect(!host.root.outline().contains("TimelineView"))
    }

    @Test("Setting the reference date moves every date")
    func referenceDate() {
        let host = ViewHost(
            TimelineView(.periodic(from: noon, by: 1)) { _ in Text("x") }, device: screen,
            referenceDate: noon)
        host.advanceTime(by: 2)
        #expect(host.root.children[0].attributes["date"] == "2026-01-01T12:00:02.000Z")
        host.referenceDate = noon.addingTimeInterval(3600)
        #expect(host.date == noon.addingTimeInterval(3602))
    }

    @Test("A session wakes for the next date and sends a frame")
    func sessionWakes() throws {
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        let host = ViewHost(
            TimelineView(.periodic(from: .now, by: 0.15)) { context in
                Text(String(format: "%.2f", context.date.timeIntervalSinceReferenceDate))
            }, device: tiny)
        nonisolated(unsafe) let closer = hostEnd
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { try? closer.send(.close) }
        try PreviewSession(host: host, channel: appEnd, scale: 1, appName: "Timeline").run()
        var frames = 0
        while let message = try hostEnd.receiveAppMessage(timeout: 0.2) {
            switch message {
            case .frame, .frameUpdate: frames += 1
            default: break
            }
        }
        // The first frame, then one for most of the five periods.
        #expect(frames >= 4)
    }
}

/// A value that a view reads and a test changes, outside of `@State`.
@MainActor
private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

extension Counter {
    func record(_ date: Date) {
        builds += 1
        dates.append(date)
    }
}

private struct PausableTimeline: View {
    let paused: Box<Bool>
    let counter: Counter

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: paused.value)) { context in
            let _ = counter.record(context.date)
            Text(secondsFromNoon(context.date))
        }
    }
}

private struct Switchable: View {
    let shown: Box<Bool>

    var body: some View {
        if shown.value {
            TimelineView(.periodic(from: noon, by: 1)) { _ in Text("on") }
        } else {
            Text("off")
        }
    }
}
