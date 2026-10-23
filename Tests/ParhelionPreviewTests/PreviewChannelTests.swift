import Foundation
import Testing

@testable import ParhelionPreview

@Suite("Preview channel")
struct PreviewChannelTests {
    @Test("App messages arrive intact")
    func appMessages() throws {
        let (app, host) = try PreviewChannel.pair()
        let hello = PreviewHello(appName: "Test", screenWidth: 393, screenHeight: 852, scale: 2)
        let frame = PreviewFrame(width: 2, height: 1, pixels: [1, 2, 3, 4, 5, 6, 7, 8])
        try app.send(.hello(hello))
        try app.send(.frame(frame))
        #expect(try host.receiveAppMessage(timeout: 1) == .hello(hello))
        #expect(try host.receiveAppMessage(timeout: 1) == .frame(frame))
    }

    @Test("A hello from an app that predates device names still decodes")
    func olderHello() throws {
        let json = #"{"appName":"Old","screenWidth":393,"screenHeight":852,"scale":2}"#
        let hello = try JSONDecoder().decode(PreviewHello.self, from: Data(json.utf8))
        #expect(
            hello == PreviewHello(appName: "Old", screenWidth: 393, screenHeight: 852, scale: 2))
        #expect(hello.deviceName == nil && hello.displayCornerRadius == nil)
    }

    @Test("Host messages arrive intact and in order")
    func hostMessages() throws {
        let (app, host) = try PreviewChannel.pair()
        let messages: [HostMessage] = [
            .pointerDown(x: 1, y: 2), .pointerMoved(x: 3, y: 4), .pointerUp(x: 5, y: 6), .close,
        ]
        for message in messages { try host.send(message) }
        for message in messages {
            #expect(try app.receiveHostMessage(timeout: 1) == message)
        }
    }

    @Test("Large frames arrive across many reads")
    func largeFrame() throws {
        let (app, host) = try PreviewChannel.pair()
        let pixels = (0..<(300 * 200 * 4)).map { UInt8(truncatingIfNeeded: $0) }
        let frame = PreviewFrame(width: 300, height: 200, pixels: pixels)
        // The receiving end is used only on this thread, the sending end only
        // on the sender thread.
        nonisolated(unsafe) let sendingEnd = app
        let sender = Thread { try? sendingEnd.send(.frame(frame)) }
        sender.start()
        #expect(try host.receiveAppMessage(timeout: 5) == .frame(frame))
    }

    @Test("Receiving times out when nothing arrives")
    func timeout() throws {
        let (app, host) = try PreviewChannel.pair()
        let message = try app.receiveHostMessage(timeout: 0.05)
        #expect(message == nil)
        withExtendedLifetime(host) {}
    }

    @Test("Receiving reports a closed connection")
    func closed() throws {
        let (app, host) = try PreviewChannel.pair()
        host.close()
        #expect(throws: PreviewChannel.ChannelError.closed) {
            try app.receiveHostMessage(timeout: 1)
        }
    }

    @Test("A listener accepts a connection at its path")
    func listener() throws {
        let path = NSTemporaryDirectory() + "parhelion-test-\(getpid()).sock"
        let listener = try PreviewListener(path: path)
        let app = try PreviewChannel.connect(to: path)
        let host = try #require(try listener.accept(timeout: 1))
        try app.send(.hello(PreviewHello(appName: "A", screenWidth: 1, screenHeight: 1, scale: 1)))
        #expect(try host.receiveAppMessage(timeout: 1) != nil)
    }
}

@Suite("Commands and replies")
struct CommandReplyTests {
    @Test("Commands and replies arrive intact")
    func roundTrip() throws {
        let (app, host) = try PreviewChannel.pair()
        let commands: [PreviewCommand] = [
            .inspect(json: true), .screenshot(scale: 2), .tapNode(id: "A/B"),
            .tapButton(label: "Go"),
            .tapPoint(x: 1, y: 2), .focus(id: nil), .typeText("hi"), .pressKey("tab"),
            .scroll(dx: 0, dy: 5, x: 1, y: 1), .scrollTo(id: "S", x: 0, y: 9),
            .drag(fromX: 0, fromY: 0, toX: 1, toY: 1, duration: 0.2),
        ]
        for (index, command) in commands.enumerated() {
            try host.send(.command(id: index, command))
            #expect(try app.receiveHostMessage(timeout: 1) == .command(id: index, command))
        }
        let reply = PreviewReply(
            ok: true, message: "Done", png: Data([1, 2, 3]), revision: 4, isAnimating: true)
        try app.send(.reply(id: 3, reply))
        #expect(try host.receiveAppMessage(timeout: 1) == .reply(id: 3, reply))
    }
}

