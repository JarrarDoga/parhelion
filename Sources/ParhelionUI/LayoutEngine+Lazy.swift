#if canImport(Foundation)
import Foundation
#endif

// Layout for lazy stacks, and for the sections of a list that has more rows
// than it creates. See docs/adr/0016-lazy-windows.md.
//
// A lazy container has a node for each slot that exists and a length for
// every slot. The slots that exist are measured when the container is sized
// and placed, and their lengths are kept. A slot that has not been created
// is as long as the mean of the others, so the container is as long as it
// will be once everything is created, and its scroll bar and its content
// size stay put as the window moves. Placing the container also finds the
// slots that overlap the scroll view, its *demand*, which the host compares
// with the slots that exist.

extension LayoutEngine {
    /// The size of a lazy stack. A lazy stack takes the length it is offered
    /// across the stack, as in SwiftUI, and is as long as all its slots
    /// along it.
    func lazyStackSize(
        _ node: ViewNode, _ proposal: ProposedSize, vertical: Bool, spacing: CGFloat? = nil
    ) -> CGSize {
        let across = vertical ? proposal.width : proposal.height
        let arrangement = lazyArrange(
            node, across: across, vertical: vertical,
            spacing: spacing ?? lazySpacing(node))
        return vertical
            ? CGSize(width: arrangement.cross, height: arrangement.length)
            : CGSize(width: arrangement.length, height: arrangement.cross)
    }

    /// The size of a list section that creates only some of its rows, or
    /// `nil` for any other node.
    func lazySectionSize(_ node: ViewNode, _ proposal: ProposedSize) -> CGSize? {
        guard node.attributes["lazyCount"] != nil else { return nil }
        return lazyStackSize(node, proposal, vertical: true, spacing: 0)
    }

    /// Places the children of a list section that creates only some of its
    /// rows, or returns `nil` for any other node.
    func lazySectionPlace(_ node: ViewNode, in rect: CGRect) -> [ViewNode]? {
        guard node.attributes["lazyCount"] != nil else { return nil }
        return lazyStackPlace(node, in: rect, vertical: true, spacing: 0, alignment: "leading")
    }

    private func lazySpacing(_ node: ViewNode) -> CGFloat {
        node.attributes["spacing"].flatMap(Double.init).map { CGFloat($0) }
            ?? LayoutDefaults.stackSpacing
    }

