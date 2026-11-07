#if canImport(Foundation)
import Foundation
#endif

// `TimelineView` and its schedules, from
// https://developer.apple.com/documentation/swiftui/timelineview and the pages
// of `TimelineSchedule`, `PeriodicTimelineSchedule`, `EveryMinuteTimelineSchedule`,
// `AnimationTimelineSchedule`, and `ExplicitTimelineSchedule`.
//
// A timeline view reads the host's clock, not the real one. See
// docs/adr/0012-manual-clock.md and the "Timelines" section of
// docs/architecture.md.

// MARK: - Schedules

/// How often a timeline view updates its content, mirroring SwiftUI's
/// `TimelineScheduleMode`.
public enum TimelineScheduleMode: Sendable {
    /// Updates as often as the schedule says.
    case normal
    /// Updates less often, to save power. Parhelion always uses ``normal``.
    case lowFrequency
}

/// A sequence of dates at which a ``TimelineView`` updates, mirroring
/// SwiftUI's `TimelineSchedule`.
public protocol TimelineSchedule {
    /// The mode a schedule is asked for entries in.
    typealias Mode = TimelineScheduleMode

    associatedtype Entries: Sequence where Entries.Element == Date

    /// The dates the view updates at, in order, beginning at or after
    /// `startDate`. A schedule may also return earlier dates: the view shows
    /// the latest date that has passed.
    func entries(from startDate: Date, mode: Mode) -> Entries
}

/// A schedule of dates at regular intervals, mirroring SwiftUI's
/// `PeriodicTimelineSchedule`.
public struct PeriodicTimelineSchedule: TimelineSchedule {
    let start: Date
    let interval: TimeInterval

    /// Every `interval` seconds from `startDate`.
    public init(from startDate: Date, by interval: TimeInterval) {
        start = startDate
        self.interval = interval
    }

    /// The dates of the schedule.
    public struct Entries: Sequence, IteratorProtocol {
        var upcoming: Date
        let interval: TimeInterval

        public mutating func next() -> Date? {
            defer { upcoming = upcoming.addingTimeInterval(interval) }
            return upcoming
        }
    }

    /// The dates `from + n × interval` from `startDate` on. Assumed: the
    /// schedule keeps to its own grid, so the first date is the first one on
    /// the grid at or after `startDate`.
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        // An interval of zero or less would never advance.
        let step = max(interval, 0.001)
        var first = start
        let behind = startDate.timeIntervalSince(start)
        if behind > 0 {
            let count = (behind / step - 1e-6).rounded(.up)
            first = start.addingTimeInterval(count * step)
        }
        return Entries(upcoming: first, interval: step)
    }
}

/// A schedule of dates at the start of every minute, mirroring SwiftUI's
/// `EveryMinuteTimelineSchedule`.
public struct EveryMinuteTimelineSchedule: TimelineSchedule {
    public init() {}

    /// The dates of the schedule.
    public struct Entries: Sequence, IteratorProtocol {
        var upcoming: TimeInterval

        public mutating func next() -> Date? {
            defer { upcoming += 60 }
            return Date(timeIntervalSince1970: upcoming)
        }
    }

    /// The start of each minute (in UTC, which is every minute everywhere) at
    /// or after `startDate`.
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        let seconds = startDate.timeIntervalSince1970
        return Entries(upcoming: (seconds / 60 - 1e-9).rounded(.up) * 60)
    }
}

/// A schedule that updates as often as the display draws, mirroring
/// SwiftUI's `AnimationTimelineSchedule`.
///
/// The host's frame clock drives it: the view updates whenever the host
/// advances its time by at least `minimumInterval`, with the host's date. A
/// window host asks for a frame every refresh while one is on screen.
public struct AnimationTimelineSchedule: TimelineSchedule {
    let minimumInterval: TimeInterval?
    let paused: Bool

    /// Updates every frame, or no more often than every `minimumInterval`
    /// seconds, and not at all after the first date while `paused`.
    public init(minimumInterval: Double? = nil, paused: Bool = false) {
        self.minimumInterval = minimumInterval
        self.paused = paused
    }

