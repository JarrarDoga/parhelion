import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// The system interface Parhelion can draw over an app's content.
public enum DeviceChrome: Sendable, CaseIterable {
    /// Only the app's content.
    case none
    /// The status bar and the home indicator, as in a screenshot taken in
    /// the iOS Simulator.
    case systemBars
    /// The system bars, the Dynamic Island or notch, and the screen's
    /// rounded corners, as the Simulator's window shows the screen.
    case screen
}

/// The sizes and positions of the system interface's parts.
///
/// Assumed: these are measurements of iOS 18 and iOS 26 Simulator
/// screenshots of 402-point-wide iPhones, which match glyph for glyph, and
/// of Apple's product bezel images. Apple publishes none of them. Parhelion
/// uses the same sizes on every device.
enum ChromeMetrics {
    /// The status bar's clock, which the Simulator shows as 9:41.
    static let time = "9:41"
    /// Assumed: the clock is SF Pro Semibold at 17 points, which matches its
    /// measured cap height of 12 points. Parhelion draws it with Inter
    /// SemiBold.
    static let timeFontSize = 17.0

    /// How far the clock and the glyphs sit from the centers of the areas
    /// beside the sensor housing, toward the housing.
    static let towardHousing: CGFloat = 5

    /// The cellular signal glyph's four bars, bottom-aligned. Assumed: the
    /// sizes are scaled from a 440-point-wide screenshot.
    static let signalBarWidth: CGFloat = 3.33
    static let signalBarSpacing: CGFloat = 2
    static let signalBarHeights: [CGFloat] = [4.67, 7, 9.67, 12.33]
    static let signalBarCornerRadius: CGFloat = 1

    /// The Wi-Fi glyph: three bands of a fan whose point is at the bottom,
    /// 17 × 12.33 points. Each band is given as its inner and outer radius.
    static let wifiBands: [(inner: CGFloat, outer: CGFloat)] = [
        (0, 3.8), (5.4, 8.1), (9.6, 12.33),
    ]
    /// The fan opens this far to each side of vertical, so that it is 17
    /// points wide.
    static let wifiHalfAngle = asin(8.5 / 12.33)

    /// The battery glyph: a translucent outline around a solid fill, which
    /// shows a full charge, and a translucent terminal to its right.
    static let batterySize = CGSize(width: 25, height: 13)
    static let batteryCornerRadius: CGFloat = 4.33
    static let batteryOutlineWidth: CGFloat = 1
    static let batteryFillInset: CGFloat = 2
    static let batteryTerminalSize = CGSize(width: 1.33, height: 4)
    static let batteryTerminalGap: CGFloat = 1
    static let batteryOutlineOpacity = 0.4
    static let batteryTerminalOpacity = 0.5

    /// The space between the glyphs on the right of the status bar.
    static let glyphSpacing: CGFloat = 7.33

    /// Assumed: the radius of the curves where a notch's sides flare out to
    /// meet the top of the screen, measured on the iPhone 14's bezel.
    static let notchFlareRadius: CGFloat = 5.67

    /// The home indicator: a 5-point capsule whose bottom is 8 points above
    /// the bottom of the screen. Its width varies by device.
    static let homeIndicatorHeight: CGFloat = 5
    static let homeIndicatorBottomMargin: CGFloat = 8
}

extension TreeRenderer {
    /// Draws the system interface over the content. It reads only the
    /// device, not the tree.
    func drawChrome(_ chrome: DeviceChrome, into canvas: inout Canvas) {
        guard chrome != .none else { return }
        // Assumed: Parhelion draws only the light appearance so far, in
        // which the status bar and the home indicator are black.
        let color = ColorPalette.systemBarForeground
        drawStatusBar(color: color, into: &canvas)
        if let width = device.homeIndicatorWidth {
            let screen = device.screenSize
            canvas.fill(
                CGRect(
                    x: (screen.width - width) / 2,
                    y: screen.height - ChromeMetrics.homeIndicatorBottomMargin
                        - ChromeMetrics.homeIndicatorHeight,
                    width: width,
                    height: ChromeMetrics.homeIndicatorHeight
                ),
                cornerRadius: ChromeMetrics.homeIndicatorHeight / 2,
                color: color
            )
        }
        guard chrome == .screen else { return }
        switch device.sensorHousing {
        case .dynamicIsland(let frame)?:
            canvas.fill(frame, cornerRadius: frame.height / 2, color: .black)
        case .notch(let frame, let cornerRadius)?:
            drawNotch(frame, cornerRadius: cornerRadius, into: &canvas)
        case nil:
            break
        }
        drawScreenCorners(into: &canvas)
    }

