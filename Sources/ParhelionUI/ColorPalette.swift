import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// The colors Parhelion draws SwiftUI's named colors and styles with.
///
/// Assumed: these are iOS 27's light-appearance system colors, from the
/// swatches of Apple's iOS 27 UI Kit. iOS 26 changed several of them from
/// the values iOS 7 through 18 used, such as blue from 0,122,255. Like the
/// constants in `LayoutDefaults`, they have not been checked against SwiftUI
/// automatically yet.
enum ColorPalette {
    /// The color for a style name recorded by `foregroundStyle` or `Color`,
    /// such as `"blue"`, `"tint"`, `"secondary"`, or `"rgba(1,0.5,0,1)"`.
    static func color(named name: String) -> RGBA {
        // A color with reduced opacity is recorded as "name@opacity".
        if let separator = name.lastIndex(of: "@"),
            let opacity = Double(name[name.index(after: separator)...])
        {
            var color = color(named: String(name[..<separator]))
            color.alpha = UInt8((Double(color.alpha) * opacity).rounded())
            return color
        }
        if let components = rgbaComponents(name) {
            return RGBA(
                fractionalRed: components[0],
                green: components[1],
                blue: components[2],
                opacity: components[3]
            )
        }
        switch name {
        case "red": return RGBA(red: 255, green: 56, blue: 60)
        case "orange": return RGBA(red: 255, green: 141, blue: 40)
        case "yellow": return RGBA(red: 255, green: 204, blue: 0)
        case "green": return RGBA(red: 52, green: 199, blue: 89)
        case "mint": return RGBA(red: 0, green: 200, blue: 179)
        case "teal": return RGBA(red: 0, green: 195, blue: 208)
        case "cyan": return RGBA(red: 0, green: 192, blue: 232)
        case "blue", "tint", "accentColor": return RGBA(red: 0, green: 136, blue: 255)
        case "indigo": return RGBA(red: 97, green: 85, blue: 245)
        case "purple": return RGBA(red: 203, green: 48, blue: 224)
        case "pink": return RGBA(red: 255, green: 45, blue: 85)
        case "brown": return RGBA(red: 172, green: 127, blue: 94)
        case "white": return .white
        case "gray": return RGBA(red: 142, green: 142, blue: 147)
        case "black", "primary": return .black
        case "secondary": return RGBA(red: 60, green: 60, blue: 67, alpha: 153)
        case "tertiary": return RGBA(red: 60, green: 60, blue: 67, alpha: 76)
        case "quaternary": return RGBA(red: 60, green: 60, blue: 67, alpha: 46)
        case "clear": return .clear
        case glassLabelStyle: return glassLabel
        case alertMessageStyle: return alertMessage
        case tertiaryFillStyle: return tertiaryFill
        default: return .black
        }
    }

    /// The background of a window.
    static let background = RGBA.white

    /// Assumed: the background of a grouped list, iOS's
    /// `systemGroupedBackground`.
    static let groupedBackground = RGBA(red: 242, green: 242, blue: 247)

    /// Assumed: the background of a grouped list's rows, iOS's
    /// `secondarySystemGroupedBackground`.
    static let groupedRowBackground = RGBA.white

    /// Assumed: the color of a list's row separators, black at 12% opacity,
    /// the iOS 27 UI Kit's light non-opaque separator.
    static let separator = RGBA(red: 0, green: 0, blue: 0, alpha: 31)

    /// Assumed: the background of a list row while it is pressed, iOS's
    /// `systemGray4`.
    static let rowHighlight = RGBA(red: 209, green: 209, blue: 214)

    /// Assumed: the color that dims the screen behind a sheet, black at 20%
    /// in the iOS 27 UI Kit's sheet overlay.
    static let sheetDim = RGBA(red: 0, green: 0, blue: 0, alpha: 51)

