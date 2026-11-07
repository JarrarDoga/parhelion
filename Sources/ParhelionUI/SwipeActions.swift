#if canImport(Foundation)
import Foundation
#endif

/// A horizontal edge, mirroring SwiftUI's `HorizontalEdge`.
public enum HorizontalEdge: Int8, CaseIterable, Hashable, Sendable {
    case leading
    case trailing
}

extension View {
    /// Adds actions to the leading or trailing edge of a list row, revealed
    /// by swiping the row, mirroring SwiftUI's `swipeActions`.
    ///
    /// The actions are buttons. Their tint is the button's own `tint(_:)`;
    /// a destructive button is red, and any other is gray. With
    /// `allowsFullSwipe`, dragging the row most of the way across runs the
    /// first action, the one at the edge. Outside a ``List``, as in SwiftUI,
    /// the modifier does nothing.
    public func swipeActions<T: View>(
        edge: HorizontalEdge = .trailing,
        allowsFullSwipe: Bool = true,
        @ViewBuilder content: () -> T
    ) -> some View {
        SwipeActionsView(
            content: self, actions: content(), edge: edge, allowsFullSwipe: allowsFullSwipe)
    }
}

/// The view behind ``View/swipeActions(edge:allowsFullSwipe:content:)``.
struct SwipeActionsView<Content: View, Actions: View>: View {
    typealias Body = Never

    let content: Content
    let actions: Actions
    let edge: HorizontalEdge
    let allowsFullSwipe: Bool

    var body: Never { fatalError("SwipeActionsView is a primitive view and has no body.") }
}

extension SwipeActionsView: PrimitiveView {
    /// A row gets an `Overlay` child, like the one `overlay(alignment:content:)`
    /// adds, so that layout leaves the actions out of the row's own layout.
    /// Inside it, a `SwipeActions` node holds the action buttons. After layout,
    /// ``SwipeLayout`` moves the row and the buttons by the row's offset.
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let nodes = evaluator.evaluate(content, at: path)
        // Swipe actions belong to the rows of a list.
        guard evaluator.environment.isInList else { return nodes }
        SwipeLayout.register()
        return nodes.map { row in
            var row = row
            let count = row.children.count { $0.kind == "Overlay" }
            let overlayPath = ViewPath().appending(row.id.rawValue)
                .appending(count == 0 ? "overlay" : "overlay\(count + 1)")
            let stripPath = overlayPath.appending("SwipeActions")
            let buttons = evaluator.withEnvironment({ $0.fontWeight = $0.fontWeight ?? .medium }) {
                evaluator.evaluate(actions, at: stripPath)
            }
            // Running an action closes the row, as on iOS.
            let rowID = row.id
            for button in buttons.flatMap(\.allNodes) where button.kind == "Button" {
                evaluator.appendToAction(for: button.id) { [weak host = evaluator.host] in
                    host?.closeSwipe(rowID)
                }
            }
            var attributes = ["edge": edge == .leading ? "leading" : "trailing"]
            if !allowsFullSwipe { attributes["allowsFullSwipe"] = "false" }
            row.children.append(
                ViewNode(
                    id: overlayPath.id, kind: "Overlay",
                    children: [
                        ViewNode(
                            id: stripPath.id, kind: "SwipeActions", attributes: attributes,
                            children: buttons)
                    ]))
            row.modifiers.append(.overlay(alignment: edge == .leading ? .leading : .trailing))
            // Every row records the clip that keeps its sliding content in
            // its cell once, however many edges it has.
            if !row.modifiers.contains(where: \.isSwipeClip) {
                row.modifiers.append(SwipeLayout.clipModifier)
            }
            let edges =
                (row.attributes["swipeActions"].map { $0.split(separator: ",") } ?? [])
                .map(String.init) + [attributes["edge"] ?? ""]
            row.attributes["swipeActions"] = edges.joined(separator: ",")
            return row
        }
    }
}

