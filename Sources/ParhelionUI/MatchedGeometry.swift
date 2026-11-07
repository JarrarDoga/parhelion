#if canImport(Foundation)
import Foundation
#endif

/// Which geometry `matchedGeometryEffect` matches, mirroring SwiftUI's
/// `MatchedGeometryProperties`.
public struct MatchedGeometryProperties: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let position = MatchedGeometryProperties(rawValue: 1 << 0)
    public static let size = MatchedGeometryProperties(rawValue: 1 << 1)
    public static let frame: MatchedGeometryProperties = [.position, .size]
}

/// How a navigation push or a presentation animates, mirroring SwiftUI's
/// `NavigationTransition`.
public protocol NavigationTransition {}

public struct AutomaticNavigationTransition: NavigationTransition {
    public init() {}
}

public struct ZoomNavigationTransition: NavigationTransition {
    let sourceID: AnyHashable
    let namespace: Namespace.ID
}

// MARK: - Modifiers

/// How the matching modifiers appear in the tree. The tree holds the names
/// and the settings as data; `AnimationEngine` reads them back when a view
/// arrives or a presentation opens.
enum MatchedGeometry {
    static let effectName = "matchedGeometryEffect"
    static let sourceName = "matchedTransitionSource"
    static let zoomName = "navigationTransition.zoom"

    static let effectBehavior = ModifierBehavior(outline: { parameters in
        var text = "matchedGeometryEffect(id: \(parameters["id"] ?? ""), "
        text += "namespace: \(parameters["namespace"] ?? "")"
        if let properties = parameters["properties"], properties != "position,size" {
            text += ", properties: \(properties)"
        }
        if parameters["isSource"] == "false" { text += ", isSource: false" }
        return text + ")"
    })
    static let sourceBehavior = ModifierBehavior(outline: { parameters in
        "matchedTransitionSource(id: \(parameters["id"] ?? ""), namespace: \(parameters["namespace"] ?? ""))"
    })
    static let zoomBehavior = ModifierBehavior(outline: { parameters in
        "navigationTransition(.zoom(sourceID: \(parameters["id"] ?? ""), namespace: \(parameters["namespace"] ?? "")))"
    })

    /// What ties views together: a namespace and an identifier.
    struct Key: Hashable {
        var namespace: String
        var id: String

        init(namespace: String, id: String) {
            self.namespace = namespace
            self.id = id
        }

        init?(_ parameters: [String: String]) {
            guard let namespace = parameters["namespace"], let id = parameters["id"] else {
                return nil
            }
            self.init(namespace: namespace, id: id)
        }
    }

    static func description(of properties: MatchedGeometryProperties) -> String {
        var names: [String] = []
        if properties.contains(.position) { names.append("position") }
        if properties.contains(.size) { names.append("size") }
        return names.joined(separator: ",")
    }

    /// A view that carries one of the modifiers, with its settings and the
    /// rectangle the modifier wraps.
    struct Match {
        var key: Key
        var node: ViewNode
        var rect: CGRect
        var properties: MatchedGeometryProperties
        var anchor: CGPoint
        var isSource: Bool
    }

    /// The views in a tree that carry the modifier called `name`.
    static func collect(_ root: ViewNode, named name: String) -> [Match] {
        var matches: [Match] = []
        func visit(_ node: ViewNode) {
            for (index, modifier) in node.modifiers.enumerated() {
                guard case .custom(let custom) = modifier, custom.name == name,
                    let key = Key(custom.parameters)
                else { continue }
                let rect =
                    index < node.modifierFrames.count
                        && node.modifierFrames.count
                            == node.modifiers.count
                    ? node.modifierFrames[index] : node.frame
                guard let rect else { continue }
                let parts = (custom.parameters["properties"] ?? "").split(separator: ",")
                var properties: MatchedGeometryProperties = []
                if parts.contains("position") { properties.insert(.position) }
                if parts.contains("size") { properties.insert(.size) }
                let anchor = (custom.parameters["anchor"] ?? "0.5,0.5").split(separator: ",")
                    .compactMap { Double($0) }
                matches.append(
                    Match(
                        key: key, node: node, rect: rect, properties: properties,
                        anchor: anchor.count == 2
                            ? CGPoint(x: anchor[0], y: anchor[1]) : CGPoint(x: 0.5, y: 0.5),
                        isSource: custom.parameters["isSource"] != "false"))
            }
            node.children.forEach(visit)
        }
        visit(root)
        return matches
    }

