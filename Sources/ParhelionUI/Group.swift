/// A view that collects views without changing their layout, mirroring
/// SwiftUI's `Group`.
///
/// A group adds no node of its own: its views take its place in the parent,
/// and a modifier applied to the group applies to each of them.
public struct Group<Content> {
    public typealias Body = Never

    let content: Content
}

extension Group: View where Content: View {
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never {
        fatalError("Group is a primitive view and has no body.")
    }
}

extension Group: PrimitiveView where Content: View {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.evaluate(content, at: path)
    }
}

/// A view of any type, mirroring SwiftUI's `AnyView`.
///
/// The wrapped view keeps its own identity: when an `AnyView` starts
/// wrapping a view of another type, the old view's state is discarded.
public struct AnyView: View {
    public typealias Body = Never

    let view: any View

    public init<V: View>(_ view: V) {
        self.view = view
    }

    public init<V: View>(erasing view: V) {
        self.init(view)
    }

    /// Wraps `value` if it is a view.
    public init?(_fromValue value: Any) {
        guard let view = value as? any View else { return nil }
        self.view = view
    }

    public var body: Never {
        fatalError("AnyView is a primitive view and has no body.")
    }
}

extension AnyView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.evaluate(view, at: path)
    }
}