    /// The dates of the schedule.
    public struct Entries: Sequence, IteratorProtocol {
        var upcoming: Date
        let interval: TimeInterval
        let isPaused: Bool
        var done = false

        public mutating func next() -> Date? {
            guard !done else { return nil }
            defer {
                upcoming = upcoming.addingTimeInterval(interval)
                done = isPaused
            }
            return upcoming
        }
    }

    /// `startDate`, then dates `minimumInterval` apart (a sixtieth of a
    /// second by default); only `startDate` while paused. The host does not
    /// walk them: it updates the view at its frames.
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(
            upcoming: startDate, interval: max(minimumInterval ?? 1.0 / 60, 0.001),
            isPaused: paused)
    }
}

/// A schedule of dates you give, mirroring SwiftUI's
/// `ExplicitTimelineSchedule`.
public struct ExplicitTimelineSchedule<Entries: Sequence>: TimelineSchedule
where Entries.Element == Date {
    let dates: Entries

    /// The dates, in increasing order.
    public init(_ dates: Entries) {
        self.dates = dates
    }

    /// All the dates. Assumed: the view shows the latest one that has passed,
    /// so dates before `startDate` are not dropped.
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        dates
    }
}

extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    /// A schedule that updates every `interval` seconds, on the grid that
    /// begins at `startDate`.
    public static func periodic(
        from startDate: Date, by interval: TimeInterval
    )
        -> PeriodicTimelineSchedule
    {
        PeriodicTimelineSchedule(from: startDate, by: interval)
    }
}

extension TimelineSchedule where Self == EveryMinuteTimelineSchedule {
    /// A schedule that updates at the start of every minute.
    public static var everyMinute: EveryMinuteTimelineSchedule { EveryMinuteTimelineSchedule() }
}

extension TimelineSchedule where Self == AnimationTimelineSchedule {
    /// A schedule that updates every frame.
    public static var animation: AnimationTimelineSchedule { AnimationTimelineSchedule() }

    /// A schedule that updates every frame, or no more often than
    /// `minimumInterval`, and stops while `paused`.
    public static func animation(
        minimumInterval: Double? = nil, paused: Bool = false
    )
        -> AnimationTimelineSchedule
    {
        AnimationTimelineSchedule(minimumInterval: minimumInterval, paused: paused)
    }
}

extension TimelineSchedule {
    /// A schedule that updates at the given dates.
    public static func explicit<S: Sequence>(_ dates: S) -> Self
    where Self == ExplicitTimelineSchedule<S>, S.Element == Date {
        ExplicitTimelineSchedule(dates)
    }
}

// MARK: - The view

/// A view that updates its content on a schedule, mirroring SwiftUI's
/// `TimelineView`.
///
/// It reads the host's clock (``ViewHost/date``), so it follows
/// ``ViewHost/advanceTime(by:)`` and the manual clock of an agent session,
/// not `Date()`: a `.periodic(from: .now, by: 1)` view updates once for each
/// second the host advances. The content is built again, with the date of
/// the latest entry of the schedule that has passed, when the host's date
/// reaches the next entry. An `.animation` schedule updates the content at
/// each frame the host advances.
///
/// The node is a `TimelineView` with its `schedule` and `date`, and the
/// content as its children. Its content is laid out like an `AsyncImage`'s:
/// the node takes the size of what it shows.
public struct TimelineView<Schedule: TimelineSchedule, Content: View>: View {
    public typealias Body = Never

    let schedule: Schedule
    let content: (Context) -> Content

    /// Shows `content` for each date of `schedule`.
    public init(
        _ schedule: Schedule, @ViewBuilder content: @escaping (Context) -> Content
    ) {
        self.schedule = schedule
        self.content = content
    }

    public var body: Never {
        fatalError("TimelineView is a primitive view and has no body.")
    }

    /// What the content closure is given: the date to show, and how often
    /// the view updates. Not nested in the generic type, so that Swift can
    /// infer the content type from the closure that takes it.
    public typealias Context = _TimelineViewContext
}

