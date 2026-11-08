import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// What a scroll edge effect draws: a blur of the content under a bar, and
/// either a fade or a cover with a dividing line.
struct ScrollEdgeEffect: Hashable {
    enum Kind: Hashable {
        /// A heavy blur whose strength fades from `peak` at the outer edge
        /// of the screen to nothing at the inner edge.
        case soft(peak: Double)
        /// A light blur under a nearly opaque `tint`, with a hairline in
        /// `line` along the inner edge.
        case hard(tint: RGBA, line: RGBA)
    }

    var kind: Kind
    /// The blur radius, as design tools give it.
    var blurRadius: Double
    /// Whether the effect is at the top of the screen. At the bottom, it is
    /// mirrored.
    var atTop: Bool
}

/// The colors of the hard style in an appearance.
struct HardScrollEdge: Hashable {
    var tint: RGBA
    var line: RGBA
}

extension Canvas {
    /// Draws a scroll edge effect over a rectangle in points, reading and
    /// changing only the pixels `scrollEdgeRegion` names.
    ///
    /// The effect blurs only what is inside the rectangle, repeating its
    /// edge pixels, as a backdrop blur does. Both styles are smooth, so the
    /// blur runs on the rectangle's pixels averaged into blocks, and its
    /// result is resampled bilinearly while it is mixed with the tint or
    /// with the original pixels: the cost follows the number of pixels in
    /// the rectangle, a few operations each, not a full blur of them.
    mutating func drawScrollEdge(_ effect: ScrollEdgeEffect, in rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        readsSurroundings = true
        let box = scrollEdgeRegion(effect, in: rect)
        guard !box.isEmpty else { return }
        let before = pixels(in: box)
        // The hard style's blur shows through a nearly opaque cover, so it
        // runs on coarser blocks than the soft style's.
        var blockDivisor = 4.0
        if case .hard = effect.kind { blockDivisor = 1.5 }
        let blurred = blurredPixels(
            before, box: box, radius: effect.blurRadius, blockDivisor: blockDivisor)
        let columns = box.maxX - box.minX
        let rows = box.maxY - box.minY
        var result = blurred
        switch effect.kind {
        case .hard(let tint, _):
            // The tint over the blur: an opaque color mixed in by its alpha.
            let word =
                UInt32(tint.red) | UInt32(tint.green) << 8 | UInt32(tint.blue) << 16
                | 0xFF00_0000
            let cover = (Int(tint.alpha) * 256 + 127) / 255
            result.withUnsafeMutableBufferPointer { result in
                let shared = Unshared(result.baseAddress!)
                forEachRange(of: rows, minimum: 64) { range in
                    let result = shared.value
                    for index in range.lowerBound * columns..<range.upperBound * columns {
                        result[index] = Self.mix(result[index], word, cover)
                    }
                }
            }
        case .soft(let peak):
            // The blur is mixed back with the pixels it replaced by a
            // weight that falls from `peak` at the outer edge to 0 at the
            // inner edge, which is what a gradient mask over the blur does.
            let atTop = effect.atTop
            result.withUnsafeMutableBufferPointer { result in
                before.withUnsafeBufferPointer { before in
                    let shared = Unshared((result.baseAddress!, before))
                    forEachRange(of: rows, minimum: 64) { range in
                        let (result, before) = shared.value
                        for row in range {
                            // 0 at the outer edge, 1 at the inner edge.
                            let along = (Double(row) + 0.5) / Double(rows)
                            let weight = Int(
                                (peak * (atTop ? 1 - along : along) * 256).rounded())
                            for index in row * columns..<(row + 1) * columns {
                                result[index] = Self.mix(before[index], result[index], weight)
                            }
                        }
                    }
                }
            }
        }
        replacePixels(in: box, with: result)
        if case .hard(_, let line) = effect.kind {
            let width = ColorPalette.hardScrollEdgeLineWidth
            let outerBlend = blendMode
            blendMode = .normal
            fill(
                CGRect(
                    x: rect.minX, y: effect.atTop ? rect.maxY - width : rect.minY,
                    width: rect.width, height: width),
                color: line)
            blendMode = outerBlend
        }
    }

