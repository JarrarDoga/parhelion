import Foundation
import ParhelionPreview

// The extension points of the tool: a new MCP tool or window hook plugs in
// from its own file by registering with one of these, with no edit to
// AgentTools.swift, MCP.swift, or WindowHost.swift. See
// docs/adr/0011-extension-seam.md.

// MARK: - MCP tools

/// What an MCP tool does with a call.
public enum AgentToolOutcome: Sendable {
    /// Send the command to the app and answer with its reply, as the
    /// built-in tools do.
    case command(PreviewCommand)
    /// Answer with a result the tool made itself.
    case result(MCPToolResult)
}

/// An MCP tool that a file of its own defines.
public protocol AgentTool: Sendable {
    /// The tool's name, description, and argument schema.
    var definition: MCPTool { get }
    /// Answers a call.
    func call(_ arguments: MCPArguments) -> AgentToolOutcome
}

/// The MCP tools offered in addition to the built-in ones.
public final class AgentToolRegistry: @unchecked Sendable {
    /// The registry that `parhelion mcp` offers.
    public static let shared = AgentToolRegistry()

    private let lock = NSLock()
    private var tools: [AgentTool] = []

    public init() {}

    /// Adds a tool, or replaces the tool of the same name.
    public func register(_ tool: AgentTool) {
        lock.withLock {
            tools.removeAll { $0.definition.name == tool.definition.name }
            tools.append(tool)
        }
    }

    /// The definitions of the registered tools, in the order they were
    /// registered.
    public var definitions: [MCPTool] {
        lock.withLock { tools.map(\.definition) }
    }

    /// Whether a registered tool has the name.
    public func has(_ name: String) -> Bool {
        lock.withLock { tools.contains { $0.definition.name == name } }
    }

    /// Answers a call to a registered tool, or returns `nil` when no
    /// registered tool has the name.
    public func call(_ name: String, _ arguments: MCPArguments) -> AgentToolOutcome? {
        let tool = lock.withLock { tools.first { $0.definition.name == name } }
        return tool?.call(arguments)
    }
}

// MARK: - Window hooks

/// What happened in the preview window, in terms that do not depend on SDL.
public struct WindowEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// A key went down. `name` is Parhelion's name for an editing or
        /// focus key, such as `tab`; `code` is the SDL key code.
        case key(name: String?, code: UInt32)
        /// Text was typed, after keyboard layout and input methods.
        case text(String)
        case pointerDown, pointerMoved, pointerUp
        /// The wheel or trackpad scrolled by `dx`, `dy` steps.
        case wheel(dx: Double, dy: Double)
        case focusGained, focusLost
        /// The window was minimized, or restored from being minimized.
        case minimized, restored
        /// Any other SDL event, by its type number.
        case other(rawType: UInt32)
    }

    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let shift = Modifiers(rawValue: 1)
        public static let control = Modifiers(rawValue: 2)
        public static let alt = Modifiers(rawValue: 4)
    }

    public var kind: Kind
    /// Where the pointer is, in screen points, for pointer and wheel events.
    public var position: (x: Double, y: Double)?
    public var modifiers: Modifiers

    public init(
        _ kind: Kind, position: (x: Double, y: Double)? = nil, modifiers: Modifiers = []
    ) {
        self.kind = kind
        self.position = position
        self.modifiers = modifiers
    }

    public static func == (lhs: WindowEvent, rhs: WindowEvent) -> Bool {
        lhs.kind == rhs.kind && lhs.position?.x == rhs.position?.x
            && lhs.position?.y == rhs.position?.y && lhs.modifiers == rhs.modifiers
    }
}

/// What a window hook does with an event.
public enum WindowHookResult: Sendable, Equatable {
    /// Forward a message to the app instead of the event's usual meaning.
    case input(HostMessage)
    /// Change the simulated device's appearance or text size.
    case appearance(PreviewAppearance.Change)
    /// Draw the window again.
    case redraw
    /// The hook took the event; do nothing else with it.
    case consumed
}

/// A handler for the preview window's events, which runs before the window's
/// own meaning for an event.
public protocol WindowHook: Sendable {
    /// What to do with an event, or `nil` to leave it to the next hook and
    /// then to the window.
    func handle(_ event: WindowEvent) -> WindowHookResult?
}

/// The hooks the preview window consults for every event.
public final class WindowHookRegistry: @unchecked Sendable {
    /// The registry the preview window uses.
    public static let shared = WindowHookRegistry()

    private let lock = NSLock()
    private var hooks: [WindowHook] = []

    public init() {}

    /// Adds a hook after the ones registered before it.
    public func register(_ hook: WindowHook) {
        lock.withLock { hooks.append(hook) }
    }

    /// The first result a hook gives for an event, or `nil` when none does.
    public func dispatch(_ event: WindowEvent) -> WindowHookResult? {
        let current = lock.withLock { hooks }
        for hook in current {
            if let result = hook.handle(event) { return result }
        }
        return nil
    }
}
