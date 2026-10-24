import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// A control that displays an editable line of text, mirroring SwiftUI's
/// `TextField`.
///
/// Click or tap the field to focus it, or press Tab to move between fields.
/// While a field is focused, typing inserts text at the caret, and Backspace,
/// Delete, the arrow keys, Home, and End edit and move the caret. Return or
/// Escape ends editing. Text selection is not supported yet.
public struct TextField: View {
    public typealias Body = Never

    let placeholder: String
    let text: Binding<String>

    public init(_ title: some StringProtocol, text: Binding<String>) {
        placeholder = String(title)
        self.text = text
    }

    public var body: Never {
        fatalError("TextField is a primitive view and has no body.")
    }
}

extension TextField: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("TextField")
        var attributes = ["placeholder": placeholder, "value": text.wrappedValue]
        // A field's text is body text, which scales with Dynamic Type.
        Font.body.resolved(dynamicTypeSize: evaluator.environment.dynamicTypeSize)
            .record(in: &attributes)
        if evaluator.environment.isEnabled {
            evaluator.registerTextField(text, for: ownPath.id)
        } else {
            attributes["disabled"] = "true"
        }
        return [ViewNode(id: ownPath.id, kind: "TextField", attributes: attributes)]
    }
}

/// Where the caret and text of a single-line field sit, shared by hit
/// testing and drawing so that both agree.
struct TextFieldGeometry {
    /// The font of a field's text: the body style, at the size its node
    /// records.
    let resolvedFont: ResolvedFont
    let font: TrueTypeFont
    let fontSize: Double

    init(node: ViewNode) {
        resolvedFont = ResolvedFont(node: node)
        font = resolvedFont.typeface
        fontSize = Double(resolvedFont.size)
    }

    /// Assumed: the caret's width in points.
    static let caretWidth: CGFloat = 2

    /// The distance from the field's leading edge to the caret before the
    /// character at `offset`, before horizontal scrolling.
    func caretX(in text: String, at offset: Int) -> CGFloat {
        CGFloat(font.width(of: text.prefix(offset), size: fontSize))
    }

    /// How far the text is shifted left so that the caret stays visible in
    /// a field `width` points wide.
    func horizontalShift(text: String, caret: Int, width: CGFloat) -> CGFloat {
        max(caretX(in: text, at: caret) + Self.caretWidth - width, 0)
    }

    /// The caret offset nearest to `x`, measured from the field's leading
    /// edge on screen.
    func caretOffset(in text: String, atX x: CGFloat, shift: CGFloat) -> Int {
        let target = x + shift
        var best = 0
        var bestDistance = CGFloat.infinity
        for offset in 0...text.count {
            let distance = abs(caretX(in: text, at: offset) - target)
            if distance < bestDistance {
                best = offset
                bestDistance = distance
            }
        }
        return best
    }
}
