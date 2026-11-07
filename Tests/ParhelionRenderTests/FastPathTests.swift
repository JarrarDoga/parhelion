import Foundation
import Testing

@testable import ParhelionRender

/// The drawing paths that skip the general ones for opaque pixels give what the general ones do,
/// to within a level in a channel.
@Suite("Fast drawing paths")
struct FastPathTests {
    private func largestDifference(_ a: Canvas, _ b: Canvas) -> Int {
        var largest = 0
        for (x, y) in zip(a.pixels, b.pixels) { largest = max(largest, abs(Int(x) - Int(y))) }
        return largest
    }

    private func gradient() -> Canvas.LinearGradient {
        Canvas.LinearGradient(
            colors: [
                RGBA(red: 255, green: 40, blue: 20, alpha: 255), .black,
                RGBA(red: 20, green: 90, blue: 230, alpha: 255),
            ],
            start: CGPoint(x: 10, y: 10), end: CGPoint(x: 90, y: 70))
    }

    @Test("A rounded rectangle filled with a gradient matches the general rasterizer")
    func roundedGradient() {
        for scale in [1.0, 2.0] {
            let rect = CGRect(x: 10.3, y: 12.6, width: 70.2, height: 50.7)
            var fast = Canvas(width: 100, height: 80, scale: scale)
            fast.fill(rect, cornerRadius: 12, gradient: gradient())
            var general = Canvas(width: 100, height: 80, scale: scale)
            general.fill(Path(roundedRect: rect, cornerRadius: 12), gradient: gradient())
            #expect(largestDifference(fast, general) <= 8)
            // The inside is exactly the gradient's color at the pixel.
            let inside = fast.pixel(x: Int(40 * scale), y: Int(35 * scale))
            let reference = general.pixel(x: Int(40 * scale), y: Int(35 * scale))
            #expect(abs(Int(inside.red) - Int(reference.red)) <= 2)
            #expect(fast.pixel(x: 0, y: 0).red == 255)
        }
    }

    @Test("A rounded rectangle with a gradient stays inside the clip")
    func gradientClipped() {
        var canvas = Canvas(width: 100, height: 80, scale: 1)
        canvas.clipRect = CGRect(x: 30, y: 20, width: 20, height: 20)
        canvas.fill(
            CGRect(x: 0, y: 0, width: 100, height: 80), cornerRadius: 10, gradient: gradient())
        #expect(canvas.pixel(x: 5, y: 5).red == 255 && canvas.pixel(x: 5, y: 5).blue == 255)
        #expect(canvas.pixel(x: 40, y: 30).blue != 255 || canvas.pixel(x: 40, y: 30).green != 255)
    }

    @Test("A translucent gradient blends over what is beneath it")
    func translucentGradient() {
        let faded = Canvas.LinearGradient(
            colors: [RGBA(red: 0, green: 0, blue: 0, alpha: 128), .clear],
            start: .zero, end: CGPoint(x: 0, y: 50))
        var canvas = Canvas(width: 50, height: 50, scale: 1)
        canvas.fill(CGRect(x: 0, y: 0, width: 50, height: 50), cornerRadius: 0, gradient: faded)
        #expect(canvas.pixel(x: 25, y: 0).red < 140)
        #expect(canvas.pixel(x: 25, y: 49).red > 250)
    }

    @Test("A shadow of a layer darkens around the layer and not far away")
    func layerShadow() {
        var layer = Canvas(width: 40, height: 40, scale: 1, background: .clear)
        layer.fill(CGRect(x: 0, y: 0, width: 40, height: 40), color: .black)
        var canvas = Canvas(width: 200, height: 200, scale: 1)
        canvas.drawShadow(
            ofLayer: layer, atPixelX: 80, y: 80, color: RGBA(red: 0, green: 0, blue: 0, alpha: 128),
            offset: .zero, blur: 20)
        let near = canvas.pixel(x: 76, y: 100)
        let far = canvas.pixel(x: 10, y: 10)
        #expect(near.red < 250 && near.red > 100)
        #expect(far.red == 255)
        // The shadow is symmetric around the layer.
        #expect(
            abs(Int(canvas.pixel(x: 76, y: 100).red) - Int(canvas.pixel(x: 123, y: 100).red)) <= 2)
        #expect(canvas.pixel(x: 100, y: 76).red == canvas.pixel(x: 100, y: 76).green)
    }

    @Test("A shadow over a clear layer keeps the color and gains opacity")
    func shadowOverClear() {
        var layer = Canvas(width: 20, height: 20, scale: 1, background: .clear)
        layer.fill(CGRect(x: 0, y: 0, width: 20, height: 20), color: .black)
        var target = Canvas(width: 100, height: 100, scale: 1, background: .clear)
        target.drawShadow(
            ofLayer: layer, atPixelX: 40, y: 40,
            color: RGBA(red: 10, green: 20, blue: 30, alpha: 200),
            offset: .zero, blur: 10)
        let pixel = target.pixel(x: 50, y: 50)
        #expect(pixel.alpha > 150)
        #expect(pixel.red == 10 && pixel.green == 20 && pixel.blue == 30)
    }

    @Test("A layer with opaque, clear, and translucent pixels draws like pixel by pixel")
    func layerDraw() {
        var layer = Canvas(width: 23, height: 5, scale: 1, background: .clear)
        layer.fill(
            CGRect(x: 2, y: 0, width: 10, height: 5),
            color: RGBA(red: 200, green: 0, blue: 0, alpha: 255))
        layer.fill(
            CGRect(x: 12, y: 0, width: 5, height: 5),
            color: RGBA(red: 0, green: 0, blue: 200, alpha: 100))
        var canvas = Canvas(
            width: 40, height: 10, scale: 1,
            background: RGBA(red: 255, green: 255, blue: 255, alpha: 255))
        canvas.draw(layer: layer, atPixelX: 3, y: 2)
        #expect(canvas.pixel(x: 3, y: 2).red == 255 && canvas.pixel(x: 3, y: 2).green == 255)
        #expect(canvas.pixel(x: 6, y: 3) == RGBA(red: 200, green: 0, blue: 0, alpha: 255))
        let blended = canvas.pixel(x: 16, y: 3)
        #expect(blended.red < 200 && blended.red > 100 && blended.blue > 200 && blended.blue < 255)
        #expect(canvas.pixel(x: 30, y: 3) == RGBA(red: 255, green: 255, blue: 255, alpha: 255))
    }
}