extension LayoutModifier {
    var isSwipeClip: Bool {
        if case .custom(let modifier) = self { return modifier.name == SwipeLayout.clipName }
        return false
    }
}

// MARK: - Layout

/// What the layout knows about a row's actions, kept by the host.
struct SwipeRowInfo: Equatable {
    /// How far the row moves to show all of the actions on each edge, or 0
    /// when it has none there.
    var leadingWidth: CGFloat = 0
    var trailingWidth: CGFloat = 0
    var cellWidth: CGFloat = 0
    /// Whether a full swipe runs the first action, per edge.
    var leadingFullSwipe = false
    var trailingFullSwipe = false

    /// How far the row can move toward an edge before it stops.
    func limit(toward positive: Bool) -> CGFloat {
        let (width, full) =
            positive ? (leadingWidth, leadingFullSwipe) : (trailingWidth, trailingFullSwipe)
        guard width > 0 else { return 0 }
        return full ? cellWidth : width + SwipeLayout.rubberBand
    }

    func width(toward positive: Bool) -> CGFloat { positive ? leadingWidth : trailingWidth }

    /// How far a full swipe has to go to run the first action.
    func fullSwipeDistance(toward positive: Bool) -> CGFloat? {
        let (width, full) =
            positive ? (leadingWidth, leadingFullSwipe) : (trailingWidth, trailingFullSwipe)
        guard full, width > 0 else { return nil }
        return max(width + SwipeLayout.fullSwipeExtra, cellWidth * SwipeLayout.fullSwipeFraction)
    }
}

/// The state of swipe actions in a ``ViewHost``.
struct SwipeHostState {
    /// How far each row is moved: negative reveals its trailing actions,
    /// positive its leading ones. Rows at rest are not in the table.
    var offsets: [NodeID: CGFloat] = [:]
    /// What layout found out about each row with actions.
    var rows: [NodeID: SwipeRowInfo] = [:]
}

/// A press that started on a row with swipe actions, or while one was open.
struct SwipePress {
    /// The row being dragged, once the press turned into a swipe.
    var row: NodeID?
    var startOffset: CGFloat = 0
    /// An open row to close when the press ends without moving.
    var closeOnRelease: NodeID?
    /// Recent horizontal positions, for the release velocity.
    var samples: [(time: TimeInterval, x: CGFloat)] = []
}

/// Swipe actions: layout after the engine, and the numbers.
enum SwipeLayout {
    // Assumed, from iOS 26 rather than a source: an action is at least 74
    // points wide, with 16 points either side of its label, and actions
    // are 8 points apart and from the row.
    static let minimumButtonWidth: CGFloat = 74
    static let buttonPadding: CGFloat = 16
    static let spacing: CGFloat = 8
    /// How far past its actions a row without a full swipe can be pulled.
    static let rubberBand: CGFloat = 24
    /// A full swipe runs the first action once the row has moved this much
    /// past the actions, or half of its width, whichever is more.
    static let fullSwipeExtra: CGFloat = 40
    static let fullSwipeFraction: CGFloat = 0.5
    /// Release speed, in points per second, that opens or closes a row
    /// regardless of how far it moved.
    static let flingVelocity: CGFloat = 400
    static let cornerRadius: CGFloat = 26

    static let clipName = "swipeClip"
    static let clipModifier = LayoutModifier.custom(CustomModifier(name: clipName))

    /// Registers how the actions are laid out and drawn; see
    /// Rendering+SwipeActions.swift.
    static func register() {
        NodeExtensions.registerOnce(kind: "SwipeActions", swipeActionsBehavior)
        NodeExtensions.registerOnce(modifier: clipName, swipeClipBehavior)
    }

    /// Places the action buttons side by side, each as wide as its label
    /// needs. Layout moves them to where the row's offset puts them.
    static func placeButtons(_ engine: LayoutEngine, _ node: ViewNode, _ rect: CGRect) -> [ViewNode]
    {
        var x = rect.minX
        return node.children.map { button in
            let natural = engine.sizeThatFits(button, .unspecified, parentAxis: nil)
            let width = max(natural.width + 2 * buttonPadding, minimumButtonWidth)
            defer { x += width + spacing }
            return engine.place(
                button, in: CGRect(x: x, y: rect.minY, width: width, height: rect.height),
                parentAxis: nil)
        }
    }

