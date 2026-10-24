import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// A font for text, mirroring SwiftUI's `Font`.
///
/// A font is one of the platform's text styles, such as ``body`` or
/// ``headline``, the system font at a fixed size, or a custom font by name,
/// optionally with a weight. Text styles and custom fonts scale with the
/// environment's Dynamic Type size; the system font at a fixed size does
/// not, as in SwiftUI. Parhelion draws every font with the bundled Inter
/// typeface in place of San Francisco or the named font, at the nearest of
/// the weights it bundles: regular, medium, semibold, and bold. Set a font
/// for a view and its content with ``View/font(_:)``.
public struct Font: Hashable, Sendable {
    /// A text style, which sets a size, line height, and weight.
    public enum TextStyle: String, CaseIterable, Hashable, Sendable {
        case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote
        case caption, caption2
    }

    /// A font weight, mirroring SwiftUI's `Font.Weight`.
    public struct Weight: Hashable, Sendable {
        /// The weight on the scale of CSS and OpenType, where regular is 400
        /// and bold is 700.
        let value: Int

        public static let ultraLight = Weight(value: 100)
        public static let thin = Weight(value: 200)
        public static let light = Weight(value: 300)
        public static let regular = Weight(value: 400)
        public static let medium = Weight(value: 500)
        public static let semibold = Weight(value: 600)
        public static let bold = Weight(value: 700)
        public static let heavy = Weight(value: 800)
        public static let black = Weight(value: 900)

        /// The weight's name, as SwiftUI spells it.
        var name: String {
            switch value {
            case ...100: "ultraLight"
            case ...200: "thin"
            case ...300: "light"
            case ...400: "regular"
            case ...500: "medium"
            case ...600: "semibold"
            case ...700: "bold"
            case ...800: "heavy"
            default: "black"
            }
        }
    }

    /// A design of the system font, mirroring SwiftUI's `Font.Design`.
    /// Parhelion draws every design with Inter.
    public enum Design: Hashable, Sendable {
        case `default`, serif, rounded, monospaced
    }

    enum Base: Hashable, Sendable {
        case textStyle(TextStyle)
        /// The system font at a size, scaled in proportion to a text style
        /// when one is given. Only Parhelion's own fonts, such as a list
        /// footer's, give one.
        case system(size: CGFloat, relativeTo: TextStyle?)
        /// A font by name, scaled in proportion to a text style unless it
        /// has a fixed size.
        case custom(name: String, size: CGFloat, relativeTo: TextStyle?)
    }

    let base: Base
    /// A weight that replaces the base's own weight.
    let weightOverride: Weight?

    init(base: Base, weight: Weight? = nil) {
        self.base = base
        weightOverride = weight
    }

    public static let largeTitle = Font(base: .textStyle(.largeTitle))
    public static let title = Font(base: .textStyle(.title))
    public static let title2 = Font(base: .textStyle(.title2))
    public static let title3 = Font(base: .textStyle(.title3))
    public static let headline = Font(base: .textStyle(.headline))
    public static let subheadline = Font(base: .textStyle(.subheadline))
    public static let body = Font(base: .textStyle(.body))
    public static let callout = Font(base: .textStyle(.callout))
    public static let footnote = Font(base: .textStyle(.footnote))
    public static let caption = Font(base: .textStyle(.caption))
    public static let caption2 = Font(base: .textStyle(.caption2))

    /// The system font at a fixed size, which does not scale with Dynamic
    /// Type.
    public static func system(
        size: CGFloat, weight: Weight? = nil, design: Design? = nil
    ) -> Font {
        Font(base: .system(size: size, relativeTo: nil), weight: weight)
    }

    /// The system font for a text style.
    public static func system(
        _ style: TextStyle, design: Design? = nil, weight: Weight? = nil
    ) -> Font {
        Font(base: .textStyle(style), weight: weight)
    }

    /// A custom font by name, which scales with the body text style.
    /// Parhelion draws it with Inter.
    public static func custom(_ name: String, size: CGFloat) -> Font {
        Font(base: .custom(name: name, size: size, relativeTo: .body))
    }

    /// A custom font by name, which scales with the given text style.
    /// Parhelion draws it with Inter.
    public static func custom(
        _ name: String, size: CGFloat, relativeTo textStyle: TextStyle
    )
        -> Font
    {
        Font(base: .custom(name: name, size: size, relativeTo: textStyle))
    }

