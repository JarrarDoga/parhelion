#if canImport(Foundation)
import Foundation
#endif

// Modifiers that draw over, clip, shadow, or scale a view without changing
// its layout. Each is a layout modifier, because its place in the chain
// matters: a clip at one place clips the backgrounds inside it and not
// those outside. Rendering+Effects.swift draws them.

extension View {
    /// Layers views in front of this view, aligned in its bounds, without
    /// changing its size. Several views form an implicit `ZStack`.
    ///
    /// The views become the children of an `Overlay` node, the last child
    /// of each node this view resolves to. They are offered the size of the
    /// bounds at this point in the modifier chain. Assumed: as children,
    /// they take the foreground style and the opacity of the view they
    /// cover, wherever those are set, because Parhelion records those as
    /// attributes, not in the chain.
    public func overlay<V: View>(
        alignment: Alignment = .center, @ViewBuilder content: () -> V
    ) -> some View {
        OverlayView(content: self, overlay: content(), alignment: alignment)
    }

    /// Fills a shape with a style in front of this view, in its bounds.
    public func overlay<S: ShapeStyle, T: Shape>(
        _ style: S, in shape: T, fillStyle: FillStyle = FillStyle()
    ) -> some View {
        layoutModifier(
            .overlayStyle(
                style: style.styleName, shape: ShapeGeometry(of: shape),
                eoFill: fillStyle.isEOFilled))
    }

    /// Fills this view's bounds with a style in front of it. The safe-area
    /// edges are ignored, as for `background(_:ignoresSafeAreaEdges:)`.
    public func overlay<S: ShapeStyle>(
        _ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all
    ) -> some View {
        layoutModifier(.overlayStyle(style: style.styleName, shape: .rectangle, eoFill: false))
    }

    /// Clips this view to a shape that fills its bounds. Taps still reach
    /// the whole frame, as in SwiftUI, where `contentShape(_:)` changes
    /// what receives them.
    public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View {
        layoutModifier(.clipShape(ShapeGeometry(of: shape), eoFill: style.isEOFilled))
    }

    /// Clips this view to its bounds.
    public func clipped(antialiased: Bool = false) -> some View {
        layoutModifier(.clipShape(.rectangle, eoFill: false))
    }

    /// Clips this view to its bounds with rounded corners.
    ///
    /// Assumed: the corners are circular, as `clipShape(RoundedRectangle(
    /// cornerRadius: radius, style: .circular))` makes them; Apple's
    /// documentation does not say.
    @available(
        iOS, introduced: 13.0, deprecated: 27.2, message: "Use `clipShape` or `fill` instead."
    )
    @available(
        macOS, introduced: 10.15, deprecated: 27.2, message: "Use `clipShape` or `fill` instead."
    )
    @available(
        tvOS, introduced: 13.0, deprecated: 27.2, message: "Use `clipShape` or `fill` instead."
    )
    @available(
        watchOS, introduced: 6.0, deprecated: 27.2, message: "Use `clipShape` or `fill` instead."
    )
    @available(
        visionOS, introduced: 1.0, deprecated: 27.2, message: "Use `clipShape` or `fill` instead."
    )
    public func cornerRadius(_ radius: CGFloat, antialiased: Bool = true) -> some View {
        layoutModifier(.cornerRadius(radius))
    }

    /// Adds a shadow of everything this view draws.
    ///
    /// The default color is SwiftUI's, black at 33% opacity
    /// (https://developer.apple.com/documentation/swiftui/view/shadow(color:radius:x:y:)).
    /// Assumed: `radius` is half the blur that design tools give, so the
    /// shadow is blurred with a standard deviation of `radius`, as Core
    /// Animation's `shadowRadius` is against Sketch's blur.
    public func shadow(
        color: Color = Color(red: 0, green: 0, blue: 0, opacity: 0.33), radius: CGFloat,
        x: CGFloat = 0, y: CGFloat = 0
    ) -> some View {
        layoutModifier(.shadow(color: color.styleName, radius: radius, x: x, y: y))
    }

    /// Scales how this view draws around an anchor, without changing its
    /// layout. Assumed: taps reach the view's unscaled frame.
    public func scaleEffect(_ scale: CGSize, anchor: UnitPoint = .center) -> some View {
        layoutModifier(
            .scaleEffect(x: scale.width, y: scale.height, anchor: CGPoint(x: anchor.x, y: anchor.y))
        )
    }

    /// Scales how this view draws by the same amount along both axes.
    public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some View {
        scaleEffect(CGSize(width: s, height: s), anchor: anchor)
    }

    /// Scales how this view draws by different amounts along each axis.
    public func scaleEffect(
        x: CGFloat = 1.0, y: CGFloat = 1.0, anchor: UnitPoint = .center
    )
        -> some View
    {
        scaleEffect(CGSize(width: x, height: y), anchor: anchor)
    }
}

/// A view with views layered in front of it, produced by
/// ``View/overlay(alignment:content:)``.
struct OverlayView<Content: View, Overlay: View>: View {
    typealias Body = Never

    let content: Content
    let overlay: Overlay
    let alignment: Alignment

    var body: Never {
        fatalError("OverlayView is a primitive view and has no body.")
    }
}

extension OverlayView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.evaluate(content, at: path).map { node in
            var node = node
            // The overlay belongs to the node it covers, so its identity
            // follows the node's. A second overlay on the same view gets the
            // next number.
            let count = node.children.count { $0.kind == "Overlay" }
            let overlayPath = ViewPath().appending(node.id.rawValue)
                .appending(count == 0 ? "overlay" : "overlay\(count + 1)")
            node.children.append(
                ViewNode(
                    id: overlayPath.id, kind: "Overlay",
                    children: evaluator.evaluate(overlay, at: overlayPath)))
            node.modifiers.append(.overlay(alignment: alignment))
            return node
        }
    }
}

extension ViewNode {
    /// Whether this node holds the views of an `overlay(alignment:content:)`.
    var isOverlayContent: Bool { kind == "Overlay" }

    /// The node without its overlays' views, which layout places and the
    /// renderer draws at their modifiers' places in the chain.
    var withoutOverlayContent: ViewNode {
        guard children.last?.isOverlayContent == true else { return self }
        var node = self
        node.children.removeAll { $0.isOverlayContent }
        return node
    }
}

extension LayoutModifier {
    /// Whether the modifier changes how the view draws: a clip, a shadow, a
    /// scale, or a shape over it.
    var isDrawingEffect: Bool {
        switch self {
        case .overlayStyle, .clipShape, .cornerRadius, .shadow, .scaleEffect: true
        default: false
        }
    }

    var isOverlay: Bool {
        if case .overlay = self { return true }
        return false
    }
}
