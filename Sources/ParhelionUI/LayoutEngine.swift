import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// A size a parent offers a child. A `nil` dimension asks for the child's
/// ideal size in that dimension.
struct ProposedSize: Hashable {
    var width: CGFloat?
    var height: CGFloat?

    static let unspecified = ProposedSize(width: nil, height: nil)

    init(width: CGFloat?, height: CGFloat?) {
        self.width = width
        self.height = height
    }

    init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }

    func inset(by insets: EdgeInsets) -> ProposedSize {
        ProposedSize(
            width: width.map { max($0 - insets.horizontal, 0) },
            height: height.map { max($0 - insets.vertical, 0) }
        )
    }
}

enum LayoutAxis {
    case horizontal, vertical
}

/// Assigns a frame to every node of a resolved tree, following SwiftUI's
/// layout model: a parent proposes a size, the child chooses its own size,
/// and the parent places the child.
///
/// The engine reads only the ``ViewNode`` tree, never view values, so it
/// lays out the same data that tools and agents see.
struct LayoutEngine {
    let device: Device
    let measurer: any TextMeasurer
    /// Scroll offsets to apply, and the scroll views found while laying out.
    let scrolling: ScrollLayout

    init(
        device: Device,
        measurer: any TextMeasurer = FontTextMeasurer(font: .interRegular),
        scrolling: ScrollLayout = ScrollLayout()
    ) {
        self.device = device
        self.measurer = measurer
        self.scrolling = scrolling
    }

    /// Lays out the root node for the device. Root content is proposed the
    /// safe area and centered in it, as in SwiftUI.
    func layout(_ root: ViewNode) -> ViewNode {
        var root = root
        root.frame = CGRect(origin: .zero, size: device.screenSize)
        let safeArea = device.safeArea
        // Several root views behave like an implicit vertical stack.
        let content =
            root.children.count == 1
            ? root.children[0] : ViewNode(id: root.id, kind: "VStack", children: root.children)
        let size = sizeThatFits(content, ProposedSize(safeArea.size), parentAxis: nil)
        let origin = CGPoint(
            x: safeArea.minX + (safeArea.width - size.width) / 2,
            y: safeArea.minY + (safeArea.height - size.height) / 2
        )
        let placed = place(content, in: CGRect(origin: origin, size: size), parentAxis: nil)
        root.children = root.children.count == 1 ? [placed] : placed.children
        return root
    }

    // MARK: - Sizing

    /// The size a node chooses for a proposal, including its layout
    /// modifiers.
    func sizeThatFits(_ node: ViewNode, _ proposal: ProposedSize, parentAxis: LayoutAxis?) -> CGSize
    {
        sizeThatFits(node, proposal, modifierCount: node.modifiers.count, parentAxis: parentAxis)
    }

    /// The size of a node with only its first `modifierCount` modifiers
    /// applied. Modifiers are stored innermost first, so the outermost
    /// applied modifier is at `modifierCount - 1`.
    private func sizeThatFits(
        _ node: ViewNode,
        _ proposal: ProposedSize,
        modifierCount: Int,
        parentAxis: LayoutAxis?
    ) -> CGSize {
        guard modifierCount > 0 else {
            return baseSize(node, proposal, parentAxis: parentAxis)
        }
        let inner = modifierCount - 1
        func child(_ proposal: ProposedSize) -> CGSize {
            sizeThatFits(node, proposal, modifierCount: inner, parentAxis: parentAxis)
        }

        switch node.modifiers[inner] {
        case .background:
            return child(proposal)

        case .padding(let insets):
            let size = child(proposal.inset(by: insets))
            return CGSize(
                width: size.width + insets.horizontal,
                height: size.height + insets.vertical
            )

        case .frame(let width, let height, _):
            let size = child(
                ProposedSize(width: width ?? proposal.width, height: height ?? proposal.height)
            )
            return CGSize(width: width ?? size.width, height: height ?? size.height)

        case .flexibleFrame(let frame):
            let childProposal = ProposedSize(
                width: clamp(
                    proposal.width ?? frame.idealWidth,
                    min: frame.minWidth,
                    max: frame.maxWidth
                ),
                height: clamp(
                    proposal.height ?? frame.idealHeight,
                    min: frame.minHeight,
                    max: frame.maxHeight
                )
            )
            let size = child(childProposal)
            return CGSize(
                width: flexibleDimension(
                    child: size.width,
                    proposed: proposal.width ?? frame.idealWidth,
                    min: frame.minWidth,
                    max: frame.maxWidth
                ),
                height: flexibleDimension(
                    child: size.height,
                    proposed: proposal.height ?? frame.idealHeight,
                    min: frame.minHeight,
                    max: frame.maxHeight
                )
            )
        }
    }

