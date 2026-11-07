import Foundation

#if canImport(Glibc)
import Glibc

// A small D-Bus client: enough of the wire format and the connection
// handshake to own a name on the session bus and answer method calls, so
// that `parhelion` links no D-Bus library. It speaks only little-endian,
// without file descriptor passing, which is all MPRIS needs.

/// A D-Bus value.
public indirect enum DBusValue: Equatable, Sendable {
    case byte(UInt8)
    case bool(Bool)
    case int32(Int32)
    case uint32(UInt32)
    case int64(Int64)
    case uint64(UInt64)
    case double(Double)
    case string(String)
    case objectPath(String)
    case signature(String)
    case variant(DBusValue)
    /// An array with the signature of its elements, which an empty array
    /// cannot tell.
    case array(String, [DBusValue])
    case dictEntry(DBusValue, DBusValue)
    case structure([DBusValue])

    /// The value's type signature.
    public var signature: String {
        switch self {
        case .byte: "y"
        case .bool: "b"
        case .int32: "i"
        case .uint32: "u"
        case .int64: "x"
        case .uint64: "t"
        case .double: "d"
        case .string: "s"
        case .objectPath: "o"
        case .signature: "g"
        case .variant: "v"
        case .array(let element, _): "a" + element
        case .dictEntry(let key, let value): "{" + key.signature + value.signature + "}"
        case .structure(let members): "(" + members.map(\.signature).joined() + ")"
        }
    }

    /// An `a{sv}` from pairs.
    public static func dictionary(_ pairs: [(String, DBusValue)]) -> DBusValue {
        .array(
            "{sv}", pairs.map { .dictEntry(.string($0.0), .variant($0.1)) })
    }

    public static func stringArray(_ strings: [String]) -> DBusValue {
        .array("s", strings.map { .string($0) })
    }

    public var stringValue: String? {
        switch self {
        case .string(let value), .objectPath(let value), .signature(let value): value
        case .variant(let inner): inner.stringValue
        default: nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value): value
        case .int32(let value): Double(value)
        case .int64(let value): Double(value)
        case .uint32(let value): Double(value)
        case .uint64(let value): Double(value)
        case .variant(let inner): inner.doubleValue
        default: nil
        }
    }

    public var int64Value: Int64? {
        switch self {
        case .int64(let value): value
        case .int32(let value): Int64(value)
        case .uint32(let value): Int64(value)
        case .variant(let inner): inner.int64Value
        default: nil
        }
    }
}

/// A D-Bus message.
public struct DBusMessage: Equatable, Sendable {
    public enum Kind: UInt8, Sendable {
        case methodCall = 1
        case methodReturn = 2
        case error = 3
        case signal = 4
    }

    public var kind: Kind
    public var serial: UInt32 = 0
    public var path: String?
    public var interface: String?
    public var member: String?
    public var errorName: String?
    public var replySerial: UInt32?
    public var destination: String?
    public var sender: String?
    public var body: [DBusValue] = []
    /// Whether a method call does not want a reply.
    public var noReplyExpected = false

    public init(
        kind: Kind, path: String? = nil, interface: String? = nil, member: String? = nil,
        destination: String? = nil, body: [DBusValue] = []
    ) {
        self.kind = kind
        self.path = path
        self.interface = interface
        self.member = member
        self.destination = destination
        self.body = body
    }

    /// The return that answers a call.
    public func reply(_ body: [DBusValue] = []) -> DBusMessage {
        var result = DBusMessage(kind: .methodReturn, destination: sender, body: body)
        result.replySerial = serial
        return result
    }

    /// The error that answers a call.
    public func error(_ name: String, _ text: String) -> DBusMessage {
        var result = DBusMessage(kind: .error, destination: sender, body: [.string(text)])
        result.errorName = name
        result.replySerial = serial
        return result
    }
}

enum DBusError: Error, Equatable {
    case malformed(String)
    case connectionFailed(String)
    case authenticationFailed(String)
    case closed
}

