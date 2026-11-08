#if canImport(Foundation)
import Foundation
#endif

// The host's side of gestures: which gestures a press reaches, which of them
// wins, and when their callbacks run. See docs/adr/0015-gesture-arbitration.md.

/// A gesture that a view attached, from the last evaluation.
@MainActor
final class GestureRegistration {
    let nodeID: NodeID
    /// Which of the gesture modifiers on the node this is, innermost first,
    /// or a negative number for a gesture with no modifier, such as a
    /// context menu's long press. Its area is then the node's frame.
    let ordinal: Int
    let priority: GesturePriority
    let mask: GestureMask
    /// A recognizer that is never fed, which says what the gesture is.
    let recognizer: GestureRecognizer
    /// Makes a recognizer for a press: each press needs a fresh one.
    let make: @MainActor () -> GestureRecognizer

    init(
        nodeID: NodeID, ordinal: Int, priority: GesturePriority, mask: GestureMask,
        recognizer: GestureRecognizer, make: @escaping @MainActor () -> GestureRecognizer
    ) {
        self.make = make
        self.nodeID = nodeID
        self.ordinal = ordinal
        self.priority = priority
        self.mask = mask
        self.recognizer = recognizer
    }
}

/// What the host keeps for gestures.
@MainActor
struct GestureHostState {
    /// The gestures of the last evaluation, by node.
    var registrations: [NodeID: [GestureRegistration]] = [:]
    private var collecting: [NodeID: [GestureRegistration]] = [:]
    /// The press being recognized, or a multi-tap waiting for its next tap.
    var session: GestureSession?

    var hasRegistrations: Bool { !registrations.isEmpty }

    /// Whether the clock should keep moving for a gesture: a long press
    /// waiting for its time, or a multi-tap waiting for its next tap.
    var wantsTicks: Bool { session?.wantsTicks ?? false }

    mutating func beginEvaluation() {
        collecting = [:]
    }

    mutating func register(_ registration: GestureRegistration) {
        collecting[registration.nodeID, default: []].append(registration)
    }

    /// The ordinal for a gesture on a node that has no modifier of its own:
    /// -1 for the first, -2 for the next.
    func nextUnmarkedOrdinal(for id: NodeID) -> Int {
        -1 - (collecting[id] ?? []).count { $0.ordinal < 0 }
    }

    /// Replaces the gestures with the ones just evaluated. A press in
    /// progress keeps its state: the new recognizers take it over, and bring
    /// the callbacks of the latest evaluation.
    mutating func finishEvaluation() {
        registrations = collecting
        collecting = [:]
        session?.rebind(to: registrations)
    }
}

/// One recognizer that takes part in a press.
@MainActor
final class GestureItem {
    enum Source {
        case gesture(nodeID: NodeID, ordinal: Int)
        /// The action of the button, link, or text field under the press.
        case control(NodeID)
    }

    let source: Source
    let priority: GesturePriority
    /// The position of the node in the chain from the root: deeper nodes
    /// have larger depths.
    let depth: Int
    var recognizer: GestureRecognizer
    /// What the recognizer reported while a gesture with higher precedence
    /// could still win.
    var held: [GestureEvent] = []
    /// Whether any callback has run, so that cancelling has something to put
    /// back.
    var delivered = false

    init(source: Source, priority: GesturePriority, depth: Int, recognizer: GestureRecognizer) {
        self.source = source
        self.priority = priority
        self.depth = depth
        self.recognizer = recognizer
    }

    var isControl: Bool {
        if case .control = source { return true }
        return false
    }

    var nodeID: NodeID {
        switch source {
        case .gesture(let id, _): id
        case .control(let id): id
        }
    }

    var status: GestureStatus { recognizer.status }

    /// Whether the item can still do something.
    var isLive: Bool {
        recognizer.status == .possible || recognizer.status == .active || !held.isEmpty
    }

    /// Runs the callbacks of what the recognizer reported.
    func deliver() {
        let events = held
        held = []
        for event in events {
            delivered = true
            event.effects.forEach { $0() }
        }
    }

    /// Ends the item because another gesture took the press, putting back
    /// what its callbacks changed.
    func cancel() {
        let events = recognizer.cancel()
        held = []
        guard delivered else { return }
        for event in events { event.effects.forEach { $0() } }
    }
}

