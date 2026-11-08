#if canImport(Foundation)
import Foundation
#endif

/// A control that shows a menu of actions when tapped, mirroring SwiftUI's
/// `Menu`.
///
/// A menu is a `Button` node with a `menu` attribute, so button styles, tints
/// and glass apply to it as they do in SwiftUI. Tapping it opens a
/// `MenuPopover` presentation next to the button. The popover holds a
/// `MenuPanel` with the content's items: `Button`s, `Section`s, `Divider`s
/// (which become `MenuSeparator` nodes), and `ControlGroup`s. A tap on an item
/// runs its action and closes the menu; a tap outside closes it.
///
/// With a `primaryAction`, a tap runs the action, and a long press opens the
/// menu, as in SwiftUI.
public struct Menu<Label: View, Content: View>: View {
    public typealias Body = Never

    let label: Label
    let content: Content
    let primaryAction: (@MainActor () -> Void)?

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.content = content()
        self.label = label()
        self.primaryAction = nil
    }

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label,
        primaryAction: @escaping @MainActor () -> Void
    ) {
        self.content = content()
        self.label = label()
        self.primaryAction = primaryAction
    }

    public var body: Never {
        fatalError("Menu is a primitive view and has no body.")
    }
}

extension Menu where Label == Text {
    public init(_ title: some StringProtocol, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.label = Text(title)
        self.primaryAction = nil
    }

    public init(
        _ title: some StringProtocol, @ViewBuilder content: () -> Content,
        primaryAction: @escaping @MainActor () -> Void
    ) {
        self.content = content()
        self.label = Text(title)
        self.primaryAction = primaryAction
    }
}

extension Menu where Label == ParhelionUI.Label<Text, Image> {
    public init(
        _ title: some StringProtocol, systemImage: String, @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.label = ParhelionUI.Label(title, systemImage: systemImage)
        self.primaryAction = nil
    }

    public init(
        _ title: some StringProtocol, systemImage: String, @ViewBuilder content: () -> Content,
        primaryAction: @escaping @MainActor () -> Void
    ) {
        self.content = content()
        self.label = ParhelionUI.Label(title, systemImage: systemImage)
        self.primaryAction = primaryAction
    }
}

/// Whether a menu is open, kept in host storage under the menu. It is not
/// `Codable`, so hot reload does not open a menu again.
struct MenuOpenState {
    var isOpen = false
}

extension Menu: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("Menu")
        let box = evaluator.controlBox(ownPath.id, "menu", initialValue: MenuOpenState())
        let open: @MainActor () -> Void = {
            box.value.isOpen = true
            box.host?.setNeedsUpdate()
        }
        let close: @MainActor () -> Void = {
            box.value.isOpen = false
            box.host?.setNeedsUpdate()
        }
        let button = Button(action: primaryAction ?? open) { label }
        var nodes = evaluator.evaluate(button, at: ownPath)
        guard var node = nodes.first else { return [] }
        let buttonID = node.id
        node.attributes["menu"] = "true"
        if box.value.isOpen { node.attributes["expanded"] = "true" }
        if primaryAction != nil, evaluator.environment.isEnabled {
            evaluator.registerInputHandlers(
                NodeInputHandlers(longPress: { _, _ in open() }), for: buttonID)
            evaluator.registerLongPress(for: buttonID, perform: open)
        }
        nodes[0] = node

        if box.value.isOpen {
            MenuPresenter.register(
                kind: "MenuPopover", id: ownPath.appending("popover").id, anchor: buttonID,
                items: AnyView(content), close: close, in: evaluator)
        }
        return nodes
    }
}

// MARK: - ControlGroup

/// A row of related controls, mirroring SwiftUI's `ControlGroup`. In a menu it
/// is one row of equal columns, each with its icon above its title, like
/// "Play next, Play last, Like". Elsewhere it lays its controls out in a row.
public struct ControlGroup<Content: View>: View {
    public typealias Body = Never

    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never {
        fatalError("ControlGroup is a primitive view and has no body.")
    }
}

extension ControlGroup: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("ControlGroup")
        guard evaluator.environment.isInMenu else {
            return evaluator.evaluate(HStack(spacing: 8) { content }, at: ownPath)
        }
        let children = evaluator.evaluate(content, at: ownPath)
        return [ViewNode(id: ownPath.id, kind: "ControlGroup", children: children)]
    }
}

// MARK: - Environment

struct IsInMenuKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// Whether the view is the content of an open menu.
    var isInMenu: Bool {
        get { self[IsInMenuKey.self] }
        set { self[IsInMenuKey.self] = newValue }
    }
}

// MARK: - Presenting

