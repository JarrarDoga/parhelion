import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 60, height: 60),
    safeAreaInsets: EdgeInsets()
)

/// A button that widens a rectangle over one second.
private struct Growing: View {
    @State private var isWide = false

    var body: some View {
        VStack(spacing: 0) {
            Color.red.frame(width: isWide ? 50 : 10, height: 10)
            Button(action: { withAnimation(.linear(duration: 1)) { isWide.toggle() } }) {
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

/// Every message the app sent, after the session ended.
private func appMessages(from hostEnd: PreviewChannel) throws -> [AppMessage] {
    var messages: [AppMessage] = []
    while let message = try hostEnd.receiveAppMessage(timeout: 0.2) { messages.append(message) }
    return messages
}

@MainActor
@Suite("Preview session with a host clock")
struct PreviewSessionClockTests {
    @Test("A welcomed session sends frames through shared memory")
    func sharedFrames() throws {
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        let host = ViewHost(Growing(), device: screen)
        let center = try buttonCenter(host)
        try hostEnd.send(.welcome(PreviewWelcome(capabilities: PreviewCapability.all)))
        try hostEnd.send(.pointerDown(x: Double(center.x), y: Double(center.y)))
        try hostEnd.send(.close)
        try PreviewSession(host: host, channel: appEnd, scale: 1, appName: "Growing").run()

        let messages = try appMessages(from: hostEnd)
        guard case .hello(let hello) = messages.first else {
            Issue.record("Expected hello first")
            return
        }
        #expect(hello.capabilities == PreviewCapability.all)
        // Before the welcome arrives, the first frame is a plain frame.
        guard case .frame(let first) = messages[1] else {
            Issue.record("Expected a plain first frame")
            return
        }
        guard case .sharedMemory(let memory) = messages[2] else {
            Issue.record("Expected the shared memory next")
            return
        }
        let buffer = try SharedFrameBuffer(mapping: memory)
        guard case .frameUpdate(let pressed) = messages[3], case .slot(let slot) = pressed.pixels
        else {
            Issue.record("Expected the pressed frame in a slot")
            return
        }
        #expect(pressed.width == 60 && pressed.height == 60 && !pressed.isAnimating)
        let pressedPixels = Array(
            UnsafeRawBufferPointer(rebasing: buffer.slot(slot)[..<(60 * 60 * 4)]))
        #expect(pressedPixels.count == first.pixels.count && pressedPixels != first.pixels)
    }

    @Test("Ticks move the clock to their target time, and each one is answered")
    func ticks() throws {
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        let host = ViewHost(Growing(), device: screen)
        let center = try buttonCenter(host)
        let start = PreviewClock.now()
        try hostEnd.send(.welcome(PreviewWelcome(capabilities: [PreviewCapability.hostClock])))
        try hostEnd.send(.pointerDown(x: Double(center.x), y: Double(center.y)))
        try hostEnd.send(.pointerUp(x: Double(center.x), y: Double(center.y)))
        let halfway = start + 500_000_000
        let done = start + 1_200_000_000
        try hostEnd.send(.tick(PreviewTick(targetTime: halfway, refreshPeriod: 4_166_667)))
        try hostEnd.send(.tick(PreviewTick(targetTime: done, refreshPeriod: 4_166_667)))
        // A tick after the animation ended moves nothing, and is answered too.
        try hostEnd.send(.tick(PreviewTick(targetTime: done + 4_166_667, refreshPeriod: 4_166_667)))
        try hostEnd.send(.close)
        try PreviewSession(host: host, channel: appEnd, scale: 1, appName: "Growing").run()

        let updates = try appMessages(from: hostEnd).compactMap { message -> PreviewFrameUpdate? in
            if case .frameUpdate(let update) = message { return update }
            return nil
        }
        // The tap starts the animation; then one answer per tick.
        let answers = updates.filter { $0.targetTime != 0 }
        #expect(answers.map(\.targetTime) == [halfway, done, done + 4_166_667])
        #expect(answers.map(\.isAnimating) == [true, false, false])
        #expect(answers.last?.pixels == .unchanged)
        #expect(updates.contains { $0.targetTime == 0 && $0.isAnimating })
        // Frames went inline: shared frames were not welcomed.
        #expect(answers.first.map { if case .inline = $0.pixels { true } else { false } } == true)
        // The clock reached the last target, measured from when the session
        // started, give or take the time the test took to queue messages.
        #expect(abs(host.time - 1.204) < 0.1)
    }

    @Test("A session that is not welcomed keeps the original protocol")
    func notWelcomed() throws {
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        let host = ViewHost(Growing(), device: screen)
        let center = try buttonCenter(host)
        try hostEnd.send(.pointerDown(x: Double(center.x), y: Double(center.y)))
        try hostEnd.send(.close)
        try PreviewSession(host: host, channel: appEnd, scale: 1, appName: "Growing").run()
        let messages = try appMessages(from: hostEnd)
        #expect(messages.count == 3)
        #expect(messages.dropFirst().allSatisfy { if case .frame = $0 { true } else { false } })
    }
}
