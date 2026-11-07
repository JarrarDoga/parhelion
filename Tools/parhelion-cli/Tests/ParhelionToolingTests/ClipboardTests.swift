import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionTooling

private final class FakeClipboard: SystemClipboard, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    init(_ text: String? = nil) { stored = text }

    func text() -> String? { lock.withLock { stored } }
    func setText(_ text: String) { lock.withLock { stored = text } }
}

private func shared(_ clipboard: FakeClipboard) -> (ClipboardHook, ClipboardBridge) {
    let bridge = ClipboardBridge()
    bridge.isShared = true
    return (ClipboardHook(bridge: bridge, clipboard: clipboard), bridge)
}

@Suite("The window's clipboard")
struct ClipboardTests {
    @Test("Control-C, X, V, and A become keys and a paste of the system clipboard")
    func shortcuts() {
        let (hook, _) = shared(FakeClipboard("from outside"))
        func press(_ letter: Character) -> WindowHookResult? {
            hook.handle(
                WindowEvent(
                    .key(name: nil, code: letter.asciiValue.map(UInt32.init) ?? 0),
                    modifiers: .control))
        }
        #expect(press("c") == .input(.key("copy")))
        #expect(press("x") == .input(.key("cut")))
        #expect(press("a") == .input(.key("selectAll")))
        #expect(press("v") == .input(.paste("from outside")))
        #expect(press("z") == nil)
    }

    @Test("Pasting an empty clipboard sends nothing")
    func emptyPaste() {
        let (hook, _) = shared(FakeClipboard())
        let event = WindowEvent(.key(name: nil, code: 0x76), modifiers: .control)
        #expect(hook.handle(event) == .consumed)
    }

    @Test("Shift with an arrow key, Home, or End extends the selection")
    func shiftKeys() {
        let (hook, _) = shared(FakeClipboard())
        func press(_ name: String, _ modifiers: WindowEvent.Modifiers) -> WindowHookResult? {
            hook.handle(WindowEvent(.key(name: name, code: 0), modifiers: modifiers))
        }
        #expect(press("left", .shift) == .input(.key("selectLeft")))
        #expect(press("right", .shift) == .input(.key("selectRight")))
        #expect(press("home", .shift) == .input(.key("selectHome")))
        #expect(press("end", .shift) == .input(.key("selectEnd")))
        #expect(press("left", []) == nil)
        #expect(press("tab", .shift) == nil)
        // Control-Shift-A is the appearance shortcut.
        #expect(
            hook.handle(WindowEvent(.key(name: nil, code: 0x61), modifiers: [.control, .shift]))
                == nil)
    }

    @Test("Gaining focus tells the app what the clipboard holds")
    func focus() {
        let (hook, _) = shared(FakeClipboard("copied elsewhere"))
        #expect(hook.handle(WindowEvent(.focusGained)) == .input(.pasteboard("copied elsewhere")))
        let (empty, _) = shared(FakeClipboard())
        #expect(empty.handle(WindowEvent(.focusGained)) == nil)
    }

    @Test("Text the app copied reaches the system clipboard on the next event")
    func copied() {
        let clipboard = FakeClipboard()
        let (hook, bridge) = shared(clipboard)
        bridge.copy("copied in the app")
        #expect(clipboard.text() == nil)
        _ = hook.handle(WindowEvent(.other(rawType: 0x8000)))
        #expect(clipboard.text() == "copied in the app")
    }

    @Test("An app that does not share its pasteboard gets no clipboard messages")
    func unshared() {
        let bridge = ClipboardBridge()
        let hook = ClipboardHook(bridge: bridge, clipboard: FakeClipboard("x"))
        #expect(hook.handle(WindowEvent(.focusGained)) == nil)
        #expect(hook.handle(WindowEvent(.key(name: nil, code: 0x76), modifiers: .control)) == nil)
        #expect(hook.handle(WindowEvent(.key(name: "left", code: 0), modifiers: .shift)) == nil)
    }

    @Test("set_clipboard sends the text to the app")
    func tool() throws {
        let registry = AgentToolRegistry()
        registry.register(SetClipboardTool())
        guard
            case .command(.setPasteboard("sid=1"))? = registry.call(
                "set_clipboard", MCPArguments(["text": "sid=1"]))
        else {
            Issue.record("set_clipboard did not send setPasteboard")
            return
        }
        guard case .result(let result)? = registry.call("set_clipboard", MCPArguments([:])) else {
            Issue.record("set_clipboard without text did not answer")
            return
        }
        #expect(result.isError)
    }
}
