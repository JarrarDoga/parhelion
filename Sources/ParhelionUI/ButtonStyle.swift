#if canImport(Foundation)
import Foundation
#endif

// MARK: - Styles

/// A style for buttons that Parhelion draws itself, mirroring SwiftUI's
/// `PrimitiveButtonStyle`.
///
/// Parhelion implements the built-in styles, such as ``bordered`` and
/// ``glass``, and has no requirements for other conforming types: a custom
/// primitive style compiles but buttons draw with the default style. Custom
/// styles that conform to ``ButtonStyle`` work.
@MainActor
@preconcurrency
public protocol PrimitiveButtonStyle {}

/// A style that builds a button's appearance from its label, mirroring
/// SwiftUI's `ButtonStyle`.
///
/// Parhelion evaluates ``makeBody(configuration:)`` in place of the label.
/// The configuration's `isPressed` is always `false`: a press changes only
/// how the button is drawn, not the tree.
@MainActor
@preconcurrency
public protocol ButtonStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    typealias Configuration = ButtonStyleConfiguration
}

/// The properties of a button that a ``ButtonStyle`` draws, mirroring
/// SwiftUI's `ButtonStyleConfiguration`.
public struct ButtonStyleConfiguration {
    /// The button's label, as a view.
    public struct Label: View {
        public typealias Body = Never

        let content: any View

        public var body: Never {
            fatalError("Label is a primitive view and has no body.")
        }
    }

    /// The button's role, if it has one.
    public let role: ButtonRole?
    /// The button's label.
    public let label: Label
    /// Whether the button is being pressed. Always `false` in Parhelion.
    public let isPressed: Bool
}

extension ButtonStyleConfiguration.Label: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        evaluator.evaluate(content, at: path)
    }
}

/// The button styles Parhelion draws, by the names nodes record.
enum BuiltInButtonStyle: String, Sendable {
    case automatic, plain, borderless, bordered, borderedProminent, glass, glassProminent

    /// Whether the style draws a capsule behind the label.
    var drawsShape: Bool {
        switch self {
        case .bordered, .borderedProminent, .glass, .glassProminent: true
        case .automatic, .plain, .borderless: false
        }
    }

    /// Whether the style fills its shape with the tint color.
    var isProminent: Bool {
        self == .borderedProminent || self == .glassProminent
    }

    var isGlass: Bool {
        self == .glass || self == .glassProminent
    }
}

/// A primitive button style that Parhelion draws.
protocol BuiltInPrimitiveButtonStyle: PrimitiveButtonStyle {
    var builtIn: BuiltInButtonStyle { get }
}

/// The default button style, mirroring SwiftUI's `DefaultButtonStyle`.
/// Outside lists and toolbars, it is ``BorderlessButtonStyle``.
public struct DefaultButtonStyle: BuiltInPrimitiveButtonStyle {
    var builtIn: BuiltInButtonStyle { .automatic }
    public init() {}
}

/// A style that draws the label without decoration, in the current
/// foreground style instead of the tint color, mirroring SwiftUI's
/// `PlainButtonStyle`.
public struct PlainButtonStyle: BuiltInPrimitiveButtonStyle {
    var builtIn: BuiltInButtonStyle { .plain }
    public init() {}
}

/// A style that draws the label in the tint color with no border,
/// mirroring SwiftUI's `BorderlessButtonStyle`.
public struct BorderlessButtonStyle: BuiltInPrimitiveButtonStyle {
    var builtIn: BuiltInButtonStyle { .borderless }
    public init() {}
}

/// A style that draws a gray capsule behind a label in the tint color,
/// mirroring SwiftUI's `BorderedButtonStyle`.
public struct BorderedButtonStyle: BuiltInPrimitiveButtonStyle {
    var builtIn: BuiltInButtonStyle { .bordered }
    public init() {}
}

/// A style that draws a capsule in the tint color behind a white label,
/// mirroring SwiftUI's `BorderedProminentButtonStyle`.
public struct BorderedProminentButtonStyle: BuiltInPrimitiveButtonStyle {
    var builtIn: BuiltInButtonStyle { .borderedProminent }
    public init() {}
}

/// A style that draws a Liquid Glass capsule behind the label, mirroring
/// SwiftUI's `GlassButtonStyle`.
public struct GlassButtonStyle: BuiltInPrimitiveButtonStyle {
    var builtIn: BuiltInButtonStyle { .glass }
    public init() {}
}

