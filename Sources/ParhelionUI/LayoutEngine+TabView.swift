#if canImport(Foundation)
import Foundation
#endif

extension LayoutEngine {
    /// A tab view takes the space it is offered, and its content's size
    /// where it is offered none.
    func tabViewSize(_ node: ViewNode, _ proposal: ProposedSize) -> CGSize {
        let content = node.children.filter { $0.kind != "TabBar" }
        let size =
            content.count == 1
            ? sizeThatFits(content[0], proposal, parentAxis: nil)
            : sizeThatFits(
                ViewNode(id: node.id, kind: "VStack", children: content), proposal, parentAxis: nil)
        return CGSize(width: proposal.width ?? size.width, height: proposal.height ?? size.height)
    }

    /// Places the selected tab's content and the tab bar floating over its
    /// bottom.
    ///
    /// Content that scrolls, directly or inside a navigation stack, fills
    /// the tab view and scrolls under the bar, with room to scroll its end
    /// above the bar. Other content is centered above the bar.
    func placeTabView(_ node: ViewNode, in rect: CGRect) -> [ViewNode] {
        guard let bar = node.children.last, bar.kind == "TabBar" else {
            return placeCentered(node.children, id: node.id, in: rect)
        }
        let content = Array(node.children.dropLast())

        // A tab view that reaches the bottom of the safe area floats its bar
        // a fixed distance above the bottom of the screen, below the safe
        // area, as on iOS.
        let screenBottom = device.screenSize.height
        let reachesBottom = abs(rect.maxY - device.safeArea.maxY) < 0.5 || rect.maxY >= screenBottom
        let barBottom =
            (reachesBottom ? screenBottom : rect.maxY) - LayoutDefaults.tabBarBottomMargin
        let margin = LayoutDefaults.tabBarMargin
        let barRect = CGRect(
            x: rect.minX + margin, y: barBottom - LayoutDefaults.tabBarHeight,
            width: max(rect.width - 2 * margin, 0), height: LayoutDefaults.tabBarHeight)

        // Assumed: content that is not a scroll view, or a navigation stack
        // around one, stays above the bar, as it would in the safe area that
        // iOS reduces by the bar's height.
        let scrolls = content.count == 1 && Self.scrollsUnderBars(content[0])
        let contentRect =
            scrolls
            ? rect
            : CGRect(
                x: rect.minX, y: rect.minY, width: rect.width,
                height: max(min(rect.maxY, barRect.minY) - rect.minY, 0))
        let outer = scrolling.obscuredBottom
        scrolling.obscuredBottom = barRect.minY
        let placedContent = placeCentered(content, id: node.id, in: contentRect)
        scrolling.obscuredBottom = outer
        return placedContent + [placeTabBar(bar, in: barRect)]
    }

    /// Whether a view fills the space below a bar and scrolls under it: a
    /// scroll view or list, or a navigation stack whose screen is one.
    private static func scrollsUnderBars(_ node: ViewNode) -> Bool {
        if node.isScrollContainer { return true }
        guard node.kind == "NavigationStack" else { return false }
        let screen = node.children.filter { $0.kind != "NavigationBar" }
        return screen.count == 1 && screen[0].isScrollContainer
    }

    /// Places the tabs in the bar's capsule, sharing its width equally, and
    /// the search tab in its own circle at the trailing end. Each tab's
    /// button fills its part of the bar, so the whole bar responds to taps.
    private func placeTabBar(_ bar: ViewNode, in rect: CGRect) -> ViewNode {
        var bar = bar
        bar.frame = rect
        let isSearch: (ViewNode) -> Bool = { $0.attributes["role"] == "search" }
        let tabCount = bar.children.filter { !isSearch($0) }.count
        let hasSearch = tabCount < bar.children.count
        let searchSide = rect.height
        let capsuleWidth =
            hasSearch
            ? max(rect.width - searchSide - LayoutDefaults.tabBarSearchSpacing, 0) : rect.width
        let insets = LayoutDefaults.tabBarItemInsets
        let tabWidth = max(capsuleWidth - insets.horizontal, 0) / CGFloat(max(tabCount, 1))
        var x = rect.minX + insets.leading
        bar.children = bar.children.map { item in
            if isSearch(item) {
                let circle = CGRect(
                    x: rect.maxX - searchSide, y: rect.minY, width: searchSide, height: searchSide)
                return placeTabBarItem(item, in: circle, symbolCenter: circle.midY)
            }
            let cell = CGRect(
                x: x, y: rect.minY + insets.top, width: tabWidth,
                height: rect.height - insets.vertical)
            x += tabWidth
            return placeTabBarItem(
                item, in: cell, symbolCenter: cell.minY + LayoutDefaults.tabBarSymbolCenter)
        }
        return bar
    }

    /// Places a tab's symbol, centered across the tab at `symbolCenter`, and
    /// its title below it.
    private func placeTabBarItem(
        _ item: ViewNode, in cell: CGRect, symbolCenter: CGFloat
    )
        -> ViewNode
    {
        var item = item
        item.frame = cell
        item.children = item.children.map { child in
            let size = sizeThatFits(
                child, ProposedSize(width: cell.width, height: nil), parentAxis: nil)
            let y =
                child.kind == "Text"
                ? cell.minY + LayoutDefaults.tabBarTitleTop : symbolCenter - size.height / 2
            return place(
                child,
                in: CGRect(
                    x: cell.midX - size.width / 2, y: y, width: size.width, height: size.height),
                parentAxis: nil)
        }
        return item
    }
}
