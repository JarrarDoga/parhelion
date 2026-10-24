import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// The outline of a 2D shape, mirroring SwiftUI's `Path`. It is the path
/// type Parhelion's renderer fills, so `Path(roundedRect:cornerRadius:)`
/// without a style has circular corners, where SwiftUI's has continuous
/// ones; pass the style to get the same shape.
public typealias Path = ParhelionRender.Path

/// The shape of a rounded rectangle's corners, mirroring SwiftUI's
/// `RoundedCornerStyle`.
public typealias RoundedCornerStyle = Path.CornerStyle

/// A geometric angle, mirroring SwiftUI's `Angle`.
public struct Angle: Hashable, Comparable, Sendable {
    public var radians: Double

    public var degrees: Double {
        get { radians * 180 / .pi }
        set { radians = newValue * .pi / 180 }
    }

    public init() {
        radians = 0
    }

    public init(radians: Double) {
        self.radians = radians
    }

    public init(degrees: Double) {
        radians = degrees * .pi / 180
    }

    public static func radians(_ radians: Double) -> Angle { Angle(radians: radians) }
    public static func degrees(_ degrees: Double) -> Angle { Angle(degrees: degrees) }
    public static let zero = Angle()

    public static func < (lhs: Angle, rhs: Angle) -> Bool { lhs.radians < rhs.radians }
}

extension Path {
    /// A path that `callback` builds.
    public init(_ callback: (inout Path) -> Void) {
        self.init()
        callback(&self)
    }

    /// Adds a rectangle as a closed subpath.
    public mutating func addRect(_ rect: CGRect) {
        addPath(Path(rect))
    }

    /// Adds rectangles as closed subpaths.
    public mutating func addRects(_ rects: [CGRect]) {
        for rect in rects { addRect(rect) }
    }

    /// Adds a rounded rectangle as a closed subpath. Assumed: the corners
    /// are as wide as they are tall, the corner size's width, because
    /// Parhelion's corners have one radius.
    public mutating func addRoundedRect(
        in rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous
    ) {
        addPath(Path(roundedRect: rect, cornerRadius: cornerSize.width, style: style))
    }

    /// Adds an ellipse inscribed in a rectangle as a closed subpath.
    public mutating func addEllipse(in rect: CGRect) {
        addPath(Path(ellipseIn: rect))
    }

    /// Adds straight lines through points, starting a new subpath at the
    /// first.
    public mutating func addLines(_ lines: [CGPoint]) {
        guard let first = lines.first else { return }
        move(to: first)
        for point in lines.dropFirst() { addLine(to: point) }
    }

    /// Adds an arc of a circle, with a line to its start from the current
    /// point if there is one.
    ///
    /// As in SwiftUI, angles are measured from the positive x axis toward
    /// the positive y axis, which points down, and `clockwise` means
    /// decreasing angles, so a clockwise arc runs counterclockwise on
    /// screen. Each quarter turn or part of one is a cubic curve.
    public mutating func addArc(
        center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool
    ) {
        var sweep = endAngle.radians - startAngle.radians
        if clockwise {
            while sweep > 0 { sweep -= 2 * .pi }
        } else {
            while sweep < 0 { sweep += 2 * .pi }
        }
        let r = Double(radius)
        func point(_ angle: Double) -> CGPoint {
            CGPoint(x: Double(center.x) + r * cos(angle), y: Double(center.y) + r * sin(angle))
        }
        let start = point(startAngle.radians)
        if currentPoint == nil { move(to: start) } else { addLine(to: start) }
        let segments = max(1, Int((abs(sweep) / (.pi / 2)).rounded(.up)))
        let step = sweep / Double(segments)
        // A cubic curve spanning θ has its control points 4/3 · tan(θ/4) · r
        // along the tangents at its ends.
        let k = 4.0 / 3.0 * tan(step / 4) * r
        var angle = startAngle.radians
        for _ in 0..<segments {
            let next = angle + step
            let from = point(angle)
            let to = point(next)
            addCurve(
                to: to,
                control1: CGPoint(
                    x: Double(from.x) - k * sin(angle), y: Double(from.y) + k * cos(angle)),
                control2: CGPoint(
                    x: Double(to.x) + k * sin(next), y: Double(to.y) - k * cos(next)))
            angle = next
        }
    }
}