// MARK: - Encoding

struct DBusWriter {
    private(set) var bytes: [UInt8] = []
    /// The offset that alignment counts from. A message body starts at a
    /// multiple of 8, so counting from its first byte is the same.
    private let base: Int

    init(base: Int = 0) { self.base = base }

    private mutating func align(_ boundary: Int) {
        while (bytes.count + base) % boundary != 0 { bytes.append(0) }
    }

    mutating func append(_ value: UInt8) { bytes.append(value) }

    mutating func append(_ value: UInt32) {
        align(4)
        for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8((value >> shift) & 0xFF)) }
    }

    mutating func append(_ value: UInt64) {
        align(8)
        for shift in stride(from: 0, to: 64, by: 8) { bytes.append(UInt8((value >> shift) & 0xFF)) }
    }

    mutating func appendString(_ string: String) {
        let utf8 = Array(string.utf8)
        append(UInt32(utf8.count))
        bytes += utf8
        bytes.append(0)
    }

    mutating func appendSignature(_ string: String) {
        let utf8 = Array(string.utf8)
        bytes.append(UInt8(utf8.count))
        bytes += utf8
        bytes.append(0)
    }

    mutating func append(_ value: DBusValue) {
        switch value {
        case .byte(let value): append(value)
        case .bool(let value): append(UInt32(value ? 1 : 0))
        case .int32(let value): append(UInt32(bitPattern: value))
        case .uint32(let value): append(value)
        case .int64(let value): append(UInt64(bitPattern: value))
        case .uint64(let value): append(value)
        case .double(let value): append(value.bitPattern)
        case .string(let value), .objectPath(let value): appendString(value)
        case .signature(let value): appendSignature(value)
        case .variant(let inner):
            appendSignature(inner.signature)
            append(inner)
        case .array(let element, let items):
            align(4)
            let lengthAt = bytes.count
            append(UInt32(0))
            // The elements are aligned even when there are none.
            align(Self.alignment(of: element))
            let start = bytes.count
            for item in items { append(item) }
            let length = UInt32(bytes.count - start)
            for index in 0..<4 {
                bytes[lengthAt + index] = UInt8((length >> (8 * UInt32(index))) & 0xFF)
            }
        case .dictEntry(let key, let value):
            align(8)
            append(key)
            append(value)
        case .structure(let members):
            align(8)
            for member in members { append(member) }
        }
    }

    static func alignment(of signature: String) -> Int {
        switch signature.first {
        case "y", "g", "v": 1
        case "n", "q": 2
        case "b", "i", "u", "s", "o", "a": 4
        case "x", "t", "d", "(", "{": 8
        default: 1
        }
    }
}

extension DBusMessage {
    /// The message on the wire.
    func encoded(serial: UInt32) -> [UInt8] {
        var bodyWriter = DBusWriter()
        for value in body { bodyWriter.append(value) }

        var fields: [DBusValue] = []
        func field(_ code: UInt8, _ value: DBusValue) {
            fields.append(.structure([.byte(code), .variant(value)]))
        }
        if let path { field(1, .objectPath(path)) }
        if let interface { field(2, .string(interface)) }
        if let member { field(3, .string(member)) }
        if let errorName { field(4, .string(errorName)) }
        if let replySerial { field(5, .uint32(replySerial)) }
        if let destination { field(6, .string(destination)) }
        if !body.isEmpty { field(8, .signature(body.map(\.signature).joined())) }

        var header = DBusWriter()
        header.append(UInt8(ascii: "l"))
        header.append(kind.rawValue)
        header.append(noReplyExpected ? UInt8(1) : 0)
        header.append(UInt8(1))
        header.append(UInt32(bodyWriter.bytes.count))
        header.append(serial)
        header.append(DBusValue.array("(yv)", fields))
        var bytes = header.bytes
        while bytes.count % 8 != 0 { bytes.append(0) }
        return bytes + bodyWriter.bytes
    }
}

