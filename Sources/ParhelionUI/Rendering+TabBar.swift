import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

extension TreeRenderer {
    /// Draws the tab bar's glass, a capsule behind the tabs and a circle
    /// behind the search tab, and the highlight behind the selected tab. The
    /// tabs' buttons draw their symbols and titles afterward.
    ///
    /// The kit's tab bar uses the same Liquid Glass recipe as its toolbar
    /// buttons, so it is drawn with the appearance's small glass.
    func drawTabBar(
        _ node: ViewNode, in frame: CGRect, opacity: Double, palette: ColorPalette.Appearance,
        paint: (RGBA) -> RGBA, into canvas: inout Canvas
    ) {
        let search = node.children.first { $0.attributes["role"] == "search" }?.frame
        var capsule = frame
        if let search {
            capsule.size.width = max(
                search.minX - LayoutDefaults.tabBarSearchSpacing - frame.minX, 0)
        }
        if capsule.width > 0, node.children.count > (search == nil ? 0 : 1) {
            canvas.drawGlass(
                capsule, cornerRadius: capsule.height / 2, material: palette.smallGlass,
                opacity: opacity)
        }
        if let search {
            canvas.drawGlass(
                search, cornerRadius: search.height / 2, material: palette.smallGlass,
                opacity: opacity)
        }

        guard let selected = node.children.first(where: { $0.attributes["selected"] == "true" }),
            var highlight = selected.frame
        else { return }
        if selected.attributes["role"] == "search" {
            // Assumed: a selected search tab is highlighted like a tab,
            // inside its circle by the capsule's inset.
            let inset = LayoutDefaults.tabBarItemInsets.top
            highlight = highlight.insetBy(dx: inset, dy: inset)
        } else {
            highlight = highlight.insetBy(dx: -LayoutDefaults.tabBarSelectionOutset, dy: 0)
        }
        canvas.fill(
            highlight, cornerRadius: highlight.height / 2,
            color: paint(palette.tabBarSelection))
    }
}
