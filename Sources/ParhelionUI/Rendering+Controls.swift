import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// Drawing for controls: toggles, sliders, steppers, pickers, and dividers,
/// with the sizes and colors of the iOS 27 UI Kit.
extension TreeRenderer {
    /// Draws what a control adds behind its node's content, before the
    /// renderer draws the node's own kind and its children.
    ///
    /// A control's container, such as a `Toggle`, can change the foreground
    /// style and opacity its children inherit, and returns `false` so that
    /// its labels draw as usual. A part that draws itself completely, such
    /// as a `Switch` with its knob, returns `true`, and the renderer draws
    /// nothing more for it.
    func drawControl(
        _ node: ViewNode, in frame: CGRect, foreground: inout String?, tint: String?,
        opacity: inout Double, into canvas: inout Canvas
    ) -> Bool {
        if node.isDisabled, node.kind != "StepperButton" {
            // Assumed: a disabled button without a shape draws its label in
            // the tertiary color, and everything else at half opacity. A
            // stepper's half draws its own disabled symbol.
            let style = BuiltInButtonStyle(rawValue: node.attributes["buttonStyle"] ?? "")
            if node.kind == "Button" || node.kind == "NavigationLink", style?.drawsShape != true {
                foreground = "tertiary"
            } else {
                opacity *= ColorPalette.disabledOpacity
            }
        }
        let style = ControlPaint(opacity: opacity, tint: tint)

        switch node.kind {
        case "Switch":
            drawSwitch(node, in: frame, style: style, into: &canvas)
            return true
        case "Divider":
            canvas.fill(frame, color: style.paint(ColorPalette.separator))
            return true
        case "SliderTrack":
            drawSliderTrack(node, in: frame, style: style, into: &canvas)
            return true
        case "Stepper":
            drawStepper(node, style: style, into: &canvas)
            return false
        case "StepperButton":
            drawStepperSymbol(node, in: frame, style: style, into: &canvas)
            return true
        case "Picker":
            drawPicker(node, in: frame, style: style, into: &canvas)
            return false
        case "SegmentIndicator":
            let shadow = ColorPalette.segmentShadow
            canvas.drawShadow(
                of: frame, cornerRadius: frame.height / 2, style: .continuous,
                color: style.paint(shadow.color), offset: CGSize(width: 0, height: shadow.offset),
                blur: shadow.blur)
            canvas.fill(
                frame, cornerRadius: frame.height / 2, style: .continuous,
                color: style.paint(ColorPalette.selectedSegment))
            return true
        case "PickerOption":
            // A selected row of an inline picker in a list has a checkmark
            // at its trailing edge. Segments and menu items are drawn by
            // their picker and menu.
            if let cell = node.listRowFrame, node.attributes["selected"] == "true" {
                drawListCheckmark(in: cell, color: style.paint("primary"), into: &canvas)
            }
            return false
        case "PopUpButton":
            if node.id == pressedNodeID { opacity *= ColorPalette.pressedOpacity }
            foreground = foreground ?? "tint"
            return false
        case "MenuIndicator":
            drawMenuIndicator(in: frame, color: style.paint(foreground ?? "tint"), into: &canvas)
            return true
        case "Menu":
            drawMenu(node, style: style, into: &canvas)
            foreground = foreground ?? "primary"
            return false
        default:
            return false
        }
    }

    /// Draws a segmented control's capsule and the glass lens over a pressed
    /// segment, or the checkmark of an inline picker outside a list. Its
    /// selected segment's capsule draws itself.
    private func drawPicker(
        _ node: ViewNode, in frame: CGRect, style: ControlPaint, into canvas: inout Canvas
    ) {
        switch node.attributes["pickerStyle"] {
        case "segmented":
            canvas.fill(
                frame, cornerRadius: frame.height / 2, style: .continuous,
                color: style.paint(ColorPalette.controlFill))
            if let pressed = node.children.first(where: { $0.id == pressedNodeID })?.frame {
                let outset = LayoutDefaults.pressedSegmentOutset
                let lens = pressed.insetBy(dx: -outset.width, dy: -outset.height)
                canvas.drawGlass(
                    lens, cornerRadius: lens.height / 2, material: ColorPalette.smallGlass,
                    opacity: style.opacity)
            }
        case "inline":
            for option in node.children where option.attributes["selected"] == "true" {
                if let cell = option.frame {
                    drawListCheckmark(in: cell, color: style.paint("primary"), into: &canvas)
                }
            }
        default:
            break
        }
    }