    /// A custom font by name at a fixed size, which does not scale with
    /// Dynamic Type. Parhelion draws it with Inter.
    public static func custom(_ name: String, fixedSize: CGFloat) -> Font {
        Font(base: .custom(name: name, size: fixedSize, relativeTo: nil))
    }

    /// The same font with the given weight.
    public func weight(_ weight: Weight) -> Font {
        Font(base: base, weight: weight)
    }

    /// The same font in bold.
    public func bold() -> Font {
        weight(.bold)
    }

    /// The size, line height, and weight the font resolves to at a Dynamic
    /// Type size, with `weight`, when it is not `nil`, replacing the font's
    /// own weight.
    func resolved(
        weight: Weight? = nil, dynamicTypeSize: DynamicTypeSize = .large
    )
        -> ResolvedFont
    {
        let weight = weight ?? weightOverride
        switch base {
        case .textStyle(let style):
            let weightAtLarge = LayoutDefaults.textStyleMetrics(style).weight
            let entry = DynamicTypeTable.entry(style, dynamicTypeSize)
            return ResolvedFont(
                name: style.rawValue,
                size: entry.size,
                lineHeight: entry.lineHeight,
                weight: weight ?? weightAtLarge,
                defaultWeight: weightAtLarge,
                defaultSize: LayoutDefaults.textStyleMetrics(style).size
            )
        case .system(let size, let style):
            return ResolvedFont(
                fixedFontNamed: "system(\(formatPoints(size)))", size: size,
                scaled: style.map {
                    DynamicTypeTable.scale(size, relativeTo: $0, at: dynamicTypeSize)
                }, weight: weight)
        case .custom(let name, let size, let style):
            return ResolvedFont(
                fixedFontNamed: "custom(\(name),\(formatPoints(size)))", size: size,
                scaled: style.map {
                    DynamicTypeTable.scale(size, relativeTo: $0, at: dynamicTypeSize)
                }, weight: weight)
        }
    }
}

/// A font after Parhelion has resolved it: the size, line height, and
/// weight that layout measures and the renderer draws with.
struct ResolvedFont: Hashable, Sendable {
    /// The text style's name, such as `"headline"`, or `"system(13)"`.
    var name: String
    var size: CGFloat
    /// The distance between baselines.
    var lineHeight: CGFloat
    var weight: Font.Weight
    /// The weight of the text style or system font before any override.
    var defaultWeight: Font.Weight
    /// The size at the default Dynamic Type size, Large. A text style or a
    /// custom font that scales is a different size at other sizes.
    var defaultSize: CGFloat

    /// The font of text that sets none: the body style.
    static let body = Font.body.resolved()

    /// The font as an attribute value: its name, followed by its weight when
    /// that differs from the style's own, as in `"largeTitle.bold"`.
    var attribute: String {
        weight == defaultWeight ? name : "\(name).\(weight.name)"
    }

    /// The size as an attribute value, when Dynamic Type makes it differ
    /// from the size at Large, as in `"23"` for `body` at xxxLarge.
    var sizeAttribute: String? {
        abs(size - defaultSize) < 0.005 ? nil : formatPoints(size)
    }

    /// Records the font in a node's attributes: `font` unless it is the body
    /// style's name and weight, and `fontSize` when Dynamic Type scaled it.
    func record(in attributes: inout [String: String]) {
        if attribute != ResolvedFont.body.attribute { attributes["font"] = attribute }
        if let sizeAttribute { attributes["fontSize"] = sizeAttribute }
    }

    /// The font a node's `font` and `fontSize` attributes describe.
    init(node: ViewNode) {
        self.init(attribute: node.attributes["font"], fontSize: node.attributes["fontSize"])
    }

    /// The font that attribute values written by ``attribute`` and
    /// ``sizeAttribute`` name, or the body font if the name is missing or
    /// unknown.
    init(attribute: String?, fontSize: String? = nil) {
        let size = fontSize.flatMap(Double.init).map { CGFloat($0) }
        guard let attribute else {
            self = .body
            if let size { scale(to: size, style: .body) }
            return
        }
        var name = Substring(attribute)
        var weight: Font.Weight?
        if let dot = attribute.lastIndex(of: "."),
            let match = Self.weights.first(where: {
                $0.name == attribute[attribute.index(after: dot)...]
            })
        {
            name = attribute[..<dot]
            weight = match
        }
        if let style = Font.TextStyle(rawValue: String(name)) {
            self = Font.system(style).resolved(weight: weight)
            if let size { scale(to: size, style: style) }
        } else if name.hasSuffix(")"),
            let open = name.firstIndex(of: "("),
            ["system", "custom"].contains(name[..<open]),
            let points = name[name.index(after: open)..<name.index(before: name.endIndex)]
                .split(separator: ",").last.flatMap({ Double($0) })
        {
            self = ResolvedFont(
                fixedFontNamed: String(name), size: CGFloat(points), scaled: size, weight: weight)
        } else {
            self = .body
        }
    }

