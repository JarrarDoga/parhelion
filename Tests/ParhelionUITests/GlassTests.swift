import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

private func gray(_ canvas: Canvas, _ x: Double, _ y: Double) -> Int {
    Int(canvas.pixel(x: Int(x * canvas.scale), y: Int(y * canvas.scale)).red)
}

/// Stripes of black and white, two points wide, under a rectangle.
private func stripes(_ canvas: inout Canvas, _ rect: CGRect) {
    var x = rect.minX
    while x < rect.maxX {
        canvas.fill(CGRect(x: x, y: rect.minY, width: 2, height: rect.height), color: .black)
        x += 4
    }
}

@Suite("Glass")
struct GlassTests {
    let rect = CGRect(x: 40, y: 40, width: 44, height: 44)

    @Test("Small glass over white: a light body, a bright top edge, and a shadow below")
    func smallGlassOverWhite() {
        var canvas = Canvas(width: 124, height: 140, scale: 3)
        canvas.drawGlass(rect, cornerRadius: 22, material: ColorPalette.smallGlass)
        // 252 gray at 60% over white.
        #expect(abs(gray(canvas, 62, 62) - 253) <= 1)
        // The bright line one pixel inside the top edge.
        let edge = (120...122).map { canvas.pixel(x: 62 * 3, y: $0).red }
        #expect(edge.max()! >= 254 && edge.max()! > gray(canvas, 62, 62))
        // The shadow darkens the white just below the bottom edge, and
        // fades out farther down.
        let below = gray(canvas, 62, 85)
        #expect(below < 250 && below > 235)
        #expect(gray(canvas, 62, 120) > below)
        // A faint ring outside the side edges.
        #expect(gray(canvas, 39.9, 62) < 252)
        #expect(canvas.blendMode == .normal)
    }

    @Test("Small glass lightens a gray background")
    func smallGlassOverGray() {
        var canvas = Canvas(
            width: 124, height: 124, scale: 2,
            background: RGBA(red: 242, green: 242, blue: 247))
        canvas.drawGlass(rect, cornerRadius: 22, material: ColorPalette.smallGlass)
        // 0.4 × 242 + 0.6 × 252.
        #expect(abs(gray(canvas, 62, 62) - 248) <= 1)
    }

    @Test("Large glass over the alert's dimmed screen makes the artwork's 235")
    func largeGlass() {
        var canvas = Canvas(
            width: 400, height: 300, scale: 2,
            background: RGBA(red: 205, green: 205, blue: 205))
        let card = CGRect(x: 50, y: 50, width: 300, height: 180)
        canvas.drawGlass(
            card, cornerRadius: 34, style: .continuous, material: ColorPalette.largeGlass)
        #expect(abs(gray(canvas, 200, 140) - 235) <= 1)
        // White lines inside the top and bottom edges.
        #expect(canvas.pixel(x: 400, y: 100).red == 255)
        #expect(canvas.pixel(x: 400, y: 459).red == 255)
        // A dark shadow below the card.
        #expect(gray(canvas, 200, 250) < 190)
    }

    @Test("Tinted glass fills with the tint color")
    func tintedGlass() {
        var canvas = Canvas(width: 124, height: 124, scale: 2)
        let blue = RGBA(red: 0, green: 136, blue: 255)
        canvas.drawGlass(rect, cornerRadius: 22, material: ColorPalette.prominentGlass, tint: blue)
        #expect(canvas.pixel(x: 124, y: 124) == blue)
    }

    @Test("Opacity fades every layer")
    func opacity() {
        var canvas = Canvas(
            width: 124, height: 124, scale: 2, background: RGBA(red: 0, green: 0, blue: 0))
        canvas.drawGlass(
            rect, cornerRadius: 22, material: ColorPalette.prominentGlass,
            tint: .white, opacity: 0.5)
        #expect(abs(gray(canvas, 62, 62) - 128) <= 1)
    }

    @Test("A flat backdrop skips the blur; a busy one is blurred")
    func flatBackdrop() {
        var noBlur = ColorPalette.smallGlass
        noBlur.blurRadius = 0

        // Over a flat color, the blur would change nothing.
        var flat = Canvas(width: 124, height: 124, scale: 2, background: .white)
        #expect(flat.isFlat(rect.insetBy(dx: -9, dy: -9)))
        var reference = flat
        flat.drawGlass(rect, cornerRadius: 22, material: ColorPalette.smallGlass)
        reference.drawGlass(rect, cornerRadius: 22, material: noBlur)
        #expect(flat.pixels == reference.pixels)

        // Over stripes, the blur averages them toward gray.
        var busy = Canvas(width: 124, height: 124, scale: 2, background: .white)
        stripes(&busy, rect.insetBy(dx: -10, dy: -10))
        #expect(!busy.isFlat(rect))
        var sharp = busy
        busy.drawGlass(rect, cornerRadius: 22, material: ColorPalette.smallGlass)
        sharp.drawGlass(rect, cornerRadius: 22, material: noBlur)
        let blurred = (0..<8).map { gray(busy, 50 + Double($0) * 0.5, 62) }
        let unblurred = (0..<8).map { gray(sharp, 50 + Double($0) * 0.5, 62) }
        #expect(blurred.max()! - blurred.min()! < unblurred.max()! - unblurred.min()!)
    }

    @Test("The flatness check sees a hairline and respects the clip")
    func flatness() {
        var canvas = Canvas(width: 100, height: 100, scale: 3)
        let area = CGRect(x: 10, y: 10, width: 50, height: 50)
        canvas.fill(CGRect(x: 0, y: 30, width: 100, height: 1.0 / 3), color: .black)
        #expect(!canvas.isFlat(area))
        #expect(canvas.isFlat(CGRect(x: 10, y: 40, width: 50, height: 20)))
        canvas.clipRect = CGRect(x: 0, y: 50, width: 100, height: 50)
        #expect(canvas.isFlat(area))
    }
}
