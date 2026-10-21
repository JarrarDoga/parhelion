#if canImport(Foundation)
import Foundation
#endif

/// A view with a modifier applied, produced by modifier methods such as
/// ``View/padding(_:_:)``.
///
/// The modifier is recorded on each node its content resolves to. The content
/// keeps its structural position, so applying a modifier does not reset state.
struct ModifiedContent<Content: View>: View {
    typealias Body = Never

    enum Change {
        /// A style value, recorded in ``ViewNode/attributes``.
        case attribute(key: String, value: String)
        /// A layout change, appended to ``ViewNode/modifiers``.
        case layout(LayoutModifier)
        /// An opacity, multiplied into the `opacity` attribute.
        case opacity(Double)
    }

    let content: Content
    let change: Change

    var body: Never {
        fatalError("ModifiedContent is a primitive view and has no body.")
    }
}

extension ModifiedContent: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.evaluate(content, at: path).map { node in
            var node = node
            switch change {
            case .attribute(let key, let value): node.attributes[key] = value
            case .layout(let modifier): node.modifiers.append(modifier)
            case .opacity(let opacity):
                let combined = node.opacity * opacity
                node.attributes["opacity"] = formatPoints(CGFloat(combined))
            }
            return node
        }
    }
}

extension View {
    func attributeModifier(_ key: String, _ value: String) -> some View {
        ModifiedContent(content: self, change: .attribute(key: key, value: value))
    }

    func layoutModifier(_ modifier: LayoutModifier) -> some View {
        ModifiedContent(content: self, change: .layout(modifier))
    }
}

// MARK: - Edges

/// An edge of a rectangle.
public enum Edge: Int8, CaseIterable, Sendable {
    case top, leading, bottom, trailing

    /// A set of edges.
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8

        public init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        public init(_ edge: Edge) {
            self.init(rawValue: 1 << edge.rawValue)
        }

        public static let top = Set(.top)
        public static let leading = Set(.leading)
        public static let bottom = Set(.bottom)
        public static let trailing = Set(.trailing)
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
        public static let all: Set = [.horizontal, .vertical]
    }
}

// MARK: - Style

/// A color or pattern used to draw content.
public protocol ShapeStyle: Sendable {
    var styleName: String { get }
}

/// A color, mirroring SwiftUI's `Color`.
public struct Color: ShapeStyle, View, Hashable {
    public typealias Body = Never

    public let styleName: String

    nonisolated init(name: String) {
        styleName = name
    }

    /// A color from red, green, blue, and opacity components in `0...1`.
    public nonisolated init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        let components = [red, green, blue, opacity].map { String(format: "%.3g", $0) }
        styleName = "rgba(" + components.joined(separator: ",") + ")"
    }

    /// The same color with its opacity multiplied by `opacity`.
    public nonisolated func opacity(_ opacity: Double) -> Color {
        Color(name: "\(styleName)@\(String(format: "%g", min(max(opacity, 0), 1)))")
    }

    public var body: Never {
        fatalError("Color is a primitive view and has no body.")
    }
}

extension Color: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        [ViewNode(id: path.appending("Color").id, kind: "Color", attributes: ["color": styleName])]
    }
}

extension ShapeStyle where Self == Color {
    public static var red: Color { Color(name: "red") }
    public static var orange: Color { Color(name: "orange") }
    public static var yellow: Color { Color(name: "yellow") }
    public static var green: Color { Color(name: "green") }
    public static var mint: Color { Color(name: "mint") }
    public static var teal: Color { Color(name: "teal") }
    public static var cyan: Color { Color(name: "cyan") }
    public static var blue: Color { Color(name: "blue") }
    public static var indigo: Color { Color(name: "indigo") }
    public static var purple: Color { Color(name: "purple") }
    public static var pink: Color { Color(name: "pink") }
    public static var brown: Color { Color(name: "brown") }
    public static var white: Color { Color(name: "white") }
    public static var gray: Color { Color(name: "gray") }
    public static var black: Color { Color(name: "black") }
    public static var clear: Color { Color(name: "clear") }
    public static var accentColor: Color { Color(name: "accentColor") }
}

/// The app's tint color.
public struct TintShapeStyle: ShapeStyle {
    public var styleName: String { "tint" }

    public init() {}
}

extension ShapeStyle where Self == TintShapeStyle {
    public static var tint: TintShapeStyle { TintShapeStyle() }
}

/// A style relative to the current foreground style.
public struct HierarchicalShapeStyle: ShapeStyle {
    public let styleName: String

    public static let primary = HierarchicalShapeStyle(styleName: "primary")
    public static let secondary = HierarchicalShapeStyle(styleName: "secondary")
    public static let tertiary = HierarchicalShapeStyle(styleName: "tertiary")
    public static let quaternary = HierarchicalShapeStyle(styleName: "quaternary")
}

extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var primary: HierarchicalShapeStyle { .primary }
    public static var secondary: HierarchicalShapeStyle { .secondary }
    public static var tertiary: HierarchicalShapeStyle { .tertiary }
    public static var quaternary: HierarchicalShapeStyle { .quaternary }
}

extension View {
    /// Sets the style used to draw foreground content such as text and
    /// symbols.
    public func foregroundStyle(_ style: some ShapeStyle) -> some View {
        attributeModifier("foregroundStyle", style.styleName)
    }

    /// Sets the relative size of symbol images.
    public func imageScale(_ scale: Image.Scale) -> some View {
        attributeModifier("imageScale", scale.rawValue)
    }
}
