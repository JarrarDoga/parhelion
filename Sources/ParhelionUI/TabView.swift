#if canImport(Foundation)
import Foundation
#endif

/// A view that switches between child views with a tab bar, mirroring
/// SwiftUI's `TabView`.
///
/// Only the selected tab's content is on screen, under iOS 27's floating
/// glass tab bar. Every tab is evaluated on every update, so each tab keeps
/// its state and its navigation stack while another one is selected. A tab
/// with the ``TabRole/search`` role is a separate glass circle at the
/// trailing end of the bar.
///
/// The bar is a `TabBar` node after the content, with one `Button` per tab,
/// so tapping a tab by identifier, by its title, or by position selects it.
/// The selected tab's button records `selected=true`.
public struct TabView<SelectionValue: Hashable, Content: View>: View {
    public typealias Body = Never

    let selection: Binding<SelectionValue>?
    let content: Content

    public var body: Never {
        fatalError("TabView is a primitive view and has no body.")
    }
}

extension TabView {
    /// Creates a tab view whose tabs are views with ``View/tabItem(_:)``
    /// labels. A tab is selected when its tag equals `selection`.
    public init(selection: Binding<SelectionValue>?, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.content = content()
    }

    /// Creates a tab view that selects the ``Tab`` whose value equals
    /// `selection`.
    public init<C: TabContent>(
        selection: Binding<SelectionValue>,
        @TabContentBuilder<SelectionValue> content: () -> C
    ) where Content == TabContentBuilder<SelectionValue>.Content<C> {
        self.selection = selection
        self.content = TabContentBuilder<SelectionValue>.Content(content: content())
    }
}

extension TabView where SelectionValue == Int {
    /// Creates a tab view whose tabs are views with ``View/tabItem(_:)``
    /// labels, and which keeps its own selection.
    public init(@ViewBuilder content: () -> Content) {
        self.init(selection: nil, content: content)
    }
}

extension TabView where SelectionValue == Never {
    /// Creates a tab view of ``Tab`` values that keeps its own selection.
    public init<C: TabContent>(@TabContentBuilder<Never> content: () -> C)
    where Content == TabContentBuilder<Never>.Content<C> {
        selection = nil
        self.content = TabContentBuilder<Never>.Content(content: content())
    }
}

// MARK: - Tabs

/// What a tab is for, which changes where its button goes, mirroring
/// SwiftUI's `TabRole`.
public struct TabRole: Hashable, Sendable {
    let name: String

    /// A search tab: a separate glass circle at the trailing end of the tab
    /// bar, with a magnifying glass unless the tab has its own label.
    public static let search = TabRole(name: "search")

    /// A prominent tab. Parhelion draws it like any other tab.
    public static let prominent = TabRole(name: "prominent")
}

/// Content of a tab view, mirroring SwiftUI's `TabContent`.
@MainActor
@preconcurrency
public protocol TabContent<TabValue> {
    /// The type of the values that select tabs.
    associatedtype TabValue: Hashable
    associatedtype Body: TabContent

    @TabContentBuilder<TabValue>
    var body: Body { get }
}

extension Never: TabContent {
    public typealias TabValue = Never
}

/// One tab of a ``TabView``: its content and the label its button shows,
/// mirroring SwiftUI's `Tab`.
public struct Tab<Value: Hashable, Content: View, Label: View>: TabContent {
    public typealias TabValue = Value
    public typealias Body = Never

    let value: Value?
    let role: TabRole?
    let content: Content
    let label: Label

    public var body: Never {
        fatalError("Tab is primitive tab content and has no body.")
    }
}

extension Tab where Label == EmptyView {
    /// Creates a tab without a label.
    public init(@ViewBuilder content: () -> Content) {
        self.init(value: nil, role: nil, content: content(), label: EmptyView())
    }

    /// Creates a tab without a label that the tab view selects when its
    /// selection equals `value`.
    public init(value: Value, @ViewBuilder content: () -> Content) {
        self.init(value: value, role: nil, content: content(), label: EmptyView())
    }
}

