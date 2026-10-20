import Foundation
import Testing

@testable import ParhelionUI

// These tests use fixed-size views so that every expected frame can be
// computed by hand. They check Parhelion's layout algorithm, not SwiftUI's
// default constants; those are listed in LayoutDefaults.swift.

/// A 400 × 400 screen with no safe-area insets, so root content is centered
/// at (200, 200).
private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 400, height: 400),
    safeAreaInsets: EdgeInsets()
)

@MainActor
private func frame(of id: NodeID, in host: ViewHost) -> CGRect? {
    host.root.node(withID: id)?.frame
}

@MainActor
@Suite("Layout")
struct LayoutTests {
    @Test("The root covers the screen and centers its content in the safe area")
    func rootCentersContent() {
        let device = Device(
            name: "Test",
            screenSize: CGSize(width: 400, height: 400),
            safeAreaInsets: EdgeInsets(top: 40, leading: 0, bottom: 0, trailing: 0)
        )
        let host = ViewHost(Color.red.frame(width: 100, height: 60), device: device)
        #expect(host.root.frame == CGRect(x: 0, y: 0, width: 400, height: 400))
        // The safe area is y 40...400, so its center is y 220.
        #expect(frame(of: "Color", in: host) == CGRect(x: 150, y: 190, width: 100, height: 60))
    }

    @Test("A vertical stack adds its spacing between children")
    func verticalStackSpacing() {
        let host = ViewHost(
            VStack(spacing: 10) {
                Color.red.frame(width: 20, height: 20)
                Color.blue.frame(width: 40, height: 30)
            },
            device: square
        )
        let stack = host.root.children[0]
        #expect(stack.frame == CGRect(x: 180, y: 170, width: 40, height: 60))
        #expect(stack.children[0].frame == CGRect(x: 190, y: 170, width: 20, height: 20))
        #expect(stack.children[1].frame == CGRect(x: 180, y: 200, width: 40, height: 30))
    }

    @Test("Stack alignment positions children across the axis")
    func stackAlignment() {
        let host = ViewHost(
            HStack(alignment: .top, spacing: 0) {
                Color.red.frame(width: 20, height: 20)
                Color.blue.frame(width: 20, height: 60)
            },
            device: square
        )
        let stack = host.root.children[0]
        #expect(stack.children[0].frame == CGRect(x: 180, y: 170, width: 20, height: 20))
        #expect(stack.children[1].frame == CGRect(x: 200, y: 170, width: 20, height: 60))
    }

    @Test("A spacer takes the space its siblings leave")
    func spacerFillsRemainder() {
        let host = ViewHost(
            HStack(spacing: 0) {
                Color.red.frame(width: 50, height: 10)
                Spacer()
                Color.blue.frame(width: 50, height: 10)
            }
            .frame(width: 300),
            device: square
        )
        let stack = host.root.children[0]
        #expect(stack.frame == CGRect(x: 50, y: 195, width: 300, height: 10))
        #expect(stack.children[1].frame?.width == 200)
        #expect(stack.children[2].frame?.minX == 300)
    }

    @Test("The least flexible child is sized first")
    func leastFlexibleFirst() {
        // The fixed child takes its 120 points first; the flexible color
        // gets the remaining 180, not an equal half of 300.
        let host = ViewHost(
            HStack(spacing: 0) {
                Color.red
                Color.blue.frame(width: 120)
            }
            .frame(width: 300, height: 50),
            device: square
        )
        let stack = host.root.children[0]
        #expect(stack.children[0].frame?.width == 180)
        #expect(stack.children[1].frame?.width == 120)
    }