@Suite("Wire compatibility")
struct WireCompatibilityTests {
    @Test("A plain frame keeps the original layout, for hosts that predate capabilities")
    func legacyFrameBytes() throws {
        let encoded = try MessageCoding.encode(
            AppMessage.frame(PreviewFrame(width: 1, height: 1, pixels: [9, 8, 7, 6])))
        #expect(
            encoded.head + (encoded.pixels ?? [])
                == [0, 0, 0, 13, 2, 0, 0, 0, 1, 0, 0, 0, 1, 9, 8, 7, 6])
        #expect(encoded.descriptor == nil)
    }

    @Test("Input stays JSON of the original kind, for apps that predate capabilities")
    func legacyHostMessageBytes() throws {
        let encoded = try MessageCoding.encode(HostMessage.close)
        #expect(encoded.head[4] == 3)
        #expect(String(decoding: encoded.head[5...], as: UTF8.self).contains("close"))
    }

    @Test("A hello with capabilities decodes where only the original fields are known")
    func newHelloForOldHost() throws {
        struct OriginalHello: Decodable, Equatable {
            var appName: String
            var screenWidth: Double
            var screenHeight: Double
            var scale: Double
        }
        let hello = PreviewHello(
            appName: "New", screenWidth: 1, screenHeight: 2, scale: 3,
            capabilities: PreviewCapability.all)
        let decoded = try JSONDecoder().decode(
            OriginalHello.self, from: JSONEncoder().encode(hello))
        #expect(decoded == OriginalHello(appName: "New", screenWidth: 1, screenHeight: 2, scale: 3))
    }

    @Test("A hello without capabilities decodes with none")
    func oldHelloForNewHost() throws {
        let json = #"{"appName":"Old","screenWidth":393,"screenHeight":852,"scale":2}"#
        let hello = try JSONDecoder().decode(PreviewHello.self, from: Data(json.utf8))
        #expect(hello.capabilities == nil)
        #expect(hello.maximumFramesPerSecond == nil, "An older app's frame rate is unknown")
    }

    @Test("Timeouts round up to whole milliseconds, so waits never end early")
    func pollTimeouts() {
        #expect(PreviewChannel.pollMilliseconds(nil) == -1)
        #expect(PreviewChannel.pollMilliseconds(0) == 0)
        #expect(PreviewChannel.pollMilliseconds(1.0 / 60) == 17)
        #expect(PreviewChannel.pollMilliseconds(0.0001) == 1)
        #expect(PreviewChannel.pollMilliseconds(-1) == 0)
    }

    @Test("A control message has room for its header and one descriptor")
    func controlMessageSpace() {
        #expect(ControlMessage.space(descriptors: 1) == MemoryLayout<cmsghdr>.size + 8)
    }
}

@Suite("Clock and frame messages")
struct ClockMessageTests {
    @Test("Welcome, ticks, and slot releases arrive intact")
    func hostMessages() throws {
        let (app, host) = try PreviewChannel.pair()
        let messages: [HostMessage] = [
            .welcome(PreviewWelcome(capabilities: [PreviewCapability.hostClock])),
            .tick(PreviewTick(targetTime: 12_345_678_901_234, refreshPeriod: 4_166_667)),
            .releaseSlot(2),
            .pointerDown(x: 1, y: 2),
        ]
        for message in messages { try host.send(message) }
        for message in messages {
            #expect(try app.receiveHostMessage(timeout: 1) == message)
        }
    }

    @Test("Frame updates arrive intact, wherever their pixels are")
    func frameUpdates() throws {
        let (app, host) = try PreviewChannel.pair()
        let updates = [
            PreviewFrameUpdate(
                width: 2, height: 1, isAnimating: true, targetTime: 99, pixels: .slot(1)),
            PreviewFrameUpdate(
                width: 2, height: 1, damage: PixelRect(x: 1, y: 0, width: 1, height: 1),
                isAnimating: false, pixels: .inline([1, 2, 3, 4, 5, 6, 7, 8])),
            PreviewFrameUpdate(
                width: 2, height: 1, isAnimating: false, targetTime: 7, pixels: .unchanged),
        ]
        for update in updates { try app.send(.frameUpdate(update)) }
        for update in updates {
            #expect(try host.receiveAppMessage(timeout: 1) == .frameUpdate(update))
        }
    }

