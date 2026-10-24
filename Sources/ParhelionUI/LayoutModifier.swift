#if canImport(Foundation)
import Foundation
#endif

/// The inset distances for the sides of a rectangle.
public struct EdgeInsets: Hashable, Sendable, Codable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init() {
        self.init(top: 0, leading: 0, bottom: 0, trailing: 0)
    }

    init(_ edges: Edge.Set, _ length: CGFloat) {
        self.init(
            top: edges.contains(.top) ? length : 0,
            leading: edges.contains(.leading) ? length : 0,
            bottom: edges.contains(.bottom) ? length : 0,
            trailing: edges.contains(.trailing) ? length : 0
        )
    }

    var horizontal: CGFloat { leading + trailing }
    var vertical: CGFloat { top + bottom }
}

/// The parameters of a flexible frame, produced by
/// `frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`.
public struct FlexibleFrame: Hashable, Sendable, Codable {
    public var minWidth: CGFloat?
    public var idealWidth: CGFloat?
    public var maxWidth: CGFloat?
    public var minHeight: CGFloat?
    public var idealHeight: CGFloat?
    public var maxHeight: CGFloat?
    public var alignment: Alignment
}

/// A modifier that changes how a view is sized, placed, or framed.
///
/// Layout modifiers are kept in order on each ``ViewNode``, innermost first,
/// because their order changes the result: `.padding().frame(width: 100)` is
/// not the same as `.frame(width: 100).padding()`.
public enum LayoutModifier: Hashable, Sendable, Codable {
    case padding(EdgeInsets)
    case frame(width: CGFloat?, height: CGFloat?, alignment: Alignment)
    case flexibleFrame(FlexibleFrame)
    /// Fills the bounds at this point in the chain with a style, behind the
    /// view. It does not change the size.
    case background(style: String)
    /// The insets of a row in a ``List``. The row fills the width it is
    /// offered and is at least a minimum height; its content sits inside the
    /// insets at the leading edge. The bounds at this point in the chain are
    /// the row's cell.
    case listRow(EdgeInsets)
    /// Moves the view when it is drawn and tapped, without changing its
    /// size or the layout around it.
    case offset(CGSize)
    /// Places the views of one of the node's `Overlay` children over the
    /// bounds at this point in the chain: the first such modifier's views
    /// are in the first `Overlay` child, and so on. It does not change the
    /// size.
    case overlay(alignment: Alignment)
    /// Fills a shape with a style over the view, in the bounds at this
    /// point in the chain.
    case overlayStyle(style: String, shape: ShapeGeometry, eoFill: Bool)
    /// Clips the view, and what the modifiers before this one draw, to a
    /// shape in the bounds at this point in the chain.
    case clipShape(ShapeGeometry, eoFill: Bool)
    /// Clips the view to the bounds at this point in the chain, with
    /// circular corners of a radius.
    case cornerRadius(CGFloat)
    /// Draws a blurred shadow of everything the view and the modifiers
    /// before this one draw. The radius and offset are in points.
    case shadow(color: String, radius: CGFloat, x: CGFloat, y: CGFloat)
    /// Scales how the view draws around an anchor, a unit point in the
    /// bounds at this point in the chain, without changing its layout.
    case scaleEffect(x: CGFloat, y: CGFloat, anchor: CGPoint)
    /// Proposes the view the largest size with a width-to-height ratio that
    /// fits the proposal, or with `fill`, the smallest that covers it. A
    /// `nil` ratio is the view's ideal size's.
    case aspectRatio(CGFloat?, fill: Bool)

