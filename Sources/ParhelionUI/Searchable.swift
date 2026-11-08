#if canImport(Foundation)
import Foundation
#endif

/// Where a search field goes, mirroring SwiftUI's `SearchFieldPlacement`.
public struct SearchFieldPlacement: Hashable, Sendable {
    /// How the field shows in the navigation bar.
    public struct NavigationBarDrawerDisplayMode: Hashable, Sendable {
        let name: String

        public static let automatic = NavigationBarDrawerDisplayMode(name: "automatic")
        public static let always = NavigationBarDrawerDisplayMode(name: "always")
    }

    let name: String

    public static let automatic = SearchFieldPlacement(name: "automatic")
    public static let toolbar = SearchFieldPlacement(name: "toolbar")
    public static let toolbarPrincipal = SearchFieldPlacement(name: "toolbarPrincipal")
    public static let sidebar = SearchFieldPlacement(name: "sidebar")
    public static let navigationBarDrawer = SearchFieldPlacement(name: "navigationBarDrawer")

    public static func navigationBarDrawer(
        displayMode: NavigationBarDrawerDisplayMode
    ) -> SearchFieldPlacement {
        SearchFieldPlacement(name: "navigationBarDrawer.\(displayMode.name)")
    }
}

struct IsSearchingKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

/// Whether the view is in the content of a tab with the search role, where
/// an automatic search field goes at the bottom, as in iOS 26.
struct IsInSearchTabKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

/// Ends a search, mirroring SwiftUI's `DismissSearchAction`.
public struct DismissSearchAction: Sendable {
    let action: @MainActor @Sendable () -> Void

    init(_ action: @escaping @MainActor @Sendable () -> Void = {}) {
        self.action = action
    }

    /// Clears the search text and ends editing in the search field.
    @MainActor
    public func callAsFunction() {
        action()
    }
}

struct DismissSearchKey: EnvironmentKey {
    static var defaultValue: DismissSearchAction { DismissSearchAction() }
}

/// Whether the view is in a tab of a tab view, whose bar takes the bottom of
/// the screen, so an automatic search field goes under the navigation bar.
struct IsInTabViewKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

/// The search field of a `searchable` on a tab view, which the tab view's
/// search tab takes. The tab sets `isTaken`, so the `searchable` knows to
/// show no field of its own.
@MainActor
final class TabViewSearch {
    let text: Binding<String>
    let prompt: String?
    var isTaken = false

    init(text: Binding<String>, prompt: String?) {
        self.text = text
        self.prompt = prompt
    }
}

struct TabViewSearchKey: EnvironmentKey {
    static var defaultValue: TabViewSearch? { nil }
}

extension EnvironmentValues {
    /// Whether the user is searching: the search field of an enclosing
    /// ``View/searchable(text:placement:prompt:)`` is focused or holds text.
    /// Read it in the searchable view's content, not on the view that
    /// applies the modifier, as in SwiftUI.
    public internal(set) var isSearching: Bool {
        get { self[IsSearchingKey.self] }
        set { self[IsSearchingKey.self] = newValue }
    }

    var isInSearchTab: Bool {
        get { self[IsInSearchTabKey.self] }
        set { self[IsInSearchTabKey.self] = newValue }
    }

    var isInTabView: Bool {
        get { self[IsInTabViewKey.self] }
        set { self[IsInTabViewKey.self] = newValue }
    }

    var tabViewSearch: TabViewSearch? {
        get { self[TabViewSearchKey.self] }
        set { self[TabViewSearchKey.self] = newValue }
    }

    /// An action that ends the search of the enclosing `searchable`: it
    /// clears the text and ends editing.
    public internal(set) var dismissSearch: DismissSearchAction {
        get { self[DismissSearchKey.self] }
        set { self[DismissSearchKey.self] = newValue }
    }
}

/// The path component, and node kind, of a search field.
let searchFieldComponent = "SearchField"

