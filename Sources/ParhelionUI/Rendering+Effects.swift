import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// Drawing the modifiers in Effects.swift: clips, shadows, scales, and
// shapes over a view, each at its place in the modifier chain.

extension TreeRenderer {
    /// Draws a node that has a clip, shadow, scale, or shape overlay among
    /// its modifiers, or returns `false` for any other node, which draws as
    /// usual.
    ///
    /// The modifiers apply from the outermost in. Outside the outermost
    /// effect, backgrounds draw behind and overlays in front, as usual. The
    /// effect then applies to everything inside it, which draws the same
    /// way, down to the node itself.
    func drawEffects(_ node: ViewNode, inherited: Inherited, into canvas: inout Canvas) -> Bool {
        guard node.frame != nil, node.modifierFrames.count == node.modifiers.count,
            node.modifiers.contains(where: \.isDrawingEffect)
        else { return false }
        drawChain(node, count: node.modifiers.count, inherited: inherited, into: &canvas)
        return true
    }

    /// Draws a node with only its first `count` modifiers.
    private func drawChain(
        _ node: ViewNode, count: Int, inherited: Inherited, into canvas: inout Canvas
    ) {
        guard let effect = node.modifiers[..<count].lastIndex(where: \.isDrawingEffect) else {
            draw(Self.truncated(node, to: count), inherited: inherited, into: &canvas)
            return
        }
        let opacity = inherited.opacity * node.opacity
        let tint = node.attributes["tint"] ?? inherited.tint
        let foreground = node.attributes["foregroundStyle"] ?? inherited.foreground
        let scheme =
            node.attributes["colorScheme"].flatMap(ColorScheme.init(name:)) ?? inherited.scheme
        func color(_ style: String) -> RGBA {
            contentColor(style, tint: tint, opacity: opacity, scheme: scheme)
        }
        var overlays: [Int] = []
        for index in stride(from: count - 1, to: effect, by: -1) {
            switch node.modifiers[index] {
            case .background(let style):
                fill(
                    node.modifierFrames[index], style: style, foreground: foreground, paint: color,
                    into: &canvas)
            case .overlay:
                overlays.append(index)
            default:
                break
            }
        }

        let bounds = node.modifierFrames[effect]
        switch node.modifiers[effect] {
        case .clipShape(let shape, let eoFill):
            let clip: Canvas.Clip
            if !eoFill, let rounded = shape.roundedRect(in: bounds) {
                clip = canvas.beginClip(
                    to: rounded.rect, cornerRadius: rounded.radius, style: rounded.style)
            } else {
                clip = canvas.beginClip(to: shape.path(in: bounds), evenOdd: eoFill)
            }
            drawChain(node, count: effect, inherited: inherited, into: &canvas)
            canvas.endClip(clip)
        case .cornerRadius(let radius):
            let clip = canvas.beginClip(to: bounds, cornerRadius: radius)
            drawChain(node, count: effect, inherited: inherited, into: &canvas)
            canvas.endClip(clip)
        case .overlayStyle(let style, let shape, let eoFill):
            drawChain(node, count: effect, inherited: inherited, into: &canvas)
            fill(
                shape, in: bounds,
                with: paint(of: style, in: bounds, foreground: foreground, color: color),
                evenOdd: eoFill, into: &canvas)
        case .shadow(let style, let radius, let x, let y):
            drawShadowed(
                node, count: effect, color: color(style), radius: radius,
                offset: CGSize(width: x, height: y), inherited: inherited, into: &canvas)
        case .scaleEffect(let x, let y, let anchor):
            drawScaled(
                node, count: effect, scale: CGSize(width: x, height: y),
                anchor: CGPoint(
                    x: bounds.minX + anchor.x * bounds.width,
                    y: bounds.minY + anchor.y * bounds.height),
                inherited: inherited, into: &canvas)
        default:
            break
        }

        // An outer overlay is in front of an inner one.
        let childInherited = Inherited(
            foreground: foreground, tint: tint, opacity: opacity, container: .standard,
            scheme: scheme, elevated: inherited.elevated || node.kind == "Sheet")
        for index in overlays.reversed() {
            let rank = node.modifiers[..<index].count(where: \.isOverlay)
            if let overlay = node.children.filter(\.isOverlayContent).dropFirst(rank).first {
                draw(overlay, inherited: childInherited, into: &canvas)
            }
        }
    }

