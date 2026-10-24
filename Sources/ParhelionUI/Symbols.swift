import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// Where the outline of a symbol image comes from.
enum SymbolSource: String, Sendable {
    /// Parhelion's own drawing: the chevrons of back buttons.
    case builtIn
    /// Phosphor Icons, for the SF Symbol names in `Symbols/symbols.txt`.
    case phosphor
    /// A ring, for a name that no source has.
    case placeholder
}

/// The outline of a symbol image in a square of side 1, which the renderer
/// scales to the symbol's frame, and where it came from.
struct ResolvedSymbol: Sendable {
    var path: Path
    var source: SymbolSource
}

/// Finds the outline that each `Image(systemName:)` draws.
///
/// Apple's license does not allow shipping SF Symbols outside Apple
/// platforms, so Parhelion draws the common SF Symbol names with Phosphor
/// Icons, in its regular weight, or its fill weight for a name that ends in
/// `.fill`. A name Parhelion cannot draw is a ring, and the image's node
/// records `missingSymbol=true`.
///
/// Every lookup goes through ``resolve(_:weight:scale:fill:)``, so another
/// source can go in front of Phosphor later without changes to `Image` or
/// the renderer.
enum SymbolLibrary {
    /// The symbols drawn as chevrons, the way the back button's is.
    static let chevrons: Set<String> = [
        "chevron.backward", "chevron.left", "chevron.forward", "chevron.right",
    ]

    /// Where the outline of a name comes from, without building it.
    static func source(of name: String) -> SymbolSource {
        if chevrons.contains(name) { return .builtIn }
        return phosphorIcon(for: name) == nil ? .placeholder : .phosphor
    }

    /// The outline of a symbol.
    ///
    /// - Parameters:
    ///   - weight: The weight of the font around the symbol. Phosphor's
    ///     regular weight draws every weight.
    ///   - scale: The image scale. The symbol's frame already has the
    ///     scale's size, so the outline does not change with it.
    ///   - fill: Whether to prefer the fill weight, as the tab bar does,
    ///     even for a name without a `.fill` suffix.
    static func resolve(
        _ name: String, weight: Font.Weight = .regular, scale: Image.Scale = .medium,
        fill: Bool = false
    ) -> ResolvedSymbol {
        if chevrons.contains(name) {
            return ResolvedSymbol(
                path: chevron(pointingLeft: name.hasSuffix("backward") || name.hasSuffix("left")),
                source: .builtIn)
        }
        if let icon = phosphorIcon(for: name),
            let path = cache.path(icon.name, fill: icon.fill || fill)
        {
            return ResolvedSymbol(path: path, source: .phosphor)
        }
        return ResolvedSymbol(path: placeholder, source: .placeholder)
    }

    /// The Phosphor icon for a name, and whether the name asks for the fill
    /// weight.
    private static func phosphorIcon(for name: String) -> (name: String, fill: Bool)? {
        if let icon = phosphorIconNames[name] { return (icon, false) }
        guard name.hasSuffix(".fill"), let icon = phosphorIconNames[String(name.dropLast(5))]
        else { return nil }
        return (icon, true)
    }

    /// A chevron in the proportions of the back button's, a 17-point symbol,
    /// which is a little taller than the symbol's side.
    private static func chevron(pointingLeft: Bool) -> Path {
        let symbol = LayoutDefaults.bodyFontSize
        let size = LayoutDefaults.backChevronSize
        let width = size.width / symbol
        let height = size.height / symbol
        return TreeRenderer.chevron(
            in: CGRect(x: 0.5 - width / 2, y: 0.5 - height / 2, width: width, height: height),
            pointingLeft: pointingLeft, thickness: LayoutDefaults.backChevronThickness / symbol)
    }

    /// A ring that fills the square.
    private static let placeholder: Path = {
        let stroke: CGFloat = 0.09
        let outer = CGRect(x: stroke / 2, y: stroke / 2, width: 1 - stroke, height: 1 - stroke)
        var ring = Path(ellipseIn: outer)
        ring.addPath(Path(ellipseIn: outer.insetBy(dx: stroke, dy: stroke), reversed: true))
        return ring
    }()

