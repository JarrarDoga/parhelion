#if canImport(Foundation)
import Foundation
#endif

// Clipping drawing to a path, and drawing on a layer of its own: the
// shadow of whatever a view draws, and a view drawn at another scale.

extension Canvas {
    /// The pixels a path clip keeps from ``beginClip(to:evenOdd:)`` until
    /// ``endClip(_:)``.
    public struct Clip: Sendable {
        let box: PixelBox
        let saved: [UInt32]
        let mask: CoverageMask?
        let outerClip: CGRect?
    }

    /// Starts limiting drawing to a path given in points, with the even-odd
    /// rule when `evenOdd` is set. Drawing until the matching
    /// ``endClip(_:)`` shows only inside the path, anti-aliased at its
    /// edge, and clips nest.
    ///
    /// The canvas keeps the pixels inside the path's bounds and limits
    /// drawing to those bounds meanwhile. `endClip(_:)` puts the kept
    /// pixels back outside the path and mixes them in at its edge, so the
    /// cost follows the size of the path, not of the canvas.
    public mutating func beginClip(to path: Path, evenOdd: Bool = false) -> Clip {
        guard let bounds = path.controlBounds, let box = clipBox(for: bounds) else {
            return emptyClip()
        }
        return beginClip(
            box, mask: CoverageMask(path: path, canvas: self, box: box, evenOdd: evenOdd))
    }

    /// Starts limiting drawing to a rounded rectangle given in points. See
    /// ``beginClip(to:evenOdd:)``. Only the corners are rasterized.
    public mutating func beginClip(
        to rect: CGRect, cornerRadius: CGFloat, style: Path.CornerStyle = .circular
    ) -> Clip {
        guard rect.width > 0, rect.height > 0, let box = clipBox(for: rect) else {
            return emptyClip()
        }
        return beginClip(
            box,
            mask: CoverageMask(
                rect: rect, cornerRadius: cornerRadius, style: style, canvas: self, box: box))
    }

    /// Ends a clip that ``beginClip(to:evenOdd:)`` started: the pixels
    /// outside its path take their old values again, and the clip
    /// rectangle is restored.
    public mutating func endClip(_ clip: Clip) {
        defer { clipRect = clip.outerClip }
        guard let mask = clip.mask, !clip.box.isEmpty else { return }
        let box = clip.box
        let rowLength = box.maxX - box.minX
        let width = width
        pixels.withUnsafeMutableBufferPointer { bytes in
            let words = UnsafeMutableRawBufferPointer(bytes).bindMemory(to: UInt32.self)
            clip.saved.withUnsafeBufferPointer { saved in
                for y in box.minY..<box.maxY {
                    let full = mask.fullSpan(y: y)
                    let row = y * width
                    let savedRow = (y - box.minY) * rowLength - box.minX
                    var x = box.minX
                    while x < box.maxX {
                        if full.contains(x) {
                            x = full.upperBound
                            continue
                        }
                        let coverage = mask.coverage(x: x, y: y)
                        if coverage <= 0 {
                            words[row + x] = saved[savedRow + x]
                        } else if coverage < 1 {
                            Self.mix(
                                saved[savedRow + x], toward: (row + x) * 4, by: coverage,
                                in: bytes)
                        }
                        x += 1
                    }
                }
            }
        }
    }

    /// The pixels inside a rectangle in points, within the clip, or `nil`
    /// if there are none.
    private func clipBox(for bounds: CGRect) -> PixelBox? {
        let clip = pixelClip
        let box = PixelBox(
            minX: max(Int((Double(bounds.minX) * scale).rounded(.down)), clip.minX),
            minY: max(Int((Double(bounds.minY) * scale).rounded(.down)), clip.minY),
            maxX: min(Int((Double(bounds.maxX) * scale).rounded(.up)), clip.maxX),
            maxY: min(Int((Double(bounds.maxY) * scale).rounded(.up)), clip.maxY))
        return box.isEmpty ? nil : box
    }

    private mutating func beginClip(_ box: PixelBox, mask: CoverageMask) -> Clip {
        let clip = Clip(box: box, saved: pixels(in: box), mask: mask, outerClip: clipRect)
        clipRect = CGRect(
            x: Double(box.minX) / scale, y: Double(box.minY) / scale,
            width: Double(box.maxX - box.minX) / scale,
            height: Double(box.maxY - box.minY) / scale)
        return clip
    }

