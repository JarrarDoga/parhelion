import ParhelionPreview

/// The `long_press` tool: holds a press at a point, then releases it. It
/// plugs in through ``AgentToolRegistry``, and the app runs it as a drag that
/// does not move, so a view's long press gesture sees a real press: the
/// pointer going down, the app's clock moving on by the duration, and the
/// pointer going up.
public struct LongPressTool: AgentTool {
    /// The longest hold the app performs, in seconds.
    public static let longestDuration = 5.0
    /// What a hold lasts when the call gives none: a little over SwiftUI's
    /// default minimum duration of 0.5 seconds.
    public static let defaultDuration = 0.6

    public init() {}

    public var definition: MCPTool {
        MCPTool(
            name: "long_press",
            title: "Long press",
            description: """
                Presses at a point, holds for a duration, and releases, as a finger would. A \
                view with onLongPressGesture or LongPressGesture runs its action once the \
                hold reaches the gesture's minimum duration (0.5 seconds unless the view asks \
                for another). The app's clock moves on by the duration, so the hold takes no \
                real time without a window. Up to \(Int(Self.longestDuration)) seconds.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "x": {"type": "number"}, "y": {"type": "number"},
                  "duration": {"type": "number", "minimum": 0.02, "maximum": 5, "default": 0.6}},
                 "required": ["x", "y"]}
                """#
        )
    }

    public func call(_ arguments: MCPArguments) -> AgentToolOutcome {
        guard let x = arguments.double("x"), let y = arguments.double("y") else {
            return .result(.text("long_press needs x and y.", isError: true))
        }
        let duration = arguments.double("duration") ?? Self.defaultDuration
        guard duration.isFinite, duration > 0, duration <= Self.longestDuration else {
            return .result(
                .text(
                    "duration must be above 0 and at most \(Int(Self.longestDuration)) seconds.",
                    isError: true))
        }
        return .command(.drag(fromX: x, fromY: y, toX: x, toY: y, duration: duration))
    }
}
