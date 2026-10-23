import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionTooling

#if canImport(Glibc)
import Glibc
#endif

/// A TCP connection to a local server, for tests.
final class TestClient {
    let descriptor: Int32
    private var buffer: [UInt8] = []

    init(port: UInt16) throws {
        descriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let status = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try #require(status == 0)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(
            descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    deinit {
        close(descriptor)
    }

    func send(_ bytes: [UInt8]) {
        _ = bytes.withUnsafeBytes {
            Glibc.send(descriptor, $0.baseAddress, $0.count, Int32(MSG_NOSIGNAL))
        }
    }

    func send(_ text: String) {
        send(Array(text.utf8))
    }

    /// Reads at least `count` bytes, or returns `false` if the connection
    /// closed or timed out first.
    private func fill(_ count: Int) -> Bool {
        var chunk = [UInt8](repeating: 0, count: 65536)
        while buffer.count < count {
            let read = chunk.withUnsafeMutableBytes {
                recv(descriptor, $0.baseAddress, $0.count, 0)
            }
            guard read > 0 else { return false }
            buffer += chunk[0..<read]
        }
        return true
    }

    /// Everything until the server closes the connection.
    func readAll() -> String {
        _ = fill(Int.max)
        defer { buffer = [] }
        return String(decoding: buffer, as: UTF8.self)
    }

    /// A response head, through its blank line.
    func readHead() -> String? {
        while HTTPRequest.headLength(in: buffer) == nil {
            guard fill(buffer.count + 1) else { return nil }
        }
        let length = HTTPRequest.headLength(in: buffer)!
        defer { buffer.removeFirst(length) }
        return String(decoding: buffer[0..<length], as: UTF8.self)
    }

    /// The next frame from the server, which never masks.
    func readFrame() -> (opcode: UInt8, payload: [UInt8])? {
        guard fill(2) else { return nil }
        var length = Int(buffer[1] & 0x7F)
        var offset = 2
        if length == 126 {
            guard fill(4) else { return nil }
            length = Int(buffer[2]) << 8 | Int(buffer[3])
            offset = 4
        } else if length == 127 {
            guard fill(10) else { return nil }
            length = buffer[2..<10].reduce(0) { $0 << 8 | Int($1) }
            offset = 10
        }
        guard fill(offset + length) else { return nil }
        defer { buffer.removeFirst(offset + length) }
        return (buffer[0] & 0x0F, Array(buffer[offset..<(offset + length)]))
    }

    /// The next text message, as JSON.
    func readJSON() throws -> [String: Any] {
        let frame = try #require(readFrame())
        try #require(frame.opcode == 1)
        return try #require(
            JSONSerialization.jsonObject(with: Data(frame.payload)) as? [String: Any])
    }

    func handshake(path: String) {
        send(
            "GET \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n"
                + "Connection: Upgrade\r\nSec-WebSocket-Version: 13\r\n"
                + "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n")
    }
}

@Suite("Web server", .serialized)
struct WebServerTests {
    let token = AccessToken("00112233445566778899aabbccddeeff")

    /// A server that answers `/` and echoes WebSocket messages.
    func makeServer() throws -> WebServer {
        let server = try WebServer(
            address: "127.0.0.1", port: 0, token: token, webSocketPath: "/socket",
            respond: { request in
                request.path == "/" ? .text(200, "OK", "page") : .notFound
            },
            acceptWebSocket: { connection in
                while let message = connection.receive() {
                    if case .text(let text) = message { connection.send(text: "echo " + text) }
                }
            })
        server.start()
        return server
    }

    @Test("Requests without the token are refused, whatever the path")
    func pageToken() throws {
        let server = try makeServer()
        defer { server.stop() }
        for target in ["/", "/?token=nope", "/missing", "/?token=00112233445566778899aabbccddeef"] {
            let client = try TestClient(port: server.port)
            client.send("GET \(target) HTTP/1.1\r\nHost: x\r\n\r\n")
            let response = client.readAll()
            #expect(response.hasPrefix("HTTP/1.1 403 Forbidden\r\n"), "\(target)")
            #expect(!response.contains("page"))
        }
        let client = try TestClient(port: server.port)
        client.send("GET /?token=\(token.value) HTTP/1.1\r\nHost: x\r\n\r\n")
        let response = client.readAll()
        #expect(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(response.hasSuffix("\r\n\r\npage"))
    }

