#if canImport(Foundation)
import Foundation
#endif

/// A list of the values pushed onto a ``NavigationStack``, of any hashable
/// types, mirroring SwiftUI's `NavigationPath`.
public struct NavigationPath: Equatable {
    var elements: [AnyHashable]

    /// Creates an empty path.
    public init() {
        elements = []
    }

    /// Creates a path from a sequence of values.
    public init<S: Sequence>(_ elements: S) where S.Element: Hashable {
        self.elements = elements.map { AnyHashable($0) }
    }

    /// The number of values in the path.
    public var count: Int { elements.count }

    /// Whether the path is empty, which shows the stack's root view.
    public var isEmpty: Bool { elements.isEmpty }

    /// Pushes a value.
    public mutating func append<V: Hashable>(_ value: V) {
        elements.append(AnyHashable(value))
    }

    /// Removes the last `k` values.
    public mutating func removeLast(_ k: Int = 1) {
        elements.removeLast(k)
    }
}

/// A view that shows a root view and the views pushed on top of it, with a
/// navigation bar, mirroring SwiftUI's `NavigationStack`.
///
/// Only the top view is on screen. The bar shows the top view's
/// ``View/navigationTitle(_:)``, its toolbar items, and a back button whose
/// label is the previous view's title. Titles display inline, at the body
/// text size, until Parhelion supports fonts.
public struct NavigationStack<Data, Root: View>: View {
    public typealias Body = Never

    let root: Root
    let path: NavigationPathAccess?

    public var body: Never {
        fatalError("NavigationStack is a primitive view and has no body.")
    }
}

extension NavigationStack where Data == NavigationPath {
    /// Creates a stack that manages its own path.
    public init(@ViewBuilder root: () -> Root) {
        self.root = root()
        path = nil
    }

    /// Creates a stack whose path is the given binding.
    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) {
        self.root = root()
        self.path = NavigationPathAccess(
            get: { path.wrappedValue.elements },
            set: { path.wrappedValue.elements = $0 }
        )
    }
}

extension NavigationStack
where
    Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection,
    Data.Element: Hashable
{
    /// Creates a stack whose path is a binding to a collection of values of
    /// one type.
    public init(path: Binding<Data>, @ViewBuilder root: () -> Root) {
        self.root = root()
        self.path = NavigationPathAccess(
            get: { path.wrappedValue.map { AnyHashable($0) } },
            set: { path.wrappedValue = Data($0.compactMap { $0.base as? Data.Element }) }
        )
    }
}

/// Reads and writes the values of a stack's path binding.
struct NavigationPathAccess {
    let get: @MainActor () -> [AnyHashable]
    let set: @MainActor ([AnyHashable]) -> Void
}

/// A view that shows the root view in a navigation stack, mirroring
/// SwiftUI's deprecated `NavigationView`.
public struct NavigationView<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        NavigationStack { content }
    }
}

/// A view that pushes a view onto the enclosing ``NavigationStack`` when
/// tapped, mirroring SwiftUI's `NavigationLink`.
///
/// In a ``List``, a link's row shows a disclosure indicator and its label
/// uses the primary color. Elsewhere the label takes the tint color, like a
/// button. A link outside a navigation stack does nothing.
public struct NavigationLink<Label: View, Destination: View>: View {
    public typealias Body = Never

    enum Target {
        case destination(Destination)
        case value(AnyHashable?)
    }

    let label: Label
    let target: Target

    /// Creates a link that pushes a destination view.
    public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.label = label()
        target = .destination(destination())
    }

    /// Creates a link that pushes a destination view.
    public init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.label = label()
        target = .destination(destination)
    }

    public var body: Never {
        fatalError("NavigationLink is a primitive view and has no body.")
    }
}

extension NavigationLink where Label == Text {
    /// Creates a link with a text label that pushes a destination view.
    public init(_ title: some StringProtocol, @ViewBuilder destination: () -> Destination) {
        self.init(destination: destination) { Text(title) }
    }

    /// Creates a link with a text label that pushes a destination view.
    public init(_ title: some StringProtocol, destination: Destination) {
        self.init(destination: destination) { Text(title) }
    }
}