    init(
        name: String, size: CGFloat, lineHeight: CGFloat, weight: Font.Weight,
        defaultWeight: Font.Weight, defaultSize: CGFloat
    ) {
        self.name = name
        self.size = size
        self.lineHeight = lineHeight
        self.weight = weight
        self.defaultWeight = defaultWeight
        self.defaultSize = defaultSize
    }

    /// The system font or a custom font, at `scaled` when Dynamic Type
    /// scaled it. Its line height is San Francisco's own for the size it is
    /// drawn at.
    fileprivate init(
        fixedFontNamed name: String, size: CGFloat, scaled: CGFloat?, weight: Font.Weight?
    ) {
        let drawn = scaled ?? size
        self.init(
            name: name, size: drawn, lineHeight: LayoutDefaults.systemLineHeight(size: drawn),
            weight: weight ?? .regular, defaultWeight: .regular, defaultSize: size)
    }

    /// Moves a text style to a size from the Dynamic Type table, with the
    /// line height the table gives that size.
    private mutating func scale(to size: CGFloat, style: Font.TextStyle) {
        self.size = size
        lineHeight = DynamicTypeTable.lineHeight(style, size: size)
    }

    private static let weights: [Font.Weight] = [
        .ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black,
    ]

    /// The distance from the top of a line to its baseline. The difference
    /// between the line height and the typeface's own height is split evenly
    /// above and below the glyphs, so a line height smaller than the
    /// typeface's moves the baseline up.
    var baseline: CGFloat {
        let typeface = typeface
        let unitsToPoints = size / CGFloat(typeface.unitsPerEm)
        let ascent = CGFloat(typeface.ascender) * unitsToPoints
        let natural = CGFloat(typeface.lineHeight(size: Double(size)))
        return (lineHeight - natural) / 2 + ascent
    }

    /// The bundled Inter weight nearest to this font's weight.
    var typeface: TrueTypeFont {
        switch weight.value {
        case ..<450: .interRegular
        case ..<550: .interMedium
        case ..<650: .interSemiBold
        default: .interBold
        }
    }
}

// MARK: - Environment

struct FontKey: EnvironmentKey {
    static var defaultValue: Font? { nil }
}

struct FontWeightKey: EnvironmentKey {
    static var defaultValue: Font.Weight? { nil }
}

extension EnvironmentValues {
    /// The default font of text in the view, or `nil` for the body style.
    public var font: Font? {
        get { self[FontKey.self] }
        set { self[FontKey.self] = newValue }
    }

    /// A weight that replaces the weight of the font of text in the view, set
    /// by ``View/fontWeight(_:)`` and ``View/bold(_:)``.
    var fontWeight: Font.Weight? {
        get { self[FontWeightKey.self] }
        set { self[FontWeightKey.self] = newValue }
    }
}

extension View {
    /// Sets the default font of text in this view and its content.
    public func font(_ font: Font?) -> some View {
        environment(\.font, font)
    }

    /// Sets the weight of text in this view and its content. A `nil` weight
    /// keeps each font's own weight.
    public func fontWeight(_ weight: Font.Weight?) -> some View {
        environment(\.fontWeight, weight)
    }

    /// Makes text in this view and its content bold.
    public func bold(_ isActive: Bool = true) -> some View {
        EnvironmentWriter(content: self) { if isActive { $0.fontWeight = .bold } }
    }
}

extension Text {
    /// The text in the given font, which overrides the environment's font.
    public func font(_ font: Font?) -> Text {
        var text = self
        text.font = font
        return text
    }

    /// The text in the given weight.
    public func fontWeight(_ weight: Font.Weight?) -> Text {
        var text = self
        text.weight = weight
        return text
    }

    /// The text in bold.
    public func bold(_ isActive: Bool = true) -> Text {
        isActive ? fontWeight(.bold) : self
    }

    /// The font this text resolves to in an environment: its own font and
    /// weight first, then the environment's, then the body style, at the
    /// environment's Dynamic Type size.
    func resolvedFont(in environment: EnvironmentValues) -> ResolvedFont {
        (font ?? environment.font ?? .body).resolved(
            weight: weight ?? environment.fontWeight,
            dynamicTypeSize: environment.dynamicTypeSize)
    }
}
