#if canImport(Foundation)
import Foundation
#endif

// The bottom bar of a navigation stack: the items of `.bottomBar` toolbar
// items, in a `ToolbarItemGroup` whose `placement` is `bottom`. On iOS 26
// and later they share a glass capsule centered above the home indicator,
// and a single symbol is a glass circle.

extension LayoutDefaults {
    /// Measured on an iPhone on iOS 27: the height of the bottom bar's
    /// glass, and the diameter of a single symbol's circle.
    static let bottomBarHeight: CGFloat = 48
    /// Measured on an iPhone on iOS 27: the distance from the bottom of the
    /// glass to the bottom of the screen.
    static let bottomBarBottomMargin: CGFloat = 28
    /// Assumed: the space between content that does not scroll and the
    /// bottom bar, which centers a view about where an iPhone does.
    static let bottomBarContentGap: CGFloat = 8
}

extension LayoutEngine {
    /// Whether a child of a navigation stack is its bottom bar.
    static func isBottomBar(_ node: ViewNode) -> Bool {
        node.kind == "ToolbarItemGroup" && node.attributes["placement"] == "bottom"
    }

    /// Places a stack's bottom bar centered at the bottom of `rect`, or of
    /// the screen when `rect` reaches the bottom of the safe area.
    func placeBottomBar(_ node: ViewNode, in rect: CGRect) -> ViewNode {
        let height = LayoutDefaults.bottomBarHeight
        let natural = sizeThatFits(node, .unspecified, parentAxis: nil).width
        let width = min(max(natural, height), rect.width)
        let reachesBottom = abs(rect.maxY - device.safeArea.maxY) < 0.5
        let bottom =
            reachesBottom
            ? device.screenSize.height - LayoutDefaults.bottomBarBottomMargin
            : rect.maxY - LayoutDefaults.bottomBarContentGap
        let frame = CGRect(
            x: rect.midX - width / 2, y: bottom - height, width: width, height: height)
        return place(node, in: frame, parentAxis: nil)
    }
}
