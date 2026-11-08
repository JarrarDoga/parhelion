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

    /// Starts keeping the pixels outside a path given in points, with the
    /// nonzero rule: ``endClip(_:)`` puts them back, so whatever is drawn
    /// meanwhile shows only inside the path. Unlike
    /// ``beginClip(to:evenOdd:)``, drawing is not limited to the path's
    /// bounds, so this cuts a shape out of drawing that reaches past it.
    public mutating func beginKeeping(outside path: Path) -> Clip {
        let outerClip = clipRect
        let clip = beginClip(to: path)
        clipRect = outerClip
        return Clip(box: clip.box, saved: clip.saved, mask: clip.mask, outerClip: outerClip)
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
                let shared = Unshared((bytes, words, source))
                // Each row changes only its own pixels.
                forEachRange(of: maxY - minY, minimum: 64) { rows in
                    let (bytes, words, source) = shared.value
                    for y in minY + rows.lowerBound..<minY + rows.upperBound {
                        let layerY = flipY ? layerHeight - 1 - (y - originY) : y - originY
                        let sourceRow = layerY * layerWidth
                        var x = minX
                        if !flipX {
                            // Four opaque pixels are copied at a time.
                            let from = UnsafeRawPointer(source.baseAddress! + sourceRow - originX)
                            let to = UnsafeMutableRawPointer(words.baseAddress! + y * width)
                            while x &+ 4 <= maxX {
                                let four = from.loadUnaligned(
                                    fromByteOffset: x &* 4, as: SIMD4<UInt32>.self)
                                if all((four &>> 24) .== 255) {
                                    to.storeBytes(
                                        of: four, toByteOffset: x &* 4, as: SIMD4<UInt32>.self)
                                    x &+= 4
                                    continue
                                }
                                if all(four .== 0) {
                                    x &+= 4
                                    continue
                                }
                                for _ in 0..<4 {
                                    Self.draw(
                                        source[sourceRow &+ x &- originX], at: y &* width &+ x,
                                        words: words, bytes: bytes)
                                    x &+= 1
                                }
                            }
                        }
                        while x < maxX {
                            let layerX = flipX ? layerWidth - 1 - (x - originX) : x - originX
                            Self.draw(
                                source[sourceRow + layerX], at: y &* width &+ x, words: words,
                                bytes: bytes)
                            x &+= 1
                        }
                    }
                }
            }
        }
    }

    /// Draws one pixel of a layer over the pixel at an index.
    @inline(__always)
    private static func draw(
        _ word: UInt32, at index: Int, words: UnsafeMutableBufferPointer<UInt32>,
        bytes: UnsafeMutableBufferPointer<UInt8>
    ) {
        let color = UInt32(littleEndian: word)
        let alpha = color >> 24
        if alpha == 0 { return }
        if alpha == 255 {
            words[index] = word
            return
        }
        blend(
            RGBA(
                red: UInt8(color & 0xFF), green: UInt8(color >> 8 & 0xFF),
                blue: UInt8(color >> 16 & 0xFF), alpha: UInt8(alpha)),
            1, into: bytes, at: index * 4)
    }

    /// Draws the blurred shadow of a layer's pixels, placed as
    /// ``draw(layer:atPixelX:y:flipX:flipY:)`` places them: their opacity,
    /// moved by `offset` in points and rounded to whole pixels, blurred
    /// with `blur` as design tools give it, a Gaussian with standard
    /// deviation `blur / 2`, and filled with `color`.
    ///
    /// Nothing cuts the shadow away under the layer, so it shows through
    /// the layer's translucent parts, as a Core Animation shadow does.
    ///
    /// When `skipsUnderOpaque` is set, the caller draws the layer over the
    /// shadow at the same place right after, as it does for a shadow modifier,
    /// so the shadow is not drawn where the layer's pixels are opaque, and
    /// the result is the same.
    public mutating func drawShadow(
        ofLayer layer: Canvas, atPixelX originX: Int, y originY: Int, color: RGBA,
        offset: CGSize, blur: Double, skipsUnderOpaque: Bool = false
    ) {
        guard color.alpha > 0, layer.width > 0, layer.height > 0 else { return }
        let kernel = BlurKernel(sigma: max(blur, 0) / 2 * scale)
        let factor = kernel.factor
        let padding = kernel.pixelReach + factor
        let clip = pixelClip
        let shapeX = originX + Int((Double(offset.width) * scale).rounded())
        let shapeY = originY + Int((Double(offset.height) * scale).rounded())
        let minX = Self.sampleOrigin(shapeX - padding, limit: clip.minX - padding, factor: factor)
        let minY = Self.sampleOrigin(shapeY - padding, limit: clip.minY - padding, factor: factor)
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
            let layerWidth = layer.width
            let layerHeight = layer.height
            mask.withUnsafeMutableBufferPointer { mask in
                let shared = Unshared((source, mask.baseAddress!))
                // Each row of samples is averaged on its own.
                forEachRange(of: samplesHigh, minimum: 24) { sampleRows in
                    let (source, mask) = shared.value
                    for sampleY in sampleRows {
                        let firstY = minY + sampleY * factor - shapeY
                        let firstRow = max(firstY, 0)
                        let endRow = min(firstY + factor, layerHeight)
                        guard firstRow < endRow else { continue }
                        for sampleX in 0..<samplesWide {
                            let firstX = minX + sampleX * factor - shapeX
                            let firstColumn = max(firstX, 0)
                            let endColumn = min(firstX + factor, layerWidth)
                            guard firstColumn < endColumn else { continue }
                            var sum: Int32 = 0
                            for y in firstRow..<endRow {
                                let row = y &* layerWidth
                                for x in firstColumn..<endColumn {
                                    sum &+= Int32(source[(row &+ x) &* 4 &+ 3])
                                }
                            }
                            mask[sampleY * samplesWide + sampleX] = sum * 255 / blockArea
                        }
                    }
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

        // The samples that change a pixel by half a level or more, and the
        // pixels that read them. The tail of a wide shadow is skipped.
        let threshold = Int32(32_512 / Int(color.alpha))
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

        let interpolation = ShadowColumns(columns)
        let lefts = interpolation.lefts
        let rights = interpolation.rights
        let weights = interpolation.weights
        let (scale, maximumWeight) = Self.shadowWeights(for: color)
        let rowEntries = rows.entries
        let skipsOpaque = skipsUnderOpaque && mode == .normal
        let layerWidth = layer.width
        let layerHeight = layer.height
        layer.pixels.withUnsafeBytes { layerBytes in
            let layerWords = layerBytes.bindMemory(to: UInt32.self)
            pixels.withUnsafeMutableBufferPointer { bytes in
                let words = UnsafeMutableRawBufferPointer(bytes).bindMemory(to: UInt32.self)
                mask.withUnsafeBufferPointer { mask in
                    lefts.withUnsafeBufferPointer { lefts in
                        rights.withUnsafeBufferPointer { rights in
                            weights.withUnsafeBufferPointer { weights in
                                let shared = Unshared(
                                    (bytes, words, mask, lefts, rights, weights, layerWords))
                                // Each row blends into its own pixels, so threads take
                                // rows of their own.
                                forEachRange(of: rowRange.count, minimum: 48) { chunk in
                                    let (bytes, words, mask, lefts, rights, weights, layerWords) =
                                        shared.value
                                    var line = [Int32](repeating: 0, count: samplesWide)
                                    line.withUnsafeMutableBufferPointer { line in
                                        for offset in chunk {
                                            let rowIndex = rowRange.lowerBound + offset
                                            let y = visible.minY + rowIndex
                                            let top = rowEntries[rowIndex * 3] * samplesWide
                                            let bottom = rowEntries[rowIndex * 3 + 1] * samplesWide
                                            let lowerWeight = Int32(rowEntries[rowIndex * 3 + 2])
                                            // Between two sample rows, in `0...65_025`.
                                            for index in 0..<samplesWide {
                                                line[index] =
                                                    (mask[top &+ index] &* (256 &- lowerWeight)
                                                        &+ mask[bottom &+ index] &* lowerWeight)
                                                    >> 8
                                            }
                                            // Where the layer is opaque, it covers the shadow.
                                            var ranges = [columnRange]
                                            let layerRow = y - originY
                                            if skipsOpaque, layerRow >= 0, layerRow < layerHeight,
                                                let run = Self.opaqueRun(
                                                    in: UnsafeBufferPointer(
                                                        rebasing: layerWords[
                                                            layerRow * layerWidth..<(layerRow + 1)
                                                                * layerWidth]))
                                            {
                                                // The row's pixels are blended in groups of four from
                                                // its first, and the same pixels must share a group
                                                // as when none is skipped, which rounds alike. A
                                                // group that holds a pixel outside the run is not
                                                // skipped.
                                                let first = columnRange.lowerBound
                                                let low =
                                                    first
                                                    + (originX + run.lowerBound - visible.minX
                                                        - first + 3) / 4 * 4
                                                let high =
                                                    first
                                                    + (originX + run.upperBound - visible.minX
                                                        - first) / 4 * 4
                                                let leftEnd = max(
                                                    min(low, columnRange.upperBound), first)
                                                let rightStart = min(
                                                    max(high, first), columnRange.upperBound)
                                                let before = first..<leftEnd
                                                let after = rightStart..<columnRange.upperBound
                                                ranges = [before, after]
                                            }
                                            for columns in ranges where !columns.isEmpty {
                                                Self.blendShadowRow(
                                                    color, mode: mode, scale: scale,
                                                    maximumWeight: maximumWeight, columns: columns,
                                                    rowStart: y &* width &+ visible.minX,
                                                    words: words, bytes: bytes, line: line,
                                                    lefts: lefts, rights: rights, weights: weights)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The first run of opaque pixels in a row of a layer, or `nil` when there
    /// is none. It is a run, not all the row's opaque pixels: later ones are
    /// shadowed as usual.
    static func opaqueRun(in row: UnsafeBufferPointer<UInt32>) -> Range<Int>? {
        let count = row.count
        var start = 0
        while start < count, row[start] >> 24 != 255 { start += 1 }
        guard start < count else { return nil }
        var end = start
        let opaque = SIMD8<UInt32>(repeating: 255)
        let base = UnsafeRawPointer(row.baseAddress!)
        while end &+ 8 <= count {
            let words = base.loadUnaligned(fromByteOffset: end &* 4, as: SIMD8<UInt32>.self)
            guard all((words &>> 24) .== opaque) else { break }
            end &+= 8
        }
        while end < count, row[end] >> 24 == 255 { end += 1 }
        return start..<end
    }

    /// What turns a coverage into a weight in 4096ths for a color: the
    /// factor, and the most the weight can be.
    static func shadowWeights(for color: RGBA) -> (scale: Int32, maximum: Int32) {
        // A value in `0...16_646_400` is full coverage. Its weight in 4096ths
        // is that times the color's opacity, over 65,025 × 256.
        (
            Int32(
                (Double(color.alpha) * (4096.0 / 255.0) * 65_536.0 / Double(BlurKernel.one))
                    .rounded()),
            Int32(Float(color.alpha) * (4096 / 255) + 0.5)
        )
    }

    /// Blends a shadow's color into a run of one row, where each pixel's
    /// coverage is interpolated between two samples of `line`. Four pixels
    /// at a time are blended over opaque pixels with integer vectors, and
    /// the rest through `blendQuickly`.
    static func blendShadowRow(
        _ color: RGBA, mode: BlendMode, scale: Int32, maximumWeight: Int32, columns: Range<Int>,
        rowStart: Int, words: UnsafeMutableBufferPointer<UInt32>,
        bytes: UnsafeMutableBufferPointer<UInt8>, line: UnsafeMutableBufferPointer<Int32>,
        lefts: UnsafeBufferPointer<Int>, rights: UnsafeBufferPointer<Int>,
        weights: UnsafeBufferPointer<Int32>
    ) {
        func coverage(of column: Int) -> Int32 {
            line[lefts[column]] &* (256 &- weights[column]) &+ line[rights[column]]
                &* weights[column]
        }
        func blendOne(_ column: Int) {
            let value = coverage(of: column)
            guard value > 0 else { return }
            blendQuickly(
                color, Float(value) / 16_646_400, mode, into: bytes,
                at: (rowStart &+ column) &* 4)
        }
        var column = columns.lowerBound
        let end = columns.upperBound
        if mode == .normal {
            let red = SIMD4<Int32>(repeating: Int32(color.red))
            let green = SIMD4<Int32>(repeating: Int32(color.green))
            let blue = SIMD4<Int32>(repeating: Int32(color.blue))
            let scaleVector = SIMD4<Int32>(repeating: scale)
            let limit = SIMD4<Int32>(repeating: maximumWeight)
            let round = SIMD4<Int32>(repeating: 2048)
            let channelMask = SIMD4<UInt32>(repeating: 0xFF)
            let opaque = SIMD4<UInt32>(repeating: 0xFF00_0000)
            let pointer = UnsafeMutableRawPointer(words.baseAddress! + rowStart)
            while column &+ 4 <= end {
                let left = SIMD4<Int32>(
                    line[lefts[column]], line[lefts[column &+ 1]], line[lefts[column &+ 2]],
                    line[lefts[column &+ 3]])
                let right = SIMD4<Int32>(
                    line[rights[column]], line[rights[column &+ 1]], line[rights[column &+ 2]],
                    line[rights[column &+ 3]])
                let weight = UnsafeRawPointer(weights.baseAddress! + column)
                    .loadUnaligned(as: SIMD4<Int32>.self)
                let value = left &* (256 &- weight) &+ right &* weight
                var amount = ((value &>> 8) &* scaleVector &+ 32_768) &>> 16
                amount.replace(with: limit, where: amount .> limit)
                if all(amount .== 0) {
                    column &+= 4
                    continue
                }
                let old = pointer.loadUnaligned(fromByteOffset: column &* 4, as: SIMD4<UInt32>.self)
                guard all((old &>> 24) .== 255) else {
                    for offset in 0..<4 { blendOne(column &+ offset) }
                    column &+= 4
                    continue
                }
                let oldRed = SIMD4<Int32>(truncatingIfNeeded: old & channelMask)
                let oldGreen = SIMD4<Int32>(truncatingIfNeeded: (old &>> 8) & channelMask)
                let oldBlue = SIMD4<Int32>(truncatingIfNeeded: (old &>> 16) & channelMask)
                let newRed = oldRed &+ (((red &- oldRed) &* amount &+ round) &>> 12)
                let newGreen = oldGreen &+ (((green &- oldGreen) &* amount &+ round) &>> 12)
                let newBlue = oldBlue &+ (((blue &- oldBlue) &* amount &+ round) &>> 12)
                let result =
                    SIMD4<UInt32>(truncatingIfNeeded: newRed)
                    | (SIMD4<UInt32>(truncatingIfNeeded: newGreen) &<< 8)
                    | (SIMD4<UInt32>(truncatingIfNeeded: newBlue) &<< 16) | opaque
                pointer.storeBytes(of: result, toByteOffset: column &* 4, as: SIMD4<UInt32>.self)
                column &+= 4
            }
        }
        while column < end {
            blendOne(column)
            column &+= 1
        }
    }
}

/// How each pixel along a row reads the samples of a blurred shadow, in
/// separate arrays.
struct ShadowColumns {
    let lefts: [Int]
    let rights: [Int]
    let weights: [Int32]

    init(_ resampling: BlurKernel.Resampling) {
        let count = resampling.count
        var lefts = [Int](repeating: 0, count: count)
        var rights = [Int](repeating: 0, count: count)
        var weights = [Int32](repeating: 0, count: count)
        for index in 0..<count {
            lefts[index] = resampling.entries[index * 3]
            rights[index] = resampling.entries[index * 3 + 1]
            weights[index] = Int32(resampling.entries[index * 3 + 2])
        }
        self.lefts = lefts
        self.rights = rights
        self.weights = weights
    }
}
