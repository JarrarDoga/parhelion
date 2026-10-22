#if canImport(Foundation)
import Foundation
#endif

/// A Gaussian blur approximated by three box blurs, run at a reduced
/// resolution when the blur is wide.
///
/// Three passes of a box blur converge on a Gaussian, and each pass costs
/// the same however wide the box is, thanks to a running sum. The box
/// widths follow Ivan Kutskir's "boxes for Gauss": odd widths, so each
/// pass is centered and the result is symmetric, chosen so the three
/// passes' variance matches σ². A blur wider than 3 pixels runs on samples
/// that each average a `factor` × `factor` block of pixels, since a wide
/// blur has no detail at that scale, and is resampled bilinearly. All of
/// it runs on integers, so every machine produces the same pixels.
struct BlurKernel {
    /// Canvas pixels per sample along each axis.
    let factor: Int
    /// The radius of each box, in samples. A box spans `2 r + 1` samples.
    let radii: [Int]

    /// The value of full coverage, or of 255 × 255 for premultiplied color.
    static let one: Int32 = 65_025

    /// A blur with standard deviation `sigma`, in canvas pixels.
    init(sigma: Double) {
        guard sigma > 0 else {
            factor = 1
            radii = []
            return
        }
        let factor = max(1, Int(sigma / 3))
        // Averaging blocks and resampling bilinearly blur by about a
        // quarter of the factor squared, so the boxes make up the rest.
        let resampling = factor > 1 ? Double(factor * factor) / 4 : 0
        let s = max(sigma * sigma - resampling, 0).squareRoot() / Double(factor)
        var lower = Int((4 * s * s + 1).squareRoot().rounded(.down))
        if lower % 2 == 0 { lower -= 1 }
        lower = max(lower, 1)
        let l = Double(lower)
        let lowerCount = Int(((12 * s * s - 3 * l * l - 12 * l - 9) / (-4 * l - 4)).rounded())
        self.factor = factor
        radii = (0..<3).map { ($0 < lowerCount ? lower : lower + 2) / 2 }
    }

    /// The radius of the three boxes together, in samples.
    var reach: Int { radii.reduce(0, +) }

    /// How far, in canvas pixels, the blur can carry color: the boxes'
    /// reach, plus a sample on each side for averaging and resampling.
    var pixelReach: Int { factor == 1 ? reach : (reach + 2) * factor }

    /// Blurs a `width` × `height` grid of interleaved channels in place.
    /// Values past the grid's edges repeat the edge.
    func apply(to values: inout [Int32], width: Int, height: Int, channels: Int) {
        guard reach > 0, width > 0, height > 0 else { return }
        var line = [Int32](repeating: 0, count: max(width, height))
        values.withUnsafeMutableBufferPointer { data in
            line.withUnsafeMutableBufferPointer { line in
                for radius in radii where radius > 0 {
                    for row in 0..<height {
                        for channel in 0..<channels {
                            Self.pass(
                                data, start: row * width * channels + channel, count: width,
                                step: channels, radius: radius, line: line)
                        }
                    }
                }
                for radius in radii where radius > 0 {
                    for column in 0..<width {
                        for channel in 0..<channels {
                            Self.pass(
                                data, start: column * channels + channel, count: height,
                                step: width * channels, radius: radius, line: line)
                        }
                    }
                }
            }
        }
    }

    /// One box blur along one line of `count` values, `step` apart.
    @inline(__always)
    private static func pass(
        _ data: UnsafeMutableBufferPointer<Int32>, start: Int, count: Int, step: Int,
        radius: Int, line: UnsafeMutableBufferPointer<Int32>
    ) {
        for index in 0..<count { line[index] = data[start &+ index &* step] }
        // Dividing by the box width is a multiplication by its reciprocal
        // in 32.32 fixed point, which is exact for flat lines.
        let width = 2 * radius + 1
        let reciprocal = ((1 << 32) + width / 2) / width
        let last = count - 1
        var sum = 0
        for offset in -radius...radius { sum += Int(line[min(max(offset, 0), last)]) }
        // The values are at most 255 × 255 and the boxes are narrow, so
        // nothing here can overflow.
        for index in 0..<count {
            data[start &+ index &* step] = Int32(
                truncatingIfNeeded: (sum &* reciprocal &+ (1 << 31)) >> 32)
            sum =
                sum &+ Int(line[min(index &+ radius &+ 1, last)])
                &- Int(line[max(index &- radius, 0)])
        }
    }

