import Foundation
import Testing

@testable import ParhelionRender

/// Draws Liquid Glass approximations with the drawing primitives, following
/// the recipes Apple's iOS 27 UI Kit uses: glass buttons over a busy
/// background, an alert, and a scroll edge effect. Set `PARHELION_DEMO_DIR`
/// to a directory to write the PNGs there and look at them.
@Suite(
    "Glass demo",
    .enabled(if: ProcessInfo.processInfo.environment["PARHELION_DEMO_DIR"] != nil)
)
struct GlassDemoTests {
    let directory = ProcessInfo.processInfo.environment["PARHELION_DEMO_DIR"] ?? ""

    func write(_ canvas: Canvas, _ name: String) throws {
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        try Data(canvas.pngData()).write(to: url)
    }

    @Test("Glass buttons over a busy background")
    func glassButtons() throws {
        for scale in [2.0, 3.0] {
            var canvas = GlassScenes.busyBackground(width: 240, height: 160, scale: scale)
            GlassScenes.smallGlass(
                &canvas, CGRect(x: 24, y: 58, width: 67, height: 44), label: "Label")
            GlassScenes.smallGlass(&canvas, CGRect(x: 110, y: 58, width: 44, height: 44), label: "")
            GlassScenes.smallGlass(
                &canvas, CGRect(x: 24, y: 112, width: 192, height: 44), label: "Wide glass")
            // The same disc as Apple's materials artwork: a large glass
            // circle with a light tint.
            GlassScenes.smallGlass(&canvas, CGRect(x: 168, y: 20, width: 64, height: 64), label: "")
            try write(canvas, "c1-glass-button@\(Int(scale))x.png")
        }
    }

    @Test("An alert card with a shadow")
    func alert() throws {
        // The HIG's alert artwork is 536 pixels wide for a 402-point screen.
        for scale in [4.0 / 3.0, 3.0] {
            var canvas = Canvas(width: 402, height: 874, scale: scale, background: .white)
            for row in 0..<16 {
                canvas.drawText(
                    "Row \(row + 1) of the screen behind the alert", font: .interRegular,
                    size: 17, origin: CGPoint(x: 20, y: 120 + Double(row) * 44), color: .black)
                canvas.fill(
                    CGRect(x: 20, y: 132 + Double(row) * 44, width: 382, height: 0.5),
                    color: RGBA(red: 60, green: 60, blue: 67, alpha: 74))
            }
            canvas.fill(
                CGRect(x: 0, y: 0, width: 402, height: 874),
                color: RGBA(red: 41, green: 41, blue: 58, alpha: 59))
            GlassScenes.alert(&canvas, CGRect(x: 51, y: 355, width: 300, height: 162))
            try write(canvas, "c1-alert@\(scale == 3 ? "3" : "1.33")x.png")
        }
    }

    @Test("A scroll edge effect under a glass button")
    func scrollEdge() throws {
        var canvas = Canvas(width: 402, height: 300, scale: 3, background: .white)
        for row in 0..<12 {
            let y = Double(row) * 44 - 20
            canvas.fill(
                CGRect(x: 16, y: y + 6, width: 32, height: 32), cornerRadius: 8,
                style: .continuous,
                color: [
                    RGBA(red: 255, green: 56, blue: 60), RGBA(red: 0, green: 136, blue: 255),
                    RGBA(red: 52, green: 199, blue: 89),
                ][row % 3])
            canvas.drawText(
                "Scrolled row \(row + 1)", font: .interRegular, size: 17,
                origin: CGPoint(x: 60, y: y + 28), color: .black)
        }
        GlassScenes.scrollEdge(&canvas, width: 402, height: 77)
        GlassScenes.smallGlass(&canvas, CGRect(x: 342, y: 16, width: 44, height: 44), label: "")
        GlassScenes.smallGlass(&canvas, CGRect(x: 16, y: 16, width: 67, height: 44), label: "Edit")
        try write(canvas, "c1-scroll-edge@3x.png")
    }
}

