import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// Pull to refresh: `refreshable(action:)` on a view that contains a `List` or a
// vertical `ScrollView`.
//
// The modifier sets the `refresh` environment value for its content and marks
// each vertical scroll view in the content `refreshable=true`, registering the
// action for it. Dragging such a scroll view down while it is at its top pulls
// a gap open above the content, with iOS's spinner in it. Releasing past the
// threshold runs the action as a host task, so ``ViewHost/waitForTasks()``
// waits for it, and holds the gap open until the action returns.

// MARK: - API

/// An action that refreshes the content of a view, mirroring SwiftUI's
/// `RefreshAction`.
public struct RefreshAction: Sendable {
    let action: @Sendable () async -> Void

    /// Runs the refresh action and returns when it is done.
    public func callAsFunction() async {
        await action()
    }
}

struct RefreshKey: EnvironmentKey {
    static var defaultValue: RefreshAction? { nil }
}

extension EnvironmentValues {
    /// The refresh action that the nearest `refreshable(action:)` above a view
    /// set, or `nil` if there is none.
    public internal(set) var refresh: RefreshAction? {
        get { self[RefreshKey.self] }
        set { self[RefreshKey.self] = newValue }
    }
}

extension View {
    /// Marks the vertical lists and scroll views in this view as refreshable:
    /// pulling one down past the threshold shows a spinner, runs `action`, and
    /// keeps the spinner until `action` returns. Also sets the `refresh`
    /// environment value for the content.
    ///
    /// A `refreshable` modifier closer to a scroll view takes precedence over
    /// one outside it.
    public func refreshable(action: @escaping @Sendable () async -> Void) -> some View {
        RefreshableView(content: self, action: action)
    }
}

extension ViewNode {
    /// Whether the node is a list or scroll view that pulling down refreshes.
    public var isRefreshable: Bool { attributes["refreshable"] == "true" }

    /// Whether a refresh action that this scroll view started is running.
    public var isRefreshing: Bool { attributes["refreshing"] == "true" }
}

// MARK: - The view

struct RefreshableView<Content: View>: View {
    typealias Body = Never

    let content: Content
    let action: @Sendable () async -> Void

    var body: Never {
        fatalError("RefreshableView is a primitive view and has no body.")
    }
}

extension RefreshableView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let refresh = RefreshAction(action: action)
        let nodes = evaluator.withEnvironment({ $0.refresh = refresh }) {
            evaluator.evaluate(content, at: path)
        }
        func mark(_ node: ViewNode) -> ViewNode {
            var node = node
            node.children = node.children.map(mark)
            guard node.isScrollContainer, LayoutEngine.scrollAxes(of: node).vertical,
                node.attributes["refreshable"] == nil
            else { return node }
            node.attributes["refreshable"] = "true"
            var handlers = evaluator.inputHandlers[node.id] ?? NodeInputHandlers()
            handlers.refresh = action
            evaluator.registerInputHandlers(handlers, for: node.id)
            return node
        }
        return nodes.map(mark)
    }
}

// MARK: - Metrics

/// Assumed: the distances of iOS's pull to refresh. The finger travels twice
/// as far as the content, and the action starts when the content has moved
/// 60 points.
enum RefreshMetrics {
    /// How much of the finger's travel past the top the content follows.
    static let resistance: CGFloat = 0.5
    /// The content's distance from its place at which releasing refreshes.
    static let threshold: CGFloat = 60
    /// The most the content follows a pull.
    static let maximumPull: CGFloat = 160
    /// The room the spinner keeps above the content while refreshing.
    static let holdHeight: CGFloat = 52
    /// The spokes of the spinner, which is 20 points across.
    static let spokes = 12
    static let spinnerInnerRadius: CGFloat = 5.5
    static let spinnerOuterRadius: CGFloat = 10
    static let spokeWidth: CGFloat = 2
}

// MARK: - State

/// What the host knows about pulls in progress, shared with the layout engine
/// through ``ScrollLayout``.
final class RefreshState {
    /// How far the finger is past the top of each scroll view being pulled.
    var travel: [NodeID: CGFloat] = [:]
    /// The room above the content of each scroll view: how far it follows a
    /// pull, or the hold height while the action runs.
    var pulls: [NodeID: CGFloat] = [:]
    /// The scroll views whose action is running.
    var refreshing: Set<NodeID> = []
    /// The spoke the spinner's head is on.
    var spoke = 0

    /// The room above the content of a scroll view, which layout adds to the
    /// top inset.
    func pull(for id: NodeID) -> CGFloat { pulls[id] ?? 0 }

    /// Records what the renderer needs on a scroll view that was laid out:
    /// where the gap starts, and how tall it is.
    func annotate(_ node: inout ViewNode, gapTop: CGFloat) {
        let pull = pull(for: node.id)
        guard pull > 0 else { return }
        node.attributes["refreshPull"] = formatPoints(pull)
        node.attributes["refreshTop"] = formatPoints(gapTop)
        if refreshing.contains(node.id) {
            node.attributes["refreshing"] = "true"
            node.attributes["refreshSpoke"] = String(spoke)
        }
    }

    /// Forgets scroll views that left the tree.
    func prune(keeping ids: Dictionary<NodeID, ScrollMetrics>.Keys) {
        let keep = Set(ids)
        travel = travel.filter { keep.contains($0.key) }
        pulls = pulls.filter { keep.contains($0.key) }
        refreshing.formIntersection(keep)
    }
}

// MARK: - Input

extension ViewHost {
    /// Whether a refresh action is running, so a client should keep drawing
    /// frames for the spinner.
    var isRefreshAnimating: Bool { !scrolling.refresh.refreshing.isEmpty }

