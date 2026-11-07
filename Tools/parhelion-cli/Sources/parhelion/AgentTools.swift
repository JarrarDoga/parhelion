import ParhelionPreview
import ParhelionTooling

/// The tools `parhelion mcp` offers, and how their arguments become
/// commands for the app.
enum AgentTools {
    static func instructions(product: String, device: String?) -> String {
        """
        Parhelion runs the SwiftUI app \(product) on Linux, on a simulated \(device ?? "iPhone 16") \
        screen; the Root view's frame is the screen's size in points. Screenshots show the status \
        bar and the home indicator over the app, as in the iOS Simulator. Start with \
        get_view_tree: it lists every view with its identifier (after #) and its frame in points. \
        Views the app marked with accessibilityIdentifier show it as an attribute; prefer \
        accessibility_identifier to label, id, or a position, because it survives layout and \
        text changes. Tap buttons by accessibility identifier, label or identifier, type into text \
        fields, scroll, and take screenshots to check how the screen looks. While a sheet or an \
        alert is presented, only it receives input; drag a sheet down to dismiss it. The view tree \
        shows where views end up, even while an animation is still moving them; if a reply says \
        the screen is animating or a task is running, call wait before you take a screenshot. After you edit the app's \
        Swift files, call rebuild; it returns compiler errors if the build fails and keeps \
        Codable @State values when it succeeds. To check the dark appearance or larger text, \
        call set_appearance. To check a screen against its design board, call compare_image with \
        the board's PNG.
        """
    }

    static let keys = [
        "backspace", "delete", "left", "right", "up", "down", "home", "end", "tab", "backTab",
        "return", "escape", "selectLeft", "selectRight", "selectHome", "selectEnd", "selectAll",
        "copy", "cut", "paste",
    ]

    /// The tools that plug in from files of their own; see
    /// ``AgentToolRegistry``.
    static let registry: AgentToolRegistry = {
        let registry = AgentToolRegistry.shared
        registry.register(LongPressTool())
        return registry
    }()

    /// The built-in tools, `compare_image`, then the registered ones.
    static var definitions: [MCPTool] { builtInDefinitions + [compareImage] + registry.definitions }