extension NodeID {
    /// Whether this node is inside a search field, whose focus changes what
    /// the content of its `searchable` sees as `isSearching`.
    var isInSearchField: Bool { rawValue.contains("/\(searchFieldComponent)/") }
}

extension ViewNode {
    /// The scroll view that this node shows as a screen, which scrolls under
    /// the bars: the node itself, or the content of a `searchable` whose field
    /// is under the navigation bar or floats over the bottom of the screen.
    var screenScrollView: ViewNode? {
        if isScrollContainer { return self }
        guard kind == "Searchable",
            attributes["placement"] != SearchFieldPosition.bottom.rawValue
        else { return nil }
        let content = children.filter { $0.kind != searchFieldComponent }
        return content.count == 1 && content[0].isScrollContainer ? content[0] : nil
    }
}

/// Where a search field is, recorded as the `placement` attribute.
enum SearchFieldPosition: String {
    /// Under the navigation bar.
    case top
    /// Above the tab bar, in a tab with the search role.
    case bottom
    /// Floating over the bottom of the screen, as the bottom toolbar does.
    case toolbar
}

extension View {
    /// Adds a search field to the view and binds its text.
    ///
    /// The field is a `SearchField` node inside a `Searchable` node that also
    /// holds the view's content. With the automatic or toolbar placement, as
    /// in iOS 26:
    /// - in a navigation stack outside a tab view, it is a glass capsule
    ///   floating over the bottom of the screen, and a list under it scrolls
    ///   under it and under the navigation bar;
    /// - on a tab view with a tab of the search role, it belongs to that tab,
    ///   and shows only while the tab is selected;
    /// - in the content of a tab with the search role, it is a glass capsule
    ///   above the tab bar.
    ///
    /// In another tab, or with another placement, it is a capsule under the
    /// navigation bar, with a Cancel button while the user searches.
    /// Focusing the field, tapping it, or `type_text` after focusing it,
    /// writes the binding. `isSearching` is true in the content while the
    /// field is focused or holds text.
    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: Text? = nil
    ) -> some View {
        Searchable(content: self, text: text, placement: placement, prompt: prompt?.content)
    }

    /// Adds a search field to the view and binds its text, with a prompt
    /// shown while the field is empty.
    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: some StringProtocol
    ) -> some View {
        Searchable(content: self, text: text, placement: placement, prompt: String(prompt))
    }
}

/// The view that `searchable` returns.
struct Searchable<Content: View>: View, PrimitiveView {
    typealias Body = Never

    let content: Content
    let text: Binding<String>
    let placement: SearchFieldPlacement
    let prompt: String?

    var body: Never {
        fatalError("searchable is a primitive view and has no body.")
    }

    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        NodeExtensions.registerOnce(kind: "Searchable") { SearchableLayout.behavior }
        let ownPath = path.appending("Searchable")
        let fieldPath = ownPath.appending(searchFieldComponent)
        let host = evaluator.host
        let focused =
            host.focusedNodeID.map { $0.rawValue.hasPrefix(fieldPath.id.rawValue + "/") } ?? false
        let isSearching = focused || !text.wrappedValue.isEmpty
        // Measured on an iPhone under iOS 27: the automatic field is at the
        // bottom of the screen in a navigation stack, and in a search tab.
        // Assumed: in another tab, where the tab bar takes the bottom, it is
        // under the navigation bar, as with an explicit placement.
        let automatic = placement == .automatic || placement == .toolbar
        let environment = evaluator.environment
        var position: SearchFieldPosition =
            !automatic
            ? .top : environment.isInSearchTab ? .bottom : environment.isInTabView ? .top : .toolbar
        // On a tab view, the field goes to its search tab, if it has one.
        let tabViewSearch =
            position == .toolbar ? TabViewSearch(text: text, prompt: prompt) : nil

