import Foundation

/// The values of a scroll view's geometry, mirroring SwiftUI's
/// `ScrollGeometry`.
public struct ScrollGeometry: Equatable, Sendable {
    public var contentOffset: CGPoint
    public var contentSize: CGSize
    public var contentInsets: EdgeInsets
    public var containerSize: CGSize

    public var visibleRect: CGRect {
        CGRect(origin: contentOffset, size: containerSize)
    }

    public var bounds: CGRect {
        CGRect(origin: .zero, size: contentSize)
    }

    public init(
        contentOffset: CGPoint, contentSize: CGSize, contentInsets: EdgeInsets,
        containerSize: CGSize
    ) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.contentInsets = contentInsets
        self.containerSize = containerSize
    }
}

/// A scroll view's position, mirroring SwiftUI's `ScrollPosition`.
public struct ScrollPosition: Equatable {
    public var edge: Edge?
    public var point: CGPoint?
    public var x: CGFloat?
    public var y: CGFloat?
    public internal(set) var isPositionedByUser: Bool = false
    var id: AnyHashable?
    var anchor: UnitPoint?

    public init() {}

    public init<ID: Hashable>(id: ID, anchor: UnitPoint? = nil) {
        self.id = AnyHashable(id)
        self.anchor = anchor
    }

    public init(edge: Edge) {
        self.edge = edge
    }

    public init(point: CGPoint) {
        self.point = point
    }

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public var viewID: (any Hashable)? { id?.base as? any Hashable }

    public func viewID<ID: Hashable>(type: ID.Type) -> ID? { id?.base as? ID }

    public mutating func scrollTo<ID: Hashable>(id: ID, anchor: UnitPoint? = nil) {
        self = ScrollPosition(id: id, anchor: anchor)
    }

    public mutating func scrollTo(edge: Edge) { self = ScrollPosition(edge: edge) }
    public mutating func scrollTo(point: CGPoint) { self = ScrollPosition(point: point) }
    public mutating func scrollTo(x: CGFloat) {
        clearDestination()
        self.x = x
    }

    public mutating func scrollTo(y: CGFloat) {
        clearDestination()
        self.y = y
    }

    private mutating func clearDestination() {
        id = nil
        anchor = nil
        edge = nil
        point = nil
        isPositionedByUser = false
    }
}

// MARK: - Modifiers

extension View {
    /// Binds the identifier of the view at the start of a scroll view to
    /// `id`, in both directions: scrolling changes the binding, and setting
    /// it scrolls to that view, with `anchor` at the same place in the
    /// visible region. The views that count are those with an `id(_:)`, or a
    /// `ForEach` element's identifier, inside a view with
    /// `scrollTargetLayout()`, or any such view if there is none.
    ///
    /// Assumed: the binding stays as the app set it until the user scrolls,
    /// and then holds the first view whose end is past the anchor's place in
    /// the visible region; without an anchor, the start is the place, for
    /// reading and for setting.
    public func scrollPosition<ID: Hashable>(
        id: Binding<ID?>, anchor: UnitPoint? = nil
    ) -> some View {
        ScrollStateModifier(content: self) { scroll, node in
            scroll.positions[node] = ScrollPositionBinding(identifier: id, anchor: anchor)
        }
    }

    /// Binds a scroll view's position to `position`, in both directions.
    /// Setting an edge, a point, or an identifier scrolls the view there.
    /// When the user scrolls, `position` holds the offset as a `point`, and
    /// the identifier of the view at the start, if there is one.
    public func scrollPosition(
        _ position: Binding<ScrollPosition>, anchor: UnitPoint? = nil
    ) -> some View {
        ScrollStateModifier(content: self) { scroll, node in
            scroll.positions[node] = ScrollPositionBinding(position: position, anchor: anchor)
        }
    }

    /// Marks the children of a view as the places a scroll view can settle
    /// on and report as its position, for `scrollPosition(id:)` and
    /// `scrollTargetBehavior(.viewAligned)`.
    public func scrollTargetLayout(isEnabled: Bool = true) -> some View {
        ScrollTargetLayoutModifier(content: self, isEnabled: isEnabled)
    }

