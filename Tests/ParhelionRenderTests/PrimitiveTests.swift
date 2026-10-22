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

@Suite("Shadows")
struct ShadowTests {
    @Test("A shadow is centered on its offset and symmetric")
    func centered() {
        var canvas = Canvas(width: 64, height: 64, scale: 1)
        canvas.drawShadow(
            of: CGRect(x: 24, y: 24, width: 16, height: 16), cornerRadius: 4, color: .black,
            offset: CGSize(width: 4, height: -2), blur: 8, drawsUnderShape: true)
        // The shadow's center is at (36, 30), between pixels 35 and 36 and
        // between rows 29 and 30.
        var total = 0
        var sumX = 0
        var sumY = 0
        for y in 0..<64 {
            for x in 0..<64 {
                let value = darkness(canvas, x, y)
                total += value
                sumX += value * x
                sumY += value * y
                if 71 - x < 64 { #expect(abs(value - darkness(canvas, 71 - x, y)) <= 1) }
            }
        }
        #expect(abs(Double(sumX) / Double(total) + 0.5 - 36) < 0.1)
        #expect(abs(Double(sumY) / Double(total) + 0.5 - 30) < 0.1)
        #expect(darkness(canvas, 35, 29) > 200)
    }

    @Test("A shadow fades with distance and leaves pixels past its reach untouched")
    func reach() {
        for blur in [4.0, 20.0] {
            var canvas = Canvas(width: 64, height: 64, scale: 1)
            canvas.drawShadow(
                of: Path(CGRect(x: 26, y: 26, width: 12, height: 12)), color: .black, blur: blur)
            let reach = BlurKernel(sigma: blur / 2).pixelReach
            for x in 38..<min(38 + reach, 63) {
                #expect(darkness(canvas, x, 32) >= darkness(canvas, x + 1, 32))
            }
            #expect(darkness(canvas, 38, 32) > darkness(canvas, 44, 32))
            for y in 0..<64 {
                for x in 0..<64
                where x < 26 - reach || x >= 38 + reach || y < 26 - reach || y >= 38 + reach {
                    #expect(canvas.pixel(x: x, y: y) == .white)
                }
            }
        }
        // A small blur reaches exactly its boxes' radii.
        #expect(BlurKernel(sigma: 2).factor == 1)
        #expect(BlurKernel(sigma: 2).pixelReach == 4)
    }

    @Test("By default a shadow is cut away under its shape")
    func knockout() {
        var canvas = Canvas(width: 48, height: 48, scale: 1)
        canvas.drawShadow(
            of: CGRect(x: 16, y: 16, width: 16, height: 16), cornerRadius: 0,
            color: RGBA(red: 0, green: 0, blue: 0, alpha: 128), blur: 6)
        #expect(canvas.pixel(x: 24, y: 24) == .white)
        #expect(canvas.pixel(x: 16, y: 16) == .white)
        #expect(darkness(canvas, 15, 24) > 30)
        var under = Canvas(width: 48, height: 48, scale: 1)
        under.drawShadow(
            of: CGRect(x: 16, y: 16, width: 16, height: 16), cornerRadius: 0,
            color: RGBA(red: 0, green: 0, blue: 0, alpha: 128), blur: 6, drawsUnderShape: true)
        #expect(darkness(under, 24, 24) > 120)
        // Outside the shape both agree.
        #expect(under.pixel(x: 10, y: 24) == canvas.pixel(x: 10, y: 24))
    }

    @Test("A shadow stays inside the clip, even when its shape is outside it")
    func clip() {
        var canvas = Canvas(width: 48, height: 48, scale: 1)
        canvas.clipRect = CGRect(x: 0, y: 0, width: 24, height: 48)
        canvas.drawShadow(
            of: Path(CGRect(x: 28, y: 16, width: 16, height: 16)), color: .black, blur: 12)
        #expect(darkness(canvas, 23, 24) > 0)
        for y in 0..<48 {
            for x in 24..<48 { #expect(canvas.pixel(x: x, y: y) == .white) }
        }
    }

    @Test("A wide, downsampled shadow is still symmetric and smooth")
    func downsampled() {
        var canvas = Canvas(width: 64, height: 64, scale: 2)
        canvas.drawShadow(
            of: CGRect(x: 22, y: 22, width: 20, height: 20), cornerRadius: 10, color: .black,
            blur: 24, drawsUnderShape: true)
        #expect(BlurKernel(sigma: 24).factor > 1)
        for x in 0..<64 {
            #expect(abs(darkness(canvas, x, 64) - darkness(canvas, 127 - x, 64)) <= 2)
        }
        for x in 64..<127 {
            #expect(darkness(canvas, x, 64) >= darkness(canvas, x + 1, 64))
        }
    }
}

@Suite("Rings")
struct RingTests {
    @Test("A ring lies inside, centered on, or outside the edge")
    func alignment() {
        let rect = CGRect(x: 10, y: 10, width: 40, height: 30)
        for (alignment, dark) in [
            (Path.StrokeAlignment.inside, [10, 11]), (.center, [9, 10]), (.outside, [8, 9]),
        ] {
            var canvas = Canvas(width: 60, height: 50, scale: 1)
            canvas.stroke(rect, cornerRadius: 0, lineWidth: 2, alignment: alignment, color: .black)
            for x in 6..<14 {
                // The left side, on the middle row, and the top, in the
                // middle column.
                #expect(darkness(canvas, x, 25) == (dark.contains(x) ? 255 : 0))
                #expect(darkness(canvas, 30, x) == (dark.contains(x) ? 255 : 0))
            }
            #expect(canvas.pixel(x: 30, y: 25) == .white)
        }
    }

    @Test("A one-pixel hairline covers exactly one row of pixels")
    func hairline() {
        var canvas = Canvas(width: 40, height: 30, scale: 3)
        canvas.stroke(
            CGRect(x: 5, y: 5, width: 30, height: 20), cornerRadius: 10, style: .continuous,
            lineWidth: 1.0 / 3, alignment: .inside, color: .black)
        #expect(darkness(canvas, 60, 15) == 255)
        #expect(darkness(canvas, 60, 14) == 0)
        #expect(darkness(canvas, 60, 16) == 0)
    }

    @Test(
        "A rounded ring matches the general rasterizer, without seams",
        arguments: [1.0, 2.0, 3.0])
    func fastPath(scale: Double) {
        let rect = CGRect(x: 5.3, y: 4.7, width: 38.2, height: 22.9)
        for style in [Path.CornerStyle.circular, .continuous] {
            for alignment in [Path.StrokeAlignment.inside, .center, .outside] {
                var fast = Canvas(width: 50, height: 32, scale: scale)
                fast.stroke(
                    rect, cornerRadius: 9, style: style, lineWidth: 1.5, alignment: alignment,
                    color: .black)
                var general = Canvas(width: 50, height: 32, scale: scale)
                general.fill(
                    Path(
                        ringAround: rect, cornerRadius: 9, style: style, lineWidth: 1.5,
                        alignment: alignment),
                    color: .black)
                #expect(largestDifference(fast, general) <= 3)
            }
        }
    }
}

@Suite("Gradients")
struct GradientTests {
    @Test("A vertical gradient has its end colors at its ends and the middle between")
    func vertical() {
        var canvas = Canvas(width: 4, height: 100, scale: 1)
        canvas.fill(
            CGRect(x: 0, y: 0, width: 4, height: 100),
            gradient: Canvas.LinearGradient(
                colors: [.black, .white], start: .zero, end: CGPoint(x: 0, y: 100)))
        for y in 0..<100 {
            let expected = (Double(y) + 0.5) / 100 * 255
            #expect(abs(Double(canvas.pixel(x: 2, y: y).red) - expected) <= 1)
            #expect(canvas.pixel(x: 0, y: y) == canvas.pixel(x: 3, y: y))
        }
        #expect(canvas.pixel(x: 0, y: 0).red <= 2)
        #expect(canvas.pixel(x: 0, y: 99).red >= 253)
        #expect((126...129).contains(canvas.pixel(x: 0, y: 50).red))
    }

    @Test("Gradients run horizontally and at any angle, and pad past their ends")
    func angles() {
        var horizontal = Canvas(width: 20, height: 2, scale: 1)
        horizontal.fill(
            CGRect(x: 0, y: 0, width: 20, height: 2),
            gradient: Canvas.LinearGradient(
                colors: [.black, .white], start: CGPoint(x: 5, y: 0), end: CGPoint(x: 15, y: 0)))
        #expect(horizontal.pixel(x: 0, y: 0) == .black)
        #expect(horizontal.pixel(x: 4, y: 1) == .black)
        #expect(horizontal.pixel(x: 19, y: 0) == .white)
        #expect(horizontal.pixel(x: 9, y: 0).red < horizontal.pixel(x: 10, y: 0).red)

        var diagonal = Canvas(width: 16, height: 16, scale: 1)
        diagonal.fill(
            CGRect(x: 0, y: 0, width: 16, height: 16),
            gradient: Canvas.LinearGradient(
                colors: [.black, .white], start: .zero, end: CGPoint(x: 16, y: 16)))
        for y in 0..<16 {
            for x in 0..<16 {
                // Lines perpendicular to the gradient have one color.
                #expect(diagonal.pixel(x: x, y: y) == diagonal.pixel(x: y, y: x))
                if x > 0, y < 15 {
                    #expect(
                        abs(
                            Int(diagonal.pixel(x: x, y: y).red)
                                - Int(diagonal.pixel(x: x - 1, y: y + 1).red)) <= 1)
                }
            }
        }
    }

    @Test("A fade to clear stays the same color as it fades")
    func premultiplied() {
        var canvas = Canvas(width: 2, height: 100, scale: 1, background: .black)
        canvas.fill(
            CGRect(x: 0, y: 0, width: 2, height: 100),
            gradient: Canvas.LinearGradient(
                colors: [RGBA(red: 255, green: 255, blue: 255, alpha: 153), .clear],
                start: .zero, end: CGPoint(x: 0, y: 100)))
        // Halfway, white at 30% over black.
        #expect((75...78).contains(canvas.pixel(x: 0, y: 50).red))
        #expect(canvas.pixel(x: 0, y: 99).red <= 2)
        #expect((150...153).contains(canvas.pixel(x: 0, y: 0).red))
    }

    @Test("Stops can be placed anywhere, and paths take gradients too")
    func stops() {
        var canvas = Canvas(width: 100, height: 4, scale: 1)
        canvas.fill(
            Path(CGRect(x: 0, y: 0, width: 100, height: 4)),
            gradient: Canvas.LinearGradient(
                stops: [
                    .init(color: .black, location: 0), .init(color: .white, location: 0.2),
                    .init(color: .black, location: 1),
                ],
                start: .zero, end: CGPoint(x: 100, y: 0)))
        #expect(canvas.pixel(x: 20, y: 0).red >= 252)
        #expect(canvas.pixel(x: 10, y: 0).red < 140 && canvas.pixel(x: 10, y: 0).red > 115)
        #expect(canvas.pixel(x: 60, y: 0).red < 130 && canvas.pixel(x: 60, y: 0).red > 125)
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

@Suite("Region blur")
struct RegionBlurTests {
    @Test("Blurring a flat color leaves it exactly as it was", arguments: [3.0, 10.0, 40.0])
    func flat(radius: Double) {
        let color = RGBA(red: 12, green: 200, blue: 77)
        var canvas = Canvas(width: 48, height: 40, scale: 1, background: color)
        let original = canvas
        canvas.blur(
            CGRect(x: 4.5, y: 3, width: 30, height: 30), cornerRadius: 12, style: .continuous,
            radius: radius)
        canvas.blur(CGRect(x: 0, y: 0, width: 48, height: 40), radius: radius, saturation: 1)
        #expect(canvas.pixels == original.pixels)
    }

    @Test("Blurring spreads an edge symmetrically", arguments: [4.0, 30.0])
    func edge(radius: Double) {
        var canvas = Canvas(width: 64, height: 8, scale: 1, background: .black)
        canvas.fill(CGRect(x: 32, y: 0, width: 32, height: 8), color: .white)
        canvas.blur(CGRect(x: 0, y: 0, width: 64, height: 8), radius: radius)
        for x in 0..<32 {
            let left = Int(canvas.pixel(x: 31 - x, y: 4).red)
            let right = Int(canvas.pixel(x: 32 + x, y: 4).red)
            #expect(abs(left + right - 255) <= 2)
            #expect(left <= Int(canvas.pixel(x: 32 - x, y: 4).red))
        }
        #expect(canvas.pixel(x: 31, y: 4).red > 40)
        #expect(canvas.pixel(x: 0, y: 0) == canvas.pixel(x: 0, y: 7))
    }

    @Test("A blur changes only pixels inside its shape and the clip")
    func clip() {
        var canvas = Canvas(width: 40, height: 40, scale: 1)
        for x in stride(from: 0, to: 40, by: 2) {
            canvas.fill(CGRect(x: Double(x), y: 0, width: 1, height: 40), color: .black)
        }
        let original = canvas
        canvas.clipRect = CGRect(x: 0, y: 0, width: 20, height: 40)
        canvas.blur(CGRect(x: 10, y: 10, width: 20, height: 20), cornerRadius: 6, radius: 6)
        for y in 0..<40 {
            for x in 0..<40 where x >= 20 || x < 10 || y < 10 || y >= 30 {
                #expect(canvas.pixel(x: x, y: y) == original.pixel(x: x, y: y))
            }
        }
        // Inside, the stripes blur to gray; the rounded corner pixel is
        // left alone.
        #expect((100...155).contains(canvas.pixel(x: 15, y: 20).red))
        #expect(canvas.pixel(x: 10, y: 10) == original.pixel(x: 10, y: 10))
    }

    @Test("Saturation 1 is the identity, 0 is gray, and 2 moves away from gray")
    func saturation() {
        let color = RGBA(red: 200, green: 120, blue: 60)
        var canvas = Canvas(width: 8, height: 8, scale: 1, background: color)
        canvas.fill(
            CGRect(x: 0, y: 0, width: 4, height: 8), color: RGBA(red: 10, green: 90, blue: 250))
        let original = canvas
        canvas.blur(CGRect(x: 0, y: 0, width: 8, height: 8), radius: 0, saturation: 1)
        #expect(canvas.pixels == original.pixels)

        var gray = original
        gray.blur(CGRect(x: 0, y: 0, width: 8, height: 8), radius: 0, saturation: 0)
        let pixel = gray.pixel(x: 6, y: 3)
        #expect(
            abs(Int(pixel.red) - Int(pixel.green)) <= 1
                && abs(Int(pixel.green) - Int(pixel.blue)) <= 1)
        // 0.2126 R + 0.7152 G + 0.0722 B, as CSS's matrix rounds it.
        #expect(abs(Int(pixel.red) - 133) <= 1)

        var vivid = original
        vivid.blur(CGRect(x: 0, y: 0, width: 8, height: 8), radius: 0, saturation: 2)
        let saturated = vivid.pixel(x: 6, y: 3)
        #expect(saturated.red > color.red && saturated.blue < color.blue)
    }
}