    private static let cache = PhosphorCache()
}

/// Phosphor outlines parsed from their SVG path data on first use, in the
/// symbol's unit square.
private final class PhosphorCache: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String: Path] = [:]

    func path(_ icon: String, fill: Bool) -> Path? {
        let key = fill ? icon + "-fill" : icon
        lock.lock()
        defer { lock.unlock() }
        if let path = paths[key] { return path }
        guard let data = phosphorIconPaths[icon],
            let path = Path(svgPathData: fill ? data.fill : data.regular)
        else { return nil }
        // Assumed: Phosphor's 256-unit grid spans 4/3 of the symbol's side,
        // centered, so a typical icon's 192 units of ink (the house spans 32
        // to 224) are as wide as the side. SF Pro's 18-point tab symbols in
        // the iOS 27 UI Kit are 17.9 to 19.9 points wide.
        let grid = 256.0
        let unit = 1 / (grid * 3 / 4)
        let scaled = path.applying(
            scaleX: unit, scaleY: unit, translateX: 0.5 - grid / 2 * unit,
            translateY: 0.5 - grid / 2 * unit)
        paths[key] = scaled
        return scaled
    }
}

// MARK: - Images

struct ImageScaleKey: EnvironmentKey {
    static var defaultValue: Image.Scale { .medium }
}

extension EnvironmentValues {
    /// The relative size of symbol images in the view, set by
    /// ``View/imageScale(_:)``.
    public var imageScale: Image.Scale {
        get { self[ImageScaleKey.self] }
        set { self[ImageScaleKey.self] = newValue }
    }
}

extension Image {
    /// The attributes of a symbol image's node: its name, the font and scale
    /// that size it when they are not the defaults, and `missingSymbol` when
    /// Parhelion has no outline for the name.
    func symbolAttributes(_ name: String, in environment: EnvironmentValues) -> [String: String] {
        var attributes = ["systemName": name]
        // A symbol takes the size of the font around it, and scales with
        // Dynamic Type as its font does. Phosphor has one weight for every
        // font weight, so only the font's size is recorded.
        let font = (environment.font ?? .body).resolved(
            dynamicTypeSize: environment.dynamicTypeSize)
        if font.name != ResolvedFont.body.name { attributes["font"] = font.name }
        if let size = font.sizeAttribute { attributes["fontSize"] = size }
        if environment.imageScale != .medium {
            attributes["imageScale"] = environment.imageScale.rawValue
        }
        if SymbolLibrary.source(of: name) == .placeholder { attributes["missingSymbol"] = "true" }
        return attributes
    }

    /// The side of a symbol image's square frame: the size of its font,
    /// scaled for its image scale.
    nonisolated static func symbolSide(of node: ViewNode) -> CGFloat {
        let font = ResolvedFont(node: node)
        let scale = node.attributes["imageScale"].flatMap(Image.Scale.init) ?? .medium
        return LayoutDefaults.symbolSide(for: scale) * font.size / LayoutDefaults.bodyFontSize
    }
}

extension TreeRenderer {
    /// Draws a symbol image's outline, scaled to the square that fits its
    /// frame, centered.
    func drawSymbol(_ node: ViewNode, in frame: CGRect, color: RGBA, into canvas: inout Canvas) {
        guard let name = node.attributes["systemName"] else { return }
        let side = min(frame.width, frame.height)
        let scale = node.attributes["imageScale"].flatMap(Image.Scale.init) ?? .medium
        let symbol = SymbolLibrary.resolve(
            name, scale: scale, fill: node.attributes["symbolVariant"] == "fill")
        canvas.fill(
            symbol.path.applying(
                scaleX: Double(side), scaleY: Double(side),
                translateX: Double(frame.midX - side / 2),
                translateY: Double(frame.midY - side / 2)),
            color: color)
    }
}