    /// For each canvas pixel from `start` to `end`, the two samples it lies
    /// between and the second one's weight out of 256, for a grid whose
    /// first sample begins at pixel `origin` and has `count` samples.
    func resampling(from start: Int, to end: Int, origin: Int, count: Int) -> Resampling {
        var result = Resampling()
        for pixel in start..<end {
            let position = (Double(pixel - origin) + 0.5) / Double(factor) - 0.5
            var first = Int(position.rounded(.down))
            var weight = Int(((position - Double(first)) * 256).rounded())
            if first < 0 {
                first = 0
                weight = 0
            }
            if first >= count - 1 {
                first = count - 1
                weight = 0
            }
            result.entries += [first, min(first + 1, count - 1), weight]
        }
        return result
    }

    /// Where each pixel along one axis reads the sample grid: three
    /// numbers per pixel, the first sample, the second sample, and the
    /// second one's weight out of 256.
    struct Resampling {
        var entries: [Int] = []

        var count: Int { entries.count / 3 }

        /// The pixels, by index, whose samples include any from `low`
        /// through `high`.
        func pixels(reaching low: Int, _ high: Int) -> Range<Int> {
            var start = 0
            while start < count, entries[start * 3 + 1] < low { start += 1 }
            var end = count
            while end > start, entries[(end - 1) * 3] > high { end -= 1 }
            return start..<end
        }
    }
}

extension Canvas {
    /// Draws the blurred shadow of a path given in points.
    ///
    /// The shadow is the path's shape moved by `offset`, blurred, and filled
    /// with `color`. `blur` is the blur radius as design tools and CSS
    /// shadows give it: a Gaussian with standard deviation `blur / 2`.
    ///
    /// The shape is rasterized at the blur's sample resolution, blurred
    /// three times with box blurs, and resampled bilinearly into the canvas,
    /// so the cost grows with the shadow's area and hardly with the blur.
    /// Only pixels within the blur's reach of the shape, and inside the
    /// clip, are touched, and pixels the shadow would change by less than
    /// half a level are skipped. Unless `drawsUnderShape` is set, the
    /// shadow is cut away where the unmoved shape covers the canvas, as CSS
    /// and Figma do, so a translucent shape drawn over it does not darken.
    public mutating func drawShadow(
        of path: Path, color: RGBA, offset: CGSize = .zero, blur: Double,
        drawsUnderShape: Bool = false
    ) {
        drawShadow(
            of: path,
            knockout: { canvas, box in
                CoverageMask(path: path, canvas: canvas, box: box)
            }, color: color, offset: offset, blur: blur, drawsUnderShape: drawsUnderShape)
    }

    /// Draws the blurred shadow of a rounded rectangle given in points. A
    /// corner radius of half the height makes a capsule's shadow.
    ///
    /// See `drawShadow(of:color:offset:blur:drawsUnderShape:)`. The shape
    /// that cuts the shadow away is rasterized only in its corners, and the
    /// pixels it covers fully are skipped as whole runs, so the cost is
    /// mostly the ring of pixels around the shape.
    public mutating func drawShadow(
        of rect: CGRect, cornerRadius: CGFloat, style: Path.CornerStyle = .circular,
        color: RGBA, offset: CGSize = .zero, blur: Double, drawsUnderShape: Bool = false
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        drawShadow(
            of: Path(roundedRect: rect, cornerRadius: cornerRadius, style: style),
            knockout: { canvas, box in
                CoverageMask(
                    rect: rect, cornerRadius: cornerRadius, style: style, canvas: canvas, box: box)
            }, color: color, offset: offset, blur: blur, drawsUnderShape: drawsUnderShape)
    }

