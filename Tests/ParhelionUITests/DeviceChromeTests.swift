import Foundation
import Testing

@testable import ParhelionUI

private func components(_ color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> [UInt8] {
    [color.red, color.green, color.blue, color.alpha]
}

/// The darkest red component among the pixels in a rectangle, sampled
/// every quarter point.
@MainActor
private func darkest(in rect: CGRect, of frame: RenderedFrame) -> UInt8 {
    var darkest = UInt8.max
    var y = rect.minY
    while y < rect.maxY {
        var x = rect.minX
        while x < rect.maxX {
            darkest = min(darkest, frame.color(at: CGPoint(x: x, y: y)).red)
            x += 0.25
        }
        y += 0.25
    }
    return darkest
}

private struct AlertOnLaunch: View {
    @State private var isShowing = true

    var body: some View {
        Text("Content").alert("Saved", isPresented: $isShowing) {}
    }
}

@MainActor
@Suite("Device chrome")
struct DeviceChromeTests {
    let device = Device.iPhone16

    var homeIndicatorCenter: CGPoint {
        CGPoint(x: device.screenSize.width / 2, y: device.screenSize.height - 10.5)
    }

    var leftEar: CGRect {
        CGRect(x: 0, y: 0, width: device.sensorHousing?.frame.minX ?? 0, height: 59)
    }

    var rightEar: CGRect {
        let minX = device.sensorHousing?.frame.maxX ?? 0
        return CGRect(x: minX, y: 0, width: device.screenSize.width - minX, height: 59)
    }

    @Test("Without chrome, only the app's content is drawn")
    func noChrome() {
        let frame = ViewHost(EmptyView(), device: device).render(scale: 1)
        #expect(darkest(in: leftEar, of: frame) == 255)
        #expect(components(frame.color(at: homeIndicatorCenter)) == [255, 255, 255, 255])
        #expect(components(frame.color(at: CGPoint(x: 1, y: 1))) == [255, 255, 255, 255])
    }

    @Test("System bars draw the clock, the status glyphs, and the home indicator")
    func systemBars() throws {
        let frame = ViewHost(EmptyView(), device: device).render(scale: 2, chrome: .systemBars)
        #expect(darkest(in: leftEar, of: frame) == 0)
        #expect(darkest(in: rightEar, of: frame) == 0)
        #expect(components(frame.color(at: homeIndicatorCenter)) == [0, 0, 0, 255])
        // Like a Simulator screenshot: square corners and no Dynamic Island.
        #expect(components(frame.color(at: CGPoint(x: 1, y: 1))) == [255, 255, 255, 255])
        let island = try #require(device.sensorHousing?.frame)
        #expect(
            components(frame.color(at: CGPoint(x: island.midX, y: island.midY)))
                == [255, 255, 255, 255])
    }

    @Test("The screen adds the Dynamic Island and black rounded corners")
    func screen() throws {
        let frame = ViewHost(EmptyView(), device: device).render(scale: 2, chrome: .screen)
        let island = try #require(device.sensorHousing?.frame)
        #expect(
            components(frame.color(at: CGPoint(x: island.midX, y: island.midY))) == [0, 0, 0, 255])
        #expect(components(frame.color(at: CGPoint(x: 1, y: 1))) == [0, 0, 0, 255])
        let bottomRight = CGPoint(x: device.screenSize.width - 1, y: device.screenSize.height - 1)
        #expect(components(frame.color(at: bottomRight)) == [0, 0, 0, 255])
        // Just inside the curve of a corner, the content shows.
        let inside = device.displayCornerRadius * (1 - 1 / 2.squareRoot()) + 2
        #expect(components(frame.color(at: CGPoint(x: inside, y: inside))) == [255, 255, 255, 255])
        #expect(components(frame.color(at: homeIndicatorCenter)) == [0, 0, 0, 255])
    }

    @Test("A notch hangs from the top edge and flares out where it meets it")
    func notch() throws {
        let phone = Device.iPhone16e
        let frame = ViewHost(EmptyView(), device: phone).render(scale: 2, chrome: .screen)
        let notch = try #require(phone.sensorHousing?.frame)
        #expect(components(frame.color(at: CGPoint(x: notch.midX, y: 1))) == [0, 0, 0, 255])
        #expect(
            components(frame.color(at: CGPoint(x: notch.midX, y: notch.maxY - 1)))
                == [0, 0, 0, 255])
        // Just outside the notch at the top edge, the flare is black; lower
        // down, the content shows.
        #expect(components(frame.color(at: CGPoint(x: notch.minX - 1, y: 0.25))) == [0, 0, 0, 255])
        #expect(
            components(frame.color(at: CGPoint(x: notch.minX - 1, y: notch.midY)))
                == [255, 255, 255, 255])
        // The status bar is centered in the top inset, beside the notch.
        let left = CGRect(x: 0, y: 0, width: notch.minX, height: phone.safeAreaInsets.top)
        #expect(darkest(in: left.insetBy(dx: 0, dy: 8), of: frame) == 0)
    }

    @Test("At scale 1 the notch's flares leave no gray fringe beside them")
    func notchFringe() throws {
        let phone = Device.iPhone16e
        let frame = ViewHost(EmptyView(), device: phone).render(scale: 1, chrome: .screen)
        let notch = try #require(phone.sensorHousing?.frame)
        let flare = ChromeMetrics.notchFlareRadius
        // The column just outside each flare, and the row just below it.
        for x in [notch.minX - flare - 1, notch.maxX + flare] {
            for y in stride(from: CGFloat(0.5), to: flare, by: 1) {
                #expect(frame.color(at: CGPoint(x: x + 0.5, y: y)).red == 255)
            }
        }
        for x in stride(from: notch.minX - flare + 0.5, to: notch.minX - 1, by: 1) {
            #expect(frame.color(at: CGPoint(x: x, y: flare + 0.5)).red == 255)
        }
    }

    @Test("An unknown device name lists the presets")
    func unknownDevice() throws {
        #expect(try Device.simulated(named: nil) == .iPhone16)
        #expect(try Device.simulated(named: "iphone 17 pro") == .iPhone17Pro)
        #expect(throws: UnknownDeviceError.self) { try Device.simulated(named: "iPhone 6") }
        let error = UnknownDeviceError(name: "iPhone 6")
        #expect(error.description.hasPrefix("Unknown device \"iPhone 6\". Use one of: iPhone 16,"))
    }

    @Test("ProMotion presets show up to 120 frames per second, the rest 60")
    func frameRates() {
        let sixty: Set<String> = ["iPhone 16", "iPhone 16 Plus", "iPhone 16e"]
        for device in Device.all {
            #expect(
                device.maximumFramesPerSecond == (sixty.contains(device.name) ? 60 : 120),
                "\(device.name)")
        }
        #expect(
            Device(name: "Custom", screenSize: .zero, safeAreaInsets: EdgeInsets())
                .maximumFramesPerSecond == 60)
    }

    @Test("The chrome is drawn once and reused while the scale stays the same")
    func overlayCache() {
        let host = ViewHost(EmptyView(), device: device)
        _ = host.render(scale: 1, chrome: .screen)
        let first = host.chromeOverlayCache?.overlay.width
        _ = host.render(scale: 2, chrome: .screen)
        #expect(first == Int(device.screenSize.width))
        #expect(host.chromeOverlayCache?.overlay.width == Int(device.screenSize.width * 2))
        #expect(host.chromeOverlayCache?.chrome == .screen)
    }

    @Test("The system bars are drawn above presentations, undimmed")
    func aboveAlerts() {
        let frame = ViewHost(AlertOnLaunch(), device: device).render(scale: 1, chrome: .systemBars)
        #expect(components(frame.color(at: homeIndicatorCenter)) == [0, 0, 0, 255])
    }

    @Test("A device without a top inset or a home indicator has no system bars")
    func plainDevice() {
        let plain = Device(
            name: "Plain", screenSize: CGSize(width: 200, height: 200),
            safeAreaInsets: EdgeInsets())
        let frame = ViewHost(EmptyView(), device: plain).render(scale: 1, chrome: .screen)
        #expect(darkest(in: CGRect(x: 0, y: 0, width: 200, height: 200), of: frame) == 255)
    }

    @Test("Screenshots for agents show the system bars")
    func screenshotCommand() throws {
        let host = ViewHost(EmptyView(), device: device)
        let reply = host.execute(.screenshot(scale: 1))
        #expect(reply.png == host.render(scale: 1, chrome: .systemBars).pngData())
    }

    @Test("Every preset's cutout is centered and inside the top safe-area inset")
    func presets() {
        #expect(Set(Device.all.map(\.name)).count == Device.all.count)
        for device in Device.all {
            let housing = device.sensorHousing?.frame ?? .zero
            #expect(abs(housing.midX - device.screenSize.width / 2) < 0.01, "\(device.name)")
            #expect(housing.maxY <= device.safeAreaInsets.top, "\(device.name)")
            #expect(device.displayCornerRadius > 0, "\(device.name)")
            #expect(device.homeIndicatorWidth != nil, "\(device.name)")
        }
    }

    @Test("Presets are found by name, ignoring case, spaces, and punctuation")
    func lookup() {
        #expect(Device.named("iPhone 16") == .iPhone16)
        #expect(Device.named("iphone-16") == .iPhone16)
        #expect(Device.named("IPHONE16") == .iPhone16)
        #expect(Device.named("iPhone 6") == nil)
    }
}