    /// Calls `action` when the value that `transform` makes from the
    /// geometry of the scroll view changes, with the old and new values.
    /// Assumed: it also runs once when the scroll view first appears, with
    /// the value as both.
    ///
    /// The content offset is relative to the content's origin, so a scroll
    /// view that starts below the safe area has a negative offset at rest,
    /// as on iOS.
    public func onScrollGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (ScrollGeometry) -> T,
        action: @escaping (T, T) -> Void
    ) -> some View {
        ScrollStateModifier(content: self) { scroll, node in
            scroll.observers[node, default: []].append(
                ScrollGeometryObserver { geometry, previous in
                    let value = transform(geometry)
                    if let previous = previous as? T {
                        if previous != value { action(previous, value) }
                    } else {
                        action(value, value)
                    }
                    return value
                })
        }
    }
}

/// A view that registers scroll state for the first scroll view in its
/// content.
struct ScrollStateModifier<Content: View>: View {
    typealias Body = Never

    let content: Content
    let register: @MainActor (ScrollEvaluation, NodeID) -> Void

    init(content: Content, register: @escaping @MainActor (ScrollEvaluation, NodeID) -> Void) {
        self.content = content
        self.register = register
    }

    var body: Never {
        fatalError("ScrollStateModifier is a primitive view and has no body.")
    }
}

extension ScrollStateModifier: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let nodes = evaluator.evaluate(content, at: path)
        // The outermost scroll view in the content, as the modifier applies
        // to the scroll views a view contains.
        func firstScrollView(in nodes: [ViewNode]) -> NodeID? {
            for node in nodes {
                if node.isScrollContainer { return node.id }
                if let found = firstScrollView(in: node.children) { return found }
            }
            return nil
        }
        if let id = firstScrollView(in: nodes) { register(evaluator.scrollRecord, id) }
        return nodes
    }
}

/// The modifier of `scrollTargetLayout(isEnabled:)`.
struct ScrollTargetLayoutModifier<Content: View>: View {
    typealias Body = Never

    let content: Content
    let isEnabled: Bool

    var body: Never {
        fatalError("ScrollTargetLayoutModifier is a primitive view and has no body.")
    }
}

extension ScrollTargetLayoutModifier: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let nodes = evaluator.evaluate(content, at: path)
        guard isEnabled else { return nodes }
        return nodes.map { node in
            var node = node
            node.attributes["scrollTargetLayout"] = "true"
            return node
        }
    }
}

// MARK: - Records

/// Where a scroll goes.
enum ScrollDestination {
    /// A view, with the place in the visible region to put it, or `nil` to
    /// scroll by the least that shows it.
    case id(AnyHashable, UnitPoint?)
    case edge(Edge)
    /// An offset, on the axes that are set.
    case point(x: CGFloat?, y: CGFloat?)
}

/// A scroll that the next layout applies.
struct ScrollRequest {
    var destination: ScrollDestination
    /// The scroll view to move, or `nil` for the first one that contains
    /// the view.
    var scrollView: NodeID?
    /// The nodes to search first for the view, or none to search the tree.
    var scope: [NodeID]
    /// How many times the request found only an estimate of where a lazy
    /// row is, and was applied again once the row existed.
    var attempts = 0
}

/// How the app's binding relates to a scroll view's position.
@MainActor
struct ScrollPositionBinding {
    var anchor: UnitPoint?
    /// The destination if the app changed the value since the last one this
    /// host honored or wrote (`nil` before any), along with that value.
    var pending: (_ lastKnown: Any?, _ hasSynced: Bool) -> (ScrollDestination, Any)?
    /// Writes what the user scrolled to, if the binding differs. Returns the
    /// value the binding holds afterwards.
    var write: (_ id: AnyHashable?, _ offset: CGPoint) -> Any?