        let binding = text
        let dismiss = DismissSearchAction { @MainActor in
            try? host.focus(nil)
            binding.wrappedValue = ""
        }
        let contentNodes = evaluator.withEnvironment({
            $0.isSearching = isSearching
            $0.dismissSearch = dismiss
            $0.isInSearchTab = false
            $0.tabViewSearch = tabViewSearch
        }) {
            evaluator.evaluate(content, at: ownPath)
        }
        if tabViewSearch?.isTaken == true { return contentNodes }
        // Assumed: a tab view without a search tab keeps the field above it.
        if contentNodes.count == 1, contentNodes[0].kind == "TabView" { position = .top }

        let row = SearchFieldRow(
            text: text, prompt: prompt ?? "Search", position: position, isSearching: isSearching,
            dismiss: dismiss)
        let field = ViewNode(
            id: fieldPath.id, kind: searchFieldComponent,
            attributes: ["placement": position.rawValue],
            children: evaluator.evaluate(row, at: fieldPath))

        var attributes = ["placement": position.rawValue]
        if isSearching { attributes["isSearching"] = "true" }
        return [
            ViewNode(
                id: ownPath.id, kind: "Searchable", attributes: attributes,
                children: contentNodes + [field])
        ]
    }
}

/// The contents of the search field: a magnifying glass, the text, a clear
/// button while there is text, and a Cancel button while searching at the
/// top.
private struct SearchFieldRow: View {
    let text: Binding<String>
    let prompt: String
    let position: SearchFieldPosition
    let isSearching: Bool
    let dismiss: DismissSearchAction

    /// Measured on an iPhone 18 Pro Max under iOS 27.2: in the glass capsule
    /// at the bottom, the magnifying glass is in the primary color, 14
    /// points from the capsule's end, and the text 42 points from it.
    var isGlass: Bool { position != .top }

