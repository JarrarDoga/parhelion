import Foundation
import Testing

@testable import ParhelionUI

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 200, height: 200),
    safeAreaInsets: EdgeInsets()
)

private func components(_ color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> [UInt8] {
    [color.red, color.green, color.blue, color.alpha]
}

@MainActor
@Suite("Rendering")
struct RenderingTests {
    @Test("A frame has scale × screen size pixels and a white background")
    func frameSize() {
        let frame = ViewHost(EmptyView(), device: square).render(scale: 3)
        #expect(frame.pixelWidth == 600 && frame.pixelHeight == 600)
        #expect(components(frame.color(at: CGPoint(x: 1, y: 1))) == [255, 255, 255, 255])
    }

    @Test("Colors fill their frames")
    func colorFill() {
        let host = ViewHost(Color.red.frame(width: 50, height: 50), device: square)
        let frame = host.render(scale: 2)
        #expect(components(frame.color(at: CGPoint(x: 100, y: 100))) == [255, 59, 48, 255])
        #expect(components(frame.color(at: CGPoint(x: 70, y: 100))) == [255, 255, 255, 255])
    }

    @Test("A background fills the bounds at its place in the modifier chain")
    func backgroundIncludesPadding() {
        let host = ViewHost(
            Color.clear.frame(width: 20, height: 20).padding(10).background(.blue),
            device: square
        )
        let frame = host.render(scale: 2)
        // 40 × 40 points of blue, centered: from 80 to 120.
        #expect(components(frame.color(at: CGPoint(x: 82, y: 100))) == [0, 122, 255, 255])
        #expect(components(frame.color(at: CGPoint(x: 78, y: 100))) == [255, 255, 255, 255])
    }

    @Test("The outer of two backgrounds is behind the inner one")
    func backgroundOrder() {
        let host = ViewHost(
            Color.clear.frame(width: 20, height: 20)
                .background(.red)
                .padding(10)
                .background(.blue),
            device: square
        )
        let frame = host.render(scale: 2)
        #expect(components(frame.color(at: CGPoint(x: 100, y: 100))) == [255, 59, 48, 255])
        #expect(components(frame.color(at: CGPoint(x: 85, y: 100))) == [0, 122, 255, 255])
    }

    @Test("Text draws in its frame with the inherited foreground style")
    func textInk() throws {
        let host = ViewHost(
            VStack { Text("Hello") }.foregroundStyle(.red),
            device: square
        )
        let text = try #require(host.nodes(withText: "Hello").first?.frame)
        let frame = host.render(scale: 2)

        var inkInside = 0
        var inkOutside = 0
        for y in stride(from: 0.0, to: 200, by: 0.5) {
            for x in stride(from: 0.0, to: 200, by: 0.5) {
                let pixel = components(frame.color(at: CGPoint(x: x, y: y)))
                guard pixel != [255, 255, 255, 255] else { continue }
                if text.insetBy(dx: -1, dy: -1).contains(CGPoint(x: x, y: y)) {
                    inkInside += 1
                    #expect(pixel[0] > pixel[2], "Text ink should be red, found \(pixel)")
                } else {
                    inkOutside += 1
                }
            }
        }
        #expect(inkInside > 50)
        #expect(inkOutside == 0)
    }

    @Test("Button labels use the tint color by default")
    func buttonTint() throws {
        let host = ViewHost(Button("Tap") {}, device: square)
        let label = try #require(host.nodes(withText: "Tap").first?.frame)
        let frame = host.render(scale: 2)
        var sawTint = false
        for y in stride(from: label.minY, to: label.maxY, by: 0.5) {
            for x in stride(from: label.minX, to: label.maxX, by: 0.5) {
                let pixel = components(frame.color(at: CGPoint(x: x, y: y)))
                if pixel == [0, 122, 255, 255] { sawTint = true }
            }
        }
        #expect(sawTint)
    }

    @Test("PNG output decodes to the frame's size")
    func pngHeader() {
        let png = [UInt8](ViewHost(EmptyView(), device: square).render(scale: 1).pngData())
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        // The IHDR chunk holds the width and height, big-endian, at offset 16.
        let width = png[16..<20].reduce(0) { $0 << 8 | Int($1) }
        let height = png[20..<24].reduce(0) { $0 << 8 | Int($1) }
        #expect(width == 200 && height == 200)
    }
}