// MARK: - Decoding

struct DBusReader {
    let bytes: [UInt8]
    var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    private mutating func align(_ boundary: Int) throws {
        while offset % boundary != 0 {
            guard offset < bytes.count else { throw DBusError.malformed("padding") }
            offset += 1
        }
    }

    /// Skips the padding between the header and the body.
    mutating func alignForBody() throws { try align(8) }

    private mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, offset + count <= bytes.count else {
            throw DBusError.malformed("short message")
        }
        defer { offset += count }
        return bytes[offset..<offset + count]
    }

    mutating func readByte() throws -> UInt8 { try take(1).first! }

    mutating func readUInt32() throws -> UInt32 {
        try align(4)
        return try take(4).enumerated().reduce(0) {
            $0 | UInt32($1.element) << (8 * UInt32($1.offset))
        }
    }

    mutating func readUInt64() throws -> UInt64 {
        try align(8)
        return try take(8).enumerated().reduce(0) {
            $0 | UInt64($1.element) << (8 * UInt64($1.offset))
        }
    }

    mutating func readString() throws -> String {
        let length = Int(try readUInt32())
        let text = String(decoding: try take(length), as: UTF8.self)
        guard try readByte() == 0 else { throw DBusError.malformed("string terminator") }
        return text
    }

    mutating func readSignature() throws -> String {
        let length = Int(try readByte())
        let text = String(decoding: try take(length), as: UTF8.self)
        guard try readByte() == 0 else { throw DBusError.malformed("signature terminator") }
        return text
    }

    /// The first complete type in `signature`, and what follows it.
    static func splitType(_ signature: Substring) throws -> (Substring, Substring) {
        guard let first = signature.first else { throw DBusError.malformed("empty type") }
        switch first {
        case "a":
            let (element, rest) = try splitType(signature.dropFirst())
            return (signature[signature.startIndex..<element.endIndex], rest)
        case "(", "{":
            let close: Character = first == "(" ? ")" : "}"
            var rest = signature.dropFirst()
            while rest.first != close {
                guard !rest.isEmpty else { throw DBusError.malformed("unclosed type") }
                rest = try splitType(rest).1
            }
            let end = rest.index(after: rest.startIndex)
            return (signature[signature.startIndex..<end], signature[end...])
        default:
            let end = signature.index(after: signature.startIndex)
            return (signature[..<end], signature[end...])
        }
    }

    mutating func read(type: Substring) throws -> DBusValue {
        guard let first = type.first else { throw DBusError.malformed("empty type") }
        switch first {
        case "y": return .byte(try readByte())
        case "b": return .bool(try readUInt32() != 0)
        case "i": return .int32(Int32(bitPattern: try readUInt32()))
        case "u": return .uint32(try readUInt32())
        case "x": return .int64(Int64(bitPattern: try readUInt64()))
        case "t": return .uint64(try readUInt64())
        case "d": return .double(Double(bitPattern: try readUInt64()))
        case "n", "q":
            try align(2)
            _ = try take(2)
            return .int32(0)
        case "s": return .string(try readString())
        case "o": return .objectPath(try readString())
        case "g": return .signature(try readSignature())
        case "h": return .uint32(try readUInt32())
        case "v":
            let inner = try readSignature()
            return .variant(try read(type: Substring(inner)))
        case "a":
            let element = String(type.dropFirst())
            let length = Int(try readUInt32())
            try align(DBusWriter.alignment(of: element))
            let end = offset + length
            guard end <= bytes.count else { throw DBusError.malformed("array length") }
            var items: [DBusValue] = []
            while offset < end { items.append(try read(type: Substring(element))) }
            return .array(element, items)
        case "(":
            try align(8)
            var members: [DBusValue] = []
            var rest = type.dropFirst().dropLast()
            while !rest.isEmpty {
                let (member, after) = try Self.splitType(rest)
                members.append(try read(type: member))
                rest = after
            }
            return .structure(members)
        case "{":
            try align(8)
            let (key, rest) = try Self.splitType(type.dropFirst().dropLast())
            return .dictEntry(try read(type: key), try read(type: rest))
        default:
            throw DBusError.malformed("type \(first)")
        }
    }

    /// Reads values of every type in `signature`.
    mutating func readBody(signature: String) throws -> [DBusValue] {
        var values: [DBusValue] = []
        var rest = Substring(signature)
        while !rest.isEmpty {
            let (type, after) = try Self.splitType(rest)
            values.append(try read(type: type))
            rest = after
        }
        return values
    }
}