    /// The first zoom transition in a node or below it, in drawing order.
    static func zoomKey(in node: ViewNode) -> Key? {
        for modifier in node.modifiers {
            if case .custom(let custom) = modifier, custom.name == zoomName {
                return Key(custom.parameters)
            }
        }
        for child in node.children {
            if let key = zoomKey(in: child) { return key }
        }
        return nil
    }

    /// The rectangle a view starts from, when it takes the place of
    /// `source`: the source's frame, or only its position or its size. The
    /// anchor stays where it will be.
    static func startRect(for match: Match, from source: Match) -> CGRect {
        let target = match.rect
        let properties = match.properties
        var size = target.size
        if properties.contains(.size) { size = source.rect.size }
        func point(_ rect: CGRect) -> CGPoint {
            CGPoint(
                x: rect.minX + rect.width * match.anchor.x,
                y: rect.minY + rect.height * match.anchor.y)
        }
        let anchorTarget =
            properties.contains(.position)
            ? point(source.rect)
            : point(target)
        return CGRect(
            x: anchorTarget.x - size.width * match.anchor.x,
            y: anchorTarget.y - size.height * match.anchor.y,
            width: size.width, height: size.height)
    }
}

/// A presentation or a pushed screen growing out of its source, or shrinking
/// back into it: its rectangle goes from the source's to its own.
struct Zoom {
    var animation: Animation
    var start: TimeInterval
    /// The source's rectangle in the screen.
    var source: CGRect
    /// Whether the view is leaving, back to the source.
    var isExit: Bool

    func progress(at time: TimeInterval) -> Double {
        animation.progress(at: time - start)
    }

    /// The rectangle at `time`, between two rectangles.
    func rect(from: CGRect, to: CGRect, at time: TimeInterval) -> CGRect {
        let p = CGFloat(progress(at: time))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        return CGRect(
            x: mix(from.minX, to.minX), y: mix(from.minY, to.minY),
            width: max(mix(from.width, to.width), 1), height: max(mix(from.height, to.height), 1))
    }

    /// The fade: the content comes in over the first third of the zoom and
    /// goes out over the last third.
    func opacity(at time: TimeInterval) -> Double {
        let p = min(max(progress(at: time), 0), 1)
        return isExit ? 1 - max((p - 0.6) / 0.4, 0) : min(p / 0.4, 1)
    }

    /// Draws `node`, laid out at its own size, in `rect`: the node keeps its
    /// size and gets a scale about its top leading corner, so that its
    /// content shrinks with it.
    static func scale(_ node: inout ViewNode, to rect: CGRect) {
        guard let frame = node.frame, frame.width > 0, frame.height > 0 else { return }
        node.frame = CGRect(origin: rect.origin, size: frame.size)
        if node.modifierFrames.count != node.modifiers.count {
            node.modifierFrames = Array(repeating: node.frame ?? .zero, count: node.modifiers.count)
        }
        node.modifiers.append(
            .scaleEffect(
                x: rect.width / frame.width, y: rect.height / frame.height, anchor: .zero))
        node.modifierFrames.append(node.frame ?? .zero)
    }
}

// MARK: - Animation

