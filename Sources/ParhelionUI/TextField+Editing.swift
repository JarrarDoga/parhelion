import Foundation

// Editing a focused `TextField`: typing, caret movement, selection, and the
// pasteboard. The host keeps one focused field, a caret, and an optional
// selection anchor; the selection is the characters between the anchor and
// the caret.

/// What the host keeps for text editing beyond the focused field and caret.
struct TextEditingState {
    /// The other end of the selection from the caret, in characters, or
    /// `nil` when nothing is selected.
    var anchor: Int?
    /// The text on the pasteboard.
    var pasteboardText: String?
    /// Called when the app copies or an agent sets the pasteboard, so a
    /// session can pass the text to the window host's clipboard.
    var onCopy: (@MainActor (String) -> Void)?
}

extension ViewHost {
    /// A key that edits text or moves keyboard focus.
    public enum Key: String, Codable, Sendable, CaseIterable {
        case backspace, delete, left, right, home, end
        /// Moves the caret to the previous or next line of a vertical text field.
        case up, down
        /// Moves focus to the next text field.
        case tab
        /// Moves focus to the previous text field.
        case backTab
        /// Ends editing.
        case `return`, escape
        /// Extend the selection by a character, or to the start or end of
        /// the text, as Shift with an arrow key, Home, or End does.
        case selectLeft, selectRight, selectHome, selectEnd
        /// Selects the whole text of the focused field.
        case selectAll
        /// Copy the selection to the pasteboard, copy it and delete it, and
        /// insert the pasteboard's text in place of the selection.
        case copy, cut, paste
    }

    // MARK: - The pasteboard

    /// The text on the pasteboard, which paste inserts and `PasteButton`
    /// hands to its action. The window host keeps it in step with the system
    /// clipboard; a test or an agent can set it directly.
    public var pasteboardText: String? {
        get { editing.pasteboardText }
        set {
            guard newValue != editing.pasteboardText else { return }
            editing.pasteboardText = newValue
            // A `PasteButton` is enabled while the pasteboard has text.
            setNeedsUpdate()
            revision += 1
        }
    }

    /// Puts text on the pasteboard as a copy does, so the window host also
    /// puts it on the system clipboard.
    func copyToPasteboard(_ text: String) {
        pasteboardText = text
        editing.onCopy?(text)
    }

    /// Sets what a session does with copied text.
    func onCopy(_ action: (@MainActor (String) -> Void)?) {
        editing.onCopy = action
    }

    // MARK: - Selection

    /// The selected characters of the focused field, as offsets in
    /// characters from the start of its text, or `nil` when nothing is
    /// selected.
    public var selectedRange: Range<Int>? {
        guard let anchor = editing.anchor, focusedNodeID != nil, anchor != caretOffset else {
            return nil
        }
        return min(anchor, caretOffset)..<max(anchor, caretOffset)
    }

    /// The selected text of the focused field, or `nil` when nothing is
    /// selected.
    public var selectedText: String? {
        guard let range = selectedRange, let id = focusedNodeID, let field = textFields[id] else {
            return nil
        }
        let text = field.wrappedValue
        guard range.upperBound <= text.count else { return nil }
        let start = text.index(text.startIndex, offsetBy: range.lowerBound)
        let end = text.index(text.startIndex, offsetBy: range.upperBound)
        return String(text[start..<end])
    }

    /// Selects characters of the focused field and puts the caret at the end
    /// of the selection. Does nothing if no field is focused.
    public func select(_ range: Range<Int>) {
        update()
        guard let id = focusedNodeID, let field = textFields[id] else { return }
        let count = field.wrappedValue.count
        setSelection(
            anchor: min(max(range.lowerBound, 0), count),
            caret: min(max(range.upperBound, 0), count))
    }

    /// Sets the anchor and the caret, and changes the revision if either moved.
    func setSelection(anchor: Int?, caret: Int) {
        let anchor = anchor == caret ? nil : anchor
        if anchor != editing.anchor {
            editing.anchor = anchor
            revision += 1
        }
        caretOffset = caret
    }

    // MARK: - Focus

    /// Focuses a text field and puts the caret at the end of its text, or
    /// ends editing when `id` is `nil`.
    public func focus(_ id: NodeID?) throws(InteractionError) {
        update()
        guard let id else {
            focusedNodeID = nil
            setSelection(anchor: nil, caret: caretOffset)
            return
        }
        guard let field = textFields[id] else {
            throw root.node(withID: id) == nil ? .nodeNotFound(id) : .notEditable(id)
        }
        focusedNodeID = id
        setSelection(anchor: nil, caret: field.wrappedValue.count)
    }

    /// Moves focus to the next or previous text field in reading order,
    /// wrapping around.
    func moveFocus(forward: Bool) {
        let fields = interactiveRoot.allNodes.filter { textFields[$0.id] != nil }.map(\.id)
        guard !fields.isEmpty else { return }
        let next: NodeID
        if let current = focusedNodeID, let index = fields.firstIndex(of: current) {
            next = fields[(index + (forward ? 1 : fields.count - 1)) % fields.count]
        } else {
            next = forward ? fields[0] : fields[fields.count - 1]
        }
        try? focus(next)
    }

