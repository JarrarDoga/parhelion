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

extension ForEach: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        data.flatMap { element in
            let identity = String(describing: element[keyPath: id])
            return evaluator.evaluate(content(element), at: path.appending("ForEach[\(identity)]"))
        }
    }
}
