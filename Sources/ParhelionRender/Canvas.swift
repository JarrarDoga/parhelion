#if canImport(Foundation)
import Foundation
#endif

/// An 8-bit-per-channel color with straight (not premultiplied) alpha.
public struct RGBA: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// A color from components in `0...1`.
    public init(fractionalRed red: Double, green: Double, blue: Double, opacity: Double = 1) {
        func byte(_ value: Double) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }
        self.init(red: byte(red), green: byte(green), blue: byte(blue), alpha: byte(opacity))
    }

    public static let white = RGBA(red: 255, green: 255, blue: 255)
    public static let black = RGBA(red: 0, green: 0, blue: 0)
    public static let clear = RGBA(red: 0, green: 0, blue: 0, alpha: 0)
}

/// A pixel buffer that shapes and text are drawn into.
///
/// Drawing calls take coordinates in points. The canvas multiplies them by
/// its `scale` to get pixels, so a 393 × 852 point canvas at scale 2 holds
/// 786 × 1704 pixels.
public struct Canvas: Sendable {
    /// The width in pixels.
    public let width: Int
    /// The height in pixels.
    public let height: Int
    /// Pixels per point.
    public let scale: Double
    /// RGBA pixels, four bytes each, row-major from the top-left corner.
    public private(set) var pixels: [UInt8]

    /// Creates a canvas of the given size in points, filled with a color.
    public init(width: Double, height: Double, scale: Double, background: RGBA = .white) {
        self.width = max(Int((width * scale).rounded()), 0)
        self.height = max(Int((height * scale).rounded()), 0)
        self.scale = scale
        let pixel = [background.red, background.green, background.blue, background.alpha]
        pixels = [UInt8](unsafeUninitializedCapacity: self.width * self.height * 4) {
            buffer,
            count in
            for index in 0..<(buffer.count / 4) {
                buffer[index * 4] = pixel[0]
                buffer[index * 4 + 1] = pixel[1]
                buffer[index * 4 + 2] = pixel[2]
                buffer[index * 4 + 3] = pixel[3]
            }
            count = buffer.count
        }
    }

    /// The color of the pixel at a position in pixels.
    public func pixel(x: Int, y: Int) -> RGBA {
        let index = (y * width + x) * 4
        return RGBA(
            red: pixels[index],
            green: pixels[index + 1],
            blue: pixels[index + 2],
            alpha: pixels[index + 3]
        )
    }

    /// Fills a path given in points.
    public mutating func fill(_ path: Path, color: RGBA) {
        guard color.alpha > 0 else { return }
        let pixelPath = path.applying(scaleX: scale, scaleY: scale, translateX: 0, translateY: 0)
        guard
            let coverage = Rasterizer.coverage(
                of: pixelPath.polygons(tolerance: 0.2),
                clipWidth: width,
                clipHeight: height
            )
        else { return }
        composite(coverage, color: color)
    }

    /// Fills a rectangle given in points.
    public mutating func fill(_ rect: CGRect, color: RGBA) {
        fill(Path(rect), color: color)
    }

    /// Draws one line of text with its baseline starting at `origin`, in
    /// points. Each glyph is placed at the advance width of the previous one,
    /// the same way layout measures text.
    public mutating func drawText(
        _ text: some StringProtocol,
        font: TrueTypeFont,
        size: Double,
        origin: CGPoint,
        color: RGBA
    ) {
        let unitsToPoints = size / Double(font.unitsPerEm)
        var x = Double(origin.x)
        var glyphs = Path()
        for scalar in text.unicodeScalars {
            let glyph = font.glyph(for: scalar)
            let outline = font.outline(ofGlyph: glyph)
            if !outline.isEmpty {
                // Font units point up; the canvas's y axis points down.
                glyphs.addPath(
                    outline.applying(
                        scaleX: unitsToPoints,
                        scaleY: -unitsToPoints,
                        translateX: x,
                        translateY: Double(origin.y)
                    )
                )
            }
            x += Double(font.advance(ofGlyph: glyph)) * unitsToPoints
        }
        fill(glyphs, color: color)
    }

    /// Blends a color into the canvas, weighted by coverage.
    private mutating func composite(_ coverage: Coverage, color: RGBA) {
        let sourceAlpha = Float(color.alpha) / 255
        let red = Float(color.red)
        let green = Float(color.green)
        let blue = Float(color.blue)
        for row in 0..<coverage.height {
            let y = coverage.originY + row
            for column in 0..<coverage.width {
                let amount = coverage.values[row * coverage.width + column] * sourceAlpha
                guard amount > 0 else { continue }
                let index = (y * width + coverage.originX + column) * 4
                let destinationAlpha = Float(pixels[index + 3]) / 255
                let outAlpha = amount + destinationAlpha * (1 - amount)
                guard outAlpha > 0 else { continue }
                func blend(_ source: Float, _ destination: UInt8) -> UInt8 {
                    let value =
                        (source * amount + Float(destination) * destinationAlpha * (1 - amount))
                        / outAlpha
                    return UInt8(min(max(value.rounded(), 0), 255))
                }
                pixels[index] = blend(red, pixels[index])
                pixels[index + 1] = blend(green, pixels[index + 1])
                pixels[index + 2] = blend(blue, pixels[index + 2])
                pixels[index + 3] = UInt8(min(max((outAlpha * 255).rounded(), 0), 255))
            }
        }
    }
}
