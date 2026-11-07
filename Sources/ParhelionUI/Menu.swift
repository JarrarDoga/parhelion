/// A compile-only stub: a menu that shows only its label. Issue #58 opens
/// the content when the label is tapped.
public struct Menu<Label: View, Content: View>: View {
    let label: Label
    let content: Content

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.content = content()
        self.label = label()
    }

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label,
        primaryAction: @escaping @MainActor () -> Void
    ) {
        self.content = content()
        self.label = label()
    }

    public var body: some View { label }
}

extension Menu where Label == Text {
    public init(_ title: some StringProtocol, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.label = Text(title)
    }
}

extension Menu where Label == ParhelionUI.Label<Text, Image> {
    public init(
        _ title: some StringProtocol, systemImage: String, @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.label = ParhelionUI.Label(title, systemImage: systemImage)
    }
}
