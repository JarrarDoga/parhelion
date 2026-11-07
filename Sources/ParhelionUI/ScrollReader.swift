/// A compile-only stub: a proxy whose `scrollTo` does nothing. Issue #60
/// scrolls.
public struct ScrollViewProxy {
    init() {}

    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {}
}

/// A compile-only stub: a view that gives its content a proxy that does
/// nothing. Issue #60 scrolls.
public struct ScrollViewReader<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) {
        self.content = content(ScrollViewProxy())
    }

    public var body: some View { content }
}

extension View {
    /// A compile-only stub that does not give the view an identity. Issue
    /// #60 does.
    public func id<ID: Hashable>(_ id: ID) -> some View {
        self
    }
}
