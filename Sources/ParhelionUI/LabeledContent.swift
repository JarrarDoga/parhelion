#if canImport(Foundation)
import Foundation
#endif

/// A label next to a value or another view, mirroring SwiftUI's
/// `LabeledContent`.
///
/// The label sits at the leading edge and the content at the trailing edge
/// of the width the view is offered, as in a settings row. Content that sets
/// no foreground style is secondary. The node's first child is the label;
/// several label views are stacked in a `VStack`.
public struct LabeledContent<Label: View, Content: View>: View {
    public typealias Body = Never

    let label: Label
    let content: Content

    /// Creates labeled content from a content view and a label view.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }

    public var body: Never {
        fatalError("LabeledContent is a primitive view and has no body.")
    }
}

extension LabeledContent where Label == Text {
    /// Creates labeled content with a text label.
    public init(_ title: some StringProtocol, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(title) }
    }
}

extension LabeledContent where Label == Text, Content == Text {
    /// Creates a text label next to a text value.
    public init(_ title: some StringProtocol, value: some StringProtocol) {
        self.init(content: { Text(value) }, label: { Text(title) })
    }
}

extension LabeledContent: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("LabeledContent")
        let labelPath = ownPath.appending("label")
        let labelNodes = evaluator.evaluate(label, at: labelPath)
        let labelNode =
            labelNodes.count == 1
            ? labelNodes[0]
            : ViewNode(
                id: labelPath.appending("VStack").id, kind: "VStack",
                attributes: ["alignment": "leading", "spacing": "0"], children: labelNodes)
        let contentNodes = evaluator.evaluate(content, at: ownPath).map { node in
            var node = node
            if node.attributes["foregroundStyle"] == nil {
                node.attributes["foregroundStyle"] = "secondary"
            }
            return node
        }
        return [
            ViewNode(id: ownPath.id, kind: "LabeledContent", children: [labelNode] + contentNodes)
        ]
    }
}

/// A thin line that separates content, mirroring SwiftUI's `Divider`.
///
/// In a horizontal stack it is a vertical line as tall as it is offered;
/// elsewhere it is a horizontal line as wide as it is offered.
public struct Divider: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("Divider is a primitive view and has no body.")
    }
}

extension Divider: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        [ViewNode(id: path.appending("Divider").id, kind: "Divider")]
    }
}

/// A container for grouped controls, such as a settings screen, mirroring
/// SwiftUI's `Form`.
///
/// On iOS a form is an inset grouped list, so its node is a `List`, and its
/// content's views become rows and sections as in a list.
public struct Form<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        List { content }
    }
}