    /// Draws an open menu's glass, the highlight of a pressed item, and the
    /// checkmark of the selected one, in the column before its text.
    private func drawMenu(_ node: ViewNode, style: ControlPaint, into canvas: inout Canvas) {
        guard let panel = node.menuPanel else { return }
        canvas.drawGlass(
            panel, cornerRadius: LayoutDefaults.menuCornerRadius, style: .continuous,
            material: ColorPalette.menuGlass, opacity: style.opacity)
        for item in node.children {
            guard let cell = item.frame else { continue }
            if item.id == pressedNodeID {
                let outerBlendMode = canvas.blendMode
                canvas.blendMode = .plusDarker
                canvas.fill(
                    cell, cornerRadius: LayoutDefaults.menuHighlightCornerRadius,
                    style: .continuous, color: style.paint(ColorPalette.menuHighlight))
                canvas.blendMode = outerBlendMode
            }
            guard item.attributes["selected"] == "true" else { continue }
            let column = LayoutDefaults.menuCheckmarkColumn
            let size = LayoutDefaults.menuCheckmarkSize
            let center = CGPoint(
                x: cell.minX + LayoutDefaults.menuCheckmarkInset + column.width / 2, y: cell.midY)
            canvas.fill(
                Self.checkmark(
                    in: CGRect(
                        x: center.x - size.width / 2, y: center.y - size.height / 2,
                        width: size.width, height: size.height),
                    thickness: LayoutDefaults.menuCheckmarkThickness),
                color: style.paint("primary"))
        }
    }

    /// Draws a list row's checkmark in the column at the trailing edge of its
    /// cell.
    private func drawListCheckmark(in cell: CGRect, color: RGBA, into canvas: inout Canvas) {
        let column = LayoutDefaults.listCheckmarkColumn
        let size = LayoutDefaults.listCheckmarkSize
        let center = CGPoint(
            x: cell.maxX - LayoutDefaults.listRowInsets.trailing - column.width / 2,
            y: cell.midY)
        canvas.fill(
            Self.checkmark(
                in: CGRect(
                    x: center.x - size.width / 2, y: center.y - size.height / 2,
                    width: size.width, height: size.height),
                thickness: LayoutDefaults.listCheckmarkThickness),
            color: color)
    }

    /// Draws `chevron.up.chevron.down`: a chevron pointing up above one
    /// pointing down, centered in `frame`.
    private func drawMenuIndicator(in frame: CGRect, color: RGBA, into canvas: inout Canvas) {
        let size = LayoutDefaults.menuIndicatorChevronSize
        let thickness = LayoutDefaults.menuIndicatorChevronThickness
        let gap = LayoutDefaults.menuIndicatorChevronGap
        let left = frame.midX - size.width / 2
        let right = frame.midX + size.width / 2
        let upTop = frame.midY - gap / 2 - size.height
        let downBottom = frame.midY + gap / 2 + size.height
        canvas.fill(
            Self.polyline(
                CGPoint(x: left, y: upTop + size.height), CGPoint(x: frame.midX, y: upTop),
                CGPoint(x: right, y: upTop + size.height), thickness: thickness),
            color: color)
        canvas.fill(
            Self.polyline(
                CGPoint(x: left, y: downBottom - size.height),
                CGPoint(x: frame.midX, y: downBottom),
                CGPoint(x: right, y: downBottom - size.height), thickness: thickness),
            color: color)
    }

    /// A checkmark that fills `rect`, drawn as a stroke.
    static func checkmark(in rect: CGRect, thickness: CGFloat) -> Path {
        let half = thickness / 2
        return polyline(
            CGPoint(x: rect.minX + half, y: rect.minY + rect.height * 0.55),
            CGPoint(x: rect.minX + rect.width * 0.37, y: rect.maxY - half),
            CGPoint(x: rect.maxX - half, y: rect.minY + half), thickness: thickness)
    }

