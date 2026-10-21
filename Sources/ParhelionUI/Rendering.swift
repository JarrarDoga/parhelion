import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// A rendered image of a view tree.
public struct RenderedFrame: Sendable {
    /// The width in pixels.
    public var pixelWidth: Int { canvas.width }
    /// The height in pixels.
    public var pixelHeight: Int { canvas.height }
    /// Pixels per point.
    public var scale: Double { canvas.scale }
    /// RGBA pixels, four bytes each, row-major from the top-left corner.
    public var pixels: [UInt8] { canvas.pixels }

    let canvas: Canvas

    /// The image encoded as PNG.
    public func pngData() -> Data {
        Data(canvas.pngData())
    }

    /// The red, green, blue, and alpha components of the pixel at a point.
    public func color(at point: CGPoint) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let x = min(max(Int(Double(point.x) * scale), 0), pixelWidth - 1)
        let y = min(max(Int(Double(point.y) * scale), 0), pixelHeight - 1)
        let pixel = canvas.pixel(x: x, y: y)
        return (pixel.red, pixel.green, pixel.blue, pixel.alpha)
    }
}

extension ViewHost {
    /// Draws the current tree at the given number of pixels per point.
    public func render(scale: Double = 2) -> RenderedFrame {
        let renderer = TreeRenderer(
            pressedNodeID: pressedNodeID,
            focusedNodeID: focusedNodeID,
            caretOffset: caretOffset
        )
        return RenderedFrame(canvas: renderer.render(root, device: device, scale: scale))
    }
}

/// Draws a laid-out ``ViewNode`` tree. Like layout, it reads only the tree.
struct TreeRenderer {
    let font = TrueTypeFont.interRegular
    let measurer = FontTextMeasurer(font: .interRegular)
    /// The button being pressed, which draws dimmed.
    var pressedNodeID: NodeID?
    /// The text field being edited, which draws a caret.
    var focusedNodeID: NodeID?
    var caretOffset = 0

    func render(_ root: ViewNode, device: Device, scale: Double) -> Canvas {
        var canvas = Canvas(
            width: Double(device.screenSize.width),
            height: Double(device.screenSize.height),
            scale: scale,
            background: ColorPalette.background
        )
        draw(root, foreground: nil, opacity: 1, into: &canvas)
        return canvas
    }

    /// Draws a node and its children. `foreground` is the style inherited
    /// from ancestors, which a node's own `foregroundStyle` overrides, and
    /// `opacity` multiplies every color in the subtree.
    private func draw(
        _ node: ViewNode,
        foreground: String?,
        opacity: Double,
        into canvas: inout Canvas
    ) {
        var foreground = node.attributes["foregroundStyle"] ?? foreground
        var opacity = opacity
        guard let frame = node.frame else { return }

        if node.kind == "Button", node.id == pressedNodeID {
            opacity *= ColorPalette.pressedOpacity
        }
        func paint(_ style: String) -> RGBA {
            var color = ColorPalette.color(named: style)
            color.alpha = UInt8((Double(color.alpha) * opacity).rounded())
            return color
        }

        // Backgrounds sit behind the view, the outermost one at the back.
        for index in node.modifiers.indices.reversed() {
            guard case .background(let style) = node.modifiers[index],
                index < node.modifierFrames.count
            else { continue }
            canvas.fill(node.modifierFrames[index], color: paint(style))
        }

        switch node.kind {
        case "Color":
            canvas.fill(frame, color: paint(node.attributes["color"] ?? "clear"))

        case "Text":
            drawText(
                node.text ?? "", in: frame, color: paint(foreground ?? "primary"), into: &canvas)

        case "TextField":
            drawTextField(
                node, in: frame, style: foreground ?? "primary", paint: paint, into: &canvas)

        case "Image":
            if node.attributes["systemName"] != nil {
                drawSymbolPlaceholder(
                    in: frame, color: paint(foreground ?? "primary"), into: &canvas)
            }

        case "Button":
            // Assumed: a button's label takes the tint color unless it sets its
            // own foreground style, as with SwiftUI's default button style.
            foreground = foreground ?? "tint"

        default:
            break
        }

        // A scroll view shows only the part of its content inside its bounds.
        let outerClip = canvas.clipRect
        if node.kind == "ScrollView" {
            canvas.clipRect = outerClip.map { $0.intersection(frame) } ?? frame
        }
        for child in node.children {
            draw(child, foreground: foreground, opacity: opacity, into: &canvas)
        }
        canvas.clipRect = outerClip
    }

    /// Draws text wrapped the same way layout measured it, one line per
    /// baseline, aligned to the leading edge.
    private func drawText(
        _ text: String,
        in frame: CGRect,
        color: RGBA,
        into canvas: inout Canvas
    ) {
        let size = Double(LayoutDefaults.bodyFontSize)
        let lines = measurer.lines(of: text, fontSize: CGFloat(size), width: frame.width)
        let ascent = Double(font.ascender) * size / Double(font.unitsPerEm)
        let lineHeight = font.lineHeight(size: size)
        for (index, line) in lines.enumerated() {
            canvas.drawText(
                line.text,
                font: font,
                size: size,
                origin: CGPoint(
                    x: Double(frame.minX),
                    y: Double(frame.minY) + ascent + Double(index) * lineHeight
                ),
                color: color
            )
        }
    }

    /// Draws a single-line text field: its text, or its placeholder when it
    /// is empty, and a caret when it is focused. Text wider than the field
    /// shifts left to keep the caret in view, and is clipped to the field.
    private func drawTextField(
        _ node: ViewNode,
        in frame: CGRect,
        style: String,
        paint: (String) -> RGBA,
        into canvas: inout Canvas
    ) {
        let value = node.attributes["value"] ?? ""
        let isFocused = node.id == focusedNodeID
        let geometry = TextFieldGeometry()
        let caret = min(caretOffset, value.count)
        let shift =
            isFocused ? geometry.horizontalShift(text: value, caret: caret, width: frame.width) : 0
        let ascent = Double(font.ascender) * geometry.fontSize / Double(font.unitsPerEm)

        let outerClip = canvas.clipRect
        canvas.clipRect = outerClip.map { $0.intersection(frame) } ?? frame
        defer { canvas.clipRect = outerClip }

        let shown = value.isEmpty ? node.attributes["placeholder"] ?? "" : value
        // Assumed: placeholders use the tertiary label color, as on iOS.
        canvas.drawText(
            shown,
            font: font,
            size: geometry.fontSize,
            origin: CGPoint(x: Double(frame.minX - shift), y: Double(frame.minY) + ascent),
            color: paint(value.isEmpty ? "tertiary" : style)
        )
        if isFocused {
            let x = frame.minX - shift + geometry.caretX(in: value, at: caret)
            canvas.fill(
                CGRect(
                    x: x, y: frame.minY, width: TextFieldGeometry.caretWidth, height: frame.height),
                color: paint("tint")
            )
        }
    }

    /// Parhelion has no SF Symbols yet, so every symbol is drawn as a ring.
    private func drawSymbolPlaceholder(in frame: CGRect, color: RGBA, into canvas: inout Canvas) {
        let side = min(frame.width, frame.height)
        let stroke = max(side * 0.09, 1)
        let outer = CGRect(
            x: frame.midX - side / 2 + stroke / 2,
            y: frame.midY - side / 2 + stroke / 2,
            width: side - stroke,
            height: side - stroke
        )
        var ring = Path(ellipseIn: outer)
        ring.addPath(Path(ellipseIn: outer.insetBy(dx: stroke, dy: stroke), reversed: true))
        canvas.fill(ring, color: color)
    }
}
