#if canImport(Foundation)
import Foundation
#endif

extension Canvas {
    /// Colors that change along a line, for filling shapes.
    ///
    /// Each stop places a color at a location from 0 at `start` to 1 at
    /// `end`. Points past either end take the nearest end's color, and
    /// lines perpendicular to the gradient have one color, so any angle
    /// works. Colors are straight-alpha, but they are interpolated
    /// premultiplied, as CSS does: a fade from white at 60% to `.clear`
    /// stays white as it fades instead of turning gray.
    public struct LinearGradient: Sendable {
        /// A color at a location along the gradient.
        public struct Stop: Sendable, Hashable {
            public var color: RGBA
            /// The position from 0 at the start point to 1 at the end point.
            public var location: Double

            public init(color: RGBA, location: Double) {
                self.color = color
                self.location = location
            }
        }

        /// The stops, sorted by location.
        public var stops: [Stop]
        /// Where location 0 is, in points.
        public var start: CGPoint
        /// Where location 1 is, in points.
        public var end: CGPoint

        /// A gradient through stops, from `start` to `end` in points.
        public init(stops: [Stop], start: CGPoint, end: CGPoint) {
            self.stops = stops.sorted { $0.location < $1.location }
            self.start = start
            self.end = end
        }

        /// A gradient through evenly spaced colors, from `start` to `end`
        /// in points.
        public init(colors: [RGBA], start: CGPoint, end: CGPoint) {
            let last = max(colors.count - 1, 1)
            self.init(
                stops: colors.enumerated().map {
                    Stop(color: $0.element, location: Double($0.offset) / Double(last))
                },
                start: start,
                end: end
            )
        }

        /// The color at a location, interpolated premultiplied.
        func color(at location: Double) -> RGBA {
            guard let first = stops.first, let last = stops.last else { return .clear }
            if location <= first.location { return first.color }
            if location >= last.location { return last.color }
            var upper = 1
            while stops[upper].location < location { upper += 1 }
            let a = stops[upper - 1]
            let b = stops[upper]
            let span = b.location - a.location
            let t = span > 0 ? (location - a.location) / span : 1
            let alphaA = Double(a.color.alpha)
            let alphaB = Double(b.color.alpha)
            let alpha = alphaA + (alphaB - alphaA) * t
            guard alpha > 0 else { return .clear }
            func channel(_ x: UInt8, _ y: UInt8) -> UInt8 {
                let premultiplied =
                    Double(x) * alphaA + (Double(y) * alphaB - Double(x) * alphaA) * t
                return UInt8(min(max((premultiplied / alpha).rounded(), 0), 255))
            }
            return RGBA(
                red: channel(a.color.red, b.color.red),
                green: channel(a.color.green, b.color.green),
                blue: channel(a.color.blue, b.color.blue),
                alpha: UInt8(min(max(alpha.rounded(), 0), 255))
            )
        }
    }

    /// Fills a path given in points with a linear gradient, with the
    /// even-odd rule when `evenOdd` is set and the nonzero rule otherwise.
    ///
    /// The path's coverage comes from the general rasterizer, and each
    /// covered pixel takes the gradient's color at its center.
    public mutating func fill(_ path: Path, gradient: LinearGradient, evenOdd: Bool = false) {
        guard !gradient.stops.isEmpty else { return }
        let pixelPath = path.applying(scaleX: scale, scaleY: scale, translateX: 0, translateY: 0)
        guard
            let coverage = Rasterizer.coverage(
                of: pixelPath.polygons(tolerance: 0.2),
                clip: pixelClip,
                evenOdd: evenOdd
            )
        else { return }
        composite(coverage, gradient: gradient)
    }

    /// Fills a rectangle given in points with a linear gradient.
    public mutating func fill(_ rect: CGRect, gradient: LinearGradient) {
        guard rect.width > 0, rect.height > 0 else { return }
        fill(Path(rect), gradient: gradient)
    }