    /// Moves each row with actions by its offset and puts its action buttons
    /// where that reveals them. Called after the layout engine, on a tree
    /// that has every row at rest.
    @MainActor
    static func apply(to root: inout ViewNode, state: inout SwipeHostState) {
        var found: [NodeID: SwipeRowInfo] = [:]
        visit(&root, state: state, found: &found)
        state.rows = found
        state.offsets = state.offsets.filter { found[$0.key] != nil }
    }

    @MainActor
    private static func visit(
        _ node: inout ViewNode, state: SwipeHostState, found: inout [NodeID: SwipeRowInfo]
    ) {
        if node.attributes["swipeActions"] != nil, let cell = node.listRowFrame {
            arrange(&node, in: cell, state: state, found: &found)
        }
        for index in node.children.indices {
            visit(&node.children[index], state: state, found: &found)
        }
    }

    @MainActor
    private static func arrange(
        _ row: inout ViewNode, in cell: CGRect, state: SwipeHostState,
        found: inout [NodeID: SwipeRowInfo]
    ) {
        // Per edge: the child index of its overlay, and its buttons' widths.
        struct Strip {
            var index: Int
            var widths: [CGFloat]
            var fullSwipe: Bool
            var total: CGFloat { widths.reduce(0, +) + SwipeLayout.spacing * CGFloat(widths.count) }
        }
        var strips: [HorizontalEdge: Strip] = [:]
        for index in row.children.indices where row.children[index].isOverlayContent {
            guard let strip = row.children[index].children.first, strip.kind == "SwipeActions"
            else { continue }
            let edge: HorizontalEdge = strip.attributes["edge"] == "leading" ? .leading : .trailing
            strips[edge] = Strip(
                index: index, widths: strip.children.map { $0.frame?.width ?? 0 },
                fullSwipe: strip.attributes["allowsFullSwipe"] != "false")
        }
        var info = SwipeRowInfo(cellWidth: cell.width)
        if let strip = strips[.leading], !strip.widths.isEmpty {
            info.leadingWidth = strip.total
            info.leadingFullSwipe = strip.fullSwipe
        }
        if let strip = strips[.trailing], !strip.widths.isEmpty {
            info.trailingWidth = strip.total
            info.trailingFullSwipe = strip.fullSwipe
        }
        found[row.id] = info

        let offset = min(
            max(state.offsets[row.id] ?? 0, -info.limit(toward: false)), info.limit(toward: true))

        // The row slides inside its cell: everything but the actions moves.
        if offset != 0 {
            var content = row
            content.children = row.children.filter { !$0.isOverlayContent }
            content = TreeRenderer.translated(content, by: CGSize(width: offset, height: 0))
            row.frame = content.frame
            row.modifierFrames = content.modifierFrames
            row.children = content.children + row.children.filter(\.isOverlayContent)
        }
        // The cell and the clip stay where they were.
        for index in row.modifiers.indices
        where index < row.modifierFrames.count
            && (row.modifiers[index].isListRow || row.modifiers[index].isSwipeClip)
        {
            row.modifierFrames[index] = cell
        }
        for (edge, strip) in strips {
            arrangeStrip(
                &row.children[strip.index], edge: edge, in: cell, offset: offset,
                widths: strip.widths, fullDistance: info.fullSwipeDistance(toward: edge == .leading)
            )
        }
        row.attributes["swipeOffset"] = offset == 0 ? nil : formatPoints(offset)
    }

