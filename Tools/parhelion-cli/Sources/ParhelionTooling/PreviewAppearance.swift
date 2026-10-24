import ParhelionPreview

/// The simulated device's appearance and text size, as the preview window,
/// web pages, and `parhelion mcp` switch them. Names are SwiftUI's, such as
/// "dark" and "accessibility2".
///
/// The tool keeps the setting, so that an app that restarts after a save or
/// a rebuild starts with it, through ``environment``.
public struct PreviewAppearance: Equatable, Sendable {
    /// The names of the color schemes, in SwiftUI's order.
    public static let colorSchemes = ["light", "dark"]
    /// The names of the Dynamic Type sizes, smallest first.
    public static let dynamicTypeSizes = [
        "xSmall", "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge",
        "accessibility1", "accessibility2", "accessibility3", "accessibility4", "accessibility5",
    ]

    public var colorScheme = "light"
    public var dynamicTypeSize = "large"

    public init() {}

    /// A change that a person or an agent asks for.
    public enum Change: Equatable, Sendable {
        /// Light becomes dark, and dark light.
        case toggleColorScheme
        /// The text size moves this many sizes larger, or smaller when
        /// negative, and stops at the smallest and largest.
        case textSize(steps: Int)
        /// Sets either value by name; `nil` keeps it.
        case set(colorScheme: String?, dynamicTypeSize: String?)
    }

    /// The setting after a change, or `nil` when the change names a scheme
    /// or a size that does not exist.
    public func applying(_ change: Change) -> PreviewAppearance? {
        var result = self
        switch change {
        case .toggleColorScheme:
            result.colorScheme = colorScheme == "dark" ? "light" : "dark"
        case .textSize(let steps):
            let sizes = Self.dynamicTypeSizes
            let index = sizes.firstIndex(of: dynamicTypeSize) ?? sizes.firstIndex(of: "large")!
            result.dynamicTypeSize = sizes[min(max(index + steps, 0), sizes.count - 1)]
        case .set(let colorScheme, let dynamicTypeSize):
            if let colorScheme {
                guard Self.colorSchemes.contains(colorScheme) else { return nil }
                result.colorScheme = colorScheme
            }
            if let dynamicTypeSize {
                guard Self.dynamicTypeSizes.contains(dynamicTypeSize) else { return nil }
                result.dynamicTypeSize = dynamicTypeSize
            }
        }
        return result
    }

    /// The command that gives a running app this setting.
    public var command: PreviewCommand {
        .setAppearance(colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize)
    }

    /// The environment variables that start an app with this setting.
    public var environment: [String: String] {
        [
            previewColorSchemeEnvironmentKey: colorScheme,
            previewDynamicTypeSizeEnvironmentKey: dynamicTypeSize,
        ]
    }

    /// The setting in a few words for a window's title, such as "Dark" or
    /// "Dark, accessibility2", or an empty string for light at Large.
    public var summary: String {
        var parts: [String] = []
        if colorScheme != "light" {
            parts.append(colorScheme.prefix(1).uppercased() + colorScheme.dropFirst())
        }
        if dynamicTypeSize != "large" { parts.append(dynamicTypeSize) }
        return parts.joined(separator: ", ")
    }

    /// Whether an app takes appearance commands: whether its hello lists
    /// ``PreviewCapability/appearance``. Apps built with an older Parhelion
    /// do not.
    public static func isSupported(by hello: PreviewHello) -> Bool {
        hello.capabilities?.contains(PreviewCapability.appearance) == true
    }
}
