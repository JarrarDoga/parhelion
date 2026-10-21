#if canImport(Foundation)
import Foundation
#endif

/// An error from driving a view through a ``ViewHost``.
public enum InteractionError: Error, Equatable, Sendable {
    /// No node in the current tree has this identifier.
    case nodeNotFound(NodeID)
    /// The node exists but does not respond to taps.
    case notTappable(NodeID)
    /// No button's label matches the given text.
    case noButton(label: String)
    /// More than one button's label matches the given text.
    case ambiguousButton(label: String, matches: [NodeID])
    /// No node that responds to taps contains the given point.
    case nothingTappable(at: CGPoint)
    /// The node is not a scroll view.
    case notScrollable(NodeID)
    /// The node is not a text field.
    case notEditable(NodeID)
    /// The node is behind a sheet or an alert, which receives input instead.
    case covered(NodeID)
}

/// Owns a view hierarchy: resolves it to a ``ViewNode`` tree, lays it out for
/// a device, keeps its state, and delivers interactions to it.
///
/// `ViewHost` is the boundary that the preview window, tests, and agents all
/// use. Nothing here depends on a window or a GPU, so it also works without a
/// display.
///
/// ```swift
/// let host = ViewHost(CounterView())
/// try host.tapButton(labeled: "Increment")
/// print(host.root.outline())
/// ```
@MainActor
public final class ViewHost {
    private let rootView: any View
    private let layoutEngine: LayoutEngine
    private let scrolling: ScrollLayout
    /// The tree as evaluated, before layout. Scrolling lays it out again
    /// without evaluating views.
    private var resolvedRoot = ViewNode(id: "", kind: "Root")
    private var storage: [String: AnyObject] = [:]
    private var visitedKeys: Set<String> = []
    private var actions: [NodeID: @MainActor () -> Void] = [:]
    private var textFields: [NodeID: Binding<String>] = [:]
    /// The entries each navigation stack keeps above its root view, by the
    /// stack's identifier.
    var navigationState: [NodeID: [NavigationEntry]] = [:]
    var visitedNavigationStacks: Set<NodeID> = []
    /// The presentations on screen, by identifier.
    private var presentations: [NodeID: Presentation] = [:]

    /// Whether a state change is waiting for the next ``update()``.
    public private(set) var needsUpdate = false

    /// The resolved and laid-out tree. Its root node has kind `"Root"` and
    /// covers the whole screen.
    public private(set) var root = ViewNode(id: "", kind: "Root")

    /// The device the tree is laid out for.
    public let device: Device

    /// A number that increases whenever anything on screen changes: the
    /// tree, the layout, a scroll position, or the pressed button. Clients
    /// compare it to decide whether to draw a new frame.
    public private(set) var revision = 0

    /// The host's clock, in seconds. It advances only through
    /// ``advanceTime(by:)``, so animations are deterministic: the same input
    /// at the same times always produces the same frames.
    public private(set) var time: TimeInterval = 0

    /// Creates a host for a view.
    ///
    /// - Parameter snapshot: State saved by ``stateSnapshot()``, for example by
    ///   an earlier run of the same app. Each `@State` whose structural
    ///   position and type still match starts from its saved value.
    public init(_ rootView: some View, device: Device = .iPhone16, restoring snapshot: Data? = nil)
    {
        self.rootView = rootView
        self.device = device
        let scrolling = ScrollLayout()
        self.scrolling = scrolling
        self.layoutEngine = LayoutEngine(device: device, scrolling: scrolling)
        pendingState = snapshot.flatMap(Self.decodeSnapshot) ?? [:]
        evaluate()
    }

    init(
        anyRootView rootView: any View, device: Device = .iPhone16, restoring snapshot: Data? = nil
    ) {
        self.rootView = rootView
        self.device = device
        let scrolling = ScrollLayout()
        self.scrolling = scrolling
        self.layoutEngine = LayoutEngine(device: device, scrolling: scrolling)
        pendingState = snapshot.flatMap(Self.decodeSnapshot) ?? [:]
        evaluate()
    }

    // MARK: - State snapshots

