/// A view that the evaluator resolves to nodes directly instead of through
/// `body`.
@MainActor
protocol PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode]
}

/// The structural position of a view in the tree.
struct ViewPath: Hashable {
    private(set) var components: [String] = []

    func appending(_ component: String) -> ViewPath {
        var copy = self
        copy.components.append(component)
        return copy
    }

    var id: NodeID { NodeID(components.joined(separator: "/")) }
}

/// The base name of a type, without generic arguments: `VStack`, not
/// `VStack<TupleView<(Text, Text)>>`.
func baseTypeName(of type: Any.Type) -> String {
    let name = String(describing: type)
    return String(name.prefix { $0 != "<" })
}

/// Resolves a view hierarchy into a tree of ``ViewNode`` values in one pass.
@MainActor
final class Evaluator {
    let host: ViewHost
    /// The innermost navigation stack being evaluated, if any.
    var navigation: NavigationContext?
    /// The environment of the view being evaluated.
    var environment = EnvironmentValues()
    /// Sheets and alerts that views asked to present, in the order they
    /// asked. The host evaluates their content after the main tree.
    private(set) var presentations: [Presentation] = []
    /// Animations from `animation(_:value:)` modifiers whose value changed,
    /// by the identifiers of the nodes they cover.
    var implicitAnimations: [NodeID: Animation?] = [:]
    /// Transitions from `transition(_:)` modifiers, by node identifier.
    var transitions: [NodeID: AnyTransition] = [:]
    /// The detents declared inside the sheet being evaluated.
    var presentationDetents: Set<PresentationDetent> = []
    /// The grabber visibility declared inside the sheet being evaluated.
    var presentationDragIndicator = Visibility.automatic
    private(set) var actions: [NodeID: @MainActor () -> Void] = [:]
    private(set) var textFields: [NodeID: Binding<String>] = [:]
    /// The lifecycle modifiers evaluated, for the host to act on.
    let lifecycle = LifecycleRecord()

    init(host: ViewHost) {
        self.host = host
    }

    func evaluate(_ view: any View, at path: ViewPath) -> [ViewNode] {
        if let primitive = view as? any PrimitiveView {
            return primitive.makeNodes(in: self, at: path)
        }
        let ownPath = path.appending(baseTypeName(of: type(of: view)))
        installDynamicProperties(of: view, at: ownPath)
        return evaluate(body(of: view), at: ownPath)
    }

    func registerAction(_ action: @escaping @MainActor () -> Void, for id: NodeID) {
        actions[id] = action
    }

    func registerTextField(_ text: Binding<String>, for id: NodeID) {
        textFields[id] = text
    }

    func registerPresentation(_ presentation: Presentation) {
        presentations.append(presentation)
    }

    /// Runs `extra` after the action registered for `id`, if any.
    func appendToAction(for id: NodeID, _ extra: @escaping @MainActor () -> Void) {
        guard let action = actions[id] else { return }
        actions[id] = {
            action()
            extra()
        }
    }

    /// Evaluates `body` with a changed environment.
    func withEnvironment<Result>(
        _ transform: (inout EnvironmentValues) -> Void, _ body: () -> Result
    ) -> Result {
        let outer = environment
        transform(&environment)
        defer { environment = outer }
        return body()
    }

    private func body<V: View>(of view: V) -> any View {
        view.body
    }

    /// Installs the dynamic properties of a view, or of an app, whose own
    /// path is `path`.
    func installDynamicProperties(of value: Any, at path: ViewPath) {
        for child in Mirror(reflecting: value).children {
            if let property = child.value as? any EnvironmentInstallable {
                property.install(environment)
                continue
            }
            guard let label = child.label, let property = child.value as? any StateInstallable
            else { continue }
            property.install(in: host, key: "\(path.id.rawValue).\(label)")
        }
    }
}

extension EmptyView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        []
    }
}

extension TupleView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        elements.enumerated().flatMap { index, element in
            evaluator.evaluate(element, at: path.appending(String(index)))
        }
    }
}

extension _ConditionalContent: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        switch storage {
        case .trueContent(let content):
            evaluator.evaluate(content, at: path.appending("if"))
        case .falseContent(let content):
            evaluator.evaluate(content, at: path.appending("else"))
        }
    }
}

extension Optional: PrimitiveView where Wrapped: View {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        switch self {
        case .some(let content): evaluator.evaluate(content, at: path.appending("if"))
        case .none: []
        }
    }
}
