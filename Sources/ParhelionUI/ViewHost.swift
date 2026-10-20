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
    private var storage: [String: AnyObject] = [:]
    private var visitedKeys: Set<String> = []
    private var actions: [NodeID: @MainActor () -> Void] = [:]

    /// Whether a state change is waiting for the next ``update()``.
    public private(set) var needsUpdate = false

    /// The resolved and laid-out tree. Its root node has kind `"Root"` and
    /// covers the whole screen.
    public private(set) var root = ViewNode(id: "", kind: "Root")

    /// The device the tree is laid out for.
    public let device: Device

    public init(_ rootView: some View, device: Device = .iPhone16) {
        self.rootView = rootView
        self.device = device
        self.layoutEngine = LayoutEngine(device: device)
        evaluate()
    }

    init(anyRootView rootView: any View, device: Device = .iPhone16) {
        self.rootView = rootView
        self.device = device
        self.layoutEngine = LayoutEngine(device: device)
        evaluate()
    }

    /// Resolves the tree again if any state changed since the last update.
    public func update() {
        guard needsUpdate else { return }
        evaluate()
    }

    /// Taps the node with the given identifier, then updates the tree.
    public func tap(_ id: NodeID) throws(InteractionError) {
        guard root.node(withID: id) != nil else { throw .nodeNotFound(id) }
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
        guard let target = frontmostTappableNode(at: point, in: root) else {
            throw .nothingTappable(at: point)
        }
        try tap(target.id)
    }

    /// Taps the one button whose label is exactly `label`.
    public func tapButton(labeled label: String) throws(InteractionError) {
        let matches = root.allNodes.filter { $0.kind == "Button" && $0.label == label }
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

    private func frontmostTappableNode(at point: CGPoint, in node: ViewNode) -> ViewNode? {
        guard let frame = node.frame, frame.contains(point) else { return nil }
        for child in node.children.reversed() {
            if let match = frontmostTappableNode(at: point, in: child) { return match }
        }
        return actions[node.id] != nil ? node : nil
    }

    func setNeedsUpdate() {
        needsUpdate = true
    }

    func stateBox<Value>(forKey key: String, initialValue: Value) -> StateBox<Value> {
        visitedKeys.insert(key)
        if let box = storage[key] as? StateBox<Value> {
            return box
        }
        let box = StateBox(initialValue)
        box.host = self
        storage[key] = box
        return box
    }

    private func evaluate() {
        needsUpdate = false
        visitedKeys = []
        let evaluator = Evaluator(host: self)
        let children = evaluator.evaluate(rootView, at: ViewPath())
        root = layoutEngine.layout(ViewNode(id: "", kind: "Root", children: children))
        actions = evaluator.actions
        // State belongs to a structural position. When a view leaves the
        // tree, its state goes with it.
        storage = storage.filter { visitedKeys.contains($0.key) }
    }
}
