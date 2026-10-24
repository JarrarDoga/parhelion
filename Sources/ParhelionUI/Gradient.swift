#if canImport(Foundation)
import Foundation
#endif

// Styles in the tree.
//
// Nodes are plain data, so a `ShapeStyle` records itself as its `styleName`,
// a string. A color is its name: `blue`, `tint`, `secondary`,
// `rgba(1,0.5,0,1)`, or `red@0.5` for a color with its opacity multiplied by
// 0.5. A linear gradient is
//
//     linearGradient(<color> <location>, ..., <color> <location>, <start>, <end>)
//
// with one color and location in `0...1` for each stop, in order, and the
// start and end unit points last. A point is the name of a `UnitPoint`
// constant, such as `top` or `bottomTrailing`, or its coordinates, such as
// `0.25 0.75`. So `LinearGradient(colors: [.blue, .purple], startPoint:
// .top, endPoint: .bottom)` is `linearGradient(blue 0, purple 1, top,
// bottom)`.
//
// `StyleDescription(_:)` reads either form back. The renderer resolves each
// color of a gradient as it resolves any other color, so the tint, opacity,
// and appearance apply to gradients too.

/// A normalized 2D point in a view's coordinate space, mirroring SwiftUI's
/// `UnitPoint`: `(0, 0)` is the top-leading corner and `(1, 1)` the
/// bottom-trailing one.
public struct UnitPoint: Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init() {
        self.init(x: 0, y: 0)
    }

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public static let zero = UnitPoint(x: 0, y: 0)
    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let leading = UnitPoint(x: 0, y: 0.5)
    public static let trailing = UnitPoint(x: 1, y: 0.5)
    public static let top = UnitPoint(x: 0.5, y: 0)
    public static let bottom = UnitPoint(x: 0.5, y: 1)
    public static let topLeading = UnitPoint(x: 0, y: 0)
    public static let topTrailing = UnitPoint(x: 1, y: 0)
    public static let bottomLeading = UnitPoint(x: 0, y: 1)
    public static let bottomTrailing = UnitPoint(x: 1, y: 1)

    /// The named points, by the name the tree records for them.
    static let named: [(name: String, point: UnitPoint)] = [
        ("center", .center), ("leading", .leading), ("trailing", .trailing), ("top", .top),
        ("bottom", .bottom), ("topLeading", .topLeading), ("topTrailing", .topTrailing),
        ("bottomLeading", .bottomLeading), ("bottomTrailing", .bottomTrailing),
    ]

    /// The point as the tree records it: a constant's name, or `x y`.
    var name: String {
        if let match = Self.named.first(where: { $0.point == self }) { return match.name }
        return "\(formatUnit(x)) \(formatUnit(y))"
    }

    /// The point a recorded name stands for.
    init?(name: some StringProtocol) {
        if let match = Self.named.first(where: { $0.name == name }) {
            self = match.point
            return
        }
        let parts = name.split(separator: " ")
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else {
            return nil
        }
        self.init(x: CGFloat(x), y: CGFloat(y))
    }

    /// The point inside a rectangle that this unit point names.
    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }
}

/// A color gradient, mirroring SwiftUI's `Gradient`: colors at locations
/// from 0 to 1.
public struct Gradient: Hashable, Sendable {
    /// One color in a gradient, at a location from 0 to 1.
    public struct Stop: Hashable, Sendable {
        public var color: Color
        public var location: CGFloat

        public init(color: Color, location: CGFloat) {
            self.color = color
            self.location = location
        }
    }

    public var stops: [Stop]

    public init(stops: [Stop]) {
        self.stops = stops
    }

    /// A gradient through colors spaced evenly from 0 to 1.
    public init(colors: [Color]) {
        let last = max(colors.count - 1, 1)
        stops = colors.enumerated().map {
            Stop(color: $0.element, location: CGFloat($0.offset) / CGFloat(last))
        }
    }

    /// The stops as the tree records them: `blue 0, purple 1`.
    var stopsDescription: String {
        stops.map { "\($0.color.styleName) \(formatUnit($0.location))" }
            .joined(separator: ", ")
    }
}

