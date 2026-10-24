#if canImport(Foundation)
import Foundation
#endif

/// The appearance the interface uses, mirroring SwiftUI's `ColorScheme`.
public enum ColorScheme: CaseIterable, Sendable {
    case light
    case dark

    /// The case's name, as nodes record it in their `colorScheme`
    /// attribute.
    var name: String {
        switch self {
        case .light: "light"
        case .dark: "dark"
        }
    }

    /// The scheme a ``name`` names.
    init?(name: String) {
        guard let match = Self.allCases.first(where: { $0.name == name }) else { return nil }
        self = match
    }
}

/// The size of the text the user chose, mirroring SwiftUI's
/// `DynamicTypeSize`.
public enum DynamicTypeSize: Hashable, Comparable, CaseIterable, Sendable {
    case xSmall
    case small
    case medium
    case large
    case xLarge
    case xxLarge
    case xxxLarge
    case accessibility1
    case accessibility2
    case accessibility3
    case accessibility4
    case accessibility5

    /// Whether the size is one of the larger accessibility sizes.
    public var isAccessibilitySize: Bool {
        self >= .accessibility1
    }

    /// The case's name, as SwiftUI spells it, which nodes record in their
    /// `dynamicTypeSize` attribute.
    var name: String {
        switch self {
        case .xSmall: "xSmall"
        case .small: "small"
        case .medium: "medium"
        case .large: "large"
        case .xLarge: "xLarge"
        case .xxLarge: "xxLarge"
        case .xxxLarge: "xxxLarge"
        case .accessibility1: "accessibility1"
        case .accessibility2: "accessibility2"
        case .accessibility3: "accessibility3"
        case .accessibility4: "accessibility4"
        case .accessibility5: "accessibility5"
        }
    }

    /// The size a ``name`` names.
    init?(name: String) {
        guard let match = Self.allCases.first(where: { $0.name == name }) else { return nil }
        self = match
    }
}

/// How much room the interface has along one axis, mirroring SwiftUI's
/// `UserInterfaceSizeClass`.
public enum UserInterfaceSizeClass: Sendable {
    case compact
    case regular
}

struct ColorSchemeKey: EnvironmentKey {
    static var defaultValue: ColorScheme { .light }
}

struct DynamicTypeSizeKey: EnvironmentKey {
    static var defaultValue: DynamicTypeSize { .large }
}

// Every `Device` preset is an iPhone in portrait, which is compact across and
// regular down.

struct HorizontalSizeClassKey: EnvironmentKey {
    static var defaultValue: UserInterfaceSizeClass? { .compact }
}

struct VerticalSizeClassKey: EnvironmentKey {
    static var defaultValue: UserInterfaceSizeClass? { .regular }
}

struct LocaleKey: EnvironmentKey {
    // Assumed: the simulated device uses US English, as a new Simulator
    // does. A fixed locale keeps trees the same on every machine.
    static var defaultValue: Locale { Locale(identifier: "en_US") }
}

extension EnvironmentValues {
    /// The appearance. Setting it changes the color scheme of a view and its
    /// content, but not of the views above it. It starts as the
    /// presentation's preferred color scheme, set with
    /// ``View/preferredColorScheme(_:)``, or else as the host's
    /// ``ViewHost/colorScheme``, which is `light` by default.
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }

    /// The size of text the user chose: the host's
    /// ``ViewHost/dynamicTypeSize``, `large` by default, unless a
    /// ``View/dynamicTypeSize(_:)`` modifier above changed it.
    public var dynamicTypeSize: DynamicTypeSize {
        get { self[DynamicTypeSizeKey.self] }
        set { self[DynamicTypeSizeKey.self] = newValue }
    }

    /// The horizontal size class: `compact` on an iPhone in portrait.
    public var horizontalSizeClass: UserInterfaceSizeClass? {
        get { self[HorizontalSizeClassKey.self] }
        set { self[HorizontalSizeClassKey.self] = newValue }
    }

    /// The vertical size class: `regular` on an iPhone in portrait.
    public var verticalSizeClass: UserInterfaceSizeClass? {
        get { self[VerticalSizeClassKey.self] }
        set { self[VerticalSizeClassKey.self] = newValue }
    }

    /// The locale that views format text for: US English.
    public var locale: Locale {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }
}

