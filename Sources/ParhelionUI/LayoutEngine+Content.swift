#if canImport(Foundation)
import Foundation
#endif

// Layout for shapes and gradients, which the layout engine calls for the
// kinds it does not handle itself.

extension LayoutEngine {
    /// The size of a shape or a gradient view for a proposal, or `nil` for
    /// other nodes. Like a color, each fills the space it is offered.
    func contentSize(_ node: ViewNode, _ proposal: ProposedSize) -> CGSize? {
        guard node.kind == "LinearGradient" || ShapeGeometry(node: node) != nil else {
            return nil
        }
        return CGSize(
            width: proposal.width ?? LayoutDefaults.flexibleIdealSize,
            height: proposal.height ?? LayoutDefaults.flexibleIdealSize
        )
    }
}

// MARK: - Overlays

extension LayoutEngine {
    /// Places a node without its overlays' views, which its overlay
    /// modifiers place, and keeps them as its last children.
    func placeBaseKeepingOverlays(
        _ node: ViewNode, in rect: CGRect, parentAxis: LayoutAxis?
    ) -> ViewNode {
        guard node.children.last?.isOverlayContent == true else {
            return placeBase(node, in: rect, parentAxis: parentAxis)
        }
        var placed = placeBase(node.withoutOverlayContent, in: rect, parentAxis: parentAxis)
        placed.children += node.children.filter(\.isOverlayContent)
        return placed
    }

    /// Places a node inside an overlay modifier, then the overlay's views
    /// over the modifier's bounds, as a `ZStack` with the overlay's
    /// alignment places them.
    func placeOverlay(
        _ node: ViewNode, in rect: CGRect, modifierCount: Int, alignment: Alignment,
        parentAxis: LayoutAxis?
    ) -> ViewNode {
        let inner = modifierCount - 1
        var placed = place(node, in: rect, modifierCount: inner, parentAxis: parentAxis)
        // The first overlay modifier's views are in the first `Overlay`
        // child, and so on.
        let rank = node.modifiers[..<inner].count(where: \.isOverlay)
        guard
            let index = placed.children.indices.filter({ placed.children[$0].isOverlayContent })
                .dropFirst(rank).first
        else { return placed }
        var overlay = placed.children[index]
        overlay.frame = rect
        overlay.children = overlay.children.map { child in
            let size = sizeThatFits(child, ProposedSize(rect.size), parentAxis: nil)
            return place(child, in: align(size, in: rect, alignment), parentAxis: nil)
        }
        placed.children[index] = overlay
        return placed
    }
}

// MARK: - Images

extension LayoutEngine {
    /// The size of an image: a symbol's square, an asset's or a loaded
    /// image's size in points, or, for a missing image, a symbol's square.
    /// A resizable image fills the space it is offered.
    func imageSize(_ node: ViewNode, _ proposal: ProposedSize) -> CGSize {
        let intrinsic: CGSize
        if node.attributes["systemName"] != nil || node.attributes["missingImage"] == "true" {
            let side = Image.symbolSide(of: node)
            intrinsic = CGSize(width: side, height: side)
        } else if let size = parseSize(node.attributes["size"]) {
            intrinsic = size
        } else {
            return .zero
        }
        guard node.attributes["resizable"] == "true" else { return intrinsic }
        return CGSize(
            width: proposal.width ?? intrinsic.width, height: proposal.height ?? intrinsic.height)
    }
}