    /// The parts of the status bar to the left and right of the sensor
    /// housing, and the height their contents are centered on.
    private var statusBarAreas: (left: CGRect, right: CGRect, midY: CGFloat)? {
        let width = device.screenSize.width
        let height = device.safeAreaInsets.top
        guard height > 0 else { return nil }
        let housing = device.sensorHousing?.frame
        // Assumed: without a sensor housing, the clock and the glyphs each
        // take the outer third of the status bar.
        let leftEdge = housing?.minX ?? width / 3
        let rightEdge = housing?.maxX ?? width * 2 / 3
        let midY = device.statusBarMidY ?? height / 2
        return (
            CGRect(x: 0, y: 0, width: leftEdge, height: height),
            CGRect(x: rightEdge, y: 0, width: width - rightEdge, height: height),
            midY
        )
    }

    private func drawStatusBar(color: RGBA, into canvas: inout Canvas) {
        guard let areas = statusBarAreas else { return }

        // The clock is centered a little toward the housing from the middle
        // of the area to its left, with its digits centered on the bar's
        // midline.
        let font = TrueTypeFont.interSemiBold
        let size = ChromeMetrics.timeFontSize
        let timeWidth = font.width(of: ChromeMetrics.time, size: size)
        let capHeight = font.capHeight(size: size)
        canvas.drawText(
            ChromeMetrics.time,
            font: font,
            size: size,
            origin: CGPoint(
                x: Double(areas.left.midX + ChromeMetrics.towardHousing) - timeWidth / 2,
                y: Double(areas.midY) + capHeight / 2
            ),
            color: color
        )

        // The signal, Wi-Fi, and battery glyphs are placed as a group the
        // same way in the area to the right, sharing a midline with the
        // clock.
        let signalWidth =
            ChromeMetrics.signalBarWidth * CGFloat(ChromeMetrics.signalBarHeights.count)
            + ChromeMetrics.signalBarSpacing * CGFloat(ChromeMetrics.signalBarHeights.count - 1)
        let wifiOuter = ChromeMetrics.wifiBands.last?.outer ?? 0
        let wifiWidth = 2 * wifiOuter * CGFloat(sin(ChromeMetrics.wifiHalfAngle))
        let batteryWidth =
            ChromeMetrics.batterySize.width + ChromeMetrics.batteryTerminalGap
            + ChromeMetrics.batteryTerminalSize.width
        let groupWidth = signalWidth + wifiWidth + batteryWidth + 2 * ChromeMetrics.glyphSpacing
        var x = areas.right.midX - ChromeMetrics.towardHousing - groupWidth / 2
        drawSignal(at: x, midY: areas.midY, color: color, into: &canvas)
        x += signalWidth + ChromeMetrics.glyphSpacing
        drawWiFi(centerX: x + wifiWidth / 2, midY: areas.midY, color: color, into: &canvas)
        x += wifiWidth + ChromeMetrics.glyphSpacing
        drawBattery(at: x, midY: areas.midY, color: color, into: &canvas)
    }

    private func drawSignal(at x: CGFloat, midY: CGFloat, color: RGBA, into canvas: inout Canvas) {
        let tallest = ChromeMetrics.signalBarHeights.max() ?? 0
        let bottom = midY + tallest / 2
        var left = x
        for height in ChromeMetrics.signalBarHeights {
            canvas.fill(
                CGRect(
                    x: left, y: bottom - height, width: ChromeMetrics.signalBarWidth, height: height
                ),
                cornerRadius: ChromeMetrics.signalBarCornerRadius,
                color: color
            )
            left += ChromeMetrics.signalBarWidth + ChromeMetrics.signalBarSpacing
        }
    }

    private func drawWiFi(centerX: CGFloat, midY: CGFloat, color: RGBA, into canvas: inout Canvas) {
        let outer = ChromeMetrics.wifiBands.last?.outer ?? 0
        let apex = CGPoint(x: centerX, y: midY + outer / 2)
        let halfAngle = ChromeMetrics.wifiHalfAngle
        let steps = 16
        func point(_ radius: CGFloat, _ angle: Double) -> CGPoint {
            // Angles are measured from straight up.
            CGPoint(
                x: apex.x + radius * CGFloat(sin(angle)),
                y: apex.y - radius * CGFloat(cos(angle))
            )
        }
        var path = Path()
        for band in ChromeMetrics.wifiBands {
            path.move(to: point(band.outer, -halfAngle))
            for step in 1...steps {
                path.addLine(
                    to: point(band.outer, -halfAngle + 2 * halfAngle * Double(step) / Double(steps))
                )
            }
            if band.inner > 0 {
                for step in 0...steps {
                    path.addLine(
                        to: point(
                            band.inner, halfAngle - 2 * halfAngle * Double(step) / Double(steps)))
                }
            } else {
                path.addLine(to: apex)
            }
            path.closeSubpath()
        }
        canvas.fill(path, color: color)
    }