    /// The pixels of a box blurred with a radius in points, as design tools
    /// give it, repeating the box's edges.
    private func blurredPixels(
        _ words: [UInt32], box: PixelBox, radius: Double, blockDivisor: Double
    ) -> [UInt32] {
        let columns = box.maxX - box.minX
        let rows = box.maxY - box.minY
        let sigma = radius / 2 * scale
        let factor = max(2, Int(sigma / blockDivisor))
        let smallColumns = (columns + factor - 1) / factor
        let smallRows = (rows + factor - 1) / factor

        // Average each block of pixels into one.
        var small = [UInt32](repeating: 0, count: smallColumns * smallRows)
        words.withUnsafeBufferPointer { words in
            small.withUnsafeMutableBufferPointer { small in
                for smallRow in 0..<smallRows {
                    let firstRow = smallRow * factor
                    let lastRow = min(firstRow + factor, rows)
                    for smallColumn in 0..<smallColumns {
                        let firstColumn = smallColumn * factor
                        let lastColumn = min(firstColumn + factor, columns)
                        var red: UInt32 = 0
                        var green: UInt32 = 0
                        var blue: UInt32 = 0
                        var alpha: UInt32 = 0
                        for row in firstRow..<lastRow {
                            let base = row * columns
                            for index in base + firstColumn..<base + lastColumn {
                                let word = words[index]
                                red &+= word & 0xFF
                                green &+= (word >> 8) & 0xFF
                                blue &+= (word >> 16) & 0xFF
                                alpha &+= word >> 24
                            }
                        }
                        let count = UInt32((lastRow - firstRow) * (lastColumn - firstColumn))
                        small[smallRow * smallColumns + smallColumn] =
                            (red / count) | (green / count) << 8 | (blue / count) << 16
                            | (alpha / count) << 24
                    }
                }
            }
        }

        // Blur the blocks with the canvas's own blur.
        var canvas = Canvas(
            width: Double(smallColumns), height: Double(smallRows), scale: 1,
            background: RGBA(red: 0, green: 0, blue: 0, alpha: 0))
        canvas.replacePixels(in: canvas.bounds, with: small)
        canvas.blur(
            CGRect(x: 0, y: 0, width: smallColumns, height: smallRows),
            radius: 2 * sigma / Double(factor))
        small = canvas.pixels(in: canvas.bounds)

        // Resample bilinearly, with each block's center at its middle: each
        // row first between two rows of blocks, then along the row.
        var lefts = [Int32](repeating: 0, count: columns)
        var rights = [Int32](repeating: 0, count: columns)
        var weights = [Int](repeating: 0, count: columns)
        for column in 0..<columns {
            let x = (Double(column) + 0.5) / Double(factor) - 0.5
            let left = min(max(Int(x.rounded(.down)), 0), smallColumns - 1)
            lefts[column] = Int32(left)
            rights[column] = Int32(min(left + 1, smallColumns - 1))
            weights[column] = Int((min(max(x - Double(left), 0), 1) * 256).rounded())
        }
        let result = [UInt32](unsafeUninitializedCapacity: columns * rows) { result, count in
            small.withUnsafeBufferPointer { small in
                lefts.withUnsafeBufferPointer { lefts in
                    rights.withUnsafeBufferPointer { rights in
                        weights.withUnsafeBufferPointer { weights in
                            let shared = Unshared(
                                (small, lefts, rights, weights, result.baseAddress!))
                            forEachRange(of: rows, minimum: 32) { range in
                                let (small, lefts, rights, weights, result) = shared.value
                                var line = [UInt32](repeating: 0, count: smallColumns)
                                line.withUnsafeMutableBufferPointer { line in
                                    for row in range {
                                        let y = (Double(row) + 0.5) / Double(factor) - 0.5
                                        let top = min(max(Int(y.rounded(.down)), 0), smallRows - 1)
                                        let bottom = min(top + 1, smallRows - 1)
                                        let lower = Int(
                                            (min(max(y - Double(top), 0), 1) * 256).rounded())
                                        for index in 0..<smallColumns {
                                            line[index] = Self.mix(
                                                small[top * smallColumns + index],
                                                small[bottom * smallColumns + index], lower)
                                        }
                                        let output = result + row * columns
                                        for column in 0..<columns {
                                            output[column] = Self.mix(
                                                line[Int(lefts[column])],
                                                line[Int(rights[column])], weights[column])
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            count = columns * rows
        }
        return result
    }

    /// Every pixel `drawScrollEdge` reads or changes, within the canvas: the
    /// rectangle's.
    func scrollEdgeRegion(_ effect: ScrollEdgeEffect, in rect: CGRect) -> PixelBox {
        pixelBox(of: rect)
    }

    /// A checksum of the pixels in a box, much cheaper than copying them.
    func checksum(of box: PixelBox) -> UInt64 {
        guard !box.isEmpty else { return 0 }
        let width = width
        return pixels.withUnsafeBytes { raw in
            var sum: UInt64 = 0xcbf2_9ce4_8422_2325
            for y in box.minY..<box.maxY {
                let row = raw.baseAddress! + (y * width + box.minX) * 4
                for x in 0..<(box.maxX - box.minX) {
                    let word = row.loadUnaligned(fromByteOffset: x * 4, as: UInt32.self)
                    sum = (sum ^ UInt64(word)) &* 0x100_0000_01b3
                }
            }
            return sum
        }
    }

    private func pixelBox(of rect: CGRect) -> PixelBox {
        PixelBox(
            minX: Int((Double(rect.minX) * scale).rounded(.down)),
            minY: Int((Double(rect.minY) * scale).rounded(.down)),
            maxX: Int((Double(rect.maxX) * scale).rounded(.up)),
            maxY: Int((Double(rect.maxY) * scale).rounded(.up))
        ).intersection(bounds)
    }

    /// Two pixels mixed channel by channel, with `weight`, from 0 to 256,
    /// for the second.
    private static func mix(_ first: UInt32, _ second: UInt32, _ weight: Int) -> UInt32 {
        let weight = UInt32(min(max(weight, 0), 256))
        let rest = 256 - weight
        let redBlue =
            ((first & 0x00FF_00FF) &* rest &+ (second & 0x00FF_00FF) &* weight) >> 8 & 0x00FF_00FF
        let alphaGreen =
            (((first >> 8) & 0x00FF_00FF) &* rest &+ ((second >> 8) & 0x00FF_00FF) &* weight)
            & 0xFF00_FF00
        return redBlue | alphaGreen
    }
}

extension TreeRenderer {
    /// Draws the scroll edge effect of a scroll view under a bar, just
    /// before the bar draws over it: at the top under a navigation bar,
    /// and at the bottom above the tab bar. Nothing is drawn unless the
    /// scroll view recorded that content lies under the bar.
    func drawScrollEdgeEffect(
        of scrollView: ViewNode, under bar: ViewNode, scheme: ColorScheme, opacity: Double,
        into canvas: inout Canvas
    ) {
        guard let scrollFrame = scrollView.frame, let barFrame = bar.frame,
            let under = scrollView.attributes["contentUnderBars"]?.split(separator: ",")
        else { return }
        let isTop = bar.kind == "NavigationBar"
        guard under.contains(isTop ? "top" : "bottom") else { return }
        let recorded = scrollView.attributes[
            isTop ? "scrollEdgeEffectTop" : "scrollEdgeEffectBottom"]
        guard recorded != "hidden" else { return }

        let palette = ColorPalette.appearance(scheme)
        let kind: ScrollEdgeEffect.Kind
        let blurRadius: Double
        // Assumed: `.automatic` is the soft style, as the iOS 27 UI Kit
        // draws it under a navigation bar on iPhone.
        if recorded == "hard" {
            kind = .hard(
                tint: palette.hardScrollEdge.tint.withOpacity(opacity),
                line: palette.hardScrollEdge.line.withOpacity(opacity))
            blurRadius = ColorPalette.hardScrollEdgeBlurRadius
        } else {
            kind = .soft(peak: ColorPalette.softScrollEdgePeak * opacity)
            blurRadius = ColorPalette.softScrollEdgeBlurRadius
        }

        let rect: CGRect
        if isTop {
            // From the top of the screen to a little below the bar's row of
            // buttons, or, under a large title, to the bottom of the bar.
            let large = bar.attributes["titleDisplayMode"] == "large"
            let bottom =
                large
                ? barFrame.maxY
                : barFrame.minY + LayoutEngine.navigationBarTopInset(bar)
                    + LayoutDefaults.toolbarButtonSize + LayoutDefaults.scrollEdgeEffectOverhang
            rect = CGRect(
                x: scrollFrame.minX, y: scrollFrame.minY, width: scrollFrame.width,
                height: max(min(bottom, scrollFrame.maxY) - scrollFrame.minY, 0))
        } else {
            let top = barFrame.minY - LayoutDefaults.scrollEdgeEffectBottomGap
            rect = CGRect(
                x: scrollFrame.minX, y: top, width: scrollFrame.width,
                height: max(scrollFrame.maxY - top, 0))
        }
        let effect = ScrollEdgeEffect(kind: kind, blurRadius: blurRadius, atTop: isTop)
        if let cache {
            cache.drawScrollEdge(effect, in: rect, into: &canvas)
        } else {
            canvas.drawScrollEdge(effect, in: rect)
        }
    }

    /// The scroll view whose content lies under a bar: the screen of a
    /// navigation stack, or a tab view's content, which can be a navigation
    /// stack around one.
    static func scrollView(under container: ViewNode) -> ViewNode? {
        let screens = container.children.filter {
            $0.kind != "NavigationBar" && $0.kind != "TabBar"
                && $0.kind != "TabViewBottomAccessory"
        }
        guard screens.count == 1 else { return nil }
        if screens[0].isScrollContainer { return screens[0] }
        if screens[0].kind == "NavigationStack" { return scrollView(under: screens[0]) }
        return nil
    }
}

extension RGBA {
    fileprivate func withOpacity(_ opacity: Double) -> RGBA {
        var color = self
        color.alpha = UInt8((Double(alpha) * opacity).rounded())
        return color
    }
}
