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

    @Test("The screen is a transparent hole, and so is everything outside the phone")
    func image() {
        let image = bezel.image(scale: 1)
        let margin = Int(DeviceBezel.margin)
        func pixel(_ x: Int, _ y: Int) -> RGBA { image.pixel(x: x, y: y) }
        // The middle of the screen and a point just inside a rounded corner.
        #expect(pixel(margin + 196, margin + 426).alpha == 0)
        #expect(pixel(margin + 20, margin + 20).alpha == 0)
        // Just outside the screen's curve, the black border shows.
        #expect(pixel(margin + 12, margin + 12) == .black)
        // Outside the phone's rounded body, at the window's corner, nothing
        // is drawn.
        #expect(pixel(0, 0).alpha == 0)
        // The metal band, halfway down the left side.
        let bandX = margin - Int(DeviceBezel.border) - Int(DeviceBezel.band) / 2
        #expect(pixel(bandX, margin + 700) == DeviceBezel.bandColor)
    }

    @Test("Only the frame's corners outside the phone's body are masked")
    func frameMasks() throws {
        let masks = bezel.frameMasks(scale: 2)
        #expect(masks.count == 4)
        let topLeft = try #require(masks.first)
        #expect(topLeft.x == 0 && topLeft.y == 0 && topLeft.width == 110)
        // The frame's very corner is outside the body, and a point on the
        // screen's diagonal past the body's curve is inside it.
        #expect(topLeft.alpha[0] == 0)
        #expect(topLeft.alpha[40 * topLeft.width + 40] == 255)
        let bottomRight = try #require(masks.last)
        #expect(bottomRight.x == 786 - 110 && bottomRight.y == 1704 - 110)
        #expect(bottomRight.alpha.last == 0)
    }
}