// MARK: - Shapes

/// A 2D shape that can be drawn as a view, mirroring SwiftUI's `Shape`.
///
/// A shape fills the space it is offered with the foreground style, or the
/// style given to ``fill(_:style:)``. The renderer asks the shape for its
/// path in the frame layout gave it. The tree records a shape of a type
/// Parhelion does not know by its description, the `shape` attribute,
/// which is `String(describing:)` of the shape, so two shapes with the
/// same description must have the same path.
public nonisolated protocol Shape: Sendable, View {
    /// The shape's outline in a rectangle.
    func path(in rect: CGRect) -> Path
}

extension Shape {
    /// A custom shape draws itself filled with the foreground style.
    @MainActor
    public var body: _ShapeView<Self, ForegroundStyle> {
        _ShapeView(shape: self, style: .foreground, fillStyle: FillStyle(), isBody: true)
    }

    /// The shape filled with a style.
    public func fill<S: ShapeStyle>(
        _ content: S, style: FillStyle = FillStyle()
    ) -> _ShapeView<Self, S> {
        _ShapeView(shape: self, style: content, fillStyle: style, isBody: false)
    }

    /// The shape filled with the foreground style.
    public func fill(style: FillStyle = FillStyle()) -> _ShapeView<Self, ForegroundStyle> {
        _ShapeView(shape: self, style: .foreground, fillStyle: style, isBody: false)
    }
}

/// How a shape is filled, mirroring SwiftUI's `FillStyle`.
public struct FillStyle: Hashable, Sendable {
    /// Whether to use the even-odd rule, which leaves the parts of a shape
    /// that its outlines cover an even number of times empty, instead of
    /// the nonzero rule.
    public var isEOFilled: Bool
    /// Whether to anti-alias the edges. Parhelion always does.
    public var isAntialiased: Bool

    public init(eoFill: Bool = false, antialiased: Bool = true) {
        isEOFilled = eoFill
        isAntialiased = antialiased
    }
}

/// A shape drawn with a style, produced by ``Shape/fill(_:style:)`` and by
/// a shape on its own.
public struct _ShapeView<Content: Shape, Style: ShapeStyle>: View {
    public typealias Body = Never

    let shape: Content
    let style: Style
    let fillStyle: FillStyle
    /// Whether this is a custom shape's body, which the evaluator has
    /// already given the shape's path component.
    let isBody: Bool

    nonisolated init(shape: Content, style: Style, fillStyle: FillStyle, isBody: Bool) {
        self.shape = shape
        self.style = style
        self.fillStyle = fillStyle
        self.isBody = isBody
    }

    public var body: Never {
        fatalError("_ShapeView is a primitive view and has no body.")
    }
}

extension _ShapeView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let geometry = ShapeGeometry(of: shape)
        let ownPath = isBody ? path : path.appending(baseTypeName(of: Content.self))
        var attributes = geometry.attributes
        if !(style is ForegroundStyle) { attributes["fill"] = style.styleName }
        if fillStyle.isEOFilled { attributes["eoFill"] = "true" }
        return [ViewNode(id: ownPath.id, kind: geometry.kind, attributes: attributes)]
    }
}

/// A rectangle, mirroring SwiftUI's `Rectangle`.
public struct Rectangle: Shape {
    public typealias Body = Never

    public nonisolated init() {}

    public nonisolated func path(in rect: CGRect) -> Path {
        Path(rect)
    }

    @MainActor public var body: Never {
        fatalError("Rectangle is a primitive view and has no body.")
    }
}

/// A rectangle with rounded corners, mirroring SwiftUI's `RoundedRectangle`.
/// The corners are continuous by default, as in SwiftUI.
public struct RoundedRectangle: Shape {
    public typealias Body = Never

    public var cornerRadius: CGFloat
    public var style: RoundedCornerStyle

    public nonisolated init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.cornerRadius = cornerRadius
        self.style = style
    }

    public nonisolated func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: cornerRadius, style: style)
    }

    @MainActor public var body: Never {
        fatalError("RoundedRectangle is a primitive view and has no body.")
    }
}

