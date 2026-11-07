import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// Line limits, truncation, and text fields that grow, for issue #80.
//
// `lineLimit(_:)` and `truncationMode(_:)` are environment values, as in
// SwiftUI: they reach every `Text` and `TextField` inside the view they are
// applied to. A `Text` records them on its node as the `lineLimit`,
// `reservesSpace`, and `truncationMode` attributes, and layout and drawing
// read them from there. A `TextField` with `axis: .vertical` records
// `axis=vertical`, `lineLimit`, and `lineLimitMinimum`.

extension Text {
    /// Where a text view cuts off its text, mirroring SwiftUI's
    /// `Text.TruncationMode`.
    public enum TruncationMode: Sendable, Hashable {
        case head
        case tail
        case middle

        var name: String {
            switch self {
            case .head: "head"
            case .tail: "tail"
            case .middle: "middle"
            }
        }

        init?(name: String?) {
            switch name {
            case "head": self = .head
            case "tail": self = .tail
            case "middle": self = .middle
            default: return nil
            }
        }
    }
}

// MARK: - The environment

/// How many lines text may use, from `lineLimit`.
struct TextLineLimit: Hashable, Sendable {
    /// The most lines text shows, or `nil` for any number. Assumed: a limit
    /// below 1 means no limit, as it does for SwiftUI's `Text`.
    var maximum: Int?
    /// The fewest lines a vertical text field is tall, 1 unless a range or
    /// `reservesSpace` says more.
    var fieldMinimum = 1
    /// Whether a `Text` is as tall as `maximum` lines even when it needs fewer.
    var reservesSpace = false

    static let none = TextLineLimit(maximum: nil)

    init(maximum: Int?, fieldMinimum: Int = 1, reservesSpace: Bool = false) {
        self.maximum = maximum.flatMap { $0 >= 1 ? $0 : nil }
        self.fieldMinimum = max(fieldMinimum, 1)
        self.reservesSpace = reservesSpace && self.maximum != nil
        if let maximum = self.maximum { self.fieldMinimum = min(self.fieldMinimum, maximum) }
    }
}

struct TextLineLimitKey: EnvironmentKey {
    static var defaultValue: TextLineLimit { .none }
}

struct TruncationModeKey: EnvironmentKey {
    static var defaultValue: Text.TruncationMode { .tail }
}

extension EnvironmentValues {
    /// The most lines text may use, or `nil` for any number. Set with
    /// ``View/lineLimit(_:)``.
    public var lineLimit: Int? {
        get { self[TextLineLimitKey.self].maximum }
        set { self[TextLineLimitKey.self] = TextLineLimit(maximum: newValue) }
    }

    /// Where text cuts off when it does not fit. Set with
    /// ``View/truncationMode(_:)``.
    public var truncationMode: Text.TruncationMode {
        get { self[TruncationModeKey.self] }
        set { self[TruncationModeKey.self] = newValue }
    }

    var textLineLimit: TextLineLimit {
        get { self[TextLineLimitKey.self] }
        set { self[TextLineLimitKey.self] = newValue }
    }
}

extension View {
    /// Limits text to a number of lines, or removes the limit with `nil`.
    /// The limit reaches every text view and text field inside this view.
    public func lineLimit(_ number: Int?) -> some View {
        environment(\.textLineLimit, TextLineLimit(maximum: number))
    }

    /// Sets the fewest lines text takes, with no limit: a text view or a
    /// vertical text field is at least the range's lower bound in lines tall.
    public func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View {
        environment(\.textLineLimit, TextLineLimit(maximum: nil, fieldMinimum: limit.lowerBound))
    }

    /// Limits text to the range's upper bound in lines. A text view or a
    /// vertical text field is at least the lower bound tall and grows to the
    /// upper bound.
    public func lineLimit(_ limit: ClosedRange<Int>) -> some View {
        environment(
            \.textLineLimit,
            TextLineLimit(maximum: limit.upperBound, fieldMinimum: limit.lowerBound))
    }

