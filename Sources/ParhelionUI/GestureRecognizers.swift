#if canImport(Foundation)
import Foundation
#endif

// The state machines behind the gestures. A gesture value (`TapGesture`,
// `DragGesture().onEnded { ... }`, `a.sequenced(before: b)`) is a description;
// `makeRecognizer(for:)` turns it into a tree of recognizers, one per
// pointer press. The host feeds a recognizer pointer events and the time, and
// the recognizer answers with events (the gesture changed, ended, or failed)
// that carry the user's callbacks as effects. The host decides when to run the
// effects: see ViewHost+Gestures.swift and docs/adr/0015-gesture-arbitration.md.

/// Where a recognizer is in recognizing its gesture.
enum GestureStatus {
    /// Still waiting to see whether the press is its gesture.
    case possible
    /// Recognized, and still changing: a drag in progress.
    case active
    /// Recognized, and finished.
    case ended
    /// The press is not its gesture.
    case failed
}

/// A pointer event for a recognizer.
struct GestureInput {
    enum Phase { case down, move, up, tick }

    var phase: Phase
    /// Where the pointer is, in screen points.
    var point: CGPoint
    /// The host's clock, in seconds.
    var time: TimeInterval
    /// The top-left corner, in screen points, of the view the gesture is on.
    var origin: CGPoint = .zero

    /// The point in a coordinate space. Named spaces are not tracked: they
    /// read as the screen's.
    func location(in space: any CoordinateSpaceProtocol) -> CGPoint {
        convert(point, in: space)
    }

    func convert(_ point: CGPoint, in space: any CoordinateSpaceProtocol) -> CGPoint {
        space is LocalCoordinateSpace
            ? CGPoint(x: point.x - origin.x, y: point.y - origin.y) : point
    }
}

/// What a recognizer reports.
struct GestureEvent {
    enum Kind { case changed, ended, failed }

    var kind: Kind
    /// The gesture's value: `()` for a tap, `true` for a long press, and so
    /// on. A failure has none.
    var value: Any
    /// The callbacks to run when the host lets the event through, innermost
    /// first.
    var effects: [@MainActor () -> Void] = []
}

/// How far a press may move and still be a tap, in points.
let tapSlop = LayoutDefaults.dragThreshold
/// How long a multi-tap waits for its next tap, in seconds.
let multiTapInterval: TimeInterval = 0.35

@MainActor
class GestureRecognizer {
    fileprivate(set) var status = GestureStatus.possible

    /// What the gesture is called in an outline.
    var summary: String { "gesture" }

    /// Whether more movement could still make the gesture active.
    var couldActivate: Bool { false }
    /// Whether the gesture waits for another press, for its next tap, until
    /// a time runs out.
    var isPending: Bool { false }
    /// Whether the passing of time can change the gesture's status.
    var wantsTicks: Bool { false }
    /// Whether the gesture is a long press or has one in it.
    var includesLongPress: Bool { false }
    /// Whether the gesture is a tap or has one in it.
    var includesTap: Bool { false }
    /// Whether recognizing the gesture takes the press from every other
    /// gesture, even those with higher precedence that are still waiting for
    /// the release. A long press does: holding is not tapping.
    var takesPress: Bool { false }

    func handle(_ input: GestureInput) -> [GestureEvent] { [] }

    /// Ends the gesture because another one took the press.
    func cancel() -> [GestureEvent] {
        guard status == .possible || status == .active else { return [] }
        status = .failed
        return []
    }

    /// Takes over the state of the recognizer that was already recognizing
    /// the press when the views were evaluated again, keeping the callbacks
    /// this one has.
    func adopt(from old: GestureRecognizer) {
        status = old.status
    }

    fileprivate func fail() {
        if status == .possible || status == .active { status = .failed }
    }

    fileprivate func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

// MARK: - Tap

final class TapRecognizer: GestureRecognizer {
    let count: Int
    let makeValue: (GestureInput) -> Any
    private let label: String
    private var taps = 0
    private var isDown = false
    private var downPoint = CGPoint.zero
    private var firstPoint = CGPoint.zero
    private var lastUp: TimeInterval = 0

    init(count: Int, label: String = "tap", makeValue: @escaping (GestureInput) -> Any) {
        self.count = max(count, 1)
        self.label = label
        self.makeValue = makeValue
    }

    override var summary: String { count == 1 ? label : "\(label)(count: \(count))" }
    override var isPending: Bool { status == .possible && taps > 0 }
    override var wantsTicks: Bool { isPending }
    override var includesTap: Bool { true }

