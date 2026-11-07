import ParhelionPreview
import Testing

@testable import ParhelionTooling

@Suite("The set_scene_phase tool and the window's scene phases")
struct ScenePhaseToolTests {
    @Test("The tool is listed and turns a phase into a command")
    func tool() {
        let registry = AgentToolRegistry()
        registry.register(ScenePhaseTool())
        #expect(registry.definitions.map(\.name) == ["set_scene_phase"])
        for phase in ["active", "inactive", "background"] {
            guard
                case .command(let command)? = registry.call(
                    "set_scene_phase", MCPArguments(["phase": phase]))
            else {
                Issue.record("expected a command for \(phase)")
                continue
            }
            #expect(command == .setScenePhase(phase))
        }
    }

    @Test("A missing or unknown phase is an error")
    func errors() {
        for arguments: [String: Any] in [[:], ["phase": "asleep"], ["phase": 3]] {
            guard case .result(let result) = ScenePhaseTool().call(MCPArguments(arguments)) else {
                Issue.record("expected an error result")
                continue
            }
            #expect(result.isError)
        }
    }

    private func command(_ phase: String) -> WindowHookResult {
        .input(.command(id: ScenePhaseWindowHook.commandID, .setScenePhase(phase)))
    }

    @Test("Losing focus is inactive, minimizing is background, and coming back is active")
    func window() {
        let hook = ScenePhaseWindowHook()
        #expect(hook.handle(WindowEvent(.focusGained)) == nil)
        #expect(hook.handle(WindowEvent(.focusLost)) == command("inactive"))
        #expect(hook.handle(WindowEvent(.minimized)) == command("background"))
        #expect(hook.handle(WindowEvent(.restored)) == command("inactive"))
        #expect(hook.handle(WindowEvent(.focusGained)) == command("active"))
        #expect(hook.handle(WindowEvent(.focusLost)) == command("inactive"))
        #expect(hook.handle(WindowEvent(.focusLost)) == nil)
    }

    @Test("A window restored while it has focus is active; other events are left alone")
    func restoredWithFocus() {
        let hook = ScenePhaseWindowHook()
        #expect(hook.handle(WindowEvent(.minimized)) == command("background"))
        #expect(hook.handle(WindowEvent(.restored)) == command("active"))
        #expect(hook.handle(WindowEvent(.pointerDown, position: (1, 1))) == nil)
        #expect(hook.handle(WindowEvent(.other(rawType: 1))) == nil)
    }

    @Test("The registry gives the hook's command first")
    func registry() {
        let registry = WindowHookRegistry()
        registry.register(ScenePhaseWindowHook())
        #expect(registry.dispatch(WindowEvent(.focusLost)) == command("inactive"))
    }
}
