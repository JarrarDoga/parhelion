import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// Drawing a scroll view's content by moving what the last frame drew.
//
// A scroll view's content mostly moves from one frame to the next: the
// rows that were on screen are still there, a few points up or down, and
// the pixels they drew are the same. So the renderer keeps the canvas it had
// after drawing the content, copies it shifted by the scroll, and draws only
// the part that is new: the rows that came into view, and any node that
// changed, as a row whose state toggled.
//
// The shifted pixels are the same as drawing the content again when
//
// - the content's position is a whole number of pixels, which the renderer
//   makes so by rounding the position of the content to a pixel, as a
//   scroll view on a device does;
// - what lies beneath the content is one flat color, so the pixels the
//   content does not cover do not depend on where they are;
// - the content does not read the pixels around what it draws, as glass and
//   blurs do, which `Canvas.readsSurroundings` tells; and
// - each node that stayed has the same description, moved by the scroll.
//
// When one of these fails, or most of the view changed, the content is drawn
// in full, as when nothing was kept.

/// The bounds of nodes that a partial redraw draws, so that it can skip the
/// others.
final class Culling {
    let bounds: [NodeID: CGRect]

    init(bounds: [NodeID: CGRect]) {
        self.bounds = bounds
    }

    /// Whether a node draws nothing inside a clip.
    func skips(_ node: ViewNode, in clip: CGRect?) -> Bool {
        guard let clip, let bounds = bounds[node.id] else { return false }
        return !bounds.intersects(clip)
    }
}

extension TreeRenderer {
    /// The smallest scroll view, as a fraction of the canvas's area, that
    /// keeps its content between frames. A small one costs less to draw
    /// than to keep.
    private static let smallestKeptFraction = 0.2

    /// More of the view than this changing is drawn in full.
    private static let largestRedrawFraction = 0.6

    /// How far, in points, drawing can reach past a node's frame beyond what
    /// `drawnBounds` counts: the edge of a stroke, and a little more.
    private static let drawingMargin: CGFloat = 8

    /// Draws a scroll view's content inside its clip.
    func drawScrollContent(
        _ node: ViewNode, frame: CGRect, inherited: Inherited, into canvas: inout Canvas
    ) {
        let scale = canvas.scale
        var content = node.children
        // Round the content's position to a pixel, and its coordinates to a
        // thousandth of a point. Frame to frame, the content then moves by
        // whole pixels and has exact coordinates, so it draws the same
        // pixels wherever it is, which is what lets the pixels be copied.
        var shift = CGSize.zero
        if let origin = content[0].frame?.origin {
            shift = CGSize(
                width: (Double(origin.x) * scale).rounded() / scale - Double(origin.x),
                height: (Double(origin.y) * scale).rounded() / scale - Double(origin.y))
        }
        content = content.map { Self.placed($0, by: shift) }
        guard let cache, culling == nil, let clip = canvas.clipRect else {
            drawAll(content, inherited: inherited, into: &canvas)
            return
        }
        let box = canvas.pixelBox(clippedTo: clip)
        let canvasArea = Double(canvas.width * canvas.height)
        guard Double(box.area) >= Self.smallestKeptFraction * canvasArea else {
            drawAll(content, inherited: inherited, into: &canvas)
            return
        }
        var scrollNode = node
        scrollNode.children = []
        scrollNode.attributes["contentOffset"] = nil
        scrollNode.attributes["contentUnderBars"] = nil
        let key = RenderCache.ScrollKey(
            id: node.id, node: scrollNode, inherited: inherited, scale: scale, device: device,
            canvasWidth: canvas.width, canvasHeight: canvas.height, box: box,
            pressedNodeID: pressedNodeID, focusedNodeID: focusedNodeID,
            caretOffset: caretOffset, selectionAnchor: selectionAnchor)
        let under = canvas.uniformPixel(in: box)

        // Take the last frame's snapshot and a spare buffer out of the cache,
        // so that neither is shared when one is written.
        let kept = cache.scrollSnapshots.removeValue(forKey: node.id)
        var buffer = cache.spareWords
        cache.spareWords = []
        defer {
            // The last snapshot's storage is the next frame's spare.
            if let kept { cache.spareWords = kept.words }
        }

        func keep() {
            canvas.copyPixels(in: box, into: &buffer)
            cache.scrollSnapshots[node.id] = RenderCache.ScrollSnapshot(
                key: key, content: content, words: buffer, under: under ?? 0,
                lastFrame: cache.frame)
        }

        if let under, let kept, kept.key == key, kept.under == under,
            let plan = shiftPlan(from: kept.content, to: content, box: box, scale: scale)
        {
            canvas.readsSurroundings = false
            canvas.replacePixels(in: box, with: kept.words, movedDownBy: plan.rows)
            var renderer = self
            renderer.culling = Culling(bounds: Self.boundsTable(of: content))
            let outerClip = canvas.clipRect
            for rows in plan.redraw {
                let part = PixelBox(
                    minX: box.minX, minY: rows.lowerBound, maxX: box.maxX, maxY: rows.upperBound)
                canvas.fill(part, pixel: under)
                canvas.clipRect = canvas.clipRect(for: part)
                renderer.drawAll(content, inherited: inherited, into: &canvas)
            }
            canvas.clipRect = outerClip
            if !canvas.readsSurroundings {
                cache.scrollShifts += 1
                if plan.rows != 0 { cache.contentMoved = true }
                keep()
                return
            }
            // The new content read its surroundings: draw it all.
            canvas.fill(box, pixel: under)
        }

        canvas.readsSurroundings = false
        drawAll(content, inherited: inherited, into: &canvas)
        cache.scrollRedraws += 1
        if under != nil, !canvas.readsSurroundings {
            keep()
        } else {
            cache.spareWords = buffer
        }
    }