    /// The size of a node without its layout modifiers.
    private func baseSize(
        _ node: ViewNode, _ proposal: ProposedSize, parentAxis: LayoutAxis?
    ) -> CGSize {
        switch node.kind {
        case "Text":
            return measurer.size(
                of: node.text ?? "",
                fontSize: LayoutDefaults.bodyFontSize,
                width: proposal.width
            )

        case "TextField":
            // A text field fills the width it is offered and is one line tall.
            let fontSize = LayoutDefaults.bodyFontSize
            let widest =
                [node.attributes["value"] ?? "", node.attributes["placeholder"] ?? ""]
                .map { measurer.size(of: $0, fontSize: fontSize, width: nil).width }
                .max() ?? 0
            return CGSize(
                width: proposal.width ?? widest + TextFieldGeometry.caretWidth,
                height: measurer.lineHeight(fontSize: fontSize)
            )

        case "Image":
            guard node.attributes["systemName"] != nil else { return .zero }
            let scale = node.attributes["imageScale"].flatMap(Image.Scale.init) ?? .medium
            let side = LayoutDefaults.symbolSide(for: scale)
            return CGSize(width: side, height: side)

        case "Color":
            return CGSize(
                width: proposal.width ?? LayoutDefaults.flexibleIdealSize,
                height: proposal.height ?? LayoutDefaults.flexibleIdealSize
            )

        case "Spacer":
            let minLength =
                node.attributes["minLength"].flatMap(Double.init).map { CGFloat($0) }
                ?? LayoutDefaults.spacerMinLength
            switch parentAxis {
            case .vertical:
                return CGSize(width: 0, height: max(proposal.height ?? minLength, minLength))
            case .horizontal:
                return CGSize(width: max(proposal.width ?? minLength, minLength), height: 0)
            case nil:
                return CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
            }

        case "VStack":
            return stackLayout(node, proposal, axis: .vertical).size
        case "HStack":
            return stackLayout(node, proposal, axis: .horizontal).size
        case "ScrollView":
            // A scroll view takes the space it is offered, and its content's
            // size where it is offered none.
            let content = scrollContentSize(node, proposal)
            return CGSize(
                width: proposal.width ?? content.width,
                height: proposal.height ?? content.height
            )
        case "ZStack":
            return overlaySize(node.children, proposal)
        case "Button":
            // Assumed: several views in a button label stack vertically.
            if node.children.count == 1 {
                return sizeThatFits(node.children[0], proposal, parentAxis: nil)
            }
            return stackLayout(node, proposal, axis: .vertical).size
        default:
            return overlaySize(node.children, proposal)
        }
    }

    private func overlaySize(_ children: [ViewNode], _ proposal: ProposedSize) -> CGSize {
        children.reduce(CGSize.zero) { size, child in
            let childSize = sizeThatFits(child, proposal, parentAxis: nil)
            return CGSize(
                width: max(size.width, childSize.width),
                height: max(size.height, childSize.height)
            )
        }
    }

    // MARK: - Stacks

    private struct StackLayout {
        var size: CGSize
        var childSizes: [CGSize]
        var spacing: CGFloat
    }