/// What a ``TimelineView``'s content closure is given, mirroring SwiftUI's
/// `TimelineView.Context`.
public struct _TimelineViewContext: Sendable {
    /// How often the view updates, mirroring SwiftUI's
    /// `TimelineView.Context.Cadence`. Faster cadences are less than slower
    /// ones.
    public enum Cadence: Comparable, Hashable, Sendable {
        /// More often than once a second.
        case live
        /// About once a second.
        case seconds
        /// About once a minute, or less often.
        case minutes
    }

    /// The date to show.
    public let date: Date
    /// How often the view updates.
    public let cadence: Cadence

    init(date: Date, cadence: Cadence) {
        self.date = date
        self.cadence = cadence
    }
}

/// The context `TimelineView`'s `init(_:content:)` is documented with in
/// SwiftUI: the one of a view that updates every minute.
public typealias TimelineViewDefaultContext = TimelineView<EveryMinuteTimelineSchedule, Never>
    .Context

extension TimelineView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("TimelineView")
        let state = evaluator.host.resolveTimeline(id: ownPath.id, schedule: schedule)
        let shown = Context(date: state.date, cadence: state.cadence)
        return [
            ViewNode(
                id: ownPath.id, kind: "TimelineView",
                attributes: [
                    "schedule": TimelineDescription.name(of: schedule),
                    "date": TimelineDescription.format(state.date),
                ],
                children: evaluator.evaluate(content(shown), at: ownPath))
        ]
    }
}

// MARK: - The tree

enum TimelineDescription {
    /// How a schedule appears in the tree.
    static func name(of schedule: Any) -> String {
        switch schedule {
        case let periodic as PeriodicTimelineSchedule:
            "periodic(by: \(formatPoints(CGFloat(periodic.interval))))"
        case is EveryMinuteTimelineSchedule: "everyMinute"
        case let animation as AnimationTimelineSchedule:
            animation.paused
                ? "animation(paused)"
                : animation.minimumInterval.map {
                    "animation(minimumInterval: \(formatPoints(CGFloat($0))))"
                } ?? "animation"
        case let explicit as any _ExplicitSchedule: "explicit(\(explicit.count))"
        default: "custom"
        }
    }

    /// A date as the tree shows it: UTC, to the millisecond.
    static func format(_ date: Date) -> String {
        let milliseconds = Int((date.timeIntervalSince1970 * 1000).rounded())
        let seconds = Int((Double(milliseconds) / 1000).rounded(.down))
        let fraction = milliseconds - seconds * 1000
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", parts.year ?? 0, parts.month ?? 0,
            parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0, fraction)
    }
}

/// An explicit schedule whose element type is erased, so that the tree can
/// say how many dates it has.
protocol _ExplicitSchedule {
    var count: Int { get }
}

extension ExplicitTimelineSchedule: _ExplicitSchedule {
    var count: Int { dates.underestimatedCount }
}

// MARK: - The host's side

/// What a timeline view showed at the last evaluation and when it updates
/// next.
struct TimelineHostState {
    struct Entry {
        /// The date the content was built for.
        var shown: Date
        /// The next date of the schedule, or `nil` if it has no more.
        var next: Date?
        /// For a schedule driven by frames, the least time between updates.
        var frameInterval: TimeInterval?
    }

    /// How far a date may fall short of an entry and still reach it. The
    /// manual clock counts in milliseconds, and sums of fractions are not
    /// exact.
    static let tolerance: TimeInterval = 0.0005
    /// The most entries one update walks through.
    static let walkLimit = 100_000

    var entries: [NodeID: Entry] = [:]
    var visited: Set<NodeID> = []
    /// The date at host time 0, once something asked for it.
    var referenceDate: Date?

    mutating func beginEvaluation() {
        visited = []
    }

    /// Forgets views that left the tree.
    mutating func finishEvaluation() {
        entries = entries.filter { visited.contains($0.key) }
    }

    /// Whether any view has an update due at `date`.
    func hasUpdateDue(at date: Date) -> Bool {
        entries.values.contains { entry in
            if let next = entry.next, next.timeIntervalSince(date) <= Self.tolerance {
                return true
            }
            if let interval = entry.frameInterval,
                date.timeIntervalSince(entry.shown) >= interval - Self.tolerance
            {
                return true
            }
            return false
        }
    }

