import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

/// A 200 × 200 screen with no safe-area insets.
private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 200, height: 200),
    safeAreaInsets: EdgeInsets()
)

/// Ten 50-point rows with 8 points between them: 572 points of content.
private struct Rows: View {
    var body: some View {
        ScrollView {
            ForEach(0..<10) { index in
                Color.red.frame(width: 50, height: 50)
            }
        }
    }
}

private struct Item: Identifiable {
    var id: String
}

@MainActor
private func scrollViewID(_ host: ViewHost) throws -> NodeID {
    try #require(host.root.allNodes.first { $0.kind == "ScrollView" }).id
}

@MainActor
@Suite("ForEach")
struct ForEachTests {
    @Test("Each element's view is identified by the element's ID")
    func identity() {
        let items = [Item(id: "a"), Item(id: "b")]
        let host = ViewHost(VStack { ForEach(items) { Text($0.id) } }, device: square)
        let ids = host.root.allNodes.filter { $0.kind == "Text" }.map(\.id.rawValue)
        #expect(ids == ["VStack/ForEach[a]/Text", "VStack/ForEach[b]/Text"])
    }

    @Test("A range creates one view per integer")
    func range() {
        let host = ViewHost(VStack { ForEach(0..<3) { Text("Row \($0)") } }, device: square)
        #expect(
            host.root.allNodes.filter { $0.kind == "Text" }.map(\.text) == [
                "Row 0", "Row 1", "Row 2",
            ])
    }
}

@MainActor
@Suite("Scrolling")
struct ScrollTests {
    @Test("A scroll view fills its proposal and lays its content out at full height")
    func layout() throws {
        let host = ViewHost(Rows(), device: square)
        let scrollView = try #require(host.root.node(withID: try scrollViewID(host)))
        #expect(scrollView.frame == CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(scrollView.attributes["contentSize"] == "50 × 572")
        #expect(scrollView.children.count == 10)
        // Content narrower than the scroll view is centered across it.
        #expect(scrollView.children[0].frame == CGRect(x: 75, y: 0, width: 50, height: 50))
        #expect(scrollView.children[9].frame?.minY == 522)
    }

