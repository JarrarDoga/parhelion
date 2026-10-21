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

    /// The radius of the screen's rounded corners in points, or 0 for a
    /// square screen.
    public var displayCornerRadius: CGFloat

    /// The cutout for the front camera at the top of the screen, if any.
    public var sensorHousing: SensorHousing?

    /// The width of the home indicator in points, or `nil` for a device
    /// without one.
    public var homeIndicatorWidth: CGFloat?

    public init(
        name: String,
        screenSize: CGSize,
        safeAreaInsets: EdgeInsets,
        displayCornerRadius: CGFloat = 0,
        sensorHousing: SensorHousing? = nil,
        homeIndicatorWidth: CGFloat? = nil
    ) {
        self.name = name
        self.screenSize = screenSize
        self.safeAreaInsets = safeAreaInsets
        self.displayCornerRadius = displayCornerRadius
        self.sensorHousing = sensorHousing
        self.homeIndicatorWidth = homeIndicatorWidth
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

    /// The height the status bar's contents are centered on: the Dynamic
    /// Island's middle, or `nil` to center them in the top safe-area inset.
    var statusBarMidY: CGFloat? {
        guard case .dynamicIsland(let frame)? = sensorHousing else { return nil }
        return frame.midY
    }
}

/// The cutout for the front camera at the top of a screen.
public enum SensorHousing: Hashable, Sendable {
    /// A capsule below the top edge of the screen.
    case dynamicIsland(CGRect)
    /// A cutout that hangs from the top edge, with rounded bottom corners.
    case notch(CGRect, cornerRadius: CGFloat)

    /// The cutout's frame in screen coordinates.
    public var frame: CGRect {
        switch self {
        case .dynamicIsland(let frame), .notch(let frame, _): frame
        }
    }
}

extension Device {
    // Screen sizes are from Apple's Human Interface Guidelines. Safe-area
    // insets are from Use Your Loaf (useyourloaf.com), and display corner
    // radii are from ScreenCorners (github.com/kylebshr/ScreenCorners).
    // Assumed: the Dynamic Island and notch frames are measurements of
    // Apple's product bezel images and Simulator screenshots, and the home
    // indicator width is measured on an iPhone 16 Pro.

    /// iPhone 16 in portrait: 393 × 852 points.
    public static let iPhone16 = dynamicIslandPhone(
        "iPhone 16", width: 393, height: 852, top: 59, cornerRadius: 55, islandY: 11.33,
        islandWidth: 125)

    /// iPhone 16 Plus in portrait: 430 × 932 points.
    public static let iPhone16Plus = dynamicIslandPhone(
        "iPhone 16 Plus", width: 430, height: 932, top: 59, cornerRadius: 55, islandY: 11.33)

    /// iPhone 16 Pro in portrait: 402 × 874 points.
    public static let iPhone16Pro = dynamicIslandPhone(
        "iPhone 16 Pro", width: 402, height: 874, top: 62, cornerRadius: 62, islandY: 14)

    /// iPhone 16 Pro Max in portrait: 440 × 956 points.
    public static let iPhone16ProMax = dynamicIslandPhone(
        "iPhone 16 Pro Max", width: 440, height: 956, top: 62, cornerRadius: 62, islandY: 14)

    /// iPhone 16e in portrait: 390 × 844 points, with a notch.
    public static let iPhone16e = Device(
        name: "iPhone 16e",
        screenSize: CGSize(width: 390, height: 844),
        safeAreaInsets: EdgeInsets(top: 47, leading: 0, bottom: 34, trailing: 0),
        displayCornerRadius: 47.33,
        // Assumed: the iPhone 14's notch, the same panel.
        sensorHousing: .notch(CGRect(x: 115, y: 0, width: 160, height: 33.67), cornerRadius: 20),
        // Assumed: the width older 375-point-wide design kits use.
        homeIndicatorWidth: 134
    )

    /// iPhone 17 in portrait: 402 × 874 points.
    public static let iPhone17 = dynamicIslandPhone(
        "iPhone 17", width: 402, height: 874, top: 62, cornerRadius: 62, islandY: 14)

    /// iPhone 17 Pro in portrait: 402 × 874 points.
    public static let iPhone17Pro = dynamicIslandPhone(
        "iPhone 17 Pro", width: 402, height: 874, top: 62, cornerRadius: 62, islandY: 14)

    /// iPhone 17 Pro Max in portrait: 440 × 956 points.
    public static let iPhone17ProMax = dynamicIslandPhone(
        "iPhone 17 Pro Max", width: 440, height: 956, top: 62, cornerRadius: 62, islandY: 14)

    /// iPhone Air in portrait: 420 × 912 points.
    public static let iPhoneAir = dynamicIslandPhone(
        "iPhone Air", width: 420, height: 912, top: 68, cornerRadius: 62, islandY: 20)

    /// A phone with a Dynamic Island centered at the top, 34 points of safe
    /// area at the bottom, and a home indicator.
    private static func dynamicIslandPhone(
        _ name: String, width: CGFloat, height: CGFloat, top: CGFloat, cornerRadius: CGFloat,
        islandY: CGFloat, islandWidth: CGFloat = 125.33
    ) -> Device {
        Device(
            name: name,
            screenSize: CGSize(width: width, height: height),
            safeAreaInsets: EdgeInsets(top: top, leading: 0, bottom: 34, trailing: 0),
            displayCornerRadius: cornerRadius,
            sensorHousing: .dynamicIsland(
                CGRect(
                    x: (width - islandWidth) / 2, y: islandY, width: islandWidth,
                    height: 36.67)),
            homeIndicatorWidth: 139
        )
    }

    /// Every device preset, in the order `parhelion` lists them.
    public static let all: [Device] = [
        .iPhone16, .iPhone16Plus, .iPhone16Pro, .iPhone16ProMax, .iPhone16e, .iPhone17,
        .iPhone17Pro, .iPhone17ProMax, .iPhoneAir,
    ]

    /// The preset to simulate when a window host or `PARHELION_DEVICE` asks
    /// for one by name, or iPhone 16 when nothing asks.
    static func simulated(named name: String?) throws -> Device {
        guard let name, !name.isEmpty else { return .iPhone16 }
        guard let device = named(name) else { throw UnknownDeviceError(name: name) }
        return device
    }

    /// The preset with a name, ignoring case, spaces, and punctuation, so
    /// that "iphone-16" finds iPhone 16.
    public static func named(_ name: String) -> Device? {
        func key(_ name: String) -> String {
            String(name.lowercased().filter { $0.isLetter || $0.isNumber })
        }
        let wanted = key(name)
        return all.first { key($0.name) == wanted }
    }
}

/// A device name that matches none of the presets.
struct UnknownDeviceError: Error, CustomStringConvertible {
    let name: String

    var description: String {
        let names = Device.all.map(\.name).joined(separator: ", ")
        return "Unknown device \"\(name)\". Use one of: \(names)."
    }
}
