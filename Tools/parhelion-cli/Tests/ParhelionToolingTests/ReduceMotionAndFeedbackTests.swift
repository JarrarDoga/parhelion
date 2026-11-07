import ParhelionPreview
import Testing

@testable import ParhelionTooling

@Suite("Reduce Motion and sensory feedback in the tools")
struct ReduceMotionAndFeedbackTests {
    @Test("get_sensory_feedback asks the app for the events, and clears them on request")
    func feedbackTool() {
        let registry = AgentToolRegistry()
        registry.register(SensoryFeedbackTool())
        #expect(registry.definitions.map(\.name) == ["get_sensory_feedback"])
        guard case .command(let read)? = registry.call("get_sensory_feedback", MCPArguments([:]))
        else {
            Issue.record("expected a command")
            return
        }
        #expect(read == .sensoryFeedback(clear: false))
        guard
            case .command(let cleared)? = registry.call(
                "get_sensory_feedback", MCPArguments(["clear": true]))
        else {
            Issue.record("expected a command")
            return
        }
        #expect(cleared == .sensoryFeedback(clear: true))
    }

    @Test("Reduce Motion toggles, sets, and reaches the launch environment and the app")
    func appearance() throws {
        let start = PreviewAppearance()
        #expect(!start.reduceMotion)
        #expect(start.environment[previewReduceMotionEnvironmentKey] == "0")
        let on = try #require(start.applying(.toggleReduceMotion))
        #expect(on.reduceMotion)
        #expect(on.environment[previewReduceMotionEnvironmentKey] == "1")
        #expect(on.reduceMotionCommand == .setReduceMotion(true))
        #expect(on.summary == "Reduce Motion")
        #expect(on.applying(.toggleReduceMotion)?.reduceMotion == false)
        #expect(on.applying(.setReduceMotion(false))?.reduceMotion == false)
        // The scheme and the size are untouched.
        #expect(on.applying(.set(colorScheme: "dark", dynamicTypeSize: nil))?.reduceMotion == true)
        let all = try #require(
            on.applying(.set(colorScheme: "dark", dynamicTypeSize: "accessibility2")))
        #expect(all.summary == "Dark, accessibility2, Reduce Motion")
    }

    @Test("Only an app that lists the capability takes the Reduce Motion command")
    func support() {
        var hello = PreviewHello(appName: "App", screenWidth: 393, screenHeight: 852, scale: 2)
        #expect(!PreviewAppearance.supportsAccessibilitySettings(hello))
        hello.capabilities = PreviewCapability.all
        #expect(PreviewAppearance.supportsAccessibilitySettings(hello))
    }

    @Test("Control-Shift-M switches Reduce Motion in the window, and other keys are left alone")
    func windowHook() {
        let hook = ReduceMotionWindowHook()
        let key = WindowEvent.Kind.key(name: nil, code: ReduceMotionWindowHook.keyCode)
        #expect(
            hook.handle(WindowEvent(key, modifiers: [.control, .shift]))
                == .appearance(.toggleReduceMotion))
        #expect(hook.handle(WindowEvent(key, modifiers: [.control])) == nil)
        #expect(hook.handle(WindowEvent(key, modifiers: [.control, .shift, .alt])) == nil)
        #expect(
            hook.handle(WindowEvent(.key(name: nil, code: 0x61), modifiers: [.control, .shift]))
                == nil)
        #expect(hook.handle(WindowEvent(.pointerDown)) == nil)
    }

    @Test("The hook plugs in through the registry")
    func registry() {
        let registry = WindowHookRegistry()
        registry.register(ReduceMotionWindowHook())
        let event = WindowEvent(
            .key(name: nil, code: ReduceMotionWindowHook.keyCode), modifiers: [.control, .shift])
        #expect(registry.dispatch(event) == .appearance(.toggleReduceMotion))
    }
}