    /// The node with only its first `count` modifiers, and only the
    /// overlays among them.
    private static func truncated(_ node: ViewNode, to count: Int) -> ViewNode {
        guard count < node.modifiers.count else { return node }
        var node = node
        let kept = node.modifiers[..<count].count(where: \.isOverlay)
        node.modifiers = Array(node.modifiers[..<count])
        node.modifierFrames = Array(node.modifierFrames.prefix(count))
        var rank = 0
        node.children.removeAll { child in
            guard child.isOverlayContent else { return false }
            rank += 1
            return rank > kept
        }
        return node
    }

    // MARK: - Layers

    /// Draws the inside of a shadow modifier on a layer of its own, the
    /// layer's blurred shadow, and the layer over it.
    private func drawShadowed(
        _ node: ViewNode, count: Int, color: RGBA, radius: CGFloat, offset: CGSize,
        inherited: Inherited, into canvas: inout Canvas
    ) {
        let content = Self.truncated(node, to: count)
        guard let drawn = Self.drawnBounds(of: content) else { return }
        let scale = canvas.scale
        // One pixel more on each side, for anti-aliased edges.
        let minX = Int((Double(drawn.minX) * scale).rounded(.down)) - 1
        let minY = Int((Double(drawn.minY) * scale).rounded(.down)) - 1
        let maxX = Int((Double(drawn.maxX) * scale).rounded(.up)) + 1
        let maxY = Int((Double(drawn.maxY) * scale).rounded(.up)) + 1
        var layer = layerCanvas(width: maxX - minX, height: maxY - minY, scale: scale)
        var renderer = self
        renderer.cache = nil
        renderer.drawChain(
            Self.translated(
                node, by: CGSize(width: -Double(minX) / scale, height: -Double(minY) / scale)),
            count: count, inherited: inherited, into: &layer)
        // Assumed: SwiftUI's radius is half the blur that design tools and
        // `drawShadow` take.
        canvas.drawShadow(
            ofLayer: layer, atPixelX: minX, y: minY, color: color, offset: offset,
            blur: Double(radius) * 2)
        canvas.draw(layer: layer, atPixelX: minX, y: minY)
    }