    @Test("Scrolling moves the content and stops at its ends")
    func wheel() throws {
        let host = ViewHost(Rows(), device: square)
        let id = try scrollViewID(host)
        #expect(host.scroll(by: CGSize(width: 0, height: 100), at: CGPoint(x: 100, y: 100)))
        #expect(host.scrollOffset(of: id) == CGPoint(x: 0, y: 100))
        #expect(host.root.node(withID: id)?.children[0].frame?.minY == -100)

        host.scroll(by: CGSize(width: 0, height: 10_000), at: CGPoint(x: 100, y: 100))
        #expect(host.scrollOffset(of: id) == CGPoint(x: 0, y: 372))
        #expect(
            !host.scroll(by: CGSize(width: 0, height: 10), at: CGPoint(x: 100, y: 100)),
            "Nothing scrolls past the end"
        )
        try host.scroll(id, to: .zero)
        #expect(host.scrollOffset(of: id) == .zero)
    }

    @Test("Scroll positions survive state changes")
    func offsetSurvivesUpdates() throws {
        struct Counter: View {
            @State private var count = 0
            var body: some View {
                ScrollView {
                    Button("Tap \(count)") { count += 1 }
                    Color.red.frame(width: 50, height: 500)
                }
            }
        }
        let host = ViewHost(Counter(), device: square)
        let id = try scrollViewID(host)
        host.scroll(by: CGSize(width: 0, height: 5), at: CGPoint(x: 100, y: 100))
        try host.tapButton(labeled: "Tap 0")
        #expect(host.scrollOffset(of: id) == CGPoint(x: 0, y: 5))
    }

    @Test("Dragging scrolls the content opposite to the pointer")
    func drag() throws {
        let host = ViewHost(Rows(), device: square)
        let id = try scrollViewID(host)
        host.pointerDown(at: CGPoint(x: 100, y: 150))
        host.pointerMoved(to: CGPoint(x: 100, y: 140))  // Below the drag threshold.
        #expect(host.scrollOffset(of: id) == .zero)
        host.pointerMoved(to: CGPoint(x: 100, y: 120))
        #expect(host.scrollOffset(of: id) == CGPoint(x: 0, y: 20))
        host.pointerMoved(to: CGPoint(x: 100, y: 70))
        #expect(host.scrollOffset(of: id) == CGPoint(x: 0, y: 70))
        host.advanceTime(by: 1)  // A slow release: no momentum.
        host.pointerUp(at: CGPoint(x: 100, y: 70))
        #expect(!host.isAnimating)
    }

    @Test("A drag that starts on a button scrolls and does not tap it")
    func dragCancelsTap() throws {
        struct Tappable: View {
            @State private var taps = 0
            var body: some View {
                ScrollView {
                    Button(action: { taps += 1 }) {
                        Color.blue.frame(width: 100, height: 100)
                    }
                    Text("Taps: \(taps)")
                    Color.red.frame(width: 50, height: 400)
                }
            }
        }
        let host = ViewHost(Tappable(), device: square)
        host.pointerDown(at: CGPoint(x: 100, y: 50))
        #expect(host.pressedNodeID != nil)
        host.pointerMoved(to: CGPoint(x: 100, y: 20))
        #expect(host.pressedNodeID == nil)
        #expect(host.pointerUp(at: CGPoint(x: 100, y: 20)) == nil)
        #expect(host.nodes(withText: "Taps: 0").count == 1)
    }

    @Test("A fast release keeps scrolling and slows to a stop")
    func momentum() throws {
        let host = ViewHost(Rows(), device: square)
        let id = try scrollViewID(host)
        host.pointerDown(at: CGPoint(x: 100, y: 190))
        host.advanceTime(by: 0.02)
        host.pointerMoved(to: CGPoint(x: 100, y: 170))
        host.advanceTime(by: 0.02)
        host.pointerMoved(to: CGPoint(x: 100, y: 150))
        host.pointerUp(at: CGPoint(x: 100, y: 150))
        let released = try #require(host.scrollOffset(of: id)).y
        #expect(host.isAnimating)

        host.advanceTime(by: 0.1)
        let coasting = try #require(host.scrollOffset(of: id)).y
        #expect(coasting > released)

        host.advanceTime(by: 10)
        #expect(!host.isAnimating)
        #expect(try #require(host.scrollOffset(of: id)).y > coasting)
    }

    @Test("A release shortly after the last movement still flings")
    func releaseAfterShortPause() throws {
        // Slow input devices report the release as a separate event at the
        // last position, a few dozen milliseconds after the last movement.
        let host = ViewHost(Rows(), device: square)
        host.pointerDown(at: CGPoint(x: 100, y: 190))
        for y in stride(from: 170.0, through: 110, by: -20) {
            host.advanceTime(by: 0.05)
            host.pointerMoved(to: CGPoint(x: 100, y: y))
        }
        host.advanceTime(by: 0.05)
        host.pointerUp(at: CGPoint(x: 100, y: 110))
        #expect(host.isAnimating)
    }

    @Test("Momentum is deterministic however time is split")
    func deterministicMomentum() throws {
        func run(_ steps: [TimeInterval]) throws -> CGFloat {
            let host = ViewHost(Rows(), device: square)
            host.pointerDown(at: CGPoint(x: 100, y: 190))
            host.advanceTime(by: 0.02)
            host.pointerMoved(to: CGPoint(x: 100, y: 160))
            host.pointerUp(at: CGPoint(x: 100, y: 160))
            for step in steps { host.advanceTime(by: step) }
            return try #require(host.scrollOffset(of: try scrollViewID(host))).y
        }
        let once = try run([0.5])
        let split = try run(Array(repeating: 0.05, count: 10))
        #expect(abs(once - split) < 0.01)
    }

    @Test("A touch stops momentum")
    func touchStopsMomentum() throws {
        let host = ViewHost(Rows(), device: square)
        host.pointerDown(at: CGPoint(x: 100, y: 190))
        host.advanceTime(by: 0.02)
        host.pointerMoved(to: CGPoint(x: 100, y: 150))
        host.pointerUp(at: CGPoint(x: 100, y: 150))
        #expect(host.isAnimating)
        host.pointerDown(at: CGPoint(x: 100, y: 100))
        #expect(!host.isAnimating)
    }

    @Test("Content outside the scroll view is clipped and cannot be tapped")
    func clipping() throws {
        struct Clipped: View {
            @State private var taps = 0
            var body: some View {
                VStack(spacing: 0) {
                    ScrollView {
                        Color.blue.frame(width: 200, height: 100)
                        Button(action: { taps += 1 }) {
                            Color.green.frame(width: 200, height: 100)
                        }
                    }
                    .frame(height: 100)
                    Text("Taps: \(taps)")
                }
            }
        }
        let host = ViewHost(Clipped(), device: square)
        let scrollFrame = try #require(host.root.node(withID: try scrollViewID(host))?.frame)
        let button = try #require(host.root.allNodes.first { $0.kind == "Button" }?.frame)
        // The button lies below the visible part of the scroll view.
        #expect(button.minY >= scrollFrame.maxY)

        let below = CGPoint(x: 100, y: scrollFrame.maxY + 4)
        let pixel = host.render(scale: 1).color(at: below)
        #expect(pixel.green != 199 || pixel.red != 52, "The hidden button must not be drawn")
        #expect(throws: InteractionError.self) { try host.tap(at: below) }
    }

    @Test("The revision changes whenever the screen changes")
    func revision() throws {
        let host = ViewHost(Rows(), device: square)
        let start = host.revision
        host.scroll(by: CGSize(width: 0, height: 10), at: CGPoint(x: 100, y: 100))
        #expect(host.revision > start)
        let afterScroll = host.revision
        host.advanceTime(by: 1)  // Nothing is moving.
        #expect(host.revision == afterScroll)
    }

    @Test("A preview session applies scroll messages and sends a frame")
    func sessionScroll() throws {
        let tiny = Device(
            name: "Tiny", screenSize: CGSize(width: 40, height: 40), safeAreaInsets: EdgeInsets())
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        let host = ViewHost(Rows(), device: tiny)
        try hostEnd.send(.scroll(dx: 0, dy: 30, x: 20, y: 20))
        try hostEnd.send(.close)
        try PreviewSession(host: host, channel: appEnd, scale: 1, appName: "Rows").run()

        var frames = 0
        while let message = try hostEnd.receiveAppMessage(timeout: 0.2) {
            if case .frame = message { frames += 1 }
        }
        #expect(frames == 2)  // The first frame and the scrolled one.
        #expect(host.scrollOffset(of: try scrollViewID(host)) == CGPoint(x: 0, y: 30))
    }
}