/// A style that draws a capsule of glass tinted with the tint color behind
/// a white label, mirroring SwiftUI's `GlassProminentButtonStyle`.
public struct GlassProminentButtonStyle: BuiltInPrimitiveButtonStyle {
    var builtIn: BuiltInButtonStyle { .glassProminent }
    public init() {}
}

extension PrimitiveButtonStyle where Self == DefaultButtonStyle {
    public static var automatic: DefaultButtonStyle { DefaultButtonStyle() }
}

extension PrimitiveButtonStyle where Self == PlainButtonStyle {
    public static var plain: PlainButtonStyle { PlainButtonStyle() }
}

extension PrimitiveButtonStyle where Self == BorderlessButtonStyle {
    public static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() }
}

extension PrimitiveButtonStyle where Self == BorderedButtonStyle {
    public static var bordered: BorderedButtonStyle { BorderedButtonStyle() }
}

extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle {
    public static var borderedProminent: BorderedProminentButtonStyle {
        BorderedProminentButtonStyle()
    }
}

extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    public static var glass: GlassButtonStyle { GlassButtonStyle() }
}

extension PrimitiveButtonStyle where Self == GlassProminentButtonStyle {
    public static var glassProminent: GlassProminentButtonStyle { GlassProminentButtonStyle() }
}

// MARK: - Control size

/// The size of controls such as bordered buttons, mirroring SwiftUI's
/// `ControlSize`.
public enum ControlSize: String, CaseIterable, Hashable, Sendable {
    case mini, small, regular, large, extraLarge
}

// MARK: - Environment

/// The style buttons take from the environment.
enum ResolvedButtonStyle {
    case builtIn(BuiltInButtonStyle)
    case custom(any ButtonStyle)
}

/// Where a button is, which changes how it looks.
enum ButtonContext {
    /// Anywhere other than below.
    case standard
    /// In the leading or trailing items of a navigation bar, which draw
    /// glass behind their buttons.
    case toolbar
    /// In an alert's actions, which draw each button as a capsule.
    case alert
}

struct ButtonStyleKey: EnvironmentKey {
    static var defaultValue: ResolvedButtonStyle { .builtIn(.automatic) }
}

struct ButtonContextKey: EnvironmentKey {
    static var defaultValue: ButtonContext { .standard }
}

struct ControlSizeKey: EnvironmentKey {
    static var defaultValue: ControlSize { .regular }
}

extension EnvironmentValues {
    /// The size of controls in the view.
    public var controlSize: ControlSize {
        get { self[ControlSizeKey.self] }
        set { self[ControlSizeKey.self] = newValue }
    }

    var buttonStyle: ResolvedButtonStyle {
        get { self[ButtonStyleKey.self] }
        set { self[ButtonStyleKey.self] = newValue }
    }

    var buttonContext: ButtonContext {
        get { self[ButtonContextKey.self] }
        set { self[ButtonContextKey.self] = newValue }
    }
}

extension View {
    /// Sets the style of buttons in this view and its content.
    public func buttonStyle<S: PrimitiveButtonStyle>(_ style: S) -> some View {
        let builtIn = (style as? any BuiltInPrimitiveButtonStyle)?.builtIn ?? .automatic
        return EnvironmentWriter(content: self) { $0.buttonStyle = .builtIn(builtIn) }
    }

    /// Sets a custom style for buttons in this view and its content.
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        EnvironmentWriter(content: self) { $0.buttonStyle = .custom(style) }
    }

    /// Sets the size of controls, such as bordered buttons, in this view and
    /// its content.
    public func controlSize(_ controlSize: ControlSize) -> some View {
        environment(\.controlSize, controlSize)
    }

    /// Sets the tint color of this view and its content: the color of
    /// buttons' labels and of prominent buttons' fills. A `nil` tint
    /// restores the default.
    public func tint(_ tint: Color?) -> some View {
        attributeModifier("tint", tint?.styleName ?? "accentColor")
    }

    /// Sets the tint of this view and its content to a shape style.
    public func tint<S: ShapeStyle>(_ tint: S?) -> some View {
        attributeModifier("tint", tint?.styleName ?? "accentColor")
    }
}
