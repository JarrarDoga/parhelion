import Foundation
import ParhelionRender
import Testing

@testable import ParhelionTooling

@Suite("Device bezel")
struct DeviceBezelTests {
    let bezel = DeviceBezel(screenWidth: 393, screenHeight: 852, screenCornerRadius: 55)

    @Test("The image is the screen plus a margin on every side")
    func size() {
        #expect(bezel.width == 393 + 2 * DeviceBezel.margin)
        #expect(bezel.height == 852 + 2 * DeviceBezel.margin)
        let image = bezel.image(scale: 2)
        #expect(image.width == Int((bezel.width * 2).rounded()))
        #expect(image.height == Int((bezel.height * 2).rounded()))
    }

    @Test("Points in the window map to points on the screen")
    func screenPoint() {
        let point = bezel.screenPoint(x: DeviceBezel.margin + 10, y: DeviceBezel.margin + 20)
        #expect(point.x == 10 && point.y == 20)
        #expect(bezel.screenPoint(x: 0, y: 0).x < 0)
    }

    @Test("Window positions account for the zoom, then the bezel")
    func windowPoint() {
        let margin = DeviceBezel.margin
        let point = ParhelionTooling.screenPoint(
            windowX: (margin + 10) * 0.5, windowY: (margin + 20) * 0.5, zoom: 0.5, bezel: bezel)
        #expect(abs(point.x - 10) < 1e-9 && abs(point.y - 20) < 1e-9)
        let plain = ParhelionTooling.screenPoint(windowX: 30, windowY: 40, zoom: 2, bezel: nil)
        #expect(plain.x == 15 && plain.y == 20)
    }

    @Test("The screen is a transparent hole, and the bezel covers its square corners")
    func image() {
        let image = bezel.image(scale: 1)
        let margin = Int(DeviceBezel.margin)
        func pixel(_ x: Int, _ y: Int) -> RGBA { image.pixel(x: x, y: y) }
        // The middle of the screen and a point just inside a rounded corner.
        #expect(pixel(margin + 196, margin + 426).alpha == 0)
        #expect(pixel(margin + 20, margin + 20).alpha == 0)
        // The screen's square corner is covered: it lies outside the phone's
        // rounded body.
        #expect(pixel(margin + 1, margin + 1) == DeviceBezel.backdrop)
        // Just outside the screen's curve, the black border shows.
        #expect(pixel(margin + 12, margin + 12) == .black)
        // The window's corner shows the backdrop.
        #expect(pixel(0, 0) == DeviceBezel.backdrop)
        // The metal band, halfway down the left side.
        let bandX = margin - Int(DeviceBezel.border) - Int(DeviceBezel.band) / 2
        #expect(pixel(bandX, margin + 700) == DeviceBezel.bandColor)
    }
}