/// Evaluates a menu's items and presents them. Both `Menu` and `contextMenu`
/// use it.
@MainActor
enum MenuPresenter {
    /// The `MenuPanel` node of a menu: its items, normalized for the panel's
    /// layout.
    ///
    /// Tapping a button runs its action, then `close`. A destructive button
    /// is red. A `Divider` becomes a `MenuSeparator`, and a separator goes
    /// between a `Section` or `ControlGroup` and its neighbors, as in iOS.
    static func panel(
        id: NodeID, items: AnyView, environment: EnvironmentValues,
        close: @escaping @MainActor () -> Void, in evaluator: Evaluator, at path: ViewPath
    ) -> ViewNode {
        let nodes = evaluator.withEnvironment({
            $0 = environment
            // The menu takes its source's appearance and text size, not its
            // button style, font, or list context.
            $0.buttonStyle = .builtIn(.automatic)
            $0.buttonContext = .standard
            $0.labelStyle = .builtIn(.automatic)
            $0.font = nil
            $0.fontWeight = nil
            $0.isInList = false
            $0.isInMenu = true
            $0 = evaluator.startingPresentation(in: $0)
        }) {
            evaluator.evaluate(items, at: path)
        }
        let items = separated(
            nodes.map { normalized($0, close: close, in: evaluator, inGroup: false) }, at: path)
        return ViewNode(
            id: id, kind: "MenuPanel", attributes: ["label": "Menu"], children: items)
    }

    /// Registers a presentation of a menu next to the node `anchor`.
    static func register(
        kind: String, id: NodeID, anchor: NodeID, items: AnyView,
        close: @escaping @MainActor () -> Void, in evaluator: Evaluator
    ) {
        MenuLayout.registerBehaviors()
        let environment = evaluator.environment
        let path = ViewPath().appending("MenuPanel[\(id.rawValue)]")
        evaluator.registerPresentation(
            Presentation(id: id, dismiss: close, onDismiss: nil) { evaluator in
                // A tap outside the panel closes the menu.
                evaluator.registerAction(close, for: id)
                let panel = panel(
                    id: id.appending("panel"), items: items, environment: environment,
                    close: close, in: evaluator, at: path)
                return ViewNode(
                    id: id, kind: kind,
                    attributes: ["anchor": anchor.rawValue, "label": "Dismiss Menu"],
                    children: [panel])
            })
    }

    private static func normalized(
        _ node: ViewNode, close: @escaping @MainActor () -> Void, in evaluator: Evaluator,
        inGroup: Bool
    ) -> ViewNode {
        var node = node
        switch node.kind {
        case "Button":
            evaluator.appendToAction(for: node.id, close)
            if node.attributes["role"] == "destructive", node.attributes["foregroundStyle"] == nil {
                node.attributes["foregroundStyle"] = "red"
            }
            if inGroup {
                node = node.settingDefaultFont(Font.caption.resolved().attribute)
            }
        case "Divider":
            node.kind = "MenuSeparator"
        case "Section", "ControlGroup":
            let isGroup = node.kind == "ControlGroup"
            node.children = node.children.map {
                normalized($0, close: close, in: evaluator, inGroup: isGroup)
            }
        case "SectionHeader", "SectionFooter":
            node = node.settingDefaultFont(Font.footnote.resolved().attribute)
                .withDefaultForeground("secondary")
        default:
            break
        }
        return node
    }

    /// Puts a separator between neighbors when either is a section or a
    /// control group, unless one is there already.
    private static func separated(_ nodes: [ViewNode], at path: ViewPath) -> [ViewNode] {
        func isGroup(_ node: ViewNode) -> Bool {
            node.kind == "Section" || node.kind == "ControlGroup"
        }
        var result: [ViewNode] = []
        for node in nodes {
            if let last = result.last, last.kind != "MenuSeparator",
                node.kind != "MenuSeparator", isGroup(last) || isGroup(node)
            {
                result.append(
                    ViewNode(
                        id: path.appending("separator[\(result.count)]").id,
                        kind: "MenuSeparator"))
            }
            result.append(node)
        }
        return result
    }
}

extension ViewNode {
    /// The node with `font` on every `Text` that sets none.
    fileprivate func settingDefaultFont(_ font: String) -> ViewNode {
        var node = self
        if node.kind == "Text", node.attributes["font"] == nil { node.attributes["font"] = font }
        node.children = node.children.map { $0.settingDefaultFont(font) }
        return node
    }
}

extension NodeID {
    /// The identifier of a part of this node.
    func appending(_ component: String) -> NodeID {
        NodeID(rawValue + "/" + component)
    }
}
