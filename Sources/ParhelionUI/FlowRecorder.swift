import ParhelionPreview

#if canImport(Foundation)
import Foundation
#endif

/// Turns the input a window host sends into the steps of a ``Flow``, and
/// writes the flow to a file after every step.
///
/// A tap names the control it hit, so that the flow survives layout changes:
/// by its accessibility identifier if that finds only it, else by its label if
/// that finds only it, else by its node identifier, and by its point only for
/// controls the commands cannot name, such as a slider. A press that moved
/// like a drag becomes a `drag`, the wheel becomes `scroll`, typing becomes
/// `typeText`, and editing keys become `pressKey`. The real time between
/// steps becomes `wait` steps.
///
/// The session calls the recorder around each input it applies, because a tap
/// has to be named from the screen as it was before the tap ran.
@MainActor
final class FlowRecorder {
    /// Waits shorter than this are not recorded: they are the gap between two
    /// events of one gesture, not a pause a person made.
    static let shortestWait: TimeInterval = 0.05
    /// The longest wait recorded. A person who left the window for a minute
    /// did not mean the app to wait that long.
    static let longestWait: TimeInterval = 10

    private let host: ViewHost
    private let path: String
    private(set) var flow: Flow
    /// When the last step ended, in ``PreviewClock`` time.
    private var lastEnd: UInt64

    /// A press in progress.
    private struct Press {
        var start: CGPoint
        var began: UInt64
        var moved = false
        /// How a tap on the control under the press is named, from the screen
        /// as it was when the press began.
        var tap: (id: NodeID, command: PreviewCommand)?
    }
    private var press: Press?

    init(host: ViewHost, path: String) {
        self.host = host
        self.path = path
        flow = Flow(device: host.device.name)
        lastEnd = PreviewClock.now()
    }

    /// Starts the flow with the appearance the app began in, if it is not
    /// the default, and a checkpoint of the first screen.
    func start() {
        if host.colorScheme != .light || host.dynamicTypeSize != .large {
            append(
                .command(
                    .setAppearance(
                        colorScheme: host.colorScheme.name,
                        dynamicTypeSize: host.dynamicTypeSize.name)))
        }
        if host.reduceMotion { append(.command(.setReduceMotion(true))) }
        checkpoint()
    }

    // MARK: - Input

    /// Call before the host applies the press.
    func pointerDown(at point: CGPoint) {
        host.update()
        let target = host.tappableNode(at: point)
        press = Press(
            start: point, began: PreviewClock.now(),
            tap: target.map { ($0.id, tapCommand(for: $0, at: point)) })
    }

    func pointerMoved(to point: CGPoint) {
        guard var current = press else { return }
        if hypot(point.x - current.start.x, point.y - current.start.y)
            > LayoutDefaults.dragThreshold
        {
            current.moved = true
            press = current
        }
    }

    /// Call after the host applied the release; `tapped` is what it returned.
    func pointerUp(at point: CGPoint, tapped: NodeID?) {
        guard let current = press else { return }
        press = nil
        let now = PreviewClock.now()
        if current.moved {
            let duration = min(max(PreviewClock.seconds(now - current.began), 0.02), 5)
            append(
                .command(
                    .drag(
                        fromX: Double(current.start.x), fromY: Double(current.start.y),
                        toX: Double(point.x), toY: Double(point.y),
                        duration: (duration * 1000).rounded() / 1000)),
                from: current.began, to: now)
        } else if let tapped {
            if let target = current.tap, target.id == tapped {
                append(.command(target.command), from: current.began, to: now)
            } else {
                append(
                    .command(.tapPoint(x: Double(point.x), y: Double(point.y))),
                    from: current.began, to: now)
            }
        }
    }

    /// Call with whether the host scrolled anything.
    func scroll(dx: Double, dy: Double, x: Double, y: Double, scrolled: Bool) {
        guard scrolled else { return }
        let now = PreviewClock.now()
        // The wheel sends many small events; they become one scroll.
        if gap(before: now) == nil,
            case .command(.scroll(let ox, let oy, let sx, let sy)) = flow.steps.last,
            sx == x, sy == y
        {
            flow.steps[flow.steps.count - 1] = .command(
                .scroll(dx: ox + dx, dy: oy + dy, x: x, y: y))
            lastEnd = now
            write()
            return
        }
        append(.command(.scroll(dx: dx, dy: dy, x: x, y: y)))
    }

