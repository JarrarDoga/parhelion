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

extension View {
    /// Adds a search field to the view and binds its text.
    ///
    /// The field is a `SearchField` node inside a `Searchable` node that also
    /// holds the view's content. In the content of a tab with the search
    /// role, and with the automatic or toolbar placement, it is a glass
    /// capsule at the bottom, above the tab bar, as in iOS 26. Anywhere else,
    /// in a navigation stack or a sheet, it is a capsule under the
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
        // Assumed: the placement chooses the top unless the view is in a
        // search tab and the placement is the automatic or toolbar one.
        let atBottom =
            evaluator.environment.isInSearchTab
            && (placement == .automatic || placement == .toolbar)

        let binding = text
        let dismiss = DismissSearchAction { @MainActor in
            try? host.focus(nil)
            binding.wrappedValue = ""
        }
        let contentNodes = evaluator.withEnvironment({
            $0.isSearching = isSearching
            $0.dismissSearch = dismiss
            $0.isInSearchTab = false
        }) {
            evaluator.evaluate(content, at: ownPath)
        }
        let row = SearchFieldRow(
            text: text, prompt: prompt ?? "Search", atBottom: atBottom, isSearching: isSearching,
            dismiss: dismiss)
        let field = ViewNode(
            id: fieldPath.id, kind: searchFieldComponent,
            attributes: ["placement": atBottom ? "bottom" : "top"],
            children: evaluator.evaluate(row, at: fieldPath))

        var attributes = ["placement": atBottom ? "bottom" : "top"]
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
    let atBottom: Bool
    let isSearching: Bool
    let dismiss: DismissSearchAction

    /// Assumed: the iOS 26 search field is 36 points tall at the top and 48
    /// at the bottom, in the tertiary fill or in glass.
    static let topHeight: CGFloat = 36
    static let bottomHeight: CGFloat = 48

    var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
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
        .padding(.horizontal, 12)
    }

    var body: some View {
        HStack(spacing: 12) {
            if atBottom {
                field.frame(height: Self.bottomHeight).glassEffect(.regular, in: .capsule)
            } else {
                field.frame(height: Self.topHeight)
                    .background(Color(name: ColorPalette.tertiaryFillStyle))
                    .clipShape(Capsule())
            }
            if isSearching && !atBottom {
                Button("Cancel") { dismiss() }.buttonStyle(.plain).foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// How a `Searchable` node is laid out: its content and its field stacked,
/// the field first at the top and last at the bottom.
enum SearchableLayout {
    static let behavior = NodeBehavior(
        size: { engine, node, proposal, axis in
            engine.sizeThatFits(stack(of: node).stack, proposal, parentAxis: axis)
        },
        place: { engine, node, rect in
            let (stack, wrapper) = stack(of: node)
            let placed = engine.place(stack, in: rect, parentAxis: nil).children
            let content = placed.filter { $0.kind != searchFieldComponent }
            let field = placed.filter { $0.kind == searchFieldComponent }
            // Put the content back as it came: not inside the wrapper that
            // stacks several views.
            let unwrapped = content.flatMap { $0.id == wrapper ? $0.children : [$0] }
            return unwrapped + field
        })

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
        let atBottom = node.attributes["placement"] == "bottom"
        return (
            ViewNode(
                id: node.id, kind: "VStack", attributes: ["spacing": "0"],
                children: atBottom ? [contentNode] + field : field + [contentNode]), wrapper
        )
    }
}
