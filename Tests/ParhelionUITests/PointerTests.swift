import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 50, height: 50),
    safeAreaInsets: EdgeInsets()
)

private struct Counter: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 0) {
            Text("\(count)")
            Button(action: { count += 1 }) {
                Color.blue.frame(width: 40, height: 20)
            }
        }
    }
}

@MainActor
private func buttonCenter(_ host: ViewHost) throws -> CGPoint {
    let button = try #require(host.root.allNodes.first { $0.kind == "Button" }?.frame)
    return CGPoint(x: button.midX, y: button.midY)
}

@MainActor
@Suite("Pointer input")
struct PointerTests {
    @Test("Pressing and releasing on a button taps it")
    func pressAndRelease() throws {
        let host = ViewHost(Counter(), device: square)
        let center = try buttonCenter(host)
        host.pointerDown(at: center)
        #expect(host.pressedNodeID != nil)
        #expect(host.pointerUp(at: center) != nil)
        #expect(host.nodes(withText: "1").count == 1)
        #expect(host.pressedNodeID == nil)
    }

    @Test("Releasing away from the button cancels the tap")
    func dragAway() throws {
        let host = ViewHost(Counter(), device: square)
        let center = try buttonCenter(host)
        host.pointerDown(at: center)
        host.pointerMoved(to: CGPoint(x: 1, y: 1))
        #expect(host.pressedNodeID == nil)
        #expect(host.pointerUp(at: CGPoint(x: 1, y: 1)) == nil)
        #expect(host.nodes(withText: "0").count == 1)
    }

    @Test("A press that starts outside a button taps nothing")
    func pressOutside() throws {
        let host = ViewHost(Counter(), device: square)
        host.pointerDown(at: CGPoint(x: 1, y: 1))
        #expect(host.pointerUp(at: try buttonCenter(host)) == nil)
        #expect(host.nodes(withText: "0").count == 1)
    }

    @Test("A pressed button draws dimmed")
    func pressedLooksDimmed() throws {
        let host = ViewHost(Counter(), device: square)
        let center = try buttonCenter(host)
        let normal = host.render(scale: 1).color(at: center)
        host.pointerDown(at: center)
        let pressed = host.render(scale: 1).color(at: center)
        #expect(normal.blue == 255 && normal.red == 0)
        #expect(pressed.red > 150, "A dimmed blue on white is lighter: \(pressed)")
    }
}

@MainActor
@Suite("Preview session")
struct PreviewSessionTests {
    @Test("A session sends hello and frames, and applies taps from the host")
    func session() throws {
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        let host = ViewHost(Counter(), device: square)
        let center = try buttonCenter(host)

        // Queue the host's messages first; the session reads them in order.
        try hostEnd.send(.pointerDown(x: Double(center.x), y: Double(center.y)))
        try hostEnd.send(.pointerUp(x: Double(center.x), y: Double(center.y)))
        try hostEnd.send(.close)

        let session = PreviewSession(host: host, channel: appEnd, scale: 1, appName: "Counter")
        try session.run()

        guard case .hello(let hello) = try hostEnd.receiveAppMessage(timeout: 1) else {
            Issue.record("Expected hello first")
            return
        }
        #expect(
            hello
                == PreviewHello(
                    appName: "Counter", screenWidth: 50, screenHeight: 50, scale: 1,
                    deviceName: "Test", displayCornerRadius: 0))

        var frames: [PreviewFrame] = []
        while case .frame(let frame)? = try hostEnd.receiveAppMessage(timeout: 0.2) {
            frames.append(frame)
        }
        // The first frame, the pressed button, and the frame after the tap.
        #expect(frames.count == 3)
        #expect(frames.allSatisfy { $0.width == 50 && $0.height == 50 })
        #expect(host.nodes(withText: "1").count == 1)
    }
}
