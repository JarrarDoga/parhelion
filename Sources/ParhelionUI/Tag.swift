#if canImport(Foundation)
import Foundation
#endif

extension View {
    /// Sets a value that identifies the view among the choices of a
    /// container, such as the option of a ``Picker`` that the view stands
    /// for. The node records the value as a `tag` attribute.
    ///
    /// With `includeOptional`, the tag also matches a selection of the
    /// optional type, such as a `Picker` whose selection is `Flavor?` with
    /// tags of type `Flavor`. When a view has several tags, the outermost one
    /// wins.
    public func tag<V: Hashable>(_ tag: V, includeOptional: Bool = true) -> some View {
        TagView(content: self, tag: Tag(value: tag, includeOptional: includeOptional))
    }
}

/// A value set with ``View/tag(_:includeOptional:)``, or the identifier of
/// the `ForEach` element a view came from.
struct Tag {
    let value: AnyHashable
    /// The static type of the value, which a selection of the same type
    /// matches exactly.
    let type: Any.Type
    let includeOptional: Bool

    init<V: Hashable>(value: V, includeOptional: Bool) {
        self.value = AnyHashable(value)
        type = V.self
        self.includeOptional = includeOptional
    }

    /// The value as a selection of type `T`: the value itself when `T` is
    /// its type, or wrapped in an optional when `T` is its optional type and
    /// the tag includes optionals.
    func value<T>(as _: T.Type) -> T? {
        guard type == T.self || includeOptional else { return nil }
        return value.base as? T
    }
}

/// The tags of the views a container evaluates, such as the options of a
/// `Picker` or the tabs of a `TabView`, by node identifier.
@MainActor
final class TagCollector {
    private var explicit: [NodeID: Tag] = [:]
    private var implicit: [NodeID: Tag] = [:]

    func record(_ tag: Tag, for nodes: [ViewNode]) {
        for node in nodes { explicit[node.id] = tag }
    }

    /// Records the identifier of a `ForEach` element as the tag of the
    /// element's views. A tag set with `tag(_:)` takes precedence.
    func recordImplicit<ID: Hashable>(_ id: ID, for nodes: [ViewNode]) {
        let tag = Tag(value: id, includeOptional: true)
        for node in nodes { implicit[node.id] = tag }
    }

    /// The tag of the node with the given identifier as a selection of type
    /// `T`, or `nil` if the node has no tag of that type.
    func tag<T>(of id: NodeID, as type: T.Type = T.self) -> T? {
        (explicit[id] ?? implicit[id])?.value(as: type)
    }
}

struct TagCollectorKey: EnvironmentKey {
    static var defaultValue: TagCollector? { nil }
}

extension EnvironmentValues {
    /// Where tagged views record their tags while a container evaluates its
    /// content.
    var tagCollector: TagCollector? {
        get { self[TagCollectorKey.self] }
        set { self[TagCollectorKey.self] = newValue }
    }
}

extension Evaluator {
    /// Evaluates the content of a container that chooses among tagged views,
    /// such as a `Picker` or a `TabView`, and returns the content's nodes with
    /// the tags of its views. Tags inside a tagged view belong to that view,
    /// not to the container.
    func evaluateTagged(
        _ content: some View, at path: ViewPath
    ) -> (nodes: [ViewNode], tags: TagCollector) {
        let tags = TagCollector()
        let nodes = withEnvironment({ $0.tagCollector = tags }) {
            evaluate(content, at: path)
        }
        return (nodes, tags)
    }
}

/// A view with a tag, produced by ``View/tag(_:includeOptional:)``.
struct TagView<Content: View>: View {
    typealias Body = Never

    let content: Content
    let tag: Tag

    var body: Never {
        fatalError("TagView is a primitive view and has no body.")
    }
}

extension TagView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let collector = evaluator.environment.tagCollector
        let nodes = evaluator.withEnvironment({ $0.tagCollector = nil }) {
            evaluator.evaluate(content, at: path)
        }
        collector?.record(tag, for: nodes)
        return nodes.map { node in
            var node = node
            node.attributes["tag"] = String(describing: tag.value.base)
            return node
        }
    }
}
