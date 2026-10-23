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
        case "Picker":
            return pickerSize(node, proposal)
        case "PickerOption":
            return sizeThatFits(Self.stack("ZStack", node), proposal, parentAxis: nil)
        case "PopUpButton":
            return sizeThatFits(Self.popUpStack(node), proposal, parentAxis: nil)
        case "MenuIndicator":
            return LayoutDefaults.menuIndicatorSize
        case "SegmentIndicator":
            return .zero
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
        case "Picker":
            return placePicker(node, in: rect)
        case "PickerOption":
            // The option's view sits at the leading edge, centered
            // vertically.
            return node.children.map { child in
                let size = sizeThatFits(child, ProposedSize(rect.size), parentAxis: nil)
                return place(
                    child,
                    in: CGRect(
                        x: rect.minX, y: rect.midY - size.height / 2, width: size.width,
                        height: size.height), parentAxis: nil)
            }
        case "PopUpButton":
            return place(Self.popUpStack(node), in: rect, parentAxis: nil).children
        case "Switch", "Knob", "Divider", "StepperButton", "SliderTrack", "MenuIndicator",
            "SegmentIndicator":
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

extension LayoutEngine {
    // MARK: - Pickers

    /// A node's children in a stack of the given kind, for measuring and
    /// placing them together.
    static func stack(_ kind: String, _ node: ViewNode, spacing: CGFloat? = nil) -> ViewNode {
        var attributes: [String: String] = [:]
        if let spacing { attributes["spacing"] = formatPoints(spacing) }
        if kind == "VStack" { attributes["alignment"] = "leading" }
        return ViewNode(id: node.id, kind: kind, attributes: attributes, children: node.children)
    }

    /// A menu picker's button: the selected option and the up and down
    /// chevrons, side by side.
    static func popUpStack(_ node: ViewNode) -> ViewNode {
        stack("HStack", node, spacing: LayoutDefaults.menuIndicatorSpacing)
    }

    private func pickerSize(_ node: ViewNode, _ proposal: ProposedSize) -> CGSize {
        switch node.attributes["pickerStyle"] {
        case "segmented":
            let segments = node.children.filter { $0.kind == "PickerOption" }
            let widest =
                segments.map {
                    sizeThatFits($0, .unspecified, parentAxis: nil).width
                        + 2 * LayoutDefaults.segmentPadding
                }.max() ?? 0
            let count = CGFloat(segments.count)
            let ideal =
                widest * count + 2 * LayoutDefaults.segmentInset
                + LayoutDefaults.segmentSpacing * max(count - 1, 0)
            return CGSize(
                width: proposal.width ?? ideal, height: LayoutDefaults.segmentedControlHeight)
        case "inline":
            let size = sizeThatFits(Self.stack("VStack", node), proposal, parentAxis: nil)
            let checkmark =
                LayoutDefaults.listCheckmarkColumn.width + LayoutDefaults.listCheckmarkSpacing
            return CGSize(width: proposal.width ?? size.width + checkmark, height: size.height)
        default:
            // A menu picker with a label is a row; without one, it is its
            // button.
            if node.children.contains(where: { !Self.isTrailingPart($0) }) {
                return rowLayout(node, ProposedSize(width: proposal.width, height: nil)).size
            }
            return sizeThatFits(Self.stack("ZStack", node), proposal, parentAxis: nil)
        }
    }

    private func placePicker(_ node: ViewNode, in rect: CGRect) -> [ViewNode] {
        switch node.attributes["pickerStyle"] {
        case "segmented":
            return placeSegments(node, in: rect)
        case "inline":
            // Options fill the width, so the checkmark can sit at the trailing
            // edge.
            var y = rect.minY
            return node.children.map { option in
                let size = sizeThatFits(option, ProposedSize(rect.size), parentAxis: nil)
                let frame = CGRect(x: rect.minX, y: y, width: rect.width, height: size.height)
                y += size.height + LayoutDefaults.stackSpacing
                return place(option, in: frame, parentAxis: nil)
            }
        default:
            if node.children.contains(where: { !Self.isTrailingPart($0) }) {
                return placeRow(node, in: rect)
            }
            return node.children.map { place($0, in: rect, parentAxis: nil) }
        }
    }