extension Tab where Label == DefaultTabLabel {
    /// Creates a tab with the label of its role: a search tab shows a
    /// magnifying glass, titled "Search".
    public init(role: TabRole?, @ViewBuilder content: () -> Content) {
        self.init(value: nil, role: role, content: content(), label: DefaultTabLabel(role: role))
    }

    /// Creates a tab with the label of its role that the tab view selects
    /// when its selection equals `value`.
    public init(value: Value, role: TabRole?, @ViewBuilder content: () -> Content) {
        self.init(value: value, role: role, content: content(), label: DefaultTabLabel(role: role))
    }

    /// Creates a tab with a title and a symbol.
    public init(
        _ title: some StringProtocol, systemImage: String, @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: nil, role: nil, content: content(),
            label: DefaultTabLabel(title: String(title), systemImage: systemImage))
    }

    /// Creates a tab with a title and a symbol that the tab view selects when
    /// its selection equals `value`.
    public init(
        _ title: some StringProtocol, systemImage: String, value: Value,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: value, role: nil, content: content(),
            label: DefaultTabLabel(title: String(title), systemImage: systemImage))
    }

    /// Creates a tab with a title, a symbol, and a role.
    public init(
        _ title: some StringProtocol, systemImage: String, role: TabRole?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: nil, role: role, content: content(),
            label: DefaultTabLabel(title: String(title), systemImage: systemImage))
    }

    /// Creates a tab with a title, a symbol, and a role that the tab view
    /// selects when its selection equals `value`.
    public init(
        _ title: some StringProtocol, systemImage: String, value: Value, role: TabRole?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: value, role: role, content: content(),
            label: DefaultTabLabel(title: String(title), systemImage: systemImage))
    }

    /// Creates a tab with a title and an image from the app's assets, which
    /// Parhelion does not draw.
    public init(_ title: some StringProtocol, image: String, @ViewBuilder content: () -> Content) {
        self.init(
            value: nil, role: nil, content: content(),
            label: DefaultTabLabel(title: String(title), image: image))
    }

    /// Creates a tab with a title and an image from the app's assets that the
    /// tab view selects when its selection equals `value`.
    public init(
        _ title: some StringProtocol, image: String, value: Value,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: value, role: nil, content: content(),
            label: DefaultTabLabel(title: String(title), image: image))
    }

    /// Creates a tab with a title, an image from the app's assets, and a
    /// role.
    public init(
        _ title: some StringProtocol, image: String, role: TabRole?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: nil, role: role, content: content(),
            label: DefaultTabLabel(title: String(title), image: image))
    }

    /// Creates a tab with a title, an image from the app's assets, and a role
    /// that the tab view selects when its selection equals `value`.
    public init(
        _ title: some StringProtocol, image: String, value: Value, role: TabRole?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: value, role: role, content: content(),
            label: DefaultTabLabel(title: String(title), image: image))
    }
}

extension Tab {
    /// Creates a tab with a custom label.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.init(value: nil, role: nil, content: content(), label: label())
    }

    /// Creates a tab with a custom label that the tab view selects when its
    /// selection equals `value`.
    public init(
        value: Value, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label
    ) {
        self.init(value: value, role: nil, content: content(), label: label())
    }

    /// Creates a tab with a role and a custom label.
    public init(
        role: TabRole?, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label
    ) {
        self.init(value: nil, role: role, content: content(), label: label())
    }

    /// Creates a tab with a role and a custom label that the tab view selects
    /// when its selection equals `value`.
    public init(
        value: Value, role: TabRole?, @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(value: value, role: role, content: content(), label: label())
    }
}

/// The label a ``Tab`` shows when it is created with a title and an image,
/// or with only a role, mirroring SwiftUI's `DefaultTabLabel`.
public struct DefaultTabLabel: View {
    let title: String
    let icon: Image?

    init(title: String, systemImage: String) {
        self.title = title
        icon = Image(systemName: systemImage)
    }

    init(title: String, image: String) {
        self.title = title
        icon = Image(image)
    }

    /// The label of a role. Assumed: a search tab is titled "Search", with
    /// the magnifying glass of the iOS 27 UI Kit's search tab, and other
    /// roles have no label of their own.
    init(role: TabRole?) {
        title = role == .search ? "Search" : ""
        icon = role == .search ? Image(systemName: "magnifyingglass") : nil
    }

