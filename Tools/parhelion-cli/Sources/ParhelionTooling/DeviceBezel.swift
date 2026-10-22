import Foundation
import ParhelionRender

/// The phone the preview window draws around the app's screen, like the
/// iOS Simulator's device bezel.
///
/// The app draws the screen itself, including its rounded corners and the
/// Dynamic Island, so screenshots and the window agree. The bezel exists
/// only in the window: it is drawn once, and the window draws it over each
/// frame from the app.
public struct DeviceBezel: Sendable {
    /// Assumed: the black border between the screen and the metal band, in
    /// points.
    static let border = 12.0
    /// Assumed: the width of the metal band around the phone, in points.
    static let band = 4.0
    /// How far the side buttons stick out of the band, in points. The
    /// window ends at the buttons.
    static let buttonDepth = 3.0

    /// The distance from the edge of the window to the edge of the screen,
    /// in points.
    public static let margin = border + band + buttonDepth

    static let bandColor = RGBA(red: 72, green: 72, blue: 74)
    static let buttonColor = RGBA(red: 99, green: 99, blue: 102)

    /// Assumed: the side buttons of an iPhone with a Dynamic Island, as the
    /// distance of each button's top from the top of the screen and its
    /// length, both as fractions of the screen's height.
    static let leftButtons: [(top: Double, length: Double)] = [
        (0.155, 0.04),  // Action button
        (0.235, 0.075),  // Volume up
        (0.33, 0.075),  // Volume down
    ]
    static let rightButtons: [(top: Double, length: Double)] = [
        (0.255, 0.12),  // Side button
        (0.6, 0.05),  // Camera Control
    ]

    /// The screen size in points.
    public var screenWidth: Double
    public var screenHeight: Double
    /// The radius of the screen's rounded corners in points.
    public var screenCornerRadius: Double

    public init(screenWidth: Double, screenHeight: Double, screenCornerRadius: Double) {
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.screenCornerRadius = screenCornerRadius
    }

    /// The size of the whole image, screen and bezel, in points.
    public var width: Double { screenWidth + 2 * Self.margin }
    public var height: Double { screenHeight + 2 * Self.margin }

    /// The point on the screen under a point in the bezel image, both in
    /// points. Points outside the screen map to negative coordinates or to
    /// coordinates past the screen's size.
    public func screenPoint(x: Double, y: Double) -> (x: Double, y: Double) {
        (x - Self.margin, y - Self.margin)
    }

    /// A part of the app's frame and how opaque each of its pixels stays.
    public struct FrameMask: Sendable {
        /// The rectangle in the frame's pixels.
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int
        /// The opacity of each pixel in the rectangle, row by row.
        public var alpha: [UInt8]
        /// The pixels that are not fully opaque, by their index in the
        /// rectangle, and their opacity.
        public var faded: [(index: Int, alpha: UInt8)] {
            alpha.indices.compactMap { alpha[$0] < 255 ? ($0, alpha[$0]) : nil }
        }
    }

    /// The parts of a frame at `scale` pixels per point that lie outside
    /// the phone's rounded body: the screen's square corners reach past it.
    /// The window makes them transparent before it shows the frame.
    public func frameMasks(scale: Double) -> [FrameMask] {
        let bodyInset = Self.border + Self.band
        // The body in the frame's coordinates, which start at the screen.
        let body = CGRect(x: 0, y: 0, width: screenWidth, height: screenHeight)
            .insetBy(dx: -bodyInset, dy: -bodyInset)
        var canvas = Canvas(
            width: screenWidth, height: screenHeight, scale: scale,
            background: RGBA(red: 0, green: 0, blue: 0, alpha: 0))
        canvas.fill(body, cornerRadius: screenCornerRadius + bodyInset, color: .white)
        // The corner boxes reach as far as the body's curve can.
        let side = min(
            Int((screenCornerRadius * scale).rounded(.up)), canvas.width / 2, canvas.height / 2)
        let origins = [
            (0, 0), (canvas.width - side, 0), (0, canvas.height - side),
            (canvas.width - side, canvas.height - side),
        ]
        return origins.map { x, y in
            var alpha: [UInt8] = []
            alpha.reserveCapacity(side * side)
            for row in y..<(y + side) {
                for column in x..<(x + side) {
                    alpha.append(canvas.pixel(x: column, y: row).alpha)
                }
            }
            return FrameMask(x: x, y: y, width: side, height: side, alpha: alpha)
        }
    }

    /// Draws the phone and its buttons, with a transparent hole the shape
    /// of the screen. Everything outside the phone is transparent too. The
    /// window draws it over the app's frame, so it covers the frame's square
    /// corners.
    public func image(scale: Double) -> Canvas {
        var canvas = Canvas(
            width: width, height: height, scale: scale,
            background: RGBA(red: 0, green: 0, blue: 0, alpha: 0))
        let screen = CGRect(
            x: Self.margin, y: Self.margin, width: screenWidth, height: screenHeight)
        let bodyInset = Self.border + Self.band
        let body = screen.insetBy(dx: -bodyInset, dy: -bodyInset)
        let glass = screen.insetBy(dx: -Self.border, dy: -Self.border)

        /// A rounded rectangle with a rounded hole in it.
        func ring(_ outer: CGRect, _ radius: Double, hole: CGRect, _ holeRadius: Double) -> Path {
            var path = Path(roundedRect: outer, cornerRadius: radius)
            path.addPath(Path(roundedRect: hole, cornerRadius: holeRadius, reversed: true))
            return path
        }

        func button(_ x: Double, _ spec: (top: Double, length: Double)) {
            canvas.fill(
                CGRect(
                    x: x,
                    y: Double(screen.minY) + spec.top * screenHeight,
                    width: Self.buttonDepth,
                    height: spec.length * screenHeight
                ),
                cornerRadius: 1,
                color: Self.buttonColor
            )
        }
        for spec in Self.leftButtons { button(Double(body.minX) - Self.buttonDepth, spec) }
        for spec in Self.rightButtons { button(Double(body.maxX), spec) }

        canvas.fill(
            ring(
                body, screenCornerRadius + bodyInset, hole: glass,
                screenCornerRadius + Self.border),
            color: Self.bandColor)
        canvas.fill(
            ring(glass, screenCornerRadius + Self.border, hole: screen, screenCornerRadius),
            color: .black)
        return canvas
    }
}

/// The point on the screen under a point in the preview window, both in
/// points: the window is `zoom` times the size of the screen, or of the
/// screen and the bezel around it.
public func screenPoint(
    windowX: Double, windowY: Double, zoom: Double, bezel: DeviceBezel?
) -> (x: Double, y: Double) {
    let x = windowX / zoom
    let y = windowY / zoom
    return bezel?.screenPoint(x: x, y: y) ?? (x, y)
}
