#if canImport(Foundation)
import Foundation
#endif

/// What decides how one layout change animates.
struct AnimationRequest {
    /// The animation of the change, from `withAnimation` or navigation, if
    /// any. `.some(nil)` turns animation off.
    var transaction: Animation??
    /// Animations from `animation(_:value:)` modifiers whose value changed,
    /// by the identifiers of the nodes they cover.
    var implicit: [NodeID: Animation?] = [:]
    /// Transitions from the evaluation that produced the new tree.
    var transitions: [NodeID: AnyTransition] = [:]
    /// Transitions from the evaluation that produced the old tree, for the
    /// views being removed.
    var previousTransitions: [NodeID: AnyTransition] = [:]
    /// The navigation stacks that pushed or popped, by identifier.
    var navigation: [NodeID: NavigationDirection] = [:]
}

/// Which way a navigation stack moved.
enum NavigationDirection {
    case push, pop
}

/// Animates the frames and opacities that the renderer draws, while the tree
/// that tools read keeps its final values.
///
/// Positions animate relative to each node's parent, so a node moving with
/// its parent needs no animation of its own, and a change that is not
/// animated, such as scrolling, still moves animated content correctly. See
/// docs/adr/0005-model-tree-and-presented-frames.md.
@MainActor
final class AnimationEngine {
    /// A node moving from an old position, size, or opacity to its new one.
    private struct Displacement {
        var animation: Animation
        var start: TimeInterval
        /// The old values minus the new ones, relative to the parent.
        var origin: CGPoint
        var size: CGSize
        var opacity: Double
    }

    /// A node entering with a transition.
    private struct Entrance {
        var animation: Animation
        var start: TimeInterval
        var offset: CGSize
        var opacity: Double
    }

    /// A node that left the tree and is drawn until its transition ends.
    private struct Exit {
        var animation: Animation
        var start: TimeInterval
        /// The node as last drawn, with frames relative to its parent's
        /// origin.
        var node: ViewNode
        var parent: NodeID
        var index: Int
        /// Whether it draws above the siblings that follow it.
        var isAbove: Bool
        var offset: CGSize
        var opacity: Double
    }

    private var displacements: [NodeID: Displacement] = [:]
    private var entrances: [NodeID: Entrance] = [:]
    private var exits: [NodeID: Exit] = [:]

    /// Whether anything is still moving at `time`.
    func isActive(at time: TimeInterval) -> Bool {
        displacements.values.contains { time < $0.start + $0.animation.totalDuration }
            || entrances.values.contains { time < $0.start + $0.animation.totalDuration }
            || exits.values.contains { time < $0.start + $0.animation.totalDuration }
    }

    /// Forgets animations that have ended.
    func removeFinished(at time: TimeInterval) {
        displacements = displacements.filter {
            time < $0.value.start + $0.value.animation.totalDuration
        }
        entrances = entrances.filter { time < $0.value.start + $0.value.animation.totalDuration }
        exits = exits.filter { time < $0.value.start + $0.value.animation.totalDuration }
    }

    // MARK: - Starting animations

