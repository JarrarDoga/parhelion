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

    /// Assumed: the color that dims the screen behind a sheet or an alert.
    static let presentationDim = RGBA(red: 0, green: 0, blue: 0, alpha: 51)

    /// Assumed: the color of the status bar's contents and the home
    /// indicator over the light appearance.
    static let systemBarForeground = RGBA.black

    /// Assumed: the background of an alert.
    static let alertBackground = RGBA(red: 242, green: 242, blue: 242)

    /// Assumed: the opacity of a button's label while it is pressed, as with
    /// SwiftUI's default button style on iOS.
    static let pressedOpacity = 0.25

    private static func rgbaComponents(_ name: String) -> [Double]? {
        guard name.hasPrefix("rgba("), name.hasSuffix(")") else { return nil }
        let values = name.dropFirst(5).dropLast().split(separator: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespaces))
        }
        return values.count == 4 ? values : nil
    }
}