    override func handle(_ input: GestureInput) -> [GestureEvent] {
        guard status == .possible else { return [] }
        switch input.phase {
        case .down:
            if taps > 0 {
                if input.time - lastUp > multiTapInterval
                    || distance(input.point, firstPoint) > tapSlop
                {
                    fail()
                    return []
                }
            } else {
                firstPoint = input.point
            }
            isDown = true
            downPoint = input.point
        case .move:
            if isDown, distance(input.point, downPoint) > tapSlop { fail() }
        case .up:
            guard isDown else { return [] }
            isDown = false
            taps += 1
            lastUp = input.time
            if distance(input.point, downPoint) > tapSlop {
                fail()
            } else if taps >= count {
                status = .ended
                return [GestureEvent(kind: .ended, value: makeValue(input))]
            }
        case .tick:
            if !isDown, taps > 0, input.time - lastUp > multiTapInterval { fail() }
        }
        return []
    }

    override func adopt(from old: GestureRecognizer) {
        guard let old = old as? TapRecognizer else { return }
        status = old.status
        taps = old.taps
        isDown = old.isDown
        downPoint = old.downPoint
        firstPoint = old.firstPoint
        lastUp = old.lastUp
    }
}

// MARK: - Long press

final class LongPressRecognizer: GestureRecognizer {
    let minimumDuration: TimeInterval
    let maximumDistance: CGFloat
    private var isDown = false
    private var downPoint = CGPoint.zero
    private var downTime: TimeInterval = 0

    init(minimumDuration: TimeInterval, maximumDistance: CGFloat) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
    }

    override var summary: String {
        minimumDuration == 0.5
            ? "longPress" : "longPress(\(formatPoints(CGFloat(minimumDuration))) s)"
    }
    override var wantsTicks: Bool { status == .possible && isDown }
    override var includesLongPress: Bool { true }
    override var takesPress: Bool { true }

    override func handle(_ input: GestureInput) -> [GestureEvent] {
        guard status == .possible else { return [] }
        switch input.phase {
        case .down:
            isDown = true
            downPoint = input.point
            downTime = input.time
            return [GestureEvent(kind: .changed, value: true)]
        case .move:
            guard isDown else { return [] }
            if distance(input.point, downPoint) > maximumDistance {
                fail()
            } else {
                return recognizeIfHeldLongEnough(input)
            }
        case .tick:
            guard isDown else { return [] }
            return recognizeIfHeldLongEnough(input)
        case .up:
            guard isDown else { return [] }
            isDown = false
            let events = recognizeIfHeldLongEnough(input)
            if events.isEmpty { fail() }
            return events
        }
        return []
    }

    private func recognizeIfHeldLongEnough(_ input: GestureInput) -> [GestureEvent] {
        // The clock counts in sums of fractions, which are not exact.
        guard input.time - downTime >= minimumDuration - 0.0005 else { return [] }
        status = .ended
        return [GestureEvent(kind: .ended, value: true)]
    }

    override func adopt(from old: GestureRecognizer) {
        guard let old = old as? LongPressRecognizer else { return }
        status = old.status
        isDown = old.isDown
        downPoint = old.downPoint
        downTime = old.downTime
    }
}

// MARK: - Drag

final class DragRecognizer: GestureRecognizer {
    let minimumDistance: CGFloat
    let space: any CoordinateSpaceProtocol
    private var start = CGPoint.zero
    private var samples: [(time: TimeInterval, point: CGPoint)] = []

    init(minimumDistance: CGFloat, space: any CoordinateSpaceProtocol) {
        self.minimumDistance = minimumDistance
        self.space = space
    }

    override var summary: String {
        minimumDistance == 10 ? "drag" : "drag(minimumDistance: \(formatPoints(minimumDistance)))"
    }
    override var couldActivate: Bool { status == .possible && !samples.isEmpty }

    override func handle(_ input: GestureInput) -> [GestureEvent] {
        guard status == .possible || status == .active else { return [] }
        switch input.phase {
        case .down:
            start = input.point
            samples = [(input.time, input.point)]
            if minimumDistance <= 0 {
                status = .active
                return [GestureEvent(kind: .changed, value: value(input))]
            }
        case .move:
            guard !samples.isEmpty else { return [] }
            samples.append((input.time, input.point))
            samples.removeAll { input.time - $0.time > 0.2 }
            if status == .possible {
                guard distance(input.point, start) >= minimumDistance else { return [] }
                status = .active
            }
            return [GestureEvent(kind: .changed, value: value(input))]
        case .up:
            guard status == .active else {
                fail()
                return []
            }
            samples.append((input.time, input.point))
            status = .ended
            return [GestureEvent(kind: .ended, value: value(input))]
        case .tick:
            break
        }
        return []
    }

