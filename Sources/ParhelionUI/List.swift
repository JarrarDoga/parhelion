#if canImport(Foundation)
import Foundation
#endif

/// A scrollable container that presents rows of data in a single column,
/// mirroring SwiftUI's `List`.
///
/// Each view the content resolves to is one row. Rows outside a ``Section``
/// are grouped into sections of their own. A button row responds to taps
/// across its whole width. The default style is iOS's inset grouped style.
/// Selection, editing, and swipe actions are not supported yet.
public struct List<SelectionValue: Hashable, Content: View>: View {
    public typealias Body = Never

    let content: Content

    public var body: Never {
        fatalError("List is a primitive view and has no body.")
    }
}

extension List where SelectionValue == Never {
    /// Creates a list of the given content.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// Creates a list with one row for each element of identifiable data.
    public init<Data, RowContent>(
        _ data: Data,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    )
    where
        Content == ForEach<Data, Data.Element.ID, RowContent>,
        Data: RandomAccessCollection, RowContent: View, Data.Element: Identifiable
    {
        content = ForEach(data, content: rowContent)
    }

    /// Creates a list with one row for each element of data, identified by
    /// the given key path.
    public init<Data, ID, RowContent>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    )
    where
        Content == ForEach<Data, ID, RowContent>,
        Data: RandomAccessCollection, ID: Hashable, RowContent: View
    {
        content = ForEach(data, id: id, content: rowContent)
    }

    /// Creates a list with one row for each integer in a constant range.
    public init<RowContent>(
        _ data: Range<Int>,
        @ViewBuilder rowContent: @escaping (Int) -> RowContent
    )
    where Content == ForEach<Range<Int>, Int, RowContent>, RowContent: View {
        content = ForEach(data, content: rowContent)
    }
}

extension List: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("List")
        // Rows outside a section form sections of their own, one for each run
        // of consecutive rows.
        var sections: [ViewNode] = []
        var looseRows: [ViewNode] = []
        var implicitCount = 0
        func closeImplicitSection() {
            guard !looseRows.isEmpty else { return }
            let id = ownPath.appending("Section[\(implicitCount)]").id
            sections.append(ViewNode(id: id, kind: "Section", children: looseRows))
            implicitCount += 1
            looseRows = []
        }
        let content = evaluator.withEnvironment({ $0.isInList = true }) {
            evaluator.evaluate(self.content, at: ownPath)
        }
        for node in content {
            if node.kind == "Section" {
                closeImplicitSection()
                sections.append(node)
            } else {
                looseRows.append(node)
            }
        }
        closeImplicitSection()

        // Every row gets the list's row insets, recorded as its outermost
        // layout modifier so that layout and drawing can find its cell.
        for index in sections.indices {
            sections[index].children = sections[index].children.map { child in
                guard child.kind != "SectionHeader", child.kind != "SectionFooter" else {
                    return child
                }
                var row = child
                var insets = child.controlRowInsets(LayoutDefaults.listRowInsets)
                if row.kind == "NavigationLink" {
                    // Leave room for the disclosure indicator.
                    insets.trailing +=
                        LayoutDefaults.disclosureIndicatorSize.width
                        + LayoutDefaults.disclosureIndicatorSpacing
                }
                row.modifiers.append(.listRow(insets))
                return row
            }
        }
        return [ViewNode(id: ownPath.id, kind: "List", children: sections)]
    }
}

/// A container that groups rows with an optional header and footer,
/// mirroring SwiftUI's `Section`.
///
/// In a ``List``, a section draws its rows together in one group, with the
/// header above and the footer below, and gives the header and footer the
/// list's fonts. Elsewhere, it stacks its header, content, and footer
/// vertically.
public struct Section<Parent: View, Content: View, Footer: View>: View {
    public typealias Body = Never

    let header: Parent
    let content: Content
    let footer: Footer

    /// Creates a section with a header and a footer.
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Parent,
        @ViewBuilder footer: () -> Footer
    ) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    /// Creates a section with the given header, footer, and content.
    public init(header: Parent, footer: Footer, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
        self.footer = footer
    }

    public var body: Never {
        fatalError("Section is a primitive view and has no body.")
    }
}

extension Section where Footer == EmptyView {
    /// Creates a section with a header.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }

    /// Creates a section with the given header and content.
    public init(header: Parent, @ViewBuilder content: () -> Content) {
        self.init(header: header, footer: EmptyView(), content: content)
    }
}

extension Section where Parent == EmptyView {
    /// Creates a section with a footer.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }

    /// Creates a section with the given footer and content.
    public init(footer: Footer, @ViewBuilder content: () -> Content) {
        self.init(header: EmptyView(), footer: footer, content: content)
    }
}

extension Section where Parent == EmptyView, Footer == EmptyView {
    /// Creates a section without a header or a footer.
    public init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension Section where Parent == Text, Footer == EmptyView {
    /// Creates a section with a text header.
    public init(_ title: some StringProtocol, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(title) })
    }
}

