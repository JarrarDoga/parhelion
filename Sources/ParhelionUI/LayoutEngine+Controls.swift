#if canImport(Foundation)
import Foundation
#endif

/// Layout for controls: toggles, sliders, steppers, pickers, labeled
/// content, and dividers. ``LayoutEngine`` calls these for the kinds it does
/// not lay out itself.
extension LayoutEngine {
    /// The size a control's node chooses for a proposal, or `nil` if the node
    /// is not a control.
    func controlSize(
        _ node: ViewNode, _ proposal: ProposedSize, parentAxis: LayoutAxis?
    )
        -> CGSize?
    {
        switch node.kind {
        case "Toggle", "LabeledContent", "Stepper":
            return rowLayout(node, ProposedSize(width: proposal.width, height: nil)).size
        case "Switch":
            return LayoutDefaults.switchSize
        case "StepperButton":
            return LayoutDefaults.stepperButtonSize
        case "Slider":
            return sliderLayout(node, proposal.width).size
        case "SliderTrack":
            return CGSize(
                width: proposal.width ?? LayoutDefaults.sliderIdealTrackWidth,
                height: LayoutDefaults.sliderHeight)
        case "Knob":
            return .zero
        case "Divider":
            let thickness = LayoutDefaults.dividerThickness
            return parentAxis == .horizontal
                ? CGSize(width: thickness, height: proposal.height ?? 0)
                : CGSize(width: proposal.width ?? 0, height: thickness)
        default:
            return nil
        }
    }

    /// Places a control's children in `rect`, the control's frame, or returns
    /// `nil` if the node is not a control.
    func placeControl(_ node: ViewNode, in rect: CGRect) -> [ViewNode]? {
        switch node.kind {
        case "Toggle", "LabeledContent", "Stepper":
            return placeRow(node, in: rect)
        case "Slider":
            return placeSlider(node, in: rect)
        case "Switch", "Knob", "Divider", "StepperButton", "SliderTrack":
            return node.children
        default:
            return nil
        }
    }

    // MARK: - Rows of a label and a control

    /// A control laid out as a row: its label at the leading edge and its
    /// control parts at the trailing edge.
    struct RowLayout {
        var size: CGSize
        /// The label's views, stacked vertically, and their size.
        var label: ViewNode?
        var labelSize: CGSize
        /// The control's views, side by side, and their size.
        var control: ViewNode
        var controlSize: CGSize
    }

    /// Splits a control row into its label and the parts at its trailing
    /// edge. A toggle's switch is its last child; labeled content's label is
    /// its first child.
    private func rowParts(_ node: ViewNode) -> (label: [ViewNode], control: [ViewNode]) {
        switch node.kind {
        case "LabeledContent":
            return (Array(node.children.prefix(1)), Array(node.children.dropFirst()))
        default:
            let count = node.children.reversed().prefix { Self.isTrailingPart($0) }.count
            return (node.children.dropLast(count), node.children.suffix(count))
        }
    }

    /// Whether a node is a part a control row places at its trailing edge.
    static func isTrailingPart(_ node: ViewNode) -> Bool {
        ["Switch", "StepperButton", "PopUpButton"].contains(node.kind)
    }

    /// Sizes a control row. The row fills the width it is offered; the
    /// control takes its ideal width, up to half of a row that is too narrow
    /// for both, and the label gets the rest.
    func rowLayout(_ node: ViewNode, _ proposal: ProposedSize) -> RowLayout {
        let (labelNodes, controlNodes) = rowParts(node)
        let label =
            labelNodes.isEmpty
            ? nil
            : ViewNode(
                id: node.id, kind: "VStack", attributes: ["alignment": "leading"],
                children: labelNodes)
        // A stepper's two halves touch; several content views are spaced.
        let control = ViewNode(
            id: node.id, kind: "HStack",
            attributes: node.kind == "LabeledContent" ? [:] : ["spacing": "0"],
            children: controlNodes)
        let spacing = label == nil ? 0 : LayoutDefaults.controlLabelSpacing
        let idealLabel = label.map { sizeThatFits($0, .unspecified, parentAxis: nil) } ?? .zero
        var controlProposal = ProposedSize.unspecified
        if let width = proposal.width {
            controlProposal.width = max(width - idealLabel.width - spacing, width / 2)
        }
        let controlSize = sizeThatFits(control, controlProposal, parentAxis: nil)
        let labelSize =
            label.map { label in
                let width = proposal.width.map { max($0 - controlSize.width - spacing, 0) }
                return sizeThatFits(label, ProposedSize(width: width, height: nil), parentAxis: nil)
            } ?? .zero
        let width = proposal.width ?? labelSize.width + spacing + controlSize.width
        return RowLayout(
            size: CGSize(width: width, height: max(labelSize.height, controlSize.height)),
            label: label, labelSize: labelSize, control: control, controlSize: controlSize)
    }

    /// Places a control row's label at the leading edge and its control at the
    /// trailing edge, both centered vertically.
    private func placeRow(_ node: ViewNode, in rect: CGRect) -> [ViewNode] {
        let layout = rowLayout(node, ProposedSize(width: rect.width, height: nil))
        var children: [ViewNode] = []
        if let label = layout.label {
            let frame = CGRect(
                x: rect.minX, y: rect.midY - layout.labelSize.height / 2,
                width: layout.labelSize.width, height: layout.labelSize.height)
            children += place(label, in: frame, parentAxis: nil).children
        }
        let controlFrame = CGRect(
            x: rect.maxX - layout.controlSize.width, y: rect.midY - layout.controlSize.height / 2,
            width: layout.controlSize.width, height: layout.controlSize.height)
        children += place(layout.control, in: controlFrame, parentAxis: nil).children.map {
            placeControlPart($0, of: node)
        }
        return children
    }