    /// Two line segments, `a` to `b` and `b` to `c`, stroked with the given
    /// thickness and joined with a miter at `b`, as `chevron(in:)` draws.
    static func polyline(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, thickness: CGFloat) -> Path {
        let half = thickness / 2
        func normal(_ p: CGPoint, _ q: CGPoint) -> CGPoint {
            let length = max(hypot(q.x - p.x, q.y - p.y), 0.0001)
            return CGPoint(x: -(q.y - p.y) / length, y: (q.x - p.x) / length)
        }
        func offset(_ point: CGPoint, _ direction: CGPoint, _ distance: CGFloat) -> CGPoint {
            CGPoint(x: point.x + direction.x * distance, y: point.y + direction.y * distance)
        }
        let first = normal(a, b)
        let second = normal(b, c)
        let sum = CGPoint(x: first.x + second.x, y: first.y + second.y)
        let sumLength = max(hypot(sum.x, sum.y), 0.0001)
        let miter = CGPoint(x: sum.x / sumLength, y: sum.y / sumLength)
        let miterLength = half / max(miter.x * first.x + miter.y * first.y, 0.1)
        var path = Path()
        path.move(to: offset(a, first, half))
        path.addLine(to: offset(b, miter, miterLength))
        path.addLine(to: offset(c, second, half))
        path.addLine(to: offset(c, second, -half))
        path.addLine(to: offset(b, miter, -miterLength))
        path.addLine(to: offset(a, first, -half))
        path.closeSubpath()
        return path
    }

    /// Draws a slider's track, tinted up to the knob's center as drawn, and
    /// its knob, which becomes a glass lens while it is dragged.
    private func drawSliderTrack(
        _ node: ViewNode, in frame: CGRect, style: ControlPaint, into canvas: inout Canvas
    ) {
        let knob = node.children.first?.frame ?? frame
        let thickness = LayoutDefaults.sliderTrackThickness
        let bar = CGRect(
            x: frame.minX, y: frame.midY - thickness / 2, width: frame.width, height: thickness)
        canvas.fill(
            bar, cornerRadius: thickness / 2, style: .continuous,
            color: style.paint(ColorPalette.sliderTrack))
        var filled = bar
        filled.size.width = min(max(knob.midX - bar.minX, 0), bar.width)
        canvas.fill(
            filled, cornerRadius: thickness / 2, style: .continuous, color: style.paint("tint"))
        if node.id == pressedNodeID {
            let size = LayoutDefaults.sliderPressedKnobSize
            canvas.drawGlass(
                CGRect(
                    x: knob.midX - size.width / 2, y: knob.midY - size.height / 2,
                    width: size.width, height: size.height),
                cornerRadius: size.height / 2, material: ColorPalette.smallGlass,
                opacity: style.opacity)
            return
        }
        for shadow in ColorPalette.sliderKnobShadows {
            canvas.drawShadow(
                of: knob, cornerRadius: knob.height / 2, style: .continuous,
                color: style.paint(shadow.color), offset: CGSize(width: 0, height: shadow.offset),
                blur: shadow.blur)
        }
        canvas.fill(
            knob, cornerRadius: knob.height / 2, style: .continuous,
            color: style.paint(ColorPalette.knob))
    }

    /// Draws a stepper's capsule behind its two halves, the pressed half
    /// darker, and the line between them.
    private func drawStepper(_ node: ViewNode, style: ControlPaint, into canvas: inout Canvas) {
        let halves = node.children.filter { $0.kind == "StepperButton" }
        let frames = halves.compactMap(\.frame)
        guard let first = frames.first, let last = frames.last else { return }
        let capsule = first.union(last)
        let radius = capsule.height / 2
        canvas.fill(
            capsule, cornerRadius: radius, style: .continuous,
            color: style.paint(ColorPalette.controlFill))
        if let pressed = halves.first(where: { $0.id == pressedNodeID })?.frame {
            let outerClip = canvas.clipRect
            let outerBlendMode = canvas.blendMode
            canvas.clipRect = outerClip.map { $0.intersection(pressed) } ?? pressed
            canvas.blendMode = .plusDarker
            canvas.fill(
                capsule, cornerRadius: radius, style: .continuous,
                color: style.paint(ColorPalette.stepperPressed))
            canvas.blendMode = outerBlendMode
            canvas.clipRect = outerClip
        }
        let size = LayoutDefaults.stepperSeparatorSize
        canvas.fill(
            CGRect(
                x: first.maxX - size.width / 2, y: capsule.midY - size.height / 2,
                width: size.width, height: size.height),
            color: style.paint(ColorPalette.stepperSeparator))
    }

