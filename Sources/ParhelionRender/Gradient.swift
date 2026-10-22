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

    /// Fills a path given in points with a linear gradient.
    ///
    /// The path's coverage comes from the general rasterizer, and each
    /// covered pixel takes the gradient's color at its center.
    public mutating func fill(_ path: Path, gradient: LinearGradient) {
        guard !gradient.stops.isEmpty else { return }
        let pixelPath = path.applying(scaleX: scale, scaleY: scale, translateX: 0, translateY: 0)
        guard
            let coverage = Rasterizer.coverage(
                of: pixelPath.polygons(tolerance: 0.2),
                clip: pixelClip
            )
        else { return }
        composite(coverage, gradient: gradient)
    }

    /// Fills a rectangle given in points with a linear gradient.
    public mutating func fill(_ rect: CGRect, gradient: LinearGradient) {
        guard rect.width > 0, rect.height > 0 else { return }
        fill(Path(rect), gradient: gradient)
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
        pixels.withUnsafeMutableBufferPointer { bytes in
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
                            Self.blendQuickly(
                                rowColor ?? color(atColumn: column), amount, mode, into: bytes,
                                at: rowStart &+ column &* 4)
                        }
                    }
                }
            }
        }
    }
}
