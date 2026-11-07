/// A horizontal edge, mirroring SwiftUI's `HorizontalEdge`.
public enum HorizontalEdge: Int8, CaseIterable, Hashable, Sendable {
    case leading
    case trailing
}

extension View {
    /// A compile-only stub that ignores the actions. Issue #57 draws them.
    public func swipeActions<T: View>(
        edge: HorizontalEdge = .trailing,
        allowsFullSwipe: Bool = true,
        @ViewBuilder content: () -> T
    ) -> some View {
        self
    }
}