    /// Limits text to a number of lines. With `reservesSpace`, a text view is
    /// that many lines tall even when its text needs fewer, and a vertical
    /// text field starts that tall.
    public func lineLimit(_ limit: Int, reservesSpace: Bool) -> some View {
        environment(
            \.textLineLimit,
            TextLineLimit(
                maximum: limit, fieldMinimum: reservesSpace ? limit : 1,
                reservesSpace: reservesSpace))
    }

    /// Sets where text cuts off when it does not fit: at its end, its
    /// beginning, or its middle. The ellipsis shows only where a line limit,
    /// or too little room, makes text cut off.
    public func truncationMode(_ mode: Text.TruncationMode) -> some View {
        environment(\.truncationMode, mode)
    }
}

extension EnvironmentValues {
    /// Records the line limit and truncation mode on a node's attributes.
    /// Defaults record nothing, so outlines show only what was chosen.
    func recordTextLimits(in attributes: inout [String: String], isField: Bool) {
        let limit = textLineLimit
        if let maximum = limit.maximum { attributes["lineLimit"] = String(maximum) }
        // A range's lower bound is the fewest lines a `Text` or a vertical
        // field takes, even when it needs fewer.
        if limit.fieldMinimum > 1, isField || !limit.reservesSpace {
            attributes["lineLimitMinimum"] = String(limit.fieldMinimum)
        }
        if !isField {
            if limit.reservesSpace { attributes["reservesSpace"] = "true" }
            if truncationMode != .tail { attributes["truncationMode"] = truncationMode.name }
        }
    }
}

extension ViewNode {
    /// The line limit a node recorded.
    var textLineLimit: TextLineLimit {
        TextLineLimit(
            maximum: attributes["lineLimit"].flatMap { Int($0) },
            fieldMinimum: attributes["lineLimitMinimum"].flatMap { Int($0) } ?? 1,
            reservesSpace: attributes["reservesSpace"] == "true")
    }

    var textTruncationMode: Text.TruncationMode {
        Text.TruncationMode(name: attributes["truncationMode"]) ?? .tail
    }

    /// Whether the node is a text field that grows vertically.
    var isVerticalTextField: Bool {
        kind == "TextField" && attributes["axis"] == "vertical"
    }
}

// MARK: - Truncating text

extension TextMeasurer {
    /// The lines `text` takes at `width` in `font`, cut to `maximum` lines
    /// with an ellipsis where `mode` says.
    func limitedLines(
        of text: String, font: ResolvedFont, width: CGFloat?, maximum: Int?,
        mode: Text.TruncationMode
    ) -> [TextLine] {
        let all = lines(of: text, font: font, width: width)
        guard let maximum, all.count > maximum else { return all }
        let fit = width.flatMap { $0.isFinite ? max($0, 0) : nil }
        func cut(_ group: ArraySlice<TextLine>) -> TextLine {
            TextTruncation.truncate(group, mode: mode, fit: fit, font: font)
        }
        switch mode {
        case .tail:
            return Array(all[..<(maximum - 1)]) + [cut(all[(maximum - 1)...])]
        case .head:
            return [cut(all[...(all.count - maximum)])] + all[(all.count - maximum + 1)...]
        case .middle:
            let top = (maximum - 1) / 2
            let bottom = maximum - 1 - top
            return Array(all[..<top]) + [cut(all[top..<(all.count - bottom)])]
                + all[(all.count - bottom)...]
        }
    }

    /// The lines a `Text` node shows at `width`.
    func textLines(for node: ViewNode, width: CGFloat?) -> [TextLine] {
        limitedLines(
            of: node.text ?? "", font: ResolvedFont(node: node), width: width,
            maximum: node.textLineLimit.maximum, mode: node.textTruncationMode)
    }

    /// The size of a `Text` node when it is offered `width`.
    func textSize(of node: ViewNode, width: CGFloat?) -> CGSize {
        let font = ResolvedFont(node: node)
        let limit = node.textLineLimit
        let lines = textLines(for: node, width: width)
        let count = max(
            limit.reservesSpace ? max(lines.count, limit.maximum ?? 0) : lines.count,
            limit.fieldMinimum)
        return CGSize(
            width: lines.map(\.width).max() ?? 0,
            height: CGFloat(count) * font.lineHeight)
    }
}

