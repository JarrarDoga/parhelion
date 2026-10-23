#if canImport(Foundation)
import Foundation
#endif

// Reading and writing whole regions of a canvas, for renderers that keep
// drawing between frames. ParhelionUI uses these to reuse a glass surface,
// the screen beneath a presentation, and a fading presentation.

extension Canvas {
    /// How far past its shape, in pixels, `drawShadow` reads and changes
    /// pixels for a blur radius at a scale, before the offset.
    package static func shadowReach(blur: Double, scale: Double) -> Int {
        let kernel = BlurKernel(sigma: max(blur, 0) / 2 * scale)
        return kernel.pixelReach + kernel.factor
    }

    /// How far past its shape, in pixels, `blur` reads pixels for a blur
    /// radius at a scale.
    package static func blurReach(radius: Double, scale: Double) -> Int {
        let kernel = BlurKernel(sigma: max(radius, 0) / 2 * scale)
        return kernel.reach > 0 ? kernel.pixelReach : 0
    }

    /// The canvas's own pixels, as a box.
    package var bounds: PixelBox { PixelBox(minX: 0, minY: 0, maxX: width, maxY: height) }

    /// The pixels inside a box, row by row, as words whose bytes are red,
    /// green, blue, and alpha. The box must lie inside the canvas.
    package func pixels(in box: PixelBox) -> [UInt32] {
        let count = box.area
        guard count > 0 else { return [] }
        let rowLength = box.maxX - box.minX
        let width = width
        return [UInt32](unsafeUninitializedCapacity: count) { stored, initialized in
            pixels.withUnsafeBytes { raw in
                let words = raw.bindMemory(to: UInt32.self)
                for row in 0..<(box.maxY - box.minY) {
                    let start = (box.minY + row) * width + box.minX
                    _ = UnsafeMutableBufferPointer(
                        rebasing: stored[(row * rowLength)..<((row + 1) * rowLength)]
                    )
                    .initialize(from: words[start..<(start + rowLength)])
                }
            }
            initialized = count
        }
    }

    /// Whether the pixels inside a box are the ones `pixels(in:)` returned.
    package func pixels(in box: PixelBox, equal stored: [UInt32]) -> Bool {
        guard stored.count == box.area else { return false }
        guard !stored.isEmpty else { return true }
        let rowBytes = (box.maxX - box.minX) * 4
        let width = width
        return pixels.withUnsafeBytes { raw in
            stored.withUnsafeBytes { stored in
                for row in 0..<(box.maxY - box.minY) {
                    let start = raw.baseAddress! + ((box.minY + row) * width + box.minX) * 4
                    let kept = stored.baseAddress! + row * rowBytes
                    if memcmp(start, kept, rowBytes) != 0 { return false }
                }
                return true
            }
        }
    }

    /// Replaces the pixels inside a box with ones `pixels(in:)` returned.
    package mutating func replacePixels(in box: PixelBox, with stored: [UInt32]) {
        precondition(stored.count == box.area, "The pixels must fill the box.")
        guard !stored.isEmpty else { return }
        let rowLength = box.maxX - box.minX
        let width = width
        pixels.withUnsafeMutableBytes { raw in
            let words = raw.bindMemory(to: UInt32.self)
            stored.withUnsafeBufferPointer { stored in
                for row in 0..<(box.maxY - box.minY) {
                    let start = (box.minY + row) * width + box.minX
                    _ = UnsafeMutableBufferPointer(rebasing: words[start..<(start + rowLength)])
                        .update(from: stored[(row * rowLength)..<((row + 1) * rowLength)])
                }
            }
        }
    }

    /// A canvas of `base` with `layer` blended over it at an opacity, as
    /// one group: each pixel moves from the base's color toward the layer's
    /// by the opacity, in 4096ths. `layer` is normally `base` with more
    /// drawn over it, at full opacity. At opacity 1 the result is `layer`
    /// exactly, and at 0 it is `base`. Both must have the same size.
    package init(blending layer: Canvas, over base: Canvas, opacity: Double) {
        precondition(
            layer.width == base.width && layer.height == base.height,
            "A layer must have its base's size in pixels.")
        width = base.width
        height = base.height
        scale = base.scale
        let weight = Int32((min(max(opacity, 0), 1) * 4096).rounded())
        // The ends need no arithmetic.
        guard weight > 0 else {
            pixels = base.pixels
            return
        }
        guard weight < 4096 else {
            pixels = layer.pixels
            return
        }
        let count = base.pixels.count
        pixels = [UInt8](unsafeUninitializedCapacity: count) { blended, initialized in
            base.pixels.withUnsafeBufferPointer { base in
                layer.pixels.withUnsafeBufferPointer { layer in
                    for index in 0..<count {
                        let from = Int32(base[index])
                        let difference = Int32(layer[index]) &- from
                        blended[index] = UInt8(
                            truncatingIfNeeded: from &+ ((difference &* weight &+ 2048) >> 12))
                    }
                }
            }
            initialized = count
        }
    }
}