    public var body: some View {
        Label {
            Text(title)
        } icon: {
            if let icon { icon }
        }
    }
}

// MARK: - Building tab content

/// Builds the tabs of a ``TabView`` from closures, mirroring SwiftUI's
/// `TabContentBuilder`.
@MainActor
@resultBuilder
public struct TabContentBuilder<TabValue: Hashable> {
    /// The content of a tab view built from ``Tab`` values.
    public struct Content<C: TabContent>: View {
        public typealias Body = Never

        let content: C

        public var body: Never {
            fatalError("TabContentBuilder.Content is a primitive view and has no body.")
        }
    }

    public static func buildExpression<C: TabContent>(_ content: C) -> C
    where C.TabValue == TabValue {
        content
    }

    /// Lets primitive tab content, whose body is `Never`, have a body that
    /// stops the program.
    public static func buildExpression(_ never: Never) -> Never {}

    public static func buildBlock(_ never: Never) -> Never {}

    public static func buildBlock<C: TabContent>(_ content: C) -> C where C.TabValue == TabValue {
        content
    }

    public static func buildBlock<each C: TabContent>(
        _ content: repeat each C
    ) -> TupleTabContent<TabValue, (repeat each C)> {
        var elements: [any TabContent] = []
        for element in repeat each content {
            elements.append(element)
        }
        return TupleTabContent(elements: elements)
    }

    public static func buildIf<C: TabContent>(_ content: C?) -> _OptionalTabContent<C>
    where C.TabValue == TabValue {
        _OptionalTabContent(wrapped: content)
    }

    public static func buildEither<T: TabContent, F: TabContent>(
        first: T
    ) -> _ConditionalTabContent<T, F> where T.TabValue == TabValue, F.TabValue == TabValue {
        _ConditionalTabContent(content: first, branch: "if")
    }

    public static func buildEither<T: TabContent, F: TabContent>(
        second: F
    ) -> _ConditionalTabContent<T, F> where T.TabValue == TabValue, F.TabValue == TabValue {
        _ConditionalTabContent(content: second, branch: "else")
    }
}

/// Several tabs, produced by ``TabContentBuilder``.
public struct TupleTabContent<TabValue: Hashable, T>: TabContent {
    public typealias Body = Never

    let elements: [any TabContent]

    public var body: Never {
        fatalError("TupleTabContent is primitive tab content and has no body.")
    }
}

/// A tab that may be absent, produced by `if` in a ``TabContentBuilder``.
public struct _OptionalTabContent<Wrapped: TabContent>: TabContent {
    public typealias TabValue = Wrapped.TabValue
    public typealias Body = Never

    let wrapped: Wrapped?

    public var body: Never {
        fatalError("_OptionalTabContent is primitive tab content and has no body.")
    }
}

/// One of two pieces of tab content, produced by `if`/`else` in a
/// ``TabContentBuilder``.
public struct _ConditionalTabContent<TrueContent: TabContent, FalseContent: TabContent>:
    TabContent
where TrueContent.TabValue == FalseContent.TabValue {
    public typealias TabValue = TrueContent.TabValue
    public typealias Body = Never

    let content: any TabContent
    let branch: String

    public var body: Never {
        fatalError("_ConditionalTabContent is primitive tab content and has no body.")
    }
}

// MARK: - Tab items

extension View {
    /// Sets the label of this view's button in the tab bar of the enclosing
    /// ``TabView``. The tab bar shows the first symbol image and the first
    /// text in the label.
    public func tabItem<V: View>(@ViewBuilder _ label: () -> V) -> some View {
        TabItemView(content: self, label: label())
    }
}

/// A view that passes its tab item's label to the enclosing tab view.
struct TabItemView<Content: View, Label: View>: View {
    typealias Body = Never

    let content: Content
    let label: Label

    var body: Never {
        fatalError("TabItemView is a primitive view and has no body.")
    }
}

