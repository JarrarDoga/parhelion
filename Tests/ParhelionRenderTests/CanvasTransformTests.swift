import Foundation
import Testing

@testable import ParhelionRender

@Suite("Rotated layers and masks")
struct CanvasTransformTests {
    private func bar() -> Canvas {
        var layer = Canvas(width: 40, height: 10, scale: 1, background: .clear)
        layer.fill(CGRect(x: 0, y: 0, width: 40, height: 10), color: .black)
        return layer
    }

    @Test("A quarter turn clockwise lays a bar on its end, around the pivot")
    func quarterTurn() {
        var canvas = Canvas(width: 100, height: 100, scale: 1)
        // The bar's center is at (50, 50), which is also the pivot.
        canvas.draw(
            layer: bar(), atPixelX: 30, y: 45, rotatedBy: .pi / 2, aroundX: 50, y: 50)
        #expect(canvas.pixel(x: 50, y: 35).red == 0)
        #expect(canvas.pixel(x: 50, y: 65).red == 0)
        #expect(canvas.pixel(x: 35, y: 50).red == 255)
        #expect(canvas.pixel(x: 65, y: 50).red == 255)
    }

    @Test("A turn around a corner swings the layer about that corner")
    func cornerPivot() {
        var canvas = Canvas(width: 100, height: 100, scale: 1)
        // Pivot at the bar's top-left corner (20, 20): the bar hangs down.
        canvas.draw(layer: bar(), atPixelX: 20, y: 20, rotatedBy: .pi / 2, aroundX: 20, y: 20)
        #expect(canvas.pixel(x: 15, y: 40).red == 0)
        #expect(canvas.pixel(x: 40, y: 25).red == 255)
    }

    @Test("A turn that is not a right angle anti-aliases the edges")
    func partCovered() {
        var canvas = Canvas(width: 100, height: 100, scale: 1)
        canvas.draw(layer: bar(), atPixelX: 30, y: 45, rotatedBy: 0.3, aroundX: 50, y: 50)
        let edge = (0..<100).flatMap { y in (0..<100).map { canvas.pixel(x: $0, y: y).red } }
            .filter { $0 > 20 && $0 < 235 }
        #expect(edge.count > 20)
    }

    @Test("Drawing stays inside the clip")
    func clipped() {
        var canvas = Canvas(width: 100, height: 100, scale: 1)
        canvas.clipRect = CGRect(x: 0, y: 0, width: 100, height: 40)
        canvas.draw(
            layer: bar(), atPixelX: 30, y: 45, rotatedBy: .pi / 2, aroundX: 50, y: 50)
        #expect(canvas.pixel(x: 50, y: 35).red == 0)
        #expect(canvas.pixel(x: 50, y: 65).red == 255)
    }

    @Test("A mask scales opacity by the mask's and leaves colors alone")
    func multiply() {
        var layer = Canvas(
            width: 4, height: 1, scale: 1,
            background: RGBA(red: 200, green: 10, blue: 10, alpha: 255))
        var mask = Canvas(width: 4, height: 1, scale: 1, background: .clear)
        mask.fill(
            CGRect(x: 1, y: 0, width: 1, height: 1),
            color: RGBA(red: 0, green: 0, blue: 0, alpha: 128))
        mask.fill(CGRect(x: 2, y: 0, width: 2, height: 1), color: .black)
        layer.multiplyOpacity(by: mask)
        #expect(layer.pixel(x: 0, y: 0).alpha == 0)
        #expect(layer.pixel(x: 1, y: 0).alpha == 128)
        #expect(layer.pixel(x: 1, y: 0).red == 200)
        #expect(layer.pixel(x: 3, y: 0).alpha == 255)
    }
}