extension AnimationEngine {
    /// Starts the motion of views that match one another, after the engine
    /// has started the rest.
    ///
    /// - A view that arrives, with a `matchedGeometryEffect`, starts at the
    ///   frame of a view in the old tree with the same identifier and
    ///   namespace and moves to its own. That view, if it left, moves to
    ///   the new frame as it fades out.
    /// - A full-screen cover or pushed screen with a zoom transition grows
    ///   from the frame of its `matchedTransitionSource`, and shrinks into it
    ///   when it goes.
    func applyMatchedGeometry(
        old: ViewNode, new: ViewNode, oldIDs: Set<NodeID>, newIDs: Set<NodeID>,
        request: AnimationRequest, at time: TimeInterval
    ) {
        moveMatchedViews(
            old: old, new: new, oldIDs: oldIDs, newIDs: newIDs, request: request, at: time)
        zoomPresentations(old: old, new: new, oldIDs: oldIDs, request: request, at: time)
    }

    private func moveMatchedViews(
        old: ViewNode, new: ViewNode, oldIDs: Set<NodeID>, newIDs: Set<NodeID>,
        request: AnimationRequest, at time: TimeInterval
    ) {
        let name = MatchedGeometry.effectName
        let arriving = MatchedGeometry.collect(new, named: name)
        guard !arriving.isEmpty else { return }
        let before = Dictionary(grouping: MatchedGeometry.collect(old, named: name), by: \.key)
        guard !before.isEmpty else { return }

        var parents: [NodeID: NodeID] = [:]
        func index(_ node: ViewNode) {
            for child in node.children {
                parents[child.id] = node.id
                index(child)
            }
        }
        index(new)

        /// The animation of the change that brought the view in, from the
        /// nearest view that has one.
        func animation(for id: NodeID) -> Animation? {
            var current: NodeID? = id
            while let id = current {
                if let implicit = request.implicit[id] { return implicit }
                if let animation = entrances[id]?.animation { return animation }
                current = parents[id]
            }
            if let transaction = request.transaction { return transaction }
            return nil
        }

        /// How far the view's ancestors have moved it at the start.
        func inheritedShift(of id: NodeID) -> CGPoint {
            var shift = CGPoint.zero
            var current: NodeID? = id
            while let id = current {
                if let entrance = entrances[id] {
                    shift.x += entrance.offset.width
                    shift.y += entrance.offset.height
                }
                if let displacement = displacements[id] {
                    shift.x += displacement.origin.x
                    shift.y += displacement.origin.y
                }
                current = parents[id]
            }
            return shift
        }

        for match in arriving where !oldIDs.contains(match.node.id) && !match.properties.isEmpty {
            guard let candidates = before[match.key],
                let source =
                    candidates.first(where: { !newIDs.contains($0.node.id) && $0.isSource })
                    ?? candidates.first(where: { !newIDs.contains($0.node.id) })
                    ?? candidates.first(where: \.isSource) ?? candidates.first,
                let chosen = animation(for: match.node.id)
            else { continue }
            let start = MatchedGeometry.startRect(for: match, from: source)
            let inherited = inheritedShift(of: match.node.id)
            displacements[match.node.id] = Displacement(
                animation: chosen, start: time,
                origin: CGPoint(
                    x: start.minX - match.rect.minX - inherited.x,
                    y: start.minY - match.rect.minY - inherited.y),
                size: CGSize(
                    width: start.width - match.rect.width,
                    height: start.height - match.rect.height),
                opacity: 0)

            // The view it replaces slides to the new frame while it fades.
            if var exit = exits[source.node.id], exit.start == time {
                exit.offset = CGSize(
                    width: match.rect.minX - source.rect.minX,
                    height: match.rect.minY - source.rect.minY)
                exits[source.node.id] = exit
            }
        }
    }

