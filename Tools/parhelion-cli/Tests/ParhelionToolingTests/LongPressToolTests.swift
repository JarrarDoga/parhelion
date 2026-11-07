import ParhelionPreview
import Testing

@testable import ParhelionTooling

@Suite("The long_press tool")
struct LongPressToolTests {
    @Test("It is listed with a schema that asks for a point")
    func listing() {
        let registry = AgentToolRegistry()
        registry.register(LongPressTool())
        #expect(registry.definitions.map(\.name) == ["long_press"])
        #expect(registry.definitions[0].inputSchema.contains("\"required\": [\"x\", \"y\"]"))
    }

    @Test("A call holds a press at one point for the duration")
    func holds() {
        let registry = AgentToolRegistry()
        registry.register(LongPressTool())
        guard
            case .command(let command)? = registry.call(
                "long_press", MCPArguments(["x": 10.0, "y": 20.0, "duration": 1.5]))
        else {
            Issue.record("expected a command")
            return
        }
        #expect(command == .drag(fromX: 10, fromY: 20, toX: 10, toY: 20, duration: 1.5))
    }

    @Test("A call without a duration holds a little over the default minimum")
    func defaultDuration() {
        guard
            case .command(let command) = LongPressTool().call(
                MCPArguments(["x": 1.0, "y": 2.0]))
        else {
            Issue.record("expected a command")
            return
        }
        #expect(command == .drag(fromX: 1, fromY: 2, toX: 1, toY: 2, duration: 0.6))
    }

    @Test("A missing point or a duration out of range is an error")
    func errors() {
        let calls: [[String: Any]] = [
            ["x": 1.0],
            ["x": 1.0, "y": 1.0, "duration": 0.0],
            ["x": 1.0, "y": 1.0, "duration": 30.0],
        ]
        for arguments in calls {
            guard case .result(let result) = LongPressTool().call(MCPArguments(arguments)) else {
                Issue.record("expected an error result")
                continue
            }
            #expect(result.isError)
        }
    }
}