    @Test("A WebSocket handshake without the token is refused")
    func socketToken() throws {
        let server = try makeServer()
        defer { server.stop() }
        for path in ["/socket", "/socket?token=wrong"] {
            let client = try TestClient(port: server.port)
            client.handshake(path: path)
            let head = try #require(client.readHead())
            #expect(head.hasPrefix("HTTP/1.1 403 Forbidden\r\n"), "\(path)")
            #expect(!head.contains("Sec-WebSocket-Accept"))
        }
    }

    @Test("With the token, the handshake opens a WebSocket that carries messages both ways")
    func socket() throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try TestClient(port: server.port)
        client.handshake(path: "/socket?token=\(token.value)")
        let head = try #require(client.readHead())
        #expect(head.hasPrefix("HTTP/1.1 101 Switching Protocols\r\n"))
        #expect(head.contains("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"))
        client.send(maskedFrame(.text, Array("hello".utf8)))
        let reply = try #require(client.readFrame())
        #expect(reply.opcode == 1 && reply.payload == Array("echo hello".utf8))
        client.send(maskedFrame(.ping, [4, 2]))
        let pong = try #require(client.readFrame())
        #expect(pong.opcode == 10 && pong.payload == [4, 2])
        client.send(maskedFrame(.close, [0x03, 0xE8]))
        #expect(client.readFrame()?.opcode == 8)
    }

    @Test("Other methods, bad requests, unknown paths, and plain GETs of the socket are refused")
    func refusals() throws {
        let server = try makeServer()
        defer { server.stop() }
        let cases = [
            ("POST /?token=\(token.value) HTTP/1.1\r\n\r\n", "405"),
            ("GET /missing?token=\(token.value) HTTP/1.1\r\n\r\n", "404"),
            ("GET /socket?token=\(token.value) HTTP/1.1\r\n\r\n", "400"),
            ("BREW\r\n\r\n", "400"),
            (
                "GET /?token=\(token.value) HTTP/1.1\r\nX: \(String(repeating: "a", count: 20_000))\r\n\r\n",
                "400"
            ),
        ]
        for (request, status) in cases {
            let client = try TestClient(port: server.port)
            client.send(request)
            let response = client.readAll()
            #expect(
                response.hasPrefix("HTTP/1.1 \(status) "),
                "\(request.prefix(30)) answered \(response.prefix(30))")
        }
    }

    @Test("A malformed frame closes the WebSocket with a protocol error")
    func protocolError() throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try TestClient(port: server.port)
        client.handshake(path: "/socket?token=\(token.value)")
        _ = try #require(client.readHead())
        // Unmasked, which browsers never send.
        client.send([0x81, 0x02, 104, 105])
        let close = try #require(client.readFrame())
        #expect(close.opcode == 8 && close.payload == [0x03, 0xEA])
    }

    @Test("An address that is not one is refused")
    func invalidAddress() {
        #expect(throws: WebServer.ServerError.self) {
            try WebServer(
                address: "example.com", port: 0, token: token, webSocketPath: "/socket",
                respond: { _ in .notFound }, acceptWebSocket: { _ in })
        }
    }
}

@Suite("Web preview", .serialized)
struct WebPreviewTests {
    static let hello = PreviewHello(
        appName: "Test", screenWidth: 4, screenHeight: 3, scale: 1, deviceName: "iPhone 16",
        displayCornerRadius: 1, maximumFramesPerSecond: 60)

    func connect(_ preview: WebPreview) throws -> TestClient {
        let client = try TestClient(port: preview.port)
        client.handshake(path: "/socket?token=\(preview.token.value)")
        _ = try #require(client.readHead())
        return client
    }

