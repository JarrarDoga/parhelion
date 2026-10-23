import Foundation
import Testing

@testable import ParhelionRender

@Suite("SVG path data")
struct SVGPathTests {
    /// The color at a point of a 1× canvas.
    private func isFilled(_ canvas: Canvas, _ x: Int, _ y: Int) -> Bool {
        canvas.pixel(x: x, y: y).red < 128
    }

    @Test("Arcs draw a ring around an empty center")
    func ring() throws {
        // A circle of radius 40 around (50, 50) with a hole of radius 30,
        // drawn the other way around, as icon sets cut holes.
        let path = try #require(
            Path(
                svgPathData: """
                    M50,10a40,40,0,1,1,0,80a40,40,0,1,1,0-80Z
                    M50,20A30,30,0,1,0,50,80A30,30,0,1,0,50,20Z
                    """))
        var canvas = Canvas(width: 100, height: 100, scale: 1)
        canvas.fill(path, color: .black)
        #expect(!isFilled(canvas, 50, 50))
        #expect(isFilled(canvas, 50, 15))
        #expect(isFilled(canvas, 85, 50))
        #expect(isFilled(canvas, 15, 50))
        #expect(!isFilled(canvas, 50, 95))
        #expect(!isFilled(canvas, 5, 5))
    }

    @Test("Relative, smooth, and implicit commands continue from the current point")
    func commands() throws {
        // A square drawn with h and v, then a smooth curve and a quadratic
        // pair after a move, with numbers that run together.
        let path = try #require(
            Path(svgPathData: "M10 10h20v20H10z m40 0c5-5 10-5 15 0s10 5 15 0q5,5 0,10t-15,0Z"))
        let bounds = try #require(path.controlBounds)
        #expect(bounds.minX == 10)
        #expect(bounds.minY < 10)
        // The quadratic curve's control point is the rightmost point.
        #expect(bounds.maxX == 85)
        var canvas = Canvas(width: 100, height: 40, scale: 1)
        canvas.fill(path, color: .black)
        #expect(isFilled(canvas, 20, 20))
        #expect(!isFilled(canvas, 40, 20))
        // Two numbers can share a decimal point boundary: ".5.5" is 0.5, 0.5.
        #expect(Path(svgPathData: "M.5.5L1,1") != nil)
    }

    @Test("Malformed data is rejected")
    func malformed() {
        #expect(Path(svgPathData: "10,10") == nil)
        #expect(Path(svgPathData: "M10") == nil)
        #expect(Path(svgPathData: "M0,0 A5,5,0,2,0,10,10") == nil)
        #expect(Path(svgPathData: "M0,0 X1,1") == nil)
    }
}
