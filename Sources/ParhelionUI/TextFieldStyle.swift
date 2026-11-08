import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// Text field styles. The automatic and plain styles draw the text alone, as
// on iOS. The rounded border style pads the field and draws a hairline
// rounded rectangle around it, with a layout modifier that this file
// registers, so no shared file knows about it.

/// A style for text fields, mirroring SwiftUI's `TextFieldStyle`.
///
/// Parhelion draws the built-in styles; other conforming types draw as
/// ``automatic``.
@MainActor
@preconcurrency
public protocol TextFieldStyle {}

/// The default text field style: the text alone on iOS, mirroring SwiftUI's
/// `DefaultTextFieldStyle`.
public struct DefaultTextFieldStyle: TextFieldStyle {
    public init() {}
}

/// A text field style without decoration, mirroring SwiftUI's
/// `PlainTextFieldStyle`.
public struct PlainTextFieldStyle: TextFieldStyle {
    public init() {}
}

/// A text field style with a rounded border, mirroring SwiftUI's
/// `RoundedBorderTextFieldStyle`.
public struct RoundedBorderTextFieldStyle: TextFieldStyle {
    public init() {}
}

extension TextFieldStyle where Self == DefaultTextFieldStyle {
    public static var automatic: DefaultTextFieldStyle { DefaultTextFieldStyle() }
}

extension TextFieldStyle where Self == PlainTextFieldStyle {
    public static var plain: PlainTextFieldStyle { PlainTextFieldStyle() }
}

extension TextFieldStyle where Self == RoundedBorderTextFieldStyle {
    public static var roundedBorder: RoundedBorderTextFieldStyle { RoundedBorderTextFieldStyle() }
}

extension View {
    /// Sets the style of text fields in this view and its content.
    public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View {
        let resolved: ResolvedTextFieldStyle =
            switch style {
            case is PlainTextFieldStyle: .plain
            case is RoundedBorderTextFieldStyle: .roundedBorder
            default: .automatic
            }
        return environment(\.textFieldStyle, resolved)
    }
}

/// The text field styles Parhelion draws, by the names nodes record in
/// their `textFieldStyle` attribute.
enum ResolvedTextFieldStyle: String, Sendable {
    case automatic, plain, roundedBorder

    /// The modifier that draws the rounded border.
    static let borderModifier = "roundedBorderTextField"

    /// Measured on an iPhone on iOS 27: the field is 34 points high for
    /// 17-point text, with its text 7 points from the border's sides.
    static let roundedBorderPadding = EdgeInsets(top: 6, leading: 7, bottom: 6, trailing: 7)
    /// Measured on an iPhone on iOS 27: the border's corner radius.
    static let roundedBorderCornerRadius: CGFloat = 5
    /// Measured on an iPhone on iOS 27: the hairline's color.
    static let lightBorder = RGBA(red: 204, green: 204, blue: 204)
    static let darkBorder = RGBA(red: 51, green: 51, blue: 51)

    /// Records the style on a field's node, and pads and frames it for the
    /// rounded border style.
    func apply(to node: inout ViewNode) {
        guard self != .automatic else { return }
        node.attributes["textFieldStyle"] = rawValue
        guard self == .roundedBorder else { return }
        NodeExtensions.registerOnce(modifier: Self.borderModifier) {
            ModifierBehavior(
                outline: { _ in Self.borderModifier },
                drawBehind: { _, _, drawing, canvas in
                    var color = drawing.scheme == .dark ? Self.darkBorder : Self.lightBorder
                    color.alpha = UInt8((Double(color.alpha) * drawing.opacity).rounded())
                    canvas.stroke(
                        drawing.frame, cornerRadius: Self.roundedBorderCornerRadius,
                        lineWidth: 1 / CGFloat(canvas.scale), alignment: .inside, color: color)
                })
        }
        node.modifiers.append(.padding(Self.roundedBorderPadding))
        node.modifiers.append(.custom(CustomModifier(name: Self.borderModifier)))
    }
}

struct TextFieldStyleKey: EnvironmentKey {
    static var defaultValue: ResolvedTextFieldStyle { .automatic }
}

extension EnvironmentValues {
    /// The style of text fields in the view.
    var textFieldStyle: ResolvedTextFieldStyle {
        get { self[TextFieldStyleKey.self] }
        set { self[TextFieldStyleKey.self] = newValue }
    }
}