    /// Places the inside of a control part that depends on its control's
    /// value, such as a switch's knob.
    private func placeControlPart(_ part: ViewNode, of control: ViewNode) -> ViewNode {
        guard part.kind == "Switch", let frame = part.frame else { return part }
        var part = part
        let size = LayoutDefaults.switchKnobSize
        let inset = LayoutDefaults.switchKnobInset
        let isOn = control.attributes["isOn"] == "true"
        let knob = CGRect(
            x: isOn ? frame.maxX - inset - size.width : frame.minX + inset,
            y: frame.midY - size.height / 2, width: size.width, height: size.height)
        part.children = part.children.map { child in
            var child = child
            child.frame = knob
            return child
        }
        return part
    }
}

extension LayoutEngine {
    // MARK: - Sliders

    struct SliderLayout {
        var size: CGSize
        var minimum: (nodes: [ViewNode], size: CGSize)
        var maximum: (nodes: [ViewNode], size: CGSize)
    }

    /// Sizes a slider: its value labels at their ideal sizes at the ends, and
    /// the track filling the width between them.
    private func sliderLayout(_ node: ViewNode, _ width: CGFloat?) -> SliderLayout {
        let trackIndex = node.children.firstIndex { $0.kind == "SliderTrack" } ?? 0
        func labels(_ nodes: [ViewNode]) -> (nodes: [ViewNode], size: CGSize) {
            guard !nodes.isEmpty else { return ([], .zero) }
            let stack = ViewNode(id: node.id, kind: "HStack", children: nodes)
            return (nodes, sizeThatFits(stack, .unspecified, parentAxis: nil))
        }
        let minimum = labels(Array(node.children[..<trackIndex]))
        let maximum = labels(Array(node.children.dropFirst(trackIndex + 1)))
        let spacing = LayoutDefaults.sliderValueLabelSpacing
        let labelsWidth =
            minimum.size.width + maximum.size.width
            + (minimum.nodes.isEmpty ? 0 : spacing) + (maximum.nodes.isEmpty ? 0 : spacing)
        let height = max(LayoutDefaults.sliderHeight, minimum.size.height, maximum.size.height)
        return SliderLayout(
            size: CGSize(
                width: width ?? labelsWidth + LayoutDefaults.sliderIdealTrackWidth, height: height),
            minimum: minimum, maximum: maximum)
    }

    /// Places a slider's value labels at its ends and its track between
    /// them, with the knob where the value is along the track.
    private func placeSlider(_ node: ViewNode, in rect: CGRect) -> [ViewNode] {
        let layout = sliderLayout(node, rect.width)
        let spacing = LayoutDefaults.sliderValueLabelSpacing
        func placeLabels(_ labels: (nodes: [ViewNode], size: CGSize), x: CGFloat) -> [ViewNode] {
            guard !labels.nodes.isEmpty else { return [] }
            let stack = ViewNode(id: node.id, kind: "HStack", children: labels.nodes)
            let frame = CGRect(
                x: x, y: rect.midY - labels.size.height / 2, width: labels.size.width,
                height: labels.size.height)
            return place(stack, in: frame, parentAxis: nil).children
        }
        let minimum = placeLabels(layout.minimum, x: rect.minX)
        let maximum = placeLabels(layout.maximum, x: rect.maxX - layout.maximum.size.width)
        let leading =
            rect.minX + layout.minimum.size.width + (minimum.isEmpty ? 0 : spacing)
        let trailing =
            rect.maxX - layout.maximum.size.width - (maximum.isEmpty ? 0 : spacing)
        let height = LayoutDefaults.sliderHeight
        let trackFrame = CGRect(
            x: leading, y: rect.midY - height / 2, width: max(trailing - leading, 0),
            height: height)
        guard var track = node.children.first(where: { $0.kind == "SliderTrack" }) else {
            return node.children
        }
        track.frame = trackFrame
        let knobSize = LayoutDefaults.sliderKnobSize
        let fraction = CGFloat(Self.sliderFraction(node))
        let knob = CGRect(
            x: trackFrame.minX + fraction * max(trackFrame.width - knobSize.width, 0),
            y: trackFrame.midY - knobSize.height / 2, width: knobSize.width,
            height: knobSize.height)
        track.children = track.children.map { child in
            var child = child
            child.frame = knob
            return child
        }
        return minimum + [track] + maximum
    }

    /// How far along its track a slider's value is, from 0 to 1, from its
    /// `value` and `bounds` attributes.
    static func sliderFraction(_ node: ViewNode) -> Double {
        let bounds = (node.attributes["bounds"] ?? "").components(separatedBy: "...")
        guard let value = node.attributes["value"].flatMap(Double.init), bounds.count == 2,
            let lower = Double(bounds[0]), let upper = Double(bounds[1]), upper > lower
        else { return 0 }
        return min(max((value - lower) / (upper - lower), 0), 1)
    }
}

extension ViewNode {
    /// The insets of this node as a list row: a control taller than a line of
    /// text gets smaller vertical insets, so that its row stays as tall as a
    /// row of text.
    func controlRowInsets(_ insets: EdgeInsets) -> EdgeInsets {
        let height: CGFloat
        switch kind {
        case "Toggle": height = LayoutDefaults.switchSize.height
        case "Stepper": height = LayoutDefaults.stepperButtonSize.height
        default: return insets
        }
        var insets = insets
        let vertical = LayoutDefaults.controlRowVerticalInset(controlHeight: height)
        insets.top = min(insets.top, vertical)
        insets.bottom = min(insets.bottom, vertical)
        return insets
    }
}
