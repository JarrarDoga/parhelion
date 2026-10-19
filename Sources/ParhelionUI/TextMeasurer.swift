#if canImport(Foundation)
import Foundation
#endif

/// Measures and wraps text for layout.
protocol TextMeasurer: Sendable {
    /// The size of `text` when it wraps to fit `width`. A `nil` or infinite
    /// width lays out each paragraph on a single line.
    func size(of text: String, fontSize: CGFloat, width: CGFloat?) -> CGSize
}

/// Measures text with the advance widths of a font, wrapping at spaces.
///
/// Words longer than the available width break between characters. Lines
/// break at newline characters. There is no hyphenation, kerning, or
/// shaping.
struct FontTextMeasurer: TextMeasurer {
    let metrics: FontMetrics

    func size(of text: String, fontSize: CGFloat, width: CGFloat?) -> CGSize {
        guard !text.isEmpty else { return .zero }
        let maxWidth = width.flatMap { $0.isFinite ? max($0, 0) : nil }
        var lineWidths: [CGFloat] = []
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let maxWidth {
                lineWidths += wrap(paragraph, fontSize: fontSize, maxWidth: maxWidth)
            } else {
                lineWidths.append(metrics.width(of: paragraph, size: fontSize))
            }
        }
        return CGSize(
            width: lineWidths.max() ?? 0,
            height: CGFloat(lineWidths.count) * metrics.lineHeight(size: fontSize)
        )
    }

    /// The widths of the lines `paragraph` wraps into.
    private func wrap(_ paragraph: Substring, fontSize: CGFloat, maxWidth: CGFloat) -> [CGFloat] {
        let space = metrics.width(of: " ", size: fontSize)
        var lines: [CGFloat] = []
        var current: CGFloat = 0
        var lineIsEmpty = true

        for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
            let wordWidth = metrics.width(of: word, size: fontSize)
            if !lineIsEmpty, current + space + wordWidth <= maxWidth {
                current += space + wordWidth
                continue
            }
            if !lineIsEmpty {
                lines.append(current)
            }
            if wordWidth <= maxWidth {
                current = wordWidth
            } else {
                let pieces = breakWord(word, fontSize: fontSize, maxWidth: maxWidth)
                lines += pieces.dropLast()
                current = pieces.last ?? 0
            }
            lineIsEmpty = false
        }
        lines.append(current)
        return lines
    }

    /// The widths of the pieces a word breaks into when it is wider than a
    /// line. Each piece holds at least one character.
    private func breakWord(_ word: Substring, fontSize: CGFloat, maxWidth: CGFloat) -> [CGFloat] {
        var pieces: [CGFloat] = []
        var current: CGFloat = 0
        for character in word {
            let characterWidth = metrics.width(of: Substring(String(character)), size: fontSize)
            if current > 0, current + characterWidth > maxWidth {
                pieces.append(current)
                current = 0
            }
            current += characterWidth
        }
        pieces.append(current)
        return pieces
    }
}