    private mutating func drawShadow(
        of path: Path, knockout makeKnockout: (Canvas, PixelBox) -> CoverageMask, color: RGBA,
        offset: CGSize, blur: Double, drawsUnderShape: Bool
    ) {
        guard color.alpha > 0, let bounds = path.controlBounds else { return }
        let kernel = BlurKernel(sigma: max(blur, 0) / 2 * scale)
        let factor = kernel.factor
        let padding = kernel.pixelReach + factor
        let clip = pixelClip
        let offsetX = Double(offset.width) * scale
        let offsetY = Double(offset.height) * scale
        // The shadow's pixels, grown by the blur's reach and limited to what
        // can reach the clip.
        let minX = max(
            Int((Double(bounds.minX) * scale + offsetX).rounded(.down)) - padding,
            clip.minX - padding)
        let minY = max(
            Int((Double(bounds.minY) * scale + offsetY).rounded(.down)) - padding,
            clip.minY - padding)
        let maxX = min(
            Int((Double(bounds.maxX) * scale + offsetX).rounded(.up)) + padding,
            clip.maxX + padding)
        let maxY = min(
            Int((Double(bounds.maxY) * scale + offsetY).rounded(.up)) + padding,
            clip.maxY + padding)
        let visible = PixelBox(
            minX: max(minX, clip.minX), minY: max(minY, clip.minY), maxX: min(maxX, clip.maxX),
            maxY: min(maxY, clip.maxY))
        guard !visible.isEmpty else { return }

        // Rasterize the moved shape onto the sample grid, and blur it.
        let samplesWide = (maxX - minX + factor - 1) / factor
        let samplesHigh = (maxY - minY + factor - 1) / factor
        let sampleScale = scale / Double(factor)
        let samplePath = path.applying(
            scaleX: sampleScale, scaleY: sampleScale,
            translateX: (offsetX - Double(minX)) / Double(factor),
            translateY: (offsetY - Double(minY)) / Double(factor))
        guard
            let shape = Rasterizer.coverage(
                of: samplePath.polygons(tolerance: 0.2),
                clip: (0, 0, samplesWide, samplesHigh))
        else { return }
        var mask = [Int32](repeating: 0, count: samplesWide * samplesHigh)
        for row in 0..<shape.height {
            for column in 0..<shape.width {
                mask[(shape.originY + row) * samplesWide + shape.originX + column] = Int32(
                    (shape.values[row * shape.width + column] * Float(BlurKernel.one)).rounded())
            }
        }
        kernel.apply(to: &mask, width: samplesWide, height: samplesHigh, channels: 1)

        // The unmoved shape, to cut the shadow away under it.
        let knockout =
            drawsUnderShape ? CoverageMask(box: visible) : makeKnockout(self, visible)
        let shapeBounds = knockout.bounds

        let columns = kernel.resampling(
            from: visible.minX, to: visible.maxX, origin: minX, count: samplesWide)
        let rows = kernel.resampling(
            from: visible.minY, to: visible.maxY, origin: minY, count: samplesHigh)
        let width = width
        let mode = blendMode
        let unit = 1 / (Float(BlurKernel.one) * 65_536)
        // Below this value, the shadow changes a pixel by less than half a
        // level.
        let faintest = Int(Float(BlurKernel.one) * 65_536 * 0.5 / Float(color.alpha))
        // Skip the rows and columns whose samples are all fainter than that.
        let threshold = Int32(faintest / 65_536)
        var strong = PixelBox(minX: samplesWide, minY: samplesHigh, maxX: -1, maxY: -1)
        for row in 0..<samplesHigh {
            for column in 0..<samplesWide where mask[row * samplesWide + column] > threshold {
                strong.minX = min(strong.minX, column)
                strong.maxX = max(strong.maxX, column)
                strong.minY = min(strong.minY, row)
                strong.maxY = max(strong.maxY, row)
            }
        }
        guard strong.maxX >= 0 else { return }
        let columnRange = columns.pixels(reaching: strong.minX, strong.maxX)
        let rowRange = rows.pixels(reaching: strong.minY, strong.maxY)
        let rowEntries = rows.entries
        var line = [Int](repeating: 0, count: samplesWide)
        pixels.withUnsafeMutableBufferPointer { bytes in
            mask.withUnsafeBufferPointer { mask in
                line.withUnsafeMutableBufferPointer { line in
                    columns.entries.withUnsafeBufferPointer { columns in
                        for rowIndex in rowRange {
                            let y = visible.minY + rowIndex
                            // Interpolate between the two sample rows once, then
                            // along the row for each pixel.
                            let top = rowEntries[rowIndex * 3] * samplesWide
                            let bottom = rowEntries[rowIndex * 3 + 1] * samplesWide
                            let lowerWeight = rowEntries[rowIndex * 3 + 2]
                            for index in 0..<samplesWide {
                                line[index] =
                                    Int(mask[top &+ index]) &* (256 &- lowerWeight)
                                    &+ Int(mask[bottom &+ index]) &* lowerWeight
                            }
                            let full = knockout.fullSpan(y: y)
                            let shapeRow = y >= shapeBounds.minY && y < shapeBounds.maxY
                            var x = visible.minX + columnRange.lowerBound
                            while x < visible.minX + columnRange.upperBound {
                                if full.contains(x) {
                                    x = full.upperBound
                                    continue
                                }
                                let column = (x &- visible.minX) &* 3
                                let rightWeight = columns[column &+ 2]
                                let value =
                                    line[columns[column]] &* (256 &- rightWeight)
                                    &+ line[columns[column &+ 1]] &* rightWeight
                                if value > faintest {
                                    var amount = Float(value) * unit
                                    if shapeRow, x >= shapeBounds.minX, x < shapeBounds.maxX {
                                        amount *= 1 - knockout.coverage(x: x, y: y)
                                    }
                                    Self.blendQuickly(
                                        color, amount, mode, into: bytes,
                                        at: (y &* width &+ x) &* 4)
                                }
                                x &+= 1
                            }
                        }
                    }
                }
            }
        }
    }

