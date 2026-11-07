import Foundation

/// A view that generates its content from a collection, mirroring SwiftUI's
/// `DynamicViewContent`.
public protocol DynamicViewContent: View {
    associatedtype Data: Collection

    var data: Data { get }
}

extension ForEach: DynamicViewContent {}

/// A `ForEach` with `onMove` or `onDelete` handlers, mirroring the opaque
/// result of those modifiers in SwiftUI.
///
/// In a ``List`` whose `editMode` is active, each row shows what the handlers
/// allow: a delete button before the row for `onDelete`, and a reorder handle
/// after it for `onMove`. Tapping the delete button shows a Delete button
/// where the handle was; tapping that calls the `onDelete` action with the
/// row's offset. Dragging a handle onto another row calls the `onMove` action
/// with the row's offset and the offset to insert it before. Outside edit
/// mode, the rows are the content's rows, unchanged.
public struct _DynamicContentModifier<Content: DynamicViewContent>: DynamicViewContent {
    public typealias Body = Never

    let content: Content
    let moveAction: ((IndexSet, Int) -> Void)?
    let deleteAction: ((IndexSet) -> Void)?

    public var data: Content.Data { content.data }

    public var body: Never {
        fatalError("This modifier's result is a primitive view and has no body.")
    }
}

extension DynamicViewContent {
    /// Sets the action that reorders the content's elements. In a list in
    /// edit mode, each row shows a handle to drag.
    ///
    /// The action receives the offsets of the elements to move and the offset
    /// of the element they go before, in the collection as it was before the
    /// move. Passing `nil` removes the action.
    public func onMove(perform action: ((IndexSet, Int) -> Void)?) -> some DynamicViewContent {
        _DynamicContentModifier(content: self, moveAction: action, deleteAction: nil)
    }

    /// Sets the action that deletes the content's elements. In a list in edit
    /// mode, each row shows a delete button.
    ///
    /// The action receives the offsets of the elements to delete. Passing
    /// `nil` removes the action.
    public func onDelete(perform action: ((IndexSet) -> Void)?) -> some DynamicViewContent {
        _DynamicContentModifier(content: self, moveAction: nil, deleteAction: action)
    }
}

extension View {
    /// Whether the row can be dragged to a new position in edit mode.
    public func moveDisabled(_ isDisabled: Bool) -> some View {
        attributeModifier("moveDisabled", isDisabled ? "true" : "false")
    }

    /// Whether the row can be deleted in edit mode.
    public func deleteDisabled(_ isDisabled: Bool) -> some View {
        attributeModifier("deleteDisabled", isDisabled ? "true" : "false")
    }
}

/// Whether a list is being edited, mirroring SwiftUI's `EditMode`.
public enum EditMode: Sendable {
    case inactive
    case transient
    case active

    public var isEditing: Bool { self != .inactive }
}

struct EditModeKey: EnvironmentKey {
    static var defaultValue: Binding<EditMode>? { nil }
}

extension EnvironmentValues {
    /// The edit mode that a view above set. `nil` until one does.
    public var editMode: Binding<EditMode>? {
        get { self[EditModeKey.self] }
        set { self[EditModeKey.self] = newValue }
    }
}

/// A button that turns edit mode on and off, mirroring SwiftUI's
/// `EditButton`.
///
/// It reads and writes the `editMode` environment value, so it does nothing
/// until a view above sets one with `environment(\.editMode, $mode)`. Unlike
/// SwiftUI, Parhelion does not supply an edit mode of its own.
public struct EditButton: View {
    @Environment(\.editMode) private var editMode

    public init() {}

    public var body: some View {
        let isEditing = editMode?.wrappedValue.isEditing == true
        Button(isEditing ? "Done" : "Edit") {
            guard let editMode else { return }
            editMode.wrappedValue = isEditing ? .inactive : .active
        }
    }
}

// MARK: - Resolving

/// The nodes one element of a `ForEach` resolved to.
struct ElementNodes {
    var identity: String
    var nodes: [ViewNode]
}

/// What a `ForEach`, or a chain of `onMove` and `onDelete` on one, resolves
/// to before rows are decorated for edit mode.
struct EditableContent {
    var elements: [ElementNodes]
    var move: ((IndexSet, Int) -> Void)?
    var delete: ((IndexSet) -> Void)?
}

protocol EditableElements {
    @MainActor func editableContent(in evaluator: Evaluator, at path: ViewPath) -> EditableContent
}

extension ForEach: EditableElements {
    // Resolves like ``ForEach``'s own nodes, but keeps the elements apart.
    func editableContent(in evaluator: Evaluator, at path: ViewPath) -> EditableContent {
        let elements = data.map { element in
            let (identity, nodes) = evaluateElement(element, in: evaluator, at: path)
            return ElementNodes(identity: identity, nodes: nodes)
        }
        return EditableContent(elements: elements)
    }
}