/// The recognizers a press reaches, in the order they win.
@MainActor
final class GestureSession {
    /// Gestures that win over what is inside them come first, then the
    /// others, the deepest view first. A button or text field comes after
    /// the gestures on its own view.
    private(set) var items: [GestureItem]
    /// Gestures that recognize the press whatever else does.
    private(set) var simultaneous: [GestureItem]
    /// The node identifiers from the root to the frontmost view under the
    /// press.
    let chain: [NodeID]
    /// The last place the pointer was, for the passing of time.
    private(set) var lastPoint: CGPoint
    /// The control whose action ran.
    private(set) var firedControl: NodeID?

    init(items: [GestureItem], simultaneous: [GestureItem], chain: [NodeID], point: CGPoint) {
        self.items = items
        self.simultaneous = simultaneous
        self.chain = chain
        lastPoint = point
    }

    var all: [GestureItem] { items + simultaneous }

    var isLive: Bool { all.contains { $0.isLive } }

    var isPending: Bool {
        all.contains { ($0.status == .possible || $0.status == .active) && $0.recognizer.isPending }
    }

    var wantsTicks: Bool {
        all.contains {
            ($0.status == .possible || $0.status == .active) && $0.recognizer.wantsTicks
        }
    }

    /// How deep in the chain the scroll view or sheet is that the press may
    /// still turn into, or `nil`. Gestures on it and outside it wait for it.
    var scrollDepth: Int?

    /// Whether a gesture, not a control, has recognized the press and taken it
    /// from the controls and scroll views below it.
    var hasClaimed: Bool {
        items.contains {
            !$0.isControl && ($0.status == .active || $0.status == .ended) && $0.held.isEmpty
        }
    }

    /// Whether a control is no longer a candidate for the press.
    func isControlOut(_ id: NodeID) -> Bool {
        guard let item = items.first(where: { $0.nodeID == id && $0.isControl }) else {
            return false
        }
        return item.status == .failed
    }

    /// Whether a gesture on a view inside the scroll view or sheet `node`,
    /// or one that has priority, has the press or may still get it. With
    /// `includingNode`, a gesture on `node` itself counts too, as for a list
    /// row that would swipe.
    func blocksScroll(of node: NodeID, includingNode: Bool = false) -> Bool {
        let scrollDepth = chain.firstIndex(of: node) ?? -1
        return items.contains { item in
            let inside = item.depth > scrollDepth || (includingNode && item.depth == scrollDepth)
            guard !item.isControl, item.priority == .high || inside else {
                return false
            }
            return item.status == .active || item.recognizer.couldActivate
        }
    }

    /// Gives the press to a scroll view or a sheet: every gesture that is
    /// not simultaneous ends.
    func cancelCompeting() {
        items.forEach { $0.cancel() }
    }

    /// Whether any recognizer is a long press.
    var includesLongPress: Bool { all.contains { $0.recognizer.includesLongPress } }

    /// Whether any recognizer takes a tap (not counting a control).
    var includesTap: Bool { all.contains { !$0.isControl && $0.recognizer.includesTap } }

    /// Feeds the pointer to the recognizers, and runs the callbacks of the ones
    /// that win.
    ///
    /// A recognizer with higher precedence is asked first. While one that is
    /// asked earlier could still win, what the others report waits. When one
    /// recognizes the press, the others that are not simultaneous end.
    func process(
        _ phase: GestureInput.Phase, at point: CGPoint, time: TimeInterval,
        origin: (GestureItem) -> CGPoint
    ) {
        if phase != .tick { lastPoint = point }
        func input(for item: GestureItem) -> GestureInput {
            GestureInput(phase: phase, point: point, time: time, origin: origin(item))
        }

        var claimed = false
        var undecided = false
        for item in items {
            if claimed {
                item.cancel()
                continue
            }
            if item.status == .failed, item.held.isEmpty { continue }
            if item.status == .possible || item.status == .active {
                item.held += item.recognizer.handle(input(for: item))
            }
            // A scroll view that the press may become wins over the gestures
            // on it and outside it, unless they have priority.
            if let scrollDepth, phase == .move, item.priority == .normal, item.depth <= scrollDepth
            {
                undecided = true
            }
            if !undecided { item.deliver() }
            switch item.status {
            case .ended, .active:
                if item.held.isEmpty {
                    claimed = true
                    if item.recognizer.takesPress {
                        for other in items where other !== item && other.status == .possible {
                            other.cancel()
                        }
                    }
                } else {
                    undecided = true
                }
            case .possible:
                if item.recognizer.couldActivate || item.recognizer.isPending || !item.held.isEmpty
                {
                    undecided = true
                }
            case .failed:
                break
            }
            // A press that has ended settles every recognizer except one that
            // waits for another press.
            if phase == .up, item.status == .active || item.status == .possible,
                !item.recognizer.isPending
            {
                item.cancel()
            }
        }
        for item in simultaneous {
            guard item.status == .possible || item.status == .active else { continue }
            item.held += item.recognizer.handle(input(for: item))
            item.deliver()
            if phase == .up, item.status != .ended, item.status != .failed,
                !item.recognizer.isPending
            {
                item.cancel()
            }
        }
    }