    /// Draws the minus or plus of a stepper's half, in the tertiary color
    /// while the half is turned off.
    private func drawStepperSymbol(
        _ node: ViewNode, in frame: CGRect, style: ControlPaint, into canvas: inout Canvas
    ) {
        let color = style.paint(node.isDisabled ? "tertiary" : "primary")
        let side = LayoutDefaults.stepperSymbolSize
        let thickness = LayoutDefaults.stepperSymbolThickness
        canvas.fill(
            CGRect(
                x: frame.midX - side / 2, y: frame.midY - thickness / 2, width: side,
                height: thickness),
            cornerRadius: thickness / 2, color: color)
        guard node.attributes["label"] == "Increment" else { return }
        canvas.fill(
            CGRect(
                x: frame.midX - thickness / 2, y: frame.midY - side / 2, width: thickness,
                height: (side - thickness) / 2),
            cornerRadius: thickness / 2, color: color)
        canvas.fill(
            CGRect(
                x: frame.midX - thickness / 2, y: frame.midY + thickness / 2, width: thickness,
                height: (side - thickness) / 2),
            cornerRadius: thickness / 2, color: color)
    }

    /// Draws a switch's track, colored by how far its knob is toward the
    /// on position as drawn, so that the color follows the knob while it
    /// slides, and its knob, which becomes a glass lens while pressed.
    private func drawSwitch(
        _ node: ViewNode, in frame: CGRect, style: ControlPaint, into canvas: inout Canvas
    ) {
        let knob = node.children.first?.frame ?? frame
        let inset = LayoutDefaults.switchKnobInset
        let travel = max(frame.width - 2 * inset - knob.width, 1)
        let progress = min(max((knob.minX - frame.minX - inset) / travel, 0), 1)
        let on = ColorPalette.color(named: style.tint ?? ColorPalette.switchOnTrackStyle)
        let track = ColorPalette.switchOffTrack.mixed(with: on, by: Double(progress))
        canvas.fill(
            frame, cornerRadius: frame.height / 2, style: .continuous, color: style.paint(track))
        if node.id == pressedNodeID {
            let size = LayoutDefaults.switchPressedKnobSize
            canvas.drawGlass(
                CGRect(
                    x: knob.midX - size.width / 2, y: knob.midY - size.height / 2,
                    width: size.width, height: size.height),
                cornerRadius: size.height / 2, material: ColorPalette.smallGlass,
                opacity: style.opacity)
        } else {
            canvas.fill(
                knob, cornerRadius: knob.height / 2, style: .continuous,
                color: style.paint(ColorPalette.knob))
        }
    }
}

/// How a control's parts are colored: at the opacity of the subtree, in the
/// tint color around it.
struct ControlPaint {
    var opacity: Double
    /// The style name of the tint color set around the control, or `nil`
    /// for the default tint.
    var tint: String?

    func paint(_ color: RGBA) -> RGBA {
        var color = color
        color.alpha = UInt8((Double(color.alpha) * opacity).rounded())
        return color
    }

    func paint(_ style: String) -> RGBA {
        paint(ColorPalette.color(named: style == "tint" ? tint ?? style : style))
    }
}

extension RGBA {
    /// The color `fraction` of the way from this color to `other`.
    func mixed(with other: RGBA, by fraction: Double) -> RGBA {
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8((Double(a) + (Double(b) - Double(a)) * fraction).rounded())
        }
        return RGBA(
            red: mix(red, other.red), green: mix(green, other.green), blue: mix(blue, other.blue),
            alpha: mix(alpha, other.alpha))
    }
}
