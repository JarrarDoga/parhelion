import Foundation

#if canImport(Glibc)
import Glibc
#endif

/// A small HTTP/1.1 server with WebSocket support, over POSIX sockets.
///
/// It serves a few fixed paths to a few browsers, so each connection gets
/// a thread of its own. Every request must carry the ``AccessToken``; the
/// server answers any request without it with 403 before it looks at the
/// path, so no route can forget the check.
public final class WebServer: @unchecked Sendable {
    public enum ServerError: Error, CustomStringConvertible {
        case invalidAddress(String)
        case cannotListen(address: String, port: UInt16, errno: Int32)

        public var description: String {
            switch self {
            case .invalidAddress(let address):
                "\(address) is not an IP address to listen on, such as 127.0.0.1 or 0.0.0.0."
            case .cannotListen(let address, let port, let error):
                "Could not listen on \(address) port \(port): \(String(cString: strerror(error)))."
            }
        }

        /// Whether another program already listens on the port.
        public var isAddressInUse: Bool {
            if case .cannotListen(_, _, EADDRINUSE) = self { return true }
            return false
        }
    }

    /// The address the server listens on, as given.
    public let address: String
    /// The port the server listens on. With port 0, the system chose it.
    public let port: UInt16
    private let token: AccessToken
    private let webSocketPath: String
    private let respond: @Sendable (HTTPRequest) -> HTTPResponse
    private let acceptWebSocket: @Sendable (WebSocketConnection) -> Void
    private let listener: Int32
    private let lock = NSLock()
    private var stopped = false
    private var connections = 0

    /// The most connections served at once; more are closed at once.
    static let maximumConnections = 32
    /// How long a client may take to send its request head, in seconds.
    static let requestTimeout = 10

    /// Starts listening.
    ///
    /// - Parameters:
    ///   - address: A numeric IPv4 or IPv6 address, or `localhost`.
    ///   - port: The port, or 0 for one the system chooses.
    ///   - webSocketPath: The path whose requests open a WebSocket.
    ///   - respond: Answers every other request that carries the token.
    ///   - acceptWebSocket: Runs a WebSocket on the connection's thread,
    ///     and returns when it ends.
    public init(
        address: String, port: UInt16, token: AccessToken, webSocketPath: String,
        respond: @escaping @Sendable (HTTPRequest) -> HTTPResponse,
        acceptWebSocket: @escaping @Sendable (WebSocketConnection) -> Void
    ) throws {
        self.address = address
        self.token = token
        self.webSocketPath = webSocketPath
        self.respond = respond
        self.acceptWebSocket = acceptWebSocket
        (listener, self.port) = try Self.listen(address: address, port: port)
    }

    deinit {
        _ = Glibc.close(listener)
    }

    /// Accepts connections on a background thread until ``stop()``.
    public func start() {
        Thread { [self] in
            var poller = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            while !lock.withLock({ stopped }) {
                guard poll(&poller, 1, 250) > 0 else { continue }
                let client = Glibc.accept(listener, nil, nil)
                guard client >= 0 else { continue }
                let admitted = lock.withLock {
                    guard !stopped, connections < Self.maximumConnections else { return false }
                    connections += 1
                    return true
                }
                guard admitted else {
                    _ = Glibc.close(client)
                    continue
                }
                Thread { [self] in
                    serve(client)
                    lock.withLock { connections -= 1 }
                }.start()
            }
        }.start()
    }

    /// Stops accepting connections. Open WebSockets stay open until their
    /// owners close them.
    public func stop() {
        lock.withLock { stopped = true }
    }

