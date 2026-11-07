/// A compile-only stub: a progress view that draws its label and nothing
/// else. Issue #77 draws the spinner and the bar.
public struct ProgressView<Label: View, CurrentValueLabel: View>: View {
    let label: Label

    public var body: some View { label }
}

extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
    public init() {
        label = EmptyView()
    }

    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) {
        label = EmptyView()
    }
}

extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    public init(_ title: some StringProtocol) {
        label = Text(title)
    }

    public init<V: BinaryFloatingPoint>(
        _ title: some StringProtocol, value: V?, total: V = 1.0
    ) {
        label = Text(title)
    }
}

extension ProgressView where CurrentValueLabel == EmptyView {
    public init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }

    public init<V: BinaryFloatingPoint>(
        value: V?, total: V = 1.0, @ViewBuilder label: () -> Label
    ) {
        self.label = label()
    }
}

extension ProgressView {
    public init<V: BinaryFloatingPoint>(
        value: V?, total: V = 1.0, @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) {
        self.label = label()
    }
}
