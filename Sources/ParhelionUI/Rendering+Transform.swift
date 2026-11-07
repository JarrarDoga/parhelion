import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// Drawing rotationEffect, blur, and mask (Effects+Transform.swift). Each
// draws the view inside the modifier on a layer of its own, at the canvas's
// scale and lined up with its pixels, then changes the layer and blends it
// over the canvas.

extension TreeRenderer {
    /// Draws a node through the `rotationEffect`, `blur`, or `mask` modifier
    /// at `effect` in its chain, or returns `false` for any other modifier.
    func drawTransformEffect(
        _ modifier: CustomModifier, of node: ViewNode, at effect: Int, bounds: CGRect,
        inherited: Inherited, into canvas: inout Canvas
    ) -> Bool {
        switch modifier.name {
        case TransformEffects.rotation:
            drawRotated(
                node, at: effect, parameters: modifier.parameters, bounds: bounds,
                inherited: inherited, into: &canvas)
        case TransformEffects.blur:
            drawBlurred(
                node, at: effect, parameters: modifier.parameters, bounds: bounds,
                inherited: inherited, into: &canvas)
        case TransformEffects.mask:
            drawMasked(node, at: effect, inherited: inherited, into: &canvas)
        default:
            return false
        }
        return true
    }

    /// The pixels from `(minX, minY)` up to but not including `(maxX, maxY)`
    /// that a layer covers, and the layer, transparent.
    private func layer(
        covering box: (minX: Int, minY: Int, maxX: Int, maxY: Int), scale: Double
    ) -> Canvas {
        layerCanvas(width: box.maxX - box.minX, height: box.maxY - box.minY, scale: scale)
    }

    /// The node with every frame moved so that the pixel `(x, y)` is the
    /// origin, which is where a layer starting there draws it.
    private static func moved(_ node: ViewNode, toPixelX x: Int, y: Int, scale: Double) -> ViewNode
    {
        translated(node, by: CGSize(width: -Double(x) / scale, height: -Double(y) / scale))
    }

    /// Draws the inside of a rotation on a layer of its own, and the layer
    /// rotated around the anchor.
    private func drawRotated(
        _ node: ViewNode, at effect: Int, parameters: [String: String], bounds: CGRect,
        inherited: Inherited, into canvas: inout Canvas
    ) {
        let degrees = TransformEffects.number(parameters, "degrees")
        guard degrees.truncatingRemainder(dividingBy: 360) != 0 else {
            drawChain(node, count: effect, inherited: inherited, into: &canvas)
            return
        }
        guard let drawn = Self.drawnBounds(of: Self.truncated(node, to: effect)) else { return }
        let scale = canvas.scale
        // One pixel more on each side, for anti-aliased edges.
        let box = (
            minX: Int((Double(drawn.minX) * scale).rounded(.down)) - 1,
            minY: Int((Double(drawn.minY) * scale).rounded(.down)) - 1,
            maxX: Int((Double(drawn.maxX) * scale).rounded(.up)) + 1,
            maxY: Int((Double(drawn.maxY) * scale).rounded(.up)) + 1
        )
        var layer = layer(covering: box, scale: scale)
        var renderer = self
        renderer.cache = nil
        renderer.drawChain(
            Self.moved(node, toPixelX: box.minX, y: box.minY, scale: scale), count: effect,
            inherited: inherited, into: &layer)
        let anchorX = TransformEffects.number(parameters, "anchorX", default: 0.5)
        let anchorY = TransformEffects.number(parameters, "anchorY", default: 0.5)
        canvas.draw(
            layer: layer, atPixelX: box.minX, y: box.minY, rotatedBy: degrees * .pi / 180,
            aroundX: (Double(bounds.minX) + anchorX * Double(bounds.width)) * scale,
            y: (Double(bounds.minY) + anchorY * Double(bounds.height)) * scale)
    }