    /// Places the views of a lazy stack that exist, and finds the slots on
    /// screen.
    func lazyStackPlace(
        _ node: ViewNode, in rect: CGRect, vertical: Bool, spacing: CGFloat? = nil,
        alignment: String? = nil
    ) -> [ViewNode] {
        let spacing = spacing ?? lazySpacing(node)
        let across = vertical ? rect.width : rect.height
        let arrangement = lazyArrange(node, across: across, vertical: vertical, spacing: spacing)
        let axis: LayoutAxis = vertical ? .vertical : .horizontal
        let alignment = alignment ?? node.attributes["alignment"]
        let origin = vertical ? rect.minY : rect.minX
        let offsets = arrangement.offsets
        let stack = arrangement.stack

        // The scroll view the stack is in, or the screen.
        let viewport = scrolling.lazy.viewports.last
        let bounds = viewport?.rect ?? CGRect(origin: .zero, size: device.screenSize)
        let low = vertical ? bounds.minY : bounds.minX
        let high = vertical ? bounds.maxY : bounds.maxX

        if let stack {
            stack.origin = origin
            stack.spacing = spacing
            stack.scrollView = viewport
            stack.offsets = offsets
            stack.vertical = vertical
            stack.viewportLength = high - low
            let crossVisible =
                vertical
                ? rect.maxX > bounds.minX && rect.minX < bounds.maxX
                : rect.maxY > bounds.minY && rect.minY < bounds.maxY
            stack.demand =
                crossVisible ? Self.lazyDemand(offsets, origin, spacing, low, high) : 0..<0
        }

        // Headers and footers that stay at the edge of the scroll view.
        let pins = (node.attributes["pinnedViews"] ?? "").split(separator: ",")
        var pinnedShift: [Int: CGFloat] = [:]
        if let stack, let viewport, !pins.isEmpty {
            let top = (vertical ? viewport.rect.minY + viewport.topInset : viewport.rect.minX)
            let bottom = (vertical ? viewport.rect.maxY - viewport.bottomInset : viewport.rect.maxX)
            for section in stack.sections {
                if pins.contains("headers"), let header = section.header,
                    arrangement.resolved.contains(header)
                {
                    let natural = origin + offsets[header]
                    let end = origin + max(offsets[section.end] - spacing, offsets[section.start])
                    let pinned = min(top, end - arrangement.lengths[header])
                    if natural < top { pinnedShift[header] = max(pinned, natural) - natural }
                }
                if pins.contains("footers"), let footer = section.footer,
                    arrangement.resolved.contains(footer)
                {
                    let natural = origin + offsets[footer]
                    let length = arrangement.lengths[footer]
                    let start = origin + offsets[section.content.lowerBound]
                    let pinned = max(bottom - length, start)
                    if natural + length > bottom {
                        pinnedShift[footer] = min(pinned, natural) - natural
                    }
                }
            }
        }

        var placed = node.children
        var pinnedChildren: [Int] = []
        var child = 0
        // The rows placed in the last layout, of which this one keeps those it
        // places again.
        let lastRows = stack?.placedRows ?? [:]
        var rows: [NodeID: LazyLayoutState.PlacedRow] = [:]
        for (index, slot) in arrangement.resolved.enumerated() {
            let shift = pinnedShift[slot] ?? 0
            var main = origin + offsets[slot] + shift
            for _ in 0..<arrangement.nodeCounts[index] {
                let size = arrangement.childSizes[child]
                let frame: CGRect
                if vertical {
                    let x: CGFloat =
                        switch alignment {
                        case "leading": rect.minX
                        case "trailing": rect.maxX - size.width
                        default: rect.minX + (rect.width - size.width) / 2
                        }
                    frame = CGRect(x: x, y: main, width: size.width, height: size.height)
                    main += size.height + spacing
                } else {
                    let y: CGFloat =
                        switch alignment {
                        case "top": rect.minY
                        case "bottom": rect.maxY - size.height
                        default: rect.minY + (rect.height - size.height) / 2
                        }
                    frame = CGRect(x: main, y: y, width: size.width, height: size.height)
                    main += size.width + spacing
                }
                let row = placed[child]
                if let last = lastRows[row.id],
                    let moved = last.moved(to: frame, node: row, axis: axis)
                {
                    placed[child] = moved
                    rows[row.id] = last
                } else {
                    placed[child] = place(row, in: frame, parentAxis: axis)
                    if stack != nil, Self.placesAnywhere(row) {
                        rows[row.id] = LazyLayoutState.PlacedRow(
                            node: row, frame: frame, axis: axis, placed: placed[child])
                    }
                }
                if shift != 0 { pinnedChildren.append(child) }
                child += 1
            }
        }
        stack?.placedRows = rows
        // A pinned view is in front of the views that scroll under it.
        guard !pinnedChildren.isEmpty else { return placed }
        let pinnedSet = Set(pinnedChildren)
        return placed.indices.filter { !pinnedSet.contains($0) }.map { placed[$0] }
            + pinnedChildren.map { placed[$0] }
    }

    /// Whether a node's placement depends only on the size of its rectangle,
    /// so that it can be moved elsewhere unchanged: whether it is made only of
    /// views whose placement neither reads where they are on screen nor
    /// records anything, unlike scroll views, navigation and tab views, lazy
    /// stacks, and views that ignore the safe area.
    static func placesAnywhere(_ node: ViewNode) -> Bool {
        guard movableKinds.contains(node.kind), node.attributes["ignoresSafeArea"] == nil,
            NodeExtensions.behavior(for: node.kind)?.place == nil
        else { return false }
        return node.children.allSatisfy(placesAnywhere)
    }

    /// The kinds of view whose placement depends only on their rectangle.
    private static let movableKinds: Set<String> = [
        "HStack", "VStack", "ZStack", "Text", "Image", "Spacer", "Divider", "Color",
        "Rectangle", "RoundedRectangle", "UnevenRoundedRectangle", "Circle", "Ellipse",
        "Capsule", "Label", "Group",
    ]

    /// The slots that overlap the range from `low` to `high`.
    private static func lazyDemand(
        _ offsets: [CGFloat], _ origin: CGFloat, _ spacing: CGFloat, _ low: CGFloat,
        _ high: CGFloat
    ) -> Range<Int> {
        let count = offsets.count - 1
        guard count > 0 else { return 0..<0 }
        func start(_ slot: Int) -> CGFloat { origin + offsets[slot] }
        func end(_ slot: Int) -> CGFloat {
            origin + max(offsets[slot + 1] - spacing, offsets[slot])
        }
        // The first slot that ends after `low`.
        var first = 0
        var upper = count
        while first < upper {
            let middle = (first + upper) / 2
            if end(middle) > low { upper = middle } else { first = middle + 1 }
        }
        // The first slot that starts at or after `high`.
        var last = first
        upper = count
        while last < upper {
            let middle = (last + upper) / 2
            if start(middle) >= high { upper = middle } else { last = middle + 1 }
        }
        return first < last ? first..<last : 0..<0
    }

