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

    var outlineDescription: String {
        switch self {
        case .background(let style):
            return "background(\(style))"
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