    /// Fills a rectangle with rounded corners, given in points, with a linear
    /// gradient.
    ///
    /// Only the corners go through the general rasterizer, and the pixels
    /// the shape covers fully in a row are written as one run, so the cost
    /// is mostly one lookup and one store for each pixel.
    public mutating func fill(
        _ rect: CGRect, cornerRadius: CGFloat, style: Path.CornerStyle = .circular,
        gradient: LinearGradient
    ) {
        guard !gradient.stops.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let clip = pixelClip
        let box = PixelBox(
            minX: max(Int((Double(rect.minX) * scale).rounded(.down)), clip.minX),
            minY: max(Int((Double(rect.minY) * scale).rounded(.down)), clip.minY),
            maxX: min(Int((Double(rect.maxX) * scale).rounded(.up)), clip.maxX),
            maxY: min(Int((Double(rect.maxY) * scale).rounded(.up)), clip.maxY))
        guard !box.isEmpty else { return }
        let mask = CoverageMask(
            rect: rect, cornerRadius: cornerRadius, style: style, canvas: self, box: box)
        let lookup = GradientLookup(gradient, scale: scale)
        let width = width
        let mode = blendMode
        let opaque = mode == .normal
        pixels.withUnsafeMutableBufferPointer { bytes in
            let words = UnsafeMutableRawBufferPointer(bytes).bindMemory(to: UInt32.self)
            lookup.table.withUnsafeBufferPointer { table in
                lookup.words.withUnsafeBufferPointer { words16 in
                    let shared = Unshared((mask, lookup, bytes, words, table, words16))
                    // Every row writes its own pixels, so threads take rows of their own.
                    forEachRange(of: box.maxY - box.minY, minimum: 64) { rows in
                        let (mask, lookup, bytes, words, table, words16) = shared.value
                        for y in box.minY + rows.lowerBound..<box.minY + rows.upperBound {
                            let full = mask.fullSpan(y: y)
                            let rowStart = y &* width
                            var x = box.minX
                            while x < box.maxX {
                                if full.contains(x) {
                                    if opaque, lookup.isOpaque {
                                        // A fully covered opaque color replaces the
                                        // pixel, which is what blending it gives.
                                        var (index, step) = lookup.fixedIndex(
                                            column: full.lowerBound, row: y)
                                        for column in full {
                                            words[rowStart &+ column] =
                                                words16[min(max(index >> 16, 0), lookup.lastStep)]
                                            index &+= step
                                        }
                                    } else {
                                        for column in full {
                                            Self.blendQuickly(
                                                lookup.color(atColumn: column, row: y, in: table),
                                                1, mode, into: bytes, at: (rowStart &+ column) &* 4)
                                        }
                                    }
                                    x = full.upperBound
                                    continue
                                }
                                let amount = mask.coverage(x: x, y: y)
                                if amount > 0 {
                                    Self.blendQuickly(
                                        lookup.color(atColumn: x, row: y, in: table), amount, mode,
                                        into: bytes, at: (rowStart &+ x) &* 4)
                                }
                                x &+= 1
                            }
                        }
                    }
                }
            }
        }
    }

    /// Blends a gradient into the canvas, weighted by coverage.
    private mutating func composite(_ coverage: Coverage, gradient: LinearGradient) {
        // Locations are a linear function of the pixel center: they change
        // by `stepX` per column and `stepY` per row.
        let startX = Double(gradient.start.x) * scale
        let startY = Double(gradient.start.y) * scale
        let dx = Double(gradient.end.x) * scale - startX
        let dy = Double(gradient.end.y) * scale - startY
        let lengthSquared = dx * dx + dy * dy
        let stepX = lengthSquared > 0 ? dx / lengthSquared : 0
        let stepY = lengthSquared > 0 ? dy / lengthSquared : 0
        let width = width
        let mode = blendMode
        // Gradients are smooth, so the color is looked up in a table of
        // 1024 steps between the first and the last stop.
        let first = gradient.stops[0].location
        let span = gradient.stops[gradient.stops.count - 1].location - first
        let steps = span > 0 ? 1024 : 1
        let table = (0...steps).map {
            gradient.color(at: first + span * Double($0) / Double(steps))
        }
        let scaledSteps = Double(steps)
        let opaque = mode == .normal
        pixels.withUnsafeMutableBufferPointer { bytes in
            let words = UnsafeMutableRawBufferPointer(bytes).bindMemory(to: UInt32.self)
            coverage.values.withUnsafeBufferPointer { values in
                table.withUnsafeBufferPointer { table in
                    for row in 0..<coverage.height {
                        let y = Double(coverage.originY + row) + 0.5
                        let rowStart = ((coverage.originY + row) * width + coverage.originX) * 4
                        let valueStart = row * coverage.width
                        func color(atColumn column: Int) -> RGBA {
                            let x = Double(coverage.originX + column) + 0.5
                            let location = (x - startX) * stepX + (y - startY) * stepY
                            let position = span > 0 ? (location - first) / span : 0
                            return table[Int(min(max(position, 0), 1) * scaledSteps + 0.5)]
                        }
                        // A vertical gradient has one color per row.
                        let rowColor = stepX == 0 ? color(atColumn: 0) : nil
                        for column in 0..<coverage.width {
                            let amount = values[valueStart &+ column]
                            guard amount > 0 else { continue }
                            let source = rowColor ?? color(atColumn: column)
                            if opaque, amount >= 1, source.alpha == 255 {
                                // A fully covered opaque color replaces the
                                // pixel, which is what blending it gives.
                                words[(rowStart >> 2) &+ column] = source.packed
                                continue
                            }
                            Self.blendQuickly(
                                source, amount, mode, into: bytes,
                                at: rowStart &+ column &* 4)
                        }
                    }
                }
            }
        }
    }
}

