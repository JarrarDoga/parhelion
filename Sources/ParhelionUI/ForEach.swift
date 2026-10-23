/// A view that creates views from a collection of data, mirroring SwiftUI's
/// `ForEach`.
///
/// Each element's view is identified by the element's ID, not its position,
/// so a row keeps its state when other rows are inserted or removed before
/// it.
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    public typealias Body = Never

    public var data: Data
    public var content: (Data.Element) -> Content
    let id: KeyPath<Data.Element, ID>

    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.id = id
        self.content = content
    }

    public var body: Never {
        fatalError("ForEach is a primitive view and has no body.")
    }
}

extension ForEach where Data == Range<Int>, ID == Int {
    /// Creates views for a constant range of integers.
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.init(data, id: \.self, content: content)
    }
}

extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    /// Creates views for identifiable data.
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}

extension ForEach {
    /// Creates views for a binding to a collection of identifiable data.
    /// Each view receives a binding to its element, so that
    /// `ForEach($items) { $item in ... }` can change the elements.
    @_disfavoredOverload
    public init<C>(
        _ data: Binding<C>,
        @ViewBuilder content: @escaping (Binding<C.Element>) -> Content
    )
    where
        Data == LazyMapSequence<C.Indices, (C.Index, ID)>, ID == C.Element.ID,
        C: MutableCollection, C: RandomAccessCollection, C.Element: Identifiable,
        C.Index: Hashable
    {
        self.init(data, id: \.id, content: content)
    }

    /// Creates views for a binding to a collection, identified by the
    /// element property at `id`. Each view receives a binding to its element.
    @_disfavoredOverload
    public init<C>(
        _ data: Binding<C>,
        id: KeyPath<C.Element, ID>,
        @ViewBuilder content: @escaping (Binding<C.Element>) -> Content
    )
    where
        Data == LazyMapSequence<C.Indices, (C.Index, ID)>, C: MutableCollection,
        C: RandomAccessCollection, C.Index: Hashable
    {
        let collection = data.wrappedValue
        let elements = collection.indices.lazy.map { index in
            (index, collection[index][keyPath: id])
        }
        self.init(elements, id: \.1) { element in
            content(data.element(at: element.0) { AnyHashable($0[keyPath: id]) })
        }
    }
}

extension ForEach: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        data.flatMap { element in
            let elementID = element[keyPath: id]
            let identity = String(describing: elementID)
            let nodes = evaluator.evaluate(
                content(element), at: path.appending("ForEach[\(identity)]"))
            // In a container that chooses among tagged views, such as a
            // Picker, an element's views are tagged with its identifier.
            evaluator.environment.tagCollector?.recordImplicit(elementID, for: nodes)
            return nodes
        }
    }
}
