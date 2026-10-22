// The preview channel uses Linux's socket API. Parhelion's preview runs on
// Linux; macOS support is planned.
#if canImport(Glibc)
import Glibc

/// One end of a connection between an app and a window host, over a Unix
/// domain socket.
///
/// A channel is used from one thread at a time for receiving, and from one
/// thread at a time for sending. Sending blocks until the whole message is
/// written; receiving blocks until a whole message arrives or the timeout
/// passes.
///
/// Each message is read in two steps: its 5-byte header, then exactly its
/// payload, straight into the array that the decoded message keeps. Pixels
/// are written from their own storage, so a frame is copied once by the
/// kernel on each side and nowhere else.
public final class PreviewChannel {
    public enum ChannelError: Error, Equatable {
        case socketFailed(errno: Int32)
        case pathTooLong
        case closed
        case malformedMessage
    }

    private let descriptor: Int32
    private var isClosed = false
    /// Descriptors that arrived with messages and have not been decoded yet.
    private var receivedDescriptors: [Int32] = []

    /// The largest payload a message may declare. A frame of a 4K screen at
    /// 4 bytes a pixel is about 33 MB; anything far larger is corruption.
    static let maximumMessageLength = 256 << 20

    /// Wraps a connected socket. The channel closes it when it is closed or
    /// deinitialized.
    public init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        if !isClosed { _ = Glibc.close(descriptor) }
        for received in receivedDescriptors { _ = Glibc.close(received) }
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

    /// Sends a message to the host. A ``AppMessage/sharedMemory(_:)``
    /// message passes a duplicate of its descriptor; the sender keeps its own.
    public func send(_ message: AppMessage) throws {
        try write(try MessageCoding.encode(message))
    }

    public func send(_ message: HostMessage) throws {
        try write(try MessageCoding.encode(message))
    }

    private func write(_ message: EncodedMessage) throws {
        let pixels = message.pixels ?? []
        try message.head.withUnsafeBytes { head in
            try pixels.withUnsafeBytes { body in
                try write(head: head, body: body, descriptor: message.descriptor)
            }
        }
    }

    /// Writes `head` and then `body` with as few system calls as the socket
    /// allows, attaching `descriptor` to the first byte.
    private func write(
        head: UnsafeRawBufferPointer, body: UnsafeRawBufferPointer, descriptor attached: Int32?
    ) throws {
        let total = head.count + body.count
        var offset = 0
        var pendingDescriptor = attached
        // Room for one `cmsghdr` and one descriptor, aligned as CMSG_SPACE.
        var control = [UInt8](repeating: 0, count: ControlMessage.space(descriptors: 1))
        while offset < total {
            var vectors: [iovec] = []
            if offset < head.count {
                vectors.append(
                    iovec(
                        iov_base: UnsafeMutableRawPointer(mutating: head.baseAddress! + offset),
                        iov_len: head.count - offset))
            }
            let bodyOffset = max(offset - head.count, 0)
            if bodyOffset < body.count {
                vectors.append(
                    iovec(
                        iov_base: UnsafeMutableRawPointer(mutating: body.baseAddress! + bodyOffset),
                        iov_len: body.count - bodyOffset))
            }
            let written = vectors.withUnsafeMutableBufferPointer { vectorBuffer in
                control.withUnsafeMutableBytes { controlBuffer in
                    var header = msghdr()
                    header.msg_iov = vectorBuffer.baseAddress
                    header.msg_iovlen = vectorBuffer.count
                    if let pendingDescriptor {
                        ControlMessage.write(descriptor: pendingDescriptor, into: controlBuffer)
                        header.msg_control = controlBuffer.baseAddress
                        header.msg_controllen = controlBuffer.count
                    }
                    return sendmsg(self.descriptor, &header, Int32(MSG_NOSIGNAL))
                }
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw errno == EPIPE ? ChannelError.closed : ChannelError.socketFailed(errno: errno)
            }
            pendingDescriptor = nil
            offset += written
        }
    }

    // MARK: - Receiving

    /// The next message from the window host, or `nil` if none arrives
    /// within `timeout` seconds. A `nil` timeout waits indefinitely.
    public func receiveHostMessage(timeout: Double? = nil) throws -> HostMessage? {
        guard let envelope = try receiveEnvelope(timeout: timeout) else { return nil }
        return try MessageCoding.decodeHostMessage(kind: envelope.kind, body: envelope.body)
    }

    /// The next message from the app, or `nil` if none arrives within
    /// `timeout` seconds. A `nil` timeout waits indefinitely.
    public func receiveAppMessage(timeout: Double? = nil) throws -> AppMessage? {
        guard let envelope = try receiveEnvelope(timeout: timeout) else { return nil }
        return try MessageCoding.decodeAppMessage(
            kind: envelope.kind, prefix: envelope.prefix, body: envelope.body
        ) { [self] in
            receivedDescriptors.isEmpty ? nil : receivedDescriptors.removeFirst()
        }
    }

    private func receiveEnvelope(
        timeout: Double?
    ) throws -> (kind: UInt8, prefix: [UInt8], body: [UInt8])? {
        guard try waitForData(timeout: timeout) else { return nil }
        // The header goes through recvmsg, which delivers any descriptor
        // attached to the message's first byte.
        var header = [UInt8](repeating: 0, count: 5)
        var filled = 0
        while filled < header.count {
            filled += try header.withUnsafeMutableBytes { buffer in
                try receiveWithDescriptors(
                    into: UnsafeMutableRawBufferPointer(rebasing: buffer[filled...]))
            }
        }
        let length = Int(header.readBigEndian(at: 0))
        guard length >= 1, length <= Self.maximumMessageLength else {
            throw ChannelError.malformedMessage
        }
        let kind = header[4]
        let prefixLength = min(MessageCoding.prefixLength(of: kind), length - 1)
        let prefix = try readExactly(prefixLength)
        let body = try readExactly(length - 1 - prefixLength)
        return (kind, prefix, body)
    }

