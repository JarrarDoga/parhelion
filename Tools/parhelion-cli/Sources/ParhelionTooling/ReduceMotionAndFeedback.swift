import ParhelionPreview

/// The `get_sensory_feedback` tool: lists the haptics that views asked for,
/// as `sensoryFeedback` modifiers play them. Linux plays nothing, so the app
/// records each one. It plugs in through ``AgentToolRegistry``.
public struct SensoryFeedbackTool: AgentTool {
    public init() {}

    public var definition: MCPTool {
        MCPTool(
            name: "get_sensory_feedback",
            title: "Read the sensory feedback",
            description: """
                Lists the haptic feedback that views asked for with the sensoryFeedback \
                modifier, oldest first (the last 50), one per line with its name, such as \
                selection, success, or impact.medium, the view that asked, and the app's time. \
                Linux plays nothing, so this is how to check a haptic. The view tree's Root \
                also lists the newest ten in its sensoryFeedback attribute. With clear, the \
                list starts over, so the next call shows only what happens after this one.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "clear": {"type": "boolean", "default": false}}}
                """#
        )
    }

    public func call(_ arguments: MCPArguments) -> AgentToolOutcome {
        .command(.sensoryFeedback(clear: arguments.bool("clear") ?? false))
    }
}

/// The key that switches Reduce Motion in the preview window: Control-Shift-M,
/// like the Simulator's accessibility shortcuts with Control in place of
/// Command. It plugs in through ``WindowHookRegistry``.
public struct ReduceMotionWindowHook: WindowHook {
    /// The SDL key code of `m`.
    public static let keyCode: UInt32 = 0x6D

    public init() {}

    public func handle(_ event: WindowEvent) -> WindowHookResult? {
        guard case .key(_, let code) = event.kind, code == Self.keyCode,
            event.modifiers.contains([.control, .shift]), !event.modifiers.contains(.alt)
        else { return nil }
        return .appearance(.toggleReduceMotion)
    }
}