    /// Places one edge's buttons for a row moved by `offset`.
    ///
    /// The buttons are rigid with the row, 8 points from its edge, the first
    /// action at the edge of the cell. A fully swiped first action grows to
    /// fill the space the row left, and the others go.
    private static func arrangeStrip(
        _ overlay: inout ViewNode, edge: HorizontalEdge, in cell: CGRect, offset: CGFloat,
        widths: [CGFloat], fullDistance: CGFloat?
    ) {
        guard !overlay.children.isEmpty else { return }
        let isTrailing = edge == .trailing
        // How far this edge's actions are pulled out; negative when the row
        // is moved the other way.
        let revealed = isTrailing ? -offset : offset
        let total = widths.reduce(0, +) + spacing * CGFloat(widths.count)
        let armed = fullDistance.map { revealed >= $0 } ?? false
        let isClosed = revealed < 0.5

        // Left to right: a trailing strip lists its actions in reverse, so
        // that the first is at the cell's edge.
        let order = isTrailing ? Array(widths.indices.reversed()) : Array(widths.indices)
        let start = isTrailing ? cell.maxX - revealed + spacing : cell.minX + revealed - total
        var strip = overlay.children[0]
        var x = start
        var union = CGRect.null
        for index in order {
            var button = strip.children[index]
            let width = widths[index]
            var target = CGRect(x: x, y: cell.minY, width: width, height: cell.height)
            x += width + spacing
            if armed {
                if index == 0 {
                    target =
                        isTrailing
                        ? CGRect(
                            x: cell.maxX - revealed + spacing, y: cell.minY,
                            width: max(revealed - spacing, 0), height: cell.height)
                        : CGRect(
                            x: cell.minX, y: cell.minY, width: max(revealed - spacing, 0),
                            height: cell.height)
                } else {
                    // Out of the way, past the clip.
                    target = CGRect(
                        x: cell.maxX + cell.width, y: cell.minY, width: width, height: cell.height)
                }
            }
            if let frame = button.frame {
                let center = CGSize(
                    width: target.midX - frame.midX, height: target.midY - frame.midY)
                button = TreeRenderer.translated(button, by: center)
            }
            // A button that is not out has no area to press.
            button.frame = isClosed ? CGRect(origin: target.origin, size: .zero) : target
            if !isClosed { union = union.union(target) }
            strip.children[index] = button
        }
        strip.frame = union.isNull ? CGRect(origin: cell.origin, size: .zero) : union
        overlay.frame = cell
        overlay.children[0] = strip
    }
}

// MARK: - Host

extension ViewHost {
    /// The row with actions that is open, if any.
    var openSwipeRow: NodeID? {
        swipe.offsets.first { abs($0.value) > 0.5 }?.key
    }

    /// Closes a row's actions, with the navigation animation.
    func closeSwipe(_ row: NodeID) {
        settleSwipe(row, to: 0)
    }

    /// Moves a row to rest at `offset` with a spring.
    func settleSwipe(_ row: NodeID, to offset: CGFloat) {
        guard swipe.offsets[row] != nil || offset != 0 else { return }
        swipe.offsets[row] = offset == 0 ? nil : offset
        pendingAnimation = .some(LayoutDefaults.presentationAnimation)
        relayout()
    }

    /// The row with swipe actions under a point, with its layout.
    private func swipeRow(at point: CGPoint) -> (id: NodeID, info: SwipeRowInfo)? {
        guard
            let node = frontmostNode(
                at: point, in: interactiveRoot, where: { swipe.rows[$0.id] != nil })
        else { return nil }
        return swipe.rows[node.id].map { (node.id, $0) }
    }

    /// Looks at a press that starts: while a row is open, a press anywhere
    /// but on its actions only closes it, as on iOS.
    func swipePressBegan(at point: CGPoint, button: inout NodeID?) -> SwipePress {
        var press = SwipePress()
        guard let open = openSwipeRow else { return press }
        let onActions =
            button.map { id in
                root.node(withID: open)?.children.contains {
                    $0.isOverlayContent && $0.node(withID: id) != nil
                } ?? false
            } ?? false
        if !onActions {
            button = nil
            press.closeOnRelease = open
        }
        return press
    }