    init<ID: Hashable>(identifier: Binding<ID?>, anchor: UnitPoint?) {
        // Assumed: without an anchor, a view the app sets goes to the start.
        let anchor = anchor ?? .zero
        self.anchor = anchor
        pending = { lastKnown, hasSynced in
            let current = identifier.wrappedValue.map { AnyHashable($0) }
            guard let current else { return nil }
            if hasSynced, let last = lastKnown as? AnyHashable, last == current { return nil }
            return (.id(current, anchor), current)
        }
        write = { id, _ in
            let typed = id?.base as? ID
            guard let typed, identifier.wrappedValue != typed else { return nil }
            identifier.wrappedValue = typed
            return AnyHashable(typed)
        }
    }

    init(position: Binding<ScrollPosition>, anchor: UnitPoint?) {
        let anchor = anchor ?? .zero
        self.anchor = anchor
        pending = { lastKnown, hasSynced in
            let current = position.wrappedValue
            if hasSynced, let last = lastKnown as? ScrollPosition, last == current { return nil }
            let destination: ScrollDestination?
            if let id = current.id {
                destination = .id(id, current.anchor ?? anchor)
            } else if let edge = current.edge {
                destination = .edge(edge)
            } else if let point = current.point {
                destination = .point(x: point.x, y: point.y)
            } else if current.x != nil || current.y != nil {
                destination = .point(x: current.x, y: current.y)
            } else {
                destination = nil
            }
            // A value with nothing to scroll to is still known.
            return (destination ?? .point(x: nil, y: nil), current)
        }
        write = { id, offset in
            var value = ScrollPosition()
            value.id = id
            value.point = offset
            value.isPositionedByUser = true
            guard position.wrappedValue != value else { return nil }
            position.wrappedValue = value
            return value
        }
    }
}

/// One `onScrollGeometryChange` modifier: given the geometry and the last
/// value it saw, runs its action if the value changed and returns the value.
struct ScrollGeometryObserver {
    let run: @MainActor (ScrollGeometry, Any?) -> Any

    init(_ run: @escaping @MainActor (ScrollGeometry, Any?) -> Any) {
        self.run = run
    }
}

/// What one evaluation of the tree found about scrolling.
@MainActor
final class ScrollEvaluation {
    /// The identifier of each view with one, by node.
    var targets: [NodeID: AnyHashable] = [:]
    /// The bindings to scroll positions, by scroll view.
    var positions: [NodeID: ScrollPositionBinding] = [:]
    /// The geometry observers, by scroll view, outermost first.
    var observers: [NodeID: [ScrollGeometryObserver]] = [:]

    /// Names a `ForEach` element's views, unless they have an `id(_:)`.
    func recordImplicit(_ identifier: AnyHashable, for nodes: [ViewNode]) {
        for node in nodes where targets[node.id] == nil { targets[node.id] = identifier }
    }
}

/// What a host keeps about scrolling between evaluations.
@MainActor
final class ScrollHostState {
    var current = ScrollEvaluation()
    /// Scrolls waiting for the next layout.
    var requests: [ScrollRequest] = []
    /// What the host knows of each scroll view whose position is bound.
    var synced: [NodeID: SyncedPosition] = [:]
    /// The last value of each geometry observer, by scroll view and place.
    var observed: [ObservedKey: Any] = [:]

    struct SyncedPosition {
        var hasSynced = false
        /// The binding's value when the host last honored or wrote it.
        var lastKnown: Any?
        /// The offset when it was last in step with the binding.
        var offset: CGPoint?
    }

    struct ObservedKey: Hashable {
        let scrollView: NodeID
        let index: Int
    }
}

// MARK: - The host

extension ViewHost {
    /// Queues a scroll and asks for an update, which applies it after layout,
    /// so that it sees the views the same action changed.
    func requestScroll(_ request: ScrollRequest) {
        scrollState.requests.append(request)
        setNeedsUpdate()
    }

    /// Scrolls to the view with the identifier `id`, as
    /// ``ScrollViewProxy/scrollTo(_:anchor:)`` does for the scroll views in
    /// the whole tree.
    public func scroll<ID: Hashable>(toViewID id: ID, anchor: UnitPoint? = nil) {
        requestScroll(
            ScrollRequest(destination: .id(AnyHashable(id), anchor), scrollView: nil, scope: []))
        update()
    }

