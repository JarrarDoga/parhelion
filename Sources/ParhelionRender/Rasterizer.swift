#if canImport(Foundation)
import Foundation
#endif

/// The anti-aliased coverage of a shape over a rectangle of pixels.
struct Coverage {
    /// The pixel rectangle the coverage spans.
    let originX: Int
    let originY: Int
    let width: Int
    let height: Int
    /// Coverage per pixel in `0...1`, row-major.
    let values: [Float]
}

/// Computes exact-area anti-aliased coverage for polygons.
///
/// Each edge adds the signed area it covers to an accumulation buffer, and a
/// running sum along each row turns those areas into coverage. Overlapping
/// shapes with the same winding direction add up and are clamped to full
/// coverage, so the result matches the nonzero fill rule for glyph outlines
/// and simple shapes. The approach follows Raph Levien's font-rs.
enum Rasterizer {
    /// Rasterizes polygons given in pixel coordinates, clipped to a
    /// `clipWidth` × `clipHeight` target. Returns `nil` if nothing is visible.
    static func coverage(of polygons: [[CGPoint]], clipWidth: Int, clipHeight: Int) -> Coverage? {
        coverage(of: polygons, clip: (0, 0, clipWidth, clipHeight))
    }

    /// Rasterizes polygons given in pixel coordinates, clipped to the pixel
    /// rectangle from `(minX, minY)` up to, not including, `(maxX, maxY)`.
    /// With `evenOdd`, a pixel inside an even number of outlines is empty,
    /// as with the even-odd fill rule; otherwise overlaps add up.
    static func coverage(
        of polygons: [[CGPoint]],
        clip: (minX: Int, minY: Int, maxX: Int, maxY: Int),
        evenOdd: Bool = false
    ) -> Coverage? {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for polygon in polygons {
            for point in polygon {
                minX = min(minX, Double(point.x))
                minY = min(minY, Double(point.y))
                maxX = max(maxX, Double(point.x))
                maxY = max(maxY, Double(point.y))
            }
        }
        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }

        let originX = max(Int(minX.rounded(.down)), clip.minX)
        let originY = max(Int(minY.rounded(.down)), clip.minY)
        let endX = min(Int(maxX.rounded(.up)), clip.maxX)
        let endY = min(Int(maxY.rounded(.up)), clip.maxY)
        guard endX > originX, endY > originY else { return nil }

        let width = endX - originX
        let height = endY - originY
        // Two extra columns per row absorb area that lands at the right edge.
        let stride = width + 2
        var accumulation = [Float](repeating: 0, count: stride * height)

        for polygon in polygons {
            for index in polygon.indices {
                let start = polygon[index]
                let end = polygon[(index + 1) % polygon.count]
                addLine(
                    from: (Double(start.x) - Double(originX), Double(start.y) - Double(originY)),
                    to: (Double(end.x) - Double(originX), Double(end.y) - Double(originY)),
                    width: width,
                    height: height,
                    stride: stride,
                    into: &accumulation
                )
            }
        }

        var values = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            var sum: Float = 0
            for column in 0..<width {
                sum += accumulation[row * stride + column]
                if evenOdd {
                    // Coverage folds back every two windings.
                    let folded = abs(sum).truncatingRemainder(dividingBy: 2)
                    values[row * width + column] = folded > 1 ? 2 - folded : folded
                } else {
                    values[row * width + column] = min(abs(sum), 1)
                }
            }
        }
        return Coverage(
            originX: originX,
            originY: originY,
            width: width,
            height: height,
            values: values
        )
    }

    /// Adds the signed area to the right of one edge to the accumulation
    /// buffer. Coordinates are relative to the coverage origin.
    private static func addLine(
        from start: (x: Double, y: Double),
        to end: (x: Double, y: Double),
        width: Int,
        height: Int,
        stride: Int,
        into accumulation: inout [Float]
    ) {
        guard start.y != end.y else { return }
        let direction: Float = start.y < end.y ? 1 : -1
        let top = start.y < end.y ? start : end
        let bottom = start.y < end.y ? end : start
        let maxX = Double(width)
        let dxdy = (bottom.x - top.x) / (bottom.y - top.y)

        var x = top.x
        if top.y < 0 { x -= top.y * dxdy }
        let firstRow = max(Int(top.y.rounded(.down)), 0)
        let lastRow = min(Int(bottom.y.rounded(.up)), height)
        guard firstRow < lastRow else { return }

        for row in firstRow..<lastRow {
            let rowTop = max(Double(row), top.y)
            let rowBottom = min(Double(row + 1), bottom.y)
            let dy = rowBottom - rowTop
            let nextX = x + dxdy * dy
            let delta = Float(dy) * direction

            // Area to the left of the canvas still counts, at column 0; area
            // to the right of it is dropped.
            let x0 = min(max(min(x, nextX), 0), maxX)
            let x1 = min(max(max(x, nextX), 0), maxX)
            let rowStart = row * stride
            let x0Floor = x0.rounded(.down)
            let x0Index = Int(x0Floor)
            let x1Ceil = x1.rounded(.up)
            let x1Index = Int(x1Ceil)

            if x1Index <= x0Index + 1 {
                // The edge stays within one pixel column in this row.
                let middle = Float(0.5 * (x0 + x1) - x0Floor)
                accumulation[rowStart + x0Index] += delta - delta * middle
                accumulation[rowStart + x0Index + 1] += delta * middle
            } else {
                let inverseSpan = Float(1 / (x1 - x0))
                let x0Fraction = Float(x0 - x0Floor)
                let firstArea = 0.5 * inverseSpan * (1 - x0Fraction) * (1 - x0Fraction)
                let x1Fraction = Float(x1 - x1Ceil + 1)
                let lastArea = 0.5 * inverseSpan * x1Fraction * x1Fraction
                accumulation[rowStart + x0Index] += delta * firstArea
                if x1Index == x0Index + 2 {
                    accumulation[rowStart + x0Index + 1] += delta * (1 - firstArea - lastArea)
                } else {
                    let secondArea = inverseSpan * (1.5 - x0Fraction)
                    accumulation[rowStart + x0Index + 1] += delta * (secondArea - firstArea)
                    for column in (x0Index + 2)..<(x1Index - 1) {
                        accumulation[rowStart + column] += delta * inverseSpan
                    }
                    let beforeLast = secondArea + Float(x1Index - x0Index - 3) * inverseSpan
                    accumulation[rowStart + x1Index - 1] += delta * (1 - beforeLast - lastArea)
                }
                accumulation[rowStart + x1Index] += delta * lastArea
            }
            x = nextX
        }
    }
}