/// The demo's scenes and glass recipes. These live in tests: the glass
/// styles themselves belong in ParhelionUI.
enum GlassScenes {
    /// A beach-like picture with clouds, sea, driftwood, and text: busy
    /// enough that a blur shows.
    static func busyBackground(width: Double, height: Double, scale: Double) -> Canvas {
        var canvas = Canvas(width: width, height: height, scale: scale)
        canvas.fill(
            CGRect(x: 0, y: 0, width: width, height: height * 0.55),
            gradient: Canvas.LinearGradient(
                colors: [
                    RGBA(red: 30, green: 90, blue: 190), RGBA(red: 150, green: 195, blue: 240),
                ],
                start: .zero, end: CGPoint(x: 0, y: height * 0.55)))
        canvas.fill(
            CGRect(x: 0, y: height * 0.55, width: width, height: height * 0.45),
            gradient: Canvas.LinearGradient(
                colors: [
                    RGBA(red: 236, green: 222, blue: 196), RGBA(red: 214, green: 196, blue: 170),
                ],
                start: CGPoint(x: 0, y: height * 0.55), end: CGPoint(x: 0, y: height)))
        canvas.fill(
            CGRect(x: width * 0.5, y: height * 0.5, width: width * 0.5, height: height * 0.1),
            color: RGBA(red: 64, green: 196, blue: 190))
        for (x, y, w) in [(0.1, 0.05, 0.3), (0.55, 0.12, 0.35), (0.3, 0.3, 0.2), (0.8, 0.35, 0.25)]
        {
            canvas.fill(
                Path(
                    ellipseIn: CGRect(
                        x: width * x, y: height * y, width: width * w, height: height * w * 0.4)),
                color: RGBA(red: 255, green: 255, blue: 255, alpha: 220))
        }
        var wood = Path()
        wood.move(to: CGPoint(x: width * 0.05, y: height * 0.62))
        wood.addLine(to: CGPoint(x: width * 0.75, y: height * 0.92))
        wood.addLine(to: CGPoint(x: width * 0.72, y: height * 0.97))
        wood.addLine(to: CGPoint(x: width * 0.02, y: height * 0.67))
        wood.closeSubpath()
        canvas.fill(wood, color: RGBA(red: 70, green: 52, blue: 40))
        canvas.drawText(
            "Busy content under glass", font: .interSemiBold, size: 15,
            origin: CGPoint(x: 8, y: height * 0.5), color: RGBA(red: 20, green: 20, blue: 20))
        return canvas
    }