/// A gradient's colors in a table of 1024 steps between its first and last
/// stop, looked up by pixel.
struct GradientLookup {
    let table: [RGBA]
    /// The table's colors as words whose bytes in memory are red, green,
    /// blue, and alpha.
    let words: [UInt32]
    /// Whether every color in the table is opaque.
    let isOpaque: Bool
    /// The index of the last color in the table.
    var lastStep: Int { Int(steps) }
    private let startX: Double
    private let startY: Double
    private let stepX: Double
    private let stepY: Double
    private let first: Double
    private let span: Double
    private let steps: Double

    init(_ gradient: Canvas.LinearGradient, scale: Double) {
        startX = Double(gradient.start.x) * scale
        startY = Double(gradient.start.y) * scale
        let dx = Double(gradient.end.x) * scale - startX
        let dy = Double(gradient.end.y) * scale - startY
        let lengthSquared = dx * dx + dy * dy
        stepX = lengthSquared > 0 ? dx / lengthSquared : 0
        stepY = lengthSquared > 0 ? dy / lengthSquared : 0
        first = gradient.stops[0].location
        span = gradient.stops[gradient.stops.count - 1].location - first
        // A step for each half pixel along the gradient is finer than the
        // eye tells, and a small shape would not use more of a bigger table.
        let length = lengthSquared.squareRoot() * span.magnitude
        let count = span > 0 ? min(1024, max(Int(length.rounded(.up)) * 2, 16)) : 1
        steps = Double(count)
        let first = first
        let span = span
        let table = (0...count).map {
            gradient.color(at: first + span * Double($0) / Double(count))
        }
        self.table = table
        words = table.map(\.packed)
        isOpaque = table.allSatisfy { $0.alpha == 255 }
    }

    /// The table index, times 65536 and rounded, at the center of a pixel,
    /// and its change from one column to the next.
    @inline(__always)
    func fixedIndex(column: Int, row: Int) -> (start: Int, step: Int) {
        let x = Double(column) + 0.5
        let y = Double(row) + 0.5
        let location = (x - startX) * stepX + (y - startY) * stepY
        let position = span > 0 ? (location - first) / span : 0
        let start = min(max(position, -8), 9) * steps + 0.5
        let step = span > 0 ? min(max(stepX / span * steps, -1e6), 1e6) : 0
        return (Int(start * 65536), Int(step * 65536))
    }

    /// The color of the pixel in a column and a row, from the table.
    @inline(__always)
    func color(atColumn column: Int, row: Int, in table: UnsafeBufferPointer<RGBA>) -> RGBA {
        let x = Double(column) + 0.5
        let y = Double(row) + 0.5
        let location = (x - startX) * stepX + (y - startY) * stepY
        let position = span > 0 ? (location - first) / span : 0
        return table[Int(min(max(position, 0), 1) * steps + 0.5)]
    }
}