    /// The identifier of the view at the start of a scroll view, as
    /// `scrollPosition(id:)` would report it, or `nil` if no view there has
    /// one.
    public func scrollPositionID(of scrollView: NodeID, anchor: UnitPoint? = nil) -> AnyHashable? {
        guard let node = root.node(withID: scrollView), let metrics = scrolling.metrics[scrollView]
        else { return nil }
        return idAtStart(of: node, metrics: metrics, anchor: anchor)
    }

    /// Adopts what an evaluation found, before layout.
    func adoptScrollEvaluation(_ evaluation: ScrollEvaluation) {
        scrollState.current = evaluation
        let present = Set(evaluation.positions.keys)
        scrollState.synced = scrollState.synced.filter { present.contains($0.key) }
        scrollState.observed = scrollState.observed.filter {
            evaluation.observers[$0.key.scrollView] != nil
        }
    }

    // MARK: Before the layout settles

    /// Honors changes the app made to bound positions, then applies queued
    /// scrolls. Each lays the tree out again, so that the next sees where
    /// views are now.
    func applyScrollRequests() {
        let state = scrollState
        for (id, binding) in state.current.positions {
            let synced = state.synced[id] ?? .init()
            guard scrolling.metrics[id] != nil else { continue }
            if let (destination, known) = binding.pending(synced.lastKnown, synced.hasSynced) {
                state.synced[id] = .init(hasSynced: true, lastKnown: known, offset: nil)
                if case .point(nil, nil) = destination { continue }
                state.requests.append(
                    ScrollRequest(destination: destination, scrollView: id, scope: []))
            }
        }
        guard !state.requests.isEmpty else { return }
        let requests = state.requests
        state.requests = []
        for request in requests {
            guard let (scrollView, offset, estimated) = resolve(request) else { continue }
            momentum[scrollView] = nil
            scrolling.offsets[scrollView] = offset
            layoutAgain()
            // A lazy row that did not exist yet: the next evaluation creates
            // it there, and the request runs again to put it in place.
            // The host evaluates again at once when the screen moved past
            // the rows that exist, so the request waits only for that.
            if estimated, lazy.needsWindowChange, request.attempts < Self.maximumScrollAttempts {
                var again = request
                again.attempts += 1
                state.requests.append(again)
            }
            // The binding is in step with the scroll view at this offset.
            if var synced = state.synced[scrollView] {
                synced.offset = nil
                state.synced[scrollView] = synced
            }
        }
    }

    /// How many times a request to scroll to a lazy row that does not exist
    /// yet runs again.
    static let maximumScrollAttempts = 3

    /// A lazy row with the identifier that is not in the tree, from the
    /// lazy stacks of the last layout: its scroll view, and its frame along
    /// the stack, estimated if it was never measured.
    private func lazyTarget(
        _ identifier: AnyHashable, in scope: [NodeID], within scrollViewID: NodeID?
    ) -> (scrollView: ViewNode, frame: CGRect, vertical: Bool)? {
        let stacks = lazy.stacks.values.sorted { $0.id.rawValue < $1.id.rawValue }
        let inScope = { (stack: LazyLayoutState.Stack) -> Bool in
            scope.isEmpty || scope.contains { stack.id.rawValue.hasPrefix($0.rawValue) }
        }
        for stack in stacks where inScope(stack) {
            guard let viewport = stack.scrollView,
                scrollViewID == nil || viewport.id == scrollViewID,
                let span = stack.span(of: identifier),
                let scrollView = root.node(withID: viewport.id)
            else { continue }
            let frame =
                stack.vertical
                ? CGRect(x: viewport.rect.minX, y: span.start, width: 0, height: span.length)
                : CGRect(x: span.start, y: viewport.rect.minY, width: span.length, height: 0)
            return (scrollView, frame, stack.vertical)
        }
        return nil
    }

