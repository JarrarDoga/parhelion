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
    /// Draws the current tree at the given number of pixels per point, with
    /// the device's system interface over it.
    public func render(scale: Double = 2, chrome: DeviceChrome = .none) -> RenderedFrame {
        let renderer = TreeRenderer(
            device: device,
            pressedNodeID: pressedNodeID,
            focusedNodeID: focusedNodeID,
            caretOffset: caretOffset
        )
        var overlay: CanvasOverlay?
        if chrome != .none {
            if let cached = chromeOverlayCache, cached.chrome == chrome, cached.scale == scale {
                overlay = cached.overlay
            } else {
                overlay = renderer.chromeOverlay(chrome, scale: scale)
                chromeOverlayCache = overlay.map { (chrome, scale, $0) }
            }
        }
        return RenderedFrame(
            canvas: renderer.render(presentedRoot, scale: scale, chrome: overlay))
    }
}

/// Draws a laid-out ``ViewNode`` tree. Like layout, it reads only the tree,
/// and the device for the system interface it can draw over the tree.
struct TreeRenderer {
    let measurer = FontTextMeasurer()
    /// The screen the tree was laid out for.
    var device: Device
    /// The button being pressed, which draws dimmed.
    var pressedNodeID: NodeID?
    /// The text field being edited, which draws a caret.
    var focusedNodeID: NodeID?
    var caretOffset = 0

    func render(_ root: ViewNode, scale: Double, chrome: CanvasOverlay? = nil) -> Canvas {
        var canvas = Canvas(
            width: Double(device.screenSize.width),
            height: Double(device.screenSize.height),
            scale: scale,
            background: ColorPalette.background
        )
        draw(root, foreground: nil, opacity: 1, into: &canvas)
        // The system interface is above everything the app presents.
        if let chrome { canvas.draw(chrome) }
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
        opacity *= node.opacity

        // A pressed list row highlights its cell instead of dimming.
        if node.kind == "Button" || node.kind == "NavigationLink", node.id == pressedNodeID,
            node.listRowFrame == nil
        {
            opacity *= ColorPalette.pressedOpacity
        }
        func paint(_ color: RGBA) -> RGBA {
            var color = color
            color.alpha = UInt8((Double(color.alpha) * opacity).rounded())
            return color
        }
        func paint(_ style: String) -> RGBA {
            paint(ColorPalette.color(named: style))
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
                node.text ?? "", font: ResolvedFont(attribute: node.attributes["font"]), in: frame,
                color: paint(foreground ?? "primary"), into: &canvas)

        case "TextField":
            drawTextField(
                node, in: frame, style: foreground ?? "primary", paint: paint, into: &canvas)

        case "Image":
            if let name = node.attributes["systemName"] {
                drawSymbol(name, in: frame, color: paint(foreground ?? "primary"), into: &canvas)
            }

        case "Button":
            // Assumed: a button's label takes the tint color unless it sets its
            // own foreground style, as with SwiftUI's default button style. A
            // destructive button's label is red.
            foreground = foreground ?? (node.attributes["role"] == "destructive" ? "red" : "tint")

        case "Sheet":
            // The dimming deepens as the sheet slides up into view.
            let screen = CGRect(origin: .zero, size: device.screenSize)
            let shown = min(max((screen.maxY - frame.minY) / max(frame.height, 1), 0), 1)
            var dim = ColorPalette.presentationDim
            dim.alpha = UInt8((Double(dim.alpha) * Double(shown)).rounded())
            canvas.fill(screen, color: paint(dim))
            // Only the top corners are rounded; the bottom ones are off screen.
            let radius = LayoutDefaults.sheetCornerRadius
            canvas.fill(
                CGRect(
                    x: frame.minX, y: frame.minY, width: frame.width,
                    height: frame.height + radius),
                cornerRadius: radius,
                color: paint(ColorPalette.background)
            )

        case "FullScreenCover":
            canvas.fill(frame, color: paint(ColorPalette.background))

        case "Alert":
            drawAlert(node, in: frame, paint: paint, into: &canvas)

        case "NavigationLink":
            // Assumed: in a list, a link's label uses the primary color;
            // elsewhere it takes the tint color, like a button.
            foreground = foreground ?? (node.listRowFrame == nil ? "tint" : "primary")

        case "NavigationStack":
            drawNavigationBarBackground(node, paint: paint, into: &canvas)

        case "List":
            drawList(node, in: frame, paint: paint, into: &canvas)

        case "SectionHeader", "SectionFooter":
            // Assumed: section headers and footers use the secondary label
            // color, as in iOS's grouped lists.
            foreground = foreground ?? "secondary"

        default:
            break
        }