    private func drawBattery(at x: CGFloat, midY: CGFloat, color: RGBA, into canvas: inout Canvas) {
        let size = ChromeMetrics.batterySize
        let body = CGRect(x: x, y: midY - size.height / 2, width: size.width, height: size.height)
        let radius = ChromeMetrics.batteryCornerRadius
        let outline = ChromeMetrics.batteryOutlineWidth
        var outlineColor = color
        outlineColor.alpha = UInt8(Double(color.alpha) * ChromeMetrics.batteryOutlineOpacity)
        var ring = Path(roundedRect: body, cornerRadius: radius)
        ring.addPath(
            Path(
                roundedRect: body.insetBy(dx: outline, dy: outline),
                cornerRadius: radius - outline,
                reversed: true
            )
        )
        canvas.fill(ring, color: outlineColor)

        // The Simulator shows a full battery.
        let inset = ChromeMetrics.batteryFillInset
        canvas.fill(
            body.insetBy(dx: inset, dy: inset), cornerRadius: radius - inset, color: color)

        let terminal = ChromeMetrics.batteryTerminalSize
        var terminalColor = color
        terminalColor.alpha = UInt8(Double(color.alpha) * ChromeMetrics.batteryTerminalOpacity)
        // Only the terminal's outer corners are rounded: it is the right half
        // of a rounded rectangle twice as wide.
        let terminalFrame = CGRect(
            x: body.maxX + ChromeMetrics.batteryTerminalGap,
            y: midY - terminal.height / 2,
            width: terminal.width,
            height: terminal.height
        )
        canvas.fill(
            Path(
                roundedRect: CGRect(
                    x: terminalFrame.minX - terminal.width, y: terminalFrame.minY,
                    width: 2 * terminal.width, height: terminal.height),
                cornerRadius: terminal.width
            ),
            clippedTo: terminalFrame,
            color: terminalColor
        )
    }

    /// Draws a notch: a black shape hanging from the top of the screen with
    /// rounded bottom corners, whose sides flare out where they meet the
    /// top edge.
    private func drawNotch(_ frame: CGRect, cornerRadius: CGFloat, into canvas: inout Canvas) {
        // The rounded rectangle reaches above the screen, so only its bottom
        // corners show.
        canvas.fill(
            CGRect(
                x: frame.minX, y: frame.minY - cornerRadius, width: frame.width,
                height: frame.height + cornerRadius),
            cornerRadius: cornerRadius,
            color: .black
        )
        // Each flare is a square beside the notch with a quarter circle cut
        // out of its lower outer corner.
        let flare = ChromeMetrics.notchFlareRadius
        for x in [frame.minX - flare, frame.maxX] {
            let square = CGRect(x: x, y: frame.minY, width: flare, height: flare)
            let center = CGPoint(x: x == frame.maxX ? square.maxX : square.minX, y: square.maxY)
            var path = Path(square)
            path.addPath(
                Path(
                    ellipseIn: CGRect(
                        x: center.x - flare, y: center.y - flare, width: 2 * flare,
                        height: 2 * flare),
                    reversed: true))
            canvas.fill(path, clippedTo: square, color: .black)
        }
    }

    /// Paints the screen's rounded corners black. Only the four corner boxes
    /// are rasterized.
    private func drawScreenCorners(into canvas: inout Canvas) {
        let radius = device.displayCornerRadius
        guard radius > 0 else { return }
        let screen = CGRect(origin: .zero, size: device.screenSize)
        let corners = [
            CGRect(x: 0, y: 0, width: radius, height: radius),
            CGRect(x: screen.maxX - radius, y: 0, width: radius, height: radius),
            CGRect(x: 0, y: screen.maxY - radius, width: radius, height: radius),
            CGRect(x: screen.maxX - radius, y: screen.maxY - radius, width: radius, height: radius),
        ]
        var mask = Path(screen)
        mask.addPath(Path(roundedRect: screen, cornerRadius: radius, reversed: true))
        for corner in corners {
            canvas.fill(mask, clippedTo: corner, color: .black)
        }
    }
}

extension Canvas {
    /// Fills a path, drawing only inside a rectangle.
    fileprivate mutating func fill(_ path: Path, clippedTo rect: CGRect, color: RGBA) {
        let outerClip = clipRect
        defer { clipRect = outerClip }
        let clip = outerClip.map { $0.intersection(rect) } ?? rect
        guard !clip.isNull, clip.width > 0, clip.height > 0 else { return }
        clipRect = clip
        fill(path, color: color)
    }
}