    /// Assumed: the color that dims the screen behind an alert,
    /// rgba(41, 41, 58, 0.23) in the iOS 27 UI Kit. Over white it makes
    /// 205,205,209, as in the alert artwork of the Human Interface
    /// Guidelines.
    static let alertDim = RGBA(red: 41, green: 41, blue: 58, alpha: 59)

    /// Assumed: the color of the status bar's contents and the home
    /// indicator over the light appearance.
    static let systemBarForeground = RGBA.black

    /// Assumed: the color of labels on glass, such as toolbar buttons and
    /// the back button's chevron: the iOS 27 UI Kit's Liquid Glass primary
    /// label, 26,26,26, which an iOS 26 Simulator screenshot shows as
    /// 25,25,25 for the back button's chevron.
    static let glassLabel = RGBA(red: 26, green: 26, blue: 26)

    /// The style name of ``glassLabel``, for the renderer's inherited
    /// foreground style. Views cannot name it.
    static let glassLabelStyle = "system.glassLabel"

    /// Assumed: the color of an alert's message. The iOS 27 UI Kit draws it
    /// in a vibrant secondary gray; in the alert artwork of the Human
    /// Interface Guidelines its darkest pixels are 62,62,63.
    static let alertMessage = RGBA(red: 62, green: 62, blue: 64)

    /// The style name of ``alertMessage``.
    static let alertMessageStyle = "system.alertMessage"

    /// Assumed: the fill of a bordered button, and of an alert's buttons
    /// other than its preferred one: the iOS 27 UI Kit's tertiary fill,
    /// 118,118,128 at 12%.
    static let tertiaryFill = RGBA(red: 118, green: 118, blue: 128, alpha: 31)

    /// The style name of ``tertiaryFill``.
    static let tertiaryFillStyle = "system.tertiaryFill"

    /// Assumed: the color of a sheet's grabber: 207 gray, drawn plus-darker
    /// in the iOS 27 UI Kit, which is 207 gray over the white sheet.
    static let grabber = RGBA(red: 207, green: 207, blue: 207)

    /// Assumed: small glass, for toolbar buttons, the back button, and
    /// `.glass` buttons, from the iOS 27 UI Kit's 44-point toolbar button,
    /// tuned to a 3× iOS 26 Simulator screenshot of a back button over
    /// white:
    ///
    /// - The backdrop is blurred with a radius of 6 and saturation 2.
    /// - The kit's tint stack works out to about 0.45 × backdrop + 132,
    ///   which is 247 over white, but the screenshot shows 253. 252 gray at
    ///   60% gives 253 over white and 248 over the grouped background.
    /// - A bright line 1.5 pixels wide at 3× inside the top edge, fainter
    ///   inside the bottom edge.
    /// - The kit's 0.5-point ring of 219 gray, plus-darker, does not show in
    ///   the screenshot, where the edge is the bright line; Parhelion keeps
    ///   a faint one, 242 gray, so glass stays visible on white.
    /// - The kit's shadow, black 2% 8 points down with a blur of 15, is
    ///   fainter and tighter than the screenshot's, which is 244 just below
    ///   the edge, 250 just above it, and still 252 16 points to the side:
    ///   black 8%, 4 down, blur 24.
    static let smallGlass = GlassMaterial(
        shadow: .init(color: RGBA(red: 0, green: 0, blue: 0, alpha: 20), offset: 4, blur: 24),
        blurRadius: 6,
        saturation: 2,
        tint: [.init(color: RGBA(red: 252, green: 252, blue: 252, alpha: 153), blendMode: .normal)],
        highlightWidth: 0.5,
        highlightTop: 1,
        highlightBottom: 0.47,
        rim: RGBA(red: 242, green: 242, blue: 242),
        rimWidth: 0.5
    )