    private func value(_ input: GestureInput) -> DragGesture.Value {
        var value = DragGesture.Value(
            time: Date(timeIntervalSinceReferenceDate: input.time),
            location: input.location(in: space),
            startLocation: input.convert(start, in: space))
        // Over the last moments of the press, as a scroll view measures a fling.
        if let first = samples.first, let last = samples.last, last.time > first.time {
            let dt = last.time - first.time
            value.velocity = CGSize(
                width: (last.point.x - first.point.x) / dt,
                height: (last.point.y - first.point.y) / dt)
        }
        return value
    }

    override func adopt(from old: GestureRecognizer) {
        guard let old = old as? DragRecognizer else { return }
        status = old.status
        start = old.start
        samples = old.samples
    }
}

// MARK: - A button, a link, or a text field

/// The tap of a control the press started on. It is the control's own
/// action, and it takes part in arbitration like a tap gesture on the control.
final class ControlRecognizer: GestureRecognizer {
    private let isOverControl: @MainActor (CGPoint) -> Bool
    private let action: @MainActor () -> Void
    private var isDown = false
    private var downPoint = CGPoint.zero

    init(
        isOverControl: @escaping @MainActor (CGPoint) -> Bool,
        action: @escaping @MainActor () -> Void
    ) {
        self.isOverControl = isOverControl
        self.action = action
    }

    override var summary: String { "control" }
    override var includesTap: Bool { true }

    override func handle(_ input: GestureInput) -> [GestureEvent] {
        guard status == .possible else { return [] }
        switch input.phase {
        case .down:
            isDown = true
            downPoint = input.point
        case .move:
            // A press that moves away is no tap on the control: something
            // else, a drag, takes it.
            if isDown, distance(input.point, downPoint) > tapSlop { fail() }
        case .up:
            guard isDown else { return [] }
            isDown = false
            guard isOverControl(input.point) else {
                fail()
                return []
            }
            status = .ended
            return [GestureEvent(kind: .ended, value: (), effects: [action])]
        case .tick: break
        }
        return []
    }
}

// MARK: - Callbacks

/// The callbacks `onChanged`, `onEnded`, and `updating` attach to a gesture.
struct GestureHandlers {
    var onChanged: ((Any) -> Void)?
    var onEnded: ((Any) -> Void)?
    /// Runs on each change with the value, and again with `nil` when the
    /// gesture ends or fails, to put the gesture state back.
    var updating: (@MainActor (Any?) -> Void)?
    /// Runs when the gesture fails or another gesture takes the press, but
    /// not when it ends.
    var onFailed: (@MainActor () -> Void)?
}

final class ModifiedRecognizer: GestureRecognizer {
    let base: GestureRecognizer
    let handlers: GestureHandlers
    /// Whether a change reached the callbacks, so that a failure has
    /// something to put back.
    private var hasChanged = false
    private var didFail = false

    init(base: GestureRecognizer, handlers: GestureHandlers) {
        self.base = base
        self.handlers = handlers
    }

    override var summary: String { base.summary }
    override var couldActivate: Bool { base.couldActivate }
    override var isPending: Bool { base.isPending }
    override var wantsTicks: Bool { base.wantsTicks }
    override var includesLongPress: Bool { base.includesLongPress }
    override var includesTap: Bool { base.includesTap }
    override var takesPress: Bool { base.takesPress }

    override func handle(_ input: GestureInput) -> [GestureEvent] {
        decorate(base.handle(input))
    }

    override func cancel() -> [GestureEvent] {
        decorate(base.cancel())
    }

    private func decorate(_ events: [GestureEvent]) -> [GestureEvent] {
        var result = events.map { event in
            var event = event
            let value = event.value
            switch event.kind {
            case .changed:
                if let updating = handlers.updating {
                    event.effects.append { updating(value) }
                }
                if let onChanged = handlers.onChanged { event.effects.append { onChanged(value) } }
            case .ended:
                if let updating = handlers.updating { event.effects.append { updating(nil) } }
                if let onEnded = handlers.onEnded { event.effects.append { onEnded(value) } }
            case .failed:
                break
            }
            return event
        }
        if !events.isEmpty { hasChanged = true }
        let status = base.status
        self.status = status
        if status == .failed, !didFail, hasChanged || handlers.onFailed != nil {
            didFail = true
            hasChanged = false
            var failure = GestureEvent(kind: .failed, value: ())
            if let updating = handlers.updating { failure.effects.append { updating(nil) } }
            if let onFailed = handlers.onFailed { failure.effects.append(onFailed) }
            result.append(failure)
        }
        return result
    }

