import ParhelionRender

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
    /// No view on screen has this accessibility identifier.
    case noAccessibilityIdentifier(String)
    /// More than one view that could take the action has this accessibility
    /// identifier.
    case ambiguousAccessibilityIdentifier(String, matches: [NodeID])
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
    let scrolling: ScrollLayout
    /// What lazy stacks and lists keep between evaluating and laying out.
    var lazy: LazyLayoutState { scrolling.lazy }
    private var isEvaluating = false
    /// What scroll views need between evaluations; see ScrollPosition.swift.
    let scrollState = ScrollHostState()
    /// The tree as evaluated, before layout. Scrolling lays it out again
    /// without evaluating views.
    private var resolvedRoot = ViewNode(id: "", kind: "Root")
    private var storage: [String: AnyObject] = [:]
    private var visitedKeys: Set<String> = []
    private var actions: [NodeID: @MainActor () -> Void] = [:]
    var textFields: [NodeID: Binding<String>] = [:]
    /// The selection and the pasteboard; see ``TextEditingState``.
    var editing = TextEditingState()
    private var inputHandlers: [NodeID: NodeInputHandlers] = [:]
    /// The entries each navigation stack keeps above its root view, by the
    /// stack's identifier.
    var navigationState: [NodeID: [NavigationEntry]] = [:]
    var visitedNavigationStacks: Set<NodeID> = []
    /// The presentations on screen, by identifier.
    private var presentations: [NodeID: Presentation] = [:]
    /// The color scheme each presentation preferred in the last evaluation,
    /// by its identifier; the window's is under the empty identifier.
    private var preferredColorSchemes: [NodeID: ColorScheme] = [:]

    // Animation state. See docs/adr/0005-model-tree-and-presented-frames.md.
    private let animations = AnimationEngine()
    /// The animation for the next layout change, from `withAnimation` or a
    /// navigation push or pop.
    var pendingAnimation: Animation??
    /// The last value of each `animation(_:value:)` modifier.
    var animationValues: [String: Any] = [:]
    var visitedAnimationKeys: Set<String> = []
    private var implicitAnimations: [NodeID: Animation?] = [:]
    private var transitions: [NodeID: AnyTransition] = [:]
    private var previousTransitions: [NodeID: AnyTransition] = [:]
    /// The navigation stacks that pushed or popped since the last layout.
    var navigationChanges: [NodeID: NavigationDirection] = [:]
    private var presentedCache: ViewNode?
    private var hasLaidOut = false
    private let observation = ObservationScope()
    /// Lifecycle actions and `task` work. See HostTasks.swift.
    let lifecycle = ViewLifecycle()
    /// What each `TimelineView` shows and when it updates. See TimelineView.swift.
    var timelines = TimelineHostState()
    /// The gestures views attached and the press being recognized. See ViewHost+Gestures.swift.
    var gestures = GestureHostState()
    /// How far each list row with swipe actions is swiped. See SwipeActions.swift.
    var swipe = SwipeHostState()

    /// Whether a state change is waiting for the next ``update()``.
    public private(set) var needsUpdate = false

    /// The resolved and laid-out tree. Its root node has kind `"Root"` and
    /// covers the whole screen.
    ///
    /// The tree holds final values: while an animation runs, its frames are
    /// where views are going, and taps go there too. ``presentedRoot`` is the
    /// tree as drawn.
    public private(set) var root = ViewNode(id: "", kind: "Root")

    /// The tree as it is drawn at the current ``time``: ``root`` with every
    /// animation in progress applied, including views that have left
    /// ``root`` and are still transitioning out. It equals ``root`` when
    /// nothing is animating.
    public var presentedRoot: ViewNode {
        if let presentedCache { return presentedCache }
        let presented = animations.presented(root, at: time)
        presentedCache = presented
        return presented
    }

    /// The device the tree is laid out for.
    public let device: Device

    /// The appearance the simulated device is set to, as in its Settings:
    /// `light` by default. A presentation's `preferredColorScheme(_:)`
    /// overrides it for that presentation. Setting it updates the tree, whose
    /// root records `colorScheme=dark` while the window is dark.
    public var colorScheme: ColorScheme {
        didSet {
            guard colorScheme != oldValue else { return }
            setNeedsUpdate()
            update()
        }
    }

    /// The text size the simulated device is set to, as in its Settings:
    /// `large` by default. Text styles, custom fonts, and `@ScaledMetric`
    /// values scale with it. Setting it updates the tree, whose root records
    /// `dynamicTypeSize` while it is not `large`.
    public var dynamicTypeSize: DynamicTypeSize {
        didSet {
            guard dynamicTypeSize != oldValue else { return }
            setNeedsUpdate()
            update()
        }
    }

    /// A number that increases whenever anything on screen changes: the
    /// tree, the layout, a scroll position, or the pressed button. Clients
    /// compare it to decide whether to draw a new frame.
    public internal(set) var revision = 0

    /// The host's clock, in seconds. It advances only through
    /// ``advanceTime(by:)``, so animations are deterministic: the same input
    /// at the same times always produces the same frames.
    public private(set) var time: TimeInterval = 0

    /// The device chrome last drawn by `render(scale:chrome:)`, kept because
    /// it does not change from frame to frame.
    var chromeOverlayCache:
        (chrome: DeviceChrome, scale: Double, colorScheme: ColorScheme, overlay: CanvasOverlay)?

    /// Drawing that `render(scale:chrome:)` keeps between frames: the screen
    /// beneath a presentation, a fading presentation, and glass surfaces.
    let renderCache = RenderCache()

    /// Creates a host for a view.
    ///
    /// - Parameters:
    ///   - colorScheme: The appearance the simulated device is set to.
    ///   - dynamicTypeSize: The text size the simulated device is set to.
    ///   - snapshot: State saved by ``stateSnapshot()``, for example by an
    ///     earlier run of the same app. Each `@State` whose structural
    ///     position and type still match starts from its saved value.
    ///   - referenceDate: The date at ``time`` 0, which `TimelineView` shows.
    ///     By default the real date when a view first asks for it.
    public init(
        _ rootView: some View, device: Device = .iPhone16, colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large, restoring snapshot: Data? = nil,
        referenceDate: Date? = nil
    ) {
        timelines.referenceDate = referenceDate
        self.rootView = rootView
        self.device = device
        self.colorScheme = colorScheme
        self.dynamicTypeSize = dynamicTypeSize
        let scrolling = ScrollLayout()
        self.scrolling = scrolling
        self.layoutEngine = LayoutEngine(device: device, scrolling: scrolling)
        pendingState = snapshot.flatMap(Self.decodeSnapshot) ?? [:]
        evaluate()
        update()
    }

    init(
        anyRootView rootView: any View, device: Device = .iPhone16,
        colorScheme: ColorScheme = .light, dynamicTypeSize: DynamicTypeSize = .large,
        restoring snapshot: Data? = nil, referenceDate: Date? = nil
    ) {
        timelines.referenceDate = referenceDate
        self.rootView = rootView
        self.device = device
        self.colorScheme = colorScheme
        self.dynamicTypeSize = dynamicTypeSize
        let scrolling = ScrollLayout()
        self.scrolling = scrolling
        self.layoutEngine = LayoutEngine(device: device, scrolling: scrolling)
        pendingState = snapshot.flatMap(Self.decodeSnapshot) ?? [:]
        evaluate()
        update()
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
    ///
    /// Every method that delivers input calls it first, so that input
    /// reaches the views on screen now, not those of an earlier update,
    /// even when a task or another thread changed state since.
    ///
    /// The actions of `onAppear`, `onChange(of:)`, and other modifiers run
    /// after the tree is resolved, and when they change state, the tree is
    /// resolved again, up to ``maximumUpdatePasses`` times.
    public func update() {
        var passes = 0
        while needsUpdate {
            guard passes < Self.maximumUpdatePasses else {
                // Left waiting, the change would make a preview session
                // update again on every turn of its loop.
                needsUpdate = false
                lifecycle.warnAboutEndlessUpdates(after: passes)
                return
            }
            evaluate()
            passes += 1
        }
    }

    /// How many times one ``update()`` resolves the tree. If state is still
    /// changing then, as when an `onChange(of:)` action changes the value it
    /// watches, the host writes a warning and stops until the next change,
    /// so that such views cannot hang the host or keep it busy.
    public static let maximumUpdatePasses = 64

    /// The part of the tree that receives input: the frontmost sheet or
    /// alert, or the whole tree when nothing is presented.
    public var interactiveRoot: ViewNode {
        root.children.last { $0.isPresentation } ?? root
    }

    /// Taps the node with the given identifier, then updates the tree.
    public func tap(_ id: NodeID) throws(InteractionError) {
        update()
        guard root.node(withID: id) != nil else { throw .nodeNotFound(id) }
        guard interactiveRoot.node(withID: id) != nil else { throw .covered(id) }
        guard let action = actions[id] else {
            if tapThroughGestures(on: id) { return }
            throw .notTappable(id)
        }
        action()
        update()
    }

    /// Taps whatever is at a point on the screen, then updates the tree.
    ///
    /// The tap goes to the frontmost node that contains the point and
    /// responds to taps. Later siblings are in front of earlier ones, and
    /// children are in front of their parents. A tap on a slider's track
    /// moves its knob there.
    public func tap(at point: CGPoint) throws(InteractionError) {
        update()
        if tapSlider(at: point) { return }
        if tapThroughGestures(at: point) { return }
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
    public internal(set) var pressedNodeID: NodeID? {
        didSet {
            if pressedNodeID != oldValue { revision += 1 }
        }
    }

    /// A press in progress.
    struct Press {
        var start: CGPoint
        var last: CGPoint
        /// The button the press started on, until the press turns into a
        /// scroll.
        var button: NodeID?
        /// The scroll view being dragged, once the press turns into a scroll.
        var scrollView: NodeID?
        /// Where the scroll view's content was when the press began to
        /// scroll it, for settling on a page.
        var scrollStartOffset: CGPoint?
        /// The sheet being dragged down, once the press turns into a drag
        /// that dismisses it.
        var sheet: NodeID?
        /// Whether the press is selecting text in the field it started on.
        var selectsText = false
        /// Where a selection by dragging began, in characters, fixed at the
        /// first move so that scrolling the field's text does not move it.
        var selectionAnchor: Int?
        /// Recent pointer positions, for the release velocity.
        var samples: [(time: TimeInterval, point: CGPoint)]
        /// A swipe of a list row with actions, or an open row to close.
        var swipe = SwipePress()
    }
    var press: Press?

    /// Starts a press at a point on the screen. A press stops any scroll
    /// momentum, as touching a scrolling list does on iOS.
    public func pointerDown(at point: CGPoint) {
        update()
        momentum.removeAll()
        // A press on a slider takes its knob, before it can become a scroll.
        let slider = beginSliderDrag(at: point)
        var button = slider ?? frontmostTappableNode(at: point, in: interactiveRoot)?.id
        // A press on the rest of an open swiped row only closes the row, so
        // it reaches no control or gesture.
        let swipePress = swipePressBegan(at: point, button: &button)
        if slider == nil, swipePress.closeOnRelease == nil {
            beginGesturePress(at: point, control: button)
        } else {
            gestures.session = nil
        }
        press = Press(
            start: point,
            last: point,
            button: button,
            scrollView: nil,
            scrollStartOffset: nil,
            sheet: nil,
            samples: [(time, point)],
            swipe: swipePress
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
        update()
        guard var press else { return }
        defer {
            press.last = point
            self.press = press
        }
        if let button = press.button, dragSlider(button, to: point) { return }
        let moved = CGSize(width: point.x - press.start.x, height: point.y - press.start.y)
        // Gestures see the pointer first. A scroll view or sheet that the press
        // could still turn into holds back the gestures outside it.
        let scrolls = press.scrollView == nil && press.sheet == nil && press.swipe.row == nil
        moveGesturePress(
            to: point,
            scrollView: scrolls
                ? innermostScrollView(at: press.start, along: moved, requireRoom: false) : nil)
        press.button = self.press?.button
        // A drag along a text field selects its text, as a mouse does.
        if let field = press.button, textFields[field] != nil,
            press.selectsText
                || (hypot(moved.width, moved.height) > LayoutDefaults.dragThreshold
                    && abs(moved.width) >= abs(moved.height))
        {
            press.selectsText = true
            selectText(in: field, from: press.start, to: point, anchor: &press.selectionAnchor)
            return
        }
        // A sideways press on a row with swipe actions swipes it, unless a
        // gesture in the row has the press.
        if scrolls, hypot(moved.width, moved.height) > LayoutDefaults.dragThreshold,
            swipeBegan(&press.swipe, from: press.start, moved: moved)
        {
            press.button = nil
            pressedNodeID = nil
        } else if scrolls, hypot(moved.width, moved.height) > LayoutDefaults.dragThreshold {
            let scrollView = innermostScrollView(at: press.start, along: moved, requireRoom: false)
            let sheet = sheetToDrag(from: press.start, along: moved, over: scrollView)
            if sheet != nil || scrollView != nil, handOverPress(to: sheet ?? scrollView) {
                if let sheet {
                    press.sheet = sheet
                } else {
                    press.scrollView = scrollView
                    press.scrollStartOffset = scrollView.flatMap { scrolling.metrics[$0]?.offset }
                }
                press.button = nil
                pressedNodeID = nil
            }
        }
        if press.swipe.row != nil {
            swipeMoved(&press.swipe, from: press.start, to: point)
        } else if let sheet = press.sheet {
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
        update()
        guard let press else { return nil }
        self.press = nil
        pressedNodeID = nil
        if let button = press.button, endSliderDrag(button, at: point) { return button }
        let released = releaseGesturePress(at: point)

        if press.swipe.row != nil {
            swipeEnded(press.swipe, at: point)
            return nil
        }
        if let sheet = press.sheet {
            let distance = scrolling.presentationOffsets[sheet] ?? 0
            scrolling.presentationOffsets[sheet] = nil
            if distance > LayoutDefaults.sheetDismissDistance,
                let presentation = presentations[sheet]
            {
                presentation.dismiss()
                update()
            } else {
                // The sheet springs back to where it rests.
                pendingAnimation = .some(LayoutDefaults.presentationAnimation)
                relayout()
            }
            return nil
        }
        if let scrollView = press.scrollView {
            let samples = press.samples + [(time, point)]
            if !settleScroll(scrollView, from: press.scrollStartOffset, samples: samples) {
                startMomentum(scrollView, samples: samples)
            }
            return nil
        }
        if let open = press.swipe.closeOnRelease {
            // A press on the rest of an open row closes it, and does nothing else.
            closeSwipe(open)
            return nil
        }
        if released.handled { return released.tapped }
        guard let button = press.button,
            frontmostTappableNode(at: point, in: interactiveRoot)?.id == button
        else { return nil }
        if textFields[button] != nil {
            if !press.selectsText { focusTextField(button, caretAt: point) }
            return button
        }
        try? tap(button)
        return button
    }

    /// Holds a press at a point for `duration` seconds, then releases it, and
    /// updates the tree.
    ///
    /// The press goes to the frontmost node at the point that registered a
    /// long press handler.
    public func longPress(at point: CGPoint, duration: TimeInterval = 0.5) throws(InteractionError)
    {
        update()
        guard
            let target = frontmostNode(
                at: point, in: interactiveRoot, where: { inputHandlers[$0.id]?.longPress != nil }),
            let handler = inputHandlers[target.id]?.longPress
        else {
            // A view with a long press gesture gets a real press: down, the
            // time, and up.
            guard hasLongPressGesture(at: point) else { throw .nothingTappable(at: point) }
            pointerDown(at: point)
            advanceTime(by: max(duration, 0))
            pointerUp(at: point)
            update()
            return
        }
        advanceTime(by: max(duration, 0))
        handler(point, duration)
        update()
    }

    /// Moves a press from one point to another over `duration` seconds, as a
    /// finger would, then releases it.
    ///
    /// A press that does not move is a ``longPress(at:duration:)`` when a view
    /// at the point handles one. Otherwise a node at the start that
    /// registered a drag handler receives the drag.
    /// Otherwise the press moves in 60 steps per second of the duration,
    /// advancing the clock, as it would for a person using the window: it
    /// drags a slider's knob, scrolls a scroll view, or pulls a sheet down.
    public func drag(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.3) {
        update()
        let duration = min(max(duration, 0.02), 5)
        // A press that does not move is a long press, which is how the
        // `long_press` tool sends one: it reaches long press handlers, such
        // as a context menu's, as well as long press gestures.
        if start == end, (try? longPress(at: start, duration: duration)) != nil { return }
        if let target = frontmostNode(
            at: start, in: interactiveRoot, where: { inputHandlers[$0.id]?.drag != nil }),
            let handler = inputHandlers[target.id]?.drag
        {
            advanceTime(by: duration)
            handler(start, end, duration)
            update()
            return
        }
        let steps = max(Int(duration * 60), 2)
        pointerDown(at: start)
        for step in 1...steps {
            advanceTime(by: duration / Double(steps))
            let t = CGFloat(step) / CGFloat(steps)
            pointerMoved(
                to: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        }
        pointerUp(at: end)
    }

    // MARK: - Text input

    /// The text field that receives typing, if any.
    public internal(set) var focusedNodeID: NodeID? {
        didSet {
            if focusedNodeID != oldValue {
                revision += 1
                // Focus in a search field changes `isSearching` in its content.
                if oldValue?.isInSearchField == true || focusedNodeID?.isInSearchField == true {
                    needsUpdate = true
                }
            }
        }
    }

    /// The caret's position in the focused field, in characters from the
    /// start of its text.
    public internal(set) var caretOffset = 0 {
        didSet {
            if caretOffset != oldValue { revision += 1 }
        }
    }

    // MARK: - Scrolling

    /// Scroll velocities in points per second, for scroll views that are
    /// still moving after a drag.
    var momentum: [NodeID: CGPoint] = [:]

    /// Whether anything is still moving, so that a client should keep calling
    /// ``advanceTime(by:)`` and drawing frames.
    public var isAnimating: Bool {
        !momentum.isEmpty || animations.isActive(at: time) || timelines.followsFrames
            || gestures.wantsTicks
    }

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
        update()
        guard let scrollView = innermostScrollView(at: point, along: delta, requireRoom: true)
        else { return false }
        momentum[scrollView] = nil
        applyScroll(scrollView, by: delta)
        return true
    }

    /// Scrolls a scroll view to an offset, clamped to its content.
    public func scroll(_ id: NodeID, to offset: CGPoint) throws(InteractionError) {
        update()
        guard scrolling.metrics[id] != nil else {
            throw root.node(withID: id) == nil ? .nodeNotFound(id) : .notScrollable(id)
        }
        momentum[id] = nil
        scrolling.offsets[id] = offset
        relayout()
    }

    /// Advances the host's clock, moving animations and scroll momentum
    /// forward, and updating the `TimelineView`s whose next date it reaches.
    /// A timeline view shows the latest date that passed, however far the
    /// clock moves; ``advanceClock(by:)`` stops at each date instead.
    public func advanceTime(by interval: TimeInterval) {
        guard interval > 0 else { return }
        // A timeline view whose next date has come builds its content again.
        defer { updateTimelines() }
        let wasAnimating = animations.isActive(at: time)
        time += interval
        tickGesturePress()
        if wasAnimating {
            animations.removeFinished(at: time)
            presentedCache = nil
            revision += 1
        }
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

    /// Taps the one control whose label is exactly `label`: a button, a
    /// navigation link, a toggle's switch, a stepper's `Increment` or
    /// `Decrement`, or a picker's option. Only the frontmost sheet, alert, or
    /// menu is searched while one is presented.
    public func tapButton(labeled label: String) throws(InteractionError) {
        update()
        let matches = interactiveRoot.allNodes.filter {
            actions[$0.id] != nil && $0.label == label
        }
        guard let button = matches.first else {
            // A disabled control has the label but takes no taps.
            if let disabled = interactiveRoot.allNodes.first(where: {
                $0.isDisabled && $0.label == label
            }) {
                throw .notTappable(disabled.id)
            }
            throw .noButton(label: label)
        }
        guard matches.count == 1 else {
            throw .ambiguousButton(label: label, matches: matches.map(\.id))
        }
        try tap(button.id)
    }

    /// Taps the one control with an accessibility identifier, as set with
    /// `accessibilityIdentifier(_:)`. An identifier on a container names every
    /// control inside it, so it is ambiguous when there are several; see
    /// ``ViewNode/accessibilityEntries()``. Only the frontmost sheet, alert,
    /// or menu is searched while one is presented.
    public func tap(accessibilityIdentifier identifier: String) throws(InteractionError) {
        let id = try resolve(accessibilityIdentifier: identifier, otherwise: { .notTappable($0) }) {
            actions[$0.id] != nil
        }
        try tap(id)
    }

    /// Focuses the one text field with an accessibility identifier.
    public func focus(accessibilityIdentifier identifier: String) throws(InteractionError) {
        let id = try resolve(accessibilityIdentifier: identifier, otherwise: { .notEditable($0) }) {
            textFields[$0.id] != nil
        }
        try focus(id)
    }

    /// Scrolls the one scroll view with an accessibility identifier to an
    /// offset, clamped to its content.
    public func scroll(
        accessibilityIdentifier identifier: String, to offset: CGPoint
    ) throws(InteractionError) {
        let id = try resolve(accessibilityIdentifier: identifier, otherwise: { .notScrollable($0) })
        {
            scrolling.metrics[$0.id] != nil
        }
        try scroll(id, to: offset)
    }

    /// The nodes with an accessibility identifier, wherever they are in the
    /// tree.
    public func nodes(withAccessibilityIdentifier identifier: String) -> [ViewNode] {
        root.nodes(withAccessibilityIdentifier: identifier)
    }

    private func resolve(
        accessibilityIdentifier identifier: String,
        otherwise wrongKind: (NodeID) -> InteractionError,
        where isTarget: (ViewNode) -> Bool
    ) throws(InteractionError) -> NodeID {
        update()
        switch interactiveRoot.resolveAccessibilityIdentifier(identifier, isTarget: isTarget) {
        case .found(let id): return id
        case .ambiguous(let matches):
            throw .ambiguousAccessibilityIdentifier(identifier, matches: matches)
        case .wrongKind(let id): throw wrongKind(id)
        case .none:
            if let hidden = root.nodes(withAccessibilityIdentifier: identifier).first {
                throw .covered(hidden.id)
            }
            throw .noAccessibilityIdentifier(identifier)
        }
    }

    /// Every node whose kind is `"Text"` and whose text is exactly `text`.
    public func nodes(withText text: String) -> [ViewNode] {
        root.allNodes.filter { $0.text == text }
    }

    /// The frontmost button or text field at a point, for recording a tap as
    /// a command that names it.
    func tappableNode(at point: CGPoint) -> ViewNode? {
        frontmostTappableNode(at: point, in: interactiveRoot)
    }

    /// Whether a tap on the node runs an action.
    func hasAction(_ id: NodeID) -> Bool { actions[id] != nil }

    /// Whether the node is a text field that can take focus.
    func isTextField(_ id: NodeID) -> Bool { textFields[id] != nil }

    /// The frontmost button or text field at a point.
    /// Children outside their parent's bounds, such as views moved by
    /// `offset`, still receive taps, except where a scroll view clips them.
    func frontmostTappableNode(at point: CGPoint, in node: ViewNode) -> ViewNode? {
        frontmostNode(at: point, in: node) { actions[$0.id] != nil || textFields[$0.id] != nil }
    }

    /// The frontmost node at a point that `matches`, found the way a tap
    /// finds its target. A kind that registered a hit test decides for
    /// itself whether a point is on it.
    func frontmostNode(
        at point: CGPoint, in node: ViewNode, where matches: (ViewNode) -> Bool
    ) -> ViewNode? {
        let isInside =
            NodeExtensions.behavior(for: node.kind)?.hitTest?(node, point)
            ?? node.hitFrame?.contains(point) ?? false
        if node.isScrollContainer, !isInside { return nil }
        for child in node.hitOrder {
            if let match = frontmostNode(at: point, in: child, where: matches) { return match }
        }
        guard isInside else { return nil }
        return matches(node) ? node : nil
    }

    /// Slides a navigation stack's screens, with the navigation animation
    /// unless `withAnimation` chose another.
    func animateNavigation(of stack: NodeID, _ direction: NavigationDirection) {
        navigationChanges[stack] = direction
        if AnimationContext.current == nil, pendingAnimation == nil {
            pendingAnimation = .some(LayoutDefaults.presentationAnimation)
        }
    }

    func setNeedsUpdate() {
        needsUpdate = true
        if let animation = AnimationContext.current { pendingAnimation = animation }
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
        isEvaluating = true
        defer { isEvaluating = false }
        lazy.beginEvaluation()
        visitedKeys = []
        visitedNavigationStacks = []
        visitedAnimationKeys = []
        timelines.beginEvaluation()
        gestures.beginEvaluation()
        let evaluator = Evaluator(host: self)
        // Each presentation starts in the color scheme it preferred in the
        // last evaluation, and the window in the device's otherwise.
        let windowScheme = preferredColorSchemes[NodeID("")] ?? colorScheme
        evaluator.environment.colorScheme = windowScheme
        evaluator.environment.dynamicTypeSize = dynamicTypeSize
        var preferences: [NodeID: ColorScheme] = [:]
        var presented: [NodeID: Presentation] = [:]
        // A change to an observable property that a view reads marks the
        // host as needing an update.
        let children = observation.track(for: self) {
            var children = evaluator.evaluate(rootView, at: ViewPath())
            preferences[NodeID("")] = evaluator.preferredColorScheme
            // Presented content can present more, so the list grows as it goes.
            var index = 0
            while index < evaluator.presentations.count {
                let presentation = evaluator.presentations[index]
                evaluator.preferredColorScheme = nil
                evaluator.presentationColorScheme = preferredColorSchemes[presentation.id]
                evaluator.presentationEnvironment = nil
                var node = presentation.makeNode(evaluator)
                // The renderer draws a presentation in the scheme it started
                // with; the root's children inherit the window's.
                if let start = evaluator.presentationEnvironment {
                    if start.colorScheme != windowScheme {
                        node.attributes["colorScheme"] = start.colorScheme.name
                    }
                    if start.dynamicTypeSize != dynamicTypeSize {
                        node.attributes["dynamicTypeSize"] = start.dynamicTypeSize.name
                    }
                }
                preferences[presentation.id] = evaluator.preferredColorScheme
                children.append(node)
                presented[presentation.id] = presentation
                index += 1
            }
            return children
        }
        var rootAttributes: [String: String] = [:]
        if windowScheme != .light { rootAttributes["colorScheme"] = windowScheme.name }
        if dynamicTypeSize != .large { rootAttributes["dynamicTypeSize"] = dynamicTypeSize.name }
        resolvedRoot = ViewNode(
            id: "", kind: "Root", attributes: rootAttributes, children: children)
        // A preference that changed applies to its whole presentation,
        // including views evaluated before the modifier that states it, so
        // the tree is evaluated again with it.
        let collected = preferences.compactMapValues { $0 }
        if collected != preferredColorSchemes {
            preferredColorSchemes = collected
            needsUpdate = true
        }
        actions = evaluator.actions
        textFields = evaluator.textFields
        inputHandlers = evaluator.inputHandlers
        adoptScrollEvaluation(evaluator.scrollRecord)
        implicitAnimations = evaluator.implicitAnimations
        previousTransitions = transitions
        transitions = evaluator.transitions
        animationValues = animationValues.filter { visitedAnimationKeys.contains($0.key) }
        timelines.finishEvaluation()
        gestures.finishEvaluation()
        lazy.finishEvaluation()
        let dismissed = presentations.filter { presented[$0.key] == nil }.values
        presentations = presented
        scrolling.presentationOffsets = scrolling.presentationOffsets.filter {
            presented[$0.key] != nil
        }
        // A focused field that left the tree loses focus.
        if let focused = focusedNodeID {
            if let field = textFields[focused] {
                let count = field.wrappedValue.count
                setSelection(
                    anchor: editing.anchor.map { min($0, count) }, caret: min(caretOffset, count))
            } else {
                focusedNodeID = nil
                setSelection(anchor: nil, caret: caretOffset)
            }
        } else if editing.anchor != nil {
            editing.anchor = nil
        }
        relayout()
        // State belongs to a structural position. When a view leaves the
        // tree, its state goes with it.
        // A lazy stack keeps the state of the rows it released.
        storage = storage.filter { visitedKeys.contains($0.key) || lazy.retainsState($0.key) }
        navigationState = navigationState.filter { visitedNavigationStacks.contains($0.key) }

        lifecycle.apply(evaluator.lifecycle, to: resolvedRoot)
        // A dismissed sheet's onDismiss runs after it leaves the tree.
        dismissed.compactMap(\.onDismiss).forEach { $0() }
    }

    /// Lays out the evaluated tree again, for example after scrolling.
    func relayout() {
        let previous = presentedRoot
        layoutAgain()
        applyScrollRequests()
        if hasLaidOut {
            animations.update(
                from: previous,
                to: root,
                request: AnimationRequest(
                    transaction: pendingAnimation,
                    implicit: implicitAnimations,
                    transitions: transitions,
                    previousTransitions: previousTransitions,
                    navigation: navigationChanges
                ),
                at: time
            )
        }
        hasLaidOut = true
        pendingAnimation = nil
        implicitAnimations = [:]
        navigationChanges = [:]
        presentedCache = nil
        // Keep each offset clamped to its content, and forget the offsets of
        // scroll views that left the tree. While lazy stacks are about to
        // evaluate more rows, the content is only estimated, so a request
        // past the end stays a request, and lands on the end of the content
        // that the rows then make.
        if lazy.needsWindowChange {
            scrolling.offsets = scrolling.offsets.filter { scrolling.metrics[$0.key] != nil }
        } else {
            scrolling.offsets = scrolling.metrics.mapValues(\.offset)
        }
        momentum = momentum.filter { scrolling.metrics[$0.key] != nil }
        revision += 1
        // Scrolling can move the screen past the views a lazy stack made.
        // Evaluating resolves the stacks' new windows and lays out again.
        // Until then the rows are estimated, so scroll bindings and geometry
        // wait for the layout that follows.
        if lazy.needsWindowChange {
            needsUpdate = true
            if !isEvaluating { update() }
        } else {
            finishScrollLayout()
        }
        // A tab bar minimized or returned: evaluate again for the
        // accessory's new placement, animated.
        if scrolling.tabBars.changed {
            scrolling.tabBars.changed = false
            if pendingAnimation == nil {
                pendingAnimation = .some(LayoutDefaults.tabBarMinimizeAnimation)
            }
            needsUpdate = true
            if !isEvaluating { update() }
        }
    }

    /// Lays the evaluated tree out with the current scroll offsets, and
    /// records each scroll view's metrics.
    func layoutAgain() {
        scrolling.metrics = [:]
        lazy.beginLayout()
        root = layoutEngine.layout(resolvedRoot)
        SwipeLayout.apply(to: &root, state: &swipe)
    }
}