/// A circle centered in its frame, as wide as the frame's shorter side,
/// mirroring SwiftUI's `Circle`.
public struct Circle: Shape {
    public typealias Body = Never

    public nonisolated init() {}

    public nonisolated func path(in rect: CGRect) -> Path {
        Path(ellipseIn: Self.square(in: rect))
    }

    /// The square a circle fills in a rectangle.
    nonisolated static func square(in rect: CGRect) -> CGRect {
        let side = min(rect.width, rect.height)
        return CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
    }

    @MainActor public var body: Never {
        fatalError("Circle is a primitive view and has no body.")
    }
}

/// An ellipse that fills its frame, mirroring SwiftUI's `Ellipse`.
public struct Ellipse: Shape {
    public typealias Body = Never

    public nonisolated init() {}

    public nonisolated func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect)
    }

    @MainActor public var body: Never {
        fatalError("Ellipse is a primitive view and has no body.")
    }
}

/// A rectangle whose ends are half circles, mirroring SwiftUI's `Capsule`.
/// The corners are continuous by default, as in SwiftUI.
public struct Capsule: Shape {
    public typealias Body = Never

    public var style: RoundedCornerStyle

    public nonisolated init(style: RoundedCornerStyle = .continuous) {
        self.style = style
    }

    public nonisolated func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2, style: style)
    }

    @MainActor public var body: Never {
        fatalError("Capsule is a primitive view and has no body.")
    }
}

extension Path: Shape {
    public typealias Body = Never

    /// A path draws itself as it is, whatever the rectangle.
    public nonisolated func path(in rect: CGRect) -> Path {
        self
    }

    @MainActor public var body: Never {
        fatalError("Path is a primitive view and has no body.")
    }
}

/// The built-in shapes, which are primitive views and draw from the tree
/// alone.
protocol BuiltInShape: Shape, PrimitiveView {}

extension BuiltInShape {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        _ShapeView(shape: self, style: .foreground, fillStyle: FillStyle(), isBody: false)
            .makeNodes(in: evaluator, at: path)
    }
}

extension Rectangle: BuiltInShape {}
extension RoundedRectangle: BuiltInShape {}
extension Circle: BuiltInShape {}
extension Ellipse: BuiltInShape {}
extension Capsule: BuiltInShape {}
extension Path: BuiltInShape {}

// MARK: - Shapes in the tree

/// A shape as the tree records it, in a shape view's node or in a modifier
/// such as `clipShape(_:style:)`, and the path it has in a rectangle.
public enum ShapeGeometry: Hashable, Sendable, Codable {
    case rectangle
    case roundedRectangle(cornerRadius: CGFloat, continuous: Bool)
    case circle
    case ellipse
    case capsule(continuous: Bool)
    /// A `Path`, as SVG path data.
    case path(String)
    /// A shape of another type, by its description; see ``Shape``.
    case custom(type: String, description: String)

    init(of shape: some Shape) {
        switch shape {
        case is Rectangle: self = .rectangle
        case let shape as RoundedRectangle:
            self = .roundedRectangle(
                cornerRadius: shape.cornerRadius, continuous: shape.style == .continuous)
        case is Circle: self = .circle
        case is Ellipse: self = .ellipse
        case let shape as Capsule: self = .capsule(continuous: shape.style == .continuous)
        case let shape as Path: self = .path(shape.svgPathData)
        default:
            let description = String(describing: shape)
            CustomShapes.shared.register(shape, as: description)
            self = .custom(type: baseTypeName(of: type(of: shape)), description: description)
        }
    }

    /// The shape a shape view's node draws, or `nil` for other nodes.
    init?(node: ViewNode) {
        let attributes = node.attributes
        let continuous = attributes["style"] != "circular"
        switch node.kind {
        case "Rectangle": self = .rectangle
        case "RoundedRectangle":
            self = .roundedRectangle(
                cornerRadius: CGFloat(Double(attributes["cornerRadius"] ?? "") ?? 0),
                continuous: continuous)
        case "Circle": self = .circle
        case "Ellipse": self = .ellipse
        case "Capsule": self = .capsule(continuous: continuous)
        case "Path": self = .path(attributes["path"] ?? "")
        default:
            guard let description = attributes["shape"] else { return nil }
            self = .custom(type: node.kind, description: description)
        }
    }

