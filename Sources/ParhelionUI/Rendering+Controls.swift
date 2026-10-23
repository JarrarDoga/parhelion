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
        if node.isDisabled {
            // Assumed: a disabled button without a shape draws its label in
            // the tertiary color, and everything else at half opacity.
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
        default:
            return false
        }
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
