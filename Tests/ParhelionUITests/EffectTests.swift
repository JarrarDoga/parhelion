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

private let white: [UInt8] = [255, 255, 255, 255]
private let red: [UInt8] = [255, 56, 60, 255]
private let blue: [UInt8] = [0, 136, 255, 255]

@MainActor
@Suite("Effects")
struct EffectTests {
    @Test("An overlay's views are an Overlay child, placed in the view's bounds")
    func overlayNodes() {
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100)
                .overlay(alignment: .topTrailing) {
                    Text("New")
                },
            device: square
        )
        #expect(
            host.root.outline(includeIDs: true) == """
                Root
                └─ Color frame(width: 100, height: 100) overlay(alignment: topTrailing) color=red  #Color
                   └─ Overlay  #Color/overlay
                      └─ Text "New"  #Color/overlay/Text
                """)
        let color = host.root.children[0]
        #expect(color.frame == CGRect(x: 50, y: 50, width: 100, height: 100))
        let overlay = color.children[0]
        #expect(overlay.frame == CGRect(x: 50, y: 50, width: 100, height: 100))
        let text = overlay.children[0]
        #expect(text.frame?.maxX == 150)
        #expect(text.frame?.minY == 50)
    }

    @Test("An overlay does not change the size, and covers the bounds at its place in the chain")
    func overlayPlacement() {
        let host = ViewHost(
            HStack(spacing: 0) {
                Color.red.frame(width: 40, height: 40).padding(10)
                    .overlay { Color.blue }
                Color.red.frame(width: 40, height: 40)
                    .overlay { Color.blue }
                    .overlay(alignment: .bottom) { Color.green.frame(height: 5) }
                    .padding(10)
            },
            device: square
        )
        let stack = host.root.children[0]
        #expect(stack.frame?.size == CGSize(width: 120, height: 60))
        // The first overlay covers the padding; the second does not.
        #expect(stack.children[0].children[0].frame?.size == CGSize(width: 60, height: 60))
        let second = stack.children[1]
        #expect(second.children.map(\.id) == ["HStack/1/Color/overlay", "HStack/1/Color/overlay2"])
        #expect(second.children[0].frame?.size == CGSize(width: 40, height: 40))
        #expect(second.children[1].children[0].frame?.maxY == second.frame?.maxY)

        let frame = host.render(scale: 1)
        #expect(components(frame.color(at: CGPoint(x: 45, y: 72))) == blue)
        #expect(components(frame.color(at: CGPoint(x: 130, y: 100))) == blue)
        #expect(components(frame.color(at: CGPoint(x: 105, y: 100))) == white)
        #expect(components(frame.color(at: CGPoint(x: 130, y: 118))) == [52, 199, 89, 255])
    }

    @Test("A button in an overlay is frontmost, and an overlay is not part of a label")
    func overlayInput() throws {
        let host = ViewHost(
            CounterOverlay(),
            device: square
        )
        let button = try #require(host.root.allNodes.first { $0.kind == "Button" })
        #expect(button.label == "Covered")
        try host.tap(at: CGPoint(x: 100, y: 100))
        #expect(host.nodes(withText: "Badge 1").count == 1)
    }

    @Test("A shape style over a view fills its bounds")
    func overlayStyle() {
        let host = ViewHost(
            Color.blue.frame(width: 100, height: 100)
                .overlay(.red, in: Circle())
                .overlay(Color.white.opacity(0.5)),
            device: square
        )
        #expect(
            host.root.children[0].modifiers.map(\.outlineDescription) == [
                "frame(width: 100, height: 100)", "overlay(red, in: Circle)", "overlay(white@0.5)",
            ])
        let frame = host.render(scale: 1)
        #expect(components(frame.color(at: CGPoint(x: 100, y: 100))) == [255, 156, 158, 255])
        #expect(components(frame.color(at: CGPoint(x: 52, y: 52))) == [128, 196, 255, 255])
    }

    @Test("A clip shape clips what is inside it in the chain, and not what is outside")
    func clipShape() {
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100)
                .background(.green)
                .clipShape(Circle())
                .padding(10)
                .background(.blue),
            device: square
        )
        #expect(
            host.root.children[0].modifiers.map(\.outlineDescription) == [
                "frame(width: 100, height: 100)", "background(green)", "clipShape(Circle)",
                "padding(10)", "background(blue)",
            ])
        let frame = host.render(scale: 2)
        #expect(components(frame.color(at: CGPoint(x: 100, y: 100))) == red)
        // The circle's bounding box corner shows the outer background.
        #expect(components(frame.color(at: CGPoint(x: 52, y: 52))) == blue)
        #expect(components(frame.color(at: CGPoint(x: 42, y: 100))) == blue)
    }

    @Test("A clip applies to an overlay inside it, and not to one outside it")
    func clipAndOverlayOrder() {
        let host = ViewHost(
            HStack(spacing: 0) {
                Color.red.frame(width: 100, height: 100)
                    .overlay { Color.blue }
                    .clipShape(Circle())
                Color.red.frame(width: 100, height: 100)
                    .clipShape(Circle())
                    .overlay(alignment: .topLeading) { Color.blue.frame(width: 10, height: 10) }
            },
            device: square
        )
        let frame = host.render(scale: 1)
        #expect(components(frame.color(at: CGPoint(x: 50, y: 100))) == blue)
        #expect(components(frame.color(at: CGPoint(x: 2, y: 52))) == white)
        #expect(components(frame.color(at: CGPoint(x: 102, y: 52))) == blue)
        #expect(components(frame.color(at: CGPoint(x: 115, y: 55))) == white)
    }

    // `cornerRadius(_:antialiased:)` is deprecated only on Apple platforms.
    @Test("Corner radius clips to circular corners")
    func cornerRadius() {
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100).cornerRadius(20),
            device: square
        )
        #expect(host.root.children[0].modifiers.last?.outlineDescription == "cornerRadius(20)")
        let frame = host.render(scale: 2)
        #expect(components(frame.color(at: CGPoint(x: 51, y: 51))) == white)
        #expect(components(frame.color(at: CGPoint(x: 56, y: 70))) == red)
        #expect(components(frame.color(at: CGPoint(x: 100, y: 51))) == red)
    }

    @Test("A path clip with the even-odd rule leaves a hole")
    func evenOddClip() {
        let ring = Path { path in
            path.addRect(CGRect(x: 0, y: 0, width: 100, height: 100))
            path.addRect(CGRect(x: 25, y: 25, width: 50, height: 50))
        }
        let host = ViewHost(
            Color.red.frame(width: 100, height: 100).clipShape(
                ring, style: FillStyle(eoFill: true)),
            device: square
        )
        #expect(
            host.root.children[0].modifiers.last?.outlineDescription == "clipShape(Path, eoFill)")
        let frame = host.render(scale: 1)
        // A path ignores the bounds, so it clips at the top-leading corner
        // of the screen: the color at 50...150 shows only from 50 to 100,
        // outside the hole from 25 to 75.
        #expect(components(frame.color(at: CGPoint(x: 90, y: 90))) == red)
        #expect(components(frame.color(at: CGPoint(x: 60, y: 60))) == white)
        #expect(components(frame.color(at: CGPoint(x: 120, y: 120))) == white)
    }

    @Test("A shadow is drawn under what the view draws, offset and blurred")
    func shadow() {
        let host = ViewHost(
            VStack(spacing: 0) {
                Color.white.frame(width: 100, height: 40).shadow(radius: 4, y: 2)
                Text("A").shadow(color: .red, radius: 0, x: 3)
            },
            device: square
        )
        let stack = host.root.children[0]
        #expect(stack.children[0].modifiers.last?.outlineDescription == "shadow(radius: 4, y: 2)")
        #expect(
            stack.children[1].modifiers.last?.outlineDescription
                == "shadow(color: red, radius: 0, x: 3)")
        let frame = host.render(scale: 2)
        let color = stack.children[0].frame!
        // Just below the white rectangle, the shadow darkens the screen.
        let below = frame.color(at: CGPoint(x: color.midX, y: color.maxY + 1))
        #expect(below.red < 235 && below.red == below.blue)
        // Inside the rectangle, the view covers its shadow.
        #expect(components(frame.color(at: CGPoint(x: color.midX, y: color.midY))) == white)
        // Far away, there is no shadow.
        #expect(components(frame.color(at: CGPoint(x: color.midX, y: color.maxY + 16))) == white)
    }

    @Test("Scale effects draw scaled around their anchor without changing layout")
    func scaleEffect() {
        let host = ViewHost(
            VStack(spacing: 0) {
                Color.red.frame(width: 40, height: 40).scaleEffect(1.5)
                Color.blue.frame(width: 40, height: 40)
                    .scaleEffect(x: 2, y: 0.5, anchor: .topLeading)
            },
            device: square
        )
        let stack = host.root.children[0]
        #expect(stack.children[0].modifiers.last?.outlineDescription == "scaleEffect(1.5)")
        #expect(
            stack.children[1].modifiers.last?.outlineDescription
                == "scaleEffect(x: 2, y: 0.5, anchor: topLeading)")
        #expect(stack.children[0].frame == CGRect(x: 80, y: 60, width: 40, height: 40))
        #expect(stack.children[1].frame == CGRect(x: 80, y: 100, width: 40, height: 40))
        let frame = host.render(scale: 2)
        // The red square grows from 80...120 to 70...130 around its center.
        #expect(components(frame.color(at: CGPoint(x: 72, y: 80))) == red)
        #expect(components(frame.color(at: CGPoint(x: 68, y: 80))) == white)
        // The blue square doubles in width and halves in height from its
        // top-leading corner.
        #expect(components(frame.color(at: CGPoint(x: 155, y: 105))) == blue)
        #expect(components(frame.color(at: CGPoint(x: 100, y: 125))) == white)
    }

    @Test("A negative scale mirrors the drawing")
    func mirroredScale() {
        let content = HStack(spacing: 0) {
            Color.red.frame(width: 20, height: 20)
            Color.blue.frame(width: 20, height: 20)
        }
        let host = ViewHost(content.scaleEffect(x: -1), device: square)
        let frame = host.render(scale: 2)
        // Mirrored, blue is on the left: 80...100.
        #expect(components(frame.color(at: CGPoint(x: 90, y: 100))) == blue)
        #expect(components(frame.color(at: CGPoint(x: 110, y: 100))) == red)
    }
}

/// A button whose label an overlay covers, with a button in the overlay.
private struct CounterOverlay: View {
    @State private var count = 0

    var body: some View {
        Button("Covered") {}
            .frame(width: 100, height: 100)
            .overlay {
                Button("Badge \(count)") { count += 1 }
                    .frame(width: 60, height: 60)
            }
    }
}