extension NavigationLink where Destination == Never {
    /// Creates a link that pushes a value onto the stack's path. The stack
    /// shows the view that ``View/navigationDestination(for:destination:)``
    /// declares for the value's type. A `nil` value disables the link.
    public init<P: Hashable>(value: P?, @ViewBuilder label: () -> Label) {
        self.label = label()
        target = .value(value.map { AnyHashable($0) })
    }
}

extension NavigationLink where Label == Text, Destination == Never {
    /// Creates a link with a text label that pushes a value onto the stack's
    /// path.
    public init<P: Hashable>(_ title: some StringProtocol, value: P?) {
        self.init(value: value) { Text(title) }
    }
}

extension NavigationLink: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("NavigationLink")
        if let navigation = evaluator.navigation {
            switch target {
            case .destination(let destination):
                navigation.linkDestinations[ownPath.id] = destination
                let id = ownPath.id
                evaluator.registerAction({ navigation.push(.link(id)) }, for: id)
            case .value(let value?):
                evaluator.registerAction({ navigation.push(.value(value)) }, for: ownPath.id)
            case .value(nil):
                break
            }
        }
        return [
            ViewNode(
                id: ownPath.id,
                kind: "NavigationLink",
                children: evaluator.evaluate(label, at: ownPath)
            )
        ]
    }
}

// MARK: - Navigation modifiers

/// How a navigation title is displayed, mirroring SwiftUI's
/// `NavigationBarItem.TitleDisplayMode`.
public enum NavigationBarItem {
    public enum TitleDisplayMode: Sendable {
        case automatic, inline, large
    }
}

extension View {
    /// Sets the title the navigation bar shows while this view is on top of
    /// a ``NavigationStack``.
    public func navigationTitle(_ title: some StringProtocol) -> some View {
        NavigationOptionView(content: self, option: .title(String(title)))
    }

    /// Sets how the navigation title is displayed. Parhelion displays every
    /// title inline until it supports fonts, so this has no effect yet.
    public func navigationBarTitleDisplayMode(
        _ displayMode: NavigationBarItem.TitleDisplayMode
    ) -> some View {
        self
    }

    /// Hides the back button while this view is on top of a
    /// ``NavigationStack``.
    public func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> some View {
        NavigationOptionView(content: self, option: .backButtonHidden(hidesBackButton))
    }

    /// Declares the view a ``NavigationStack`` shows for values of a type
    /// pushed by ``NavigationLink/init(value:label:)`` or through the
    /// stack's path.
    public func navigationDestination<D: Hashable, C: View>(
        for data: D.Type,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View {
        NavigationOptionView(
            content: self,
            option: .destination(
                ObjectIdentifier(D.self),
                { value in (value.base as? D).map { destination($0) } }
            )
        )
    }
}

/// A view that passes a navigation option to the enclosing stack.
struct NavigationOptionView<Content: View>: View {
    typealias Body = Never

    enum Option {
        case title(String)
        case backButtonHidden(Bool)
        case destination(ObjectIdentifier, (AnyHashable) -> (any View)?)
    }

    let content: Content
    let option: Option

    var body: Never {
        fatalError("NavigationOptionView is a primitive view and has no body.")
    }
}

extension NavigationOptionView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let nodes = evaluator.evaluate(content, at: path)
        guard let navigation = evaluator.navigation else { return nodes }
        switch option {
        case .title(let title):
            // The innermost title wins, so a view's own title overrides one
            // set around it.
            if navigation.screen.title == nil { navigation.screen.title = title }
        case .backButtonHidden(let hidden):
            navigation.screen.backButtonHidden = navigation.screen.backButtonHidden || hidden
        case .destination(let type, let makeView):
            navigation.valueDestinations[type] = makeView
        }
        return nodes
    }
}

// MARK: - Toolbars

/// Where a toolbar item goes, mirroring SwiftUI's `ToolbarItemPlacement`.
///
/// Parhelion places items in the navigation bar: leading, trailing, or in
/// place of the title.
public struct ToolbarItemPlacement: Sendable, Equatable {
    enum Position: Sendable {
        case leading, principal, trailing
    }

    let position: Position