    /// Sizes the children of a stack the way SwiftUI does.
    ///
    /// The stack subtracts its spacing from the proposal, then offers the
    /// remaining length to its children one at a time, least flexible
    /// first. Each child is offered an equal share of what is left, and
    /// whatever it does not use goes to the children after it. A child's
    /// flexibility is the difference between its largest and smallest size
    /// along the stack's axis.
    private func stackLayout(
        _ node: ViewNode, _ proposal: ProposedSize, axis: LayoutAxis
    ) -> StackLayout {
        let children = node.children
        let spacing =
            node.attributes["spacing"].flatMap(Double.init).map { CGFloat($0) }
            ?? LayoutDefaults.stackSpacing
        let totalSpacing = spacing * CGFloat(max(children.count - 1, 0))
        let along = axis == .vertical ? proposal.height : proposal.width
        let across = axis == .vertical ? proposal.width : proposal.height

        func propose(_ length: CGFloat?) -> ProposedSize {
            axis == .vertical
                ? ProposedSize(width: across, height: length)
                : ProposedSize(width: length, height: across)
        }
        func length(_ size: CGSize) -> CGFloat {
            axis == .vertical ? size.height : size.width
        }

        var sizes = [CGSize](repeating: .zero, count: children.count)
        if let along, along.isInfinite {
            // A parent measuring this stack's maximum size. There is nothing
            // to share out, and subtracting infinite sizes would produce NaN.
            sizes = children.map { sizeThatFits($0, propose(.infinity), parentAxis: axis) }
        } else if let along {
            let flexibility = children.map { child in
                length(sizeThatFits(child, propose(.infinity), parentAxis: axis))
                    - length(sizeThatFits(child, propose(0), parentAxis: axis))
            }
            let order = children.indices.sorted { flexibility[$0] < flexibility[$1] }
            var remaining = max(along - totalSpacing, 0)
            for (position, index) in order.enumerated() {
                let share = remaining / CGFloat(children.count - position)
                let size = sizeThatFits(children[index], propose(share), parentAxis: axis)
                sizes[index] = size
                remaining = max(remaining - length(size), 0)
            }
        } else {
            sizes = children.map { sizeThatFits($0, propose(nil), parentAxis: axis) }
        }

        let total = sizes.reduce(0) { $0 + length($1) } + totalSpacing
        let thickness = sizes.map { axis == .vertical ? $0.width : $0.height }.max() ?? 0
        let size =
            axis == .vertical
            ? CGSize(width: thickness, height: total)
            : CGSize(width: total, height: thickness)
        return StackLayout(size: size, childSizes: sizes, spacing: spacing)
    }

    // MARK: - Placement

    /// Places a node in `rect`, the space its parent gave it, and returns the
    /// node with frames assigned to it and its descendants.
    func place(_ node: ViewNode, in rect: CGRect, parentAxis: LayoutAxis?) -> ViewNode {
        place(node, in: rect, modifierCount: node.modifiers.count, parentAxis: parentAxis)
    }

    private func place(
        _ node: ViewNode,
        in rect: CGRect,
        modifierCount: Int,
        parentAxis: LayoutAxis?
    ) -> ViewNode {
        guard modifierCount > 0 else {
            return placeBase(node, in: rect, parentAxis: parentAxis)
        }
        var placed = placeModifier(
            node,
            in: rect,
            modifierCount: modifierCount,
            parentAxis: parentAxis
        )
        if placed.modifierFrames.count != placed.modifiers.count {
            placed.modifierFrames = Array(repeating: .zero, count: placed.modifiers.count)
        }
        placed.modifierFrames[modifierCount - 1] = rect
        return placed
    }

    /// Places a node inside its outermost applied modifier.
    private func placeModifier(
        _ node: ViewNode,
        in rect: CGRect,
        modifierCount: Int,
        parentAxis: LayoutAxis?
    ) -> ViewNode {
        let inner = modifierCount - 1

        switch node.modifiers[inner] {
        case .background:
            return place(node, in: rect, modifierCount: inner, parentAxis: parentAxis)

        case .padding(let insets):
            let content = CGRect(
                x: rect.minX + insets.leading,
                y: rect.minY + insets.top,
                width: max(rect.width - insets.horizontal, 0),
                height: max(rect.height - insets.vertical, 0)
            )
            return place(node, in: content, modifierCount: inner, parentAxis: parentAxis)

        case .frame(_, _, let alignment):
            let size = sizeThatFits(
                node,
                ProposedSize(rect.size),
                modifierCount: inner,
                parentAxis: parentAxis
            )
            let content = align(size, in: rect, alignment)
            return place(node, in: content, modifierCount: inner, parentAxis: parentAxis)

        case .flexibleFrame(let frame):
            let alignment = frame.alignment
            let size = sizeThatFits(
                node,
                ProposedSize(rect.size),
                modifierCount: inner,
                parentAxis: parentAxis
            )
            let content = align(size, in: rect, alignment)
            return place(node, in: content, modifierCount: inner, parentAxis: parentAxis)
        }
    }