extension DBusMessage {
    /// The length of the message that starts with `header`, the first 16
    /// bytes, or `nil` if it is not a little-endian message.
    static func length(ofMessageStartingWith header: [UInt8]) -> Int? {
        guard header.count >= 16, header[0] == UInt8(ascii: "l") else { return nil }
        func word(_ at: Int) -> Int {
            Int(header[at]) | Int(header[at + 1]) << 8 | Int(header[at + 2]) << 16
                | Int(header[at + 3]) << 24
        }
        let fieldsLength = word(12)
        let headerLength = (16 + fieldsLength + 7) & ~7
        return headerLength + word(4)
    }

    static func decode(_ bytes: [UInt8]) throws -> DBusMessage {
        guard bytes.count >= 16, bytes[0] == UInt8(ascii: "l"),
            let kind = Kind(rawValue: bytes[1])
        else { throw DBusError.malformed("header") }
        var reader = DBusReader(bytes)
        reader.offset = 2
        let flags = try reader.readByte()
        _ = try reader.readByte()
        let bodyLength = Int(try reader.readUInt32())
        let serial = try reader.readUInt32()
        guard case .array(_, let fields) = try reader.read(type: "a(yv)") else {
            throw DBusError.malformed("fields")
        }
        var message = DBusMessage(kind: kind)
        message.serial = serial
        message.noReplyExpected = flags & 1 != 0
        var signature = ""
        for case .structure(let pair) in fields {
            guard pair.count == 2, case .byte(let code) = pair[0],
                case .variant(let value) = pair[1]
            else { continue }
            switch code {
            case 1: message.path = value.stringValue
            case 2: message.interface = value.stringValue
            case 3: message.member = value.stringValue
            case 4: message.errorName = value.stringValue
            case 5: if case .uint32(let serial) = value { message.replySerial = serial }
            case 6: message.destination = value.stringValue
            case 7: message.sender = value.stringValue
            case 8: signature = value.stringValue ?? ""
            default: break
            }
        }
        try reader.alignForBody()
        guard reader.offset + bodyLength <= bytes.count else { throw DBusError.malformed("body") }
        message.body = try reader.readBody(signature: signature)
        return message
    }
}

// MARK: - Connection

/// A connection to a message bus.
///
/// One thread reads; any thread can send. The handler runs on the reading
/// thread for every method call and signal that arrives.
public final class DBusConnection: @unchecked Sendable {
    private let descriptor: Int32
    private let writeLock = NSLock()
    private let stateLock = NSLock()
    private var nextSerial: UInt32 = 1
    private var closed = false
    private var waiters: [UInt32: (DBusMessage) -> Void] = [:]
    /// The bus's name for this connection, such as `:1.42`.
    public private(set) var uniqueName = ""

    /// Connects to the session bus named by `DBUS_SESSION_BUS_ADDRESS`, or
    /// the per-user socket if it is not set.
    public static func connectToSessionBus(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        handler: @escaping @Sendable (DBusMessage, DBusConnection) -> Void
    ) throws -> DBusConnection {
        let address =
            environment["DBUS_SESSION_BUS_ADDRESS"] ?? "unix:path=/run/user/\(getuid())/bus"
        return try connect(address: address, handler: handler)
    }

