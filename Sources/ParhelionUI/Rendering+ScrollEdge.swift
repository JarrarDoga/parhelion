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
    mutating func drawScrollEdge(_ effect: ScrollEdgeEffect, in rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        let outerBlend = blendMode
        defer { blendMode = outerBlend }
        blendMode = .normal
        switch effect.kind {
        case .hard(let tint, let line):
            blur(rect, radius: effect.blurRadius)
            fill(rect, color: tint)
            let width = ColorPalette.hardScrollEdgeLineWidth
            fill(
                CGRect(
                    x: rect.minX, y: effect.atTop ? rect.maxY - width : rect.minY,
                    width: rect.width, height: width),
                color: line)
        case .soft(let peak):
            // The blur is mixed back with the pixels it replaced by a
            // weight that falls from `peak` at the outer edge to 0 at the
            // inner edge, which is what a gradient mask over the blur does.
            let box = pixelBox(of: rect)
            guard !box.isEmpty else { return }
            let before = pixels(in: box)
            blur(rect, radius: effect.blurRadius)
            var mixed = pixels(in: box)
            let columns = box.maxX - box.minX
            let rows = box.maxY - box.minY
            for row in 0..<rows {
                // 0 at the outer edge, 1 at the inner edge.
                let along = (Double(row) + 0.5) / Double(rows)
                let weight = peak * (effect.atTop ? 1 - along : along)
                let blurred = Int((weight * 256).rounded())
                guard blurred < 256 else { continue }
                for column in 0..<columns {
                    let index = row * columns + column
                    mixed[index] = Self.mix(before[index], mixed[index], blurred: blurred)
                }
            }
            replacePixels(in: box, with: mixed)
        }
    }

    /// Every pixel `drawScrollEdge` reads or changes, within the canvas.
    func scrollEdgeRegion(_ effect: ScrollEdgeEffect, in rect: CGRect) -> PixelBox {
        let reach = Canvas.blurReach(radius: effect.blurRadius, scale: scale) + 1
        var box = pixelBox(of: rect)
        box = PixelBox(
            minX: box.minX - reach, minY: box.minY - reach, maxX: box.maxX + reach,
            maxY: box.maxY + reach)
        return box.intersection(bounds)
    }

    private func pixelBox(of rect: CGRect) -> PixelBox {
        PixelBox(
            minX: Int((Double(rect.minX) * scale).rounded(.down)),
            minY: Int((Double(rect.minY) * scale).rounded(.down)),
            maxX: Int((Double(rect.maxX) * scale).rounded(.up)),
            maxY: Int((Double(rect.maxY) * scale).rounded(.up))
        ).intersection(bounds)
    }

    /// Two pixels mixed channel by channel, with `blurred` of 256 for the
    /// second.
    private static func mix(_ original: UInt32, _ blurred: UInt32, blurred weight: Int) -> UInt32 {
        var result: UInt32 = 0
        for shift in stride(from: 0, to: 32, by: 8) {
            let from = Int((original >> UInt32(shift)) & 0xFF)
            let to = Int((blurred >> UInt32(shift)) & 0xFF)
            let value = (from * (256 - weight) + to * weight + 128) >> 8
            result |= UInt32(min(max(value, 0), 255)) << UInt32(shift)
        }
        return result
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
