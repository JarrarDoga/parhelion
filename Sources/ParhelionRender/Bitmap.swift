#if canImport(Foundation)
import Foundation
#endif

/// An image's pixels: four bytes each, red, green, blue, and straight
/// (not premultiplied) alpha, row-major from the top-left corner.
public struct Bitmap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    /// A bitmap of pixels. There must be `width × height × 4` bytes.
    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4, "A bitmap needs four bytes per pixel.")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The pixels of a canvas.
    public init(_ canvas: Canvas) {
        self.init(width: canvas.width, height: canvas.height, pixels: canvas.pixels)
    }

    /// The color of the pixel at a position.
    public func pixel(x: Int, y: Int) -> RGBA {
        let index = (y * width + x) * 4
        return RGBA(
            red: pixels[index], green: pixels[index + 1], blue: pixels[index + 2],
            alpha: pixels[index + 3])
    }

    /// The bitmap at half its size, rounded up, each pixel the average of
    /// up to four, with their colors weighted by their opacity. Drawing a
    /// large image small samples one of these levels, so that every source
    /// pixel counts.
    public func halved() -> Bitmap {
        let newWidth = max((width + 1) / 2, 1)
        let newHeight = max((height + 1) / 2, 1)
        var result = [UInt8](repeating: 0, count: newWidth * newHeight * 4)
        pixels.withUnsafeBufferPointer { source in
            for y in 0..<newHeight {
                for x in 0..<newWidth {
                    var red = 0
                    var green = 0
                    var blue = 0
                    var alpha = 0
                    var count = 0
                    for dy in 0..<2 where y * 2 + dy < height {
                        for dx in 0..<2 where x * 2 + dx < width {
                            let index = ((y * 2 + dy) * width + x * 2 + dx) * 4
                            let a = Int(source[index + 3])
                            red += Int(source[index]) * a
                            green += Int(source[index + 1]) * a
                            blue += Int(source[index + 2]) * a
                            alpha += a
                            count += 1
                        }
                    }
                    let index = (y * newWidth + x) * 4
                    if alpha > 0 {
                        result[index] = UInt8((red + alpha / 2) / alpha)
                        result[index + 1] = UInt8((green + alpha / 2) / alpha)
                        result[index + 2] = UInt8((blue + alpha / 2) / alpha)
                    }
                    result[index + 3] = UInt8((alpha + count / 2) / max(count, 1))
                }
            }
        }
        return Bitmap(width: newWidth, height: newHeight, pixels: result)
    }
}

extension Canvas {
    /// Draws part of a bitmap stretched into a rectangle given in points,
    /// sampling it bilinearly.
    ///
    /// - Parameters:
    ///   - source: The part of the bitmap to draw, in its pixels, or `nil`
    ///     for all of it. Samples never read outside it.
    ///   - opacity: Multiplies the bitmap's opacity.
    ///   - tint: A color that replaces every pixel's color, keeping its
    ///     opacity, for template images.
    ///   - flipX: Mirrors the bitmap left to right within the rectangle.
    ///   - flipY: Mirrors it top to bottom.
    ///
    /// Each pixel the rectangle covers takes the bitmap's color at its
    /// center, from the four nearest bitmap pixels, weighted by their
    /// opacity. Pixels along the rectangle's edges are covered in part and
    /// blended by how much. Drawing a bitmap much smaller than its size
    /// skips pixels; draw a level from `Bitmap.halved()` instead.
    public mutating func draw(
        _ bitmap: Bitmap, from source: CGRect? = nil, in rect: CGRect, opacity: Double = 1,
        tint: RGBA? = nil, flipX: Bool = false, flipY: Bool = false
    ) {
        guard rect.width > 0, rect.height > 0, bitmap.width > 0, bitmap.height > 0, opacity > 0
        else { return }
        let source = source ?? CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)
        guard source.width > 0, source.height > 0 else { return }
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