    /// A clip that shows nothing, for an empty path.
    private mutating func emptyClip() -> Clip {
        let clip = Clip(
            box: PixelBox(minX: 0, minY: 0, maxX: 0, maxY: 0), saved: [], mask: nil,
            outerClip: clipRect)
        clipRect = .zero
        return clip
    }

    /// Moves the pixel at a byte offset from a kept color toward its
    /// current color by `amount` in `0...1`, mixing premultiplied colors
    /// when either is translucent.
    @inline(__always)
    private static func mix(
        _ kept: UInt32, toward index: Int, by amount: Float,
        in bytes: UnsafeMutableBufferPointer<UInt8>
    ) {
        let old = UInt32(littleEndian: kept)
        let oldRed = Int(old & 0xFF)
        let oldGreen = Int(old >> 8 & 0xFF)
        let oldBlue = Int(old >> 16 & 0xFF)
        let oldAlpha = Int(old >> 24)
        let weight = Int(amount * 4096 + 0.5)
        let newAlpha = Int(bytes[index + 3])
        if oldAlpha == 255, newAlpha == 255 {
            @inline(__always) func channel(_ from: Int, _ to: UInt8) -> UInt8 {
                UInt8(truncatingIfNeeded: from + (((Int(to) - from) * weight + 2048) >> 12))
            }
            bytes[index] = channel(oldRed, bytes[index])
            bytes[index + 1] = channel(oldGreen, bytes[index + 1])
            bytes[index + 2] = channel(oldBlue, bytes[index + 2])
            return
        }
        let alpha = oldAlpha * 4096 + (newAlpha - oldAlpha) * weight
        guard alpha > 0 else {
            bytes[index + 3] = 0
            return
        }
        @inline(__always) func channel(_ from: Int, _ to: UInt8) -> UInt8 {
            let premultiplied =
                from * oldAlpha * 4096 + (Int(to) * newAlpha - from * oldAlpha) * weight
            return UInt8(min(max((premultiplied + alpha / 2) / alpha, 0), 255))
        }
        bytes[index] = channel(oldRed, bytes[index])
        bytes[index + 1] = channel(oldGreen, bytes[index + 1])
        bytes[index + 2] = channel(oldBlue, bytes[index + 2])
        bytes[index + 3] = UInt8(min(max((alpha + 2048) >> 12, 0), 255))
    }

    // MARK: - Layers

    /// Blends a layer's pixels over the canvas, "source over", with the
    /// layer's first pixel at the canvas pixel `(x, y)`. `flipX` and
    /// `flipY` mirror the layer within the pixels it covers. Only pixels
    /// inside the clip change.
    public mutating func draw(
        layer: Canvas, atPixelX originX: Int, y originY: Int, flipX: Bool = false,
        flipY: Bool = false
    ) {
        let clip = pixelClip
        let minX = max(originX, clip.minX)
        let maxX = min(originX + layer.width, clip.maxX)
        let minY = max(originY, clip.minY)
        let maxY = min(originY + layer.height, clip.maxY)
        guard maxX > minX, maxY > minY else { return }
        let width = width
        let layerWidth = layer.width
        let layerHeight = layer.height
        pixels.withUnsafeMutableBufferPointer { bytes in
            let words = UnsafeMutableRawBufferPointer(bytes).bindMemory(to: UInt32.self)
            layer.pixels.withUnsafeBytes { raw in
                let source = raw.bindMemory(to: UInt32.self)
                for y in minY..<maxY {
                    let layerY = flipY ? layerHeight - 1 - (y - originY) : y - originY
                    let sourceRow = layerY * layerWidth
                    for x in minX..<maxX {
                        let layerX = flipX ? layerWidth - 1 - (x - originX) : x - originX
                        let word = source[sourceRow + layerX]
                        let alpha = UInt32(littleEndian: word) >> 24
                        if alpha == 0 { continue }
                        if alpha == 255 {
                            words[y * width + x] = word
                            continue
                        }
                        let color = UInt32(littleEndian: word)
                        Self.blend(
                            RGBA(
                                red: UInt8(color & 0xFF), green: UInt8(color >> 8 & 0xFF),
                                blue: UInt8(color >> 16 & 0xFF), alpha: UInt8(alpha)),
                            1, into: bytes, at: (y * width + x) * 4)
                    }
                }
            }
        }
    }

