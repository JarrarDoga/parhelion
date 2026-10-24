#if canImport(Foundation)
import Foundation
#endif

/// A control that selects one of several tagged options, mirroring SwiftUI's
/// `Picker`.
///
/// Each view of the content is an option, identified by its
/// ``View/tag(_:includeOptional:)`` or by the identifier of the `ForEach`
/// element it comes from. Options whose tag is not of the selection's type
/// cannot be selected. The style, set with ``View/pickerStyle(_:)``, decides
/// how the options show:
///
/// - `.segmented`: a capsule of `PickerOption` segments, with the selection
///   on a white capsule that slides to a new selection.
/// - `.menu`, and `.automatic`, as iOS chooses everywhere: a `PopUpButton`
///   showing the selected option, which opens iOS 27's glass `Menu` of the
///   options. In a list, the label sits at the leading edge of the row.
/// - `.inline`: the options as rows, with a checkmark on the selected one.
///   In a list, they form a section with the label as its header.
/// - `.navigationLink`: a link showing the selected option, which pushes a
///   list of the options; choosing one goes back.
///
/// The node records `pickerStyle` and `selection`, and the label's text as a
/// `label` attribute when the style does not show the label.
public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: View {
    public typealias Body = Never

    let selection: Binding<SelectionValue>
    let label: Label
    let content: Content

    /// Creates a picker with a label view.
    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.selection = selection
        self.content = content()
        self.label = label()
    }

    public var body: Never {
        fatalError("Picker is a primitive view and has no body.")
    }
}

extension Picker where Label == Text {
    /// Creates a picker with a text label.
    public init(
        _ title: some StringProtocol,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(selection: selection, content: content) { Text(title) }
    }
}

// MARK: - Picker styles

/// The appearance of a ``Picker``, set with ``View/pickerStyle(_:)``.
///
/// Parhelion draws the built-in styles and has no others.
@MainActor
@preconcurrency
public protocol PickerStyle {}

/// The picker styles Parhelion draws, by the names nodes record.
enum BuiltInPickerStyle: String, Sendable {
    case automatic, segmented, menu, inline, navigationLink

    /// The style a picker draws with: iOS chooses a menu for `.automatic`,
    /// in lists and forms and elsewhere.
    var resolved: BuiltInPickerStyle {
        self == .automatic ? .menu : self
    }
}

/// A picker style that Parhelion draws.
protocol BuiltInPickerStyleProtocol: PickerStyle {
    var builtIn: BuiltInPickerStyle { get }
}

/// The platform's default picker style: a menu on iOS.
public struct DefaultPickerStyle: BuiltInPickerStyleProtocol {
    var builtIn: BuiltInPickerStyle { .automatic }
    public init() {}
}

/// Options side by side in a capsule, one of them selected.
public struct SegmentedPickerStyle: BuiltInPickerStyleProtocol {
    var builtIn: BuiltInPickerStyle { .segmented }
    public init() {}
}

/// A button showing the selection, which opens a menu of the options.
public struct MenuPickerStyle: BuiltInPickerStyleProtocol {
    var builtIn: BuiltInPickerStyle { .menu }
    public init() {}
}

/// The options inline with the content around them, as rows.
public struct InlinePickerStyle: BuiltInPickerStyleProtocol {
    var builtIn: BuiltInPickerStyle { .inline }
    public init() {}
}

/// A navigation link showing the selection, which pushes a list of the
/// options.
public struct NavigationLinkPickerStyle: BuiltInPickerStyleProtocol {
    var builtIn: BuiltInPickerStyle { .navigationLink }
    public init() {}
}

extension PickerStyle where Self == DefaultPickerStyle {
    public static var automatic: DefaultPickerStyle { DefaultPickerStyle() }
}

extension PickerStyle where Self == SegmentedPickerStyle {
    public static var segmented: SegmentedPickerStyle { SegmentedPickerStyle() }
}

extension PickerStyle where Self == MenuPickerStyle {
    public static var menu: MenuPickerStyle { MenuPickerStyle() }
}

extension PickerStyle where Self == InlinePickerStyle {
    public static var inline: InlinePickerStyle { InlinePickerStyle() }
}

extension PickerStyle where Self == NavigationLinkPickerStyle {
    public static var navigationLink: NavigationLinkPickerStyle { NavigationLinkPickerStyle() }
}

struct PickerStyleKey: EnvironmentKey {
    static var defaultValue: BuiltInPickerStyle { .automatic }
}