    /// Connects to a bus at a D-Bus address such as `unix:path=/tmp/bus`.
    /// The first address of a list that works is used.
    public static func connect(
        address: String, handler: @escaping @Sendable (DBusMessage, DBusConnection) -> Void
    ) throws -> DBusConnection {
        var lastError: Error = DBusError.connectionFailed("no address")
        for candidate in address.split(separator: ";") {
            do {
                let descriptor = try openSocket(String(candidate))
                let connection = DBusConnection(descriptor: descriptor)
                try connection.authenticate()
                connection.startReading(handler)
                let reply = try connection.call(
                    DBusMessage(
                        kind: .methodCall, path: "/org/freedesktop/DBus",
                        interface: "org.freedesktop.DBus", member: "Hello",
                        destination: "org.freedesktop.DBus"))
                connection.uniqueName = reply.body.first?.stringValue ?? ""
                return connection
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private init(descriptor: Int32) { self.descriptor = descriptor }

    deinit { close() }

    public func close() {
        let wasClosed = stateLock.withLock {
            defer { closed = true }
            return closed
        }
        guard !wasClosed else { return }
        shutdown(descriptor, Int32(SHUT_RDWR))
        _ = Glibc.close(descriptor)
    }

    private static func openSocket(_ address: String) throws -> Int32 {
        guard address.hasPrefix("unix:") else {
            throw DBusError.connectionFailed("only unix: addresses are supported")
        }
        var path: String?
        var isAbstract = false
        for part in address.dropFirst(5).split(separator: ",") {
            if part.hasPrefix("path=") { path = unescape(String(part.dropFirst(5))) }
            if part.hasPrefix("abstract=") {
                path = unescape(String(part.dropFirst(9)))
                isAbstract = true
            }
        }
        guard let path else { throw DBusError.connectionFailed("no path in \(address)") }
        let descriptor = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard descriptor >= 0 else { throw DBusError.connectionFailed("socket: \(errno)") }
        var socketAddress = sockaddr_un()
        socketAddress.sun_family = sa_family_t(AF_UNIX)
        let name = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: socketAddress.sun_path)
        guard name.count + 1 < capacity else {
            _ = Glibc.close(descriptor)
            throw DBusError.connectionFailed("path too long")
        }
        withUnsafeMutableBytes(of: &socketAddress.sun_path) { buffer in
            // An abstract name starts with a zero byte and has no terminator.
            let start = isAbstract ? 1 : 0
            for (index, byte) in name.enumerated() { buffer[start + index] = byte }
        }
        let length =
            MemoryLayout<sa_family_t>.size + 1 + name.count
        let result = withUnsafePointer(to: &socketAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Glibc.connect(descriptor, $0, socklen_t(length))
            }
        }
        guard result == 0 else {
            let code = errno
            _ = Glibc.close(descriptor)
            throw DBusError.connectionFailed("connect to \(path): errno \(code)")
        }
        return descriptor
    }

    /// Undoes the `%xx` escapes of a D-Bus address value.
    static func unescape(_ text: String) -> String {
        var bytes: [UInt8] = []
        let input = Array(text.utf8)
        var index = 0
        while index < input.count {
            if input[index] == UInt8(ascii: "%"), index + 2 < input.count,
                let value = UInt8(
                    String(decoding: input[index + 1...index + 2], as: UTF8.self), radix: 16)
            {
                bytes.append(value)
                index += 3
            } else {
                bytes.append(input[index])
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func authenticate() throws {
        let uid = String(getuid())
        let hex = uid.utf8.map { String($0, radix: 16) }.joined()
        try writeAll(Array("\0AUTH EXTERNAL \(hex)\r\n".utf8))
        var line: [UInt8] = []
        while !line.suffix(2).elementsEqual([13, 10]) {
            var byte: UInt8 = 0
            guard read(descriptor, &byte, 1) == 1 else {
                throw DBusError.authenticationFailed("the bus closed the connection")
            }
            line.append(byte)
        }
        let text = String(decoding: line, as: UTF8.self)
        guard text.hasPrefix("OK") else { throw DBusError.authenticationFailed(text) }
        try writeAll(Array("BEGIN\r\n".utf8))
    }

    private func writeAll(_ data: [UInt8]) throws {
        try writeLock.withLock {
            var offset = 0
            while offset < data.count {
                let written = data.withUnsafeBytes {
                    Glibc.send(
                        descriptor, $0.baseAddress! + offset, data.count - offset,
                        Int32(MSG_NOSIGNAL))
                }
                if written < 0 {
                    if errno == EINTR { continue }
                    throw DBusError.closed
                }
                offset += written
            }
        }
    }

    /// Sends a message and returns its serial.
    @discardableResult
    public func send(_ message: DBusMessage) throws -> UInt32 {
        let serial = stateLock.withLock {
            defer { nextSerial += 1 }
            return nextSerial
        }
        try writeAll(message.encoded(serial: serial))
        return serial
    }

    /// Sends a method call and waits for its return.
    public func call(_ message: DBusMessage, timeout: TimeInterval = 5) throws -> DBusMessage {
        let condition = NSCondition()
        nonisolated(unsafe) var answer: DBusMessage?
        let serial = stateLock.withLock {
            defer { nextSerial += 1 }
            return nextSerial
        }
        stateLock.withLock {
            waiters[serial] = { reply in
                condition.withLock {
                    answer = reply
                    condition.broadcast()
                }
            }
        }
        do {
            try writeAll(message.encoded(serial: serial))
        } catch {
            stateLock.withLock { _ = waiters.removeValue(forKey: serial) }
            throw error
        }
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while answer == nil {
            guard condition.wait(until: deadline) else {
                stateLock.withLock { _ = waiters.removeValue(forKey: serial) }
                throw DBusError.connectionFailed("no reply to \(message.member ?? "a call")")
            }
        }
        let reply = answer!
        if reply.kind == .error {
            throw DBusError.connectionFailed(
                "\(reply.errorName ?? "error"): \(reply.body.first?.stringValue ?? "")")
        }
        return reply
    }

    private func startReading(_ handler: @escaping @Sendable (DBusMessage, DBusConnection) -> Void)
    {
        let thread = Thread { [self] in
            while true {
                guard let message = readMessage() else { break }
                if message.kind == .methodReturn || message.kind == .error,
                    let serial = message.replySerial,
                    let waiter = stateLock.withLock({ waiters.removeValue(forKey: serial) })
                {
                    waiter(message)
                    continue
                }
                handler(message, self)
            }
            // Wake the callers that wait for an answer that will not come.
            let pending = stateLock.withLock {
                defer { waiters = [:] }
                return Array(waiters.values)
            }
            var gone = DBusMessage(kind: .error)
            gone.errorName = "org.freedesktop.DBus.Error.Disconnected"
            for waiter in pending { waiter(gone) }
        }
        thread.name = "Parhelion D-Bus"
        thread.start()
    }

    private func readExactly(_ count: Int) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: count)
        var filled = 0
        while filled < count {
            let received = data.withUnsafeMutableBytes {
                recv(descriptor, $0.baseAddress! + filled, count - filled, 0)
            }
            if received < 0 && errno == EINTR { continue }
            if received <= 0 { return nil }
            filled += received
        }
        return data
    }

    private func readMessage() -> DBusMessage? {
        while true {
            guard let head = readExactly(16),
                let total = DBusMessage.length(ofMessageStartingWith: head),
                total >= 16, total < 128 << 20, let rest = readExactly(total - 16)
            else { return nil }
            // A message this client cannot parse is skipped, not fatal.
            if let message = try? DBusMessage.decode(head + rest) { return message }
        }
    }
}
#endif