    @Test("A page gets the hello, the status, and then the frame")
    func frames() throws {
        let preview = try WebPreview(address: "127.0.0.1", port: 0, showsBezel: true)
        defer { preview.stop() }
        preview.setApp(Self.hello)
        preview.setStatus(.building)
        let pixels = scrolledFrame(width: 4, height: 3, offset: 0, bar: 1)
        pixels.withUnsafeBytes {
            preview.update(
                width: 4, height: 3, damage: PixelRect(x: 0, y: 0, width: 4, height: 3), pixels: $0)
        }
        preview.publish()

        let client = try connect(preview)
        let hello = try client.readJSON()
        #expect(hello["type"] as? String == "hello")
        #expect(hello["appName"] as? String == "Test")
        #expect(hello["screenWidth"] as? Double == 4)
        #expect((hello["bezel"] as? [String: Any])?["margin"] as? Double == DeviceBezel.margin)
        let status = try client.readJSON()
        #expect(status["state"] as? String == "building")
        let frame = try #require(client.readFrame())
        #expect(frame.opcode == 2)
        var page = ReferencePage()
        #expect(try page.apply(frame.payload) == 1)
        #expect(page.pixels == pixels)
    }

    @Test("A page that falls behind gets the newest pixels, not every frame")
    func flowControl() throws {
        let preview = try WebPreview(address: "127.0.0.1", port: 0, showsBezel: false)
        defer { preview.stop() }
        preview.setApp(Self.hello)
        let client = try connect(preview)
        _ = try client.readJSON()  // hello
        _ = try client.readJSON()  // status
        var page = ReferencePage()
        var last: [UInt8] = []
        for offset in 0..<(WebPreview.maximumFramesInFlight + 5) {
            last = scrolledFrame(width: 4, height: 3, offset: offset * 3, bar: 0)
            last.withUnsafeBytes {
                preview.update(
                    width: 4, height: 3, damage: PixelRect(x: 0, y: 0, width: 4, height: 3),
                    pixels: $0)
            }
            preview.publish()
            Thread.sleep(forTimeInterval: 0.02)
        }
        // Without acknowledgements, only the frames in flight were sent.
        var sequence: UInt32 = 0
        for _ in 0..<WebPreview.maximumFramesInFlight {
            sequence = try page.apply(try #require(client.readFrame()).payload)
        }
        #expect(sequence == UInt32(WebPreview.maximumFramesInFlight))
        client.send(maskedFrame(.text, Array(#"{"type":"ack","sequence":\#(sequence)}"#.utf8)))
        // Then one frame with everything that changed since.
        #expect(try page.apply(try #require(client.readFrame()).payload) == sequence + 1)
        #expect(page.pixels == last)
    }

    @Test("Input from a page reaches the host, and other messages do not")
    func input() throws {
        let preview = try WebPreview(address: "127.0.0.1", port: 0, showsBezel: false)
        defer { preview.stop() }
        let client = try connect(preview)
        client.send(maskedFrame(.text, Array(#"{"type":"command","command":"inspect"}"#.utf8)))
        client.send(maskedFrame(.text, Array(#"{"type":"down","x":1,"y":2}"#.utf8)))
        client.send(maskedFrame(.text, Array(#"{"type":"text","text":"hi"}"#.utf8)))
        var received: [HostMessage] = []
        let deadline = Date().addingTimeInterval(5)
        while received.count < 2, Date() < deadline {
            received += preview.waitForInput(timeout: 0.5)
        }
        #expect(received == [.pointerDown(x: 1, y: 2), .text("hi")])
    }

    @Test("The page and the bezel need the token")
    func pages() throws {
        let preview = try WebPreview(address: "127.0.0.1", port: 0, showsBezel: true)
        defer { preview.stop() }
        preview.setApp(Self.hello)
        let get = { (target: String) throws -> String in
            let client = try TestClient(port: preview.port)
            client.send("GET \(target) HTTP/1.1\r\nHost: x\r\n\r\n")
            return client.readAll()
        }
        #expect(try get("/bezel.png").hasPrefix("HTTP/1.1 403"))
        let page = try get("/?token=\(preview.token.value)")
        #expect(page.hasPrefix("HTTP/1.1 200 OK"))
        #expect(page.contains("Content-Security-Policy: default-src 'none'"))
        #expect(page.contains("new WebSocket("))
        let bezel = try get("/bezel.png?token=\(preview.token.value)")
        #expect(bezel.hasPrefix("HTTP/1.1 200 OK"))
        #expect(bezel.contains("Content-Type: image/png"))
        #expect(preview.urls == ["http://127.0.0.1:\(preview.port)/?token=\(preview.token.value)"])
    }
}
