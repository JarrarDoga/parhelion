import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// Drawing shapes, gradients, and styles that can be gradients, which the
// renderer calls for the kinds it does not handle itself.

extension TreeRenderer {
    /// What a style fills with in a rectangle: one color, or a gradient
    /// whose unit points are mapped into the rectangle.
    enum Paint {
        case color(RGBA)
        case gradient(Canvas.LinearGradient)
    }

    /// The color of a style name, with the tint and an opacity, for content
    /// drawn where no `paint` function from `draw(_:inherited:into:)` is at
    /// hand. Every other color the shape, effect, and image drawing uses
    /// goes through that function, so this is the one place where they
    /// look a color up themselves.
    func contentColor(_ style: String, tint: String?, opacity: Double) -> RGBA {
        var color = ColorPalette.color(named: style == "tint" ? tint ?? style : style)
        color.alpha = UInt8((Double(color.alpha) * opacity).rounded())
        return color
    }

    /// The system fills that content in these files draws with, by name,
    /// as the colors `ColorPalette` reads: `AsyncImage`'s placeholder is
    /// `secondarySystemFill`, 120,120,128 at 16% in light (swatch
    /// `Fills/Light/2 Secondary`).
    static let systemFills = ["secondarySystemFill": "rgba(0.4706,0.4706,0.502,0.16)"]

    /// The paint of a style in a rectangle. `foreground` is the style that
    /// `.foreground` stands for, and `color` resolves each color name, with
    /// the node's tint and opacity.
    func paint(
        of style: String, in rect: CGRect, foreground: String?, color: (String) -> RGBA
    ) -> Paint {
        switch StyleDescription(style) {
        case .color(let name):
            return .color(color(Self.systemFills[name] ?? name))
        case .foreground:
            guard let foreground, foreground != "foreground" else {
                return .color(color("primary"))
            }
            return paint(of: foreground, in: rect, foreground: nil, color: color)
        case .linearGradient(let stops, let start, let end):
            return .gradient(
                Canvas.LinearGradient(
                    stops: stops.map {
                        Canvas.LinearGradient.Stop(color: color($0.color), location: $0.location)
                    },
                    start: start.point(in: rect), end: end.point(in: rect)))
        }
    }

    /// Fills a rectangle with a style, as a `background` does.
    func fill(
        _ rect: CGRect, style: String, foreground: String?, paint color: (String) -> RGBA,
        into canvas: inout Canvas
    ) {
        fill(
            .rectangle, in: rect,
            with: paint(of: style, in: rect, foreground: foreground, color: color),
            into: &canvas)
    }

    /// Fills a shape in a rectangle with a paint. Rectangles, rounded
    /// rectangles, capsules, and circles skip the general rasterizer for a
    /// color.
    func fill(
        _ shape: ShapeGeometry, in rect: CGRect, with paint: Paint, evenOdd: Bool = false,
        into canvas: inout Canvas
    ) {
        switch paint {
        case .color(let color):
            if let rounded = shape.roundedRect(in: rect) {
                canvas.fill(
                    rounded.rect, cornerRadius: rounded.radius, style: rounded.style, color: color)
            } else {
                canvas.fill(shape.path(in: rect), color: color, evenOdd: evenOdd)
            }
        case .gradient(let gradient):
            canvas.fill(shape.path(in: rect), gradient: gradient, evenOdd: evenOdd)
        }
    }

    /// Draws a shape view or a gradient view, and nothing for other nodes.
    func drawContent(
        _ node: ViewNode, in frame: CGRect, foreground: String?, paint color: (String) -> RGBA,
        into canvas: inout Canvas
    ) {
        if node.kind == "LinearGradient" {
            let style =
                "linearGradient(\(node.attributes["gradient"] ?? ""), "
                + "\(node.attributes["startPoint"] ?? "top"), "
                + "\(node.attributes["endPoint"] ?? "bottom"))"
            fill(
                .rectangle, in: frame,
                with: paint(of: style, in: frame, foreground: foreground, color: color),
                into: &canvas)
            return
        }
        guard let shape = ShapeGeometry(node: node) else { return }
        let style = node.attributes["fill"] ?? "foreground"
        fill(
            shape, in: frame,
            with: paint(of: style, in: frame, foreground: foreground, color: color),
            evenOdd: node.attributes["eoFill"] == "true", into: &canvas)
    }
}
