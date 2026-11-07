import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

// A view kind that lives in this file only: it registers how it is laid
// out, drawn, and hit the first time it is evaluated, and no shared file
// knows about it. See docs/adr/0011-extension-seam.md.

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 200, height: 200),
    safeAreaInsets: EdgeInsets()
)

/// Two bars side by side in a fixed size; a press and a drag on it are
/// recorded.
private struct TestMeter: View {
    typealias Body = Never

    @MainActor static var longPresses: [(CGPoint, TimeInterval)] = []
    @MainActor static var drags: [(CGPoint, CGPoint, TimeInterval)] = []

    var body: Never { fatalError("TestMeter is a primitive view.") }
}

extension TestMeter: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        NodeExtensions.registerOnce(kind: "TestMeter") {
            NodeBehavior(
                size: { _, _, proposal, _ in
                    CGSize(width: min(proposal.width ?? 80, 80), height: 20)
                },
                place: { engine, node, rect in
                    // Children are squeezed into the left half.
                    node.children.map {
                        engine.place(
                            $0,
                            in: CGRect(
                                x: rect.minX, y: rect.minY, width: rect.width / 2,
                                height: rect.height), parentAxis: nil)
                    }
                },
                draw: { _, _, drawing, canvas in
                    canvas.fill(drawing.frame, color: drawing.color("red"))
                },
                // Only the left half is hit.
                hitTest: { node, point in
                    guard let frame = node.frame else { return false }
                    return CGRect(
                        x: frame.minX, y: frame.minY, width: frame.width / 2, height: frame.height
                    ).contains(point)
                })
        }
        let id = path.appending("TestMeter").id
        evaluator.registerInputHandlers(
            NodeInputHandlers(
                longPress: { point, duration in TestMeter.longPresses.append((point, duration)) },
                drag: { start, end, duration in TestMeter.drags.append((start, end, duration)) }),
            for: id)
        return [ViewNode(id: id, kind: "TestMeter", children: [])]
    }
}

@MainActor
@Suite("A view kind that plugs in from its own file", .serialized)
struct ExtensionKindTests {
    @Test("Its size comes from its registered behavior")
    func size() {
        let host = ViewHost(TestMeter(), device: square)
        #expect(
            host.root.outline(includeFrames: true) == """
                Root  [0, 0, 200 × 200]
                └─ TestMeter  [60, 90, 80 × 20]
                """)
    }

    @Test("Its registered size is wrapped by the layout modifiers around it")
    func modifiers() {
        let host = ViewHost(TestMeter().padding(10), device: square)
        let node = host.root.children[0]
        #expect(node.frame == CGRect(x: 60, y: 90, width: 80, height: 20))
        #expect(node.modifierFrames.last == CGRect(x: 50, y: 80, width: 100, height: 40))
    }

    @Test("It draws itself, and a hit test of its own decides where it is hit")
    func drawAndHit() throws {
        let host = ViewHost(TestMeter(), device: square)
        let frame = host.render(scale: 1)
        // Drawn in the foreground red the palette names for "red".
        #expect(frame.color(at: CGPoint(x: 100, y: 100)).red > 200)
        #expect(frame.color(at: CGPoint(x: 10, y: 10)).red == 255)
        TestMeter.longPresses = []
        try host.longPress(at: CGPoint(x: 70, y: 100), duration: 1)
        #expect(TestMeter.longPresses.count == 1)
        #expect(TestMeter.longPresses.first?.1 == 1)
        // The right half is not part of the node.
        #expect(throws: InteractionError.nothingTappable(at: CGPoint(x: 130, y: 100))) {
            try host.longPress(at: CGPoint(x: 130, y: 100))
        }
    }

    @Test("A long press where nothing handles one throws, and a drag reaches its handler")
    func inputEntryPoints() throws {
        let host = ViewHost(TestMeter(), device: square)
        #expect(throws: InteractionError.nothingTappable(at: CGPoint(x: 5, y: 5))) {
            try host.longPress(at: CGPoint(x: 5, y: 5))
        }
        TestMeter.drags = []
        host.drag(from: CGPoint(x: 70, y: 100), to: CGPoint(x: 90, y: 100), duration: 0.5)
        #expect(TestMeter.drags.count == 1)
        #expect(TestMeter.drags.first?.1 == CGPoint(x: 90, y: 100))
        #expect(TestMeter.drags.first?.2 == 0.5)
        // A drag that starts elsewhere falls through to the pointer.
        host.drag(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 50))
        #expect(TestMeter.drags.count == 1)
    }

    @Test("A drag over a scroll view scrolls it, as a pointer drag does")
    func dragScrolls() throws {
        let host = ViewHost(
            ScrollView {
                VStack(spacing: 0) { ForEach(0..<20) { _ in Color.blue.frame(height: 50) } }
            },
            device: square)
        let id = try #require(host.root.allNodes.first { $0.kind == "ScrollView" }?.id)
        host.drag(from: CGPoint(x: 100, y: 150), to: CGPoint(x: 100, y: 50), duration: 0.3)
        #expect((host.scrollOffset(of: id)?.y ?? 0) > 50)
    }

    @Test("A kind registered as a presentation is one, and is placed by its own function")
    func presentation() {
        NodeExtensions.register(
            kind: "TestToast",
            NodeBehavior(
                isPresentation: true,
                placePresentation: { _, node, _ in
                    var node = node
                    node.frame = CGRect(x: 0, y: 0, width: 200, height: 30)
                    return node
                }))
        let toast = ViewNode(id: "toast", kind: "TestToast")
        #expect(toast.isPresentation)
        #expect(!ViewNode(id: "other", kind: "TestOther").isPresentation)
        let placed = LayoutEngine(device: square).layout(
            ViewNode(id: "", kind: "Root", children: [toast]))
        #expect(placed.children.first?.frame == CGRect(x: 0, y: 0, width: 200, height: 30))
    }
}