    private static let builtInDefinitions: [MCPTool] = [
        MCPTool(
            name: "get_view_tree",
            title: "Get the view tree",
            description: """
                The current screen as a tree of views, each with its identifier (after #), \
                its frame in points as [x, y, width × height], and its attributes. Use \
                format "json" for the full machine-readable tree.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "format": {"type": "string", "enum": ["outline", "json"], "default": "outline"}}}
                """#
        ),
        MCPTool(
            name: "screenshot",
            title: "Take a screenshot",
            description:
                "A PNG image of the screen. Scale is pixels per point; 1 is 393 × 852 pixels.",
            inputSchema: #"""
                {"type": "object", "properties": {
                  "scale": {"type": "number", "minimum": 0.25, "maximum": 3, "default": 1}}}
                """#
        ),
        MCPTool(
            name: "tap",
            title: "Tap",
            description: """
                Taps a control or focuses a text field: a button, a navigation link, a \
                toggle's Switch, a stepper's Increment or Decrement, a picker's button or \
                PickerOption, or a slider's track, whose knob moves to the point. Give exactly \
                one of: accessibility_identifier (the accessibilityIdentifier of a control; an \
                error lists the candidates if several controls have it), id (a node identifier \
                from get_view_tree), label (the exact accessibilityLabel, text, or label \
                attribute of a control; the back button's label is the previous title), or x and \
                y (a point on the screen, in points).
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "accessibility_identifier": {"type": "string"},
                  "id": {"type": "string"}, "label": {"type": "string"},
                  "x": {"type": "number"}, "y": {"type": "number"}}}
                """#
        ),
        MCPTool(
            name: "type_text",
            title: "Type text",
            description: """
                Types text into the focused text field, or into the field named by field_id (a \
                node identifier) or accessibility_identifier after focusing it. Typing inserts \
                at the caret.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "text": {"type": "string"}, "field_id": {"type": "string"},
                  "accessibility_identifier": {"type": "string"}},
                 "required": ["text"]}
                """#
        ),
        MCPTool(
            name: "press_key",
            title: "Press a key",
            description: """
                Presses an editing or focus key. tab and backTab move between text fields; \
                return and escape end editing. selectLeft, selectRight, selectHome, and \
                selectEnd extend the selection from the caret, selectAll selects the field's \
                text, copy and cut put the selection on the clipboard, and paste inserts the \
                clipboard's text in place of the selection; set_clipboard fills the clipboard.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "key": {"type": "string", "enum": ["backspace", "delete", "left", "right", "up", "down", "home", "end", "tab", "backTab", "return", "escape", "selectLeft", "selectRight", "selectHome", "selectEnd", "selectAll", "copy", "cut", "paste"]}},
                 "required": ["key"]}
                """#
        ),
        MCPTool(
            name: "scroll",
            title: "Scroll",
            description: """
                Scrolls the scroll view at x, y by dx, dy points, like a mouse wheel. A positive \
                dy moves toward the end of the content.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "x": {"type": "number"}, "y": {"type": "number"},
                  "dx": {"type": "number", "default": 0}, "dy": {"type": "number", "default": 0}},
                 "required": ["x", "y"]}
                """#
        ),
        MCPTool(
            name: "scroll_to",
            title: "Scroll to an offset",
            description: """
                Scrolls a scroll view, by id (a node identifier) or accessibility_identifier, to \
                a content offset in points.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "id": {"type": "string"}, "accessibility_identifier": {"type": "string"},
                  "x": {"type": "number", "default": 0}, "y": {"type": "number", "default": 0}}}
                """#
        ),
        MCPTool(
            name: "drag",
            title: "Drag",
            description: """
                Drags from one point to another over a duration, as a finger would. A drag that \
                starts on a slider moves its knob. A fast drag over a scroll view leaves it \
                coasting; call wait to let it settle.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "from_x": {"type": "number"}, "from_y": {"type": "number"},
                  "to_x": {"type": "number"}, "to_y": {"type": "number"},
                  "duration": {"type": "number", "default": 0.3}},
                 "required": ["from_x", "from_y", "to_x", "to_y"]}
                """#
        ),
        MCPTool(
            name: "wait",
            title: "Wait",
            description: """
                Lets `seconds` (up to 10) pass, then reports the state. Without a window or a \
                page, the app runs on a manual clock: wait moves the app's time on by `seconds` \
                in an instant, so animations, scrolling, Task.sleep, and the views' .task work \
                reach the state they would after that long, and the reply says when the next \
                timer fires. With a window or a page, the app keeps real time: wait returns \
                when scrolling, animations, and .task work finish, or after `seconds`; if none \
                is in progress, it waits the whole time, which gives other work, such as a Task \
                that a button starts, time to run.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "seconds": {"type": "number", "minimum": 0, "maximum": 10, "default": 0.5}}}
                """#
        ),
        MCPTool(
            name: "set_appearance",
            title: "Set the appearance and text size",
            description: """
                Sets the simulated device's appearance, light or dark, and its Dynamic Type \
                size, as in the device's Settings; give either or both. The app's \
                preferredColorScheme still wins for its own windows and sheets. The setting \
                stays for later rebuilds, and the view tree's Root shows it as colorScheme and \
                dynamicTypeSize when they are not light and large.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "color_scheme": {"type": "string", "enum": ["light", "dark"]},
                  "dynamic_type_size": {"type": "string", "enum": ["xSmall", "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge", "accessibility1", "accessibility2", "accessibility3", "accessibility4", "accessibility5"]}}}
                """#
        ),
        MCPTool(
            name: "rebuild",
            title: "Rebuild the app",
            description: """
                Builds the app from its current source files and restarts it, keeping Codable \
                @State values. If the build fails, returns the compiler errors with paths to \
                the source files, and the previous version keeps running.
                """,
            inputSchema: #"{"type": "object", "properties": {}}"#
        ),
        MCPTool(
            name: "app_output",
            title: "Read the app's output",
            description: "The last lines the app printed to standard output or standard error.",
            inputSchema: #"""
                {"type": "object", "properties": {
                  "lines": {"type": "integer", "minimum": 1, "maximum": 1000, "default": 50}}}
                """#
        ),
    ]

    /// The app command for a tool call, or `nil` if the arguments are not
    /// valid for the tool.
    static func command(for name: String, _ arguments: MCPArguments) -> PreviewCommand? {
        switch name {
        case "get_view_tree":
            return .inspect(json: arguments.string("format") == "json")
        case "screenshot":
            return .screenshot(scale: arguments.double("scale") ?? 1)
        case "tap":
            if let identifier = arguments.string("accessibility_identifier") {
                return .tapAccessibilityIdentifier(identifier)
            }
            if let id = arguments.string("id") { return .tapNode(id: id) }
            if let label = arguments.string("label") { return .tapButton(label: label) }
            if let x = arguments.double("x"), let y = arguments.double("y") {
                return .tapPoint(x: x, y: y)
            }
            return nil
        case "type_text":
            guard let text = arguments.string("text") else { return nil }
            return .typeText(text)
        case "press_key":
            guard let key = arguments.string("key") else { return nil }
            return .pressKey(key)
        case "scroll":
            guard let x = arguments.double("x"), let y = arguments.double("y") else { return nil }
            return .scroll(
                dx: arguments.double("dx") ?? 0, dy: arguments.double("dy") ?? 0, x: x, y: y)
        case "scroll_to":
            let x = arguments.double("x") ?? 0
            let y = arguments.double("y") ?? 0
            if let identifier = arguments.string("accessibility_identifier") {
                return .scrollToAccessibilityIdentifier(identifier, x: x, y: y)
            }
            guard let id = arguments.string("id") else { return nil }
            return .scrollTo(id: id, x: x, y: y)
        case "drag":
            guard let fromX = arguments.double("from_x"), let fromY = arguments.double("from_y"),
                let toX = arguments.double("to_x"), let toY = arguments.double("to_y")
            else { return nil }
            return .drag(
                fromX: fromX, fromY: fromY, toX: toX, toY: toY,
                duration: arguments.double("duration") ?? 0.3)
        default:
            return nil
        }
    }

    /// Whether the command names a view by accessibility identifier, which
    /// only apps built with a newer Parhelion understand.
    static func usesAccessibilityIdentifier(_ command: PreviewCommand) -> Bool {
        switch command {
        case .tapAccessibilityIdentifier, .focusAccessibilityIdentifier,
            .scrollToAccessibilityIdentifier:
            true
        default: false
        }
    }

    static func usage(of name: String) -> String {
        switch name {
        case "tap": "tap needs one of: accessibility_identifier, id, label, or both x and y."
        case "type_text": "type_text needs text."
        case "press_key": "press_key needs key, one of: \(keys.joined(separator: ", "))."
        case "scroll": "scroll needs x and y, and dx or dy."
        case "scroll_to": "scroll_to needs id or accessibility_identifier."
        case "drag": "drag needs from_x, from_y, to_x, and to_y."
        case "set_appearance":
            "set_appearance needs color_scheme (\(PreviewAppearance.colorSchemes.joined(separator: " or "))) "
                + "or dynamic_type_size (one of \(PreviewAppearance.dynamicTypeSizes.joined(separator: ", ")))."
        default: "\(name) received arguments it does not understand."
        }
    }
}
