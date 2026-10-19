#if canImport(Foundation)
import Foundation
#endif

/// Every value in which Parhelion's layout assumes how SwiftUI behaves.
///
/// These numbers come from Apple's documentation, the Human Interface
/// Guidelines, and observation. None of them has been checked automatically
/// against SwiftUI yet. They are collected here so that the planned macOS
/// fidelity job can verify each one; see docs/roadmap.md.
enum LayoutDefaults {
    /// Assumed: the length `padding()` uses when no length is given, on iOS.
    static let padding: CGFloat = 16

    /// Assumed: the spacing between adjacent children of a stack when
    /// `spacing` is `nil`. SwiftUI varies this by the kinds of the two
    /// children; Parhelion uses one value for every pair.
    static let stackSpacing: CGFloat = 8

    /// Assumed: the minimum length of a `Spacer` when `minLength` is `nil`.
    static let spacerMinLength: CGFloat = 8

    /// Assumed: the point size of the `body` text style at the default
    /// Dynamic Type size, on iOS.
    static let bodyFontSize: CGFloat = 17

    /// Assumed: the ideal size of a view that fills its proposal, such as
    /// `Color`, when the parent proposes no size.
    static let flexibleIdealSize: CGFloat = 10

    /// Assumed: the side of a symbol image relative to the font size, for
    /// each image scale. Parhelion has no SF Symbols, so every symbol is a
    /// square of this size.
    static func symbolSide(for scale: Image.Scale) -> CGFloat {
        switch scale {
        case .small: bodyFontSize * 0.78
        case .medium: bodyFontSize
        case .large: bodyFontSize * 1.29
        }
    }
}