    /// The scroll view and offset a request leads to, in the laid-out tree,
    /// and whether the offset is an estimate, for a lazy row that does not
    /// exist yet.
    private func resolve(_ request: ScrollRequest) -> (NodeID, CGPoint, estimated: Bool)? {
        switch request.destination {
        case .id(let identifier, let anchor):
            let scrollView: ViewNode
            let frame: CGRect
            var axes: (horizontal: Bool, vertical: Bool)
            var estimated = false
            if let (found, target) = locateTarget(
                identifier, in: request.scope, within: request.scrollView),
                // A list row scrolls by its cell.
                let targetFrame = target.listRowFrame ?? target.frame
            {
                scrollView = found
                frame = targetFrame
                let scrollAxes = LayoutEngine.scrollAxes(of: found)
                axes = (scrollAxes.horizontal, scrollAxes.vertical)
            } else if let (found, estimate, vertical) = lazyTarget(
                identifier, in: request.scope, within: request.scrollView)
            {
                scrollView = found
                frame = estimate
                let scrollAxes = LayoutEngine.scrollAxes(of: found)
                axes = (scrollAxes.horizontal && !vertical, scrollAxes.vertical && vertical)
                estimated = true
            } else {
                return nil
            }
            guard let metrics = scrolling.metrics[scrollView.id] else { return nil }
            let visible = CGRect(
                x: metrics.viewport.minX, y: metrics.viewport.minY + metrics.topInset,
                width: metrics.viewport.width,
                height: max(metrics.viewport.height - metrics.topInset - metrics.bottomInset, 0))
            var offset = metrics.offset
            if axes.horizontal {
                offset.x += Self.shift(
                    frame.minX, frame.width, visible.minX, visible.width, anchor?.x)
            }
            if axes.vertical {
                offset.y += Self.shift(
                    frame.minY, frame.height, visible.minY, visible.height, anchor?.y)
            }
            return (scrollView.id, offset, estimated)
        case .edge(let edge):
            guard let id = request.scrollView, let metrics = scrolling.metrics[id] else {
                return nil
            }
            var offset = metrics.offset
            let max = metrics.maxOffset
            switch edge {
            case .top: offset.y = 0
            case .bottom: offset.y = max.y
            case .leading: offset.x = 0
            case .trailing: offset.x = max.x
            }
            return (id, offset, false)
        case .point(let x, let y):
            guard let id = request.scrollView, let metrics = scrolling.metrics[id] else {
                return nil
            }
            // A point is in the content's coordinates, whose origin is the
            // top of the content, below the inset.
            return (
                id,
                CGPoint(
                    x: x ?? metrics.offset.x, y: y.map { $0 + metrics.topInset } ?? metrics.offset.y
                ),
                false
            )
        }
    }

    /// How far to scroll so that a view's span is where `anchor` says in the
    /// visible span, or by the least that shows it without an anchor.
    private static func shift(
        _ start: CGFloat, _ length: CGFloat, _ visibleStart: CGFloat, _ visibleLength: CGFloat,
        _ anchor: CGFloat?
    ) -> CGFloat {
        if let anchor {
            return (start + anchor * length) - (visibleStart + anchor * visibleLength)
        }
        if start < visibleStart { return start - visibleStart }
        if start + length > visibleStart + visibleLength {
            // A view taller than the visible region shows its start.
            return min(start + length - (visibleStart + visibleLength), start - visibleStart)
        }
        return 0
    }

    /// The first view with an identifier, and the innermost scroll view that
    /// contains it. A request names the scroll view, or lists the nodes to
    /// search first.
    private func locateTarget(
        _ identifier: AnyHashable, in scope: [NodeID], within scrollViewID: NodeID?
    ) -> (scrollView: ViewNode, target: ViewNode)? {
        let targets = scrollState.current.targets
        func search(_ node: ViewNode, _ scrollViews: [ViewNode]) -> (ViewNode, ViewNode)? {
            if targets[node.id] == identifier, let scrollView = scrollViews.last {
                return (scrollView, node)
            }
            let inner = node.isScrollContainer ? scrollViews + [node] : scrollViews
            for child in node.children {
                if let found = search(child, inner) { return found }
            }
            return nil
        }
        if let scrollViewID, let scrollView = root.node(withID: scrollViewID) {
            return scrollView.children.lazy.compactMap { search($0, [scrollView]) }.first
        }
        for id in scope {
            guard let node = root.node(withID: id) else { continue }
            // The scroll views above the scope are not known here; a scope
            // is the content of a reader, which holds the scroll views.
            if let found = search(node, []) { return found }
        }
        return search(root, [])
    }