    /// Whether a press that moved turns into a swipe of a row, and if so,
    /// starts it. A swipe is mostly sideways and begins on a row with
    /// actions on the side it moves toward, or on the open row.
    func swipeBegan(_ press: inout SwipePress, from start: CGPoint, moved: CGSize) -> Bool {
        guard abs(moved.width) > abs(moved.height) else { return false }
        let row: (id: NodeID, info: SwipeRowInfo)?
        if let open = openSwipeRow, let info = swipe.rows[open],
            root.node(withID: open)?.listRowFrame?.contains(start) == true
        {
            row = (open, info)
        } else if let found = swipeRow(at: start),
            found.info.width(toward: moved.width > 0) > 0
        {
            row = found
        } else {
            row = nil
        }
        // A gesture in the row, or one with priority, keeps the press.
        guard let row, handOverPress(to: row.id, includingNode: true) else { return false }
        if let open = openSwipeRow, open != row.id { closeSwipe(open) }
        press.row = row.id
        press.closeOnRelease = nil
        press.startOffset = swipe.offsets[row.id] ?? 0
        press.samples = [(time, start.x)]
        return true
    }

    /// Follows the pointer with a swiped row.
    func swipeMoved(_ press: inout SwipePress, from start: CGPoint, to point: CGPoint) {
        guard let row = press.row, let info = swipe.rows[row] else { return }
        let raw = press.startOffset + point.x - start.x
        // Past its actions a row without a full swipe resists.
        func resisted(_ distance: CGFloat, width: CGFloat, full: Bool) -> CGFloat {
            guard !full, distance > width else { return distance }
            return width + min((distance - width) * 0.25, SwipeLayout.rubberBand)
        }
        let offset: CGFloat
        if raw < 0 {
            offset = -min(
                resisted(-raw, width: info.trailingWidth, full: info.trailingFullSwipe),
                info.limit(toward: false))
        } else {
            offset = min(
                resisted(raw, width: info.leadingWidth, full: info.leadingFullSwipe),
                info.limit(toward: true))
        }
        swipe.offsets[row] = offset == 0 ? nil : offset
        press.samples.append((time, point.x))
        press.samples.removeAll { time - $0.time > 0.15 }
        relayout()
    }

    /// Ends a swipe. A row dragged most of the way across runs its first
    /// action; one dragged halfway, or flung, stays open; otherwise it closes.
    func swipeEnded(_ press: SwipePress, at point: CGPoint) {
        guard let row = press.row, let info = swipe.rows[row] else { return }
        let offset = swipe.offsets[row] ?? 0
        let positive = offset > 0
        let revealed = abs(offset)
        var velocity: CGFloat = 0
        if let first = press.samples.first, time - first.time > 0.001 {
            velocity = (point.x - first.x) / CGFloat(time - first.time)
        }
        if revealed > 0, let full = info.fullSwipeDistance(toward: positive), revealed >= full,
            let action = firstSwipeAction(of: row, leading: positive)
        {
            // The action closes the row when it runs.
            try? tap(action)
            if swipe.offsets[row] != nil { closeSwipe(row) }
            return
        }
        let width = info.width(toward: positive)
        // A fling toward the actions opens the row; away from them, closes it.
        let towardActions = positive ? velocity : -velocity
        let opens: Bool
        if abs(velocity) > SwipeLayout.flingVelocity {
            opens = towardActions > 0
        } else {
            opens = revealed > width / 2
        }
        settleSwipe(row, to: opens ? (positive ? width : -width) : 0)
    }

    /// The first action of a row's leading or trailing edge.
    private func firstSwipeAction(of row: NodeID, leading: Bool) -> NodeID? {
        guard let node = root.node(withID: row) else { return nil }
        let edge = leading ? "leading" : "trailing"
        for overlay in node.children where overlay.isOverlayContent {
            guard let strip = overlay.children.first, strip.kind == "SwipeActions",
                strip.attributes["edge"] == edge
            else { continue }
            return strip.children.flatMap(\.allNodes).first { hasAction($0.id) }?.id
        }
        return nil
    }
}
