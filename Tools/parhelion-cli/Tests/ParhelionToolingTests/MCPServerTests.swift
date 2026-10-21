import Foundation
import Testing

@testable import ParhelionTooling

private func makeServer() -> MCPServer {
    MCPServer(
        name: "parhelion",
        version: "0.0.0",
        instructions: "Drive the app.",
        tools: [
            MCPTool(
                name: "echo",
                title: "Echo",
                description: "Repeats its text.",
                inputSchema:
                    #"{"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}"#
            ),
            MCPTool(
                name: "picture", title: "Picture", description: "An image.",
                inputSchema: #"{"type": "object"}"#),
        ]
    ) { name, arguments in
        switch name {
        case "echo":
            guard let text = arguments.string("text") else {
                return .text("text is required", isError: true)
            }
            return .text(text)
        default:
            return MCPToolResult(content: [
                .image(Data([1, 2, 3]), mimeType: "image/png"), .text("1 × 1"),
            ])
        }
    }
}

private func respond(_ server: MCPServer, _ request: String) throws -> [String: Any] {
    let line = try #require(server.handle(request))
    #expect(!line.contains("\n"), "Responses must be one line")
    return try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
}

@Suite("MCP server")
struct MCPServerTests {
    @Test("Initialize agrees on the client's version when it is supported")
    func initialize() throws {
        let response = try respond(
            makeServer(),
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#
        )
        let result = try #require(response["result"] as? [String: Any])
        #expect(response["id"] as? Int == 1)
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "parhelion")
        #expect(result["instructions"] as? String == "Drive the app.")
    }

    @Test("Initialize offers the newest supported version for an unknown one")
    func versionNegotiation() throws {
        let response = try respond(
            makeServer(),
            #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#
        )
        #expect(response["id"] as? String == "a", "String ids are echoed as strings")
        #expect(
            (response["result"] as? [String: Any])?["protocolVersion"] as? String
                == MCPServer.supportedVersions[0])
    }

    @Test("Notifications get no response")
    func notifications() {
        #expect(
            makeServer().handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test("Ping returns an empty result")
    func ping() throws {
        let response = try respond(makeServer(), #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)
        #expect((response["result"] as? [String: Any])?.isEmpty == true)
    }

    @Test("Tools are listed with their schemas")
    func listTools() throws {
        let response = try respond(makeServer(), #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
        let tools = try #require(
            (response["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.map { $0["name"] as? String } == ["echo", "picture"])
        let schema = try #require(tools[0]["inputSchema"] as? [String: Any])
        #expect(schema["required"] as? [String] == ["text"])
    }

    @Test("Tool calls return text and image content")
    func callTools() throws {
        let server = makeServer()
        let echo = try respond(
            server,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hi\nthere"}}}"#
        )
        let result = try #require(echo["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        #expect((result["content"] as? [[String: Any]])?.first?["text"] as? String == "hi\nthere")

        let picture = try respond(
            server,
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"picture"}}"#
        )
        let content = try #require(
            (picture["result"] as? [String: Any])?["content"] as? [[String: Any]])
        #expect(content[0]["type"] as? String == "image")
        #expect(content[0]["data"] as? String == Data([1, 2, 3]).base64EncodedString())
        #expect(content[0]["mimeType"] as? String == "image/png")
    }

    @Test("Tool failures are results with isError, not protocol errors")
    func toolError() throws {
        let response = try respond(
            makeServer(),
            #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"echo","arguments":{}}}"#
        )
        #expect(response["error"] == nil)
        #expect((response["result"] as? [String: Any])?["isError"] as? Bool == true)
    }

    @Test("Protocol errors use JSON-RPC error codes")
    func protocolErrors() throws {
        let server = makeServer()
        let unknownTool = try respond(
            server,
            #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"nope"}}"#
        )
        #expect((unknownTool["error"] as? [String: Any])?["code"] as? Int == -32602)

        let unknownMethod = try respond(
            server, #"{"jsonrpc":"2.0","id":8,"method":"server/discover"}"#)
        #expect((unknownMethod["error"] as? [String: Any])?["code"] as? Int == -32601)

        let parseError = try respond(server, "{not json")
        #expect((parseError["error"] as? [String: Any])?["code"] as? Int == -32700)
        #expect(parseError["id"] is NSNull)

        let batch = try respond(server, "[]")
        #expect((batch["error"] as? [String: Any])?["code"] as? Int == -32600)
    }

    @Test("Serving reads lines until the input ends")
    func serve() {
        var input = [
            #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#,
        ]
        var output: [String] = []
        makeServer().serve(
            readLine: { input.isEmpty ? nil : input.removeFirst() }, write: { output.append($0) })
        #expect(output.count == 2)
    }
}