    /// Starts the animations for a change from what was on screen to a new
    /// tree.
    func update(
        from old: ViewNode, to new: ViewNode, request: AnimationRequest, at time: TimeInterval
    ) {
        var oldNodes: [NodeID: (node: ViewNode, parent: ViewNode?, index: Int)] = [:]
        func indexOld(_ node: ViewNode, parent: ViewNode?, index: Int) {
            guard exits[node.id] == nil || parent == nil else { return }
            oldNodes[node.id] = (node, parent, index)
            for (childIndex, child) in node.children.enumerated() {
                indexOld(child, parent: node, index: childIndex)
            }
        }
        indexOld(old, parent: nil, index: 0)

        var newNodes: [NodeID: (node: ViewNode, parent: ViewNode?)] = [:]
        func indexNew(_ node: ViewNode, parent: ViewNode?) {
            newNodes[node.id] = (node, parent)
            node.children.forEach { indexNew($0, parent: node) }
        }
        indexNew(new, parent: nil)

        func animation(for id: NodeID, kind: String?) -> Animation? {
            if let implicit = request.implicit[id] { return implicit }
            if let transaction = request.transaction { return transaction }
            if let kind, ["Sheet", "FullScreenCover", "Alert", "Menu"].contains(kind) {
                return LayoutDefaults.presentationAnimation
            }
            return nil
        }

        // Views that stay: animate changes in position, size, and opacity.
        for (id, entry) in newNodes {
            guard let target = entry.node.frame, let before = oldNodes[id],
                let previous = before.node.frame
            else { continue }
            exits[id] = nil
            let targetOrigin = Self.relativeOrigin(target, in: entry.parent)
            let previousOrigin = Self.relativeOrigin(previous, in: before.parent)
            let delta = Displacement(
                animation: .default,
                start: time,
                origin: CGPoint(
                    x: previousOrigin.x - targetOrigin.x, y: previousOrigin.y - targetOrigin.y),
                size: CGSize(
                    width: previous.width - target.width, height: previous.height - target.height),
                opacity: Self.opacity(of: before.node) - Self.opacity(of: entry.node)
            )
            let changed =
                abs(delta.origin.x) > 0.01 || abs(delta.origin.y) > 0.01
                || abs(delta.size.width) > 0.01 || abs(delta.size.height) > 0.01
                || abs(delta.opacity) > 0.001
            guard changed, let chosen = animation(for: id, kind: nil) else { continue }
            var displacement = delta
            displacement.animation = chosen
            displacements[id] = displacement
            // The old values already include any entrance in progress.
            entrances[id] = nil
        }

        // Views that arrive: the topmost one of each new subtree enters with
        // its transition.
        for (id, entry) in newNodes where oldNodes[id] == nil {
            guard let parent = entry.parent, oldNodes[parent.id] != nil,
                let frame = entry.node.frame,
                let chosen = animation(for: id, kind: entry.node.kind)
            else { continue }
            exits[id] = nil
            let effect = transition(
                for: entry.node, parent: parent, request.transitions, request.navigation,
                inserting: true
            ).insertion
            entrances[id] = Entrance(
                animation: chosen, start: time, offset: effect.offset(for: frame),
                opacity: effect.opacity)
        }

        // Views that leave: the topmost one of each removed subtree stays on
        // screen until its transition ends.
        for (id, entry) in oldNodes where newNodes[id] == nil {
            guard let parent = entry.parent, newNodes[parent.id] != nil,
                let frame = entry.node.frame,
                let chosen = request.implicit[parent.id]
                    ?? animation(for: id, kind: entry.node.kind)
            else { continue }
            let parentOrigin = parent.frame?.origin ?? .zero
            let transition = transition(
                for: entry.node, parent: newNodes[parent.id]?.node ?? parent,
                request.previousTransitions, request.navigation, inserting: false)
            let effect = transition.removal
            let direction = request.navigation[parent.id]
            exits[id] = Exit(
                animation: chosen,
                start: time,
                node: Self.translated(
                    entry.node, by: CGSize(width: -parentOrigin.x, height: -parentOrigin.y)),
                parent: parent.id,
                index: entry.index,
                isAbove: direction == .pop,
                offset: effect.offset(for: frame),
                opacity: effect.opacity
            )
        }
    }

    /// The transition for a node entering or leaving. A screen of a
    /// navigation stack slides across the stack; other views use their own
    /// transition, or fade.
    private func transition(
        for node: ViewNode,
        parent: ViewNode,
        _ transitions: [NodeID: AnyTransition],
        _ navigation: [NodeID: NavigationDirection],
        inserting: Bool
    ) -> AnyTransition {
        if parent.kind == "NavigationStack", node.kind != "NavigationBar",
            let direction = navigation[parent.id], let width = parent.frame?.width
        {
            let full = AnyTransition.Effect(offsets: [.fixed(CGSize(width: width, height: 0))])
            let partial = AnyTransition.Effect(
                opacity: 0,
                offsets: [
                    .fixed(CGSize(width: -width * LayoutDefaults.navigationParallax, height: 0))
                ])
            // Pushing slides the new screen in over the old one; popping
            // slides the top screen away to reveal the one beneath.
            return direction == .push
                ? AnyTransition(insertion: full, removal: partial)
                : AnyTransition(insertion: partial, removal: full)
        }
        if let transition = transitions[node.id] { return transition }
        switch node.kind {
        case "Sheet", "FullScreenCover": return .move(edge: .bottom)
        default: return .opacity
        }
    }