    public static let automatic = ToolbarItemPlacement(position: .trailing)
    public static let principal = ToolbarItemPlacement(position: .principal)
    public static let topBarLeading = ToolbarItemPlacement(position: .leading)
    public static let topBarTrailing = ToolbarItemPlacement(position: .trailing)
    public static let navigationBarLeading = ToolbarItemPlacement(position: .leading)
    public static let navigationBarTrailing = ToolbarItemPlacement(position: .trailing)
    public static let primaryAction = ToolbarItemPlacement(position: .trailing)
    public static let confirmationAction = ToolbarItemPlacement(position: .trailing)
    public static let destructiveAction = ToolbarItemPlacement(position: .trailing)
    public static let cancellationAction = ToolbarItemPlacement(position: .leading)
}

/// Content for a toolbar, mirroring SwiftUI's `ToolbarContent`.
@MainActor
@preconcurrency
public protocol ToolbarContent {}

/// Toolbar content that lists its items.
@MainActor
protocol ToolbarItemsProvider {
    var toolbarItems: [(placement: ToolbarItemPlacement, view: any View)] { get }
}

/// One item in a toolbar, mirroring SwiftUI's `ToolbarItem`.
public struct ToolbarItem<ID, Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    let content: Content
}

extension ToolbarItem where ID == () {
    public init(
        placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.content = content()
    }
}

extension ToolbarItem: ToolbarItemsProvider {
    var toolbarItems: [(placement: ToolbarItemPlacement, view: any View)] {
        [(placement, content)]
    }
}

/// Several toolbar items with one placement, mirroring SwiftUI's
/// `ToolbarItemGroup`.
public struct ToolbarItemGroup<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    let content: Content

    public init(
        placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.content = content()
    }
}

extension ToolbarItemGroup: ToolbarItemsProvider {
    var toolbarItems: [(placement: ToolbarItemPlacement, view: any View)] {
        [(placement, content)]
    }
}

/// Several pieces of toolbar content, produced by ``ToolbarContentBuilder``.
public struct TupleToolbarContent<T>: ToolbarContent, ToolbarItemsProvider {
    let elements: [any ToolbarContent]

    var toolbarItems: [(placement: ToolbarItemPlacement, view: any View)] {
        elements.flatMap { ($0 as? any ToolbarItemsProvider)?.toolbarItems ?? [] }
    }
}

/// Toolbar content that may be absent, produced by `if` in a
/// ``ToolbarContentBuilder``.
public struct _OptionalToolbarContent<Wrapped: ToolbarContent>: ToolbarContent,
    ToolbarItemsProvider
{
    let wrapped: Wrapped?

    var toolbarItems: [(placement: ToolbarItemPlacement, view: any View)] {
        (wrapped as? any ToolbarItemsProvider)?.toolbarItems ?? []
    }
}

/// One of two pieces of toolbar content, produced by `if`/`else` in a
/// ``ToolbarContentBuilder``.
public struct _ConditionalToolbarContent<TrueContent: ToolbarContent, FalseContent: ToolbarContent>:
    ToolbarContent, ToolbarItemsProvider
{
    let content: any ToolbarContent

    var toolbarItems: [(placement: ToolbarItemPlacement, view: any View)] {
        (content as? any ToolbarItemsProvider)?.toolbarItems ?? []
    }
}

/// Builds toolbar content from closures, mirroring SwiftUI's
/// `ToolbarContentBuilder`.
@MainActor
@resultBuilder
public enum ToolbarContentBuilder {
    public static func buildExpression<Content: ToolbarContent>(_ content: Content) -> Content {
        content
    }

    public static func buildBlock<Content: ToolbarContent>(_ content: Content) -> Content {
        content
    }

    public static func buildBlock<each Content: ToolbarContent>(
        _ content: repeat each Content
    ) -> TupleToolbarContent<(repeat each Content)> {
        var elements: [any ToolbarContent] = []
        for element in repeat each content {
            elements.append(element)
        }
        return TupleToolbarContent(elements: elements)
    }

    public static func buildOptional<Content: ToolbarContent>(
        _ content: Content?
    ) -> _OptionalToolbarContent<Content> {
        _OptionalToolbarContent(wrapped: content)
    }