/// A linear gradient, mirroring SwiftUI's `LinearGradient`. As a view it
/// fills the space it is offered; as a style it fills the bounds of each
/// shape it paints, mapping its unit points into them.
public struct LinearGradient: ShapeStyle, View {
    public typealias Body = Never

    let gradient: Gradient
    let startPoint: UnitPoint
    let endPoint: UnitPoint

    public nonisolated init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    public nonisolated init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }

    public nonisolated init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
    }

    public nonisolated var styleName: String {
        "linearGradient(\(gradient.stopsDescription), \(startPoint.name), \(endPoint.name))"
    }

    public var body: Never {
        fatalError("LinearGradient is a primitive view and has no body.")
    }
}

extension LinearGradient: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        [
            ViewNode(
                id: path.appending("LinearGradient").id, kind: "LinearGradient",
                attributes: [
                    "gradient": gradient.stopsDescription, "startPoint": startPoint.name,
                    "endPoint": endPoint.name,
                ])
        ]
    }
}

extension ShapeStyle where Self == LinearGradient {
    /// A linear gradient through a gradient's stops.
    public static func linearGradient(
        _ gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint
    ) -> LinearGradient {
        LinearGradient(gradient: gradient, startPoint: startPoint, endPoint: endPoint)
    }

    /// A linear gradient through colors spaced evenly.
    public static func linearGradient(
        colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint
    ) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
    }

    /// A linear gradient through stops.
    public static func linearGradient(
        stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint
    ) -> LinearGradient {
        LinearGradient(stops: stops, startPoint: startPoint, endPoint: endPoint)
    }
}

/// The style that draws foreground content, mirroring SwiftUI's
/// `ForegroundStyle`: the style a `foregroundStyle(_:)` set, primary by
/// default.
public struct ForegroundStyle: ShapeStyle {
    public var styleName: String { "foreground" }

    public init() {}
}

extension ShapeStyle where Self == ForegroundStyle {
    public static var foreground: ForegroundStyle { ForegroundStyle() }
}

/// A style read back from its description in the tree.
enum StyleDescription: Equatable {
    /// A color's name, such as `blue`, `tint`, or `rgba(1,0,0,1)`.
    case color(String)
    /// The style the content is drawn with, from `foregroundStyle(_:)`.
    case foreground
    case linearGradient(stops: [Stop], start: UnitPoint, end: UnitPoint)

    struct Stop: Equatable {
        var color: String
        var location: Double
    }

    init(_ name: String) {
        if name == "foreground" {
            self = .foreground
            return
        }
        let prefix = "linearGradient("
        guard name.hasPrefix(prefix), name.hasSuffix(")") else {
            self = .color(name)
            return
        }
        let parts = Self.topLevelParts(name.dropFirst(prefix.count).dropLast())
        guard parts.count >= 3, let start = UnitPoint(name: parts[parts.count - 2]),
            let end = UnitPoint(name: parts[parts.count - 1])
        else {
            self = .color(name)
            return
        }
        var stops: [Stop] = []
        for part in parts.dropLast(2) {
            guard let space = part.lastIndex(of: " "),
                let location = Double(part[part.index(after: space)...])
            else {
                self = .color(name)
                return
            }
            stops.append(Stop(color: String(part[..<space]), location: location))
        }
        self = .linearGradient(stops: stops, start: start, end: end)
    }

    /// The comma-separated parts of a list, without splitting inside
    /// parentheses, so that `rgba(1,0,0,1) 0` stays one part.
    private static func topLevelParts(_ list: Substring) -> [Substring] {
        var parts: [Substring] = []
        var depth = 0
        var start = list.startIndex
        for index in list.indices {
            switch list[index] {
            case "(": depth += 1
            case ")": depth -= 1
            case "," where depth == 0:
                parts.append(list[start..<index])
                start = list.index(after: index)
            default: break
            }
        }
        parts.append(list[start...])
        return parts.map { $0.drop { $0 == " " } }
    }
}

/// Formats a unit value with at most four decimal places: `0`, `0.5`,
/// `0.3333`.
func formatUnit(_ value: CGFloat) -> String {
    let rounded = (Double(value) * 10_000).rounded() / 10_000
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    var text = String(format: "%.4f", rounded)
    while text.hasSuffix("0") { text.removeLast() }
    return text
}