    private func placeBase(_ node: ViewNode, in rect: CGRect, parentAxis: LayoutAxis?) -> ViewNode {
        var node = node
        node.frame = rect
        let proposal = ProposedSize(rect.size)

        switch node.kind {
        case "VStack", "HStack":
            let axis: LayoutAxis = node.kind == "VStack" ? .vertical : .horizontal
            node.children = placeStack(node, in: rect, axis: axis)
        case "ScrollView":
            placeScrollView(&node, in: rect)
        case "Button" where node.children.count > 1:
            node.children = placeStack(node, in: rect, axis: .vertical)
        case "ZStack":
            let alignment = Alignment(name: node.attributes["alignment"]) ?? .center
            node.children = node.children.map { child in
                let size = sizeThatFits(child, proposal, parentAxis: nil)
                return place(child, in: align(size, in: rect, alignment), parentAxis: nil)
            }
        default:
            node.children = node.children.map { child in
                let size = sizeThatFits(child, proposal, parentAxis: nil)
                return place(child, in: align(size, in: rect, .center), parentAxis: nil)
            }
        }
        return node
    }

    private func placeStack(_ node: ViewNode, in rect: CGRect, axis: LayoutAxis) -> [ViewNode] {
        let layout = stackLayout(node, ProposedSize(rect.size), axis: axis)
        let alignment = node.attributes["alignment"]
        var offset = axis == .vertical ? rect.minY : rect.minX

        return node.children.enumerated().map { index, child in
            let size = layout.childSizes[index]
            let origin: CGPoint
            if axis == .vertical {
                let x: CGFloat =
                    switch alignment {
                    case "leading": rect.minX
                    case "trailing": rect.maxX - size.width
                    default: rect.minX + (rect.width - size.width) / 2
                    }
                origin = CGPoint(x: x, y: offset)
                offset += size.height + layout.spacing
            } else {
                let y: CGFloat =
                    switch alignment {
                    case "top": rect.minY
                    case "bottom": rect.maxY - size.height
                    default: rect.minY + (rect.height - size.height) / 2
                    }
                origin = CGPoint(x: offset, y: y)
                offset += size.width + layout.spacing
            }
            return place(child, in: CGRect(origin: origin, size: size), parentAxis: axis)
        }
    }

    // MARK: - Scroll views

    /// The axes a scroll view scrolls along, from its `axes` attribute.
    static func scrollAxes(of node: ViewNode) -> (horizontal: Bool, vertical: Bool) {
        switch node.attributes["axes"] {
        case "both": (true, true)
        case "horizontal": (true, false)
        case "none": (false, false)
        default: (false, true)
        }
    }

    /// The content of a scroll view as a stack along its scroll axis, as
    /// SwiftUI lays out several content views.
    private func scrollContentStack(_ node: ViewNode) -> (stack: ViewNode, axis: LayoutAxis) {
        let axes = Self.scrollAxes(of: node)
        let axis: LayoutAxis = axes.horizontal && !axes.vertical ? .horizontal : .vertical
        let stack = ViewNode(
            id: node.id,
            kind: axis == .vertical ? "VStack" : "HStack",
            children: node.children
        )
        return (stack, axis)
    }

    /// The proposal a scroll view gives its content: no limit along the
    /// scrollable axes, and the scroll view's own size across them.
    private func scrollContentProposal(_ node: ViewNode, _ proposal: ProposedSize) -> ProposedSize {
        let axes = Self.scrollAxes(of: node)
        return ProposedSize(
            width: axes.horizontal ? nil : proposal.width,
            height: axes.vertical ? nil : proposal.height
        )
    }

    private func scrollContentSize(_ node: ViewNode, _ proposal: ProposedSize) -> CGSize {
        let (stack, _) = scrollContentStack(node)
        return sizeThatFits(stack, scrollContentProposal(node, proposal), parentAxis: nil)
    }