extension Section: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("Section")
        var children: [ViewNode] = []
        let headerPath = ownPath.appending("header")
        // In a list, headers and footers have their own fonts, which a font
        // set inside them overrides.
        let inList = evaluator.environment.isInList
        func labelFont(_ font: Font) -> (inout EnvironmentValues) -> Void {
            { if inList { $0.font = font } }
        }
        let headerNodes = evaluator.withEnvironment(labelFont(LayoutDefaults.listHeaderFont)) {
            evaluator.evaluate(header, at: headerPath)
        }
        if !headerNodes.isEmpty {
            children.append(
                ViewNode(id: headerPath.id, kind: "SectionHeader", children: headerNodes))
        }
        children += evaluator.evaluate(content, at: ownPath)
        let footerPath = ownPath.appending("footer")
        let footerNodes = evaluator.withEnvironment(labelFont(LayoutDefaults.listFooterFont)) {
            evaluator.evaluate(footer, at: footerPath)
        }
        if !footerNodes.isEmpty {
            children.append(
                ViewNode(id: footerPath.id, kind: "SectionFooter", children: footerNodes))
        }
        return [ViewNode(id: ownPath.id, kind: "Section", children: children)]
    }
}

struct IsInListKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// Whether the view is in a ``List``, where sections style their headers
    /// and footers.
    var isInList: Bool {
        get { self[IsInListKey.self] }
        set { self[IsInListKey.self] = newValue }
    }
}

// MARK: - List styles

/// The appearance of a ``List``, set with ``View/listStyle(_:)``.
public protocol ListStyle: Sendable {
    /// The name recorded in the tree.
    var styleName: String { get }
}

/// The platform's default list style: inset grouped on iOS.
public struct DefaultListStyle: ListStyle {
    public var styleName: String { "insetGrouped" }

    public init() {}
}

/// Rows in rounded groups, inset from the edges of the list.
public struct InsetGroupedListStyle: ListStyle {
    public var styleName: String { "insetGrouped" }

    public init() {}
}

/// Rows in groups that span the width of the list.
public struct GroupedListStyle: ListStyle {
    public var styleName: String { "grouped" }

    public init() {}
}

/// Rows that span the width of the list, without group backgrounds.
public struct PlainListStyle: ListStyle {
    public var styleName: String { "plain" }

    public init() {}
}

/// Rows without group backgrounds. Parhelion draws it as the plain style.
public struct InsetListStyle: ListStyle {
    public var styleName: String { "plain" }

    public init() {}
}

/// A sidebar list. On iPhone, Parhelion draws it as the inset grouped style.
public struct SidebarListStyle: ListStyle {
    public var styleName: String { "insetGrouped" }

    public init() {}
}

extension ListStyle where Self == DefaultListStyle {
    public static var automatic: DefaultListStyle { DefaultListStyle() }
}

extension ListStyle where Self == InsetGroupedListStyle {
    public static var insetGrouped: InsetGroupedListStyle { InsetGroupedListStyle() }
}

extension ListStyle where Self == GroupedListStyle {
    public static var grouped: GroupedListStyle { GroupedListStyle() }
}

extension ListStyle where Self == PlainListStyle {
    public static var plain: PlainListStyle { PlainListStyle() }
}

extension ListStyle where Self == InsetListStyle {
    public static var inset: InsetListStyle { InsetListStyle() }
}

extension ListStyle where Self == SidebarListStyle {
    public static var sidebar: SidebarListStyle { SidebarListStyle() }
}

extension View {
    /// Sets the style of lists in this view.
    public func listStyle(_ style: some ListStyle) -> some View {
        attributeModifier("listStyle", style.styleName)
    }
}

/// The layout of one list style.
struct ListStyleMetrics {
    /// The space around all of the list's sections.
    var contentInsets: EdgeInsets
    /// Whether the list and its sections draw group backgrounds.
    var isGrouped: Bool
    /// The corner radius of each section's group.
    var cornerRadius: CGFloat

    init(styleName: String?) {
        switch styleName {
        case "plain":
            self.init(contentInsets: EdgeInsets(), isGrouped: false, cornerRadius: 0)
        case "grouped":
            self.init(
                contentInsets: EdgeInsets(
                    top: LayoutDefaults.listContentInsets.top, leading: 0,
                    bottom: LayoutDefaults.listContentInsets.bottom, trailing: 0),
                isGrouped: true,
                cornerRadius: 0
            )
        default:
            self.init(
                contentInsets: LayoutDefaults.listContentInsets,
                isGrouped: true,
                cornerRadius: LayoutDefaults.listCornerRadius
            )
        }
    }

    init(contentInsets: EdgeInsets, isGrouped: Bool, cornerRadius: CGFloat) {
        self.contentInsets = contentInsets
        self.isGrouped = isGrouped
        self.cornerRadius = cornerRadius
    }

    /// The space between sections.
    var sectionSpacing: CGFloat { isGrouped ? LayoutDefaults.listSectionSpacing : 0 }
}

extension ViewNode {
    /// The cell this node fills, if it is a row of a list.
    var listRowFrame: CGRect? {
        guard let index = modifiers.lastIndex(where: { $0.isListRow }),
            index < modifierFrames.count
        else { return nil }
        return modifierFrames[index]
    }

    /// The area that receives taps: a list row's whole cell, or the node's
    /// frame.
    var hitFrame: CGRect? {
        listRowFrame ?? frame
    }

    /// Whether the node shows scrollable content.
    var isScrollContainer: Bool {
        kind == "ScrollView" || kind == "List"
    }
}

extension LayoutModifier {
    var isListRow: Bool {
        if case .listRow = self { return true }
        return false
    }
}
