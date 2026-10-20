import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// One line of wrapped text.
struct TextLine: Equatable {
    var text: String
    var width: CGFloat
}

/// Measures and wraps text for layout and drawing.
protocol TextMeasurer: Sendable {
    /// The lines `text` wraps into at `width`. A `nil` or infinite width lays
    /// out each paragraph on a single line.
    func lines(of text: String, fontSize: CGFloat, width: CGFloat?) -> [TextLine]

    /// The distance between baselines at the given font size.
    func lineHeight(fontSize: CGFloat) -> CGFloat
}

extension TextMeasurer {
    /// The size of `text` when it wraps to fit `width`.
    func size(of text: String, fontSize: CGFloat, width: CGFloat?) -> CGSize {
        let lines = lines(of: text, fontSize: fontSize, width: width)
        return CGSize(
            width: lines.map(\.width).max() ?? 0,
            height: CGFloat(lines.count) * lineHeight(fontSize: fontSize)
        )
    }
}

/// Measures text with the advance widths of a font, wrapping at spaces.
///
/// Words longer than the available width break between characters. Lines
/// break at newline characters. There is no hyphenation, kerning, or
/// shaping, matching how ``Canvas`` draws text.
struct FontTextMeasurer: TextMeasurer {
    let font: TrueTypeFont

    /// Absorbs rounding differences when text is wrapped again at the width
    /// layout chose for it.
    private let tolerance: CGFloat = 0.001

    func lineHeight(fontSize: CGFloat) -> CGFloat {
        CGFloat(font.lineHeight(size: Double(fontSize)))
    }

    func lines(of text: String, fontSize: CGFloat, width: CGFloat?) -> [TextLine] {
        guard !text.isEmpty else { return [] }
        let maxWidth = width.flatMap { $0.isFinite ? max($0, 0) : nil }
        var lines: [TextLine] = []
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let maxWidth {
                lines += wrap(paragraph, fontSize: fontSize, maxWidth: maxWidth + tolerance)
            } else {
                lines.append(TextLine(text: String(paragraph), width: measure(paragraph, fontSize)))
            }
        }
        return lines
    }

    private func measure(_ text: some StringProtocol, _ fontSize: CGFloat) -> CGFloat {
        CGFloat(font.width(of: text, size: Double(fontSize)))
    }

    /// Greedy wrapping: each line takes as many words as fit.
    private func wrap(_ paragraph: Substring, fontSize: CGFloat, maxWidth: CGFloat) -> [TextLine] {
        let space = measure(" ", fontSize)
        var lines: [TextLine] = []
        var current = TextLine(text: "", width: 0)
        var lineIsEmpty = true

        for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
            let wordWidth = measure(word, fontSize)
            if !lineIsEmpty, current.width + space + wordWidth <= maxWidth {
                current.text += " " + word
                current.width += space + wordWidth
                continue
            }
            if !lineIsEmpty {
                lines.append(current)
            }
            if wordWidth <= maxWidth {
                current = TextLine(text: String(word), width: wordWidth)
            } else {
                let pieces = breakWord(word, fontSize: fontSize, maxWidth: maxWidth)
                lines += pieces.dropLast()
                current = pieces.last ?? TextLine(text: "", width: 0)
            }
            lineIsEmpty = false
        }
        lines.append(current)
        return lines
    }

    /// The pieces a word breaks into when it is wider than a line. Each piece
    /// holds at least one character.
    private func breakWord(_ word: Substring, fontSize: CGFloat, maxWidth: CGFloat) -> [TextLine] {
        var pieces: [TextLine] = []
        var current = TextLine(text: "", width: 0)
        for character in word {
            let characterWidth = measure(String(character), fontSize)
            if !current.text.isEmpty, current.width + characterWidth > maxWidth {
                pieces.append(current)
                current = TextLine(text: "", width: 0)
            }
            current.text.append(character)
            current.width += characterWidth
        }
        pieces.append(current)
        return pieces
    }
}