    /// Focuses a field the pointer was released on, with the caret nearest
    /// the point and nothing selected.
    func focusTextField(_ id: NodeID, caretAt point: CGPoint) {
        guard let field = textFields[id], let offset = caretOffset(in: id, field, at: point)
        else { return }
        focusedNodeID = id
        setSelection(anchor: nil, caret: offset)
    }

    /// Extends a selection that a drag over a field started. The first move
    /// focuses the field and anchors the selection where the press began.
    func selectText(in id: NodeID, from start: CGPoint, to point: CGPoint) {
        guard let field = textFields[id], let anchor = caretOffset(in: id, field, at: start),
            let caret = caretOffset(in: id, field, at: point, clamped: true)
        else { return }
        focusedNodeID = id
        setSelection(anchor: anchor, caret: caret)
    }

    /// The caret offset nearest a point on screen in a field, accounting for
    /// the horizontal shift that keeps the caret in view. A point outside the
    /// field gives `nil` unless `clamped`.
    private func caretOffset(
        in id: NodeID, _ field: Binding<String>, at point: CGPoint, clamped: Bool = false
    ) -> Int? {
        guard let node = root.node(withID: id), let frame = node.frame else { return nil }
        if let offset = verticalCaretOffset(for: node, at: point) { return offset }
        let text = field.wrappedValue
        let geometry = TextFieldGeometry(node: node)
        let shift =
            focusedNodeID == id
            ? geometry.horizontalShift(text: text, caret: caretOffset, width: frame.width) : 0
        return geometry.caretOffset(in: text, atX: point.x - frame.minX, shift: shift)
    }

    // MARK: - Typing and keys

    /// Inserts text at the caret of the focused field, in place of the
    /// selection, then updates the tree. Does nothing if no field is focused.
    public func typeText(_ text: String) {
        update()
        guard let id = focusedNodeID, let field = textFields[id] else { return }
        insert(text, into: field)
        update()
    }

    /// Replaces the selection, or inserts at the caret, and puts the caret
    /// after the new text.
    private func insert(_ text: String, into field: Binding<String>) {
        var value = field.wrappedValue
        let range = editRange(in: value)
        let lower = value.index(value.startIndex, offsetBy: range.lowerBound)
        let upper = value.index(value.startIndex, offsetBy: range.upperBound)
        value.replaceSubrange(lower..<upper, with: text)
        field.wrappedValue = value
        setSelection(anchor: nil, caret: range.lowerBound + text.count)
    }

    /// The characters an edit replaces: the selection, or an empty range at
    /// the caret.
    private func editRange(in value: String) -> Range<Int> {
        if let range = selectedRange, range.upperBound <= value.count { return range }
        let caret = min(caretOffset, value.count)
        return caret..<caret
    }

    /// Applies an editing or focus key.
    public func press(_ key: Key) {
        update()
        if pressInVerticalField(key) { return }
        switch key {
        case .tab, .backTab:
            moveFocus(forward: key == .tab)
            return
        case .return, .escape:
            focusedNodeID = nil
            setSelection(anchor: nil, caret: caretOffset)
            return
        default:
            break
        }
        guard let id = focusedNodeID, let field = textFields[id] else { return }
        let value = field.wrappedValue
        let caret = min(caretOffset, value.count)
        let selection = selectedRange
        switch key {
        case .backspace:
            if selection != nil {
                insert("", into: field)
            } else if caret > 0 {
                setSelection(anchor: caret, caret: caret - 1)
                insert("", into: field)
            }
        case .delete:
            if selection != nil {
                insert("", into: field)
            } else if caret < value.count {
                setSelection(anchor: caret, caret: caret + 1)
                insert("", into: field)
            }
        // A plain arrow key collapses a selection to its edge, as on iOS and
        // macOS; Home and End move to the ends.
        case .left:
            setSelection(anchor: nil, caret: selection?.lowerBound ?? max(caret - 1, 0))
        case .right:
            setSelection(anchor: nil, caret: selection?.upperBound ?? min(caret + 1, value.count))
        case .home:
            setSelection(anchor: nil, caret: 0)
        case .end:
            setSelection(anchor: nil, caret: value.count)
        case .selectLeft:
            setSelection(anchor: editing.anchor ?? caret, caret: max(caret - 1, 0))
        case .selectRight:
            setSelection(anchor: editing.anchor ?? caret, caret: min(caret + 1, value.count))
        case .selectHome:
            setSelection(anchor: editing.anchor ?? caret, caret: 0)
        case .selectEnd:
            setSelection(anchor: editing.anchor ?? caret, caret: value.count)
        case .selectAll:
            setSelection(anchor: 0, caret: value.count)
        case .copy:
            if let text = selectedText { copyToPasteboard(text) }
        case .cut:
            if let text = selectedText {
                copyToPasteboard(text)
                insert("", into: field)
            }
        case .paste:
            // Assumed: a single-line field turns line breaks in pasted text
            // into spaces, as UIKit's does. A vertical field keeps them.
            if let text = pasteboardText, !text.isEmpty {
                let vertical = root.node(withID: id)?.isVerticalTextField == true
                insert(vertical ? text : Self.singleLine(text), into: field)
            }
        default:
            break
        }
        update()
    }

    /// Pastes the text a window host read from the system clipboard.
    func paste(_ text: String) {
        pasteboardText = text
        press(.paste)
    }

    private static func singleLine(_ text: String) -> String {
        String(text.map { $0.isNewline ? " " : $0 })
    }
}