    /// The node kind of a shape view: the shape's type name.
    var kind: String {
        switch self {
        case .rectangle: "Rectangle"
        case .roundedRectangle: "RoundedRectangle"
        case .circle: "Circle"
        case .ellipse: "Ellipse"
        case .capsule: "Capsule"
        case .path: "Path"
        case .custom(let type, _): type
        }
    }

    /// The attributes that describe the shape in its view's node.
    var attributes: [String: String] {
        switch self {
        case .roundedRectangle(let radius, let continuous):
            var attributes = ["cornerRadius": formatPoints(radius)]
            if !continuous { attributes["style"] = "circular" }
            return attributes
        case .capsule(let continuous):
            return continuous ? [:] : ["style": "circular"]
        case .path(let data): return ["path": data]
        case .custom(_, let description): return ["shape": description]
        case .rectangle, .circle, .ellipse: return [:]
        }
    }

    /// The shape in a modifier's outline, such as
    /// `RoundedRectangle(cornerRadius: 8)`.
    var outlineDescription: String {
        switch self {
        case .roundedRectangle(let radius, let continuous):
            "RoundedRectangle(cornerRadius: \(formatPoints(radius))"
                + (continuous ? ")" : ", style: circular)")
        case .capsule(let continuous): continuous ? "Capsule" : "Capsule(style: circular)"
        case .path: "Path"
        case .custom(_, let description): description
        default: kind
        }
    }

    /// The shape's outline in a rectangle. A custom shape whose description
    /// is no longer registered draws as the rectangle.
    func path(in rect: CGRect) -> Path {
        switch self {
        case .rectangle: return Path(rect)
        case .roundedRectangle(let radius, let continuous):
            return Path(
                roundedRect: rect, cornerRadius: radius,
                style: continuous ? .continuous : .circular)
        case .circle: return Path(ellipseIn: Circle.square(in: rect))
        case .ellipse: return Path(ellipseIn: rect)
        case .capsule(let continuous):
            return Path(
                roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2,
                style: continuous ? .continuous : .circular)
        case .path(let data): return Path(svgPathData: data) ?? Path()
        case .custom(_, let description):
            return CustomShapes.shared.shape(for: description)?.path(in: rect) ?? Path(rect)
        }
    }

    /// The rounded rectangle this shape is in a rectangle, for drawing it
    /// without the general rasterizer, or `nil` if it is not one.
    func roundedRect(in rect: CGRect) -> (rect: CGRect, radius: CGFloat, style: RoundedCornerStyle)?
    {
        switch self {
        case .rectangle: (rect, 0, .circular)
        case .roundedRectangle(let radius, let continuous):
            (rect, radius, continuous ? .continuous : .circular)
        case .capsule(let continuous):
            (rect, min(rect.width, rect.height) / 2, continuous ? .continuous : .circular)
        case .circle:
            (Circle.square(in: rect), min(rect.width, rect.height) / 2, .circular)
        case .ellipse where rect.width == rect.height: (rect, rect.width / 2, .circular)
        default: nil
        }
    }
}

/// Shapes of types that Parhelion does not know, by their description, so
/// the renderer can ask them for their paths in the frames layout chose.
///
/// The table is shared by every host in the process and keeps the shapes
/// registered most recently, up to a limit, so a shape whose description
/// changes in every frame of an animation does not grow it without bound.
final class CustomShapes: @unchecked Sendable {
    static let shared = CustomShapes()
    static let limit = 4096

    private let lock = NSLock()
    private var shapes: [String: any Shape] = [:]
    private var order: [String] = []

    func register(_ shape: any Shape, as description: String) {
        lock.lock()
        defer { lock.unlock() }
        if shapes.updateValue(shape, forKey: description) == nil { order.append(description) }
        if order.count > Self.limit {
            // Forget the oldest half at once, so registering stays cheap.
            for key in order.prefix(Self.limit / 2) { shapes[key] = nil }
            order.removeFirst(Self.limit / 2)
        }
    }

    func shape(for description: String) -> (any Shape)? {
        lock.lock()
        defer { lock.unlock() }
        return shapes[description]
    }
}
