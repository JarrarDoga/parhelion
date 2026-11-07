import Foundation
import ParhelionPreview

/// The `set_scene_phase` tool: moves the app between `active`, `inactive`, and
/// `background`, as the system does when the app loses focus or goes away.
/// Views that read `@Environment(\.scenePhase)` see the new phase, and their
/// `onChange(of: scenePhase)` actions run before the tool answers. It plugs in
/// through ``AgentToolRegistry``.
public struct ScenePhaseTool: AgentTool {
    /// The phases the tool accepts, by SwiftUI's case names.
    public static let phases = ["active", "inactive", "background"]

    public init() {}

    public var definition: MCPTool {
        MCPTool(
            name: "set_scene_phase",
            title: "Set the scene phase",
            description: """
                Moves the app to a scene phase: active, inactive, or background. A view or app \
                that reads @Environment(\\.scenePhase) sees it, and an onChange(of: scenePhase) \
                action runs once per change, so you can test what the app does when it goes to \
                the background and returns. The phase moves straight to the one you set; \
                SwiftUI on a phone passes through inactive on the way, so set inactive first \
                to see that step. The preview window sets inactive when it loses focus and \
                background when it is minimized.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "phase": {"type": "string", "enum": ["active", "inactive", "background"]}},
                 "required": ["phase"]}
                """#
        )
    }

    public func call(_ arguments: MCPArguments) -> AgentToolOutcome {
        guard let phase = arguments.string("phase"), Self.phases.contains(phase) else {
            return .result(
                .text(
                    "set_scene_phase needs phase: \(Self.phases.joined(separator: ", ")).",
                    isError: true))
        }
        return .command(.setScenePhase(phase))
    }
}

/// A window hook that turns focus and minimizing into scene phases: the
/// window losing focus makes the app `inactive`, minimizing it makes the app
/// `background`, and getting focus back makes it `active`. It tells the app
/// only when the phase changes.
public final class ScenePhaseWindowHook: WindowHook, @unchecked Sendable {
    /// The id the hook gives its commands. Nobody waits for the app's reply to
    /// them, and the host keeps at most one reply under this id.
    public static let commandID = -1

    private let lock = NSLock()
    private var focused = true
    private var minimized = false
    private var phase = "active"

    public init() {}

    public func handle(_ event: WindowEvent) -> WindowHookResult? {
        let next: String? = lock.withLock {
            switch event.kind {
            case .focusGained: focused = true
            case .focusLost: focused = false
            case .minimized: minimized = true
            case .restored: minimized = false
            default: return nil
            }
            let current = minimized ? "background" : focused ? "active" : "inactive"
            defer { phase = current }
            return current == phase ? nil : current
        }
        guard let next else { return nil }
        return .input(.command(id: Self.commandID, .setScenePhase(next)))
    }
}