    /// Draws the blurred shadow of a layer's pixels, placed as
    /// ``draw(layer:atPixelX:y:flipX:flipY:)`` places them: their opacity,
    /// moved by `offset` in points and rounded to whole pixels, blurred
    /// with `blur` as design tools give it, a Gaussian with standard
    /// deviation `blur / 2`, and filled with `color`.
    ///
    /// Nothing cuts the shadow away under the layer, so it shows through
    /// the layer's translucent parts, as a Core Animation shadow does.
    public mutating func drawShadow(
        ofLayer layer: Canvas, atPixelX originX: Int, y originY: Int, color: RGBA,
        offset: CGSize, blur: Double
    ) {
        guard color.alpha > 0, layer.width > 0, layer.height > 0 else { return }
        let kernel = BlurKernel(sigma: max(blur, 0) / 2 * scale)
        let factor = kernel.factor
        let padding = kernel.pixelReach + factor
        let clip = pixelClip
        let shapeX = originX + Int((Double(offset.width) * scale).rounded())
        let shapeY = originY + Int((Double(offset.height) * scale).rounded())
        let minX = max(shapeX - padding, clip.minX - padding)
        let minY = max(shapeY - padding, clip.minY - padding)
        let maxX = min(shapeX + layer.width + padding, clip.maxX + padding)
        let maxY = min(shapeY + layer.height + padding, clip.maxY + padding)
        let visible = PixelBox(
            minX: max(minX, clip.minX), minY: max(minY, clip.minY), maxX: min(maxX, clip.maxX),
            maxY: min(maxY, clip.maxY))
        guard !visible.isEmpty, maxX > minX, maxY > minY else { return }

        // The layer's opacity, averaged into the blur's samples.
        let samplesWide = (maxX - minX + factor - 1) / factor
        let samplesHigh = (maxY - minY + factor - 1) / factor
        var mask = [Int32](repeating: 0, count: samplesWide * samplesHigh)
        let blockArea = Int32(factor * factor)
        layer.pixels.withUnsafeBufferPointer { source in
            for sampleY in 0..<samplesHigh {
                for sampleX in 0..<samplesWide {
                    var sum: Int32 = 0
                    for dy in 0..<factor {
                        let y = minY + sampleY * factor + dy - shapeY
                        guard y >= 0, y < layer.height else { continue }
                        for dx in 0..<factor {
                            let x = minX + sampleX * factor + dx - shapeX
                            guard x >= 0, x < layer.width else { continue }
                            sum += Int32(source[(y * layer.width + x) * 4 + 3]) * 255
                        }
                    }
                    mask[sampleY * samplesWide + sampleX] = sum / blockArea
                }
            }
        }
        kernel.apply(to: &mask, width: samplesWide, height: samplesHigh, channels: 1)

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
        let rowEntries = rows.entries
        let columnEntries = columns.entries
        var line = [Int](repeating: 0, count: samplesWide)
        pixels.withUnsafeMutableBufferPointer { bytes in
            for rowIndex in 0..<rows.count {
                let y = visible.minY + rowIndex
                let top = rowEntries[rowIndex * 3] * samplesWide
                let bottom = rowEntries[rowIndex * 3 + 1] * samplesWide
                let lowerWeight = rowEntries[rowIndex * 3 + 2]
                for index in 0..<samplesWide {
                    line[index] =
                        Int(mask[top + index]) * (256 - lowerWeight)
                        + Int(mask[bottom + index]) * lowerWeight
                }
                for columnIndex in 0..<columns.count {
                    let entry = columnIndex * 3
                    let rightWeight = columnEntries[entry + 2]
                    let value =
                        line[columnEntries[entry]] * (256 - rightWeight)
                        + line[columnEntries[entry + 1]] * rightWeight
                    guard value > faintest else { continue }
                    Self.blendQuickly(
                        color, Float(value) * unit, mode, into: bytes,
                        at: (y * width + visible.minX + columnIndex) * 4)
                }
            }
        }
    }
}
