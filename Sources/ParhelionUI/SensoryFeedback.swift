#if canImport(Foundation)
import Foundation
#endif

/// A haptic or sound, mirroring SwiftUI's `SensoryFeedback`.
///
/// Linux has no haptics, so nothing plays. A view's
/// ``View/sensoryFeedback(_:trigger:)`` records each feedback it would play
/// on the ``ViewHost``; see ``ViewHost/sensoryFeedbackEvents``.
public struct SensoryFeedback: Equatable, Sendable {
    let name: String

    public struct Weight: Equatable, Sendable {
        let name: String
        public static let light = Weight(name: "light")
        public static let medium = Weight(name: "medium")
        public static let heavy = Weight(name: "heavy")
    }

    public struct Flexibility: Equatable, Sendable {
        let name: String
        public static let rigid = Flexibility(name: "rigid")
        public static let solid = Flexibility(name: "solid")
        public static let soft = Flexibility(name: "soft")
    }

    public static let success = SensoryFeedback(name: "success")
    public static let warning = SensoryFeedback(name: "warning")
    public static let error = SensoryFeedback(name: "error")
    public static let selection = SensoryFeedback(name: "selection")
    public static let increase = SensoryFeedback(name: "increase")
    public static let decrease = SensoryFeedback(name: "decrease")
    public static let start = SensoryFeedback(name: "start")
    public static let stop = SensoryFeedback(name: "stop")
    public static let alignment = SensoryFeedback(name: "alignment")
    public static let levelChange = SensoryFeedback(name: "levelChange")
    public static let impact = SensoryFeedback(name: "impact")

    public static func impact(
        weight: Weight = .medium, intensity: Double = 1.0
    )
        -> SensoryFeedback
    {
        SensoryFeedback(name: "impact.\(weight.name)" + intensitySuffix(intensity))
    }

    public static func impact(
        flexibility: Flexibility, intensity: Double = 1.0
    )
        -> SensoryFeedback
    {
        SensoryFeedback(name: "impact.\(flexibility.name)" + intensitySuffix(intensity))
    }

    /// ` x0.5` for an intensity other than 1, so that two impacts of
    /// different strength read differently in the log.
    private static func intensitySuffix(_ intensity: Double) -> String {
        intensity == 1 ? "" : " x\(formatPoints(CGFloat(intensity)))"
    }
}

extension View {
    /// Plays `feedback` when `trigger` changes. Parhelion records it instead:
    /// see ``ViewHost/sensoryFeedbackEvents``.
    public func sensoryFeedback<T: Equatable>(
        _ feedback: SensoryFeedback, trigger: T
    ) -> some View {
        SensoryFeedbackView(
            content: self, label: feedback.name, trigger: trigger,
            choose: { _, _ in feedback })
    }

    /// Plays the feedback that `feedback` returns for the old and new values
    /// of `trigger` when it changes, or none when it returns `nil`.
    public func sensoryFeedback<T: Equatable>(
        trigger: T, _ feedback: @escaping (T, T) -> SensoryFeedback?
    ) -> some View {
        SensoryFeedbackView(
            content: self, label: "dynamic", trigger: trigger, choose: feedback)
    }

    /// Plays `feedback` when `trigger` changes and `condition` returns `true`
    /// for its old and new values.
    public func sensoryFeedback<T: Equatable>(
        _ feedback: SensoryFeedback, trigger: T, condition: @escaping (T, T) -> Bool
    ) -> some View {
        SensoryFeedbackView(
            content: self, label: feedback.name, trigger: trigger,
            choose: { old, new in condition(old, new) ? feedback : nil })
    }
}

/// A view that records feedback when a trigger changes. It marks its nodes
/// with `sensoryFeedback=<name>` (`dynamic` when the feedback depends on the
/// values), joined with a comma when several modifiers cover one node.
struct SensoryFeedbackView<Content: View, T: Equatable>: View {
    typealias Body = Never

    let content: Content
    let label: String
    let trigger: T
    let choose: (T, T) -> SensoryFeedback?

    var body: Never {
        fatalError("SensoryFeedbackView is a primitive view and has no body.")
    }
}

