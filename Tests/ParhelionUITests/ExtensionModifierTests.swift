import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

// A layout modifier that lives in this file only. It registers its behavior
// by name the first time it is used and appears in the tree as data.

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 200, height: 200),
    safeAreaInsets: EdgeInsets()
)

extension View {
    /// Grows the view by `amount` points on every side and paints the
    /// added margin green, behind the view.
    fileprivate func testMargin(_ amount: CGFloat) -> some View {
        customModifier(
            "testMargin", ["amount": formatPoints(amount)],
            behavior: ModifierBehavior(
                size: { parameters, proposal, inner in
                    let amount = CGFloat(Double(parameters["amount"] ?? "") ?? 0)
                    let size = inner(proposal.inset(by: EdgeInsets(.all, amount)))
                    return CGSize(width: size.width + 2 * amount, height: size.height + 2 * amount)
                },
                place: { parameters, rect, _ in
                    rect.insetBy(
                        dx: CGFloat(Double(parameters["amount"] ?? "") ?? 0),
                        dy: CGFloat(Double(parameters["amount"] ?? "") ?? 0))
                },
                drawBehind: { _, _, drawing, canvas in
                    canvas.fill(drawing.frame, color: drawing.color("green"))
                }))
    }

    /// Draws the view at half strength, through an effect.
    fileprivate func testFade() -> some View {
        customModifier(
            "testFade",
            behavior: ModifierBehavior(
                outline: { _ in "testFade!" },
                drawEffect: { _, _, drawing, inside, canvas in
                    inside(&canvas)
                    canvas.fill(
                        drawing.frame, color: RGBA(red: 255, green: 255, blue: 255, alpha: 128))
                }))
    }
}

@MainActor
@Suite("A layout modifier that plugs in from its own file")
struct ExtensionModifierTests {
    @Test("It appears in the outline in its place in the chain, with its parameters")
    func outline() {
        let host = ViewHost(
            Color.red.frame(width: 20, height: 20).testMargin(5).padding(10).testFade(),
            device: square)
        #expect(
            host.root.outline() == """
                Root
                └─ Color frame(width: 20, height: 20) testMargin(amount: 5) padding(10) testFade! color=red
                """)
    }

    @Test("It changes the size and places what it wraps, in order with the other modifiers")
    func layout() {
        let host = ViewHost(Color.red.frame(width: 20, height: 20).testMargin(5), device: square)
        let node = host.root.children[0]
        #expect(node.frame == CGRect(x: 90, y: 90, width: 20, height: 20))
        #expect(node.modifierFrames.last == CGRect(x: 85, y: 85, width: 30, height: 30))
    }

    @Test("It draws behind the view, and its effect draws the view through a function")
    func drawing() {
        let host = ViewHost(Color.red.frame(width: 20, height: 20).testMargin(5), device: square)
        let frame = host.render(scale: 1)
        // The margin is green, and the view is red.
        #expect(frame.color(at: CGPoint(x: 87, y: 100)).red < 100)
        #expect(frame.color(at: CGPoint(x: 87, y: 100)).green > 150)
        #expect(frame.color(at: CGPoint(x: 80, y: 100)).red > 200)
        #expect(frame.color(at: CGPoint(x: 90, y: 90)).red > 200)

        let faded = ViewHost(Color.red.frame(width: 20, height: 20).testFade(), device: square)
        let pixel = faded.render(scale: 1).color(at: CGPoint(x: 100, y: 100))
        // Red, then white at half strength.
        #expect(pixel.red == 255)
        #expect(pixel.green > 100 && pixel.green < 200)
    }

    @Test("It survives encoding the tree as JSON")
    func codable() throws {
        let host = ViewHost(Color.red.testMargin(3), device: square)
        let data = try JSONEncoder().encode(host.root)
        let decoded = try JSONDecoder().decode(ViewNode.self, from: data)
        #expect(decoded.children[0].modifiers == host.root.children[0].modifiers)
    }
}
