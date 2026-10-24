#if canImport(Foundation)
import Foundation
#endif

/// The size and line height of every text style at every Dynamic Type size.
///
/// From the Dynamic Type table of Apple's iOS 27 UI Kit (Text Styles and
/// Dynamic Type page, the annotation layers `Dynamic Type Table/Labels + BG`
/// for xSmall through xxxLarge and `Dynamic Type Table - Accessibility
/// Sizes/Labels + BG` for the five accessibility sizes), which match the
/// "iOS, iPadOS Dynamic Type sizes" and "larger accessibility type sizes"
/// tables of the Human Interface Guidelines in every cell
/// (https://developer.apple.com/design/human-interface-guidelines/typography).
/// The kit's sample text layers in the same table disagree in seven cells;
/// those are copy slips, and the annotations are used instead.
///
/// A style's weight is the same at every size: `headline` is semibold and
/// every other style regular. The kit's text styles set no tracking, and
/// Parhelion draws Inter without any.
enum DynamicTypeTable {
    /// A size and the distance between baselines, in points.
    struct Entry: Equatable {
        var size: CGFloat
        var lineHeight: CGFloat
    }

    /// The entries of a style, one for each `DynamicTypeSize` in order, from
    /// `xSmall` to `accessibility5`.
    static func entries(_ style: Font.TextStyle) -> [Entry] {
        switch style {
        case .largeTitle:
            table(
                [31, 38], [32, 39], [33, 40], [34, 41], [36, 43], [38, 46], [40, 48],
                [44, 52], [48, 57], [52, 61], [56, 66], [60, 70])
        case .title:
            table(
                [25, 31], [26, 32], [27, 33], [28, 34], [30, 37], [32, 39], [34, 41],
                [38, 46], [43, 51], [48, 57], [53, 62], [58, 68])
        case .title2:
            table(
                [19, 24], [20, 25], [21, 26], [22, 28], [24, 30], [26, 32], [28, 34],
                [34, 41], [39, 47], [44, 52], [50, 59], [56, 66])
        case .title3:
            table(
                [17, 22], [18, 23], [19, 24], [20, 25], [22, 28], [24, 30], [26, 32],
                [31, 38], [37, 44], [43, 51], [49, 58], [55, 65])
        case .headline, .body:
            table(
                [14, 19], [15, 20], [16, 21], [17, 22], [19, 24], [21, 26], [23, 29],
                [28, 34], [33, 40], [40, 48], [47, 56], [53, 62])
        case .callout:
            table(
                [13, 18], [14, 19], [15, 20], [16, 21], [18, 23], [20, 25], [22, 28],
                [26, 32], [32, 39], [38, 46], [44, 52], [51, 60])
        case .subheadline:
            table(
                [12, 16], [13, 18], [14, 19], [15, 20], [17, 22], [19, 24], [21, 28],
                [25, 31], [30, 37], [36, 43], [42, 50], [49, 58])
        case .footnote:
            table(
                [12, 16], [12, 16], [12, 16], [13, 18], [15, 20], [17, 22], [19, 24],
                [23, 29], [27, 33], [33, 40], [38, 46], [44, 52])
        case .caption:
            table(
                [11, 13], [11, 13], [11, 13], [12, 16], [14, 19], [16, 21], [18, 23],
                [22, 28], [26, 32], [32, 39], [37, 44], [43, 51])
        case .caption2:
            table(
                [11, 13], [11, 13], [11, 13], [11, 13], [13, 18], [15, 20], [17, 22],
                [20, 25], [24, 30], [29, 35], [34, 41], [40, 48])
        }
    }

    /// The size and line height of a style at a Dynamic Type size.
    static func entry(_ style: Font.TextStyle, _ size: DynamicTypeSize) -> Entry {
        entries(style)[DynamicTypeSize.allCases.firstIndex(of: size)!]
    }

    /// The line height of a style drawn at a point size. Within a style,
    /// every Dynamic Type size with the same point size has the same line
    /// height, so the size alone finds it. A size the table does not list
    /// keeps the style's proportion at the default size.
    static func lineHeight(_ style: Font.TextStyle, size: CGFloat) -> CGFloat {
        let entries = entries(style)
        if let match = entries.first(where: { abs($0.size - size) < 0.005 }) {
            return match.lineHeight
        }
        let large = entry(style, .large)
        return (large.lineHeight * size / large.size).rounded()
    }

    /// Scales a value from the default Dynamic Type size, Large, to another
    /// size, in proportion to a text style's point size, as `@ScaledMetric`
    /// and `Font.custom(_:size:relativeTo:)` do.
    ///
    /// Assumed: Apple documents no formula for `UIFontMetrics` or
    /// `ScaledMetric`; scaling with the style's own sizes keeps a value in
    /// step with text of that style.
    static func scale(
        _ value: CGFloat, relativeTo style: Font.TextStyle, at size: DynamicTypeSize
    ) -> CGFloat {
        guard size != .large else { return value }
        return value * entry(style, size).size / entry(style, .large).size
    }

    private static func table(_ pairs: [CGFloat]...) -> [Entry] {
        pairs.map { Entry(size: $0[0], lineHeight: $0[1]) }
    }
}
