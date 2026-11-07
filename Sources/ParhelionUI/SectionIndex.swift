#if canImport(Foundation)
import Foundation
#endif

// The section index of a list: a column of letters along the trailing edge.
// Tapping a letter, or dragging over the column, scrolls the list so that the
// section with that label is at the top.
//
// The index is an overlay of the `List` node, made of ordinary views: a
// button for each letter, so that every client of `ViewHost` can tap it, and
// a drag gesture on the column, so that a press that moves over the letters
// follows the pointer.

extension View {
    /// Shows or hides the section index of lists in this view.
    ///
    /// A list shows an index along its trailing edge when `visibility` is not
    /// `.hidden` and at least one of its sections has a
    /// ``sectionIndexLabel(_:)``. Assumed: `.automatic` and `.visible` both
    /// show it, because Parhelion has no other reason to hide it.
    public func listSectionIndexVisibility(_ visibility: Visibility) -> some View {
        environment(\.listSectionIndexVisibility, visibility)
    }

    /// Sets the label that stands for this section in the section index of
    /// its list. A `nil` label removes a label that a view inside set.
    ///
    /// The label is recorded as the `sectionIndexLabel` attribute of the
    /// section's node. Sections whose labels are equal share a letter, which
    /// scrolls to the first of them. Assumed: iOS does the same.
    public func sectionIndexLabel(_ label: Text?) -> some View {
        SectionIndexLabelView(content: self, label: label?.content)
    }
}

struct ListSectionIndexVisibilityKey: EnvironmentKey {
    static var defaultValue: Visibility { .automatic }
}

extension EnvironmentValues {
    /// Whether lists show a section index.
    var listSectionIndexVisibility: Visibility {
        get { self[ListSectionIndexVisibilityKey.self] }
        set { self[ListSectionIndexVisibilityKey.self] = newValue }
    }
}

/// A view that records its section index label on the nodes it resolves to.
struct SectionIndexLabelView<Content: View>: View {
    typealias Body = Never

    let content: Content
    let label: String?

    var body: Never {
        fatalError("SectionIndexLabelView is a primitive view and has no body.")
    }
}

extension SectionIndexLabelView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.evaluate(content, at: path).map { node in
            var node = node
            node.attributes["sectionIndexLabel"] = label
            return node
        }
    }
}

// MARK: - The index

/// Measurements of the index. Assumed, not measured on a device: iOS's index
/// is a column of small semibold letters, about 16 points apart, with a
/// touch area wider than the letters.
enum SectionIndex {
    /// The width of the column, which is also the touch area of a letter.
    static let width: CGFloat = 28
    /// The distance between the centers of two letters.
    static let pitch: CGFloat = 16
    /// The size of a letter.
    static let fontSize: CGFloat = 11

    /// The label a section stands for in the index, from the section or,
    /// failing that, its first row.
    static func label(of section: ViewNode) -> String? {
        if let label = section.attributes["sectionIndexLabel"] { return label }
        return section.children.lazy
            .filter { $0.kind != "SectionHeader" && $0.kind != "SectionFooter" }
            .compactMap { $0.attributes["sectionIndexLabel"] }.first
    }

    /// Adds the index to a list's node as an overlay at its trailing edge,
    /// unless the environment hides it or no section has a label.
    @MainActor
    static func attach(to list: inout ViewNode, in evaluator: Evaluator) {
        guard evaluator.environment.listSectionIndexVisibility != .hidden else { return }
        // One letter for each distinct label, in section order.
        var labels: [String] = []
        var sections: [NodeID] = []
        for section in list.children where section.kind == "Section" {
            guard let label = label(of: section), !labels.contains(label) else { continue }
            labels.append(label)
            sections.append(section.id)
        }
        guard !labels.isEmpty else { return }

        let host = evaluator.host
        let listID = list.id
        let view = SectionIndexView(labels: labels) { index in
            scroll(host, list: listID, to: sections[index])
        }
        // The overlay belongs to the list, so its identity follows the
        // list's, as for `overlay(alignment:content:)`.
        let overlayPath = ViewPath().appending(listID.rawValue).appending("overlay")
        let index = ViewNode(
            id: overlayPath.appending("SectionIndex").id, kind: "Overlay",
            children: evaluator.evaluate(view, at: overlayPath.appending("SectionIndex")))
        list.children.append(index)
        list.modifiers.append(.overlay(alignment: .trailing))
    }

    /// Scrolls a list so that a section starts at the top of its content's
    /// visible area, below a navigation bar, clamped to the list's content.
    ///
    /// The offset that puts a section there is its distance from the first
    /// section, plus the space the list's style leaves above its sections,
    /// whatever the list is scrolled to now.
    @MainActor
    static func scroll(_ host: ViewHost, list: NodeID, to section: NodeID) {
        guard let listNode = host.root.node(withID: list),
            let first = listNode.children.first(where: { $0.kind == "Section" })?.frame,
            let start = host.root.node(withID: section)?.frame,
            let offset = host.scrollOffset(of: list)
        else { return }
        let style = ListStyleMetrics(styleName: listNode.attributes["listStyle"])
        let target = start.minY - first.minY + style.contentInsets.top
        try? host.scroll(list, to: CGPoint(x: offset.x, y: target))
    }
}

/// The column of letters. A letter is a plain button; a drag over the column
/// scrolls to the letter under the pointer.
private struct SectionIndexView: View {
    let labels: [String]
    let select: @MainActor (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Button {
                    select(index)
                } label: {
                    Text(label)
                        .font(.system(size: SectionIndex.fontSize, weight: .semibold))
                        .frame(width: SectionIndex.width, height: SectionIndex.pitch)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.tint)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let index = Int((value.location.y / SectionIndex.pitch).rounded(.down))
                    let last = labels.count - 1
                    MainActor.assumeIsolated { select(min(max(index, 0), last)) }
                }
        )
    }
}