    // MARK: - Drawing

    /// The tree as it appears at `time`: the final tree with every animation
    /// in progress applied.
    func presented(_ root: ViewNode, at time: TimeInterval) -> ViewNode {
        guard !displacements.isEmpty || !entrances.isEmpty || !exits.isEmpty else { return root }
        return present(root, parentTarget: .zero, parentPresented: .zero, at: time)
    }

    private func present(
        _ node: ViewNode, parentTarget: CGPoint, parentPresented: CGPoint, at time: TimeInterval
    ) -> ViewNode {
        guard let frame = node.frame else { return node }
        var node = node
        // Adding the parent's displacement last keeps the frame exact when
        // the parent is where it will end up, so a still subtree matches
        // the final tree.
        var origin = CGPoint(
            x: frame.minX + (parentPresented.x - parentTarget.x),
            y: frame.minY + (parentPresented.y - parentTarget.y))
        var size = frame.size
        var opacity = Self.opacity(of: node)
        if let displacement = displacements[node.id] {
            let remaining = 1 - displacement.animation.progress(at: time - displacement.start)
            origin.x += displacement.origin.x * remaining
            origin.y += displacement.origin.y * remaining
            // Text keeps its final size, so it does not wrap differently while
            // it moves.
            if node.kind != "Text", node.kind != "TextField" {
                size.width = max(size.width + displacement.size.width * remaining, 0)
                size.height = max(size.height + displacement.size.height * remaining, 0)
            }
            opacity += displacement.opacity * remaining
        }
        if let entrance = entrances[node.id] {
            let progress = entrance.animation.progress(at: time - entrance.start)
            origin.x += entrance.offset.width * (1 - progress)
            origin.y += entrance.offset.height * (1 - progress)
            opacity *= entrance.opacity + (1 - entrance.opacity) * min(max(progress, 0), 1)
        }
        let shift = CGSize(width: origin.x - frame.minX, height: origin.y - frame.minY)
        node.frame = CGRect(origin: origin, size: size)
        node.modifierFrames = node.modifierFrames.map {
            $0.offsetBy(dx: shift.width, dy: shift.height)
        }
        Self.setOpacity(opacity, of: &node)

        var children = node.children.map {
            present($0, parentTarget: frame.origin, parentPresented: origin, at: time)
        }
        for exit in exits.values.sorted(by: { $0.index < $1.index }) where exit.parent == node.id {
            let progress = exit.animation.progress(at: time - exit.start)
            var ghost = Self.translated(
                exit.node,
                by: CGSize(
                    width: origin.x + exit.offset.width * progress,
                    height: origin.y + exit.offset.height * progress))
            Self.setOpacity(
                Self.opacity(of: ghost)
                    * (1 - (1 - exit.opacity) * min(max(progress, 0), 1)), of: &ghost)
            let index = min(exit.index + (exit.isAbove ? 1 : 0), children.count)
            children.insert(ghost, at: index)
        }
        node.children = children
        return node
    }

    // MARK: - Helpers

    private static func relativeOrigin(_ frame: CGRect, in parent: ViewNode?) -> CGPoint {
        let parentOrigin = parent?.frame?.origin ?? .zero
        return CGPoint(x: frame.minX - parentOrigin.x, y: frame.minY - parentOrigin.y)
    }

    private static func opacity(of node: ViewNode) -> Double {
        node.opacity
    }

    private static func setOpacity(_ opacity: Double, of node: inout ViewNode) {
        let clamped = min(max(opacity, 0), 1)
        node.attributes["opacity"] = clamped >= 0.9995 ? nil : String(format: "%.3f", clamped)
    }

    /// The node and its descendants moved by an offset.
    private static func translated(_ node: ViewNode, by offset: CGSize) -> ViewNode {
        var node = node
        node.frame = node.frame?.offsetBy(dx: offset.width, dy: offset.height)
        node.modifierFrames = node.modifierFrames.map {
            $0.offsetBy(dx: offset.width, dy: offset.height)
        }
        node.children = node.children.map { translated($0, by: offset) }
        return node
    }
}

extension ViewNode {
    /// The node's own opacity, from its `opacity` attribute.
    var opacity: Double {
        attributes["opacity"].flatMap(Double.init) ?? 1
    }
}
