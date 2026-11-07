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
    /// The lines `text` wraps into at `width` in `font`. A `nil` or infinite
    /// width lays out each paragraph on a single line.
    func lines(of text: String, font: ResolvedFont, width: CGFloat?) -> [TextLine]
}

extension TextMeasurer {
    /// The size of `text` in `font` when it wraps to fit `width`. Each line
    /// is the font's line height tall.
    func size(of text: String, font: ResolvedFont, width: CGFloat?) -> CGSize {
        let lines = lines(of: text, font: font, width: width)
        return CGSize(
            width: lines.map(\.width).max() ?? 0,
            height: CGFloat(lines.count) * font.lineHeight
        )
    }
}

/// Measures text with the advance widths of the bundled Inter weight nearest
/// to each font's weight, wrapping at spaces.
///
/// Words longer than the available width break between characters. Lines
/// break at newline characters. There is no hyphenation, kerning, or
/// shaping, matching how ``Canvas`` draws text. Every character is followed
/// by the font's tracking, as ``Canvas`` draws it.
///
/// The lines of a string are kept for the next time layout asks for the same
/// string, font, and width, which it does for every row of a list in every
/// frame of a scroll. See ``TextLineCache``.
struct FontTextMeasurer: TextMeasurer {
    /// Absorbs rounding differences when text is wrapped again at the width
    /// layout chose for it.
    private let tolerance: CGFloat = 0.001

    func lines(of text: String, font: ResolvedFont, width: CGFloat?) -> [TextLine] {
        guard !text.isEmpty else { return [] }
        let key = TextLineCache.Key(
            text: text, size: font.size, weight: font.weight, width: width)
        if let lines = TextLineCache.shared[key] { return lines }
        let lines = wrapped(text, font: font, width: width)
        TextLineCache.shared[key] = lines
        return lines
    }

    private func wrapped(_ text: String, font: ResolvedFont, width: CGFloat?) -> [TextLine] {
        let maxWidth = width.flatMap { $0.isFinite ? max($0, 0) : nil }
        var lines: [TextLine] = []
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let maxWidth {
                lines += wrap(paragraph, font: font, maxWidth: maxWidth + tolerance)
            } else {
                lines.append(TextLine(text: String(paragraph), width: measure(paragraph, font)))
            }
        }
        return lines
    }

    private func measure(_ text: some StringProtocol, _ font: ResolvedFont) -> CGFloat {
        CGFloat(font.typeface.width(of: text, size: Double(font.size)))
    }

    /// Greedy wrapping: each line takes as many words as fit.
    private func wrap(_ paragraph: Substring, font: ResolvedFont, maxWidth: CGFloat) -> [TextLine] {
        let space = measure(" ", font)
        var lines: [TextLine] = []
        var current = TextLine(text: "", width: 0)
        var lineIsEmpty = true

        for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
            let wordWidth = measure(word, font)
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
                let pieces = breakWord(word, font: font, maxWidth: maxWidth)
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
    private func breakWord(_ word: Substring, font: ResolvedFont, maxWidth: CGFloat) -> [TextLine] {
        var pieces: [TextLine] = []
        var current = TextLine(text: "", width: 0)
        for character in word {
            let characterWidth = measure(String(character), font)
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

/// The lines that ``FontTextMeasurer`` made, by string, size, weight, and
/// width, shared by every measurer.
///
/// A line's width depends on nothing else, so a hit is the same, bit for
/// bit, as wrapping again. The cache holds at most ``limit`` entries and
/// starts over when it is full, which a screen's text rarely fills.
final class TextLineCache: @unchecked Sendable {
    struct Key: Hashable {
        var text: String
        var size: CGFloat
        var weight: Font.Weight
        var width: CGFloat?
    }

    static let shared = TextLineCache()
    static let limit = 16_384

    private let lock = NSLock()
    private var entries: [Key: [TextLine]] = [:]
    /// How many lookups found their lines, for tests.
    private(set) var hits = 0

    subscript(key: Key) -> [TextLine]? {
        get {
            lock.lock()
            defer { lock.unlock() }
            let lines = entries[key]
            if lines != nil { hits += 1 }
            return lines
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            if entries.count >= Self.limit { entries.removeAll(keepingCapacity: true) }
            entries[key] = newValue
        }
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
}
