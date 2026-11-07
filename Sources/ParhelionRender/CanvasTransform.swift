#if canImport(Foundation)
import Foundation
#endif

extension Canvas {
    /// Blends a layer's pixels over the canvas, rotated clockwise on the
    /// screen by an angle around a pivot, "source over". Without rotation,
    /// the layer's first pixel is at the canvas pixel `(x, y)`.
    ///
    /// The pivot is a position on the canvas, in pixels. Each canvas pixel
    /// the rotated layer covers takes its color from the four nearest layer
    /// pixels, weighted by their opacity, and pixels beyond the layer's edge
    /// count as transparent, so the rotated edges are anti-aliased. Only
    /// pixels inside the clip change.
    public mutating func draw(
        layer: Canvas, atPixelX originX: Int, y originY: Int, rotatedBy radians: Double,
        aroundX pivotX: Double, y pivotY: Double
    ) {
        guard layer.width > 0, layer.height > 0 else { return }
        let cosine = cos(radians)
        let sine = sin(radians)
        // The corners of the layer, rotated, bound the pixels that change.
        var low = (x: Double.infinity, y: Double.infinity)
        var high = (x: -Double.infinity, y: -Double.infinity)
        for corner in [
            (0.0, 0.0), (Double(layer.width), 0), (0, Double(layer.height)),
            (Double(layer.width), Double(layer.height)),
        ] {
            let relativeX = Double(originX) + corner.0 - pivotX
            let relativeY = Double(originY) + corner.1 - pivotY
            let x = pivotX + relativeX * cosine - relativeY * sine
            let y = pivotY + relativeX * sine + relativeY * cosine
            low = (min(low.x, x), min(low.y, y))
            high = (max(high.x, x), max(high.y, y))
        }
        let clip = pixelClip
        let minX = max(Int(low.x.rounded(.down)) - 1, clip.minX)
        let maxX = min(Int(high.x.rounded(.up)) + 1, clip.maxX)
        let minY = max(Int(low.y.rounded(.down)) - 1, clip.minY)
        let maxY = min(Int(high.y.rounded(.up)) + 1, clip.maxY)
        guard maxX > minX, maxY > minY else { return }

        let width = width
        let mode = blendMode
        let layerWidth = layer.width
        let layerHeight = layer.height
        pixels.withUnsafeMutableBufferPointer { bytes in
            layer.pixels.withUnsafeBufferPointer { source in
                for y in minY..<maxY {
                    for x in minX..<maxX {
                        // Where this pixel's center comes from in the layer,
                        // as a position between pixel centers.
                        let relativeX = Double(x) + 0.5 - pivotX
                        let relativeY = Double(y) + 0.5 - pivotY
                        let u =
                            pivotX + relativeX * cosine + relativeY * sine - Double(originX) - 0.5
                        let v =
                            pivotY - relativeX * sine + relativeY * cosine - Double(originY) - 0.5
                        let column = Int(u.rounded(.down))
                        let row = Int(v.rounded(.down))
                        guard column >= -1, column < layerWidth, row >= -1, row < layerHeight
                        else { continue }
                        let right = Float(u - Double(column))
                        let lower = Float(v - Double(row))
                        var red: Float = 0
                        var green: Float = 0
                        var blue: Float = 0
                        var alpha: Float = 0
                        @inline(__always) func accumulate(_ dx: Int, _ dy: Int, _ weight: Float) {
                            let sampleX = column + dx
                            let sampleY = row + dy
                            guard sampleX >= 0, sampleX < layerWidth, sampleY >= 0,
                                sampleY < layerHeight, weight > 0
                            else { return }
                            let index = (sampleY * layerWidth + sampleX) * 4
                            let opacity = Float(source[index + 3]) * weight
                            red += Float(source[index]) * opacity
                            green += Float(source[index + 1]) * opacity
                            blue += Float(source[index + 2]) * opacity
                            alpha += opacity
                        }
                        accumulate(0, 0, (1 - right) * (1 - lower))
                        accumulate(1, 0, right * (1 - lower))
                        accumulate(0, 1, (1 - right) * lower)
                        accumulate(1, 1, right * lower)
                        guard alpha > 0.5 else { continue }
                        Self.blend(
                            RGBA(
                                red: Self.byte(red / alpha), green: Self.byte(green / alpha),
                                blue: Self.byte(blue / alpha), alpha: Self.byte(alpha)),
                            1, mode, into: bytes, at: (y * width + x) * 4)
                    }
                }
            }
        }
    }

    /// Multiplies each pixel's opacity by the opacity of the pixel at the
    /// same place in `mask`, which must be the same size. The colors stay
    /// as they are, so what the mask hides is hidden, as a SwiftUI mask
    /// does with a view's alpha.
    public mutating func multiplyOpacity(by mask: Canvas) {
        precondition(
            mask.width == width && mask.height == height, "A mask must be as large as the canvas.")
        mask.pixels.withUnsafeBufferPointer { mask in
            pixels.withUnsafeMutableBufferPointer { bytes in
                for index in stride(from: 3, to: bytes.count, by: 4) {
                    let opacity = Int(mask[index])
                    if opacity == 255 { continue }
                    bytes[index] = UInt8((Int(bytes[index]) * opacity + 127) / 255)
                }
            }
        }
    }
}
