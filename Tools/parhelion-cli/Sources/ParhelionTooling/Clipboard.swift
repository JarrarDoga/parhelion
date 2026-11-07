import Foundation
import ParhelionPreview

// The preview window's clipboard: copy, cut, paste, and select-all keys, and
// the `set_clipboard` tool. The app keeps its own pasteboard
// (`ViewHost.pasteboardText`); this file keeps it in step with the system
// clipboard when the window shows the app. It plugs in through
// `WindowHookRegistry` and `AgentToolRegistry`; see
// docs/adr/0011-extension-seam.md.

/// The system clipboard, as the window host reads and writes it. SDL3 is the
/// implementation; tests use a fake.
public protocol SystemClipboard: Sendable {
    /// The clipboard's text, or `nil` when it has none.
    func text() -> String?
    func setText(_ text: String)
}

/// Text the app copied, waiting to go to the system clipboard, and whether
/// the app shares its pasteboard at all.
///
/// The connection's reader thread hands over copied text, and the window's
/// thread puts it on the clipboard, because SDL's clipboard belongs to the
/// thread that runs the window.
public final class ClipboardBridge: @unchecked Sendable {
    /// The bridge the connection and the window hook share.
    public static let shared = ClipboardBridge()

    private let lock = NSLock()
    private var copied: String?
    private var shared = false

    public init() {}

    /// Whether the connected app welcomed ``PreviewCapability/pasteboard``,
    /// so that the host may send it pasteboard messages.
    public var isShared: Bool {
        get { lock.withLock { shared } }
        set { lock.withLock { shared = newValue } }
    }

    /// Records text the app copied.
    public func copy(_ text: String) {
        lock.withLock { copied = text }
    }

    /// The text copied since the last call, if any.
    public func takeCopied() -> String? {
        lock.withLock {
            defer { copied = nil }
            return copied
        }
    }
}

/// Turns the window's clipboard shortcuts into messages for the app:
/// Control-C, X, V, and A, and Shift with the arrow keys, Home, and End.
/// Also puts text the app copied on the system clipboard, and tells the app
/// what the clipboard holds when the window gains focus.
public struct ClipboardHook: WindowHook {
    private let bridge: ClipboardBridge
    private let clipboard: any SystemClipboard

    public init(bridge: ClipboardBridge = .shared, clipboard: any SystemClipboard) {
        self.bridge = bridge
        self.clipboard = clipboard
    }

    public func handle(_ event: WindowEvent) -> WindowHookResult? {
        // Every event, including the wake-up after a message from the app,
        // is a chance to put copied text on the clipboard.
        if let text = bridge.takeCopied() { clipboard.setText(text) }
        guard bridge.isShared else { return nil }
        switch event.kind {
        case .focusGained:
            return clipboard.text().map { .input(.pasteboard($0)) }
        case .key(let name, let code):
            let control = event.modifiers.contains(.control)
            let shift = event.modifiers.contains(.shift)
            guard !event.modifiers.contains(.alt) else { return nil }
            if control, !shift {
                // SDL's key codes for letters are the lowercase ASCII codes.
                switch code {
                case 0x61: return .input(.key("selectAll"))
                case 0x63: return .input(.key("copy"))
                case 0x78: return .input(.key("cut"))
                case 0x76:
                    // A clipboard without text pastes nothing.
                    guard let text = clipboard.text(), !text.isEmpty else { return .consumed }
                    return .input(.paste(text))
                default: return nil
                }
            }
            if shift, !control {
                switch name {
                case "left": return .input(.key("selectLeft"))
                case "right": return .input(.key("selectRight"))
                case "home": return .input(.key("selectHome"))
                case "end": return .input(.key("selectEnd"))
                default: return nil
                }
            }
            return nil
        default:
            return nil
        }
    }
}

/// `set_clipboard`: puts text on the app's pasteboard, for an agent that
/// cannot copy from anywhere else. A window shows it on the system clipboard
/// too.
public struct SetClipboardTool: AgentTool {
    public init() {}

    public var definition: MCPTool {
        MCPTool(
            name: "set_clipboard",
            title: "Set the clipboard",
            description: """
                Puts text on the clipboard, which a PasteButton pastes and the paste key \
                (press_key with key paste) inserts into the focused text field. Copy, cut, \
                and the shift arrow keys of press_key (selectLeft, selectRight, selectHome, \
                selectEnd, selectAll) fill the clipboard from a field's own text.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {"text": {"type": "string"}},
                 "required": ["text"]}
                """#
        )
    }

    public func call(_ arguments: MCPArguments) -> AgentToolOutcome {
        guard let text = arguments.string("text") else {
            return .result(.text("set_clipboard needs text.", isError: true))
        }
        return .command(.setPasteboard(text))
    }
}

/// Registers the clipboard tool and hook; call once at start.
public enum ClipboardSupport {
    public static func register(clipboard: any SystemClipboard) {
        AgentToolRegistry.shared.register(SetClipboardTool())
        WindowHookRegistry.shared.register(ClipboardHook(clipboard: clipboard))
    }
}