    /// Places a segmented control's segments side by side in equal widths,
    /// with their labels centered, and the selected segment's capsule under
    /// the selected one.
    private func placeSegments(_ node: ViewNode, in rect: CGRect) -> [ViewNode] {
        let inset = LayoutDefaults.segmentInset
        let spacing = LayoutDefaults.segmentSpacing
        let count = CGFloat(node.children.filter { $0.kind == "PickerOption" }.count)
        let width = max((rect.width - 2 * inset - spacing * max(count - 1, 0)) / max(count, 1), 0)
        var x = rect.minX + inset
        var selected: CGRect?
        var children = node.children.map { child -> ViewNode in
            guard child.kind == "PickerOption" else { return child }
            var segment = child
            let frame = CGRect(
                x: x, y: rect.minY + inset, width: width, height: max(rect.height - 2 * inset, 0))
            x += width + spacing
            segment.frame = frame
            segment.children = segment.children.map { label in
                let size = sizeThatFits(label, ProposedSize(frame.size), parentAxis: nil)
                return place(
                    label,
                    in: CGRect(
                        x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                        width: size.width, height: size.height), parentAxis: nil)
            }
            if segment.attributes["selected"] == "true" { selected = frame }
            return segment
        }
        for index in children.indices where children[index].kind == "SegmentIndicator" {
            children[index].frame = selected ?? .zero
        }
        return children
    }

    // MARK: - Menus

    /// Places an open menu next to the button it opened from, in the screen
    /// above everything else. The menu's node covers the screen, so that a
    /// tap outside its items closes it; its items are 42-point cells inside
    /// the menu's glass.
    ///
    /// Assumed: the menu's top edge is level with the button's, as iOS 27's
    /// menus grow out of their buttons, and its trailing edge lines up with a
    /// button in the trailing half of the screen. It stays inside the safe
    /// area, 16 points from the edges.
    func placeMenu(_ node: ViewNode, over below: [ViewNode]) -> ViewNode {
        var node = node
        let screen = CGRect(origin: .zero, size: device.screenSize)
        let safeArea = device.safeArea
        node.frame = screen
        let anchor =
            node.attributes["anchor"].flatMap { id in
                below.lazy.compactMap { $0.node(withID: NodeID(id))?.frame }.first
            } ?? CGRect(x: safeArea.midX, y: safeArea.midY, width: 0, height: 0)

        let margin = LayoutDefaults.menuMargin
        let padding = LayoutDefaults.menuPadding
        let insets = LayoutDefaults.menuItemInsets
        let width = min(LayoutDefaults.menuWidth, max(safeArea.width - 2 * margin, 0))
        let cellWidth = max(width - 2 * padding, 0)
        let labelWidth = max(cellWidth - insets.horizontal, 0)
        let heights = node.children.map { item in
            let label = sizeThatFits(
                Self.stack("ZStack", item), ProposedSize(width: labelWidth, height: nil),
                parentAxis: nil)
            return max(label.height + insets.vertical, LayoutDefaults.menuItemHeight)
        }
        let height = heights.reduce(0, +) + 2 * padding
        var x = anchor.midX >= safeArea.midX ? anchor.maxX - width : anchor.minX
        x = min(max(x, safeArea.minX + margin), safeArea.maxX - margin - width)
        var y = anchor.minY
        if y + height > safeArea.maxY - margin {
            y = max(safeArea.maxY - margin - height, safeArea.minY + margin)
        }

        var top = y + padding
        node.children = zip(node.children, heights).map { item, rowHeight in
            var item = item
            let cell = CGRect(x: x + padding, y: top, width: cellWidth, height: rowHeight)
            top += rowHeight
            item.frame = cell
            let content = cell.inset(by: insets)
            item.children = item.children.map { child in
                let size = sizeThatFits(child, ProposedSize(content.size), parentAxis: nil)
                return place(
                    child,
                    in: CGRect(
                        x: content.minX, y: content.midY - size.height / 2, width: size.width,
                        height: size.height), parentAxis: nil)
            }
            return item
        }
        return node
    }
}

extension ViewNode {
    /// The panel of an open menu: its items' cells and the padding around
    /// them.
    var menuPanel: CGRect? {
        let cells = children.compactMap(\.frame)
        guard let first = cells.first else { return nil }
        let padding = LayoutDefaults.menuPadding
        return cells.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -padding, dy: -padding)
    }

    /// The insets of this node as a list row: a control taller than a line of
    /// text gets smaller vertical insets, so that its row stays as tall as a
    /// row of text.
    func controlRowInsets(_ insets: EdgeInsets) -> EdgeInsets {
        let height: CGFloat
        switch kind {
        case "Toggle": height = LayoutDefaults.switchSize.height
        case "Stepper": height = LayoutDefaults.stepperButtonSize.height
        case "Picker" where attributes["pickerStyle"] == "segmented":
            height = LayoutDefaults.segmentedControlHeight
        case "PickerOption":
            // Leave room for the checkmark.
            var insets = insets
            insets.trailing +=
                LayoutDefaults.listCheckmarkColumn.width + LayoutDefaults.listCheckmarkSpacing
            return insets
        default: return insets
        }
        var insets = insets
        let vertical = LayoutDefaults.controlRowVerticalInset(controlHeight: height)
        insets.top = min(insets.top, vertical)
        insets.bottom = min(insets.bottom, vertical)
        return insets
    }
}
