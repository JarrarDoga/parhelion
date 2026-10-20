#if canImport(Foundation)
import Foundation
#endif

/// The screen a view hierarchy is laid out for.
public struct Device: Hashable, Sendable {
    public var name: String

    /// The screen size in points.
    public var screenSize: CGSize

    /// The insets of the area not covered by system UI, such as the status
    /// bar and the home indicator.
    public var safeAreaInsets: EdgeInsets

    public init(name: String, screenSize: CGSize, safeAreaInsets: EdgeInsets) {
        self.name = name
        self.screenSize = screenSize
        self.safeAreaInsets = safeAreaInsets
    }

    /// The safe area in screen coordinates.
    public var safeArea: CGRect {
        CGRect(
            x: safeAreaInsets.leading,
            y: safeAreaInsets.top,
            width: screenSize.width - safeAreaInsets.leading - safeAreaInsets.trailing,
            height: screenSize.height - safeAreaInsets.top - safeAreaInsets.bottom
        )
    }

    /// iPhone 16 in portrait: 393 × 852 points. Assumed safe-area insets:
    /// 59 points at the top and 34 at the bottom.
    public static let iPhone16 = Device(
        name: "iPhone 16",
        screenSize: CGSize(width: 393, height: 852),
        safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    )
}