    @Test("An inline frame update with the wrong number of pixels is rejected")
    func malformedInline() throws {
        let (app, host) = try PreviewChannel.pair()
        try app.send(
            .frameUpdate(
                PreviewFrameUpdate(width: 2, height: 2, isAnimating: false, pixels: .inline([1]))))
        #expect(throws: PreviewChannel.ChannelError.malformedMessage) {
            try host.receiveAppMessage(timeout: 1)
        }
    }

    @Test("The timeline moves forward only")
    func timeline() {
        var timeline = PreviewTimeline(start: 1_000_000_000)
        #expect(timeline.advance(to: 1_500_000_000) == 0.5)
        #expect(timeline.advance(to: 1_400_000_000) == 0)
        #expect(timeline.current == 1_500_000_000)
        #expect(abs(timeline.advance(to: 1_504_166_667) - 0.004166667) < 1e-12)
    }

    @Test("The preview clock is monotonic")
    func clock() {
        let first = PreviewClock.now()
        let second = PreviewClock.now()
        #expect(second >= first && first > 0)
    }
}

@Suite("Shared frames")
struct SharedFrameTests {
    @Test("Slots are handed out oldest-released first, and stray releases are refused")
    func slotPool() {
        var pool = SlotPool(count: 3)
        let first = [pool.acquire(), pool.acquire(), pool.acquire(), pool.acquire()]
        #expect(first == [0, 1, 2, nil])
        let released = [pool.release(1), pool.release(1), pool.release(7)]
        #expect(released == [true, false, false])
        let again = pool.acquire()
        #expect(again == 1)
        #expect(pool.freeCount == 0)
    }

    @Test("A frame crosses in shared memory: the host maps the slot the app names, then frees it")
    func handoff() throws {
        let (app, host) = try PreviewChannel.pair()
        let width = 64
        let height = 32
        let appBuffer = try SharedFrameBuffer.create(slotCount: 3, slotSize: width * height * 4)
        var pool = SlotPool(count: 3)
        try app.send(.sharedMemory(appBuffer.announcement))
        // A message after the announcement still decodes normally.
        let hello = PreviewHello(appName: "A", screenWidth: 1, screenHeight: 1, scale: 1)
        try app.send(.hello(hello))

        guard case .sharedMemory(let memory)? = try host.receiveAppMessage(timeout: 1) else {
            Issue.record("Expected the shared memory announcement")
            return
        }
        #expect(memory.descriptor != appBuffer.descriptor)
        #expect(memory.slotCount == 3 && memory.slotSize == width * height * 4)
        let hostBuffer = try SharedFrameBuffer(mapping: memory)
        #expect(try host.receiveAppMessage(timeout: 1) == .hello(hello))

        for frame in 0..<5 {
            let acquired = pool.acquire()
            let slot = try #require(acquired)
            let pixels = (0..<(width * height * 4)).map { UInt8(truncatingIfNeeded: $0 &+ frame) }
            appBuffer.write(pixels, toSlot: slot)
            try app.send(
                .frameUpdate(
                    PreviewFrameUpdate(
                        width: width, height: height, isAnimating: true, pixels: .slot(slot))))
            guard case .frameUpdate(let update)? = try host.receiveAppMessage(timeout: 1),
                case .slot(let received) = update.pixels
            else {
                Issue.record("Expected a frame update in a slot")
                return
            }
            #expect(received == slot)
            #expect(Array(UnsafeRawBufferPointer(hostBuffer.slot(received))) == pixels)
            try host.send(.releaseSlot(received))
            guard case .releaseSlot(let released)? = try app.receiveHostMessage(timeout: 1) else {
                Issue.record("Expected a release")
                return
            }
            let accepted = pool.release(released)
            #expect(accepted)
        }
        #expect(pool.freeCount == 3)
    }

    @Test("Mapping memory smaller than its slots fails")
    func tooSmall() throws {
        let buffer = try SharedFrameBuffer.create(slotCount: 1, slotSize: 16)
        let duplicate = dup(buffer.descriptor)
        #expect(throws: SharedFrameBuffer.SharedMemoryError.tooSmall) {
            try SharedFrameBuffer(
                mapping: PreviewSharedMemory(descriptor: duplicate, slotCount: 2, slotSize: 16))
        }
    }

    @Test("Large inline frame updates arrive across many reads")
    func largeInline() throws {
        let (app, host) = try PreviewChannel.pair()
        let pixels = (0..<(300 * 200 * 4)).map { UInt8(truncatingIfNeeded: $0 &* 7) }
        let update = PreviewFrameUpdate(
            width: 300, height: 200, isAnimating: false, pixels: .inline(pixels))
        nonisolated(unsafe) let sendingEnd = app
        let sender = Thread { try? sendingEnd.send(.frameUpdate(update)) }
        sender.start()
        #expect(try host.receiveAppMessage(timeout: 5) == .frameUpdate(update))
    }
}