enum TextTruncation {
    static let ellipsis = "…"
    /// Absorbs rounding, as the measurer's wrapping does.
    private static let tolerance: CGFloat = 0.001

    /// One line that stands for a group of lines whose text does not fit: the
    /// group's text with the part that `mode` hides replaced by an ellipsis,
    /// cut to `fit` points. Without a width, the group is cut at line
    /// boundaries instead.
    static func truncate(
        _ group: ArraySlice<TextLine>, mode: Text.TruncationMode, fit: CGFloat?, font: ResolvedFont
    ) -> TextLine {
        func measure(_ text: some StringProtocol) -> CGFloat {
            CGFloat(font.typeface.width(of: text, size: Double(font.size)))
        }
        let first = group.first?.text ?? ""
        let last = group.last?.text ?? ""
        guard let fit else {
            let text: String
            switch mode {
            case .tail: text = first + ellipsis
            case .head: text = ellipsis + last
            case .middle: text = first + ellipsis + last
            }
            return TextLine(text: text, width: measure(text))
        }

        let characters = Array(group.map(\.text).joined(separator: " "))
        let widths = characters.map { measure(String($0)) }
        let budget = fit + tolerance - measure(ellipsis)
        var head = 0
        var tail = 0
        var used: CGFloat = 0
        switch mode {
        case .tail:
            while head < characters.count, used + widths[head] <= budget {
                used += widths[head]
                head += 1
            }
        case .head:
            while tail < characters.count, used + widths[characters.count - 1 - tail] <= budget {
                used += widths[characters.count - 1 - tail]
                tail += 1
            }
        case .middle:
            // Takes a character from the start, then one from the end, while
            // both sides fit, so the start keeps the extra character.
            var progressed = true
            while progressed, head + tail < characters.count {
                progressed = false
                if used + widths[head] <= budget {
                    used += widths[head]
                    head += 1
                    progressed = true
                }
                if head + tail < characters.count,
                    used + widths[characters.count - 1 - tail] <= budget
                {
                    used += widths[characters.count - 1 - tail]
                    tail += 1
                    progressed = true
                }
            }
        }
        var start = String(characters[..<head])
        while start.last?.isWhitespace == true { start.removeLast() }
        var end = String(characters[(characters.count - tail)...])
        while end.first?.isWhitespace == true { end.removeFirst() }
        let text = start + ellipsis + end
        return TextLine(text: text, width: measure(text))
    }
}

// MARK: - Vertical text fields

extension TextField {
    /// Creates a text field that can grow along an axis. With `.vertical`, the
    /// field wraps its text, starts one line tall, and grows as text is typed,
    /// up to the limit that ``View/lineLimit(_:)`` sets; past the limit it
    /// scrolls to keep the caret in view. Return inserts a new line.
    public init(_ title: some StringProtocol, text: Binding<String>, axis: Axis) {
        self.init(title, text: text)
        self.axis = axis
    }
}

/// One line of a vertical text field, with where it starts in the text.
struct FieldLine: Equatable {
    /// The offset in characters of the line's first character.
    var start: Int
    var text: String
    var width: CGFloat

    var end: Int { start + text.count }
}

/// How a vertical text field breaks its text into lines and which lines show.
/// Layout, drawing, hit testing, and the caret share it so that they agree.
struct VerticalFieldGeometry {
    let font: TextFieldGeometry
    /// The lines of the value, or of the placeholder while the value is empty.
    let lines: [FieldLine]
    let showsPlaceholder: Bool
    /// The number of lines the field is tall.
    let visibleCount: Int
    /// The width the text wraps at, which leaves room for the caret.
    let textWidth: CGFloat

    var lineHeight: CGFloat { font.resolvedFont.lineHeight }

