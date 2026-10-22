import Foundation
import Testing

@testable import ParhelionRender

/// How far apart two canvases' bytes are, at most.
private func largestDifference(_ a: Canvas, _ b: Canvas) -> Int {
    zip(a.pixels, b.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
}

/// How dark a pixel is on a white canvas, from 0 to 255.
private func darkness(_ canvas: Canvas, _ x: Int, _ y: Int) -> Int {
    255 - Int(canvas.pixel(x: x, y: y).red)
}

@Suite("Continuous corners")
struct ContinuousCornerTests {
    func filled(_ style: Path.CornerStyle, radius: CGFloat = 20, scale: Double = 1) -> Canvas {
        var canvas = Canvas(width: 64, height: 64, scale: scale)
        canvas.fill(
            Path(
                roundedRect: CGRect(x: 2, y: 2, width: 60, height: 60), cornerRadius: radius,
                style: style),
            color: .black)
        return canvas
    }

    @Test("A cubic curve flattens to points on the curve")
    func cubicFlattening() {
        // A quarter circle of radius 100 as one cubic curve.
        var path = Path()
        path.move(to: CGPoint(x: 100, y: 0))
        path.addCurve(
            to: CGPoint(x: 0, y: 100), control1: CGPoint(x: 100, y: 55.2285),
            control2: CGPoint(x: 55.2285, y: 100))
        let coarse = path.polygons(tolerance: 1)
        let fine = path.polygons(tolerance: 0.05)
        #expect(fine[0].count > coarse[0].count)
        for polygon in [coarse[0], fine[0]] {
            #expect(polygon.last == CGPoint(x: 0, y: 100))
            for point in polygon {
                let radius = (Double(point.x * point.x + point.y * point.y)).squareRoot()
                #expect(abs(radius - 100) < 0.05)
            }
        }
        // Chord midpoints stay within the tolerance of the circle.
        for (a, b) in zip(fine[0], fine[0].dropFirst()) {
            let x = Double(a.x + b.x) / 2
            let y = Double(a.y + b.y) / 2
            #expect(100 - (x * x + y * y).squareRoot() < 0.05 + 0.03)
        }
    }

    @Test("Continuous corners leave the edge earlier than circular ones")
    func direction() {
        // With a radius of 16, the circular corner meets the top edge 18
        // points from the canvas edge and the continuous one 26.5. At scale
        // 4, curves are flattened finely enough to compare.
        let circular = filled(.circular, radius: 16, scale: 4)
        let continuous = filled(.continuous, radius: 16, scale: 4)
        var circularInk = 0
        var continuousInk = 0
        for x in 0..<256 {
            let circularEdge = darkness(circular, x, 8)
            let continuousEdge = darkness(continuous, x, 8)
            circularInk += circularEdge
            continuousInk += continuousEdge
            // Along the edge a continuous corner never has more ink.
            #expect(continuousEdge <= circularEdge + 2)
            if (76...100).contains(x) {
                #expect(circularEdge == 255)
                #expect(continuousEdge < 255)
            }
            if (108...148).contains(x) { #expect(continuousEdge == 255) }
        }
        #expect(continuousInk < circularInk - 1000)
        // At the diagonal the continuous curve passes 0.2915 radii from each
        // edge, the circle 0.2929: a hair more ink.
        for d in 20...36 {
            #expect(darkness(continuous, d, d) >= darkness(circular, d, d))
            #expect(darkness(continuous, d, d) - darkness(circular, d, d) <= 40)
        }
    }

    @Test("Continuous corners are symmetric")
    func symmetry() {
        let canvas = filled(.continuous)
        for y in 0..<64 {
            for x in 0..<64 {
                let value = darkness(canvas, x, y)
                #expect(abs(value - darkness(canvas, 63 - x, y)) <= 1)
                #expect(abs(value - darkness(canvas, x, 63 - y)) <= 1)
                #expect(abs(value - darkness(canvas, y, x)) <= 1)
            }
        }
    }

    @Test("A continuous capsule is a circular capsule")
    func capsule() {
        var circular = Canvas(width: 64, height: 32, scale: 4)
        circular.fill(
            Path(roundedRect: CGRect(x: 2, y: 4, width: 60, height: 24), cornerRadius: 12),
            color: .black)
        var continuous = Canvas(width: 64, height: 32, scale: 4)
        continuous.fill(
            Path(
                roundedRect: CGRect(x: 2, y: 4, width: 60, height: 24), cornerRadius: 12,
                style: .continuous),
            color: .black)
        // The circular path's quadratic curves bulge out by 0.3% of the
        // radius between their ends, and both are flattened to within 0.2
        // pixels, so edge pixels differ by up to a third.
        #expect(largestDifference(circular, continuous) <= 80)
        #expect(
            Path.cornerExtent(
                of: CGRect(x: 0, y: 0, width: 60, height: 24), cornerRadius: 12, style: .continuous)
                == 12)
        // Shorter sides blend between the two.
        let extent = Path.cornerExtent(
            of: CGRect(x: 0, y: 0, width: 60, height: 30), cornerRadius: 12, style: .continuous)
        #expect(extent > 12 && extent <= 15)
    }

    @Test("The circular style is the existing rounded rectangle")
    func circularUnchanged() {
        let rect = CGRect(x: 3.3, y: 2.7, width: 40.2, height: 25.9)
        var old = Canvas(width: 50, height: 32, scale: 2)
        old.fill(Path(roundedRect: rect, cornerRadius: 8, reversed: true), color: .black)
        var new = Canvas(width: 50, height: 32, scale: 2)
        new.fill(
            Path(roundedRect: rect, cornerRadius: 8, style: .circular, reversed: true),
            color: .black)
        #expect(old.pixels == new.pixels)
    }

    @Test(
        "A continuous rounded rectangle matches the general rasterizer, without seams",
        arguments: [1.0, 2.0, 3.0])
    func fastPath(scale: Double) {
        let rect = CGRect(x: 3.3, y: 2.7, width: 40.2, height: 25.9)
        let color = RGBA(red: 0, green: 0, blue: 255)
        for radius: CGFloat in [4, 8, 12.95] {
            var fast = Canvas(width: 50, height: 32, scale: scale, background: .white)
            fast.fill(rect, cornerRadius: radius, style: .continuous, color: color)
            var general = Canvas(width: 50, height: 32, scale: scale, background: .white)
            general.fill(
                Path(roundedRect: rect, cornerRadius: radius, style: .continuous), color: color)
            #expect(largestDifference(fast, general) <= 3)
        }
    }

    @Test("A reversed continuous rectangle cuts a hole")
    func reversedHole() throws {
        var ring = Path(
            roundedRect: CGRect(x: 0, y: 0, width: 20, height: 20), cornerRadius: 6,
            style: .continuous)
        ring.addPath(
            Path(
                roundedRect: CGRect(x: 5, y: 5, width: 10, height: 10), cornerRadius: 3,
                style: .continuous, reversed: true))
        let coverage = try #require(
            Rasterizer.coverage(of: ring.polygons(tolerance: 0.1), clipWidth: 20, clipHeight: 20))
        #expect(coverage.values[10 * coverage.width + 10] < 0.01)
        #expect(coverage.values[10 * coverage.width + 2] > 0.99)
    }
}

