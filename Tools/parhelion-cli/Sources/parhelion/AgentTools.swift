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
        get_view_tree: it lists every view with its identifier (after #) and its frame in points. Tap buttons by label or identifier, type into text \
        fields, scroll, and take screenshots to check how the screen looks. While a sheet or an \
        alert is presented, only it receives input; drag a sheet down to dismiss it. The view tree \
        shows where views end up, even while an animation is still moving them; if a reply says \
        the screen is animating, call wait before you take a screenshot. After you edit the app's \
        Swift files, call rebuild; it returns compiler errors if the build fails and keeps \
        Codable @State values when it succeeds.
        """
    }

    static let keys = [
        "backspace", "delete", "left", "right", "home", "end", "tab", "backTab", "return", "escape",
    ]

    static let definitions: [MCPTool] = [
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
                one of: id (a node identifier from get_view_tree), label (the exact text or \
                label attribute of a control; the back button's label is the previous title), \
                or x and y (a point on the screen, in points).
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "id": {"type": "string"}, "label": {"type": "string"},
                  "x": {"type": "number"}, "y": {"type": "number"}}}
                """#
        ),
        MCPTool(
            name: "type_text",
            title: "Type text",
            description: """
                Types text into the focused text field, or into field_id after focusing it. \
                Typing inserts at the caret.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "text": {"type": "string"}, "field_id": {"type": "string"}},
                 "required": ["text"]}
                """#
        ),
        MCPTool(
            name: "press_key",
            title: "Press a key",
            description: """
                Presses an editing or focus key. tab and backTab move between text fields; \
                return and escape end editing.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "key": {"type": "string", "enum": ["backspace", "delete", "left", "right", "home", "end", "tab", "backTab", "return", "escape"]}},
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
            description: "Scrolls a scroll view, by identifier, to a content offset in points.",
            inputSchema: #"""
                {"type": "object", "properties": {
                  "id": {"type": "string"}, "x": {"type": "number", "default": 0},
                  "y": {"type": "number", "default": 0}},
                 "required": ["id"]}
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
            description:
                "Waits up to 10 seconds, for example for scrolling or an animation to settle, then reports the state.",
            inputSchema: #"""
                {"type": "object", "properties": {
                  "seconds": {"type": "number", "minimum": 0, "maximum": 10, "default": 0.5}}}
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
            guard let id = arguments.string("id") else { return nil }
            return .scrollTo(id: id, x: arguments.double("x") ?? 0, y: arguments.double("y") ?? 0)
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

    static func usage(of name: String) -> String {
        switch name {
        case "tap": "tap needs one of: id, label, or both x and y."
        case "type_text": "type_text needs text."
        case "press_key": "press_key needs key, one of: \(keys.joined(separator: ", "))."
        case "scroll": "scroll needs x and y, and dx or dy."
        case "scroll_to": "scroll_to needs id."
        case "drag": "drag needs from_x, from_y, to_x, and to_y."
        default: "\(name) received arguments it does not understand."
        }
    }
}