    public static func buildEither<TrueContent: ToolbarContent, FalseContent: ToolbarContent>(
        first: TrueContent
    ) -> _ConditionalToolbarContent<TrueContent, FalseContent> {
        _ConditionalToolbarContent(content: first)
    }

    public static func buildEither<TrueContent: ToolbarContent, FalseContent: ToolbarContent>(
        second: FalseContent
    ) -> _ConditionalToolbarContent<TrueContent, FalseContent> {
        _ConditionalToolbarContent(content: second)
    }
}

extension View {
    /// Adds items to the navigation bar while this view is on top of a
    /// ``NavigationStack``.
    public func toolbar<Content: ToolbarContent>(
        @ToolbarContentBuilder content: () -> Content
    ) -> some View {
        ToolbarView(
            content: self,
            items: (content() as? any ToolbarItemsProvider)?.toolbarItems ?? []
        )
    }

    /// Adds views to the trailing end of the navigation bar while this view
    /// is on top of a ``NavigationStack``.
    public func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ToolbarView(content: self, items: [(.automatic, content())])
    }
}

/// A view that passes toolbar items to the enclosing stack.
struct ToolbarView<Content: View>: View {
    typealias Body = Never

    let content: Content
    let items: [(placement: ToolbarItemPlacement, view: any View)]

    var body: Never {
        fatalError("ToolbarView is a primitive view and has no body.")
    }
}

extension ToolbarView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let nodes = evaluator.evaluate(content, at: path)
        guard let navigation = evaluator.navigation else { return nodes }
        let toolbarPath = path.appending("toolbar")
        for (index, item) in items.enumerated() {
            let itemNodes = evaluator.evaluate(item.view, at: toolbarPath.appending(String(index)))
            navigation.screen.toolbarItems.append((item.placement.position, itemNodes))
        }
        return nodes
    }
}

// MARK: - Evaluation

/// An entry in a navigation stack above its root view.
enum NavigationEntry: Hashable {
    /// The destination of a ``NavigationLink`` with a destination view.
    case link(NodeID)
    /// A value, shown by the matching `navigationDestination`.
    case value(AnyHashable)
}

/// What the views of a navigation stack declare while it is evaluated.
@MainActor
final class NavigationContext {
    /// What the view being evaluated declares for its own screen.
    struct Screen {
        var title: String?
        var backButtonHidden = false
        var toolbarItems: [(position: ToolbarItemPlacement.Position, nodes: [ViewNode])] = []
    }

    let push: @MainActor (NavigationEntry) -> Void
    var linkDestinations: [NodeID: any View] = [:]
    var valueDestinations: [ObjectIdentifier: (AnyHashable) -> (any View)?] = [:]
    var screen = Screen()

    init(push: @escaping @MainActor (NavigationEntry) -> Void) {
        self.push = push
    }

    func destination(for entry: NavigationEntry) -> (any View)? {
        switch entry {
        case .link(let id):
            return linkDestinations[id]
        case .value(let value):
            return valueDestinations[ObjectIdentifier(type(of: value.base))]?(value)
        }
    }
}

