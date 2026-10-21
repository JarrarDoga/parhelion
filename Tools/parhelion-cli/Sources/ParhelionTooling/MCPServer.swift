import Foundation

/// A tool a Model Context Protocol server offers.
public struct MCPTool: Sendable {
    public var name: String
    public var title: String
    public var description: String
    /// The JSON Schema of the tool's arguments, as JSON text.
    public var inputSchema: String

    public init(name: String, title: String, description: String, inputSchema: String) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// What a tool call returns.
public struct MCPToolResult: Sendable {
    public enum Content: Sendable, Equatable {
        case text(String)
        case image(Data, mimeType: String)
    }

    public var content: [Content]
    /// Whether the tool ran but failed. The model sees the content and can
    /// try again; this is not a protocol error.
    public var isError: Bool

    public init(content: [Content], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    public static func text(_ text: String, isError: Bool = false) -> MCPToolResult {
        MCPToolResult(content: [.text(text)], isError: isError)
    }
}

/// The arguments of a tool call, with typed accessors.
public struct MCPArguments {
    public let values: [String: Any]

    public init(_ values: [String: Any]) {
        self.values = values
    }

    public func string(_ key: String) -> String? { values[key] as? String }
    public func double(_ key: String) -> Double? { (values[key] as? NSNumber)?.doubleValue }
    public func bool(_ key: String) -> Bool? { (values[key] as? NSNumber)?.boolValue }
    public func int(_ key: String) -> Int? { (values[key] as? NSNumber)?.intValue }
}

/// A Model Context Protocol server for the stdio transport: one JSON-RPC
/// message per line on standard input, one per line on standard output.
///
/// It implements the lifecycle and the tools feature of protocol versions
/// 2024-11-05 through 2025-11-25. A client of a later, stateless version
/// probes with `server/discover`, gets "method not found", and falls back
/// to `initialize`.
public final class MCPServer: Sendable {
    public typealias Handler =
        @Sendable (_ name: String, _ arguments: MCPArguments) -> MCPToolResult

    /// The protocol versions this server speaks, newest first.
    public static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    let name: String
    let version: String
    let instructions: String
    let tools: [MCPTool]
    let handler: Handler

    public init(
        name: String,
        version: String,
        instructions: String,
        tools: [MCPTool],
        handler: @escaping Handler
    ) {
        self.name = name
        self.version = version
        self.instructions = instructions
        self.tools = tools
        self.handler = handler
    }

    /// Reads requests until the input ends, and writes each response.
    public func serve(readLine: () -> String?, write: (String) -> Void) {
        while let line = readLine() {
            if let response = handle(line) { write(response) }
        }
    }

    /// The response to one line of input, or `nil` for notifications.
    public func handle(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) else {
            return encode(error: -32700, message: "Parse error", id: NSNull())
        }
        guard let message = object as? [String: Any], let method = message["method"] as? String
        else {
            return encode(error: -32600, message: "Invalid Request", id: NSNull())
        }
        // A message without an id is a notification, which gets no response.
        guard let id = message["id"], !(id is NSNull) else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            let agreed =
                requested.flatMap { Self.supportedVersions.contains($0) ? $0 : nil }
                ?? Self.supportedVersions[0]
            return encode(
                result: [
                    "protocolVersion": agreed,
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": name, "title": "Parhelion", "version": version],
                    "instructions": instructions,
                ],
                id: id
            )

        case "ping":
            return encode(result: [:], id: id)

        case "tools/list":
            let list: [[String: Any]] = tools.map { tool in
                [
                    "name": tool.name,
                    "title": tool.title,
                    "description": tool.description,
                    "inputSchema":
                        (try? JSONSerialization.jsonObject(with: Data(tool.inputSchema.utf8)))
                        ?? ["type": "object"],
                ]
            }
            return encode(result: ["tools": list], id: id)

        case "tools/call":
            guard let toolName = params["name"] as? String else {
                return encode(error: -32602, message: "Missing tool name", id: id)
            }
            guard tools.contains(where: { $0.name == toolName }) else {
                return encode(error: -32602, message: "Unknown tool: \(toolName)", id: id)
            }
            let arguments = MCPArguments(params["arguments"] as? [String: Any] ?? [:])
            let result = handler(toolName, arguments)
            let content: [[String: Any]] = result.content.map { item in
                switch item {
                case .text(let text):
                    return ["type": "text", "text": text]
                case .image(let data, let mimeType):
                    return [
                        "type": "image", "data": data.base64EncodedString(), "mimeType": mimeType,
                    ]
                }
            }
            return encode(result: ["content": content, "isError": result.isError], id: id)

        default:
            return encode(error: -32601, message: "Method not found: \(method)", id: id)
        }
    }

    private func encode(result: [String: Any], id: Any) -> String {
        encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func encode(error code: Int, message: String, id: Any) -> String {
        encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    /// One line of JSON. JSONSerialization escapes newlines inside strings,
    /// so the line never contains a raw newline, as the stdio transport
    /// requires.
    private func encode(_ object: [String: Any]) -> String {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.withoutEscapingSlashes]
            )
        else {
            return
                #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}