    @Test("Nested stacks of flexible views get finite frames")
    func nestedFlexibleStacks() {
        // The outer stack measures the inner one with an infinite proposal.
        // Two fill-everything children must not turn that into NaN.
        let host = ViewHost(
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.red
                    Color.blue
                }
                Color.green.frame(width: 100)
            }
            .frame(width: 300, height: 50),
            device: square
        )
        for node in host.root.allNodes {
            let frame = node.frame ?? .null
            let values = [frame.minX, frame.minY, frame.width, frame.height]
            #expect(values.allSatisfy { $0.isFinite }, "\(node.id) has frame \(frame)")
        }
        let inner = host.root.children[0].children[0]
        #expect(inner.frame?.width == 200)
        #expect(inner.children.map { $0.frame?.width } == [100, 100])
    }

    @Test("Padding insets the view's frame")
    func padding() {
        let host = ViewHost(Color.red.frame(width: 100, height: 100).padding(20), device: square)
        #expect(frame(of: "Color", in: host) == CGRect(x: 150, y: 150, width: 100, height: 100))
    }

    @Test("Modifiers apply in order")
    func modifierOrder() {
        let paddedThenFramed = ViewHost(
            Color.red.padding(10).frame(width: 100, height: 100),
            device: square
        )
        #expect(
            frame(of: "Color", in: paddedThenFramed)
                == CGRect(x: 160, y: 160, width: 80, height: 80)
        )

        let framedThenPadded = ViewHost(
            Color.red.frame(width: 100, height: 100).padding(10),
            device: square
        )
        #expect(
            frame(of: "Color", in: framedThenPadded)
                == CGRect(x: 150, y: 150, width: 100, height: 100)
        )
    }

    @Test("A frame aligns its content")
    func frameAlignment() {
        let host = ViewHost(
            Color.red.frame(width: 20, height: 20).frame(
                width: 100,
                height: 100,
                alignment: .bottomTrailing
            ),
            device: square
        )
        #expect(frame(of: "Color", in: host) == CGRect(x: 230, y: 230, width: 20, height: 20))
    }

    @Test("A frame with an infinite maximum fills the proposal")
    func flexibleFrameFills() {
        let host = ViewHost(
            Color.red.frame(width: 20, height: 20).frame(maxWidth: .infinity),
            device: square
        )
        let color = host.root.children[0]
        #expect(color.frame == CGRect(x: 190, y: 190, width: 20, height: 20))
        #expect(color.modifiers.count == 2)
    }

    @Test("A frame with a minimum is at least that large")
    func flexibleFrameMinimum() {
        let host = ViewHost(
            VStack(spacing: 0) {
                Color.red.frame(width: 20, height: 20)
                    .frame(minWidth: 100, minHeight: 50, alignment: .leading)
            },
            device: square
        )
        let stack = host.root.children[0]
        #expect(stack.frame?.size == CGSize(width: 100, height: 50))
        #expect(stack.children[0].frame == CGRect(x: 150, y: 190, width: 20, height: 20))
    }

    @Test("Tapping a point taps the frontmost button there")
    func tapAtPoint() throws {
        struct Taps: View {
            @State private var count = 0
            var body: some View {
                VStack(spacing: 0) {
                    Text("Taps: \(count)")
                    Button(action: { count += 1 }) {
                        Color.blue.frame(width: 100, height: 40)
                    }
                }
            }
        }
        let host = ViewHost(Taps(), device: square)
        let button = try #require(host.root.allNodes.first { $0.kind == "Button" })
        let center = CGPoint(x: button.frame!.midX, y: button.frame!.midY)

        try host.tap(at: center)
        #expect(host.nodes(withText: "Taps: 1").count == 1)

        #expect(throws: InteractionError.nothingTappable(at: CGPoint(x: 1, y: 1))) {
            try host.tap(at: CGPoint(x: 1, y: 1))
        }
    }

    @Test("Frames and modifiers appear in the JSON tree")
    func jsonIncludesFrames() throws {
        let host = ViewHost(Color.red.frame(width: 10, height: 20), device: square)
        let data = try JSONEncoder().encode(host.root.children[0])
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let frame = try #require(json["frame"] as? [String: Double])
        #expect(frame == ["x": 195, "y": 190, "width": 10, "height": 20])
        #expect((json["modifiers"] as? [Any])?.count == 1)
    }
}
