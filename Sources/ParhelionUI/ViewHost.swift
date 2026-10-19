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
}

/// Owns a view hierarchy: resolves it to a ``ViewNode`` tree, keeps its state,
/// and delivers interactions to it.
///
/// `ViewHost` is the boundary that renderers, tests, and agents all use. It
/// works headlessly; nothing here depends on a window or a GPU.
///
/// ```swift
/// let host = ViewHost(CounterView())
/// try host.tapButton(labeled: "Increment")
/// print(host.root.outline())
/// ```
@MainActor
public final class ViewHost {
    private let rootView: any View
    private var storage: [String: AnyObject] = [:]
    private var visitedKeys: Set<String> = []
    private var actions: [NodeID: @MainActor () -> Void] = [:]

    /// Whether a state change is waiting for the next ``update()``.
    public private(set) var needsUpdate = false

    /// The resolved tree. Its root node has kind `"Root"`.
    public private(set) var root = ViewNode(id: "", kind: "Root")

    public init(_ rootView: some View) {
        self.rootView = rootView
        evaluate()
    }

    init(anyRootView rootView: any View) {
        self.rootView = rootView
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
        root = ViewNode(id: "", kind: "Root", children: children)
        actions = evaluator.actions
        // State belongs to a structural position. When a view leaves the
        // tree, its state goes with it.
        storage = storage.filter { visitedKeys.contains($0.key) }
    }
}