// MARK: - Modifiers

extension View {
    /// Sets the preferred color scheme of the presentation that contains this
    /// view: the window, a sheet, or another presentation. The whole
    /// presentation takes it, including views above this one, but not the
    /// presentations beneath it. `nil` means no preference.
    ///
    /// A modifier overrides the preferences of the views inside it. Between
    /// views side by side, the first one with a preference wins.
    public func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View {
        PreferredColorSchemeView(content: self, colorScheme: colorScheme)
    }

    /// Sets the Dynamic Type size of this view and its content. A size range
    /// applied inside this modifier limits the size.
    public func dynamicTypeSize(_ size: DynamicTypeSize) -> some View {
        environment(\.dynamicTypeSize, size)
    }

    /// Limits the Dynamic Type size of this view and its content to a range.
    /// Several ranges limit the size to their intersection, and a size set
    /// inside this modifier is not limited.
    public func dynamicTypeSize<T: RangeExpression>(_ range: T) -> some View
    where T.Bound == DynamicTypeSize {
        EnvironmentWriter(content: self) { environment in
            environment.dynamicTypeSize = range.clamping(environment.dynamicTypeSize)
        }
    }
}

extension RangeExpression where Bound == DynamicTypeSize {
    /// The size nearest to `size` in the range.
    fileprivate func clamping(_ size: DynamicTypeSize) -> DynamicTypeSize {
        if contains(size) { return size }
        let sizes = DynamicTypeSize.allCases
        let inside = sizes.filter(contains)
        guard let lowest = inside.first, let highest = inside.last else { return size }
        return size < lowest ? lowest : highest
    }
}

/// A view that states its presentation's preferred color scheme.
struct PreferredColorSchemeView<Content: View>: View {
    typealias Body = Never

    let content: Content
    let colorScheme: ColorScheme?

    var body: Never {
        fatalError("PreferredColorSchemeView is a primitive view and has no body.")
    }
}

extension PreferredColorSchemeView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        // The content's preferences are collected on their own, so that this
        // modifier overrides them and an earlier sibling's preference still
        // wins over this one.
        let earlier = evaluator.preferredColorScheme
        evaluator.preferredColorScheme = nil
        let nodes = evaluator.evaluate(content, at: path)
        evaluator.preferredColorScheme = earlier ?? colorScheme ?? evaluator.preferredColorScheme
        return nodes
    }
}

// MARK: - Scaled metrics

/// A dimension that scales with the Dynamic Type size, mirroring SwiftUI's
/// `ScaledMetric`.
///
/// The value scales in proportion to a text style's point size, the body
/// style unless another is given: at xxxLarge, where body text is 23
/// points instead of 17, a metric of 17 is 23.
@propertyWrapper
public struct ScaledMetric<Value: BinaryFloatingPoint>: DynamicProperty {
    private let baseValue: Value
    private let textStyle: Font.TextStyle
    let box = EnvironmentBox()

    /// A metric that scales like body text.
    public init(wrappedValue: Value) {
        self.init(wrappedValue: wrappedValue, relativeTo: .body)
    }

    /// A metric that scales like text in the given style.
    public init(wrappedValue: Value, relativeTo textStyle: Font.TextStyle) {
        baseValue = wrappedValue
        self.textStyle = textStyle
    }

    /// The value scaled for the environment's Dynamic Type size.
    @MainActor
    public var wrappedValue: Value {
        Value(
            DynamicTypeTable.scale(
                CGFloat(baseValue), relativeTo: textStyle, at: box.values.dynamicTypeSize))
    }
}

extension ScaledMetric: EnvironmentInstallable {
    func install(_ values: EnvironmentValues) {
        box.values = values
    }
}