        // A scroll view shows only the part of its content inside its bounds.
        let outerClip = canvas.clipRect
        if node.isScrollContainer {
            canvas.clipRect = outerClip.map { $0.intersection(frame) } ?? frame
        }
        for child in node.children {
            draw(child, foreground: foreground, opacity: opacity, into: &canvas)
        }
        canvas.clipRect = outerClip
    }

    /// Draws a list's background, and each section's group of cells with
    /// separators between its rows. The rows draw themselves afterward.
    private func drawList(
        _ node: ViewNode,
        in frame: CGRect,
        paint: (RGBA) -> RGBA,
        into canvas: inout Canvas
    ) {
        let style = ListStyleMetrics(styleName: node.attributes["listStyle"])
        if style.isGrouped {
            // A list that reaches the safe area extends its background to the
            // edge of the screen, as in SwiftUI.
            let safeArea = device.safeArea
            let screen = CGRect(origin: .zero, size: device.screenSize)
            var background = frame
            if abs(frame.minY - safeArea.minY) < 0.5 { background.origin.y = screen.minY }
            if abs(frame.maxY - safeArea.maxY) < 0.5 {
                background.size.height = screen.maxY - background.minY
            }
            if abs(frame.minX - safeArea.minX) < 0.5 { background.origin.x = screen.minX }
            if abs(frame.maxX - safeArea.maxX) < 0.5 {
                background.size.width = screen.maxX - background.minX
            }
            canvas.fill(background, color: paint(ColorPalette.groupedBackground))
        }

        let outerClip = canvas.clipRect
        canvas.clipRect = outerClip.map { $0.intersection(frame) } ?? frame
        defer { canvas.clipRect = outerClip }
        for section in node.children {
            let rows = section.children.compactMap { row -> (ViewNode, CGRect, EdgeInsets)? in
                guard let cell = row.listRowFrame,
                    case .listRow(let insets) = row.modifiers.last(where: { $0.isListRow })
                else { return nil }
                return (row, cell, insets)
            }
            guard let first = rows.first, let last = rows.last else { continue }
            if style.isGrouped {
                let group = first.1.union(last.1)
                canvas.fill(
                    group, cornerRadius: style.cornerRadius,
                    color: paint(ColorPalette.groupedRowBackground)
                )
            }
            for (index, (row, cell, insets)) in rows.enumerated() {
                if row.id == pressedNodeID {
                    canvas.fill(cell, color: paint(ColorPalette.rowHighlight))
                }
                if row.kind == "NavigationLink" {
                    let size = LayoutDefaults.disclosureIndicatorSize
                    let indicator = CGRect(
                        x: cell.maxX - LayoutDefaults.listRowInsets.trailing - size.width,
                        y: cell.midY - size.height / 2,
                        width: size.width,
                        height: size.height
                    )
                    canvas.fill(
                        Self.chevron(in: indicator, pointingLeft: false, thickness: 2),
                        color: paint(ColorPalette.color(named: "tertiary"))
                    )
                }
                guard index < rows.count - 1 else { continue }
                let thickness = LayoutDefaults.listSeparatorThickness
                canvas.fill(
                    CGRect(
                        x: cell.minX + insets.leading,
                        y: cell.maxY - thickness,
                        width: cell.width - insets.leading,
                        height: thickness
                    ),
                    color: paint(ColorPalette.separator)
                )
            }
        }
    }

    /// Draws text wrapped the same way layout measured it, one line per
    /// baseline, aligned to the leading edge.
    private func drawText(
        _ text: String,
        font: ResolvedFont,
        in frame: CGRect,
        color: RGBA,
        into canvas: inout Canvas
    ) {
        let lines = measurer.lines(of: text, font: font, width: frame.width)
        let typeface = font.typeface
        let baseline = font.baseline
        for (index, line) in lines.enumerated() {
            canvas.drawText(
                line.text,
                font: typeface,
                size: Double(font.size),
                origin: CGPoint(
                    x: Double(frame.minX),
                    y: Double(frame.minY + baseline + CGFloat(index) * font.lineHeight)
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
        let baseline = Double(TextFieldGeometry.resolvedFont.baseline)

        let outerClip = canvas.clipRect
        canvas.clipRect = outerClip.map { $0.intersection(frame) } ?? frame
        defer { canvas.clipRect = outerClip }

        let shown = value.isEmpty ? node.attributes["placeholder"] ?? "" : value
        // Assumed: placeholders use the tertiary label color, as on iOS.
        canvas.drawText(
            shown,
            font: geometry.font,
            size: geometry.fontSize,
            origin: CGPoint(x: Double(frame.minX - shift), y: Double(frame.minY) + baseline),
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

    /// Draws the dimmed screen behind an alert, the alert's background, and
    /// the separators around its buttons.
    private func drawAlert(
        _ node: ViewNode,
        in frame: CGRect,
        paint: (RGBA) -> RGBA,
        into canvas: inout Canvas
    ) {
        let screen = CGRect(origin: .zero, size: device.screenSize)
        canvas.fill(screen, color: paint(ColorPalette.presentationDim))
        canvas.fill(
            frame, cornerRadius: LayoutDefaults.alertCornerRadius,
            color: paint(ColorPalette.alertBackground)
        )
        let thickness = LayoutDefaults.listSeparatorThickness
        for button in node.children where button.kind == "Button" {
            guard let cell = button.frame else { continue }
            canvas.fill(
                CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: thickness),
                color: paint(ColorPalette.separator))
            if cell.minX > frame.minX {
                canvas.fill(
                    CGRect(x: cell.minX, y: cell.minY, width: thickness, height: cell.height),
                    color: paint(ColorPalette.separator))
            }
        }
    }

    /// Draws the area behind a navigation bar, up to the top of the screen.
    /// It takes the background of a grouped list beneath it, as iOS's bar
    /// does at the top of scrolling content.
    private func drawNavigationBarBackground(
        _ node: ViewNode,
        paint: (RGBA) -> RGBA,
        into canvas: inout Canvas
    ) {
        guard let bar = node.children.first(where: { $0.kind == "NavigationBar" })?.frame,
            let content = node.children.first(where: { $0.kind != "NavigationBar" }),
            content.kind == "List",
            ListStyleMetrics(styleName: content.attributes["listStyle"]).isGrouped
        else { return }
        if abs(bar.minY - device.safeArea.minY) < 0.5 {
            let area = CGRect(x: bar.minX, y: 0, width: bar.width, height: bar.maxY)
            canvas.fill(area, color: paint(ColorPalette.groupedBackground))
        } else {
            // A stack below the top of the screen is in a sheet, whose top
            // corners are rounded. The fill extends under the list beneath.
            let radius = LayoutDefaults.sheetCornerRadius
            let area = CGRect(
                x: bar.minX, y: bar.minY, width: bar.width, height: bar.height + radius)
            canvas.fill(area, cornerRadius: radius, color: paint(ColorPalette.groupedBackground))
        }
    }

    /// Draws a symbol. Parhelion has no SF Symbols yet: chevrons are drawn as
    /// chevrons, and every other symbol as a ring.
    private func drawSymbol(
        _ name: String, in frame: CGRect, color: RGBA, into canvas: inout Canvas
    ) {
        let side = min(frame.width, frame.height)
        switch name {
        case "chevron.backward", "chevron.left", "chevron.forward", "chevron.right":
            let width = side * 0.55
            let rect = CGRect(
                x: frame.midX - width / 2, y: frame.midY - side / 2, width: width, height: side)
            let pointingLeft = name == "chevron.backward" || name == "chevron.left"
            canvas.fill(
                Self.chevron(in: rect, pointingLeft: pointingLeft, thickness: side * 0.13),
                color: color)
        default:
            drawSymbolPlaceholder(in: frame, color: color, into: &canvas)
        }
    }

    /// A chevron that fills `rect`, drawn as a stroke of the given
    /// thickness with a mitered tip.
    static func chevron(in rect: CGRect, pointingLeft: Bool, thickness: CGFloat) -> Path {
        let half = thickness / 2
        let tipX = pointingLeft ? rect.minX + half : rect.maxX - half
        let tailX = pointingLeft ? rect.maxX - half : rect.minX + half
        let top = CGPoint(x: tailX, y: rect.minY + half)
        let tip = CGPoint(x: tipX, y: rect.midY)
        let bottom = CGPoint(x: tailX, y: rect.maxY - half)
        func normal(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let length = hypot(b.x - a.x, b.y - a.y)
            return CGPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
        }
        func offset(_ point: CGPoint, _ direction: CGPoint, _ distance: CGFloat) -> CGPoint {
            CGPoint(x: point.x + direction.x * distance, y: point.y + direction.y * distance)
        }
        let first = normal(top, tip)
        let second = normal(tip, bottom)
        let sum = CGPoint(x: first.x + second.x, y: first.y + second.y)
        let sumLength = hypot(sum.x, sum.y)
        let miter = CGPoint(x: sum.x / sumLength, y: sum.y / sumLength)
        let miterLength = half / (miter.x * first.x + miter.y * first.y)
        var path = Path()
        path.move(to: offset(top, first, half))
        path.addLine(to: offset(tip, miter, miterLength))
        path.addLine(to: offset(bottom, second, half))
        path.addLine(to: offset(bottom, second, -half))
        path.addLine(to: offset(tip, miter, -miterLength))
        path.addLine(to: offset(top, first, -half))
        path.closeSubpath()
        return path
    }

    /// Draws a symbol Parhelion cannot draw yet as a ring.
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
