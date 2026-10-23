#if canImport(Foundation)
import Foundation
#endif

/// The appearance the interface uses, mirroring SwiftUI's `ColorScheme`.
public enum ColorScheme: CaseIterable, Sendable {
    case light
    case dark
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
}

/// How much room the interface has along one axis, mirroring SwiftUI's
/// `UserInterfaceSizeClass`.
public enum UserInterfaceSizeClass: Sendable {
    case compact
    case regular
}

struct ColorSchemeKey: EnvironmentKey {
    // Parhelion draws only the light appearance so far.
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
    /// The appearance: light, until Parhelion draws the dark appearance.
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }

    /// The size of text the user chose. The default is `large`, and text does
    /// not scale with it yet.
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