        // Where each column and row samples the bitmap: the two source
        // pixels it lies between, the second one's weight out of 256, and
        // how much of the column or row the rectangle covers.
        struct Sample {
            var first: Int
            var second: Int
            var weight: Int
            var coverage: Double
        }
        func samples(
            from start: Int, to end: Int, low: Double, high: Double, sourceLow: Double,
            sourceHigh: Double, flipped: Bool
        ) -> [Sample] {
            let firstPixel = Int(sourceLow.rounded(.down))
            let lastPixel = max(Int(sourceHigh.rounded(.up)) - 1, firstPixel)
            let ratio = (sourceHigh - sourceLow) / (high - low)
            return (start..<end).map { pixel in
                var offset = (Double(pixel) + 0.5 - low) * ratio
                if flipped { offset = sourceHigh - sourceLow - offset }
                let position = sourceLow + offset - 0.5
                var first = Int(position.rounded(.down))
                var weight = Int(((position - Double(first)) * 256).rounded())
                if first < firstPixel {
                    first = firstPixel
                    weight = 0
                }
                if first >= lastPixel {
                    first = lastPixel
                    weight = 0
                }
                let coverage = min(Double(pixel + 1), high) - max(Double(pixel), low)
                return Sample(
                    first: first, second: min(first + 1, lastPixel), weight: weight,
                    coverage: coverage)
            }
        }
        let columns = samples(
            from: startX, to: endX, low: left, high: right, sourceLow: Double(source.minX),
            sourceHigh: Double(source.maxX), flipped: flipX)
        let rows = samples(
            from: startY, to: endY, low: top, high: bottom, sourceLow: Double(source.minY),
            sourceHigh: Double(source.maxY), flipped: flipY)
        let width = width
        let bitmapWidth = bitmap.width
        let mode = blendMode
        let strength = Float(min(opacity, 1))
        pixels.withUnsafeMutableBufferPointer { bytes in
            bitmap.pixels.withUnsafeBufferPointer { image in
                for (rowIndex, row) in rows.enumerated() {
                    let y = startY + rowIndex
                    let upper = row.first * bitmapWidth
                    let lower = row.second * bitmapWidth
                    let rowWeight = row.weight
                    for (columnIndex, column) in columns.enumerated() {
                        // Interpolate premultiplied colors, in 65536ths.
                        var red = 0
                        var green = 0
                        var blue = 0
                        var alpha = 0
                        let right = column.weight
                        Self.accumulate(
                            image, upper + column.first, (256 - right) * (256 - rowWeight),
                            &red, &green, &blue, &alpha)
                        Self.accumulate(
                            image, upper + column.second, right * (256 - rowWeight), &red, &green,
                            &blue, &alpha)
                        Self.accumulate(
                            image, lower + column.first, (256 - right) * rowWeight, &red, &green,
                            &blue, &alpha)
                        Self.accumulate(
                            image, lower + column.second, right * rowWeight, &red, &green, &blue,
                            &alpha)
                        guard alpha > 0 else { continue }
                        let color: RGBA
                        if let tint {
                            color = RGBA(
                                red: tint.red, green: tint.green, blue: tint.blue,
                                alpha: UInt8((alpha * Int(tint.alpha) / 255 + 32_768) >> 16))
                        } else {
                            color = RGBA(
                                red: UInt8((red + alpha / 2) / alpha),
                                green: UInt8((green + alpha / 2) / alpha),
                                blue: UInt8((blue + alpha / 2) / alpha),
                                alpha: UInt8((alpha + 32_768) >> 16))
                        }
                        let coverage = Float(column.coverage * row.coverage) * strength
                        Self.blend(
                            color, coverage, mode, into: bytes,
                            at: (y * width + startX + columnIndex) * 4)
                    }
                }
            }
        }
    }

    /// Adds a bitmap pixel's premultiplied color, weighted, to sums.
    @inline(__always)
    private static func accumulate(
        _ image: UnsafeBufferPointer<UInt8>, _ index: Int, _ weight: Int, _ red: inout Int,
        _ green: inout Int, _ blue: inout Int, _ alpha: inout Int
    ) {
        guard weight > 0 else { return }
        let a = Int(image[index &* 4 &+ 3]) &* weight
        red &+= Int(image[index &* 4]) &* a
        green &+= Int(image[index &* 4 &+ 1]) &* a
        blue &+= Int(image[index &* 4 &+ 2]) &* a
        alpha &+= a
    }
}