    /// Small glass in light mode, from the kit's toolbar button: blur 6
    /// with saturation 2, a tint stack that works out to about
    /// 0.45 × backdrop + 132, a darkened 0.5-point rim, specular lines
    /// inside the top and bottom edges, and a faint drop shadow.
    static func smallGlass(_ canvas: inout Canvas, _ rect: CGRect, label: String) {
        let radius = min(rect.width, rect.height) / 2
        let pixel = 1 / canvas.scale
        canvas.drawShadow(
            of: rect, cornerRadius: radius, color: RGBA(red: 0, green: 0, blue: 0, alpha: 13),
            offset: CGSize(width: 0, height: 6), blur: 18)
        canvas.blur(rect, cornerRadius: radius, radius: 6, saturation: 2)
        // The kit's luminosity fill acts like a normal one over gray.
        canvas.fill(
            rect, cornerRadius: radius, color: RGBA(red: 248, green: 248, blue: 248, alpha: 51))
        canvas.fill(rect, cornerRadius: radius, color: RGBA(red: 0, green: 0, blue: 0, alpha: 64))
        canvas.fill(
            rect, cornerRadius: radius, color: RGBA(red: 255, green: 255, blue: 255, alpha: 64))
        canvas.blendMode = .plusLighter
        canvas.fill(
            rect, cornerRadius: radius, color: RGBA(red: 68, green: 68, blue: 68, alpha: 153))
        // Specular lines one pixel inside the top and bottom edges, fading
        // toward the middle.
        canvas.fill(
            Path(
                ringAround: rect, cornerRadius: radius, lineWidth: pixel * 1.5, alignment: .inside),
            gradient: Canvas.LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: RGBA(red: 255, green: 255, blue: 255, alpha: 0), location: 0.35),
                    .init(color: RGBA(red: 255, green: 255, blue: 255, alpha: 0), location: 0.7),
                    .init(color: RGBA(red: 255, green: 255, blue: 255, alpha: 120), location: 1),
                ],
                start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY)))
        canvas.blendMode = .plusDarker
        canvas.stroke(
            rect, cornerRadius: radius, lineWidth: 0.5, alignment: .outside,
            color: RGBA(red: 219, green: 219, blue: 219))
        canvas.blendMode = .normal
        if !label.isEmpty {
            let size = 17.0
            let width = TrueTypeFont.interSemiBold.width(of: label, size: size)
            canvas.drawText(
                label, font: .interSemiBold, size: size,
                origin: CGPoint(x: Double(rect.midX) - width / 2, y: Double(rect.midY) + 6),
                color: RGBA(red: 20, green: 20, blue: 20))
        } else {
            // A placeholder symbol.
            canvas.fill(
                Path(ellipseIn: rect.insetBy(dx: rect.width * 0.36, dy: rect.height * 0.36)),
                color: RGBA(red: 20, green: 20, blue: 20))
        }
    }

    /// An iOS 27 alert: large glass (blur 30, saturation 1.4, white 70%
    /// lighten and 191 gray 10% darken, about 0.27 × backdrop + 180), a
    /// 0.3-point rim, a white line inside the bottom edge, and a drop
    /// shadow of black 25%, y 18, blur 46.
    static func alert(_ canvas: inout Canvas, _ rect: CGRect) {
        let radius: CGFloat = 34
        canvas.drawShadow(
            of: rect, cornerRadius: radius, style: .continuous,
            color: RGBA(red: 0, green: 0, blue: 0, alpha: 64), offset: CGSize(width: 0, height: 18),
            blur: 46)
        canvas.blur(rect, cornerRadius: radius, style: .continuous, radius: 30, saturation: 1.4)
        canvas.blendMode = .lighten
        canvas.fill(
            rect, cornerRadius: radius, style: .continuous,
            color: RGBA(red: 255, green: 255, blue: 255, alpha: 179))
        canvas.blendMode = .darken
        canvas.fill(
            rect, cornerRadius: radius, style: .continuous,
            color: RGBA(red: 191, green: 191, blue: 191, alpha: 26))
        canvas.blendMode = .plusLighter
        canvas.fill(
            Path(
                ringAround: rect, cornerRadius: radius, style: .continuous, lineWidth: 1.5,
                alignment: .inside),
            gradient: Canvas.LinearGradient(
                stops: [
                    .init(color: RGBA(red: 255, green: 255, blue: 255, alpha: 90), location: 0),
                    .init(color: RGBA(red: 255, green: 255, blue: 255, alpha: 0), location: 0.25),
                    .init(color: RGBA(red: 255, green: 255, blue: 255, alpha: 0), location: 0.6),
                    .init(color: .white, location: 1),
                ],
                start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY)))
        canvas.blendMode = .plusDarker
        canvas.stroke(
            rect, cornerRadius: radius, style: .continuous, lineWidth: 0.5, alignment: .outside,
            color: RGBA(red: 200, green: 200, blue: 200))
        canvas.blendMode = .normal

        let left = Double(rect.minX) + 22
        canvas.drawText(
            "Alert Title", font: .interSemiBold, size: 17,
            origin: CGPoint(x: left, y: Double(rect.minY) + 39), color: .black)
        canvas.drawText(
            "A description of the alert.", font: .interRegular, size: 17,
            origin: CGPoint(x: left, y: Double(rect.minY) + 71),
            color: RGBA(red: 74, green: 74, blue: 74))
        let buttonY = rect.maxY - 14 - 48
        let secondary = CGRect(x: rect.minX + 14, y: buttonY, width: 132, height: 48)
        let primary = CGRect(x: rect.minX + 154, y: buttonY, width: 132, height: 48)
        canvas.fill(
            secondary, cornerRadius: 24, color: RGBA(red: 118, green: 118, blue: 128, alpha: 31))
        canvas.fill(primary, cornerRadius: 24, color: RGBA(red: 0, green: 136, blue: 255))
        for (button, title, font, color) in [
            (secondary, "Secondary", TrueTypeFont.interSemiBold, RGBA.black),
            (primary, "Primary", TrueTypeFont.interSemiBold, RGBA.white),
        ] {
            let width = font.width(of: title, size: 17)
            canvas.drawText(
                title, font: font, size: 17,
                origin: CGPoint(x: Double(button.midX) - width / 2, y: Double(button.midY) + 6),
                color: color)
        }
    }

    /// The scroll edge effect: white fading from 60% to clear over the
    /// content under the top bar. Apple also blurs the content there with a
    /// blur that fades out; a region blur has a hard edge, so the gradient
    /// alone is the closer approximation.
    static func scrollEdge(_ canvas: inout Canvas, width: Double, height: Double) {
        canvas.fill(
            CGRect(x: 0, y: 0, width: width, height: height),
            gradient: Canvas.LinearGradient(
                colors: [RGBA(red: 255, green: 255, blue: 255, alpha: 153), .clear],
                start: .zero, end: CGPoint(x: 0, y: height)))
    }
}
