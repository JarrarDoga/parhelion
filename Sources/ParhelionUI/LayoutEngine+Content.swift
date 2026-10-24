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