extension NavigationStack: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("NavigationStack")
        let id = ownPath.id
        let pathAccess = self.path
        let host = evaluator.host
        let navigation = NavigationContext { [weak host] entry in
            host?.pushNavigation(entry, onto: id, path: pathAccess)
        }

        let outer = evaluator.navigation
        evaluator.navigation = navigation
        defer { evaluator.navigation = outer }

        func evaluateScreen(
            _ view: any View, at screenPath: ViewPath, environment: EnvironmentValues
        ) -> (nodes: [ViewNode], screen: NavigationContext.Screen) {
            navigation.screen = NavigationContext.Screen()
            let nodes = evaluator.withEnvironment({ $0 = environment }) {
                evaluator.evaluate(view, at: screenPath)
            }
            return (nodes, navigation.screen)
        }

        // Every screen is evaluated, in order, so that the views beneath the
        // top one keep their state and declare the destinations above them.
        var screens = [evaluateScreen(root, at: ownPath, environment: evaluator.environment)]
        let entries = host.navigationEntries(of: id, path: pathAccess)
        for (index, entry) in entries.enumerated() {
            guard let destination = navigation.destination(for: entry) else {
                // The link or destination that pushed this entry is gone.
                host.truncateNavigation(of: id, path: pathAccess, toCount: index)
                break
            }
            screens.append(
                evaluateScreen(
                    destination, at: ownPath.appending("Destination[\(index + 1)]"),
                    environment: evaluator.environment.presenting { [weak host] in
                        // A pushed view's dismiss action pops it and the views
                        // above it.
                        host?.popNavigation(of: id, path: pathAccess, toCount: index)
                    }))
        }

        let top = screens[screens.count - 1]
        let barPath = ownPath.appending("bar")
        var leading: [ViewNode] = []
        if screens.count > 1, !top.screen.backButtonHidden {
            let backPath = barPath.appending("back")
            let count = screens.count - 2
            evaluator.registerAction(
                { [weak host] in host?.popNavigation(of: id, path: pathAccess, toCount: count) },
                for: backPath.id
            )
            let previousTitle = screens[screens.count - 2].screen.title
            let label = ViewNode(
                id: backPath.appending("HStack").id,
                kind: "HStack",
                attributes: ["spacing": formatPoints(LayoutDefaults.backButtonSpacing)],
                children: [
                    ViewNode(
                        id: backPath.appending("Image").id, kind: "Image",
                        attributes: ["systemName": "chevron.backward"]),
                    ViewNode(
                        id: backPath.appending("Text").id, kind: "Text",
                        attributes: ["text": previousTitle ?? "Back"]),
                ]
            )
            leading.append(ViewNode(id: backPath.id, kind: "Button", children: [label]))
        }
        func items(_ position: ToolbarItemPlacement.Position) -> [ViewNode] {
            top.screen.toolbarItems.filter { $0.position == position }.flatMap(\.nodes)
        }
        leading += items(.leading)

        var barChildren: [ViewNode] = []
        func group(_ name: String, _ nodes: [ViewNode]) {
            guard !nodes.isEmpty else { return }
            barChildren.append(
                ViewNode(
                    id: barPath.appending(name).id,
                    kind: "ToolbarItemGroup",
                    attributes: ["placement": name],
                    children: nodes
                ))
        }
        group("leading", leading)
        let principal = items(.principal)
        if !principal.isEmpty {
            group("principal", principal)
        } else if let title = top.screen.title {
            barChildren.append(
                ViewNode(
                    id: barPath.appending("title").id, kind: "Text",
                    attributes: ["text": title]))
        }
        group("trailing", items(.trailing))

        let bar = ViewNode(id: barPath.id, kind: "NavigationBar", children: barChildren)
        return [ViewNode(id: id, kind: "NavigationStack", children: [bar] + top.nodes)]
    }
}

extension ViewHost {
    /// The entries above a stack's root view: the values in its path
    /// binding, if it has one, followed by the entries the stack keeps
    /// itself.
    func navigationEntries(of stack: NodeID, path: NavigationPathAccess?) -> [NavigationEntry] {
        visitedNavigationStacks.insert(stack)
        let values = path?.get().map(NavigationEntry.value) ?? []
        return values + (navigationState[stack] ?? [])
    }

    func truncateNavigation(of stack: NodeID, path: NavigationPathAccess?, toCount count: Int) {
        let pathCount = path?.get().count ?? 0
        // Entries in a path binding belong to the app; only the stack's own
        // entries are removed.
        guard count >= pathCount else { return }
        navigationState[stack] = Array((navigationState[stack] ?? []).prefix(count - pathCount))
    }

    func pushNavigation(_ entry: NavigationEntry, onto stack: NodeID, path: NavigationPathAccess?) {
        if case .value(let value) = entry, let path, (navigationState[stack] ?? []).isEmpty {
            path.set(path.get() + [value])
        } else {
            navigationState[stack, default: []].append(entry)
        }
        setNeedsUpdate()
    }

    /// Pops entries until `count` remain above the root view.
    func popNavigation(of stack: NodeID, path: NavigationPathAccess?, toCount count: Int) {
        let values = path?.get() ?? []
        if count >= values.count {
            navigationState[stack] = Array(
                (navigationState[stack] ?? []).prefix(count - values.count))
        } else {
            navigationState[stack] = []
            path?.set(Array(values.prefix(count)))
        }
        setNeedsUpdate()
    }
}