    /// - Parameters:
    ///   - width: The field's width.
    init(node: ViewNode, value: String, width: CGFloat, measurer: any TextMeasurer) {
        font = TextFieldGeometry(node: node)
        textWidth = max(width - TextFieldGeometry.caretWidth, 0)
        showsPlaceholder = value.isEmpty
        let shown = value.isEmpty ? node.attributes["placeholder"] ?? "" : value
        lines = Self.fieldLines(
            of: shown, font: font.resolvedFont, width: textWidth, measurer: measurer)
        let limit = node.textLineLimit
        let upper = limit.maximum ?? Int.max
        visibleCount = min(max(lines.count, limit.fieldMinimum), max(upper, limit.fieldMinimum))
    }

    /// Wraps `text` and records where each line starts. Wrapping drops the
    /// space or newline between two lines, so the offsets skip it.
    static func fieldLines(
        of text: String, font: ResolvedFont, width: CGFloat, measurer: any TextMeasurer
    ) -> [FieldLine] {
        let wrapped = measurer.lines(of: text, font: font, width: width)
        guard !wrapped.isEmpty else { return [FieldLine(start: 0, text: "", width: 0)] }
        let characters = Array(text)
        var result: [FieldLine] = []
        var cursor = 0
        for (index, line) in wrapped.enumerated() {
            result.append(FieldLine(start: cursor, text: line.text, width: line.width))
            cursor += line.text.count
            if index < wrapped.count - 1, cursor < characters.count,
                characters[cursor] == " " || characters[cursor] == "\n"
            {
                cursor += 1
            }
        }
        return result
    }

    /// The line the caret at `offset` is on: the last line that starts at or
    /// before it.
    func lineIndex(forOffset offset: Int) -> Int {
        lines.lastIndex { $0.start <= offset } ?? 0
    }

    /// The first line that shows. While the field is focused, the lines scroll
    /// so that the caret's line is the last one shown, once the text is taller
    /// than the field.
    func firstVisibleLine(caret: Int?) -> Int {
        guard let caret else { return 0 }
        return max(lineIndex(forOffset: caret) - visibleCount + 1, 0)
    }

    /// The distance from a line's leading edge to the caret at `offset`.
    func caretX(offset: Int, line index: Int) -> CGFloat {
        let line = lines[index]
        let count = min(max(offset - line.start, 0), line.text.count)
        return font.caretX(in: line.text, at: count)
    }

    /// The offset on line `index` nearest to `x`.
    func offset(onLine index: Int, nearX x: CGFloat) -> Int {
        let line = lines[index]
        return line.start + font.caretOffset(in: line.text, atX: x, shift: 0)
    }

    /// The caret offset for a point in a field whose frame is `frame`.
    func caretOffset(at point: CGPoint, in frame: CGRect, caret: Int?) -> Int {
        let top = firstVisibleLine(caret: caret)
        let row = Int(((point.y - frame.minY) / max(lineHeight, 1)).rounded(.down))
        let index = min(max(top + row, 0), lines.count - 1)
        return offset(onLine: index, nearX: point.x - frame.minX)
    }
}

extension LayoutEngine {
    /// The size of a vertical text field: as wide as it is offered, and as
    /// tall as its text, within the line limit.
    func verticalFieldSize(_ node: ViewNode, _ proposal: ProposedSize) -> CGSize {
        let font = TextFieldGeometry(node: node).resolvedFont
        let value = node.attributes["value"] ?? ""
        let width: CGFloat
        if let offered = proposal.width {
            width = offered
        } else {
            let widest =
                [value, node.attributes["placeholder"] ?? ""]
                .map { measurer.size(of: $0, font: font, width: nil).width }
                .max() ?? 0
            width = widest + TextFieldGeometry.caretWidth
        }
        let geometry = VerticalFieldGeometry(
            node: node, value: value, width: width, measurer: measurer)
        return CGSize(width: width, height: CGFloat(geometry.visibleCount) * font.lineHeight)
    }
}