    /// Saved values waiting for their `@State` to appear, keyed by
    /// structural position.
    private var pendingState: [String: Data] = [:]

    /// The value of every `@State` whose type is `Codable`, as JSON.
    ///
    /// The snapshot maps each state's structural position, such as
    /// `"CounterView.count"`, to its value. Hot reload uses it to carry state
    /// into the rebuilt app. State of other types is not included.
    public func stateSnapshot() -> Data {
        var values: [String: String] = [:]
        for (key, box) in storage {
            if let box = box as? any SnapshotEncodable, let json = box.encodedValue() {
                values[key] = String(decoding: json, as: UTF8.self)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(values)) ?? Data("{}".utf8)
    }

    private static func decodeSnapshot(_ data: Data) -> [String: Data]? {
        guard let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return values.mapValues { Data($0.utf8) }
    }

    /// Resolves the tree again if any state changed since the last update.
    public func update() {
        guard needsUpdate else { return }
        evaluate()
    }

    /// The part of the tree that receives input: the frontmost sheet or
    /// alert, or the whole tree when nothing is presented.
    public var interactiveRoot: ViewNode {
        root.children.last { $0.isPresentation } ?? root
    }

    /// Taps the node with the given identifier, then updates the tree.
    public func tap(_ id: NodeID) throws(InteractionError) {
        guard root.node(withID: id) != nil else { throw .nodeNotFound(id) }
        guard interactiveRoot.node(withID: id) != nil else { throw .covered(id) }
        guard let action = actions[id] else { throw .notTappable(id) }
        action()
        update()
    }

    /// Taps whatever is at a point on the screen, then updates the tree.
    ///
    /// The tap goes to the frontmost node that contains the point and
    /// responds to taps. Later siblings are in front of earlier ones, and
    /// children are in front of their parents.
    public func tap(at point: CGPoint) throws(InteractionError) {
        guard let target = frontmostTappableNode(at: point, in: interactiveRoot) else {
            throw .nothingTappable(at: point)
        }
        try tap(target.id)
    }

    // MARK: - Pointer input

    /// The button under the pointer while it is down, if any.
    ///
    /// A press that starts on a button taps it only if the pointer is
    /// released over the same button, as on iOS. The renderer draws the
    /// pressed button dimmed.
    public private(set) var pressedNodeID: NodeID? {
        didSet {
            if pressedNodeID != oldValue { revision += 1 }
        }
    }

    /// A press in progress.
    private struct Press {
        var start: CGPoint
        var last: CGPoint
        /// The button the press started on, until the press turns into a
        /// scroll.
        var button: NodeID?
        /// The scroll view being dragged, once the press turns into a scroll.
        var scrollView: NodeID?
        /// The sheet being dragged down, once the press turns into a drag
        /// that dismisses it.
        var sheet: NodeID?
        /// Recent pointer positions, for the release velocity.
        var samples: [(time: TimeInterval, point: CGPoint)]
    }
    private var press: Press?

    /// Starts a press at a point on the screen. A press stops any scroll
    /// momentum, as touching a scrolling list does on iOS.
    public func pointerDown(at point: CGPoint) {
        momentum.removeAll()
        let button = frontmostTappableNode(at: point, in: interactiveRoot)?.id
        press = Press(
            start: point,
            last: point,
            button: button,
            scrollView: nil,
            sheet: nil,
            samples: [(time, point)]
        )
        // Text fields take focus on release but do not dim while pressed.
        pressedNodeID = button.flatMap { textFields[$0] == nil ? $0 : nil }
    }

    /// Moves a press.
    ///
    /// A button stays pressed only while the pointer is over it. If the
    /// pointer moves more than a few points over a scroll view, the press
    /// turns into a scroll: the button press is cancelled and the content
    /// follows the pointer.
    public func pointerMoved(to point: CGPoint) {
        guard var press else { return }
        defer {
            press.last = point
            self.press = press
        }
        let moved = CGSize(width: point.x - press.start.x, height: point.y - press.start.y)
        if press.scrollView == nil, press.sheet == nil,
            hypot(moved.width, moved.height) > LayoutDefaults.dragThreshold
        {
            let scrollView = innermostScrollView(at: press.start, along: moved, requireRoom: false)
            if let sheet = sheetToDrag(from: press.start, along: moved, over: scrollView) {
                press.sheet = sheet
            } else {
                press.scrollView = scrollView
            }
            if press.sheet != nil || press.scrollView != nil {
                press.button = nil
                pressedNodeID = nil
            }
        }
        if let sheet = press.sheet {
            scrolling.presentationOffsets[sheet] = max(moved.height, 0)
            relayout()
        } else if let scrollView = press.scrollView {
            applyScroll(
                scrollView,
                by: CGSize(width: press.last.x - point.x, height: press.last.y - point.y)
            )
            press.samples.append((time, point))
            press.samples.removeAll { time - $0.time > 0.15 }
        } else if let button = press.button, textFields[button] == nil {
            pressedNodeID =
                frontmostTappableNode(at: point, in: interactiveRoot)?.id == button ? button : nil
        }
    }

    /// Ends a press. If the pointer is over the button the press started on,
    /// the button is tapped and the tree updates. If the press was a scroll
    /// released while moving, the content keeps moving and slows down; call
    /// ``advanceTime(by:)`` to animate it.
    ///
    /// - Returns: The identifier of the tapped button, or `nil` if the press
    ///   did not tap anything.
    @discardableResult
    public func pointerUp(at point: CGPoint) -> NodeID? {
        guard let press else { return nil }
        self.press = nil
        pressedNodeID = nil

        if let sheet = press.sheet {
            let distance = scrolling.presentationOffsets[sheet] ?? 0
            scrolling.presentationOffsets[sheet] = nil
            if distance > LayoutDefaults.sheetDismissDistance,
                let presentation = presentations[sheet]
            {
                presentation.dismiss()
                update()
            } else {
                relayout()
            }
            return nil
        }
        if let scrollView = press.scrollView {
            startMomentum(scrollView, samples: press.samples + [(time, point)])
            return nil
        }
        guard let button = press.button,
            frontmostTappableNode(at: point, in: interactiveRoot)?.id == button
        else { return nil }
        if textFields[button] != nil {
            focusTextField(button, caretAt: point)
            return button
        }
        try? tap(button)
        return button
    }

    // MARK: - Text input

    /// A key that edits text or moves keyboard focus.
    public enum Key: String, Codable, Sendable, CaseIterable {
        case backspace, delete, left, right, home, end
        /// Moves focus to the next text field.
        case tab
        /// Moves focus to the previous text field.
        case backTab
        /// Ends editing.
        case `return`, escape
    }

    /// The text field that receives typing, if any.
    public private(set) var focusedNodeID: NodeID? {
        didSet {
            if focusedNodeID != oldValue { revision += 1 }
        }
    }

    /// The caret's position in the focused field, in characters from the
    /// start of its text.
    public private(set) var caretOffset = 0 {
        didSet {
            if caretOffset != oldValue { revision += 1 }
        }
    }

    /// Focuses a text field and puts the caret at the end of its text, or
    /// ends editing when `id` is `nil`.
    public func focus(_ id: NodeID?) throws(InteractionError) {
        guard let id else {
            focusedNodeID = nil
            return
        }
        guard let field = textFields[id] else {
            throw root.node(withID: id) == nil ? .nodeNotFound(id) : .notEditable(id)
        }
        focusedNodeID = id
        caretOffset = field.wrappedValue.count
    }

    /// Inserts text at the caret of the focused field, then updates the
    /// tree. Does nothing if no field is focused.
    public func typeText(_ text: String) {
        guard let id = focusedNodeID, let field = textFields[id] else { return }
        var value = field.wrappedValue
        let index = value.index(value.startIndex, offsetBy: min(caretOffset, value.count))
        value.insert(contentsOf: text, at: index)
        field.wrappedValue = value
        caretOffset = min(caretOffset, value.count) + text.count
        update()
    }

    /// Applies an editing or focus key.
    public func press(_ key: Key) {
        switch key {
        case .tab, .backTab:
            moveFocus(forward: key == .tab)
            return
        case .return, .escape:
            focusedNodeID = nil
            return
        default:
            break
        }
        guard let id = focusedNodeID, let field = textFields[id] else { return }
        var value = field.wrappedValue
        let caret = min(caretOffset, value.count)
        switch key {
        case .backspace where caret > 0:
            value.remove(at: value.index(value.startIndex, offsetBy: caret - 1))
            field.wrappedValue = value
            caretOffset = caret - 1
        case .delete where caret < value.count:
            value.remove(at: value.index(value.startIndex, offsetBy: caret))
            field.wrappedValue = value
        case .left:
            caretOffset = max(caret - 1, 0)
        case .right:
            caretOffset = min(caret + 1, value.count)
        case .home:
            caretOffset = 0
        case .end:
            caretOffset = value.count
        default:
            break
        }
        update()
    }

    /// Moves focus to the next or previous text field in reading order,
    /// wrapping around.
    private func moveFocus(forward: Bool) {
        let fields = interactiveRoot.allNodes.filter { textFields[$0.id] != nil }.map(\.id)
        guard !fields.isEmpty else { return }
        let next: NodeID
        if let current = focusedNodeID, let index = fields.firstIndex(of: current) {
            next = fields[(index + (forward ? 1 : fields.count - 1)) % fields.count]
        } else {
            next = forward ? fields[0] : fields[fields.count - 1]
        }
        try? focus(next)
    }

    private func focusTextField(_ id: NodeID, caretAt point: CGPoint) {
        guard let field = textFields[id], let frame = root.node(withID: id)?.frame else { return }
        let text = field.wrappedValue
        let geometry = TextFieldGeometry()
        let shift =
            focusedNodeID == id
            ? geometry.horizontalShift(text: text, caret: caretOffset, width: frame.width) : 0
        focusedNodeID = id
        caretOffset = geometry.caretOffset(in: text, atX: point.x - frame.minX, shift: shift)
    }

    // MARK: - Scrolling

    /// Scroll velocities in points per second, for scroll views that are
    /// still moving after a drag.
    private var momentum: [NodeID: CGPoint] = [:]

    /// Whether anything is still moving, so that a client should keep calling
    /// ``advanceTime(by:)`` and drawing frames.
    public var isAnimating: Bool { !momentum.isEmpty }

    /// How far a scroll view's content is scrolled, or `nil` if the node is
    /// not a scroll view.
    public func scrollOffset(of id: NodeID) -> CGPoint? {
        scrolling.metrics[id]?.offset
    }

    /// Scrolls the innermost scroll view at a point that can move in the
    /// direction of `delta`, as a mouse wheel or trackpad does. A positive
    /// height scrolls toward the end of the content.
    ///
    /// - Returns: Whether anything scrolled.
    @discardableResult
    public func scroll(by delta: CGSize, at point: CGPoint) -> Bool {
        guard let scrollView = innermostScrollView(at: point, along: delta, requireRoom: true)
        else { return false }
        momentum[scrollView] = nil
        applyScroll(scrollView, by: delta)
        return true
    }

    /// Scrolls a scroll view to an offset, clamped to its content.
    public func scroll(_ id: NodeID, to offset: CGPoint) throws(InteractionError) {
        guard scrolling.metrics[id] != nil else {
            throw root.node(withID: id) == nil ? .nodeNotFound(id) : .notScrollable(id)
        }
        momentum[id] = nil
        scrolling.offsets[id] = offset
        relayout()
    }

    /// Advances the host's clock, moving any scroll momentum forward.
    public func advanceTime(by interval: TimeInterval) {
        guard interval > 0 else { return }
        time += interval
        guard !momentum.isEmpty else { return }

        // Fixed steps make the result the same however the time is split.
        let step = 1.0 / 240
        var remaining = interval
        while remaining > 0, !momentum.isEmpty {
            let dt = min(step, remaining)
            remaining -= dt
            for (id, velocity) in momentum {
                guard let metrics = scrolling.metrics[id] else {
                    momentum[id] = nil
                    continue
                }
                let decay = pow(LayoutDefaults.scrollDecelerationRate, dt * 1000)
                var velocity = CGPoint(x: velocity.x * decay, y: velocity.y * decay)
                let current = scrolling.offsets[id] ?? metrics.offset
                var offset = CGPoint(
                    x: current.x + velocity.x * dt,
                    y: current.y + velocity.y * dt
                )
                // Stop at the ends of the content.
                if offset.x <= 0 || offset.x >= metrics.maxOffset.x { velocity.x = 0 }
                if offset.y <= 0 || offset.y >= metrics.maxOffset.y { velocity.y = 0 }
                offset.x = min(max(offset.x, 0), metrics.maxOffset.x)
                offset.y = min(max(offset.y, 0), metrics.maxOffset.y)
                scrolling.offsets[id] = offset
                let speed = hypot(velocity.x, velocity.y)
                momentum[id] = speed < LayoutDefaults.momentumStopSpeed ? nil : velocity
            }
        }
        relayout()
    }

    private func applyScroll(_ id: NodeID, by delta: CGSize) {
        guard let metrics = scrolling.metrics[id], let node = root.node(withID: id) else { return }
        let axes = LayoutEngine.scrollAxes(of: node)
        let current = scrolling.offsets[id] ?? metrics.offset
        scrolling.offsets[id] = CGPoint(
            x: current.x + (axes.horizontal ? delta.width : 0),
            y: current.y + (axes.vertical ? delta.height : 0)
        )
        relayout()
    }

    private func startMomentum(
        _ id: NodeID,
        samples: [(time: TimeInterval, point: CGPoint)]
    ) {
        // Only the last moments before release count: a pointer that rested
        // before it was lifted does not fling the content. The release usually
        // repeats the last position, so measure up to the last movement.
        guard let release = samples.last else { return }
        var moving = samples.filter { release.time - $0.time <= 0.15 }
        while moving.count > 1, moving[moving.count - 1].point == moving[moving.count - 2].point {
            moving.removeLast()
        }
        guard let first = moving.first, let last = moving.last, last.time > first.time,
            let node = root.node(withID: id)
        else { return }
        let axes = LayoutEngine.scrollAxes(of: node)
        let dt = last.time - first.time
        // The content moves opposite to the pointer.
        let velocity = CGPoint(
            x: axes.horizontal ? (first.point.x - last.point.x) / dt : 0,
            y: axes.vertical ? (first.point.y - last.point.y) / dt : 0
        )
        if hypot(velocity.x, velocity.y) > LayoutDefaults.minimumFlingSpeed {
            momentum[id] = velocity
        }
    }

    /// The innermost scroll view containing `point` that scrolls along the
    /// main direction of `delta`. With `requireRoom`, it must also have room
    /// to move that way.
    private func innermostScrollView(
        at point: CGPoint, along delta: CGSize, requireRoom: Bool
    )
        -> NodeID?
    {
        var candidates: [ViewNode] = []
        func collect(_ node: ViewNode) {
            guard let frame = node.frame, frame.contains(point) else { return }
            if node.isScrollContainer { candidates.append(node) }
            node.children.forEach(collect)
        }
        collect(interactiveRoot)

        for node in candidates.reversed() {
            guard let metrics = scrolling.metrics[node.id] else { continue }
            let axes = LayoutEngine.scrollAxes(of: node)
            let vertical = abs(delta.height) >= abs(delta.width)
            if vertical, axes.vertical {
                if !requireRoom { return node.id }
                if delta.height > 0, metrics.offset.y < metrics.maxOffset.y { return node.id }
                if delta.height < 0, metrics.offset.y > 0 { return node.id }
            }
            if !vertical, axes.horizontal {
                if !requireRoom { return node.id }
                if delta.width > 0, metrics.offset.x < metrics.maxOffset.x { return node.id }
                if delta.width < 0, metrics.offset.x > 0 { return node.id }
            }
        }
        return nil
    }

    /// The sheet a press should drag down to dismiss: the frontmost
    /// presentation, if it is a sheet that contains the press, the press
    /// moves down, and no scroll view under it can scroll toward the top.
    private func sheetToDrag(
        from start: CGPoint, along moved: CGSize, over scrollView: NodeID?
    )
        -> NodeID?
    {
        let front = interactiveRoot
        guard front.kind == "Sheet", front.frame?.contains(start) == true,
            moved.height > abs(moved.width)
        else { return nil }
        if let scrollView, let metrics = scrolling.metrics[scrollView], metrics.offset.y > 0 {
            return nil
        }
        return front.id
    }

    /// Taps the one button or navigation link whose label is exactly
    /// `label`. Only the frontmost sheet or alert is searched while one is
    /// presented.
    public func tapButton(labeled label: String) throws(InteractionError) {
        let matches = interactiveRoot.allNodes.filter {
            ($0.kind == "Button" || $0.kind == "NavigationLink") && $0.label == label
        }
        guard let button = matches.first else { throw .noButton(label: label) }
        guard matches.count == 1 else {
            throw .ambiguousButton(label: label, matches: matches.map(\.id))
        }
        try tap(button.id)
    }

    /// Every node whose kind is `"Text"` and whose text is exactly `text`.
    public func nodes(withText text: String) -> [ViewNode] {
        root.allNodes.filter { $0.text == text }
    }

    /// The frontmost button or text field at a point.
    private func frontmostTappableNode(at point: CGPoint, in node: ViewNode) -> ViewNode? {
        guard let frame = node.hitFrame, frame.contains(point) else { return nil }
        for child in node.children.reversed() {
            if let match = frontmostTappableNode(at: point, in: child) { return match }
        }
        return actions[node.id] != nil || textFields[node.id] != nil ? node : nil
    }

    func setNeedsUpdate() {
        needsUpdate = true
    }

    func stateBox<Value>(forKey key: String, initialValue: Value) -> StateBox<Value> {
        visitedKeys.insert(key)
        if let box = storage[key] as? StateBox<Value> {
            return box
        }
        var value = initialValue
        if let saved = pendingState.removeValue(forKey: key),
            let type = Value.self as? any Decodable.Type,
            let restored = decode(type, from: saved) as? Value
        {
            value = restored
        }
        let box = StateBox(value)
        box.host = self
        storage[key] = box
        return box
    }

    private func evaluate() {
        needsUpdate = false
        visitedKeys = []
        visitedNavigationStacks = []
        let evaluator = Evaluator(host: self)
        var children = evaluator.evaluate(rootView, at: ViewPath())
        // Presented content can present more, so the list grows as it goes.
        var index = 0
        var presented: [NodeID: Presentation] = [:]
        while index < evaluator.presentations.count {
            let presentation = evaluator.presentations[index]
            children.append(presentation.makeNode(evaluator))
            presented[presentation.id] = presentation
            index += 1
        }
        resolvedRoot = ViewNode(id: "", kind: "Root", children: children)
        actions = evaluator.actions
        textFields = evaluator.textFields
        let dismissed = presentations.filter { presented[$0.key] == nil }.values
        presentations = presented
        scrolling.presentationOffsets = scrolling.presentationOffsets.filter {
            presented[$0.key] != nil
        }
        // A focused field that left the tree loses focus.
        if let focused = focusedNodeID {
            if let field = textFields[focused] {
                caretOffset = min(caretOffset, field.wrappedValue.count)
            } else {
                focusedNodeID = nil
            }
        }
        relayout()
        // State belongs to a structural position. When a view leaves the
        // tree, its state goes with it.
        storage = storage.filter { visitedKeys.contains($0.key) }
        navigationState = navigationState.filter { visitedNavigationStacks.contains($0.key) }

        // A dismissed sheet's onDismiss runs after it leaves the tree.
        let callbacks = dismissed.compactMap(\.onDismiss)
        if !callbacks.isEmpty {
            callbacks.forEach { $0() }
            update()
        }
    }

    /// Lays out the evaluated tree again, for example after scrolling.
    private func relayout() {
        scrolling.metrics = [:]
        root = layoutEngine.layout(resolvedRoot)
        // Keep each offset clamped to its content, and forget the offsets of
        // scroll views that left the tree.
        scrolling.offsets = scrolling.metrics.mapValues(\.offset)
        momentum = momentum.filter { scrolling.metrics[$0.key] != nil }
        revision += 1
    }
}
