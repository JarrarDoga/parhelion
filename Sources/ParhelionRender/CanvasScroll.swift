#if canImport(Foundation)
import Foundation
#endif

// Moving rows of pixels, for a renderer that draws a scrolled view by moving
// what it drew in the last frame and drawing only what is new.

extension Canvas {
    /// The pixels a clip rectangle covers, rounded the
    /// way ``pixelClip`` rounds, within the canvas.
    package func pixelBox(clippedTo clip: CGRect) -> PixelBox {
        PixelBox(
            minX: max(Int((Double(clip.minX) * scale).rounded()), 0),
            minY: max(Int((Double(clip.minY) * scale).rounded()), 0),
            maxX: min(Int((Double(clip.maxX) * scale).rounded()), width),
            maxY: min(Int((Double(clip.maxY) * scale).rounded()), height)
        )
    }

    /// The clip rectangle, in points, that limits drawing to a box.
    package func clipRect(for box: PixelBox) -> CGRect {
        CGRect(
            x: Double(box.minX) / scale, y: Double(box.minY) / scale,
            width: Double(box.maxX - box.minX) / scale,
            height: Double(box.maxY - box.minY) / scale)
    }

    /// The pixel every pixel in the box is, or `nil` when they differ. The
    /// box must lie inside the canvas.
    package func uniformPixel(in box: PixelBox) -> UInt32? {
        guard !box.isEmpty else { return nil }
        let width = width
        return pixels.withUnsafeBytes { raw -> UInt32? in
            let base = raw.baseAddress!
            let first = base.loadUnaligned(
                fromByteOffset: (box.minY * width + box.minX) * 4, as: UInt32.self)
            let same = SIMD8<UInt32>(repeating: first)
            let length = box.maxX - box.minX
            let height = box.maxY - box.minY
            // Each thread reports whether its rows are all the same.
            var results = [Bool](repeating: true, count: 8)
            results.withUnsafeMutableBufferPointer { results in
                let shared = Unshared((base, results.baseAddress!))
                forEachRange(of: height, minimum: 128) { rows in
                    let (base, results) = shared.value
                    var uniform = true
                    scan: for y in box.minY + rows.lowerBound..<box.minY + rows.upperBound {
                        let row = base + (y * width + box.minX) * 4
                        var x = 0
                        while x &+ 8 <= length {
                            let words = row.loadUnaligned(
                                fromByteOffset: x &* 4, as: SIMD8<UInt32>.self)
                            if !all(words .== same) {
                                uniform = false
                                break scan
                            }
                            x &+= 8
                        }
                        while x < length {
                            if row.loadUnaligned(fromByteOffset: x &* 4, as: UInt32.self) != first {
                                uniform = false
                                break scan
                            }
                            x &+= 1
                        }
                    }
                    if !uniform { results[rows.lowerBound * 8 / max(height, 1)] = false }
                }
            }
            return results.allSatisfy { $0 } ? first : nil
        }
    }

    /// Copies the pixels inside a box into `words`, row by row, reusing its
    /// storage when it is the right size. The box must lie inside the canvas.
    package func copyPixels(in box: PixelBox, into words: inout [UInt32]) {
        let count = box.area
        if words.count != count {
            words = [UInt32](repeating: 0, count: count)
        }
        guard count > 0 else { return }
        let width = width
        let rowLength = box.maxX - box.minX
        pixels.withUnsafeBytes { source in
            words.withUnsafeMutableBytes { target in
                let shared = Unshared((source.baseAddress!, target.baseAddress!))
                forEachRange(of: box.maxY - box.minY, minimum: 128) { rows in
                    let (source, target) = shared.value
                    for row in rows {
                        memcpy(
                            target + row * rowLength * 4,
                            source + ((box.minY + row) * width + box.minX) * 4, rowLength * 4)
                    }
                }
            }
        }
    }

    /// Sets every pixel in the box to a word, as is, without blending. The
    /// box must lie inside the canvas.
    package mutating func fill(_ box: PixelBox, pixel word: UInt32) {
        guard !box.isEmpty else { return }
        let width = width
        pixels.withUnsafeMutableBytes { raw in
            let words = raw.bindMemory(to: UInt32.self)
            for y in box.minY..<box.maxY {
                let start = y * width + box.minX
                UnsafeMutableBufferPointer(rebasing: words[start..<(start + box.maxX - box.minX)])
                    .update(repeating: word)
            }
        }
    }

    /// Sets the pixels inside a box to pixels that `copyPixels(in:into:)`
    /// copied from the same box, moved down by `rows` (up when negative).
    /// Pixels whose source is outside the box are left as they are.
    package mutating func replacePixels(
        in box: PixelBox, with words: [UInt32], movedDownBy rows: Int
    ) {
        precondition(words.count == box.area)
        guard !box.isEmpty else { return }
        let width = width
        let height = box.maxY - box.minY
        let rowLength = box.maxX - box.minX
        let first = max(0, rows)
        let last = min(height, height + rows)
        guard first < last else { return }
        pixels.withUnsafeMutableBytes { target in
            words.withUnsafeBytes { source in
                let shared = Unshared((target.baseAddress!, source.baseAddress!))
                forEachRange(of: last - first, minimum: 128) { chunk in
                    let (target, source) = shared.value
                    for row in first + chunk.lowerBound..<first + chunk.upperBound {
                        memcpy(
                            target + ((box.minY + row) * width + box.minX) * 4,
                            source + (row - rows) * rowLength * 4, rowLength * 4)
                    }
                }
            }
        }
    }
}