    // MARK: - Measuring

    struct LazyArrangement {
        var stack: LazyLayoutState.Stack?
        /// The slots that exist, and how many nodes each has.
        var resolved: [Int]
        var nodeCounts: [Int]
        /// The size of each child node.
        var childSizes: [CGSize]
        /// The length of every slot, as far as it is known.
        var lengths: [CGFloat]
        /// Where each slot starts along the stack, and where the last ends
        /// including its spacing: one more than the slots.
        var offsets: [CGFloat]
        /// The length of all the slots and their spacing.
        var length: CGFloat
        /// The length across the stack.
        var cross: CGFloat
    }

    /// Measures the views that exist, and places every slot along the stack.
    func lazyArrange(
        _ node: ViewNode, across: CGFloat?, vertical: Bool, spacing: CGFloat
    ) -> LazyArrangement {
        let axis: LayoutAxis = vertical ? .vertical : .horizontal
        let across = across.flatMap { $0.isFinite ? $0 : nil }
        // The lengths the stack has measured are not in its node.
        sizes.noteStateRead()
        var stack = scrolling.lazy.stacks[node.id]
        var resolved: [Int]
        var counts: [Int]
        if let known = stack, known.resolved.count == known.nodeCounts.count,
            known.nodeCounts.reduce(0, +) == node.children.count,
            known.resolved.allSatisfy({ $0 < known.count })
        {
            resolved = known.resolved
            counts = known.nodeCounts
        } else {
            // A tree that was not evaluated by this host: every child is a
            // slot of its own.
            stack = nil
            resolved = Array(node.children.indices)
            counts = Array(repeating: 1, count: node.children.count)
        }
        var lengths = stack?.lengths ?? [CGFloat](repeating: .nan, count: resolved.count)
        if let stack, let across, let measured = stack.measuredAcross, abs(measured - across) > 0.5
        {
            lengths = [CGFloat](repeating: .nan, count: lengths.count)
        }

        // Scrolling lays out the same nodes again, so their sizes are kept
        // until the next evaluation.
        var childSizes: [CGSize] = []
        if let stack, let across, let cached = stack.childSizes, cached.across == across,
            cached.sizes.count == node.children.count, cached.spacing == spacing
        {
            childSizes = cached.sizes
        } else {
            let proposal =
                vertical
                ? ProposedSize(width: across, height: nil)
                : ProposedSize(width: nil, height: across)
            childSizes = node.children.map { sizeThatFits($0, proposal, parentAxis: axis) }
            if let stack, let across {
                stack.childSizes = (across: across, spacing: spacing, sizes: childSizes)
            }
        }
        var crossLength: CGFloat = 0
        var cursor = 0
        for (index, slot) in resolved.enumerated() {
            var length: CGFloat = 0
            for _ in 0..<counts[index] {
                let size = childSizes[cursor]
                length += vertical ? size.height : size.width
                crossLength = max(crossLength, vertical ? size.width : size.height)
                cursor += 1
            }
            lengths[slot] =
                counts[index] == 0 ? -1 : length + spacing * CGFloat(counts[index] - 1)
        }
        let (offsets, estimate) = Self.lazyOffsets(lengths, spacing: spacing)
        if let stack, across != nil {
            stack.lengths = lengths
            stack.measuredAcross = across
            stack.estimate = estimate
        }
        let total = offsets.last.map { max($0 - (lengths.isEmpty ? 0 : spacing), 0) } ?? 0
        return LazyArrangement(
            stack: stack, resolved: resolved, nodeCounts: counts, childSizes: childSizes,
            lengths: lengths, offsets: offsets, length: total,
            cross: across ?? crossLength)
    }

    /// Where each slot starts, given the lengths that are known, and the
    /// mean length used for the others.
    private static func lazyOffsets(
        _ lengths: [CGFloat], spacing: CGFloat
    ) -> (offsets: [CGFloat], estimate: CGFloat) {
        var sum: CGFloat = 0
        var measured = 0
        for length in lengths where length >= 0 {
            sum += length
            measured += 1
        }
        let estimate = measured > 0 ? sum / CGFloat(measured) : LazyDefaults.estimatedLength
        var offsets = [CGFloat](repeating: 0, count: lengths.count + 1)
        var cursor: CGFloat = 0
        for (index, length) in lengths.enumerated() {
            offsets[index] = cursor
            // A slot with no views takes no space and no spacing.
            if length != -1 { cursor += (length.isNaN ? estimate : length) + spacing }
        }
        offsets[lengths.count] = cursor
        return (offsets, estimate)
    }
}
