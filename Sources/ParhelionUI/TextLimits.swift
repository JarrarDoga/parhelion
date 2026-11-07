extension Text {
    /// Where a text view cuts off its text, mirroring SwiftUI's
    /// `Text.TruncationMode`.
    public enum TruncationMode: Sendable {
        case head
        case tail
        case middle
    }
}

extension TextField {
    /// Creates a text field that can grow along an axis. A compile-only
    /// stub: it still has one line. Issue #80 adds more.
    public init(_ title: some StringProtocol, text: Binding<String>, axis: Axis) {
        self.init(title, text: text)
    }
}

extension View {
    /// A compile-only stub: no limit applies. Issue #80 applies it.
    public func lineLimit(_ number: Int?) -> some View {
        self
    }

    public func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View {
        self
    }

    public func lineLimit(_ limit: ClosedRange<Int>) -> some View {
        self
    }

    public func lineLimit(_ limit: Int, reservesSpace: Bool) -> some View {
        self
    }

    /// A compile-only stub: text cuts off as before. Issue #80 applies it.
    public func truncationMode(_ mode: Text.TruncationMode) -> some View {
        self
    }
}