    var field: some View {
        HStack(spacing: isGlass ? 10 : 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isGlass ? HierarchicalShapeStyle.primary : .secondary)
            TextField(prompt, text: text).frame(maxWidth: .infinity)
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear text")
            }
        }
        .padding(.horizontal, isGlass ? 14 : 12)
    }

    var body: some View {
        switch position {
        case .toolbar:
            // The layout places the capsule; it has no space around it.
            field.frame(height: SearchableLayout.glassHeight).glassEffect(.regular, in: .capsule)
        case .bottom:
            field.frame(height: SearchableLayout.glassHeight).glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        case .top:
            HStack(spacing: 12) {
                field.frame(height: SearchableLayout.topHeight)
                    .background(Color(name: ColorPalette.tertiaryFillStyle))
                    .clipShape(Capsule())
                if isSearching {
                    Button("Cancel") { dismiss() }.buttonStyle(.plain).foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

/// How a `Searchable` node is laid out.
///
/// A field floating over the bottom of the screen leaves the content the
/// whole space, and a scroll view under it can scroll its end above it. A
/// field under the navigation bar of a screen that scrolls under the bar
/// takes the top of what the bar leaves, and the scroll view's content
/// starts below the field. Otherwise the field and the content are stacked,
/// the field first at the top and last above the tab bar.
enum SearchableLayout {
    /// Assumed: the field under the navigation bar is 36 points tall.
    static let topHeight: CGFloat = 36
    /// The glass capsule at the bottom is 48 points tall, measured on an
    /// iPhone 18 Pro Max under iOS 27.2.
    static let glassHeight: CGFloat = 48
    /// The space between the floating field and the sides and bottom of the
    /// screen, 28 points, measured on the same iPhone.
    static let toolbarMargin: CGFloat = 28

    static let behavior = NodeBehavior(
        size: { engine, node, proposal, axis in
            engine.sizeThatFits(stack(of: node).stack, proposal, parentAxis: axis)
        },
        place: { engine, node, rect in
            let position = SearchFieldPosition(rawValue: node.attributes["placement"] ?? "")
            if position == .toolbar {
                return placeFloating(engine, node, in: rect)
            }
            if position == .top, node.screenScrollView != nil,
                let top = engine.scrolling.obscuredTop
            {
                return placeUnderBar(engine, node, below: top, in: rect)
            }
            let (stack, wrapper) = stack(of: node)
            let placed = engine.place(stack, in: rect, parentAxis: nil).children
            let content = placed.filter { $0.kind != searchFieldComponent }
            let field = placed.filter { $0.kind == searchFieldComponent }
            // Put the content back as it came: not inside the wrapper that
            // stacks several views.
            let unwrapped = content.flatMap { $0.id == wrapper ? $0.children : [$0] }
            return unwrapped + field
        })

    /// Places the field over the bottom of the screen, below the safe area
    /// as the tab bar is, and the content in the whole space, or above the
    /// field when it does not scroll.
    private static func placeFloating(
        _ engine: LayoutEngine, _ node: ViewNode, in rect: CGRect
    ) -> [ViewNode] {
        let (content, field) = parts(of: node)
        let device = engine.device
        let screenBottom = device.screenSize.height
        let reachesBottom = abs(rect.maxY - device.safeArea.maxY) < 0.5 || rect.maxY >= screenBottom
        let bottom = (reachesBottom ? screenBottom : rect.maxY) - toolbarMargin
        let fieldRect = CGRect(
            x: rect.minX + toolbarMargin, y: bottom - glassHeight,
            width: max(rect.width - 2 * toolbarMargin, 0), height: glassHeight)
        let scrolls = node.screenScrollView != nil
        let contentRect =
            scrolls
            ? rect
            : CGRect(
                x: rect.minX, y: rect.minY, width: rect.width,
                height: max(min(rect.maxY, fieldRect.minY) - rect.minY, 0))
        let scrolling = engine.scrolling
        let outer = scrolling.obscuredBottom
        scrolling.obscuredBottom = min(outer ?? fieldRect.minY, fieldRect.minY)
        let placedContent = engine.placeCentered(content, id: node.id, in: contentRect)
        scrolling.obscuredBottom = outer
        return placedContent + field.map { engine.place($0, in: fieldRect, parentAxis: nil) }
    }

    /// Places the field below the navigation bar, and the scroll view in the
    /// whole space with its content starting below the field.
    private static func placeUnderBar(
        _ engine: LayoutEngine, _ node: ViewNode, below top: CGFloat, in rect: CGRect
    ) -> [ViewNode] {
        let (content, field) = parts(of: node)
        let placedField = field.map { field in
            let size = engine.sizeThatFits(
                field, ProposedSize(width: rect.width, height: nil), parentAxis: nil)
            return engine.place(
                field, in: CGRect(x: rect.minX, y: top, width: rect.width, height: size.height),
                parentAxis: nil)
        }
        let scrolling = engine.scrolling
        let outer = scrolling.obscuredTop
        scrolling.obscuredTop = placedField.first?.frame?.maxY ?? top
        let placedContent = content.map { engine.place($0, in: rect, parentAxis: nil) }
        scrolling.obscuredTop = outer
        return placedContent + placedField
    }

    private static func parts(of node: ViewNode) -> (content: [ViewNode], field: [ViewNode]) {
        (
            node.children.filter { $0.kind != searchFieldComponent },
            node.children.filter { $0.kind == searchFieldComponent }
        )
    }

    /// A vertical stack of the node's content, as one view, and its field.
    /// `wrapper` is the identifier of the stack that holds several content
    /// views.
    private static func stack(of node: ViewNode) -> (stack: ViewNode, wrapper: NodeID?) {
        let field = Array(node.children.suffix(1))
        let content = Array(node.children.dropLast())
        var wrapper: NodeID?
        let contentNode: ViewNode
        if content.count == 1 {
            contentNode = content[0]
        } else {
            let id = NodeID(node.id.rawValue + "/content")
            wrapper = id
            contentNode = ViewNode(
                id: id, kind: "VStack", attributes: ["spacing": "0"], children: content)
        }
        let atBottom = node.attributes["placement"] != SearchFieldPosition.top.rawValue
        return (
            ViewNode(
                id: node.id, kind: "VStack", attributes: ["spacing": "0"],
                children: atBottom ? [contentNode] + field : field + [contentNode]), wrapper
        )
    }
}