    /// Handles the part of a drag that pulls a refreshable scroll view down
    /// from its top, and gives back the part that scrolls it.
    ///
    /// - Parameter delta: How far the content scrolls toward its end; a
    ///   negative height is a finger moving down.
    /// - Returns: What is left of `delta` to scroll by, or `nil` if the pull
    ///   used all of it.
    func pullToRefresh(_ id: NodeID, by delta: CGSize) -> CGSize? {
        let state = scrolling.refresh
        guard !state.refreshing.contains(id), let node = root.node(withID: id),
            node.isRefreshable, inputHandlers[id]?.refresh != nil,
            let metrics = scrolling.metrics[id]
        else { return delta }
        let offset = scrolling.offsets[id] ?? metrics.offset
        var travel = state.travel[id] ?? 0
        guard travel > 0 || (delta.height < 0 && offset.y <= 0) else { return delta }

        travel -= delta.height
        var remaining = delta
        remaining.height = 0
        if travel <= 0 {
            // The finger came back past the top: the rest scrolls.
            remaining.height = -travel
            travel = 0
        }
        state.travel[id] = travel > 0 ? travel : nil
        state.pulls[id] =
            travel > 0 ? min(travel * RefreshMetrics.resistance, RefreshMetrics.maximumPull) : nil
        relayout()
        return remaining.height == 0 ? nil : remaining
    }

    /// Ends a pull where the finger is lifted: starts the action if the pull
    /// passed the threshold, and lets the gap close otherwise.
    ///
    /// - Returns: Whether the scroll view was being pulled.
    func endRefreshPull(_ id: NodeID) -> Bool {
        let state = scrolling.refresh
        guard state.travel[id] != nil else { return false }
        let pull = state.pulls[id] ?? 0
        state.travel[id] = nil
        pendingAnimation = .some(LayoutDefaults.presentationAnimation)
        if pull >= RefreshMetrics.threshold, let action = inputHandlers[id]?.refresh {
            state.pulls[id] = RefreshMetrics.holdHeight
            state.refreshing.insert(id)
            lifecycle.track(name: "refreshable @ \(id.rawValue)") { [weak self] in
                await action()
                self?.finishRefresh(id)
            }
        } else {
            state.pulls[id] = nil
        }
        relayout()
        return true
    }

    private func finishRefresh(_ id: NodeID) {
        let state = scrolling.refresh
        guard state.refreshing.remove(id) != nil else { return }
        state.pulls[id] = nil
        pendingAnimation = .some(LayoutDefaults.presentationAnimation)
        relayout()
    }

    /// Turns the spinner of a refreshing scroll view as time passes.
    func advanceRefresh() {
        let state = scrolling.refresh
        guard !state.refreshing.isEmpty else { return }
        let spoke =
            Int((time * Double(RefreshMetrics.spokes)).rounded(.down)) % RefreshMetrics.spokes
        guard spoke != state.spoke else { return }
        state.spoke = spoke
        relayout()
    }
}

// MARK: - Drawing

extension TreeRenderer {
    /// Draws the spinner in the gap that a pull opened above a scroll view's
    /// content: spokes appearing as the pull grows, then all twelve, with a
    /// bright head that turns while the action runs.
    func drawRefreshControl(
        _ node: ViewNode, scheme: ColorScheme, paint: (RGBA) -> RGBA, into canvas: inout Canvas
    ) {
        guard let frame = node.frame,
            let pull = node.attributes["refreshPull"].flatMap(Double.init),
            let top = node.attributes["refreshTop"].flatMap(Double.init), pull > 0
        else { return }
        let gap = CGRect(x: frame.minX, y: CGFloat(top), width: frame.width, height: CGFloat(pull))
        let outerClip = canvas.clipRect
        canvas.clipRect = outerClip.map { $0.intersection(gap) } ?? gap
        defer { canvas.clipRect = outerClip }

        let refreshing = node.isRefreshing
        let progress = refreshing ? 1 : min(CGFloat(pull) / RefreshMetrics.threshold, 1)
        let spokes = RefreshMetrics.spokes
        let visible = refreshing ? spokes : max(Int((progress * CGFloat(spokes)).rounded(.down)), 1)
        let head = refreshing ? Int(node.attributes["refreshSpoke"] ?? "") ?? 0 : spokes - 1
        let base = ColorPalette.color(named: "secondary", in: scheme)
        let center = CGPoint(x: gap.midX, y: gap.midY)
        for index in 0..<visible {
            // The head is bright and the spokes behind it fade.
            let behind = CGFloat((head - index + spokes) % spokes) / CGFloat(spokes)
            var color = base
            color.alpha = UInt8((CGFloat(base.alpha) * (1 - behind * 0.75)).rounded())
            canvas.fill(Self.spoke(index, of: spokes, around: center), color: paint(color))
        }
    }

    /// A spoke of the spinner, clockwise from the top.
    private static func spoke(_ index: Int, of count: Int, around center: CGPoint) -> Path {
        let angle = Double(index) / Double(count) * 2 * .pi
        let direction = CGPoint(x: CGFloat(sin(angle)), y: CGFloat(-cos(angle)))
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let half = RefreshMetrics.spokeWidth / 2
        func point(_ radius: CGFloat, _ side: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + direction.x * radius + normal.x * half * side,
                y: center.y + direction.y * radius + normal.y * half * side)
        }
        var path = Path()
        path.move(to: point(RefreshMetrics.spinnerInnerRadius, -1))
        path.addLine(to: point(RefreshMetrics.spinnerOuterRadius, -1))
        path.addLine(to: point(RefreshMetrics.spinnerOuterRadius, 1))
        path.addLine(to: point(RefreshMetrics.spinnerInnerRadius, 1))
        path.closeSubpath()
        return path
    }
}
