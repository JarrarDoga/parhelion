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