    /// Assumed: tinted glass, for prominent toolbar buttons and
    /// `.glassProminent` buttons: the tint color fills the shape under the
    /// small glass's shadow and a fainter bright line, without the darker
    /// ring, as in the iOS 27 UI Kit's prominent toolbar button and the
    /// Human Interface Guidelines' sheet artwork.
    static let prominentGlass = GlassMaterial(
        shadow: smallGlass.shadow,
        blurRadius: 0,
        saturation: 1,
        tint: [],
        highlightWidth: 0.5,
        highlightTop: 0.45,
        highlightBottom: 0.25,
        rim: .clear,
        rimWidth: 0
    )

    /// Assumed: large glass, for alerts, from the iOS 27 UI Kit's alert:
    ///
    /// - The backdrop is blurred with a radius of 30 and saturation 1.4.
    /// - White at 70%, lighten, then 191 gray at 10%, darken: about
    ///   0.27 × backdrop + 180, which makes the 235,235,236 of the Human
    ///   Interface Guidelines' alert artwork over its dimmed screen.
    /// - A 1.5-point white line inside the top and bottom edges, and a
    ///   darker ring outside, as in the same artwork.
    /// - A shadow of black 25%, 18 points down, with a blur of 46.
    static let largeGlass = GlassMaterial(
        shadow: .init(color: RGBA(red: 0, green: 0, blue: 0, alpha: 64), offset: 18, blur: 46),
        blurRadius: 30,
        saturation: 1.4,
        tint: [
            .init(color: RGBA(red: 255, green: 255, blue: 255, alpha: 179), blendMode: .lighten),
            .init(color: RGBA(red: 191, green: 191, blue: 191, alpha: 26), blendMode: .darken),
        ],
        highlightWidth: 1.5,
        highlightTop: 1,
        highlightBottom: 1,
        rim: RGBA(red: 200, green: 200, blue: 200),
        rimWidth: 0.5
    )

    /// Assumed: the glass of a sheet at a partial-height detent: large glass
    /// with a blur radius of 15, in the iOS 27 UI Kit's medium-detent sheet,
    /// and the sheet's shadow.
    static let partialSheetGlass: GlassMaterial = {
        var material = largeGlass
        material.blurRadius = 15
        material.shadow = sheetShadow
        return material
    }()

    /// Assumed: the shadow of a sheet, black 18%, 15 points down, with a
    /// blur of 50, in the iOS 27 UI Kit.
    static let sheetShadow = GlassMaterial.Shadow(
        color: RGBA(red: 0, green: 0, blue: 0, alpha: 46), offset: 15, blur: 50)

    /// Assumed: the opacity of a button's label while it is pressed, as with
    /// SwiftUI's default button style on iOS.
    static let pressedOpacity = 0.25

    /// The highlight behind the selected tab in the tab bar: 120,120,128 at
    /// 16%, a full capsule, in the iOS 27 UI Kit.
    static let tabBarSelection = RGBA(red: 120, green: 120, blue: 128, alpha: 41)

    private static func rgbaComponents(_ name: String) -> [Double]? {
        guard name.hasPrefix("rgba("), name.hasSuffix(")") else { return nil }
        let values = name.dropFirst(5).dropLast().split(separator: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespaces))
        }
        return values.count == 4 ? values : nil
    }
}

// MARK: - Controls

extension ColorPalette {
    /// Assumed: the opacity of a control turned off with `disabled(_:)`, 50%
    /// in the iOS 27 UI Kit's disabled switches, sliders, and segmented
    /// controls.
    static let disabledOpacity = 0.5

    /// Assumed: the track of a switch that is off, 60,60,67 at 30% in the iOS
    /// 27 UI Kit.
    static let switchOffTrack = RGBA(red: 60, green: 60, blue: 67, alpha: 77)

    /// Assumed: the track of a switch that is on when no tint is set: the
    /// system green, as in the iOS 27 UI Kit.
    static let switchOnTrackStyle = "green"

    /// Assumed: the knob of a switch or a slider, white in the iOS 27 UI Kit.
    static let knob = RGBA.white
}
