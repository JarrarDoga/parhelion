// The preview channel uses Linux's socket API. Parhelion's preview runs on
// Linux; macOS support is planned.
#if canImport(Glibc)
import Glibc

/// One end of a connection between an app and a window host, over a Unix
/// domain socket.
///
/// A channel is used from one thread at a time. Sending blocks until the
/// whole message is written; receiving blocks until a whole message arrives
/// or the timeout passes.
public final class PreviewChannel {
    public enum ChannelError: Error, Equatable {
        case socketFailed(errno: Int32)
        case pathTooLong
        case closed
        case malformedMessage
    }

    private let descriptor: Int32
    private var buffer: [UInt8] = []
    private var isClosed = false

    /// Wraps a connected socket. The channel closes it when it is closed or
    /// deinitialized.
    public init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        if !isClosed { _ = Glibc.close(descriptor) }
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        _ = Glibc.close(descriptor)
    }

    /// Connects to a window host listening at `path`.
    public static func connect(to path: String) throws -> PreviewChannel {
        let socketDescriptor = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard socketDescriptor >= 0 else { throw ChannelError.socketFailed(errno: errno) }
        var address = try unixAddress(path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Glibc.connect(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let error = errno
            _ = Glibc.close(socketDescriptor)
            throw ChannelError.socketFailed(errno: error)
        }
        return PreviewChannel(descriptor: socketDescriptor)
    }

    /// A connected pair of channels, for tests.
    public static func pair() throws -> (PreviewChannel, PreviewChannel) {
        var descriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0, &descriptors) == 0 else {
            throw ChannelError.socketFailed(errno: errno)
        }
        return (
            PreviewChannel(descriptor: descriptors[0]), PreviewChannel(descriptor: descriptors[1])
        )
    }

    // MARK: - Sending

    public func send(_ message: AppMessage) throws {
        try write(try MessageCoding.encode(message))
    }

    public func send(_ message: HostMessage) throws {
        try write(try MessageCoding.encode(message))
    }

    private func write(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes {
                Glibc.send(descriptor, $0.baseAddress, $0.count, Int32(MSG_NOSIGNAL))
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw errno == EPIPE ? ChannelError.closed : ChannelError.socketFailed(errno: errno)
            }
            offset += written
        }
    }

    // MARK: - Receiving

    /// The next message from the window host, or `nil` if none arrives
    /// within `timeout` seconds. A `nil` timeout waits indefinitely.
    public func receiveHostMessage(timeout: Double? = nil) throws -> HostMessage? {
        guard let (kind, payload) = try receiveEnvelope(timeout: timeout) else { return nil }
        return try MessageCoding.decodeHostMessage(kind: kind, payload: payload)
    }

    /// The next message from the app, or `nil` if none arrives within
    /// `timeout` seconds. A `nil` timeout waits indefinitely.
    public func receiveAppMessage(timeout: Double? = nil) throws -> AppMessage? {
        guard let (kind, payload) = try receiveEnvelope(timeout: timeout) else { return nil }
        return try MessageCoding.decodeAppMessage(kind: kind, payload: payload)
    }

    private func receiveEnvelope(timeout: Double?) throws -> (UInt8, [UInt8])? {
        while true {
            if buffer.count >= 4 {
                let length = Int(buffer.readBigEndian(at: 0))
                guard length >= 1 else { throw ChannelError.malformedMessage }
                if buffer.count >= 4 + length {
                    let kind = buffer[4]
                    let payload = Array(buffer[5..<4 + length])
                    buffer.removeFirst(4 + length)
                    return (kind, payload)
                }
            }
            guard try waitForData(timeout: timeout) else { return nil }
            var chunk = [UInt8](repeating: 0, count: 1 << 16)
            let count = chunk.withUnsafeMutableBytes {
                recv(descriptor, $0.baseAddress, $0.count, 0)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw ChannelError.socketFailed(errno: errno)
            }
            guard count > 0 else { throw ChannelError.closed }
            buffer += chunk[0..<count]
        }
    }

    /// Waits until the socket has data. Returns `false` on timeout.
    private func waitForData(timeout: Double?) throws -> Bool {
        var entry = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let milliseconds = timeout.map { Int32(max($0, 0) * 1000) } ?? -1
        while true {
            let result = poll(&entry, 1, milliseconds)
            if result < 0 {
                if errno == EINTR { continue }
                throw ChannelError.socketFailed(errno: errno)
            }
            return result > 0
        }
    }

    static func unixAddress(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw ChannelError.pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
            buffer[bytes.count] = 0
        }
        return address
    }
}

/// A listening socket that a window host waits for its app on.
public final class PreviewListener {
    public let path: String
    private let descriptor: Int32

    /// Listens at `path`, replacing any stale socket file there.
    public init(path: String) throws {
        self.path = path
        _ = unlink(path)
        descriptor = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard descriptor >= 0 else { throw PreviewChannel.ChannelError.socketFailed(errno: errno) }
        var address = try PreviewChannel.unixAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(descriptor, 1) == 0 else {
            let error = errno
            _ = Glibc.close(descriptor)
            throw PreviewChannel.ChannelError.socketFailed(errno: error)
        }
    }

    deinit {
        _ = Glibc.close(descriptor)
        _ = unlink(path)
    }

    /// Waits up to `timeout` seconds for an app to connect.
    public func accept(timeout: Double) throws -> PreviewChannel? {
        var entry = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&entry, 1, Int32(timeout * 1000))
        guard ready > 0 else { return nil }
        let connection = Glibc.accept(descriptor, nil, nil)
        guard connection >= 0 else { throw PreviewChannel.ChannelError.socketFailed(errno: errno) }
        return PreviewChannel(descriptor: connection)
    }
}
#endif
