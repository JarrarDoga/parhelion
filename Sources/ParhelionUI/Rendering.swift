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
            caretOffset: caretOffset,
            cache: renderCache
        )
        var overlay: CanvasOverlay?
        if chrome != .none {
            // Assumed: the status bar and the home indicator follow the
            // window's color scheme, not the content behind them.
            let scheme = TreeRenderer.colorScheme(of: root)
            if let cached = chromeOverlayCache, cached.chrome == chrome, cached.scale == scale,
                cached.colorScheme == scheme
            {
                overlay = cached.overlay
            } else {
                overlay = renderer.chromeOverlay(chrome, scale: scale, colorScheme: scheme)
                chromeOverlayCache = overlay.map { (chrome, scale, scheme, $0) }
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
    /// Drawing kept from earlier frames, or `nil` to draw everything.
    var cache: RenderCache?

    func render(_ root: ViewNode, scale: Double, chrome: CanvasOverlay? = nil) -> Canvas {
        cache?.beginFrame()
        let front = root.children.lastIndex { $0.isPresentation }
        defer { cache?.endFrame(presenting: front != nil) }
        var canvas: Canvas
        // The root draws nothing of its own, so its children can be drawn
        // one at a time: those beneath the frontmost presentation, which
        // the cache can keep, and the rest.
        let scheme = Self.colorScheme(of: root)
        if root.kind == "Root", root.modifiers.isEmpty, root.frame != nil {
            let inherited = Inherited(
                foreground: root.attributes["foregroundStyle"], tint: root.attributes["tint"],
                opacity: root.opacity, scheme: scheme)
            var backdropGeneration: Int?
            var rest = root.children[...]
            if let cache, let front {
                (canvas, backdropGeneration) = backdrop(
                    root.children[..<front], inherited: inherited, scale: scale, cache: cache)
                rest = root.children[front...]
            } else {
                canvas = blankCanvas(scale: scale, scheme: scheme)
            }
            for child in rest {
                drawChildOfRoot(
                    child, inherited: inherited, over: backdropGeneration, into: &canvas)
                backdropGeneration = nil
            }
        } else {
            canvas = blankCanvas(scale: scale, scheme: scheme)
            draw(root, inherited: Inherited(scheme: scheme), into: &canvas)
        }
        // The system interface is above everything the app presents.
        if let chrome { canvas.draw(chrome) }
        return canvas
    }

    private func blankCanvas(scale: Double, scheme: ColorScheme) -> Canvas {
        Canvas(
            width: Double(device.screenSize.width),
            height: Double(device.screenSize.height),
            scale: scale,
            background: ColorPalette.appearance(scheme).background
        )
    }

    /// The color scheme a node records, or `light`.
    static func colorScheme(of node: ViewNode) -> ColorScheme {
        node.attributes["colorScheme"].flatMap(ColorScheme.init(name:)) ?? .light
    }

    /// The screen beneath the frontmost presentation, from the cache when
    /// nothing in it changed, and the generation of the cached backdrop.
    private func backdrop(
        _ nodes: ArraySlice<ViewNode>, inherited: Inherited, scale: Double, cache: RenderCache
    ) -> (Canvas, Int) {
        func contains(_ id: NodeID?) -> Bool {
            guard let id else { return false }
            return nodes.contains { $0.node(withID: id) != nil }
        }
        let isFocused = contains(focusedNodeID)
        let key = RenderCache.BackdropKey(
            scale: scale, device: device, colorScheme: inherited.scheme, nodes: Array(nodes),
            pressedNodeID: contains(pressedNodeID) ? pressedNodeID : nil,
            focusedNodeID: isFocused ? focusedNodeID : nil, caretOffset: isFocused ? caretOffset : 0
        )
        if let kept = cache.backdrop, kept.key == key {
            return (kept.canvas, kept.generation)
        }
        var canvas = blankCanvas(scale: scale, scheme: inherited.scheme)
        for node in nodes {
            drawChildOfRoot(node, inherited: inherited, over: nil, into: &canvas)
        }
        return (canvas, cache.keepBackdrop(canvas, key: key))
    }

    /// Draws one of the root's children. A presentation that is fading in
    /// or out draws as one group, as Core Animation fades a layer: at full
    /// opacity, then blended over what is beneath it with its opacity.
    /// Fading each part on its own would show the blur of its glass at full
    /// strength from the first frame of the fade. When the presentation is
    /// drawn straight over the cached backdrop, whose generation is given,
    /// the cache keeps it at full opacity, so each frame of the fade is one
    /// blend, and the frame where it reaches full opacity is the layer.
    private func drawChildOfRoot(
        _ node: ViewNode, inherited: Inherited, over backdropGeneration: Int?,
        into canvas: inout Canvas
    ) {
        guard node.isPresentation, node.frame != nil else {
            draw(node, inherited: inherited, into: &canvas)
            return
        }
        let opacity = inherited.opacity * node.opacity
        var opaque = node
        opaque.attributes["opacity"] = nil
        let key = backdropGeneration.map {
            RenderCache.LayerKey(
                backdropGeneration: $0, colorScheme: inherited.scheme, node: opaque,
                pressedNodeID: pressedNodeID,
                focusedNodeID: focusedNodeID, caretOffset: caretOffset)
        }
        guard opacity < 1 else {
            if let cache, let key, let kept = cache.layer(for: key) {
                canvas = kept
            } else {
                draw(node, inherited: inherited, into: &canvas)
            }
            return
        }
        var layer: Canvas
        if let cache, let key, let kept = cache.layer(for: key) {
            layer = kept
        } else {
            var full = inherited
            full.opacity = 1
            layer = canvas
            draw(opaque, inherited: full, into: &layer)
            if let cache, let key { cache.keepLayer(layer, key: key) }
        }
        canvas = Canvas(blending: layer, over: canvas, opacity: opacity)
    }

    /// Draws glass, or copies it from an earlier frame through the cache.
    private func drawGlass(
        _ rect: CGRect, cornerRadius: CGFloat, style: Path.CornerStyle = .circular,
        material: GlassMaterial, tint: RGBA? = nil, opacity: Double = 1,
        into canvas: inout Canvas
    ) {
        if let cache {
            cache.drawGlass(
                rect, cornerRadius: cornerRadius, style: style, material: material, tint: tint,
                opacity: opacity, into: &canvas)
        } else {
            canvas.drawGlass(
                rect, cornerRadius: cornerRadius, style: style, material: material, tint: tint,
                opacity: opacity)
        }
    }

    /// What a node inherits from its ancestors when it is drawn.
    struct Inherited {
        /// The foreground style, which a node's own `foregroundStyle`
        /// overrides.
        var foreground: String?
        /// The tint color's style name, set by `tint(_:)`, or `nil` for the
        /// default tint.
        var tint: String?
        /// The opacity that multiplies every color in the subtree.
        var opacity = 1.0
        /// What the node is in, which changes how its buttons draw.
        var container = Container.standard
        /// The color scheme, which a node's own `colorScheme` overrides.
        var scheme = ColorScheme.light
        /// Whether the node is in a sheet, whose dark backgrounds are
        /// lighter.
        var elevated = false

        /// The colors and materials the node draws with.
        var palette: ColorPalette.Appearance {
            ColorPalette.appearance(scheme, elevated: elevated)
        }
    }

    /// What a node is in, for how buttons inside it draw.
    enum Container {
        case standard
        /// A navigation bar, whose back button draws its own glass.
        case navigationBar
        /// A group of toolbar items, which draws one glass capsule behind
        /// its buttons.
        case toolbarGroup
        /// An alert, whose buttons are capsules.
        case alert
        /// A tab bar, whose buttons are its tabs.
        case tabBar
    }

    /// Draws a node and its children.
    private func draw(_ node: ViewNode, inherited: Inherited, into canvas: inout Canvas) {
        var foreground = node.attributes["foregroundStyle"] ?? inherited.foreground
        let tint = node.attributes["tint"] ?? inherited.tint
        var container = inherited.container
        var opacity = inherited.opacity
        guard let frame = node.frame else { return }
        opacity *= node.opacity
        var scheme = inherited.scheme
        if let own = node.attributes["colorScheme"].flatMap(ColorScheme.init(name:)) {
            scheme = own
        }
        let elevated = inherited.elevated || node.kind == "Sheet"
        let palette = ColorPalette.appearance(scheme, elevated: elevated)

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
            paint(ColorPalette.color(named: style == "tint" ? tint ?? style : style, in: scheme))
        }

        // Backgrounds sit behind the view, the outermost one at the back.
        for index in node.modifiers.indices.reversed() {
            guard case .background(let style) = node.modifiers[index],
                index < node.modifierFrames.count
            else { continue }
            canvas.fill(node.modifierFrames[index], color: paint(style))
        }

        // Controls draw their parts in Rendering+Controls.swift.
        if drawControl(
            node, in: frame, foreground: &foreground, tint: tint, opacity: &opacity,
            scheme: scheme, palette: palette, into: &canvas)
        {
            return
        }

        switch node.kind {
        case "Color":
            canvas.fill(frame, color: paint(node.attributes["color"] ?? "clear"))

        case "Text":
            drawText(
                node.text ?? "", font: ResolvedFont(node: node), in: frame,
                color: paint(foreground ?? "primary"), into: &canvas)

        case "TextField":
            drawTextField(
                node, in: frame, style: foreground ?? "primary", paint: paint, into: &canvas)

        case "Image":
            drawSymbol(node, in: frame, color: paint(foreground ?? "primary"), into: &canvas)

        case "Button":
            let style = BuiltInButtonStyle(rawValue: node.attributes["buttonStyle"] ?? "")
            let drawn = drawButton(
                node, in: frame, container: container, tint: tint, opacity: opacity,
                scheme: scheme, paint: paint, paintStyle: paint, into: &canvas)
            if let drawn {
                foreground = drawn
            } else if container == .standard || container == .navigationBar {
                foreground =
                    foreground
                    ?? (style == .plain
                        ? "primary" : node.attributes["role"] == "destructive" ? "red" : "tint")
            }
            container = .standard

        case "ToolbarItemGroup" where node.attributes["placement"] != "principal":
            // Assumed: toolbar items are labeled in near-black on glass, or
            // white on prominent glass, not in the tint color, as in the
            // iOS 27 UI Kit. Explicit styles on the items still win.
            let radius = min(frame.width, frame.height) / 2
            if node.attributes["glass"] == "prominent" {
                let fill = node.children.first?.attributes["tint"] ?? tint ?? "tint"
                drawGlass(
                    frame, cornerRadius: radius, material: palette.prominentGlass,
                    tint: ColorPalette.color(named: fill, in: scheme), opacity: opacity,
                    into: &canvas)
                foreground = node.attributes["foregroundStyle"] ?? "white"
            } else {
                drawGlass(
                    frame, cornerRadius: radius, material: palette.smallGlass,
                    opacity: opacity, into: &canvas)
                foreground = node.attributes["foregroundStyle"] ?? ColorPalette.glassLabelStyle
            }
            container = .toolbarGroup

        case "ToolbarItemGroup":
            // Principal items draw as they would anywhere else.
            container = .standard

        case "Sheet":
            drawSheet(
                node, in: frame, palette: palette, paint: paint, opacity: opacity, into: &canvas)

        case "FullScreenCover":
            canvas.fill(frame, color: paint(palette.background))

        case "Alert":
            drawAlert(in: frame, palette: palette, paint: paint, opacity: opacity, into: &canvas)
            container = .alert

        case "NavigationLink":
            // Assumed: in a list, a link's label uses the primary color;
            // elsewhere it takes the tint color, like a button.
            foreground = foreground ?? (node.listRowFrame == nil ? "tint" : "primary")

        case "NavigationStack":
            drawNavigationBarBackground(node, palette: palette, paint: paint, into: &canvas)

        case "NavigationBar":
            container = .navigationBar

        case "TabBar":
            drawTabBar(
                node, in: frame, opacity: opacity, palette: palette, paint: paint, into: &canvas)
            container = .tabBar

        case "List":
            drawList(node, in: frame, palette: palette, paint: paint, into: &canvas)

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
        let inherited = Inherited(
            foreground: foreground, tint: tint, opacity: opacity, container: container,
            scheme: scheme, elevated: elevated)
        for (index, child) in node.children.enumerated() {
            var childInherited = inherited
            // An alert's message, after its title, is gray.
            if node.kind == "Alert", index > 0, child.kind != "Button",
                child.kind != "TextField"
            {
                childInherited.foreground = foreground ?? ColorPalette.alertMessageStyle
            }
            draw(child, inherited: childInherited, into: &canvas)
        }
        canvas.clipRect = outerClip
    }

    /// Draws what a button's style puts behind its label, and returns the
    /// label's foreground style when the style chooses one.
    private func drawButton(
        _ node: ViewNode, in frame: CGRect, container: Container, tint: String?, opacity: Double,
        scheme: ColorScheme, paint: (RGBA) -> RGBA, paintStyle: (String) -> RGBA,
        into canvas: inout Canvas
    ) -> String? {
        let palette = ColorPalette.appearance(scheme)
        let own = node.attributes["foregroundStyle"]
        let isDestructive = node.attributes["role"] == "destructive"
        let radius = min(frame.width, frame.height) / 2
        switch container {
        case .navigationBar where node.id.rawValue.hasSuffix("/bar/back"):
            // The back button is a glass circle.
            drawGlass(
                frame, cornerRadius: radius, material: palette.smallGlass, opacity: opacity,
                into: &canvas)
            return own ?? ColorPalette.glassLabelStyle
        case .toolbarGroup:
            // The group draws the glass. An explicit tint colors the label.
            return own ?? (node.attributes["tint"] != nil ? "tint" : nil)
        case .alert:
            // Assumed: every alert button is a gray capsule with a black
            // label, red for a destructive one, in the iOS 27 UI Kit. Only a
            // preferred action is blue, and Parhelion has no way to mark one
            // yet.
            canvas.fill(frame, cornerRadius: radius, color: paint(palette.alertButtonFill))
            return own ?? (isDestructive ? "red" : "primary")
        case .tabBar:
            // The bar draws the highlight. The selected tab is in the tint
            // color, and the others in the glass label color, as in the iOS
            // 27 UI Kit.
            return own
                ?? (node.attributes["selected"] == "true" ? "tint" : ColorPalette.glassLabelStyle)
        case .navigationBar, .standard:
            break
        }
        let style = BuiltInButtonStyle(rawValue: node.attributes["buttonStyle"] ?? "")
        let accent = isDestructive ? "red" : "tint"
        switch style {
        case .bordered:
            canvas.fill(frame, cornerRadius: radius, color: paint(palette.borderedFill))
            return own ?? accent
        case .borderedProminent:
            canvas.fill(frame, cornerRadius: radius, color: paintStyle(accent))
            return own ?? "white"
        case .glass:
            drawGlass(
                frame, cornerRadius: radius, material: palette.smallGlass, opacity: opacity,
                into: &canvas)
            return own ?? (isDestructive ? "red" : ColorPalette.glassLabelStyle)
        case .glassProminent:
            drawGlass(
                frame, cornerRadius: radius, material: palette.prominentGlass,
                tint: ColorPalette.color(named: isDestructive ? "red" : tint ?? "tint", in: scheme),
                opacity: opacity, into: &canvas)
            return own ?? "white"
        case .plain:
            // Assumed: a plain button's label keeps the foreground style
            // around it, primary by default, instead of the tint color.
            return nil
        case .automatic, .borderless, nil:
            // Assumed: a button's label takes the tint color unless it sets
            // its own foreground style, as with SwiftUI's default button
            // style. A destructive button's label is red.
            return nil
        }
    }

    /// Draws a list's background, and each section's group of cells with
    /// separators between its rows. The rows draw themselves afterward.
    private func drawList(
        _ node: ViewNode,
        in frame: CGRect,
        palette: ColorPalette.Appearance,
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
            canvas.fill(background, color: paint(palette.groupedBackground))
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
                    group, cornerRadius: style.cornerRadius, style: .continuous,
                    color: paint(palette.groupedRowBackground)
                )
            }
            for (index, (row, cell, insets)) in rows.enumerated() {
                if row.id == pressedNodeID {
                    canvas.fill(cell, color: paint(palette.rowHighlight))
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
                        Self.chevron(
                            in: indicator, pointingLeft: false,
                            thickness: LayoutDefaults.disclosureIndicatorThickness),
                        color: paint(palette.tertiaryLabel)
                    )
                }
                guard index < rows.count - 1 else { continue }
                // Assumed: a separator spans the row's content, inset on both
                // sides, as in the iOS 27 UI Kit. A navigation link's trailing
                // inset includes its disclosure indicator, so the trailing
                // end uses the list's own inset.
                let thickness = LayoutDefaults.listSeparatorThickness
                canvas.fill(
                    CGRect(
                        x: cell.minX + insets.leading,
                        y: cell.maxY - thickness,
                        width: max(
                            cell.width - insets.leading - LayoutDefaults.listRowInsets.trailing, 0),
                        height: thickness
                    ),
                    color: paint(palette.separator)
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

    /// Draws the dimmed screen behind an alert and the alert's large glass.
    /// Its buttons draw their own capsules.
    private func drawAlert(
        in frame: CGRect, palette: ColorPalette.Appearance, paint: (RGBA) -> RGBA,
        opacity: Double, into canvas: inout Canvas
    ) {
        let screen = CGRect(origin: .zero, size: device.screenSize)
        canvas.fill(screen, color: paint(palette.alertDim))
        drawGlass(
            frame, cornerRadius: LayoutDefaults.alertCornerRadius, style: .continuous,
            material: palette.largeGlass, opacity: opacity, into: &canvas)
    }

    /// Draws the dimmed screen behind a sheet, and the sheet: opaque with
    /// rounded top corners at its large detent, and inset glass with four
    /// rounded corners at a smaller one. A grabber shows at the top when the
    /// sheet has several detents or asks for one.
    private func drawSheet(
        _ node: ViewNode, in frame: CGRect, palette: ColorPalette.Appearance,
        paint: (RGBA) -> RGBA, opacity: Double, into canvas: inout Canvas
    ) {
        // The dimming deepens as the sheet slides up into view.
        let screen = CGRect(origin: .zero, size: device.screenSize)
        let shown = min(max((screen.maxY - frame.minY) / max(frame.height, 1), 0), 1)
        var dim = palette.sheetDim
        dim.alpha = UInt8((Double(dim.alpha) * Double(shown)).rounded())
        canvas.fill(screen, color: paint(dim))

        if frame.minX > 0.5 {
            drawGlass(
                frame, cornerRadius: LayoutDefaults.partialSheetCornerRadius, style: .continuous,
                material: palette.partialSheetGlass, opacity: opacity, into: &canvas)
        } else {
            let radius = LayoutDefaults.sheetCornerRadius
            let shadow = ColorPalette.sheetShadow
            // Only the shadow above the sheet and around its top corners
            // shows, so a strip along its top casts it, which is much cheaper
            // than the whole sheet. The blur reaches about 1.5 × its radius,
            // so the shadow of the strip's bottom edge, moved down by the
            // offset, stays below the corners, under the opaque sheet.
            let strip = CGRect(
                x: frame.minX, y: frame.minY, width: frame.width,
                height: min(
                    frame.height, radius + max(CGFloat(shadow.blur) * 1.5 - shadow.offset, 0)))
            // The shadow is drawn only where it can show: above the sheet and
            // beside its corners.
            let reach = CGFloat(shadow.blur) * 1.5
            let visible = CGRect(
                x: frame.minX - reach, y: frame.minY - reach, width: frame.width + 2 * reach,
                height: reach + radius * 1.53)
            let outerClip = canvas.clipRect
            canvas.clipRect = outerClip.map { $0.intersection(visible) } ?? visible
            canvas.drawShadow(
                of: strip, cornerRadius: radius, style: .continuous, color: paint(shadow.color),
                offset: CGSize(width: 0, height: shadow.offset), blur: shadow.blur)
            canvas.clipRect = outerClip
            // Only the top corners are rounded; the bottom ones are off
            // screen.
            canvas.fill(
                CGRect(
                    x: frame.minX, y: frame.minY, width: frame.width,
                    height: frame.height + radius),
                cornerRadius: radius, style: .continuous, color: paint(palette.background))
        }

        let detents = node.attributes["detents"]?.split(separator: ",").count ?? 0
        let indicator = node.attributes["dragIndicator"]
        if indicator == "visible" || (indicator == nil && detents > 1) {
            let size = LayoutDefaults.grabberSize
            canvas.fill(
                CGRect(
                    x: frame.midX - size.width / 2, y: frame.minY + LayoutDefaults.grabberTop,
                    width: size.width, height: size.height),
                cornerRadius: size.height / 2, color: paint(palette.grabber))
        }
    }

    /// Draws the area behind a navigation bar, up to the top of the screen.
    /// It takes the background of a grouped list beneath it, as iOS's bar
    /// does at the top of scrolling content.
    private func drawNavigationBarBackground(
        _ node: ViewNode,
        palette: ColorPalette.Appearance,
        paint: (RGBA) -> RGBA,
        into canvas: inout Canvas
    ) {
        guard let barNode = node.children.first(where: { $0.kind == "NavigationBar" }),
            let bar = barNode.frame,
            let content = node.children.first(where: { $0.kind != "NavigationBar" }),
            content.kind == "List",
            ListStyleMetrics(styleName: content.attributes["listStyle"]).isGrouped
        else { return }
        if barNode.attributes["presentation"] != "sheet" {
            let area = CGRect(x: bar.minX, y: 0, width: bar.width, height: bar.maxY)
            canvas.fill(area, color: paint(palette.groupedBackground))
        } else {
            // A sheet's top corners are rounded, and more so at its large
            // detent, where it spans the screen. The fill extends under the
            // list beneath.
            let radius =
                bar.minX > 0.5
                ? LayoutDefaults.partialSheetCornerRadius : LayoutDefaults.sheetCornerRadius
            let area = CGRect(
                x: bar.minX, y: bar.minY, width: bar.width, height: bar.height + radius)
            canvas.fill(
                area, cornerRadius: radius, style: .continuous,
                color: paint(palette.groupedBackground))
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
}