extension SensoryFeedbackView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        // Watching the trigger is `onChange(of:)`: the first value is not a
        // change, and the action runs after the update, in tree order.
        let target = FeedbackTarget(fallback: path.id)
        let host = evaluator.host
        let choose = choose
        let observer = ChangeObserver(value: trigger, initial: false) { (old: T, new: T) in
            guard let feedback = choose(old, new) else { return }
            MainActor.assumeIsolated { host.recordSensoryFeedback(feedback.name, at: target.id) }
        }
        let index = evaluator.lifecycle.begin(.change(observer), at: path)
        var nodes = evaluator.evaluate(content, at: path)
        evaluator.lifecycle.end(index, nodes: nodes)
        target.id = nodes.first?.id ?? path.id
        for i in nodes.indices {
            let existing = nodes[i].attributes[SensoryFeedbackKey.attribute]
            nodes[i].attributes[SensoryFeedbackKey.attribute] =
                existing.map { $0 + "," + label } ?? label
        }
        return nodes
    }
}

/// The node a modifier's feedback is recorded against, known once its
/// content has been evaluated.
private final class FeedbackTarget: @unchecked Sendable {
    var id: NodeID
    init(fallback: NodeID) { id = fallback }
}

enum SensoryFeedbackKey {
    /// The attribute that names a view's feedback, and that lists the recent
    /// events on the root, oldest first.
    static let attribute = "sensoryFeedback"
}

/// One feedback that a view asked for, as ``ViewHost`` recorded it.
public struct SensoryFeedbackEvent: Equatable, Hashable, Sendable, Codable {
    /// 1 for the first event of a host, then increasing by 1.
    public var sequence: Int
    /// SwiftUI's name for the feedback, such as `selection`, `success`, or
    /// `impact.medium`. An impact whose intensity is not 1 adds ` x0.5`.
    public var feedback: String
    /// The node of the view that asked for it.
    public var node: NodeID
    /// The host's ``ViewHost/time`` when the view asked.
    public var time: TimeInterval
}

/// The recent feedback events of a host.
struct SensoryFeedbackLog {
    /// How many events the log keeps; older ones are dropped.
    static let capacity = 50
    /// How many of the newest events the root node lists.
    static let listed = 10

    var events: [SensoryFeedbackEvent] = []
    var total = 0

    mutating func record(_ feedback: String, at node: NodeID, time: TimeInterval) {
        total += 1
        events.append(
            SensoryFeedbackEvent(sequence: total, feedback: feedback, node: node, time: time))
        if events.count > Self.capacity { events.removeFirst(events.count - Self.capacity) }
    }

    /// The value of the root's `sensoryFeedback` attribute, or `nil` when the
    /// log is empty.
    var rootValue: String? {
        guard !events.isEmpty else { return nil }
        return events.suffix(Self.listed).map(\.feedback).joined(separator: ",")
    }
}

extension ViewHost {
    /// The feedback that views asked for, oldest first, up to the last 50.
    /// Linux plays nothing, so this is where a test or an agent checks a
    /// haptic. The root node lists the newest ten in its `sensoryFeedback`
    /// attribute, and `PARHELION_DEBUG=1` logs each one.
    public var sensoryFeedbackEvents: [SensoryFeedbackEvent] { sensoryFeedbackLog.events }

    /// Forgets the recorded feedback.
    public func clearSensoryFeedback() {
        guard !sensoryFeedbackLog.events.isEmpty else { return }
        sensoryFeedbackLog.events = []
        setNeedsUpdate()
        update()
    }

    /// Records a feedback, and marks the tree for an update that lists it.
    func recordSensoryFeedback(_ feedback: String, at node: NodeID) {
        sensoryFeedbackLog.record(feedback, at: node, time: time)
        if ProcessInfo.processInfo.environment["PARHELION_DEBUG"] != nil {
            FileHandle.standardError.write(
                Data("parhelion app: sensory feedback \(feedback) at \(node)\n".utf8))
        }
        setNeedsUpdate()
    }

    /// What the events are, for a command's reply.
    var sensoryFeedbackDescription: String {
        let events = sensoryFeedbackLog.events
        guard !events.isEmpty else { return "No sensory feedback has played." }
        let lines = events.map { event in
            "\(event.sequence). \(event.feedback) at \(event.node) (t=\(formatPoints(CGFloat(event.time))) s)"
        }
        let count =
            events.count == 1
            ? "1 sensory feedback event" : "\(events.count) sensory feedback events"
        return "\(count):\n" + lines.joined(separator: "\n")
    }
}