    /// Takes over the state of the recognizers from a new evaluation of the
    /// views, so that a press carries on across a state change.
    func rebind(to registrations: [NodeID: [GestureRegistration]]) {
        for item in all {
            guard case .gesture(let nodeID, let ordinal) = item.source,
                let registration = registrations[nodeID]?.first(where: { $0.ordinal == ordinal })
            else { continue }
            let recognizer = registration.make()
            recognizer.adopt(from: item.recognizer)
            item.recognizer = recognizer
        }
    }

    /// Records that a control's action ran.
    func fired(_ id: NodeID) { firedControl = id }
}

extension ViewHost {
    // MARK: - Hit testing

    /// The nodes from the root to the frontmost node under a point, found
    /// the way a tap finds its target.
    func hitChain(at point: CGPoint, in node: ViewNode) -> [ViewNode]? {
        let isInside =
            NodeExtensions.behavior(for: node.kind)?.hitTest?(node, point)
            ?? node.hitFrame?.contains(point) ?? false
        if node.isScrollContainer, !isInside { return nil }
        for child in node.hitOrder {
            if let chain = hitChain(at: point, in: child) { return [node] + chain }
        }
        // A gesture's area includes what the modifiers inside it add, such as
        // padding.
        let onGesture =
            (gestures.registrations[node.id] ?? []).contains {
                gestureRegion(of: node, ordinal: $0.ordinal)?.contains(point) == true
            }
        return isInside || onGesture ? [node] : nil
    }

    /// The area of the `ordinal`th gesture on a node: the bounds its modifier
    /// was placed in.
    func gestureRegion(of node: ViewNode, ordinal: Int) -> CGRect? {
        var count = 0
        for (index, modifier) in node.modifiers.enumerated() where modifier.isGesture {
            if count == ordinal {
                return index < node.modifierFrames.count ? node.modifierFrames[index] : node.frame
            }
            count += 1
        }
        return node.frame
    }

    private func gestureOrigin(of item: GestureItem) -> CGPoint {
        guard case .gesture(let nodeID, let ordinal) = item.source,
            let node = root.node(withID: nodeID)
        else { return .zero }
        return gestureRegion(of: node, ordinal: ordinal)?.origin ?? .zero
    }

    // MARK: - Pressing

    /// Starts recognizing a press at a point. `control` is the button, link,
    /// or text field the press started on.
    func beginGesturePress(at point: CGPoint, control: NodeID?) {
        if let session = gestures.session {
            // A multi-tap carries on with the next press, if it is close and
            // soon enough for the recognizers to say so.
            if session.isPending {
                session.process(.down, at: point, time: time, origin: gestureOrigin(of:))
                if session.isLive {
                    finishGestureStep()
                    return
                }
            }
            gestures.session = nil
        }
        guard gestures.hasRegistrations,
            let nodes = hitChain(at: point, in: interactiveRoot)
        else { return }

        // Outermost first, so that a gesture that leaves out its subviews cuts
        // off what is inside it.
        var perNode: [[GestureItem]] = []
        var cutOff = false
        for (depth, node) in nodes.enumerated() {
            var own: [GestureItem] = []
            for registration in (gestures.registrations[node.id] ?? []).reversed() where !cutOff {
                guard
                    gestureRegion(of: node, ordinal: registration.ordinal)?.contains(point) == true
                else { continue }
                if registration.mask.contains(.gesture) {
                    own.append(
                        GestureItem(
                            source: .gesture(nodeID: node.id, ordinal: registration.ordinal),
                            priority: registration.priority, depth: depth,
                            recognizer: registration.make()))
                }
                if !registration.mask.contains(.subviews) { cutOff = true }
            }
            // Inner modifiers win over outer ones, and a control comes last
            // on its view: a gesture put on a button replaces its action.
            own.reverse()
            if !cutOff, let control, node.id == control {
                own.append(
                    GestureItem(
                        source: .control(control), priority: .normal, depth: depth,
                        recognizer: makeControlRecognizer(control)))
            }
            perNode.append(own)
        }
        let ordered = perNode.reversed().flatMap { $0 }
        guard ordered.contains(where: { !$0.isControl }) else { return }
        let session = GestureSession(
            items: ordered.filter { $0.priority == .high }
                + ordered.filter { $0.priority == .normal },
            simultaneous: ordered.filter { $0.priority == .simultaneous },
            chain: nodes.map(\.id), point: point)
        gestures.session = session
        session.process(.down, at: point, time: time, origin: gestureOrigin(of:))
        finishGestureStep()
    }