extension TabItemView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        // Tab items inside this view belong to a tab view inside it, if any.
        let collector = evaluator.environment.tabItemCollector
        let nodes = evaluator.withEnvironment({ $0.tabItemCollector = nil }) {
            evaluator.evaluate(content, at: path)
        }
        guard let collector, let first = nodes.first else { return nodes }
        collector.labels[first.id] = evaluator.evaluate(label, at: path.appending("tabItem"))
        return nodes
    }
}

/// The labels that views declare with ``View/tabItem(_:)`` while a tab view
/// evaluates its content, by the identifier of each view's first node.
@MainActor
final class TabItemCollector {
    var labels: [NodeID: [ViewNode]] = [:]
}

struct TabItemCollectorKey: EnvironmentKey {
    static var defaultValue: TabItemCollector? { nil }
}

extension EnvironmentValues {
    /// Where views record their tab items while a tab view evaluates its
    /// content.
    var tabItemCollector: TabItemCollector? {
        get { self[TabItemCollectorKey.self] }
        set { self[TabItemCollectorKey.self] = newValue }
    }
}

// MARK: - Evaluation

/// One tab, evaluated.
struct EvaluatedTab {
    /// The value or tag that selects the tab, if it has one.
    var value: AnyHashable?
    var role: TabRole?
    /// The nodes of the tab's label, which the bar takes its symbol and
    /// title from.
    var label: [ViewNode]
    var content: [ViewNode]
}

/// Tab content that the evaluator turns into tabs directly.
@MainActor
protocol PrimitiveTabContent {
    func makeTabs(in evaluator: Evaluator, at path: ViewPath) -> [EvaluatedTab]
}

extension Evaluator {
    /// The tabs of any tab content: primitive content directly, and other
    /// content through its `body`.
    func evaluateTabs(_ content: any TabContent, at path: ViewPath) -> [EvaluatedTab] {
        if let primitive = content as? any PrimitiveTabContent {
            return primitive.makeTabs(in: self, at: path)
        }
        return evaluateTabs(
            tabBody(of: content), at: path.appending(baseTypeName(of: type(of: content))))
    }

    private func tabBody<C: TabContent>(of content: C) -> any TabContent {
        content.body
    }
}

extension Tab: PrimitiveTabContent {
    func makeTabs(in evaluator: Evaluator, at path: ViewPath) -> [EvaluatedTab] {
        let ownPath = path.appending("Tab")
        return [
            EvaluatedTab(
                value: value.map { AnyHashable($0) },
                role: role,
                label: evaluator.evaluate(label, at: ownPath.appending("label")),
                content: evaluator.evaluate(content, at: ownPath))
        ]
    }
}

extension TupleTabContent: PrimitiveTabContent {
    func makeTabs(in evaluator: Evaluator, at path: ViewPath) -> [EvaluatedTab] {
        elements.enumerated().flatMap { index, element in
            evaluator.evaluateTabs(element, at: path.appending(String(index)))
        }
    }
}

extension _OptionalTabContent: PrimitiveTabContent {
    func makeTabs(in evaluator: Evaluator, at path: ViewPath) -> [EvaluatedTab] {
        wrapped.map { evaluator.evaluateTabs($0, at: path.appending("if")) } ?? []
    }
}

extension _ConditionalTabContent: PrimitiveTabContent {
    func makeTabs(in evaluator: Evaluator, at path: ViewPath) -> [EvaluatedTab] {
        evaluator.evaluateTabs(content, at: path.appending(branch))
    }
}

/// A tab view's content, which evaluates its tabs.
@MainActor
protocol TabViewContent {
    func makeTabs(in evaluator: Evaluator, at path: ViewPath) -> [EvaluatedTab]
}

extension TabContentBuilder.Content: TabViewContent {
    func makeTabs(in evaluator: Evaluator, at path: ViewPath) -> [EvaluatedTab] {
        evaluator.evaluateTabs(content, at: path)
    }
}

