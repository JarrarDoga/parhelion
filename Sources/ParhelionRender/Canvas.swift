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

    /// A rectangle in points that drawing is limited to, or `nil` to draw
    /// anywhere on the canvas.
    public var clipRect: CGRect?

    /// Creates a canvas of the given size in points, filled with a color.
    public init(width: Double, height: Double, scale: Double, background: RGBA = .white) {
        self.width = max(Int((width * scale).rounded()), 0)
        self.height = max(Int((height * scale).rounded()), 0)
        self.scale = scale
        let count = self.width * self.height
        let word = background.packed
        pixels = [UInt8](unsafeUninitializedCapacity: count * 4) { buffer, initialized in
            UnsafeMutableRawBufferPointer(buffer).bindMemory(to: UInt32.self)
                .initialize(repeating: word)
            initialized = count * 4
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

    /// The clip rectangle in whole pixels, intersected with the canvas.
    private var pixelClip: (minX: Int, minY: Int, maxX: Int, maxY: Int) {
        var clip = (minX: 0, minY: 0, maxX: width, maxY: height)
        if let clipRect {
            // Clip to whole pixels, so content next to a clip edge never bleeds
            // across it.
            clip.minX = max(clip.minX, Int((Double(clipRect.minX) * scale).rounded()))
            clip.minY = max(clip.minY, Int((Double(clipRect.minY) * scale).rounded()))
            clip.maxX = min(clip.maxX, Int((Double(clipRect.maxX) * scale).rounded()))
            clip.maxY = min(clip.maxY, Int((Double(clipRect.maxY) * scale).rounded()))
        }
        return clip
    }

    /// Fills a path given in points.
    public mutating func fill(_ path: Path, color: RGBA) {
        guard color.alpha > 0 else { return }
        let pixelPath = path.applying(scaleX: scale, scaleY: scale, translateX: 0, translateY: 0)
        guard
            let coverage = Rasterizer.coverage(
                of: pixelPath.polygons(tolerance: 0.2),
                clip: pixelClip
            )
        else { return }
        composite(coverage, color: color)
    }

    /// Fills a rectangle given in points.
    ///
    /// Rectangles are most of what an interface draws, so they skip the
    /// general rasterizer: each pixel's coverage is the exact overlap of the
    /// pixel with the rectangle, and fully covered runs of an opaque color are
    /// written as whole 32-bit words. A translucent color is blended once for
    /// each run of equal pixels it covers.
    public mutating func fill(_ rect: CGRect, color: RGBA) {
        guard color.alpha > 0, rect.width > 0, rect.height > 0 else { return }
        let left = Double(rect.minX) * scale
        let right = Double(rect.maxX) * scale
        let top = Double(rect.minY) * scale
        let bottom = Double(rect.maxY) * scale
        let clip = pixelClip
        let startX = max(Int(left.rounded(.down)), clip.minX)
        let endX = min(Int(right.rounded(.up)), clip.maxX)
        let startY = max(Int(top.rounded(.down)), clip.minY)
        let endY = min(Int(bottom.rounded(.up)), clip.maxY)
        guard endX > startX, endY > startY else { return }

        // Columns whose pixels lie entirely inside the rectangle.
        let solidStartX = max(Int(left.rounded(.up)), startX)
        let solidEndX = min(Int(right.rounded(.down)), endX)
        let word = color.packed
        let width = width

        pixels.withUnsafeMutableBufferPointer { bytes in
            let words = UnsafeMutableRawBufferPointer(bytes).bindMemory(to: UInt32.self)
            for y in startY..<endY {
                let rowCoverage = min(Double(y + 1), bottom) - max(Double(y), top)
                let row = y * width
                if rowCoverage >= 1, solidEndX > solidStartX {
                    if color.alpha == 255 {
                        UnsafeMutableBufferPointer(
                            rebasing: words[(row + solidStartX)..<(row + solidEndX)]
                        )
                        .update(repeating: word)
                    } else {
                        // Interfaces draw translucent colors over flat ones,
                        // so blend once per run of equal pixels.
                        var source: UInt32?
                        var blended: UInt32 = 0
                        for index in (row + solidStartX)..<(row + solidEndX) {
                            if words[index] == source {
                                words[index] = blended
                                continue
                            }
                            source = words[index]
                            Self.blend(color, 1, into: bytes, at: index * 4)
                            blended = words[index]
                        }
                    }
                    for x in startX..<solidStartX {
                        let columnCoverage = min(Double(x + 1), right) - max(Double(x), left)
                        Self.blend(color, Float(columnCoverage), into: bytes, at: (row + x) * 4)
                    }
                    for x in max(solidEndX, startX)..<endX {
                        let columnCoverage = min(Double(x + 1), right) - max(Double(x), left)
                        Self.blend(color, Float(columnCoverage), into: bytes, at: (row + x) * 4)
                    }
                } else {
                    for x in startX..<endX {
                        let columnCoverage = min(Double(x + 1), right) - max(Double(x), left)
                        Self.blend(
                            color,
                            Float(columnCoverage * rowCoverage),
                            into: bytes,
                            at: (row + x) * 4
                        )
                    }
                }
            }
        }
    }

    /// Fills a rectangle with rounded corners, given in points.
    ///
    /// Only the four corners go through the general rasterizer, each clipped
    /// to its own box. The rest is filled as rectangles. Every edge that two
    /// of these pieces share lies on a pixel boundary, so no seams show.
    public mutating func fill(_ rect: CGRect, cornerRadius: CGFloat, color: RGBA) {
        guard color.alpha > 0, rect.width > 0, rect.height > 0 else { return }
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        guard radius > 0 else {
            fill(rect, color: color)
            return
        }
        func snap(_ value: CGFloat, _ rule: FloatingPointRoundingRule) -> CGFloat {
            CGFloat((Double(value) * scale).rounded(rule) / scale)
        }
        let innerLeft = snap(rect.minX + radius, .up)
        let innerRight = snap(rect.maxX - radius, .down)
        let innerTop = snap(rect.minY + radius, .up)
        let innerBottom = snap(rect.maxY - radius, .down)
        let path = Path(roundedRect: rect, cornerRadius: radius)
        guard innerLeft < innerRight, innerTop < innerBottom else {
            fill(path, color: color)
            return
        }

        fill(
            CGRect(x: rect.minX, y: innerTop, width: rect.width, height: innerBottom - innerTop),
            color: color)
        fill(
            CGRect(
                x: innerLeft, y: rect.minY, width: innerRight - innerLeft,
                height: innerTop - rect.minY),
            color: color)
        fill(
            CGRect(
                x: innerLeft, y: innerBottom, width: innerRight - innerLeft,
                height: rect.maxY - innerBottom),
            color: color)

        // Each corner box reaches outward to whole pixels, so the clip keeps
        // the partly covered pixels along the rectangle's edges.
        let outerLeft = snap(rect.minX, .down)
        let outerRight = snap(rect.maxX, .up)
        let outerTop = snap(rect.minY, .down)
        let outerBottom = snap(rect.maxY, .up)
        let corners = [
            CGRect(
                x: outerLeft, y: outerTop, width: innerLeft - outerLeft, height: innerTop - outerTop
            ),
            CGRect(
                x: innerRight, y: outerTop, width: outerRight - innerRight,
                height: innerTop - outerTop),
            CGRect(
                x: outerLeft, y: innerBottom, width: innerLeft - outerLeft,
                height: outerBottom - innerBottom),
            CGRect(
                x: innerRight, y: innerBottom, width: outerRight - innerRight,
                height: outerBottom - innerBottom),
        ]
        let outerClip = clipRect
        defer { clipRect = outerClip }
        for corner in corners {
            let clip = outerClip.map { $0.intersection(corner) } ?? corner
            guard !clip.isNull, clip.width > 0, clip.height > 0 else { continue }
            clipRect = clip
            fill(path, color: color)
        }
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
        let width = width
        pixels.withUnsafeMutableBufferPointer { bytes in
            coverage.values.withUnsafeBufferPointer { values in
                for row in 0..<coverage.height {
                    let rowStart = ((coverage.originY + row) * width + coverage.originX) * 4
                    let valueStart = row * coverage.width
                    for column in 0..<coverage.width {
                        let amount = values[valueStart + column]
                        guard amount > 0 else { continue }
                        Self.blend(color, amount, into: bytes, at: rowStart + column * 4)
                    }
                }
            }
        }
    }

    /// Blends `color`, weighted by `coverage` in `0...1`, over the pixel at a
    /// byte offset, with straight-alpha "source over" compositing.
    @inline(__always)
    private static func blend(
        _ color: RGBA,
        _ coverage: Float,
        into bytes: UnsafeMutableBufferPointer<UInt8>,
        at index: Int
    ) {
        let amount = min(coverage, 1) * Float(color.alpha) / 255
        guard amount > 0 else { return }
        let destinationAlpha = Float(bytes[index + 3]) / 255
        let outAlpha = amount + destinationAlpha * (1 - amount)
        guard outAlpha > 0 else { return }
        let keep = destinationAlpha * (1 - amount)
        func channel(_ source: UInt8, _ destination: UInt8) -> UInt8 {
            let value = (Float(source) * amount + Float(destination) * keep) / outAlpha
            return UInt8(min(max(value.rounded(), 0), 255))
        }
        bytes[index] = channel(color.red, bytes[index])
        bytes[index + 1] = channel(color.green, bytes[index + 1])
        bytes[index + 2] = channel(color.blue, bytes[index + 2])
        bytes[index + 3] = UInt8(min(max((outAlpha * 255).rounded(), 0), 255))
    }
}

extension RGBA {
    /// The color as a 32-bit word whose bytes in memory are red, green,
    /// blue, alpha.
    var packed: UInt32 {
        let value =
            UInt32(red) | UInt32(green) << 8 | UInt32(blue) << 16 | UInt32(alpha) << 24
        return value.littleEndian
    }
}
