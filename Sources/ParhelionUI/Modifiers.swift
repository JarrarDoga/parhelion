#if canImport(Foundation)
import Foundation
#endif

/// A view with a modifier applied, produced by modifier methods such as
/// ``View/padding(_:_:)``.
///
/// The modifier is recorded as an attribute on each node its content
/// resolves to. The content keeps its structural position, so applying a
/// modifier does not reset state.
struct ModifiedContent<Content: View>: View {
    typealias Body = Never

    let content: Content
    let key: String
    let value: String

    var body: Never {
        fatalError("ModifiedContent is a primitive view and has no body.")
    }
}

extension ModifiedContent: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.evaluate(content, at: path).map { node in
            var node = node
            node.attributes[key] = value
            return node
        }
    }
}

extension View {
    func modifier(_ key: String, _ value: String) -> some View {
        ModifiedContent(content: self, key: key, value: value)
    }
}

// MARK: - Layout

/// A set of edges of a rectangle.
public struct Edge: Sendable {
    public struct Set: OptionSet, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let top = Set(rawValue: 1 << 0)
        public static let leading = Set(rawValue: 1 << 1)
        public static let bottom = Set(rawValue: 1 << 2)
        public static let trailing = Set(rawValue: 1 << 3)
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
        public static let all: Set = [.horizontal, .vertical]

        var name: String {
            switch self {
            case .all: return "all"
            case .horizontal: return "horizontal"
            case .vertical: return "vertical"
            default:
                let names: [(Set, String)] = [
                    (.top, "top"), (.leading, "leading"), (.bottom, "bottom"),
                    (.trailing, "trailing"),
                ]
                return names.filter { contains($0.0) }.map(\.1).joined(separator: ",")
            }
        }
    }
}

extension View {
    /// Adds padding to the given edges. A `nil` length uses the platform
    /// default.
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        let value = length.map { "\(edges.name) \(formatLength($0))" } ?? edges.name
        return modifier("padding", value)
    }

    /// Adds the same padding to every edge.
    public func padding(_ length: CGFloat) -> some View {
        padding(.all, length)
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
        modifier("foregroundStyle", style.styleName)
    }

    /// Sets the relative size of symbol images.
    public func imageScale(_ scale: Image.Scale) -> some View {
        modifier("imageScale", scale.rawValue)
    }
}