    var outlineDescription: String {
        switch self {
        case .background(let style):
            return "background(\(style))"
        case .listRow:
            return "listRow"
        case .offset(let offset):
            return "offset(x: \(formatPoints(offset.width)), y: \(formatPoints(offset.height)))"
        case .overlay(let alignment):
            return alignment == .center ? "overlay" : "overlay(alignment: \(alignment.name))"
        case .overlayStyle(let style, let shape, let eoFill):
            let fill = eoFill ? ", eoFill" : ""
            return shape == .rectangle
                ? "overlay(\(style)\(fill))"
                : "overlay(\(style), in: \(shape.outlineDescription)\(fill))"
        case .clipShape(let shape, let eoFill):
            return "clipShape(\(shape.outlineDescription)\(eoFill ? ", eoFill" : ""))"
        case .cornerRadius(let radius):
            return "cornerRadius(\(formatPoints(radius)))"
        case .shadow(let color, let radius, let x, let y):
            var parts: [String] = []
            if color != Self.defaultShadowColor { parts.append("color: \(color)") }
            parts.append("radius: \(formatPoints(radius))")
            if x != 0 { parts.append("x: \(formatPoints(x))") }
            if y != 0 { parts.append("y: \(formatPoints(y))") }
            return "shadow(" + parts.joined(separator: ", ") + ")"
        case .aspectRatio(let ratio, let fill):
            let mode = "contentMode: \(fill ? "fill" : "fit")"
            return "aspectRatio(" + (ratio.map { "\(formatUnit($0)), " } ?? "") + mode + ")"
        case .scaleEffect(let x, let y, let anchor):
            var parts =
                x == y ? [formatPoints(x)] : ["x: \(formatPoints(x))", "y: \(formatPoints(y))"]
            let unit = UnitPoint(x: anchor.x, y: anchor.y)
            if unit != .center { parts.append("anchor: \(unit.name)") }
            return "scaleEffect(" + parts.joined(separator: ", ") + ")"
        case .padding(let insets):
            let values = [insets.top, insets.leading, insets.bottom, insets.trailing]
            if Set(values).count == 1 { return "padding(\(formatPoints(insets.top)))" }
            return "padding(" + values.map(formatPoints).joined(separator: ", ") + ")"
        case .frame(let width, let height, let alignment):
            var parts: [String] = []
            if let width { parts.append("width: \(formatPoints(width))") }
            if let height { parts.append("height: \(formatPoints(height))") }
            if alignment != .center { parts.append("alignment: \(alignment.name)") }
            return "frame(" + parts.joined(separator: ", ") + ")"
        case .flexibleFrame(let frame):
            let fields: [(String, CGFloat?)] = [
                ("minWidth", frame.minWidth), ("idealWidth", frame.idealWidth),
                ("maxWidth", frame.maxWidth), ("minHeight", frame.minHeight),
                ("idealHeight", frame.idealHeight), ("maxHeight", frame.maxHeight),
            ]
            var parts = fields.compactMap { name, value in
                value.map { "\(name): \(formatPoints($0))" }
            }
            if frame.alignment != .center { parts.append("alignment: \(frame.alignment.name)") }
            return "frame(" + parts.joined(separator: ", ") + ")"
        }
    }
}

extension LayoutModifier {
    /// The style name of `shadow(color:radius:x:y:)`'s default color.
    static let defaultShadowColor = Color(red: 0, green: 0, blue: 0, opacity: 0.33).styleName
}

extension View {
    /// Adds padding to the given edges. A `nil` length uses the platform
    /// default.
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        layoutModifier(.padding(EdgeInsets(edges, length ?? LayoutDefaults.padding)))
    }

    /// Adds the same padding to every edge.
    public func padding(_ length: CGFloat) -> some View {
        padding(.all, length)
    }

    /// Adds padding with a different length on each edge.
    public func padding(_ insets: EdgeInsets) -> some View {
        layoutModifier(.padding(insets))
    }

    /// Fills the view's bounds, at this point in the modifier chain, with a
    /// style. The safe-area edges are ignored: Parhelion does not extend
    /// backgrounds into the safe area yet.
    public func background(
        _ style: some ShapeStyle,
        ignoresSafeAreaEdges edges: Edge.Set = .all
    ) -> some View {
        layoutModifier(.background(style: style.styleName))
    }

    /// Places the view in an invisible frame of a fixed size. A `nil`
    /// dimension takes the size of the view in that dimension.
    public func frame(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        layoutModifier(.frame(width: width, height: height, alignment: alignment))
    }

    /// Places the view in an invisible frame whose size adapts to the
    /// proposed size within the given limits.
    public func frame(
        minWidth: CGFloat? = nil,
        idealWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        idealHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        layoutModifier(
            .flexibleFrame(
                FlexibleFrame(
                    minWidth: minWidth,
                    idealWidth: idealWidth,
                    maxWidth: maxWidth,
                    minHeight: minHeight,
                    idealHeight: idealHeight,
                    maxHeight: maxHeight,
                    alignment: alignment
                )
            )
        )
    }
}

/// How a view fills the space a ratio gives it, mirroring SwiftUI's
/// `ContentMode`.
public enum ContentMode: Hashable, CaseIterable, Sendable {
    /// The view fits inside the space.
    case fit
    /// The view covers the space.
    case fill
}

extension View {
    /// Constrains the view to a width-to-height ratio, or, for `nil`, to its
    /// ideal size's, fitting or filling the space it is offered.
    public func aspectRatio(_ aspectRatio: CGFloat? = nil, contentMode: ContentMode) -> some View {
        layoutModifier(.aspectRatio(aspectRatio, fill: contentMode == .fill))
    }

    /// Constrains the view to the ratio of a size's width to its height.
    public func aspectRatio(_ aspectRatio: CGSize, contentMode: ContentMode) -> some View {
        self.aspectRatio(
            aspectRatio.height == 0 ? nil : aspectRatio.width / aspectRatio.height,
            contentMode: contentMode)
    }

    /// Scales the view to fit the space it is offered, keeping its ratio.
    public func scaledToFit() -> some View {
        aspectRatio(contentMode: .fit)
    }

    /// Scales the view to cover the space it is offered, keeping its ratio.
    public func scaledToFill() -> some View {
        aspectRatio(contentMode: .fill)
    }
}