    /// Draws the inside of a blur on a layer of its own, and the blurred
    /// layer.
    ///
    /// The layer reaches three standard deviations past what the view
    /// draws, where the blur has faded to nothing. With `opaque`, it is
    /// only the bounds, and the blur repeats the edge pixels outward.
    private func drawBlurred(
        _ node: ViewNode, at effect: Int, parameters: [String: String], bounds: CGRect,
        inherited: Inherited, into canvas: inout Canvas
    ) {
        let radius = TransformEffects.number(parameters, "radius")
        guard radius > 0 else {
            drawChain(node, count: effect, inherited: inherited, into: &canvas)
            return
        }
        let isOpaque = parameters["opaque"] == "true"
        let scale = canvas.scale
        let reach = Int((3 * radius * scale).rounded(.up))
        var box: (minX: Int, minY: Int, maxX: Int, maxY: Int)
        if isOpaque {
            box = (
                minX: Int((Double(bounds.minX) * scale).rounded(.down)),
                minY: Int((Double(bounds.minY) * scale).rounded(.down)),
                maxX: Int((Double(bounds.maxX) * scale).rounded(.up)),
                maxY: Int((Double(bounds.maxY) * scale).rounded(.up))
            )
        } else {
            guard let drawn = Self.drawnBounds(of: Self.truncated(node, to: effect)) else {
                return
            }
            box = (
                minX: Int((Double(drawn.minX) * scale).rounded(.down)) - 1 - reach,
                minY: Int((Double(drawn.minY) * scale).rounded(.down)) - 1 - reach,
                maxX: Int((Double(drawn.maxX) * scale).rounded(.up)) + 1 + reach,
                maxY: Int((Double(drawn.maxY) * scale).rounded(.up)) + 1 + reach
            )
        }
        // Nothing past the canvas, and its reach, can show.
        box = (
            minX: max(box.minX, -reach), minY: max(box.minY, -reach),
            maxX: min(box.maxX, canvas.width + reach), maxY: min(box.maxY, canvas.height + reach)
        )
        guard box.maxX > box.minX, box.maxY > box.minY else { return }
        var layer = layer(covering: box, scale: scale)
        var renderer = self
        renderer.cache = nil
        renderer.drawChain(
            Self.moved(node, toPixelX: box.minX, y: box.minY, scale: scale), count: effect,
            inherited: inherited, into: &layer)
        // `Canvas.blur` takes the blur as design tools give it, twice the
        // standard deviation.
        layer.blur(
            CGRect(
                x: 0, y: 0, width: Double(layer.width) / scale, height: Double(layer.height) / scale
            ), radius: radius * 2)
        canvas.draw(layer: layer, atPixelX: box.minX, y: box.minY)
    }

    /// Draws the inside of a mask on a layer of its own, the mask's views
    /// on another, and the first layer where the second is opaque.
    ///
    /// The modifier before the mask in the chain is the `overlay` that
    /// placed the mask's views, so the inside is the chain without it.
    private func drawMasked(
        _ node: ViewNode, at effect: Int, inherited: Inherited, into canvas: inout Canvas
    ) {
        let overlay = effect - 1
        guard overlay >= 0, node.modifiers[overlay].isOverlay else {
            drawChain(node, count: effect, inherited: inherited, into: &canvas)
            return
        }
        let rank = node.modifiers[..<overlay].count(where: \.isOverlay)
        guard let mask = node.children.filter(\.isOverlayContent).dropFirst(rank).first,
            let drawn = Self.drawnBounds(of: Self.truncated(node, to: overlay))
        else {
            drawChain(node, count: overlay, inherited: inherited, into: &canvas)
            return
        }
        let scale = canvas.scale
        let box = (
            minX: Int((Double(drawn.minX) * scale).rounded(.down)) - 1,
            minY: Int((Double(drawn.minY) * scale).rounded(.down)) - 1,
            maxX: Int((Double(drawn.maxX) * scale).rounded(.up)) + 1,
            maxY: Int((Double(drawn.maxY) * scale).rounded(.up)) + 1
        )
        var content = layer(covering: box, scale: scale)
        var renderer = self
        renderer.cache = nil
        renderer.drawChain(
            Self.moved(node, toPixelX: box.minX, y: box.minY, scale: scale), count: overlay,
            inherited: inherited, into: &content)

        // The mask's colors resolve like the view's, but only their opacity
        // matters, and the view's own opacity applies to the view alone.
        var maskInherited = inherited
        maskInherited.opacity = 1
        maskInherited.foreground = node.attributes["foregroundStyle"] ?? inherited.foreground
        maskInherited.tint = node.attributes["tint"] ?? inherited.tint
        maskInherited.container = .standard
        var maskLayer = layer(covering: box, scale: scale)
        renderer.draw(
            Self.moved(mask, toPixelX: box.minX, y: box.minY, scale: scale),
            inherited: maskInherited, into: &maskLayer)
        content.multiplyOpacity(by: maskLayer)
        canvas.draw(layer: content, atPixelX: box.minX, y: box.minY)
    }
}