    override func adopt(from old: GestureRecognizer) {
        guard let old = old as? ModifiedRecognizer else { return }
        base.adopt(from: old.base)
        status = base.status
        hasChanged = old.hasChanged
        didFail = old.didFail
    }
}

// MARK: - Combinations

/// Runs the first gesture, and the second after the first ends.
final class SequenceRecognizer: GestureRecognizer {
    private enum Stage { case first, waitingForSecond, second }

    let first: GestureRecognizer
    let second: GestureRecognizer
    let wrapFirst: (Any) -> Any
    let wrapSecond: (Any, Any?) -> Any
    private var stage = Stage.first
    private var firstValue: Any = ()
    private var firstEndedAt: TimeInterval = 0

    init(
        first: GestureRecognizer, second: GestureRecognizer,
        wrapFirst: @escaping (Any) -> Any,
        wrapSecond: @escaping (Any, Any?) -> Any
    ) {
        self.first = first
        self.second = second
        self.wrapFirst = wrapFirst
        self.wrapSecond = wrapSecond
    }

    override var summary: String { "sequenced(\(first.summary), \(second.summary))" }
    override var couldActivate: Bool {
        switch stage {
        case .first: first.couldActivate
        case .waitingForSecond: true
        case .second: second.couldActivate
        }
    }
    override var isPending: Bool {
        stage == .waitingForSecond || (stage == .first && first.isPending)
    }
    override var wantsTicks: Bool {
        stage == .waitingForSecond || (stage == .first ? first.wantsTicks : second.wantsTicks)
    }
    override var includesLongPress: Bool { first.includesLongPress || second.includesLongPress }
    override var includesTap: Bool { first.includesTap }

    override func handle(_ input: GestureInput) -> [GestureEvent] {
        guard status == .possible || status == .active else { return [] }
        switch stage {
        case .first:
            return handleFirst(input)
        case .waitingForSecond:
            if input.time - firstEndedAt > multiTapInterval {
                fail()
            } else if input.phase == .down {
                return startSecond(at: input)
            }
            return []
        case .second:
            return handleSecond(input)
        }
    }

    private func handleFirst(_ input: GestureInput) -> [GestureEvent] {
        var result: [GestureEvent] = []
        for event in first.handle(input) {
            var mapped = event
            mapped.value = wrapFirst(event.value)
            switch event.kind {
            case .changed:
                status = .active
                result.append(mapped)
            case .ended:
                firstValue = event.value
                firstEndedAt = input.time
                // The first gesture has ended, but the sequence has not.
                mapped.kind = .changed
                status = .active
                result.append(mapped)
                if input.phase == .up {
                    stage = .waitingForSecond
                } else {
                    result += startSecond(at: input)
                }
            case .failed:
                break
            }
        }
        if stage == .first, first.status == .failed { fail() }
        return result
    }

    private func startSecond(at input: GestureInput) -> [GestureEvent] {
        stage = .second
        var start = input
        start.phase = .down
        var result = [GestureEvent(kind: .changed, value: wrapSecond(firstValue, nil))]
        result += second.handle(start).map(mapSecond)
        if second.status == .ended { status = .ended }
        return result
    }

    private func handleSecond(_ input: GestureInput) -> [GestureEvent] {
        var result = second.handle(input).map(mapSecond)
        switch second.status {
        case .ended:
            status = .ended
        case .failed:
            if input.phase == .up {
                // The press ended before the second gesture began: the
                // sequence ends with the first gesture's value alone.
                status = .ended
                result.append(GestureEvent(kind: .ended, value: wrapSecond(firstValue, nil)))
            } else {
                fail()
            }
        case .possible, .active:
            break
        }
        return result
    }

    private func mapSecond(_ event: GestureEvent) -> GestureEvent {
        var event = event
        event.value = wrapSecond(firstValue, event.value)
        return event
    }

    override func cancel() -> [GestureEvent] {
        let events = stage == .second ? second.cancel() : first.cancel()
        fail()
        return events
    }

    override func adopt(from old: GestureRecognizer) {
        guard let old = old as? SequenceRecognizer else { return }
        first.adopt(from: old.first)
        second.adopt(from: old.second)
        status = old.status
        stage = old.stage
        firstValue = old.firstValue
        firstEndedAt = old.firstEndedAt
    }
}