    /// Draws the inside of a scale modifier on a layer of its own, at the
    /// scale it shows at, and the layer scaled around the anchor.
    ///
    /// When both axes scale by the same amount, the layer's pixels line up
    /// with the canvas's, so text and edges stay as sharp as when drawn
    /// directly. Otherwise the layer is drawn at the larger scale and
    /// sampled into place.
    private func drawScaled(
        _ node: ViewNode, count: Int, scale factor: CGSize, anchor: CGPoint,
        inherited: Inherited, into canvas: inout Canvas
    ) {
        if factor.width == 1, factor.height == 1 {
            drawChain(node, count: count, inherited: inherited, into: &canvas)
            return
        }
        guard factor.width != 0, factor.height != 0,
            let drawn = Self.drawnBounds(of: Self.truncated(node, to: count))
        else { return }
        let scale = canvas.scale
        let along = (x: abs(Double(factor.width)), y: abs(Double(factor.height)))
        var renderer = self
        renderer.cache = nil

        if along.x == along.y {
            // A point p draws at canvas pixel c + p × s, where c is the
            // anchor's pixel times 1 − s. The layer starts at a point whose
            // pixel there is whole.
            let layerScale = scale * along.x
            func axis(
                low: CGFloat, high: CGFloat, anchor: CGFloat, factor: CGFloat
            ) -> (
                origin: Int, shift: Double, length: Int
            ) {
                let c = Double(anchor) * scale * (1 - Double(factor))
                let a = c + Double(low) * scale * Double(factor)
                let b = c + Double(high) * scale * Double(factor)
                let origin = Int(min(a, b).rounded(.down)) - 1
                let end = Int(max(a, b).rounded(.up)) + 1
                // The layer's first pixel is at canvas pixel `origin`, or at
                // `end - 1` when mirrored.
                let shift =
                    factor > 0
                    ? (Double(origin) - c) / layerScale : (c - Double(end)) / layerScale
                return (origin, shift, end - origin)
            }
            let x = axis(low: drawn.minX, high: drawn.maxX, anchor: anchor.x, factor: factor.width)
            let y = axis(low: drawn.minY, high: drawn.maxY, anchor: anchor.y, factor: factor.height)
            var layer = layerCanvas(width: x.length, height: y.length, scale: layerScale)
            renderer.drawChain(
                Self.translated(node, by: CGSize(width: -x.shift, height: -y.shift)), count: count,
                inherited: inherited, into: &layer)
            canvas.draw(
                layer: layer, atPixelX: x.origin, y: y.origin, flipX: factor.width < 0,
                flipY: factor.height < 0)
            return
        }

        let layerScale = scale * max(along.x, along.y)
        let minX = Int((Double(drawn.minX) * layerScale).rounded(.down)) - 1
        let minY = Int((Double(drawn.minY) * layerScale).rounded(.down)) - 1
        let maxX = Int((Double(drawn.maxX) * layerScale).rounded(.up)) + 1
        let maxY = Int((Double(drawn.maxY) * layerScale).rounded(.up)) + 1
        var layer = layerCanvas(width: maxX - minX, height: maxY - minY, scale: layerScale)
        let origin = CGPoint(x: Double(minX) / layerScale, y: Double(minY) / layerScale)
        renderer.drawChain(
            Self.translated(node, by: CGSize(width: -origin.x, height: -origin.y)), count: count,
            inherited: inherited, into: &layer)
        let size = CGSize(
            width: Double(maxX - minX) / layerScale, height: Double(maxY - minY) / layerScale)
        func scaled(_ value: CGFloat, _ anchor: CGFloat, _ factor: CGFloat) -> CGFloat {
            anchor + (value - anchor) * factor
        }
        let corners = (
            x: (
                scaled(origin.x, anchor.x, factor.width),
                scaled(origin.x + size.width, anchor.x, factor.width)
            ),
            y: (
                scaled(origin.y, anchor.y, factor.height),
                scaled(origin.y + size.height, anchor.y, factor.height)
            )
        )
        canvas.draw(
            Bitmap(layer),
            in: CGRect(
                x: min(corners.x.0, corners.x.1), y: min(corners.y.0, corners.y.1),
                width: abs(corners.x.1 - corners.x.0), height: abs(corners.y.1 - corners.y.0)),
            flipX: factor.width < 0, flipY: factor.height < 0)
    }

    /// A transparent canvas of a size in pixels.
    private func layerCanvas(width: Int, height: Int, scale: Double) -> Canvas {
        Canvas(
            width: Double(max(width, 0)) / scale, height: Double(max(height, 0)) / scale,
            scale: scale, background: .clear)
    }

    /// The bounds of everything a node draws: its frame, the bounds of its
    /// modifiers, and what its descendants draw, except the content of a
    /// scroll view beyond its bounds. `nil` if it has no frame.
    static func drawnBounds(of node: ViewNode) -> CGRect? {
        guard var bounds = node.frame else { return nil }
        for frame in node.modifierFrames where frame.width > 0 || frame.height > 0 {
            bounds = bounds.union(frame)
        }
        guard !node.isScrollContainer else { return bounds }
        for child in node.children {
            if let drawn = drawnBounds(of: child) { bounds = bounds.union(drawn) }
        }
        return bounds
    }

    /// The node with every frame in it moved by an offset.
    static func translated(_ node: ViewNode, by offset: CGSize) -> ViewNode {
        var node = node
        node.frame = node.frame?.offsetBy(dx: offset.width, dy: offset.height)
        node.modifierFrames = node.modifierFrames.map {
            $0.offsetBy(dx: offset.width, dy: offset.height)
        }
        node.children = node.children.map { translated($0, by: offset) }
        return node
    }
}
