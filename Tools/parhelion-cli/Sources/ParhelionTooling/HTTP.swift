import Foundation

/// The head of an HTTP/1.1 request: the request line and the header
/// fields. The web preview's server reads nothing else, because its pages
/// only send `GET` requests.
public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    /// The path of the target, without the query.
    public var path: String
    /// The query's parameters, percent-decoded. A repeated parameter keeps
    /// its first value.
    public var query: [String: String]
    /// Header fields by lowercased name. A repeated field's values are
    /// joined with commas, as HTTP allows.
    public var headers: [String: String]

    /// The most bytes a request head may have.
    public static let maximumHeadSize = 16 * 1024

    /// Parses a request head, or returns `nil` if it is not one.
    public init?(head: some Collection<UInt8>) {
        guard let text = String(validating: Array(head), as: UTF8.self) else { return nil }
        var lines = text.components(separatedBy: "\r\n")
        while lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().split(
            separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1."),
            requestLine[1].hasPrefix("/")
        else { return nil }
        method = String(requestLine[0])
        let target = requestLine[1]
        let pathEnd = target.firstIndex(of: "?") ?? target.endIndex
        guard let path = String(target[..<pathEnd]).removingPercentEncoding else { return nil }
        self.path = path
        query = [:]
        if pathEnd < target.endIndex {
            for pair in target[target.index(after: pathEnd)...].split(separator: "&") {
                let parts = pair.split(
                    separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let name = String(parts[0]).removingPercentEncoding else { continue }
                let value = parts.count > 1 ? String(parts[1]).removingPercentEncoding : ""
                if query[name] == nil, let value { query[name] = value }
            }
        }
        headers = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":"), colon > line.startIndex else { return nil }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = headers[name].map { "\($0), \(value)" } ?? value
        }
    }

    /// The length of the request head at the start of `bytes`, through the
    /// blank line that ends it, or `nil` if the head is not complete yet.
    public static func headLength(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for index in 3..<bytes.count
        where bytes[index] == 10 && bytes[index - 1] == 13 && bytes[index - 2] == 10
            && bytes[index - 3] == 13
        {
            return index + 1
        }
        return nil
    }

    /// Whether a header field's comma-separated values include `token`,
    /// ignoring case.
    func header(_ name: String, contains token: String) -> Bool {
        guard let value = headers[name] else { return false }
        return value.split(separator: ",").contains {
            $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(token) == .orderedSame
        }
    }

    /// Whether the request opens a WebSocket, as RFC 6455 describes.
    public var isWebSocketUpgrade: Bool {
        method == "GET" && header("upgrade", contains: "websocket")
            && header("connection", contains: "upgrade")
            && headers["sec-websocket-version"] == "13" && headers["sec-websocket-key"] != nil
    }
}

/// An HTTP/1.1 response. The server closes the connection after each one,
/// except after switching to a WebSocket.
public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var reason: String
    public var headers: [String: String]
    public var body: [UInt8]

    public init(status: Int, reason: String, headers: [String: String] = [:], body: [UInt8] = []) {
        self.status = status
        self.reason = reason
        self.headers = headers
        self.body = body
    }

    /// A response with a plain-text body.
    public static func text(_ status: Int, _ reason: String, _ message: String) -> HTTPResponse {
        HTTPResponse(
            status: status, reason: reason,
            headers: ["Content-Type": "text/plain; charset=utf-8"], body: Array(message.utf8))
    }

    /// The answer to a request without the access token.
    public static let forbidden = text(
        403, "Forbidden", "This preview needs the URL that parhelion printed, with its token.\n")

    /// The answer to a request for a path the server does not have.
    public static let notFound = text(404, "Not Found", "Not found.\n")

    /// The answer to a request that is not a well-formed `GET`.
    public static let badRequest = text(400, "Bad Request", "Bad request.\n")

    /// The response to a WebSocket handshake with the client's key.
    public static func switchingToWebSocket(key: String) -> HTTPResponse {
        HTTPResponse(
            status: 101, reason: "Switching Protocols",
            headers: [
                "Upgrade": "websocket", "Connection": "Upgrade",
                "Sec-WebSocket-Accept": WebSocket.acceptValue(forKey: key),
            ])
    }

    /// The status line, the header fields, and the body. Every response
    /// that is not a switch to a WebSocket closes the connection and is
    /// never cached or sent as a referrer, because its URL carries the
    /// access token.
    public func encoded() -> [UInt8] {
        var fields = headers
        if status != 101 {
            fields["Content-Length"] = String(body.count)
            fields["Connection"] = "close"
            fields["Cache-Control"] = "no-store"
            fields["Referrer-Policy"] = "no-referrer"
            fields["X-Content-Type-Options"] = "nosniff"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for name in fields.keys.sorted() { head += "\(name): \(fields[name]!)\r\n" }
        head += "\r\n"
        return Array(head.utf8) + body
    }
}

/// The secret in the web preview's URL.
///
/// Anyone who can open the page controls the app, so the server refuses
/// every request that does not carry the token in its `token` query
/// parameter, including the WebSocket handshake.
public struct AccessToken: Equatable, Sendable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    /// A new token of 128 random bits, as 32 hexadecimal digits.
    public static func random() -> AccessToken {
        var generator = SystemRandomNumberGenerator()
        let words = [generator.next(), generator.next()] as [UInt64]
        return AccessToken(words.map { String(format: "%016llx", $0) }.joined())
    }

    /// Whether a request carries the token. The comparison takes the same
    /// time wherever the first difference is, so timing does not reveal
    /// how much of a guess was right.
    public func admits(_ request: HTTPRequest) -> Bool {
        guard let offered = request.query["token"] else { return false }
        let expected = Array(value.utf8)
        let given = Array(offered.utf8)
        guard expected.count == given.count, !expected.isEmpty else { return false }
        var difference: UInt8 = 0
        for index in expected.indices { difference |= expected[index] ^ given[index] }
        return difference == 0
    }
}
