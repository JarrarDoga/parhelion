import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionTooling

// An MCP tool that lives in this file only: it registers with a registry and
// answers through the server, with no edit to AgentTools.swift or MCP.swift.

private struct ShoutTool: AgentTool {
    let definition = MCPTool(
        name: "shout", title: "Shout", description: "Repeats text in capitals.",
        inputSchema: #"{"type": "object", "properties": {"text": {"type": "string"}}}"#)

    func call(_ arguments: MCPArguments) -> AgentToolOutcome {
        guard let text = arguments.string("text") else {
            return .result(.text("text is required", isError: true))
        }
        return .result(.text(text.uppercased()))
    }
}

private struct PressReturnTool: AgentTool {
    let definition = MCPTool(
        name: "press_return", title: "Return", description: "Presses return.",
        inputSchema: #"{"type": "object"}"#)

    func call(_ arguments: MCPArguments) -> AgentToolOutcome { .command(.pressKey("return")) }
}

@Suite("MCP tools that plug in from their own files")
struct ExtensionToolTests {
    @Test("A registered tool is listed after registration, in order, and replaced by name")
    func listing() {
        let registry = AgentToolRegistry()
        #expect(registry.definitions.isEmpty)
        registry.register(ShoutTool())
        registry.register(PressReturnTool())
        registry.register(ShoutTool())
        #expect(registry.definitions.map(\.name) == ["press_return", "shout"])
        #expect(registry.has("shout"))
        #expect(!registry.has("whisper"))
    }

    @Test("A tool answers a call through a server")
    func answers() throws {
        let registry = AgentToolRegistry()
        registry.register(ShoutTool())
        let server = MCPServer(
            name: "parhelion", version: "0.0.0", instructions: "", tools: registry.definitions
        ) { name, arguments in
            switch registry.call(name, arguments) {
            case .result(let result)?: result
            case .command?: .text("forwarded")
            case nil: .text("unknown", isError: true)
            }
        }
        let call = """
            {"jsonrpc":"2.0","id":7,"method":"tools/call",\
            "params":{"name":"shout","arguments":{"text":"hello"}}}
            """
        let reply = try #require(server.handle(call))
        #expect(reply.contains("HELLO"))
        let list = try #require(
            server.handle(#"{"jsonrpc":"2.0","id":8,"method":"tools/list"}"#))
        #expect(list.contains("shout"))
    }

    @Test("A tool can name a command for the app instead of answering")
    func commands() {
        let registry = AgentToolRegistry()
        registry.register(PressReturnTool())
        guard case .command(let command)? = registry.call("press_return", MCPArguments([:])) else {
            Issue.record("expected a command")
            return
        }
        #expect(command == .pressKey("return"))
        #expect(registry.call("missing", MCPArguments([:])) == nil)
    }
}