    // MARK: After the layout settles

    /// Writes what the user scrolled to into the bindings, and runs the
    /// geometry observers.
    func finishScrollLayout() {
        let state = scrollState
        for (id, binding) in state.current.positions {
            guard let node = root.node(withID: id), let metrics = scrolling.metrics[id] else {
                continue
            }
            var synced = state.synced[id] ?? .init()
            defer { state.synced[id] = synced }
            // The first offset the host sees is the one the binding starts at.
            guard let offset = synced.offset else {
                synced.offset = metrics.offset
                continue
            }
            guard offset != metrics.offset else { continue }
            synced.offset = metrics.offset
            let identifier = idAtStart(of: node, metrics: metrics, anchor: binding.anchor)
            let logical = CGPoint(x: metrics.offset.x, y: metrics.offset.y - metrics.topInset)
            if let written = binding.write(identifier, logical) {
                synced.lastKnown = written
                synced.hasSynced = true
            }
        }
        for (id, observers) in state.current.observers {
            guard let metrics = scrolling.metrics[id] else { continue }
            let geometry = ScrollGeometry(metrics)
            for (index, observer) in observers.enumerated() {
                let key = ScrollHostState.ObservedKey(scrollView: id, index: index)
                state.observed[key] = observer.run(geometry, state.observed[key])
            }
        }
    }

    /// The identifier of the first target whose end is past the place the
    /// anchor names in the visible region.
    func idAtStart(
        of scrollView: ViewNode, metrics: ScrollMetrics, anchor: UnitPoint?
    ) -> AnyHashable? {
        let axes = LayoutEngine.scrollAxes(of: scrollView)
        let horizontal = axes.horizontal && !axes.vertical
        let visibleStart =
            horizontal ? metrics.viewport.minX : metrics.viewport.minY + metrics.topInset
        let visibleLength =
            horizontal
            ? metrics.viewport.width
            : max(metrics.viewport.height - metrics.topInset - metrics.bottomInset, 0)
        let fraction = (horizontal ? anchor?.x : anchor?.y) ?? 0
        let line = visibleStart + fraction * visibleLength
        let targets = scrollState.current.targets
        for target in scrollTargets(in: scrollView) {
            guard let identifier = targets[target.id], let frame = target.frame else { continue }
            let end = horizontal ? frame.maxX : frame.maxY
            if end > line + 0.5 { return identifier }
        }
        return nil
    }

    /// The views a scroll view settles on and reports: the children of the
    /// views marked with `scrollTargetLayout()`, or, if none is, the
    /// outermost views with an identifier.
    func scrollTargets(in scrollView: ViewNode) -> [ViewNode] {
        let targets = scrollState.current.targets
        var marked: [ViewNode] = []
        func collectMarked(_ node: ViewNode) {
            if node.attributes["scrollTargetLayout"] == "true" {
                marked.append(contentsOf: node.children)
                return
            }
            for child in node.children where !child.isScrollContainer { collectMarked(child) }
        }
        scrollView.children.forEach(collectMarked)
        if !marked.isEmpty { return marked }

        var found: [ViewNode] = []
        func collectIdentified(_ node: ViewNode) {
            if targets[node.id] != nil {
                found.append(node)
                return
            }
            for child in node.children where !child.isScrollContainer { collectIdentified(child) }
        }
        scrollView.children.forEach(collectIdentified)
        return found
    }
}

extension ScrollGeometry {
    /// The geometry of a scroll view from its layout. The offset is relative
    /// to the content's origin, so it is negative while the content sits
    /// below an inset, as on iOS.
    init(_ metrics: ScrollMetrics) {
        self.init(
            contentOffset: CGPoint(x: metrics.offset.x, y: metrics.offset.y - metrics.topInset),
            contentSize: metrics.contentSize,
            contentInsets: EdgeInsets(
                top: metrics.topInset, leading: 0, bottom: metrics.bottomInset, trailing: 0),
            containerSize: metrics.viewport.size)
    }
}