    /// Blurs the pixels already on the canvas inside a rounded rectangle
    /// given in points, and optionally changes their saturation, for glass
    /// and other materials over busy content. Draw the material's tint
    /// layers over the result.
    ///
    /// `radius` is a blur radius as design tools give it: a Gaussian with
    /// standard deviation `radius / 2`. The blur reads pixels around the
    /// rectangle, up to its reach, so content next to the shape bleeds in
    /// as it does under real glass; past the edges of the canvas and the
    /// clip it repeats the edge pixels, so a flat color stays flat. Only
    /// pixels inside the shape and the clip change, and anti-aliased edge
    /// pixels mix the blurred and the original color.
    ///
    /// `saturation` scales each color's distance from its gray, with the
    /// same matrix as CSS's `saturate()`: 0 is gray, 1 leaves colors as
    /// they are, and 2 doubles their saturation. Liquid Glass uses 2 for
    /// small controls and 1.4 for alerts and sheets.
    ///
    /// The pixels are premultiplied, averaged into blocks for a wide blur,
    /// blurred with three box blurs, saturated, and resampled bilinearly,
    /// all in integers. The shape's coverage is rasterized only in its
    /// corners.
    public mutating func blur(
        _ rect: CGRect, cornerRadius: CGFloat = 0, style: Path.CornerStyle = .circular,
        radius: Double, saturation: Double = 1
    ) {
        guard rect.width > 0, rect.height > 0, radius > 0 || saturation != 1 else { return }
        let clip = pixelClip
        let target = PixelBox(
            minX: max(Int((Double(rect.minX) * scale).rounded(.down)), clip.minX),
            minY: max(Int((Double(rect.minY) * scale).rounded(.down)), clip.minY),
            maxX: min(Int((Double(rect.maxX) * scale).rounded(.up)), clip.maxX),
            maxY: min(Int((Double(rect.maxY) * scale).rounded(.up)), clip.maxY))
        guard !target.isEmpty else { return }

        let kernel = BlurKernel(sigma: max(radius, 0) / 2 * scale)
        let factor = kernel.factor
        let padding = kernel.reach > 0 ? kernel.pixelReach : 0
        let originX = target.minX - padding
        let originY = target.minY - padding
        let samplesWide = (target.maxX - target.minX + 2 * padding + factor - 1) / factor
        let samplesHigh = (target.maxY - target.minY + 2 * padding + factor - 1) / factor
        var values = downsample(
            originX: originX, originY: originY, samplesWide: samplesWide,
            samplesHigh: samplesHigh, factor: factor, clip: clip)
        kernel.apply(to: &values, width: samplesWide, height: samplesHigh, channels: 4)
        if saturation != 1 { Self.saturate(&values, by: saturation) }

        let mask = CoverageMask(
            rect: rect, cornerRadius: cornerRadius, style: style, canvas: self, box: target)
        let columns = kernel.resampling(
            from: target.minX, to: target.maxX, origin: originX, count: samplesWide)
        let rows = kernel.resampling(
            from: target.minY, to: target.maxY, origin: originY, count: samplesHigh)
        let width = width
        let rowEntries = rows.entries
        var line = [Int](repeating: 0, count: samplesWide * 4)
        pixels.withUnsafeMutableBufferPointer { bytes in
            values.withUnsafeBufferPointer { values in
                line.withUnsafeMutableBufferPointer { line in
                    columns.entries.withUnsafeBufferPointer { columns in
                        for rowIndex in 0..<rows.count {
                            let y = target.minY + rowIndex
                            // Interpolate between the two sample rows once,
                            // then along the row for each pixel.
                            let top = rowEntries[rowIndex * 3] * samplesWide * 4
                            let bottom = rowEntries[rowIndex * 3 + 1] * samplesWide * 4
                            let lowerWeight = rowEntries[rowIndex * 3 + 2]
                            for index in 0..<samplesWide * 4 {
                                line[index] =
                                    Int(values[top &+ index]) &* (256 &- lowerWeight)
                                    &+ Int(values[bottom &+ index]) &* lowerWeight
                            }
                            let full = mask.fullSpan(y: y)
                            for x in target.minX..<target.maxX {
                                let coverage = full.contains(x) ? 1 : mask.coverage(x: x, y: y)
                                guard coverage > 0 else { continue }
                                let column = (x &- target.minX) &* 3
                                let rightWeight = columns[column &+ 2]
                                let leftWeight = 256 &- rightWeight
                                let left = columns[column] &* 4
                                let right = columns[column &+ 1] &* 4
                                Self.storeSample(
                                    red: line[left] &* leftWeight &+ line[right] &* rightWeight,
                                    green: line[left &+ 1] &* leftWeight &+ line[right &+ 1]
                                        &* rightWeight,
                                    blue: line[left &+ 2] &* leftWeight &+ line[right &+ 2]
                                        &* rightWeight,
                                    alpha: line[left &+ 3] &* leftWeight &+ line[right &+ 3]
                                        &* rightWeight,
                                    coverage: coverage, into: bytes, at: (y &* width &+ x) &* 4)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Writes a resampled premultiplied sample, with 255 × 255 × 65536 as
    /// full, over a pixel, mixed with the pixel by `coverage`.
    @inline(__always)
    private static func storeSample(
        red: Int, green: Int, blue: Int, alpha: Int, coverage: Float,
        into bytes: UnsafeMutableBufferPointer<UInt8>, at index: Int
    ) {
        // A sample's straight color is its premultiplied color over its
        // opacity. Opaque samples, the usual case, divide by a constant,
        // which compiles to a multiplication.
        let unit = 16_711_680  // 255 × 65536: one level of an opaque sample
        var newRed = 0
        var newGreen = 0
        var newBlue = 0
        var newAlpha = 0
        if alpha >= 255 * unit {
            newRed = (red &+ unit / 2) / unit
            newGreen = (green &+ unit / 2) / unit
            newBlue = (blue &+ unit / 2) / unit
            newAlpha = 255
        } else if alpha > 0 {
            let inverse = 255 / Double(alpha)
            newRed = Int(Double(red) * inverse + 0.5)
            newGreen = Int(Double(green) * inverse + 0.5)
            newBlue = Int(Double(blue) * inverse + 0.5)
            newAlpha = (alpha + unit / 2) / unit
        }
        if coverage >= 1 {
            bytes[index] = UInt8(truncatingIfNeeded: min(newRed, 255))
            bytes[index &+ 1] = UInt8(truncatingIfNeeded: min(newGreen, 255))
            bytes[index &+ 2] = UInt8(truncatingIfNeeded: min(newBlue, 255))
            bytes[index &+ 3] = UInt8(truncatingIfNeeded: min(newAlpha, 255))
        } else {
            @inline(__always) func mix(_ old: UInt8, _ new: Int) -> UInt8 {
                let value = Float(old) + (Float(min(new, 255)) - Float(old)) * coverage
                return UInt8(truncatingIfNeeded: Int(value + 0.5))
            }
            bytes[index] = mix(bytes[index], newRed)
            bytes[index + 1] = mix(bytes[index + 1], newGreen)
            bytes[index + 2] = mix(bytes[index + 2], newBlue)
            bytes[index + 3] = mix(bytes[index + 3], newAlpha)
        }
    }

    /// Averages `factor` × `factor` blocks of premultiplied pixels into a
    /// grid of samples, four channels each, scaled so that 255 × 255 is
    /// full. Pixels outside the clip repeat the nearest pixel inside it.
    private func downsample(
        originX: Int, originY: Int, samplesWide: Int, samplesHigh: Int, factor: Int,
        clip: (minX: Int, minY: Int, maxX: Int, maxY: Int)
    ) -> [Int32] {
        let columns = (0..<samplesWide * factor).map {
            min(max(originX + $0, clip.minX), clip.maxX - 1) * 4
        }
        let rows = (0..<samplesHigh * factor).map {
            min(max(originY + $0, clip.minY), clip.maxY - 1)
        }
        var samples = [Int32](repeating: 0, count: samplesWide * samplesHigh * 4)
        var sums = [Int](repeating: 0, count: samplesWide * 4)
        let blockSize = factor * factor
        let width = width
        pixels.withUnsafeBufferPointer { bytes in
            columns.withUnsafeBufferPointer { columns in
                sums.withUnsafeMutableBufferPointer { sums in
                    samples.withUnsafeMutableBufferPointer { samples in
                        for sampleRow in 0..<samplesHigh {
                            for index in 0..<sums.count { sums[index] = 0 }
                            for subrow in 0..<factor {
                                let rowStart = rows[sampleRow * factor + subrow] * width * 4
                                var column = 0
                                for sampleColumn in 0..<samplesWide {
                                    var red = 0
                                    var green = 0
                                    var blue = 0
                                    var alpha = 0
                                    for _ in 0..<factor {
                                        let index = rowStart &+ columns[column]
                                        let pixelAlpha = Int(bytes[index &+ 3])
                                        red &+= Int(bytes[index]) &* pixelAlpha
                                        green &+= Int(bytes[index &+ 1]) &* pixelAlpha
                                        blue &+= Int(bytes[index &+ 2]) &* pixelAlpha
                                        alpha &+= pixelAlpha
                                        column &+= 1
                                    }
                                    let sample = sampleColumn &* 4
                                    sums[sample] &+= red
                                    sums[sample &+ 1] &+= green
                                    sums[sample &+ 2] &+= blue
                                    sums[sample &+ 3] &+= alpha &* 255
                                }
                            }
                            let start = sampleRow * samplesWide * 4
                            for index in 0..<sums.count {
                                samples[start + index] = Int32(
                                    (sums[index] + blockSize / 2) / blockSize)
                            }
                        }
                    }
                }
            }
        }
        return samples
    }

    /// Scales each premultiplied sample's saturation with CSS's
    /// `saturate()` matrix, in 20.12 fixed point.
    private static func saturate(_ values: inout [Int32], by amount: Double) {
        func fixed(_ value: Double) -> Int { Int((value * 4096).rounded()) }
        let s = amount
        let (rr, rg, rb) = (
            fixed(0.213 + 0.787 * s), fixed(0.715 - 0.715 * s), fixed(0.072 - 0.072 * s)
        )
        let (gr, gg, gb) = (
            fixed(0.213 - 0.213 * s), fixed(0.715 + 0.285 * s), fixed(0.072 - 0.072 * s)
        )
        let (br, bg, bb) = (
            fixed(0.213 - 0.213 * s), fixed(0.715 - 0.715 * s), fixed(0.072 + 0.928 * s)
        )
        values.withUnsafeMutableBufferPointer { values in
            var index = 0
            while index < values.count {
                let red = Int(values[index])
                let green = Int(values[index + 1])
                let blue = Int(values[index + 2])
                let alpha = Int(values[index + 3])
                func clamp(_ value: Int) -> Int32 { Int32(min(max(value >> 12, 0), alpha)) }
                values[index] = clamp(rr * red + rg * green + rb * blue + 2048)
                values[index + 1] = clamp(gr * red + gg * green + gb * blue + 2048)
                values[index + 2] = clamp(br * red + bg * green + bb * blue + 2048)
                index += 4
            }
        }
    }
}

/// A rectangle of pixels, from `(minX, minY)` up to, not including,
/// `(maxX, maxY)`.
struct PixelBox {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    var isEmpty: Bool { maxX <= minX || maxY <= minY }
}

/// A shape's coverage of the pixels in a box, for blurs and for cutting
/// shadows away.
///
/// A rounded rectangle is rasterized only in its four corner boxes;
/// elsewhere its coverage is the exact overlap of the pixel with the
/// rectangle. Any other path is rasterized over the whole box. Pixels
/// outside the box have no coverage.
struct CoverageMask {
    let box: PixelBox
    /// The pixels of the box that the shape may cover.
    let bounds: PixelBox
    /// For a rounded rectangle, each column's and row's overlap with it.
    private let columnCoverage: [Float]
    private let rowCoverage: [Float]
    /// The pixels where the corners don't reach: a rounded rectangle's
    /// coverage there is the product of its column and row coverage.
    private let inner: PixelBox
    /// The columns a rounded rectangle covers fully.
    private let fullColumns: Range<Int>
    /// The rasterized coverage: each corner box of a rounded rectangle, or
    /// the whole box for other paths.
    private let rasterized: [Coverage]

    /// The coverage of a rounded rectangle given in points.
    init(
        rect: CGRect, cornerRadius: CGFloat, style: Path.CornerStyle, canvas: Canvas, box: PixelBox
    ) {
        self.box = box
        let scale = canvas.scale
        let left = Double(rect.minX) * scale
        let right = Double(rect.maxX) * scale
        let top = Double(rect.minY) * scale
        let bottom = Double(rect.maxY) * scale
        let columns = (box.minX..<max(box.maxX, box.minX)).map {
            Float(max(min(Double($0 + 1), right) - max(Double($0), left), 0))
        }
        columnCoverage = columns
        rowCoverage = (box.minY..<max(box.maxY, box.minY)).map {
            Float(max(min(Double($0 + 1), bottom) - max(Double($0), top), 0))
        }
        bounds = PixelBox(
            minX: max(box.minX, Int(left.rounded(.down))),
            minY: max(box.minY, Int(top.rounded(.down))),
            maxX: min(box.maxX, Int(right.rounded(.up))),
            maxY: min(box.maxY, Int(bottom.rounded(.up))))
        let firstFull = columns.firstIndex { $0 >= 1 }.map { $0 + box.minX } ?? 0
        let lastFull = columns.lastIndex { $0 >= 1 }.map { $0 + box.minX + 1 } ?? 0
        fullColumns = firstFull..<max(lastFull, firstFull)

        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        let extent = Double(Path.cornerExtent(of: rect, cornerRadius: radius, style: style)) * scale
        guard extent > 0 else {
            inner = box
            rasterized = []
            return
        }
        let polygons = Path(roundedRect: rect, cornerRadius: radius, style: style)
            .applying(scaleX: scale, scaleY: scale, translateX: 0, translateY: 0)
            .polygons(tolerance: 0.2)
        let cross = PixelBox(
            minX: Int((left + extent).rounded(.up)), minY: Int((top + extent).rounded(.up)),
            maxX: Int((right - extent).rounded(.down)), maxY: Int((bottom - extent).rounded(.down)))
        guard !cross.isEmpty else {
            // No straight sides to speak of: rasterize the whole shape.
            inner = PixelBox(minX: 0, minY: 0, maxX: 0, maxY: 0)
            rasterized = [
                Rasterizer.coverage(of: polygons, clip: (box.minX, box.minY, box.maxX, box.maxY))
            ].compactMap { $0 }
            return
        }
        inner = cross
        let corners = [
            PixelBox(minX: box.minX, minY: box.minY, maxX: cross.minX, maxY: cross.minY),
            PixelBox(minX: cross.maxX, minY: box.minY, maxX: box.maxX, maxY: cross.minY),
            PixelBox(minX: box.minX, minY: cross.maxY, maxX: cross.minX, maxY: box.maxY),
            PixelBox(minX: cross.maxX, minY: cross.maxY, maxX: box.maxX, maxY: box.maxY),
        ]
        rasterized = corners.compactMap { corner in
            let clipped = PixelBox(
                minX: max(corner.minX, box.minX), minY: max(corner.minY, box.minY),
                maxX: min(corner.maxX, box.maxX), maxY: min(corner.maxY, box.maxY))
            guard !clipped.isEmpty else { return nil }
            return Rasterizer.coverage(
                of: polygons, clip: (clipped.minX, clipped.minY, clipped.maxX, clipped.maxY))
        }
    }

    /// The coverage of any path given in points.
    init(path: Path, canvas: Canvas, box: PixelBox) {
        self.box = box
        columnCoverage = []
        rowCoverage = []
        inner = PixelBox(minX: 0, minY: 0, maxX: 0, maxY: 0)
        fullColumns = 0..<0
        let scale = canvas.scale
        let coverage = Rasterizer.coverage(
            of: path.applying(scaleX: scale, scaleY: scale, translateX: 0, translateY: 0)
                .polygons(tolerance: 0.2),
            clip: (box.minX, box.minY, box.maxX, box.maxY))
        rasterized = [coverage].compactMap { $0 }
        bounds =
            coverage.map {
                PixelBox(
                    minX: $0.originX, minY: $0.originY, maxX: $0.originX + $0.width,
                    maxY: $0.originY + $0.height)
            } ?? PixelBox(minX: 0, minY: 0, maxX: 0, maxY: 0)
    }

    /// No coverage anywhere in the box.
    init(box: PixelBox) {
        self.box = box
        bounds = PixelBox(minX: 0, minY: 0, maxX: 0, maxY: 0)
        columnCoverage = []
        rowCoverage = []
        inner = bounds
        fullColumns = 0..<0
        rasterized = []
    }

    /// The coverage of a pixel.
    @inline(__always)
    func coverage(x: Int, y: Int) -> Float {
        guard x >= box.minX, x < box.maxX, y >= box.minY, y < box.maxY else { return 0 }
        if !columnCoverage.isEmpty,
            rasterized.isEmpty || (x >= inner.minX && x < inner.maxX)
                || (y >= inner.minY && y < inner.maxY)
        {
            return columnCoverage[x - box.minX] * rowCoverage[y - box.minY]
        }
        for corner in rasterized
        where x >= corner.originX && x < corner.originX + corner.width && y >= corner.originY
            && y < corner.originY + corner.height
        {
            return corner.values[(y - corner.originY) * corner.width + x - corner.originX]
        }
        return 0
    }

    /// The pixels of a row that the shape covers fully, as one run, or an
    /// empty range if it doesn't know of any.
    func fullSpan(y: Int) -> Range<Int> {
        guard !columnCoverage.isEmpty, y >= box.minY, y < box.maxY,
            rowCoverage[y - box.minY] >= 1
        else { return 0..<0 }
        if rasterized.isEmpty || (y >= inner.minY && y < inner.maxY) { return fullColumns }
        let start = max(inner.minX, fullColumns.lowerBound)
        let end = min(inner.maxX, fullColumns.upperBound)
        return start < end ? start..<end : 0..<0
    }
}