    private func zoomPresentations(
        old: ViewNode, new: ViewNode, oldIDs: Set<NodeID>, request: AnimationRequest,
        at time: TimeInterval
    ) {
        let name = MatchedGeometry.sourceName
        let oldSources = Dictionary(
            MatchedGeometry.collect(old, named: name).map { ($0.key, $0.rect) },
            uniquingKeysWith: { first, _ in first })
        let newSources = Dictionary(
            MatchedGeometry.collect(new, named: name).map { ($0.key, $0.rect) },
            uniquingKeysWith: { first, _ in first })
        guard !oldSources.isEmpty || !newSources.isEmpty else { return }

        // Screens that arrive: a full-screen cover, or a screen pushed onto a
        // navigation stack.
        func zoomIn(_ node: ViewNode) {
            guard !oldIDs.contains(node.id), let entrance = entrances[node.id],
                let key = MatchedGeometry.zoomKey(in: node),
                let source = oldSources[key] ?? newSources[key]
            else { return }
            entrances[node.id] = nil
            zooms[node.id] = Zoom(
                animation: entrance.animation, start: time, source: source, isExit: false)
        }
        for child in new.children where child.kind == "FullScreenCover" { zoomIn(child) }
        for stack in new.allNodes where stack.kind == "NavigationStack" {
            guard request.navigation[stack.id] == .push else { continue }
            for child in stack.children where child.kind != "NavigationBar" { zoomIn(child) }
        }

        // Screens that leave shrink back into their source.
        for (id, exit) in exits where exit.start == time {
            guard exit.node.kind == "FullScreenCover" || exit.isAbove,
                let key = MatchedGeometry.zoomKey(in: exit.node),
                let source = newSources[key] ?? oldSources[key]
            else { continue }
            var zoomed = exit
            zoomed.offset = .zero
            exits[id] = zoomed
            zooms[id] = Zoom(
                animation: exit.animation, start: time, source: source, isExit: true)
        }
    }
}

extension NavigationTransition where Self == AutomaticNavigationTransition {
    public static var automatic: AutomaticNavigationTransition {
        AutomaticNavigationTransition()
    }
}

extension NavigationTransition where Self == ZoomNavigationTransition {
    public static func zoom(
        sourceID: some Hashable, in namespace: Namespace.ID
    ) -> ZoomNavigationTransition {
        ZoomNavigationTransition(sourceID: AnyHashable(sourceID), namespace: namespace)
    }
}

extension View {
    /// Matches this view's frame with the views that share its identifier and
    /// namespace. When a view with the identifier arrives in an animation, it
    /// starts at the frame of the view in the namespace that was on screen,
    /// and moves to its own.
    public func matchedGeometryEffect<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID,
        properties: MatchedGeometryProperties = .frame,
        anchor: UnitPoint = .center,
        isSource: Bool = true
    ) -> some View {
        customModifier(
            MatchedGeometry.effectName,
            [
                "id": "\(id)", "namespace": "\(namespace.value)",
                "properties": MatchedGeometry.description(of: properties),
                "anchor": "\(anchor.x),\(anchor.y)",
                "isSource": isSource ? "true" : "false",
            ], behavior: MatchedGeometry.effectBehavior)
    }

    /// Marks this view as the source that a zoom transition grows out of.
    public func matchedTransitionSource<ID: Hashable>(
        id: ID, in namespace: Namespace.ID
    ) -> some View {
        customModifier(
            MatchedGeometry.sourceName,
            ["id": "\(id)", "namespace": "\(namespace.value)"],
            behavior: MatchedGeometry.sourceBehavior)
    }

    /// Sets how a navigation push or a presentation animates. With
    /// `.zoom(sourceID:in:)`, the view grows out of the frame of the
    /// `matchedTransitionSource` and shrinks back into it. Apply it to the
    /// content of a `fullScreenCover` or to a pushed screen.
    @ViewBuilder
    public func navigationTransition(_ style: some NavigationTransition) -> some View {
        if let zoom = style as? ZoomNavigationTransition {
            customModifier(
                MatchedGeometry.zoomName,
                ["id": "\(zoom.sourceID)", "namespace": "\(zoom.namespace.value)"],
                behavior: MatchedGeometry.zoomBehavior)
        } else {
            self
        }
    }
}
