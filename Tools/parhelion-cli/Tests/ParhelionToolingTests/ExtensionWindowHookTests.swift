import ParhelionPreview
import Testing

@testable import ParhelionTooling

// A window hook that lives in this file only: it registers with a registry
// and sees window events before the window's own meaning for them, with no
// edit to WindowHost.swift.

private struct FunctionKeyHook: WindowHook {
    func handle(_ event: WindowEvent) -> WindowHookResult? {
        switch event.kind {
        case .key(_, let code) where code == 0x4000_003E:
            // F5 asks for dark mode.
            return .appearance(.set(colorScheme: "dark", dynamicTypeSize: nil))
        case .key(let name, _) where name == "escape" && event.modifiers.contains(.shift):
            return .consumed
        case .pointerDown where event.position?.x ?? 0 > 1000:
            return .input(.pointerDown(x: 0, y: 0))
        case .focusLost:
            return .redraw
        default:
            return nil
        }
    }
}

@Suite("Window hooks that plug in from their own files")
struct ExtensionWindowHookTests {
    @Test("A hook answers the events it handles and leaves the others")
    func dispatch() {
        let registry = WindowHookRegistry()
        registry.register(FunctionKeyHook())
        #expect(
            registry.dispatch(WindowEvent(.key(name: nil, code: 0x4000_003E)))
                == .appearance(.set(colorScheme: "dark", dynamicTypeSize: nil)))
        #expect(
            registry.dispatch(WindowEvent(.key(name: "escape", code: 27), modifiers: .shift))
                == .consumed)
        #expect(registry.dispatch(WindowEvent(.key(name: "escape", code: 27))) == nil)
        #expect(registry.dispatch(WindowEvent(.focusLost)) == .redraw)
        #expect(
            registry.dispatch(WindowEvent(.pointerDown, position: (2000, 5)))
                == .input(.pointerDown(x: 0, y: 0)))
        #expect(registry.dispatch(WindowEvent(.pointerDown, position: (5, 5))) == nil)
    }

    @Test("Hooks run in the order they were registered, and the first answer wins")
    func order() {
        struct Fixed: WindowHook {
            let result: WindowHookResult?
            func handle(_ event: WindowEvent) -> WindowHookResult? { result }
        }
        let registry = WindowHookRegistry()
        #expect(registry.dispatch(WindowEvent(.focusGained)) == nil)
        registry.register(Fixed(result: nil))
        registry.register(Fixed(result: .redraw))
        registry.register(Fixed(result: .consumed))
        #expect(registry.dispatch(WindowEvent(.focusGained)) == .redraw)
    }
}