    /// Reads one request from a new connection and answers it.
    private func serve(_ descriptor: Int32) {
        var enabled: Int32 = 1
        _ = setsockopt(
            descriptor, Int32(IPPROTO_TCP), TCP_NODELAY, &enabled,
            socklen_t(MemoryLayout<Int32>.size))
        setReceiveTimeout(descriptor, seconds: Self.requestTimeout)

        var buffer: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        var headLength: Int?
        while headLength == nil, buffer.count <= HTTPRequest.maximumHeadSize {
            let count = chunk.withUnsafeMutableBytes {
                recv(descriptor, $0.baseAddress, $0.count, 0)
            }
            guard count > 0 else { break }
            buffer += chunk[0..<count]
            headLength = HTTPRequest.headLength(in: buffer)
        }
        guard let headLength, headLength <= HTTPRequest.maximumHeadSize,
            let request = HTTPRequest(head: buffer[0..<headLength])
        else {
            if !buffer.isEmpty { writeAll(descriptor, HTTPResponse.badRequest.encoded()) }
            // Closing with unread bytes would reset the connection and lose
            // the response.
            finish(descriptor, discardingInput: headLength == nil)
            return
        }
        guard token.admits(request) else {
            writeAll(descriptor, HTTPResponse.forbidden.encoded())
            finish(descriptor)
            return
        }
        guard request.method == "GET" else {
            writeAll(
                descriptor,
                HTTPResponse.text(405, "Method Not Allowed", "Only GET is supported.\n").encoded())
            finish(descriptor)
            return
        }
        if request.path == webSocketPath {
            guard request.isWebSocketUpgrade, let key = request.headers["sec-websocket-key"] else {
                writeAll(descriptor, HTTPResponse.badRequest.encoded())
                finish(descriptor)
                return
            }
            guard writeAll(descriptor, HTTPResponse.switchingToWebSocket(key: key).encoded()) else {
                finish(descriptor)
                return
            }
            setReceiveTimeout(descriptor, seconds: 0)
            let connection = WebSocketConnection(
                descriptor: descriptor, request: request, leftover: Array(buffer[headLength...]))
            acceptWebSocket(connection)
            connection.finish()
            return
        }
        writeAll(descriptor, respond(request).encoded())
        finish(descriptor)
    }

    /// Ends a plain HTTP connection after its response, first reading what
    /// the client is still sending if `discardingInput`, for up to a second.
    private func finish(_ descriptor: Int32, discardingInput: Bool = false) {
        _ = shutdown(descriptor, Int32(SHUT_WR))
        if discardingInput {
            setReceiveTimeout(descriptor, seconds: 1)
            var chunk = [UInt8](repeating: 0, count: 4096)
            var total = 0
            while total < 1 << 20 {
                let count = chunk.withUnsafeMutableBytes {
                    recv(descriptor, $0.baseAddress, $0.count, 0)
                }
                guard count > 0 else { break }
                total += count
            }
        }
        _ = Glibc.close(descriptor)
    }

    private func setReceiveTimeout(_ descriptor: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        _ = setsockopt(
            descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Creates a socket listening on `address` and `port`, and returns it
    /// with the port it is bound to.
    private static func listen(address: String, port: UInt16) throws -> (Int32, UInt16) {
        var hints = addrinfo()
        hints.ai_flags = AI_PASSIVE | AI_NUMERICHOST | AI_NUMERICSERV
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        var results: UnsafeMutablePointer<addrinfo>?
        let host = address == "localhost" ? "127.0.0.1" : address
        guard getaddrinfo(host, String(port), &hints, &results) == 0, let info = results else {
            throw ServerError.invalidAddress(address)
        }
        defer { freeaddrinfo(results) }

        func failure(_ descriptor: Int32?) -> ServerError {
            let error = errno
            if let descriptor { _ = Glibc.close(descriptor) }
            return .cannotListen(address: address, port: port, errno: error)
        }
        let descriptor = socket(info.pointee.ai_family, Int32(SOCK_STREAM.rawValue), 0)
        guard descriptor >= 0 else { throw failure(nil) }
        var enabled: Int32 = 1
        _ = setsockopt(
            descriptor, SOL_SOCKET, SO_REUSEADDR, &enabled, socklen_t(MemoryLayout<Int32>.size))
        guard bind(descriptor, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0,
            Glibc.listen(descriptor, 16) == 0
        else { throw failure(descriptor) }

        var bound = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let boundPort = withUnsafeMutablePointer(to: &bound) { storage in
            storage.withMemoryRebound(to: sockaddr.self, capacity: 1) { address -> UInt16 in
                guard getsockname(descriptor, address, &length) == 0 else { return port }
                if address.pointee.sa_family == sa_family_t(AF_INET6) {
                    return address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                        UInt16(bigEndian: $0.pointee.sin6_port)
                    }
                }
                return address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt16(bigEndian: $0.pointee.sin_port)
                }
            }
        }
        return (descriptor, boundPort)
    }
}

/// Writes every byte, retrying after interruptions and partial writes.
/// Returns `false` if the connection failed.
@discardableResult
func writeAll(_ descriptor: Int32, _ bytes: [UInt8]) -> Bool {
    bytes.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let written = send(
                descriptor, buffer.baseAddress! + offset, buffer.count - offset,
                Int32(MSG_NOSIGNAL))
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { return false }
            offset += written
        }
        return true
    }
}

