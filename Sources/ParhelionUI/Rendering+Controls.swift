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
        default:
            return false
        }
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