    /// The earliest next date of a view that does not follow frames.
    var nextDate: Date? { entries.values.compactMap(\.next).min() }

    var followsFrames: Bool { entries.values.contains { $0.frameInterval != nil } }

    /// Finds the date a view shows at `now`, and records when it updates.
    mutating func resolve<S: TimelineSchedule>(
        id: NodeID, schedule: S, now: Date
    ) -> (date: Date, cadence: _TimelineViewContext.Cadence) {
        visited.insert(id)
        let previous = entries[id]
        if let animation = schedule as? AnimationTimelineSchedule, !animation.paused {
            let interval = animation.minimumInterval.map { max($0, 0) } ?? 0
            var shown = previous?.shown ?? now
            if previous?.frameInterval == nil
                || now.timeIntervalSince(shown) >= interval - Self.tolerance
            {
                shown = now
            }
            entries[id] = Entry(shown: shown, next: nil, frameInterval: interval)
            return (shown, .live)
        }
        // Walk the entries from the date last shown, so that an update visits
        // only the dates that passed since.
        var shown = previous?.shown ?? now
        var next: Date?
        var walked = 0
        for date in schedule.entries(from: shown, mode: .normal) {
            if date.timeIntervalSince(now) <= Self.tolerance {
                shown = date
            } else {
                next = date
                break
            }
            walked += 1
            if walked >= Self.walkLimit { break }
        }
        entries[id] = Entry(shown: shown, next: next, frameInterval: nil)
        return (shown, Self.cadence(of: schedule, from: shown, to: next))
    }

    /// How often a schedule updates. Assumed: from the interval of a
    /// periodic schedule and the gap to the next date of any other.
    private static func cadence<S: TimelineSchedule>(
        of schedule: S, from shown: Date, to next: Date?
    ) -> _TimelineViewContext.Cadence {
        let gap: TimeInterval
        switch schedule {
        case let periodic as PeriodicTimelineSchedule: gap = periodic.interval
        case is EveryMinuteTimelineSchedule: gap = 60
        default: gap = next.map { $0.timeIntervalSince(shown) } ?? 60
        }
        return gap < 1 ? .live : gap < 60 ? .seconds : .minutes
    }
}

extension ViewHost {
    /// The date the host's clock shows: ``referenceDate`` plus ``time``.
    /// `TimelineView` reads it.
    public var date: Date {
        referenceDate.addingTimeInterval(time)
    }

    /// The date at ``time`` 0.
    ///
    /// It is the real date at the first moment a view asked for it, so a
    /// `Date.now` read just before agrees with it, and then it stays: the
    /// host's date moves with ``advanceTime(by:)``, never with the real
    /// clock. Set it to make dates repeat, as in a test.
    public var referenceDate: Date {
        get {
            if let date = timelines.referenceDate { return date }
            let date = Date(timeIntervalSinceNow: -time)
            timelines.referenceDate = date
            return date
        }
        set {
            timelines.referenceDate = newValue
            // Dates in the tree are dates of the old reference.
            timelines.entries = [:]
            setNeedsUpdate()
            update()
        }
    }

    /// The seconds from now until a `TimelineView` with a schedule of dates
    /// next updates, or `nil` if none will. Views that follow frames are not
    /// counted: see ``isAnimating``.
    public var secondsUntilNextTimelineUpdate: TimeInterval? {
        timelines.nextDate.map { max($0.timeIntervalSince(date), 0) }
    }

    func resolveTimeline<S: TimelineSchedule>(
        id: NodeID, schedule: S
    ) -> (date: Date, cadence: _TimelineViewContext.Cadence) {
        timelines.resolve(id: id, schedule: schedule, now: date)
    }

    /// Updates the timeline views whose next date the clock has reached.
    func updateTimelines() {
        guard timelines.hasUpdateDue(at: date) else { return }
        setNeedsUpdate()
        update()
    }
}
