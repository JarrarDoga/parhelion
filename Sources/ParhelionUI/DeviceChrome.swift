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
/// These are iOS 27's, from the iPhone 17 Pro status bar in Apple's iOS 27
/// UI Kit for Sketch (v27.1.2). Assumed: no device capture has confirmed
/// them yet, and Parhelion uses the same sizes on every device.
enum ChromeMetrics {
    /// The status bar's clock, which the Simulator shows as 9:41.
    static let time = "9:41"
    /// The clock is SF Pro Semibold at 17.67 points. Parhelion draws it with
    /// Inter SemiBold.
    static let timeFontSize = 17.67

    /// How far the clock's center sits from the center of the area to the
    /// left of the sensor housing, toward the housing. Negative values move
    /// it toward the screen's edge.
    static let timeTowardHousing: CGFloat = -2
    /// How far the glyphs' center sits from the center of the area to the
    /// right of the housing, toward the housing.
    static let glyphsTowardHousing: CGFloat = -1

    /// The cellular signal glyph's four fully rounded bars, bottom-aligned.
    static let signalBarWidth: CGFloat = 3.33
    static let signalBarSpacing: CGFloat = 2.33
    static let signalBarHeights: [CGFloat] = [6.33, 8.67, 11, 13.67]
    static let signalBarCornerRadius: CGFloat = 3.33 / 2

    /// The Wi-Fi glyph: three bands of a fan whose point is at the bottom,
    /// 19.33 × 14.33 points. Each band is given as its inner and outer
    /// radius.
    static let wifiBands: [(inner: CGFloat, outer: CGFloat)] = [
        (0, 4.4), (6.3, 9.4), (11.2, 14.33),
    ]
    /// The fan opens this far to each side of vertical, so that it is 19.33
    /// points wide.
    static let wifiHalfAngle = asin(9.665 / 14.33)

    /// The battery glyph: a solid body, which shows a full charge, and a
    /// translucent terminal to its right. Assumed: the terminal's opacity.
    static let batterySize = CGSize(width: 26.33, height: 13.67)
    static let batteryCornerRadius: CGFloat = 4.33
    static let batteryTerminalSize = CGSize(width: 2, height: 5)
    static let batteryTerminalGap: CGFloat = 1
    static let batteryTerminalOpacity = 0.5

    /// The space between the glyphs on the right of the status bar.
    static let glyphSpacing: CGFloat = 8

    /// Assumed: the radius of the curves where a notch's sides flare out to
    /// meet the top of the screen, measured on the iPhone 14's bezel.
    static let notchFlareRadius: CGFloat = 5.67

    /// The home indicator: a 5-point capsule whose bottom is 8 points above
    /// the bottom of the screen. Its width varies by device.
    static let homeIndicatorHeight: CGFloat = 5
    static let homeIndicatorBottomMargin: CGFloat = 8
}

extension TreeRenderer {
    /// The system interface drawn once, to blend over every frame. It
    /// depends only on the device, the scale, the kind of chrome, and the
    /// color scheme, so the host keeps it between frames.
    func chromeOverlay(
        _ chrome: DeviceChrome, scale: Double, colorScheme: ColorScheme
    )
        -> CanvasOverlay
    {
        var canvas = Canvas(
            width: Double(device.screenSize.width),
            height: Double(device.screenSize.height),
            scale: scale,
            background: RGBA(red: 0, green: 0, blue: 0, alpha: 0)
        )
        drawChrome(chrome, colorScheme: colorScheme, into: &canvas)
        return CanvasOverlay(canvas)
    }

    /// Draws the system interface. It reads only the device and the color
    /// scheme, not the tree. The status bar and the home indicator are black
    /// in light and white in dark; the Dynamic Island stays black.
    private func drawChrome(
        _ chrome: DeviceChrome, colorScheme: ColorScheme, into canvas: inout Canvas
    ) {
        guard chrome != .none else { return }
        let color = ColorPalette.appearance(colorScheme).systemBarForeground
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
        // take the outer third of the status bar. Without a Dynamic Island,
        // as beside a notch, they are centered in the top safe-area inset.
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

        // The clock is centered near the middle of the area to the left of
        // the housing, with its digits centered on the bar's midline.
        let font = TrueTypeFont.interSemiBold
        let size = ChromeMetrics.timeFontSize
        let timeWidth = font.width(of: ChromeMetrics.time, size: size)
        let capHeight = font.capHeight(size: size)
        canvas.drawText(
            ChromeMetrics.time,
            font: font,
            size: size,
            origin: CGPoint(
                x: Double(areas.left.midX + ChromeMetrics.timeTowardHousing) - timeWidth / 2,
                y: Double(areas.midY) + capHeight / 2
            ),
            color: color
        )

        // The signal, Wi-Fi, and battery glyphs are placed as a group near
        // the middle of the area to the right, sharing a midline with the
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
        var x = areas.right.midX - ChromeMetrics.glyphsTowardHousing - groupWidth / 2
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
        // The Simulator shows a full battery, which iOS 27 draws solid.
        canvas.fill(body, cornerRadius: ChromeMetrics.batteryCornerRadius, color: color)

        let terminal = ChromeMetrics.batteryTerminalSize
        var terminalColor = color
        terminalColor.alpha = UInt8(Double(color.alpha) * ChromeMetrics.batteryTerminalOpacity)
        // Only the terminal's outer corners are rounded.
        let terminalFrame = CGRect(
            x: body.maxX + ChromeMetrics.batteryTerminalGap,
            y: midY - terminal.height / 2,
            width: terminal.width,
            height: terminal.height
        )
        var terminalPath = Path()
        terminalPath.move(to: CGPoint(x: terminalFrame.minX, y: terminalFrame.minY))
        terminalPath.addQuadCurve(
            to: CGPoint(x: terminalFrame.maxX, y: terminalFrame.minY + terminal.width),
            control: CGPoint(x: terminalFrame.maxX, y: terminalFrame.minY))
        terminalPath.addLine(
            to: CGPoint(x: terminalFrame.maxX, y: terminalFrame.maxY - terminal.width))
        terminalPath.addQuadCurve(
            to: CGPoint(x: terminalFrame.minX, y: terminalFrame.maxY),
            control: CGPoint(x: terminalFrame.maxX, y: terminalFrame.maxY))
        terminalPath.closeSubpath()
        canvas.fill(terminalPath, color: terminalColor)
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
        // Each flare runs along the top edge, down the notch's side, and
        // back up along a quarter circle curving away from the notch.
        let flare = ChromeMetrics.notchFlareRadius
        for (wall, outward) in [(frame.minX, -1.0), (frame.maxX, 1.0)] {
            let center = CGPoint(x: wall + outward * flare, y: frame.minY + flare)
            var path = Path()
            path.move(to: CGPoint(x: center.x, y: frame.minY))
            path.addLine(to: CGPoint(x: wall, y: frame.minY))
            path.addLine(to: CGPoint(x: wall, y: center.y))
            let steps = 8
            for step in 1...steps {
                // From pointing at the wall to pointing straight up.
                let angle = Double.pi / 2 * Double(step) / Double(steps)
                path.addLine(
                    to: CGPoint(
                        x: center.x - outward * flare * CGFloat(cos(angle)),
                        y: center.y - flare * CGFloat(sin(angle))))
            }
            path.closeSubpath()
            canvas.fill(path, color: .black)
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