    /// The node and its descendants moved by an offset, with every
    /// coordinate rounded to 1/1024 of a point.
    private static func placed(_ node: ViewNode, by offset: CGSize) -> ViewNode {
        func round(_ value: CGFloat) -> CGFloat { (value * 1024).rounded() / 1024 }
        func place(_ rect: CGRect) -> CGRect {
            CGRect(
                x: round(rect.minX + offset.width), y: round(rect.minY + offset.height),
                width: round(rect.width), height: round(rect.height))
        }
        var node = node
        node.frame = node.frame.map(place)
        node.modifierFrames = node.modifierFrames.map(place)
        node.children = node.children.map { placed($0, by: offset) }
        return node
    }

    private func drawAll(_ nodes: [ViewNode], inherited: Inherited, into canvas: inout Canvas) {
        for node in nodes {
            if let culling, culling.skips(node, in: canvas.clipRect) { continue }
            draw(node, inherited: inherited, into: &canvas)
        }
    }

    // MARK: - Plan

    /// How to turn the pixels of the last frame into this one's.
    private struct ShiftPlan {
        /// The pixel rows the content moved down by.
        var rows: Int
        /// The pixel rows to draw again, in order and apart.
        var redraw: [Range<Int>]
    }

    /// Compares the content with the last frame's, and decides which rows to
    /// draw again, or returns `nil` when the pixels cannot be reused.
    private func shiftPlan(
        from old: [ViewNode], to new: [ViewNode], box: PixelBox, scale: Double
    ) -> ShiftPlan? {
        // How far the content moved: how far its first node that stayed did.
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let match = new.first(where: { oldByID[$0.id] != nil }),
            let before = oldByID[match.id]?.frame, let after = match.frame,
            abs(after.minX - before.minX) < 1e-6
        else { return nil }
        let moved = Double(after.minY - before.minY) * scale
        let rows = Int(moved.rounded())
        guard abs(moved - Double(rows)) < 1e-3, abs(rows) < box.maxY - box.minY else {
            return nil
        }

        var changed: [CGRect] = []
        var reusable = true
        func mark(_ node: ViewNode, at offset: CGFloat) {
            guard let bounds = Self.changedBounds(of: node) else {
                reusable = false
                return
            }
            changed.append(bounds.offsetBy(dx: 0, dy: offset))
        }
        let shift = CGFloat(after.minY - before.minY)
        compare(children: new, with: old, shift: shift) { mark($0, at: $1) }
        guard reusable else { return nil }

        // Rows to draw again: what changed, and what scrolled into view.
        var intervals: [Range<Int>] = changed.map { rect in
            let low = Int((Double(rect.minY) * scale).rounded(.down)) - 1
            let high = Int((Double(rect.maxY) * scale).rounded(.up)) + 1
            return max(low, box.minY)..<min(high, box.maxY)
        }.filter { !$0.isEmpty }
        if rows > 0 {
            intervals.append(box.minY..<min(box.minY + rows, box.maxY))
        } else if rows < 0 {
            intervals.append(max(box.maxY + rows, box.minY)..<box.maxY)
        }
        intervals.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<Int>] = []
        for interval in intervals {
            if let last = merged.last, interval.lowerBound <= last.upperBound {
                merged[merged.count - 1] =
                    last.lowerBound..<max(last.upperBound, interval.upperBound)
            } else {
                merged.append(interval)
            }
        }
        let redrawn = merged.reduce(0) { $0 + $1.count }
        guard Double(redrawn) <= Self.largestRedrawFraction * Double(box.maxY - box.minY) else {
            return nil
        }
        return ShiftPlan(rows: rows, redraw: merged)
    }

    /// Whether two nodes are the same apart from where they are, and the
    /// scroll's shift.
    private static func same(_ new: ViewNode, as old: ViewNode, shift: CGFloat) -> Bool {
        guard new.id == old.id, new.kind == old.kind, new.attributes == old.attributes,
            new.modifiers == old.modifiers, new.modifierFrames.count == old.modifierFrames.count,
            let newFrame = new.frame, let oldFrame = old.frame,
            close(newFrame, oldFrame.offsetBy(dx: 0, dy: shift))
        else { return false }
        for (index, frame) in new.modifierFrames.enumerated()
        where !close(frame, old.modifierFrames[index].offsetBy(dx: 0, dy: shift)) {
            return false
        }
        return true
    }

    private static func close(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) < 1e-4 && abs(first.minY - second.minY) < 1e-4
            && abs(first.width - second.width) < 1e-4 && abs(first.height - second.height) < 1e-4
    }

    /// Nodes whose children are drawn without looking at the other children
    /// or at where they are, so that a child may come or go alone.
    private static let independentParents: Set<String> = [
        "VStack", "HStack", "ZStack", "LazyVStack", "LazyHStack", "Group", "ForEach",
        "ScrollView",
    ]

    /// Calls `mark` for each node of `new` that is not the same as in `old`,
    /// and each node of `old` that is gone, as deep down as the difference
    /// goes.
    private func compare(
        children new: [ViewNode], with old: [ViewNode], shift: CGFloat,
        mark: (ViewNode, CGFloat) -> Void
    ) {
        var oldIndex: [NodeID: Int] = [:]
        for (index, node) in old.enumerated() { oldIndex[node.id] = index }
        var seen = Set<NodeID>()
        var last = -1
        for node in new {
            seen.insert(node.id)
            guard let index = oldIndex[node.id], index > last else {
                mark(node, 0)
                continue
            }
            last = index
            let before = old[index]
            guard Self.same(node, as: before, shift: shift) else {
                mark(node, 0)
                mark(before, shift)
                continue
            }
            let sameChildren =
                node.children.count == before.children.count
                && zip(node.children, before.children).allSatisfy { $0.id == $1.id }
            if sameChildren || Self.independentParents.contains(node.kind) {
                compare(children: node.children, with: before.children, shift: shift, mark: mark)
            } else {
                mark(node, 0)
                mark(before, shift)
            }
        }
        for node in old where !seen.contains(node.id) { mark(node, shift) }
    }

    // MARK: - Bounds

    /// Where drawing a node and what is inside it can change pixels, or `nil`
    /// when it can change any: the node scales or transforms its content
    /// through a modifier that has no bounds here.
    private static func changedBounds(of node: ViewNode) -> CGRect? {
        var reach: CGFloat = 0
        guard var bounds = reachingBounds(of: node, reach: &reach) else { return nil }
        bounds = bounds.insetBy(dx: -(reach + drawingMargin), dy: -(reach + drawingMargin))
        return bounds
    }

    /// The bounds a node's drawing covers, and the largest reach of a
    /// shadow in it past its shape.
    private static func reachingBounds(of node: ViewNode, reach: inout CGFloat) -> CGRect? {
        guard var bounds = drawnBounds(of: node) else { return nil }
        for modifier in node.modifiers {
            switch modifier {
            case .scaleEffect, .custom:
                return nil
            case .shadow(_, let radius, let x, let y):
                reach = max(reach, radius * 4 + max(abs(x), abs(y)))
            default:
                break
            }
        }
        guard !node.isScrollContainer else { return bounds }
        for child in node.children {
            guard let inner = reachingBounds(of: child, reach: &reach) else { return nil }
            bounds = bounds.union(inner)
        }
        return bounds
    }

    /// The bounds of every node in the content, for skipping the nodes a
    /// partial redraw does not reach.
    private static func boundsTable(of nodes: [ViewNode]) -> [NodeID: CGRect] {
        var table: [NodeID: CGRect] = [:]
        // The bounds and shadow reach of a subtree, from its children's.
        @discardableResult
        func visit(_ node: ViewNode) -> (bounds: CGRect, reach: CGFloat)? {
            guard var bounds = drawnBounds(of: node) else { return nil }
            var reach: CGFloat = 0
            var plain = true
            for modifier in node.modifiers {
                switch modifier {
                case .scaleEffect, .custom:
                    plain = false
                case .shadow(_, let radius, let x, let y):
                    reach = max(reach, radius * 4 + max(abs(x), abs(y)))
                default:
                    break
                }
            }
            if !node.isScrollContainer {
                for child in node.children {
                    guard let inner = visit(child) else { plain = false; continue }
                    bounds = bounds.union(inner.bounds)
                    reach = max(reach, inner.reach)
                }
            }
            guard plain else { return nil }
            // A node without bounds is always drawn.
            table[node.id] = bounds.insetBy(
                dx: -(reach + drawingMargin), dy: -(reach + drawingMargin))
            return (bounds, reach)
        }
        for node in nodes { visit(node) }
        return table
    }
}