extension TabView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("TabView")
        let id = ownPath.id
        let tabs = evaluateTabs(in: evaluator, at: ownPath)
        guard !tabs.isEmpty else { return [ViewNode(id: id, kind: "TabView")] }

        // Without a binding, the tab view keeps the selected tab's position
        // itself, as state of its own that lasts while it is in the tree.
        let host = evaluator.host
        let ownSelection =
            selection == nil
            ? host.stateBox(forKey: "\(id.rawValue).selection", initialValue: 0) : nil
        let selected: Int
        if let selection {
            // Assumed: a selection that matches no tab shows the first one.
            let current = AnyHashable(selection.wrappedValue)
            selected = tabs.firstIndex { $0.value == current } ?? 0
        } else {
            selected = min(max(ownSelection?.value ?? 0, 0), tabs.count - 1)
        }

        let barPath = ownPath.appending("bar")
        var items: [ViewNode] = []
        for (index, tab) in tabs.enumerated() {
            let itemPath = barPath.appending(String(index))
            let selection = self.selection
            evaluator.registerAction(
                { [weak host] in
                    if let selection, let value = tab.value?.base as? SelectionValue {
                        selection.wrappedValue = value
                    } else if let ownSelection, ownSelection.value != index {
                        ownSelection.value = index
                        host?.setNeedsUpdate()
                    }
                }, for: itemPath.id)
            items.append(tabBarItem(tab, at: itemPath, isSelected: index == selected))
        }
        let bar = ViewNode(id: barPath.id, kind: "TabBar", children: items)
        return [ViewNode(id: id, kind: "TabView", children: tabs[selected].content + [bar])]
    }

    /// Evaluates every tab, so that each keeps its state while it is not
    /// selected.
    private func evaluateTabs(in evaluator: Evaluator, at path: ViewPath) -> [EvaluatedTab] {
        if let content = content as? any TabViewContent {
            return content.makeTabs(in: evaluator, at: path)
        }
        // Each view the content resolves to is a tab,
        // labeled by its `tabItem` and selected by its `tag`.
        let labels = TabItemCollector()
        let (nodes, tags) = evaluator.withEnvironment({ $0.tabItemCollector = labels }) {
            evaluator.evaluateTagged(content, at: path)
        }
        return nodes.map { node in
            EvaluatedTab(
                value: tags.tag(of: node.id, as: SelectionValue.self).map { AnyHashable($0) },
                role: nil, label: labels.labels[node.id] ?? [], content: [node])
        }
    }

    /// A tab's button in the bar: its symbol above its title, or only the
    /// symbol for a search tab. The symbol is the first one in the tab's
    /// label, in the fill variant as on iOS, and the title is the label's
    /// first text.
    private func tabBarItem(_ tab: EvaluatedTab, at path: ViewPath, isSelected: Bool) -> ViewNode {
        let labelNodes = tab.label.flatMap(\.allNodes)
        let title = labelNodes.first { $0.kind == "Text" }?.text ?? ""
        let symbol = labelNodes.first { $0.kind == "Image" && $0.attributes["systemName"] != nil }?
            .attributes["systemName"]
        let isSearch = tab.role == .search
        var attributes: [String: String] = [:]
        if isSelected { attributes["selected"] = "true" }
        if let role = tab.role { attributes["role"] = role.name }
        var children: [ViewNode] = []
        if let symbol {
            var symbolAttributes = [
                "systemName": symbol,
                "font":
                    (isSearch
                    ? LayoutDefaults.tabBarSearchSymbolFont : LayoutDefaults.tabBarSymbolFont)
                    .resolved().name,
            ]
            if !isSearch { symbolAttributes["symbolVariant"] = "fill" }
            if SymbolLibrary.source(of: symbol) == .placeholder {
                symbolAttributes["missingSymbol"] = "true"
            }
            children.append(
                ViewNode(
                    id: path.appending("Image").id, kind: "Image", attributes: symbolAttributes))
        }
        if isSearch {
            // The search tab shows only its symbol; its title is its label.
            attributes["label"] = title
        } else if !title.isEmpty {
            children.append(
                ViewNode(
                    id: path.appending("Text").id, kind: "Text",
                    attributes: [
                        "text": title,
                        "font": LayoutDefaults.tabBarTitleFont.resolved().attribute,
                    ]))
        }
        return ViewNode(id: path.id, kind: "Button", attributes: attributes, children: children)
    }
}