/// Runs two gestures at once.
final class SimultaneousRecognizer: GestureRecognizer {
    let first: GestureRecognizer
    let second: GestureRecognizer
    /// Makes the combined value from each gesture's latest value.
    let combine: (Any?, Any?) -> Any
    private var firstValue: Any?
    private var secondValue: Any?

    init(
        first: GestureRecognizer, second: GestureRecognizer,
        combine: @escaping (Any?, Any?) -> Any
    ) {
        self.first = first
        self.second = second
        self.combine = combine
    }

    override var summary: String { "simultaneously(\(first.summary), \(second.summary))" }
    override var couldActivate: Bool { first.couldActivate || second.couldActivate }
    override var isPending: Bool { first.isPending || second.isPending }
    override var wantsTicks: Bool { first.wantsTicks || second.wantsTicks }
    override var includesLongPress: Bool { first.includesLongPress || second.includesLongPress }
    override var includesTap: Bool { first.includesTap || second.includesTap }

    override func handle(_ input: GestureInput) -> [GestureEvent] {
        guard status == .possible || status == .active else { return [] }
        var effects: [@MainActor () -> Void] = []
        var changed = false
        for event in first.handle(input) where event.kind != .failed {
            firstValue = event.value
            effects += event.effects
            changed = true
        }
        for event in second.handle(input) where event.kind != .failed {
            secondValue = event.value
            effects += event.effects
            changed = true
        }
        let statuses = [first.status, second.status]
        if statuses.allSatisfy({ $0 == .failed }) {
            fail()
        } else if !statuses.contains(where: { $0 == .possible || $0 == .active }) {
            status = .ended
        } else if statuses.contains(.active) || changed {
            status = .active
        }
        guard changed else { return [] }
        return [
            GestureEvent(
                kind: status == .ended ? .ended : .changed,
                value: combine(firstValue, secondValue), effects: effects)
        ]
    }

    override func cancel() -> [GestureEvent] {
        let events = first.cancel() + second.cancel()
        fail()
        return events
    }

    override func adopt(from old: GestureRecognizer) {
        guard let old = old as? SimultaneousRecognizer else { return }
        first.adopt(from: old.first)
        second.adopt(from: old.second)
        status = old.status
        firstValue = old.firstValue
        secondValue = old.secondValue
    }
}

/// Runs two gestures, and lets the second succeed only if the first fails.
final class ExclusiveRecognizer: GestureRecognizer {
    let first: GestureRecognizer
    let second: GestureRecognizer
    let wrapFirst: (Any) -> Any
    let wrapSecond: (Any) -> Any
    /// What the second gesture reported while the first could still win.
    private var held: [GestureEvent] = []

    init(
        first: GestureRecognizer, second: GestureRecognizer,
        wrapFirst: @escaping (Any) -> Any, wrapSecond: @escaping (Any) -> Any
    ) {
        self.first = first
        self.second = second
        self.wrapFirst = wrapFirst
        self.wrapSecond = wrapSecond
    }

    override var summary: String { "exclusively(\(first.summary), \(second.summary))" }
    override var couldActivate: Bool { first.couldActivate || second.couldActivate }
    override var isPending: Bool { first.isPending || second.isPending }
    override var wantsTicks: Bool { first.wantsTicks || second.wantsTicks }
    override var includesLongPress: Bool { first.includesLongPress || second.includesLongPress }
    override var includesTap: Bool { first.includesTap || second.includesTap }

    override func handle(_ input: GestureInput) -> [GestureEvent] {
        guard status == .possible || status == .active else { return [] }
        let firstEvents = first.handle(input).map(wrapped(wrapFirst))
        if first.status == .active || first.status == .ended {
            held = []
            _ = second.cancel()
            status = first.status
            return firstEvents
        }
        let secondEvents = second.handle(input).map(wrapped(wrapSecond))
        guard first.status == .failed else {
            // The first gesture may still win, so the second waits.
            held += secondEvents
            return []
        }
        let result = held + secondEvents
        held = []
        status = second.status
        return result
    }

    private func wrapped(_ wrap: @escaping (Any) -> Any) -> (GestureEvent) -> GestureEvent {
        { event in
            var event = event
            event.value = wrap(event.value)
            return event
        }
    }

    override func cancel() -> [GestureEvent] {
        let events = first.cancel() + second.cancel()
        fail()
        return events
    }

    override func adopt(from old: GestureRecognizer) {
        guard let old = old as? ExclusiveRecognizer else { return }
        first.adopt(from: old.first)
        second.adopt(from: old.second)
        status = old.status
        held = old.held
    }
}