    /// Reads exactly `count` bytes into a new array, blocking as needed.
    private func readExactly(_ count: Int) throws -> [UInt8] {
        guard count > 0 else { return [] }
        return try [UInt8](unsafeUninitializedCapacity: count) { buffer, initialized in
            initialized = 0
            while initialized < count {
                let received = recv(
                    descriptor, buffer.baseAddress! + initialized, count - initialized,
                    Int32(MSG_WAITALL))
                if received < 0 {
                    if errno == EINTR { continue }
                    throw ChannelError.socketFailed(errno: errno)
                }
                guard received > 0 else { throw ChannelError.closed }
                initialized += received
            }
        }
    }

    /// Receives up to `buffer.count` bytes with `recvmsg`, keeping any
    /// descriptors that arrive with them. Returns the number of bytes.
    private func receiveWithDescriptors(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        var control = [UInt8](repeating: 0, count: ControlMessage.space(descriptors: 4))
        while true {
            var vector = iovec(iov_base: buffer.baseAddress, iov_len: buffer.count)
            let (received, controlLength) = withUnsafeMutablePointer(to: &vector) { vectorPointer in
                control.withUnsafeMutableBytes { controlBuffer in
                    var header = msghdr()
                    header.msg_iov = vectorPointer
                    header.msg_iovlen = 1
                    header.msg_control = controlBuffer.baseAddress
                    header.msg_controllen = controlBuffer.count
                    let count = recvmsg(descriptor, &header, Int32(MSG_CMSG_CLOEXEC))
                    return (count, Int(header.msg_controllen))
                }
            }
            if received < 0 {
                if errno == EINTR { continue }
                throw ChannelError.socketFailed(errno: errno)
            }
            guard received > 0 else { throw ChannelError.closed }
            if controlLength > 0 {
                control.withUnsafeBytes { controlBuffer in
                    receivedDescriptors += ControlMessage.descriptors(
                        in: UnsafeRawBufferPointer(rebasing: controlBuffer[..<controlLength]))
                }
            }
            return received
        }
    }

    /// Waits until the socket has data. Returns `false` on timeout.
    private func waitForData(timeout: Double?) throws -> Bool {
        var entry = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let milliseconds = Self.pollMilliseconds(timeout)
        while true {
            let result = poll(&entry, 1, milliseconds)
            if result < 0 {
                if errno == EINTR { continue }
                throw ChannelError.socketFailed(errno: errno)
            }
            return result > 0
        }
    }

    /// A timeout in seconds as `poll` takes it: whole milliseconds, rounded
    /// up so that a wait never ends before its deadline, or -1 for none.
    static func pollMilliseconds(_ timeout: Double?) -> Int32 {
        guard let timeout else { return -1 }
        return Int32(min(max(timeout, 0) * 1000, Double(Int32.max)).rounded(.up))
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

/// The layout of `SCM_RIGHTS` control messages. Swift cannot import the
/// `CMSG_*` macros, so this spells out what they compute: a `cmsghdr`
/// (length, level, type), then the descriptors, each part aligned to the
/// size of `size_t`.
enum ControlMessage {
    private static let alignment = MemoryLayout<Int>.size
    private static var headerSize: Int { align(MemoryLayout<cmsghdr>.size) }

    private static func align(_ length: Int) -> Int {
        (length + alignment - 1) & ~(alignment - 1)
    }

    /// `CMSG_SPACE` for `descriptors` descriptors.
    static func space(descriptors: Int) -> Int {
        headerSize + align(descriptors * MemoryLayout<Int32>.size)
    }

    /// Writes a control message that passes one descriptor.
    static func write(descriptor: Int32, into buffer: UnsafeMutableRawBufferPointer) {
        buffer.initializeMemory(as: UInt8.self, repeating: 0)
        var header = cmsghdr()
        header.cmsg_len = headerSize + MemoryLayout<Int32>.size
        header.cmsg_level = SOL_SOCKET
        header.cmsg_type = Int32(SCM_RIGHTS)
        buffer.storeBytes(of: header, toByteOffset: 0, as: cmsghdr.self)
        buffer.storeBytes(of: descriptor, toByteOffset: headerSize, as: Int32.self)
    }

    /// The descriptors in a received control buffer.
    static func descriptors(in buffer: UnsafeRawBufferPointer) -> [Int32] {
        var result: [Int32] = []
        var offset = 0
        while offset + headerSize <= buffer.count {
            let header = buffer.loadUnaligned(fromByteOffset: offset, as: cmsghdr.self)
            let length = Int(header.cmsg_len)
            guard length >= headerSize, offset + length <= buffer.count else { break }
            if header.cmsg_level == SOL_SOCKET, header.cmsg_type == Int32(SCM_RIGHTS) {
                let count = (length - headerSize) / MemoryLayout<Int32>.size
                for index in 0..<count {
                    result.append(
                        buffer.loadUnaligned(
                            fromByteOffset: offset + headerSize + index * 4, as: Int32.self))
                }
            }
            offset += align(length)
        }
        return result
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
        let ready = poll(&entry, 1, PreviewChannel.pollMilliseconds(timeout))
        guard ready > 0 else { return nil }
        let connection = Glibc.accept(descriptor, nil, nil)
        guard connection >= 0 else { throw PreviewChannel.ChannelError.socketFailed(errno: errno) }
        return PreviewChannel(descriptor: connection)
    }
}
#endif