/// An open WebSocket to one page.
///
/// The thread that the server hands the connection to reads with
/// ``receive()``; any thread can send. A blocked send or receive returns
/// once ``shutDown()`` is called.
public final class WebSocketConnection: @unchecked Sendable {
    /// The request that opened the WebSocket.
    public let request: HTTPRequest
    private let descriptor: Int32
    private var decoder = WebSocket.Decoder(maximumMessageSize: maximumMessageSize)
    private var leftover: [UInt8]
    private let writeLock = NSLock()
    private let stateLock = NSLock()
    private var isOpen = true
    private var isFinished = false

    /// The longest message accepted from a page. Pages send only small
    /// JSON messages.
    static let maximumMessageSize = 64 * 1024

    init(descriptor: Int32, request: HTTPRequest, leftover: [UInt8]) {
        self.descriptor = descriptor
        self.request = request
        self.leftover = leftover
    }

    /// Sends a text message. Returns `false` if the connection is closed.
    @discardableResult
    public func send(text: String) -> Bool {
        write(WebSocket.frame(.text, payload: Array(text.utf8)))
    }

    /// Sends a binary message. Returns `false` if the connection is closed.
    @discardableResult
    public func send(binary payload: [UInt8]) -> Bool {
        write(WebSocket.frame(.binary, payload: payload))
    }

    private func write(_ bytes: [UInt8]) -> Bool {
        writeLock.withLock {
            guard stateLock.withLock({ isOpen }) else { return false }
            guard writeAll(descriptor, bytes) else {
                shutDown()
                return false
            }
            return true
        }
    }

    /// Waits for the next text or binary message. It answers pings and
    /// returns `nil` once the page closes the connection, it breaks the
    /// protocol, or ``shutDown()`` is called.
    public func receive() -> WebSocket.Message? {
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            do {
                if !leftover.isEmpty {
                    decoder.append(leftover)
                    leftover = []
                }
                while let message = try decoder.next() {
                    switch message {
                    case .text, .binary:
                        return message
                    case .ping(let payload):
                        _ = write(WebSocket.frame(.pong, payload: payload))
                    case .pong:
                        break
                    case .close:
                        _ = write(WebSocket.closeFrame(code: 1000))
                        shutDown()
                        return nil
                    }
                }
            } catch let error as WebSocket.ProtocolError {
                _ = write(WebSocket.closeFrame(code: error.closeCode))
                shutDown()
                return nil
            } catch {
                shutDown()
                return nil
            }
            let count = chunk.withUnsafeMutableBytes {
                recv(descriptor, $0.baseAddress, $0.count, 0)
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                shutDown()
                return nil
            }
            leftover = Array(chunk[0..<count])
        }
    }

    /// Ends the connection. Threads blocked in sending or receiving return.
    public func shutDown() {
        stateLock.withLock {
            guard isOpen else { return }
            isOpen = false
            _ = Glibc.shutdown(descriptor, Int32(SHUT_RDWR))
        }
    }

    /// Closes the descriptor, once no thread can be writing to it.
    func finish() {
        shutDown()
        writeLock.withLock {
            guard !isFinished else { return }
            isFinished = true
            _ = Glibc.close(descriptor)
        }
    }
}
