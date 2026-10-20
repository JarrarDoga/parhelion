/// The horizontal or vertical dimension in a 2D coordinate system.
public enum Axis: Int8, CaseIterable, Sendable {
    case horizontal, vertical

    /// A set of axes.
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8

        public init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        public static let horizontal = Set(rawValue: 1 << 0)
        public static let vertical = Set(rawValue: 1 << 1)
    }
}

/// A scrollable view, mirroring SwiftUI's `ScrollView`.
///
/// The content is laid out at its ideal size along the scrollable axes and
/// clipped to the scroll view's bounds. Several content views stack along the
/// scroll axis, as in SwiftUI. Scroll by dragging, with the mouse wheel or
/// trackpad, or with ``ViewHost/scroll(by:at:)``.
public struct ScrollView<Content: View>: View {
    public typealias Body = Never

    public var axes: Axis.Set
    public var showsIndicators: Bool
    public var content: Content

    public init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    public var body: Never {
        fatalError("ScrollView is a primitive view and has no body.")
    }
}

extension ScrollView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("ScrollView")
        let axesName =
            switch (axes.contains(.horizontal), axes.contains(.vertical)) {
            case (true, true): "both"
            case (true, false): "horizontal"
            case (false, true): "vertical"
            case (false, false): "none"
            }
        return [
            ViewNode(
                id: ownPath.id,
                kind: "ScrollView",
                attributes: ["axes": axesName],
                children: evaluator.evaluate(content, at: ownPath)
            )
        ]
    }
}