@Suite("Blend modes")
struct BlendModeTests {
    let backdrop = RGBA(red: 200, green: 100, blue: 50)

    func blended(_ mode: Canvas.BlendMode, _ color: RGBA) -> RGBA {
        var canvas = Canvas(width: 2, height: 1, scale: 1, background: backdrop)
        canvas.blendMode = mode
        canvas.fill(CGRect(x: 0, y: 0, width: 1, height: 1), color: color)
        canvas.fill(Path(CGRect(x: 1, y: 0, width: 1, height: 1)), color: color)
        // The rectangle and path fills agree.
        #expect(canvas.pixel(x: 0, y: 0) == canvas.pixel(x: 1, y: 0))
        return canvas.pixel(x: 0, y: 0)
    }

    @Test("Each mode combines opaque colors as specified")
    func opaque() {
        let source = RGBA(red: 100, green: 150, blue: 255)
        #expect(blended(.normal, source) == source)
        #expect(blended(.multiply, source) == RGBA(red: 78, green: 59, blue: 50))
        #expect(blended(.screen, source) == RGBA(red: 222, green: 191, blue: 255))
        #expect(blended(.lighten, source) == RGBA(red: 200, green: 150, blue: 255))
        #expect(blended(.darken, source) == RGBA(red: 100, green: 100, blue: 50))
        #expect(blended(.plusLighter, source) == RGBA(red: 255, green: 250, blue: 255))
        #expect(blended(.plusDarker, source) == RGBA(red: 45, green: 0, blue: 50))
    }

    @Test("Glass highlights and rims shift the backdrop by fixed levels")
    func glassLevels() {
        // White at 40% plus-lighter: +102 levels.
        #expect(
            blended(.plusLighter, RGBA(red: 255, green: 255, blue: 255, alpha: 102))
                == RGBA(red: 255, green: 202, blue: 152))
        // 219 gray plus-darker: −36 levels.
        #expect(
            blended(.plusDarker, RGBA(red: 219, green: 219, blue: 219))
                == RGBA(red: 164, green: 64, blue: 14))
    }

    @Test("Translucent sources mix the mode's result with the backdrop")
    func translucent() {
        let source = RGBA(red: 100, green: 150, blue: 255, alpha: 128)
        let half = 128.0 / 255
        func mixed(_ full: Double, _ back: UInt8) -> UInt8 {
            UInt8((Double(back) + (full - Double(back)) * half).rounded())
        }
        let multiply = blended(.multiply, source)
        #expect(abs(Int(multiply.red) - Int(mixed(200 * 100 / 255, 200))) <= 1)
        #expect(abs(Int(multiply.green) - Int(mixed(100 * 150 / 255, 100))) <= 1)
        let darken = blended(.darken, source)
        #expect(abs(Int(darken.red) - Int(mixed(100, 200))) <= 1)
        #expect(darken.blue == 50)
        #expect(darken.alpha == 255)
    }

    @Test("Over a transparent backdrop a mode draws the source as it is")
    func transparentBackdrop() {
        var canvas = Canvas(width: 1, height: 1, scale: 1, background: .clear)
        canvas.blendMode = .multiply
        canvas.fill(
            CGRect(x: 0, y: 0, width: 1, height: 1), color: RGBA(red: 10, green: 20, blue: 30))
        #expect(canvas.pixel(x: 0, y: 0) == RGBA(red: 10, green: 20, blue: 30))
    }
}
