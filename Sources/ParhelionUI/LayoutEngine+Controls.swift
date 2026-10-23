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
        case "Toggle", "LabeledContent":
            return rowLayout(node, ProposedSize(width: proposal.width, height: nil)).size
        case "Switch":
            return LayoutDefaults.switchSize
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
        case "Toggle", "LabeledContent":
            return placeRow(node, in: rect)
        case "Switch", "Knob", "Divider":
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

extension ViewNode {
    /// The insets of this node as a list row: a control taller than a line of
    /// text gets smaller vertical insets, so that its row stays as tall as a
    /// row of text.
    func controlRowInsets(_ insets: EdgeInsets) -> EdgeInsets {
        let height: CGFloat
        switch kind {
        case "Toggle": height = LayoutDefaults.switchSize.height
        default: return insets
        }
        var insets = insets
        let vertical = LayoutDefaults.controlRowVerticalInset(controlHeight: height)
        insets.top = min(insets.top, vertical)
        insets.bottom = min(insets.bottom, vertical)
        return insets
    }
}