extension _DynamicContentModifier: EditableElements {
    func editableContent(in evaluator: Evaluator, at path: ViewPath) -> EditableContent {
        var inner =
            (content as? any EditableElements)?.editableContent(in: evaluator, at: path)
            ?? EditableContent(elements: [])
        inner.move = moveAction ?? inner.move
        inner.delete = deleteAction ?? inner.delete
        return inner
    }
}

extension _DynamicContentModifier: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        guard content is any EditableElements else {
            return evaluator.evaluate(content, at: path)
        }
        let editable = editableContent(in: evaluator, at: path)
        let environment = evaluator.environment
        let isEditing = environment.isInList && environment.editMode?.wrappedValue.isEditing == true
        let revealed = evaluator.host.stateBox(
            forKey: path.id.rawValue + ".revealedDelete", initialValue: String?.none)
        guard isEditing, editable.move != nil || editable.delete != nil else {
            revealed.value = nil
            return editable.elements.flatMap(\.nodes)
        }
        return decorate(editable, revealed: revealed, in: evaluator, at: path)
    }

    private func decorate(
        _ editable: EditableContent, revealed: StateBox<String?>, in evaluator: Evaluator,
        at path: ViewPath
    ) -> [ViewNode] {
        // The row each element ends up as, for the drag to find the row it
        // is dropped on.
        var rowIDs: [NodeID] = []
        var wrapped: [[ViewNode]] = []
        var handles: [(index: Int, id: NodeID)] = []
        if let target = revealed.value,
            !editable.elements.contains(where: { $0.identity == target })
        {
            revealed.value = nil
        }
        for (index, element) in editable.elements.enumerated() {
            var nodes: [ViewNode] = []
            for node in element.nodes {
                let canDelete =
                    editable.delete != nil && node.attributes["deleteDisabled"] != "true"
                let canMove = editable.move != nil && node.attributes["moveDisabled"] != "true"
                guard canDelete || canMove else {
                    nodes.append(node)
                    continue
                }
                let rowPath = path.appending("EditRow[\(element.identity)]")
                var children: [ViewNode] = []
                let isRevealed = revealed.value == element.identity
                if canDelete {
                    children += evaluator.evaluate(
                        EditControls.minus {
                            revealed.value = isRevealed ? nil : element.identity
                            evaluator.host.setNeedsUpdate()
                        }, at: rowPath.appending("delete"))
                }
                children.append(node)
                children += evaluator.evaluate(Spacer(), at: rowPath.appending("spacer"))
                if canDelete, isRevealed, let delete = editable.delete {
                    children += evaluator.evaluate(
                        EditControls.confirm {
                            revealed.value = nil
                            delete(IndexSet(integer: index))
                            evaluator.host.setNeedsUpdate()
                        }, at: rowPath.appending("confirm"))
                } else if canMove {
                    let handle = evaluator.evaluate(
                        EditControls.handle, at: rowPath.appending("reorder"))
                    handles += handle.map { (index, $0.id) }
                    children += handle
                }
                let rowID = rowPath.appending("HStack").id
                nodes.append(
                    ViewNode(
                        id: rowID, kind: "HStack",
                        attributes: ["spacing": formatPoints(EditControls.spacing)],
                        children: children))
            }
            rowIDs.append(nodes.first?.id ?? element.nodes.first?.id ?? path.id)
            wrapped.append(nodes)
        }
        if let move = editable.move {
            for handle in handles {
                evaluator.registerInputHandlers(
                    NodeInputHandlers(
                        drag: { [weak host = evaluator.host] _, end, _ in
                            guard let host else { return }
                            EditControls.drop(
                                row: handle.index, at: end, rows: rowIDs, in: host, move: move)
                        }),
                    for: handle.id)
            }
        }
        return wrapped.flatMap { $0 }
    }
}

/// The controls that edit mode adds to a row, and where a dragged row lands.
@MainActor
enum EditControls {
    static let spacing: CGFloat = 12

    static func minus(_ action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill").foregroundStyle(Color.red)
        }
        .accessibilityLabel("Delete")
    }

    static func confirm(_ action: @escaping @MainActor () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Text("Delete").foregroundStyle(Color.red)
        }
    }

    static var handle: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.secondary)
            .accessibilityLabel("Reorder")
    }

    /// Moves the row at offset `row` to the row that contains the point,
    /// or to the first or last row if the point is above or below all of
    /// them.
    static func drop(
        row: Int, at point: CGPoint, rows: [NodeID], in host: ViewHost,
        move: (IndexSet, Int) -> Void
    ) {
        let frames = rows.map { host.interactiveRoot.node(withID: $0)?.hitFrame }
        guard row < frames.count, !frames.isEmpty else { return }
        var target = frames.indices.first {
            frames[$0].map { $0.minY <= point.y && point.y < $0.maxY } ?? false
        }
        if target == nil {
            let tops = frames.compactMap { $0?.minY }
            if let top = tops.min(), point.y < top { target = 0 } else { target = frames.count - 1 }
        }
        guard let target, target != row else { return }
        move(IndexSet(integer: row), target > row ? target + 1 : target)
    }
}
