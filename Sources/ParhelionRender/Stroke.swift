#if canImport(Foundation)
import Foundation
#endif

extension Path {
    /// Where a stroke lies relative to the edge of the shape it outlines.
    public enum StrokeAlignment: Sendable, Hashable {
        /// The stroke lies inside the edge, as SwiftUI's `strokeBorder`.
        case inside
        /// The stroke is centered on the edge, as SwiftUI's `stroke`.
        case center
        /// The stroke lies outside the edge, like a ring around the shape.
        case outside
    }

    /// The outer and inner rounded rectangles that bound a ring of
    /// `lineWidth` around `rect`, with the inner one's corners shrunk and
    /// the outer one's grown by the distance from the edge.
    static func ringBounds(
        around rect: CGRect, cornerRadius: CGFloat, lineWidth: CGFloat,
        alignment: StrokeAlignment
    ) -> (outer: CGRect, outerRadius: CGFloat, inner: CGRect, innerRadius: CGFloat) {
        let outset: CGFloat
        switch alignment {
        case .inside: outset = 0
        case .center: outset = lineWidth / 2
        case .outside: outset = lineWidth
        }
        let inset = lineWidth - outset
        let radius = max(min(cornerRadius, rect.width / 2, rect.height / 2), 0)
        let outer = rect.insetBy(dx: -outset, dy: -outset)
        let inner = rect.insetBy(dx: inset, dy: inset)
        return (
            outer, radius > 0 ? radius + outset : 0,
            inner, max(radius - inset, 0)
        )
    }

    /// A ring of `lineWidth` points that outlines a rounded rectangle:
    /// the outer edge, plus the inner edge running the other way, so the
    /// inside stays empty.
    ///
    /// The two edges are rounded rectangles whose radii differ by their
    /// distance, so circular corners stay concentric. Continuous corners
    /// are not exact parallel curves, so their ring's width varies by a few
    /// percent around the corners. Rectangles with square corners keep
    /// square corners on both edges. A ring as wide as the rectangle is the
    /// filled outer shape. This makes rings and hairlines for rounded
    /// shapes; there is no general stroker for arbitrary paths.
    public init(
        ringAround rect: CGRect, cornerRadius: CGFloat, style: CornerStyle = .circular,
        lineWidth: CGFloat, alignment: StrokeAlignment = .center
    ) {
        let bounds = Path.ringBounds(
            around: rect, cornerRadius: cornerRadius, lineWidth: lineWidth, alignment: alignment)
        self = Path(roundedRect: bounds.outer, cornerRadius: bounds.outerRadius, style: style)
        if bounds.inner.width > 0, bounds.inner.height > 0 {
            addPath(
                Path(
                    roundedRect: bounds.inner, cornerRadius: bounds.innerRadius, style: style,
                    reversed: true))
        }
    }
}

extension Canvas {
    /// Strokes the edge of a rounded rectangle given in points with a ring
    /// of `lineWidth` points, inside, centered on, or outside the edge.
    ///
    /// Like rounded-rectangle fills, only the corners go through the
    /// general rasterizer, each clipped to its own box; the straight sides
    /// are filled as rectangles with exact coverage. So a hairline around a
    /// large card costs about as much as its four corners. For a line one
    /// pixel wide, pass `1 / scale`.
    public mutating func stroke(
        _ rect: CGRect, cornerRadius: CGFloat, style: Path.CornerStyle = .circular,
        lineWidth: CGFloat, alignment: Path.StrokeAlignment = .center, color: RGBA
    ) {
        guard color.alpha > 0, lineWidth > 0, rect.width > 0, rect.height > 0 else { return }
        let bounds = Path.ringBounds(
            around: rect, cornerRadius: cornerRadius, lineWidth: lineWidth, alignment: alignment)
        let path = Path(
            ringAround: rect, cornerRadius: cornerRadius, style: style, lineWidth: lineWidth,
            alignment: alignment)
        let outer = bounds.outer
        let inner = bounds.inner
        guard inner.width > 0, inner.height > 0 else {
            fill(path, color: color)
            return
        }
        func snap(_ value: CGFloat, _ rule: FloatingPointRoundingRule) -> CGFloat {
            CGFloat((Double(value) * scale).rounded(rule) / scale)
        }
        // The sides are straight between the points where both edges'
        // corners end.
        let outerExtent = Path.cornerExtent(
            of: outer, cornerRadius: bounds.outerRadius, style: style)
        let innerExtent = Path.cornerExtent(
            of: inner, cornerRadius: bounds.innerRadius, style: style)
        let left = snap(max(outer.minX + outerExtent, inner.minX + innerExtent), .up)
        let right = snap(min(outer.maxX - outerExtent, inner.maxX - innerExtent), .down)
        let top = snap(max(outer.minY + outerExtent, inner.minY + innerExtent), .up)
        let bottom = snap(min(outer.maxY - outerExtent, inner.maxY - innerExtent), .down)
        guard left < right, top < bottom else {
            fill(path, color: color)
            return
        }
        fill(
            CGRect(x: left, y: outer.minY, width: right - left, height: inner.minY - outer.minY),
            color: color)
        fill(
            CGRect(x: left, y: inner.maxY, width: right - left, height: outer.maxY - inner.maxY),
            color: color)
        fill(
            CGRect(x: outer.minX, y: top, width: inner.minX - outer.minX, height: bottom - top),
            color: color)
        fill(
            CGRect(x: inner.maxX, y: top, width: outer.maxX - inner.maxX, height: bottom - top),
            color: color)

        let outerLeft = snap(outer.minX, .down)
        let outerRight = snap(outer.maxX, .up)
        let outerTop = snap(outer.minY, .down)
        let outerBottom = snap(outer.maxY, .up)
        let corners = [
            CGRect(x: outerLeft, y: outerTop, width: left - outerLeft, height: top - outerTop),
            CGRect(x: right, y: outerTop, width: outerRight - right, height: top - outerTop),
            CGRect(x: outerLeft, y: bottom, width: left - outerLeft, height: outerBottom - bottom),
            CGRect(x: right, y: bottom, width: outerRight - right, height: outerBottom - bottom),
        ]
        for corner in corners {
            fill(path, clippedTo: corner, color: color)
        }
    }
}
