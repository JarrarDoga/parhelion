#if canImport(Foundation)
import Foundation
#endif

/// The horizontal alignment of children in a vertical stack.
public enum HorizontalAlignment: String, Sendable {
    case leading, center, trailing
}

/// The vertical alignment of children in a horizontal stack.
public enum VerticalAlignment: String, Sendable {
    case top, center, bottom
}

/// The alignment of children in an overlapping stack.
public struct Alignment: Equatable, Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment

    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)

    var name: String {
        switch (horizontal, vertical) {
        case (.center, .center): "center"
        case (.center, _): vertical.rawValue
        case (_, .center): horizontal.rawValue
        default:
            vertical.rawValue + horizontal.rawValue.prefix(1).uppercased()
                + horizontal.rawValue.dropFirst()
        }
    }
}

/// A view that arranges its children in a vertical line.
public struct VStack<Content: View>: View {
    public typealias Body = Never

    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content

    public init(
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: Never {
        fatalError("VStack is a primitive view and has no body.")
    }
}

/// A view that arranges its children in a horizontal line.
public struct HStack<Content: View>: View {
    public typealias Body = Never

    let alignment: VerticalAlignment
    let spacing: CGFloat?
    let content: Content

    public init(
        alignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: Never {
        fatalError("HStack is a primitive view and has no body.")
    }
}

/// A view that overlays its children.
public struct ZStack<Content: View>: View {
    public typealias Body = Never

    let alignment: Alignment
    let content: Content

    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    public var body: Never {
        fatalError("ZStack is a primitive view and has no body.")
    }
}

extension VStack: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        var attributes: [String: String] = [:]
        if alignment != .center { attributes["alignment"] = alignment.rawValue }
        if let spacing { attributes["spacing"] = formatLength(spacing) }
        return [makeStackNode("VStack", attributes, content, evaluator, path)]
    }
}

extension HStack: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        var attributes: [String: String] = [:]
        if alignment != .center { attributes["alignment"] = alignment.rawValue }
        if let spacing { attributes["spacing"] = formatLength(spacing) }
        return [makeStackNode("HStack", attributes, content, evaluator, path)]
    }
}

extension ZStack: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        var attributes: [String: String] = [:]
        if alignment != .center { attributes["alignment"] = alignment.name }
        return [makeStackNode("ZStack", attributes, content, evaluator, path)]
    }
}

@MainActor
private func makeStackNode(
    _ kind: String,
    _ attributes: [String: String],
    _ content: some View,
    _ evaluator: Evaluator,
    _ path: ViewPath
) -> ViewNode {
    let ownPath = path.appending(kind)
    return ViewNode(
        id: ownPath.id,
        kind: kind,
        attributes: attributes,
        children: evaluator.evaluate(content, at: ownPath)
    )
}