extension TreeRenderer {
    /// Draws a vertical text field: the lines that show, or the placeholder
    /// while the value is empty, and a caret when it is focused. Text taller
    /// than the field scrolls to keep the caret in view.
    func drawVerticalTextField(
        _ node: ViewNode, in frame: CGRect, style: String, paint: (String) -> RGBA,
        into canvas: inout Canvas
    ) {
        let value = node.attributes["value"] ?? ""
        let isFocused = node.id == focusedNodeID
        let caret = min(caretOffset, value.count)
        let geometry = VerticalFieldGeometry(
            node: node, value: value, width: frame.width, measurer: measurer)
        let top = geometry.firstVisibleLine(caret: isFocused ? caret : nil)
        let baseline = Double(geometry.font.resolvedFont.baseline)

        let outerClip = canvas.clipRect
        canvas.clipRect = outerClip.map { $0.intersection(frame) } ?? frame
        defer { canvas.clipRect = outerClip }

        // Assumed: placeholders use the tertiary label color, as on iOS.
        let color = paint(geometry.showsPlaceholder ? "tertiary" : style)
        for row in 0..<geometry.visibleCount where top + row < geometry.lines.count {
            let line = geometry.lines[top + row]
            canvas.drawText(
                line.text, font: geometry.font.font, size: geometry.font.fontSize,
                origin: CGPoint(
                    x: Double(frame.minX),
                    y: Double(frame.minY + CGFloat(row) * geometry.lineHeight) + baseline),
                color: color)
        }
        if isFocused {
            let index = geometry.lineIndex(forOffset: caret)
            let x = frame.minX + geometry.caretX(offset: caret, line: index)
            canvas.fill(
                CGRect(
                    x: x, y: frame.minY + CGFloat(index - top) * geometry.lineHeight,
                    width: TextFieldGeometry.caretWidth, height: geometry.lineHeight),
                color: paint("tint"))
        }
    }
}

extension ViewHost {
    /// The geometry of the vertical text field `node`, with its value.
    private func verticalGeometry(of node: ViewNode, width: CGFloat) -> VerticalFieldGeometry {
        VerticalFieldGeometry(
            node: node, value: textFields[node.id]?.wrappedValue ?? "", width: width,
            measurer: FontTextMeasurer())
    }

    /// The caret offset a click at `point` puts in a vertical text field.
    func verticalCaretOffset(for node: ViewNode, at point: CGPoint) -> Int? {
        guard node.isVerticalTextField, let frame = node.frame else { return nil }
        let geometry = verticalGeometry(of: node, width: frame.width)
        return geometry.caretOffset(
            at: point, in: frame, caret: focusedNodeID == node.id ? caretOffset : nil)
    }

    /// Handles the keys that behave differently in a vertical text field:
    /// Return inserts a new line, Up and Down move the caret between lines,
    /// and Home and End go to the start and end of the caret's line.
    ///
    /// - Returns: Whether the key was handled.
    func pressInVerticalField(_ key: Key) -> Bool {
        guard let id = focusedNodeID, let node = root.node(withID: id), node.isVerticalTextField,
            let frame = node.frame
        else { return false }
        switch key {
        case .return:
            typeText("\n")
            return true
        case .up, .down, .home, .end:
            let geometry = verticalGeometry(of: node, width: frame.width)
            let caret = min(caretOffset, textFields[id]?.wrappedValue.count ?? 0)
            let index = geometry.lineIndex(forOffset: caret)
            switch key {
            case .home:
                setSelection(anchor: nil, caret: geometry.lines[index].start)
            case .end:
                setSelection(anchor: nil, caret: geometry.lines[index].end)
            default:
                let target = index + (key == .up ? -1 : 1)
                if geometry.lines.indices.contains(target) {
                    setSelection(
                        anchor: nil,
                        caret: geometry.offset(
                            onLine: target, nearX: geometry.caretX(offset: caret, line: index)))
                } else {
                    setSelection(
                        anchor: nil, caret: key == .up ? 0 : textFields[id]?.wrappedValue.count ?? 0
                    )
                }
            }
            update()
            return true
        default:
            return false
        }
    }
}
