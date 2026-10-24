import Foundation
import Testing

@testable import ParhelionRender

@Suite("Luminosity blending")
struct LuminosityBlendTests {
    @Test("A gray source over a gray backdrop acts as normal blending")
    func grayOverGray() {
        var luminosity = Canvas(
            width: 1, height: 1, scale: 1, background: RGBA(red: 200, green: 200, blue: 200))
        luminosity.blendMode = .luminosity
        luminosity.fill(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            color: RGBA(red: 26, green: 26, blue: 26, alpha: 230))
        var normal = Canvas(
            width: 1, height: 1, scale: 1, background: RGBA(red: 200, green: 200, blue: 200))
        normal.fill(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            color: RGBA(red: 26, green: 26, blue: 26, alpha: 230))
        let a = luminosity.pixel(x: 0, y: 0)
        let b = normal.pixel(x: 0, y: 0)
        #expect(abs(Int(a.red) - Int(b.red)) <= 1)
        #expect(a.red == a.green && a.green == a.blue)
    }

    @Test("Over a color, the backdrop's hue stays and the source's luminosity replaces its own")
    func keepsHue() {
        var canvas = Canvas(
            width: 1, height: 1, scale: 1, background: RGBA(red: 200, green: 40, blue: 40))
        canvas.blendMode = .luminosity
        canvas.fill(
            CGRect(x: 0, y: 0, width: 1, height: 1), color: RGBA(red: 26, green: 26, blue: 26))
        let pixel = canvas.pixel(x: 0, y: 0)
        // Still red, but as dark as the source: Lum = 0.3 R + 0.59 G + 0.11 B.
        #expect(pixel.red > pixel.green && pixel.green == pixel.blue)
        let luminosity =
            0.3 * Double(pixel.red) + 0.59 * Double(pixel.green) + 0.11 * Double(pixel.blue)
        #expect(abs(luminosity - 26) < 1.5)
    }
}