    /// Call before the host applies the text.
    func text(_ text: String) {
        guard host.focusedNodeID != nil, !text.isEmpty else { return }
        let now = PreviewClock.now()
        if gap(before: now) == nil, case .command(.typeText(let typed)) = flow.steps.last {
            flow.steps[flow.steps.count - 1] = .command(.typeText(typed + text))
            lastEnd = now
            write()
            return
        }
        append(.command(.typeText(text)))
    }

    /// Records the text a paste read from the clipboard.
    func pasteboard(_ text: String) {
        append(.command(.setPasteboard(text)))
    }

    func key(_ name: String) {
        guard ViewHost.Key(rawValue: name) != nil else { return }
        append(.command(.pressKey(name)))
    }

    /// Records a change of appearance that worked.
    func appearance(_ command: PreviewCommand) {
        switch command {
        case .setAppearance, .setReduceMotion: append(.command(command))
        default: return
        }
    }

    // MARK: - Checkpoints

    /// Adds a checkpoint of the screen as it is now.
    func checkpoint() {
        host.update()
        append(.expect(outline: host.root.outline()))
    }

    /// Ends the recording with a checkpoint of the final screen, unless the
    /// last step already is one, and writes the file.
    func finish() {
        host.update()
        let outline = host.root.outline()
        if case .expect(let last) = flow.steps.last, last == outline {
            write()
        } else {
            append(.expect(outline: outline))
        }
    }

    // MARK: - Steps

    /// The wait before an event at `time`, or `nil` if it is too short to
    /// record.
    private func gap(before time: UInt64) -> TimeInterval? {
        guard time > lastEnd else { return nil }
        let seconds = PreviewClock.seconds(time - lastEnd)
        return seconds >= Self.shortestWait ? min(seconds, Self.longestWait) : nil
    }

    private func append(_ step: FlowStep, from began: UInt64? = nil, to end: UInt64? = nil) {
        if let wait = gap(before: began ?? PreviewClock.now()) {
            flow.steps.append(.wait(seconds: (wait * 100).rounded() / 100))
        }
        flow.steps.append(step)
        lastEnd = end ?? PreviewClock.now()
        write()
    }

    /// Writes the file. A recording that cannot be written says so once on
    /// standard error and goes on.
    private func write() {
        do {
            try flow.encoded().write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            guard !reportedWriteFailure else { return }
            reportedWriteFailure = true
            FileHandle.standardError.write(
                Data("parhelion: cannot write the recording to \(path): \(error)\n".utf8))
        }
    }
    private var reportedWriteFailure = false

    // MARK: - Naming

    /// The command that taps `node`, named as the type's comment says.
    private func tapCommand(for node: ViewNode, at point: CGPoint) -> PreviewCommand {
        // A slider's knob follows the point; no command names that.
        if node.kind == "Slider" { return .tapPoint(x: Double(point.x), y: Double(point.y)) }
        let isField = host.isTextField(node.id)
        let isTarget: (ViewNode) -> Bool = { [host] in
            isField ? host.isTextField($0.id) : host.hasAction($0.id)
        }
        let entries = host.interactiveRoot.accessibilityEntries()
        if let identifier = entries.first(where: { $0.node.id == node.id })?.identifier,
            host.interactiveRoot.resolveAccessibilityIdentifier(identifier, isTarget: isTarget)
                == .found(node.id)
        {
            return isField
                ? .focusAccessibilityIdentifier(identifier)
                : .tapAccessibilityIdentifier(identifier)
        }
        if !isField {
            let label = node.label
            let sameLabel = host.interactiveRoot.allNodes.filter {
                host.hasAction($0.id) && $0.label == label
            }
            if !label.isEmpty, sameLabel.count == 1 { return .tapButton(label: label) }
            return .tapNode(id: node.id.rawValue)
        }
        return .focus(id: node.id.rawValue)
    }
}