extension EnvironmentValues {
    /// The style of pickers in the view.
    var pickerStyle: BuiltInPickerStyle {
        get { self[PickerStyleKey.self] }
        set { self[PickerStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style of pickers in this view.
    public func pickerStyle(_ style: some PickerStyle) -> some View {
        let builtIn = (style as? any BuiltInPickerStyleProtocol)?.builtIn ?? .automatic
        return environment(\.pickerStyle, builtIn)
    }
}

// MARK: - Evaluation

/// One of a picker's options: the node its view resolved to, and its tag as
/// a selection, if it has one.
struct PickerOptionItem<SelectionValue> {
    var node: ViewNode
    var tag: SelectionValue?
}

/// Whether a picker's menu is open, kept in host storage under the picker.
/// It is not `Codable`, so hot reload does not open a menu again.
struct PickerMenuState {
    var isOpen = false
}

extension Picker: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("Picker")
        let style = evaluator.environment.pickerStyle.resolved
        let options = evaluateOptions(in: evaluator, at: ownPath, style: style)
        var attributes = [
            "pickerStyle": style.rawValue,
            "selection": describe(selection.wrappedValue),
        ]
        evaluator.markDisabled(&attributes)
        switch style {
        case .segmented:
            return [segmentedNode(options, attributes, in: evaluator, at: ownPath)]
        case .inline:
            return [inlineNode(options, attributes, in: evaluator, at: ownPath)]
        case .navigationLink:
            return navigationLinkNodes(options, attributes, in: evaluator, at: ownPath)
        case .menu, .automatic:
            return [menuNode(options, attributes, in: evaluator, at: ownPath)]
        }
    }

    /// Evaluates the options, in the segment font for a segmented picker.
    private func evaluateOptions(
        in evaluator: Evaluator, at path: ViewPath, style: BuiltInPickerStyle
    ) -> [PickerOptionItem<SelectionValue>] {
        let (nodes, tags) = evaluator.withEnvironment({
            if style == .segmented { $0.font = LayoutDefaults.segmentFont }
        }) {
            evaluator.evaluateTagged(content, at: path)
        }
        return nodes.map { PickerOptionItem(node: $0, tag: tags.tag(of: $0.id)) }
    }

    /// Evaluates the label, and returns its nodes and its text.
    private func evaluateLabel(
        in evaluator: Evaluator, at path: ViewPath
    ) -> (
        nodes: [ViewNode], text: String
    ) {
        let nodes = evaluator.evaluate(label, at: path)
        return (nodes, nodes.map(\.label).filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// Whether an option is the current selection.
    private func isSelected(_ option: PickerOptionItem<SelectionValue>) -> Bool {
        option.tag.map { $0 == selection.wrappedValue } ?? false
    }

    /// The identifier of an option's node, by its tag where it has one.
    private func optionID(
        _ option: PickerOptionItem<SelectionValue>, _ index: Int, in path: ViewPath
    )
        -> NodeID
    {
        path.appending("option[\(option.tag.map(describe) ?? String(index))]").id
    }

    /// Makes the node of an option that selects its tag when tapped, then
    /// runs `afterSelecting`.
    private func optionNode(
        _ option: PickerOptionItem<SelectionValue>, id: NodeID, in evaluator: Evaluator,
        afterSelecting: (@MainActor () -> Void)? = nil
    ) -> ViewNode {
        var attributes: [String: String] = [:]
        if isSelected(option) { attributes["selected"] = "true" }
        if let tag = option.tag, evaluator.environment.isEnabled {
            let selection = selection
            evaluator.registerAction(
                {
                    selection.wrappedValue = tag
                    afterSelecting?()
                }, for: id)
        }
        return ViewNode(
            id: id, kind: "PickerOption", attributes: attributes, children: [option.node])
    }

    // MARK: Segmented

    private func segmentedNode(
        _ options: [PickerOptionItem<SelectionValue>], _ attributes: [String: String],
        in evaluator: Evaluator, at path: ViewPath
    ) -> ViewNode {
        var attributes = attributes
        let label = evaluateLabel(in: evaluator, at: path.appending("label"))
        if !label.text.isEmpty { attributes["label"] = label.text }
        var children: [ViewNode] = []
        let indicatorID = path.appending("indicator").id
        if options.contains(where: isSelected) {
            children.append(ViewNode(id: indicatorID, kind: "SegmentIndicator"))
        }
        // The selected segment's label is semibold.
        let selectedFont = LayoutDefaults.segmentFont.weight(.semibold).resolved().attribute
        let font = LayoutDefaults.segmentFont.resolved().attribute
        for (index, option) in options.enumerated() {
            var option = option
            if isSelected(option) {
                option.node = option.node.replacingFont(font, with: selectedFont)
            }
            children.append(
                optionNode(option, id: optionID(option, index, in: path), in: evaluator))
        }
        evaluator.animate(
            [indicatorID], with: LayoutDefaults.segmentAnimation,
            whenChanged: AnyHashable(selection.wrappedValue), key: path.id)
        return ViewNode(id: path.id, kind: "Picker", attributes: attributes, children: children)
    }

    // MARK: Menu

    private func menuNode(
        _ options: [PickerOptionItem<SelectionValue>], _ attributes: [String: String],
        in evaluator: Evaluator, at path: ViewPath
    ) -> ViewNode {
        var attributes = attributes
        let inList = evaluator.environment.isInList
        // In a list, the label leads the row; elsewhere only the button
        // shows.
        let label = evaluateLabel(in: evaluator, at: path)
        if !inList, !label.text.isEmpty { attributes["label"] = label.text }

        let buttonPath = path.appending("button")
        let box = evaluator.controlBox(path.id, "menu", initialValue: PickerMenuState())
        if evaluator.environment.isEnabled {
            evaluator.registerAction(
                {
                    box.value.isOpen = true
                    box.host?.setNeedsUpdate()
                }, for: buttonPath.id)
        }
        // The button shows a copy of the selected option.
        var value =
            options.first(where: isSelected).map {
                [$0.node.moved(to: buttonPath.appending("value").id)]
            } ?? []
        var indicator = ViewNode(
            id: buttonPath.appending("indicator").id, kind: "MenuIndicator")
        if inList {
            value = value.map { $0.withDefaultForeground("secondary") }
            indicator.attributes["foregroundStyle"] = "tertiary"
        }
        let button = ViewNode(id: buttonPath.id, kind: "PopUpButton", children: value + [indicator])

        if box.value.isOpen {
            registerMenu(options, anchor: buttonPath.id, box: box, in: evaluator, at: path)
        }
        return ViewNode(
            id: path.id, kind: "Picker", attributes: attributes,
            children: (inList ? label.nodes : []) + [button])
    }

    /// Presents the open menu of options, anchored to the picker's button.
    private func registerMenu(
        _ options: [PickerOptionItem<SelectionValue>], anchor: NodeID,
        box: StateBox<PickerMenuState>, in evaluator: Evaluator, at path: ViewPath
    ) {
        let menuPath = path.appending("menu")
        let close: @MainActor () -> Void = {
            box.value.isOpen = false
            box.host?.setNeedsUpdate()
        }
        // The menu takes its button's appearance and text size, and none of
        // the button's other environment, such as its font.
        let colorScheme = evaluator.environment.colorScheme
        let dynamicTypeSize = evaluator.environment.dynamicTypeSize
        evaluator.registerPresentation(
            Presentation(id: menuPath.id, dismiss: close, onDismiss: nil) { evaluator in
                // A tap outside the options closes the menu.
                evaluator.registerAction(close, for: menuPath.id)
                let children = evaluator.withEnvironment({
                    $0.colorScheme = colorScheme
                    $0.dynamicTypeSize = dynamicTypeSize
                    $0 = evaluator.startingPresentation(in: $0)
                }) {
                    options.enumerated().map { index, option in
                        optionNode(
                            option, id: optionID(option, index, in: menuPath), in: evaluator,
                            afterSelecting: close)
                    }
                }
                return ViewNode(
                    id: menuPath.id, kind: "Menu",
                    attributes: ["anchor": anchor.rawValue, "label": "Dismiss Menu"],
                    children: children)
            })
    }

    // MARK: Inline

    /// The options as rows. In a list they form a section, with the label as
    /// the section's header; elsewhere a `Picker` holds them.
    private func inlineNode(
        _ options: [PickerOptionItem<SelectionValue>], _ attributes: [String: String],
        in evaluator: Evaluator, at path: ViewPath
    ) -> ViewNode {
        var attributes = attributes
        let rows = optionRows(options, in: evaluator, at: path)
        guard evaluator.environment.isInList else {
            let label = evaluateLabel(in: evaluator, at: path.appending("label"))
            if !label.text.isEmpty { attributes["label"] = label.text }
            return ViewNode(id: path.id, kind: "Picker", attributes: attributes, children: rows)
        }
        // Assumed: in a list, an inline picker is a section with its label as
        // the header, which a section around it drops.
        let sectionPath = path.appending("Section")
        let headerPath = sectionPath.appending("header")
        let header = evaluator.withEnvironment({ $0.font = LayoutDefaults.listHeaderFont }) {
            evaluator.evaluate(label, at: headerPath)
        }
        var children = rows
        if !header.isEmpty {
            children.insert(
                ViewNode(id: headerPath.id, kind: "SectionHeader", children: header), at: 0)
        }
        return ViewNode(
            id: sectionPath.id, kind: "Section", attributes: attributes, children: children)
    }

    /// One row for each option.
    func optionRows(
        _ options: [PickerOptionItem<SelectionValue>], in evaluator: Evaluator, at path: ViewPath,
        afterSelecting: (@MainActor () -> Void)? = nil
    ) -> [ViewNode] {
        options.enumerated().map { index, option in
            optionNode(
                option, id: optionID(option, index, in: path), in: evaluator,
                afterSelecting: afterSelecting)
        }
    }

    // MARK: Navigation link

    private func navigationLinkNodes(
        _ options: [PickerOptionItem<SelectionValue>], _ attributes: [String: String],
        in evaluator: Evaluator, at path: ViewPath
    ) -> [ViewNode] {
        let title = evaluateLabel(in: evaluator, at: path.appending("title")).text
        let value = options.first(where: isSelected)?.node
        let link = NavigationLink {
            PickerDestination(picker: self, title: title)
        } label: {
            LabeledContent {
                ResolvedNodes(nodes: value.map { [$0] } ?? [])
            } label: {
                label
            }
        }
        return evaluator.evaluate(link, at: path).map { node in
            var node = node
            node.attributes.merge(attributes) { own, _ in own }
            return node
        }
    }
}

/// The screen a navigation-link picker pushes: its options in a list, under
/// the picker's label as the title. Choosing one goes back.
struct PickerDestination<Label: View, SelectionValue: Hashable, Content: View>: View {
    let picker: Picker<Label, SelectionValue, Content>
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let dismiss = dismiss
        // Assumed: the list of options has an inline title.
        List {
            PickerRows(picker: picker) { dismiss() }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A picker's options as list rows, without its label.
struct PickerRows<Label: View, SelectionValue: Hashable, Content: View>: View {
    typealias Body = Never

    let picker: Picker<Label, SelectionValue, Content>
    let afterSelecting: @MainActor () -> Void

    var body: Never {
        fatalError("PickerRows is a primitive view and has no body.")
    }
}

extension PickerRows: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("Picker")
        let (nodes, tags) = evaluator.evaluateTagged(picker.content, at: ownPath)
        let options = nodes.map {
            PickerOptionItem(node: $0, tag: tags.tag(of: $0.id, as: SelectionValue.self))
        }
        return picker.optionRows(
            options, in: evaluator, at: ownPath, afterSelecting: afterSelecting)
    }
}

/// A view that shows nodes already resolved elsewhere, such as the
/// selected option a navigation-link picker shows, under its own path.
struct ResolvedNodes: View {
    typealias Body = Never

    let nodes: [ViewNode]

    var body: Never {
        fatalError("ResolvedNodes is a primitive view and has no body.")
    }
}

extension ResolvedNodes: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        nodes.enumerated().map { index, node in
            node.moved(to: path.appending("value[\(index)]").id)
        }
    }
}

// MARK: - Helpers

/// A value as a node attribute: an optional shows its value, or `nil`.
func describe(_ value: Any) -> String {
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional {
        return mirror.children.first.map { describe($0.value) } ?? "nil"
    }
    return String(describing: value)
}

extension ViewNode {
    /// The node and its descendants with identifiers under `id` instead of
    /// the node's own, for a copy of the node shown elsewhere in the tree.
    func moved(to id: NodeID) -> ViewNode {
        let old = self.id.rawValue
        func move(_ node: ViewNode) -> ViewNode {
            var node = node
            let raw = node.id.rawValue
            node.id = NodeID(
                id.rawValue + (raw.hasPrefix(old) ? String(raw.dropFirst(old.count)) : ""))
            node.children = node.children.map(move)
            return node
        }
        return move(self)
    }

    /// The node with a foreground style, unless it sets its own.
    func withDefaultForeground(_ style: String) -> ViewNode {
        var node = self
        if node.attributes["foregroundStyle"] == nil { node.attributes["foregroundStyle"] = style }
        return node
    }

    /// The node with every `Text` in `font` changed to `replacement`.
    func replacingFont(_ font: String, with replacement: String) -> ViewNode {
        var node = self
        if node.kind == "Text", node.attributes["font"] == font {
            node.attributes["font"] = replacement
        }
        node.children = node.children.map { $0.replacingFont(font, with: replacement) }
        return node
    }
}
