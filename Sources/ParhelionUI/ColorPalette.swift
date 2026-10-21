import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// The colors Parhelion draws SwiftUI's named colors and styles with.
///
/// Assumed: these are iOS's light-appearance system colors, from the Human
/// Interface Guidelines. Like the constants in `LayoutDefaults`, they have
/// not been checked against SwiftUI automatically yet.
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
        case "red": return RGBA(red: 255, green: 59, blue: 48)
        case "orange": return RGBA(red: 255, green: 149, blue: 0)
        case "yellow": return RGBA(red: 255, green: 204, blue: 0)
        case "green": return RGBA(red: 52, green: 199, blue: 89)
        case "mint": return RGBA(red: 0, green: 199, blue: 190)
        case "teal": return RGBA(red: 48, green: 176, blue: 199)
        case "cyan": return RGBA(red: 50, green: 173, blue: 230)
        case "blue", "tint", "accentColor": return RGBA(red: 0, green: 122, blue: 255)
        case "indigo": return RGBA(red: 88, green: 86, blue: 214)
        case "purple": return RGBA(red: 175, green: 82, blue: 222)
        case "pink": return RGBA(red: 255, green: 45, blue: 85)
        case "brown": return RGBA(red: 162, green: 132, blue: 94)
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