    private func placeScrollView(_ node: inout ViewNode, in rect: CGRect) {
        let (stack, axis) = scrollContentStack(node)
        let contentSize = sizeThatFits(
            stack,
            scrollContentProposal(node, ProposedSize(rect.size)),
            parentAxis: nil
        )
        let maxOffset = CGPoint(
            x: max(contentSize.width - rect.width, 0),
            y: max(contentSize.height - rect.height, 0)
        )
        let requested = scrolling.offsets[node.id] ?? .zero
        let offset = CGPoint(
            x: min(max(requested.x, 0), maxOffset.x),
            y: min(max(requested.y, 0), maxOffset.y)
        )
        scrolling.metrics[node.id] = ScrollMetrics(
            viewport: rect,
            contentSize: contentSize,
            offset: offset
        )
        node.attributes["contentSize"] =
            "\(formatPoints(contentSize.width)) × \(formatPoints(contentSize.height))"
        node.attributes["contentOffset"] = "\(formatPoints(offset.x)), \(formatPoints(offset.y))"

        // Content narrower than the scroll view is centered across the scroll
        // axis, as in SwiftUI.
        let contentRect = CGRect(
            x: rect.minX - offset.x,
            y: rect.minY - offset.y,
            width: axis == .vertical ? max(contentSize.width, rect.width) : contentSize.width,
            height: axis == .horizontal ? max(contentSize.height, rect.height) : contentSize.height
        )
        node.children = placeStack(stack, in: contentRect, axis: axis)
    }

    // MARK: - Helpers

    private func align(_ size: CGSize, in rect: CGRect, _ alignment: Alignment) -> CGRect {
        let x: CGFloat =
            switch alignment.horizontal {
            case .leading: rect.minX
            case .center: rect.minX + (rect.width - size.width) / 2
            case .trailing: rect.maxX - size.width
            }
        let y: CGFloat =
            switch alignment.vertical {
            case .top: rect.minY
            case .center: rect.minY + (rect.height - size.height) / 2
            case .bottom: rect.maxY - size.height
            }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func clamp(_ value: CGFloat?, min lower: CGFloat?, max upper: CGFloat?) -> CGFloat? {
        guard var value else { return nil }
        if let lower { value = Swift.max(value, lower) }
        if let upper { value = Swift.min(value, upper) }
        return value
    }

    /// The size a flexible frame chooses in one dimension. Without limits it
    /// takes its child's size. With a minimum it grows toward the proposal,
    /// and with a maximum it fills the proposal, within the limits.
    private func flexibleDimension(
        child: CGFloat,
        proposed: CGFloat?,
        min lower: CGFloat?,
        max upper: CGFloat?
    ) -> CGFloat {
        let proposed = proposed ?? child
        var result = child
        if let lower { result = Swift.max(lower, Swift.min(result, proposed)) }
        if let upper { result = Swift.min(upper, Swift.max(result, proposed)) }
        return result
    }
}

extension Alignment {
    /// The alignment with the given outline name, such as `"topLeading"`.
    init?(name: String?) {
        guard let name else { return nil }
        let all: [Alignment] = [
            .center, .top, .bottom, .leading, .trailing,
            .topLeading, .topTrailing, .bottomLeading, .bottomTrailing,
        ]
        guard let match = all.first(where: { $0.name == name }) else { return nil }
        self = match
    }
}

/// The scroll position and size of one scroll view after layout.
struct ScrollMetrics: Equatable {
    /// The scroll view's bounds on screen.
    var viewport: CGRect
    /// The size of all of its content.
    var contentSize: CGSize
    /// How far the content is scrolled, clamped to the content.
    var offset: CGPoint

    /// The largest offset on each axis.
    var maxOffset: CGPoint {
        CGPoint(
            x: max(contentSize.width - viewport.width, 0),
            y: max(contentSize.height - viewport.height, 0)
        )
    }
}

/// Scroll offsets for layout to apply, and the metrics it records.
///
/// A class, so that the layout engine, a value type, can report what it found
/// without threading results through every call.
final class ScrollLayout {
    var offsets: [NodeID: CGPoint] = [:]
    var metrics: [NodeID: ScrollMetrics] = [:]
}