    private func makeControlRecognizer(_ id: NodeID) -> GestureRecognizer {
        ControlRecognizer(
            isOverControl: { [unowned self] point in
                frontmostTappableNode(at: point, in: interactiveRoot)?.id == id
            },
            action: { [unowned self] in
                gestures.session?.fired(id)
                if textFields[id] != nil {
                    focusTextField(id, caretAt: gestures.session?.lastPoint ?? .zero)
                } else {
                    try? tap(id)
                }
            })
    }

    /// Moves a press. `scrollView` is the scroll view the press may turn into,
    /// if it has not yet.
    func moveGesturePress(to point: CGPoint, scrollView: NodeID?) {
        guard let session = gestures.session else { return }
        session.scrollDepth = scrollView.flatMap { session.chain.firstIndex(of: $0) }
        session.process(.move, at: point, time: time, origin: gestureOrigin(of:))
        settleControl()
        finishGestureStep()
    }

    /// Ends a press. Returns the control that was tapped, if its action ran,
    /// or `nil` if there is no session.
    func releaseGesturePress(at point: CGPoint) -> (tapped: NodeID?, handled: Bool) {
        guard let session = gestures.session else { return (nil, false) }
        session.process(.up, at: point, time: time, origin: gestureOrigin(of:))
        let tapped = session.firedControl
        finishGestureStep()
        return (tapped, true)
    }

    /// Lets time pass for a gesture that waits for it.
    func tickGesturePress() {
        guard let session = gestures.session, session.wantsTicks || session.isPending else {
            return
        }
        session.process(.tick, at: session.lastPoint, time: time, origin: gestureOrigin(of:))
        settleControl()
        finishGestureStep()
    }

    /// Gives the press to a scroll view or sheet, if no gesture has the press
    /// or may still get it. Returns whether it did. With `includingNode`,
    /// gestures on `node` itself keep the press too.
    func handOverPress(to node: NodeID?, includingNode: Bool = false) -> Bool {
        guard let session = gestures.session else { return true }
        if let node, session.blocksScroll(of: node, includingNode: includingNode) { return false }
        if session.hasClaimed { return false }
        session.cancelCompeting()
        settleControl()
        return true
    }

    /// Whether a gesture, not a control, has the press.
    var gestureHasPress: Bool { gestures.session?.hasClaimed ?? false }

    /// Stops dimming a button that a gesture took the press from.
    private func settleControl() {
        guard let session = gestures.session, let button = press?.button else { return }
        if session.hasClaimed || session.isControlOut(button) {
            press?.button = nil
            pressedNodeID = nil
        }
    }

    /// Updates the views after callbacks ran, and drops a session that is
    /// done.
    private func finishGestureStep() {
        if let session = gestures.session, !session.isLive { gestures.session = nil }
        if needsUpdate { update() }
    }

    // MARK: - Entry points

    /// Taps a view that has a tap gesture, at the middle of its first gesture's
    /// area.
    func tapThroughGestures(on id: NodeID) -> Bool {
        guard
            let registration = gestures.registrations[id]?.first(where: {
                $0.recognizer.includesTap
            }),
            let node = root.node(withID: id),
            let region = gestureRegion(of: node, ordinal: registration.ordinal)
        else { return false }
        let point = CGPoint(x: region.midX, y: region.midY)
        pointerDown(at: point)
        pointerUp(at: point)
        return true
    }

    /// Taps the point as a press, if a tap gesture is under it.
    func tapThroughGestures(at point: CGPoint) -> Bool {
        guard gestures.hasRegistrations,
            let nodes = hitChain(at: point, in: interactiveRoot),
            nodes.contains(where: { node in
                (gestures.registrations[node.id] ?? []).contains {
                    $0.recognizer.includesTap
                        && gestureRegion(of: node, ordinal: $0.ordinal)?.contains(point) == true
                }
            })
        else { return false }
        pointerDown(at: point)
        pointerUp(at: point)
        return true
    }

    /// Whether a long press gesture is under the point.
    func hasLongPressGesture(at point: CGPoint) -> Bool {
        guard gestures.hasRegistrations, let nodes = hitChain(at: point, in: interactiveRoot)
        else { return false }
        return nodes.contains { node in
            (gestures.registrations[node.id] ?? []).contains {
                $0.recognizer.includesLongPress
                    && gestureRegion(of: node, ordinal: $0.ordinal)?.contains(point) == true
            }
        }
    }
}
