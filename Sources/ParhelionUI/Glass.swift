import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// How a Liquid Glass surface draws in the light appearance: a drop shadow,
/// a blur of what is behind it, a tint, a bright line just inside its edge,
/// and a darker ring just outside it.
///
/// Apple's glass also bends the content behind its edges. Parhelion leaves
/// that out: in a flat screenshot, glass reads as glass mostly from its
/// shape, its shadow, and its edges. The materials Parhelion uses are in
/// ``ColorPalette``.
struct GlassMaterial: Equatable {
    /// A blurred drop shadow under the glass.
    struct Shadow: Equatable {
        var color: RGBA
        var offset: CGFloat
        var blur: Double
    }

    /// One layer of the glass's tint, blended over the blurred backdrop.
    struct TintLayer: Equatable {
        var color: RGBA
        var blendMode: Canvas.BlendMode
    }

    var shadow: Shadow
    /// The blur radius of the backdrop, as design tools give it.
    var blurRadius: Double
    /// How much the backdrop's colors are saturated: 1 leaves them.
    var saturation: Double
    /// The tint, bottom layer first. A tinted surface, such as a prominent
    /// button, replaces it with its tint color.
    var tint: [TintLayer]
    /// The width, in points, of the bright line just inside the edge.
    var highlightWidth: CGFloat
    /// The bright line's opacity at the top edge and at the bottom edge. It
    /// fades out toward the middle, and is blended plus-lighter.
    var highlightTop: Double
    var highlightBottom: Double
    /// The color of the ring just outside the edge, blended plus-darker.
    var rim: RGBA
    var rimWidth: CGFloat
}

extension Canvas {
    /// Draws a glass surface in a rounded rectangle given in points.
    ///
    /// `tint` makes a tinted surface, such as a prominent button, filled with
    /// that color. `opacity` multiplies every layer, for a surface that is
    /// fading in or a pressed button. The blur is skipped when what is
    /// behind the surface, as far as the blur reaches, is one flat color,
    /// since blurring it would change nothing.
    mutating func drawGlass(
        _ rect: CGRect, cornerRadius: CGFloat, style: Path.CornerStyle = .circular,
        material: GlassMaterial, tint: RGBA? = nil, opacity: Double = 1
    ) {
        guard rect.width > 0, rect.height > 0, opacity > 0 else { return }
        let outerBlendMode = blendMode
        defer { blendMode = outerBlendMode }
        blendMode = .normal
        func faded(_ color: RGBA, by factor: Double = 1) -> RGBA {
            var color = color
            color.alpha = UInt8((Double(color.alpha) * opacity * factor).rounded())
            return color
        }

        // Whether the backdrop needs blurring is decided before the shadow
        // darkens it.
        let reach = CGFloat(material.blurRadius * 1.5)
        let blursBackdrop =
            tint == nil && material.blurRadius > 0
            && !isFlat(rect.insetBy(dx: -reach, dy: -reach))
        drawShadow(
            of: rect, cornerRadius: cornerRadius, style: style,
            color: faded(material.shadow.color),
            offset: CGSize(width: 0, height: material.shadow.offset), blur: material.shadow.blur)

        if let tint {
            fill(rect, cornerRadius: cornerRadius, style: style, color: faded(tint))
        } else {
            if blursBackdrop {
                blur(
                    rect, cornerRadius: cornerRadius, style: style, radius: material.blurRadius,
                    saturation: material.saturation)
            }
            for layer in material.tint {
                blendMode = layer.blendMode
                fill(rect, cornerRadius: cornerRadius, style: style, color: faded(layer.color))
            }
        }

        // The bright line inside the edge, strongest at the top and the
        // bottom.
        blendMode = .plusLighter
        let clearWhite = RGBA(red: 255, green: 255, blue: 255, alpha: 0)
        let fade = min(cornerRadius / max(rect.height, 1), 0.45)
        fill(
            Path(
                ringAround: rect, cornerRadius: cornerRadius, style: style,
                lineWidth: material.highlightWidth, alignment: .inside),
            gradient: LinearGradient(
                stops: [
                    .init(color: faded(.white, by: material.highlightTop), location: 0),
                    .init(color: clearWhite, location: Double(fade)),
                    .init(color: clearWhite, location: Double(1 - fade)),
                    .init(color: faded(.white, by: material.highlightBottom), location: 1),
                ],
                start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY)))

        if material.rimWidth > 0 {
            blendMode = .plusDarker
            stroke(
                rect, cornerRadius: cornerRadius, style: style, lineWidth: material.rimWidth,
                alignment: .outside, color: faded(material.rim))
        }
    }

    /// Whether every pixel in a rectangle given in points, within the canvas
    /// and the clip, has the same color.
    ///
    /// Every row is checked, at every pixel for scales up to 1 and at every
    /// point's first pixel above that: the narrowest thing drawn, a
    /// hairline, is a row of pixels, and glyph strokes are wider than a
    /// point.
    func isFlat(_ rect: CGRect) -> Bool {
        let clip = clipRect.map { $0.intersection(rect) } ?? rect
        guard !clip.isNull else { return true }
        let minX = max(Int((Double(clip.minX) * scale).rounded(.down)), 0)
        let minY = max(Int((Double(clip.minY) * scale).rounded(.down)), 0)
        let maxX = min(Int((Double(clip.maxX) * scale).rounded(.up)), width)
        let maxY = min(Int((Double(clip.maxY) * scale).rounded(.up)), height)
        guard minX < maxX, minY < maxY else { return true }
        let step = max(Int(scale.rounded(.down)), 1)
        let width = width
        return pixels.withUnsafeBytes { raw in
            let first = raw.load(fromByteOffset: (minY * width + minX) * 4, as: UInt32.self)
            for y in minY..<maxY {
                let row = y * width
                for x in stride(from: minX, to: maxX, by: step)
                where raw.load(fromByteOffset: (row + x) * 4, as: UInt32.self) != first {
                    return false
                }
                // The last pixel of the row, which the stride can skip.
                if raw.load(fromByteOffset: (row + maxX - 1) * 4, as: UInt32.self) != first {
                    return false
                }
            }
            return true
        }
    }
}
