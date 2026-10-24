import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 200),
    safeAreaInsets: EdgeInsets()
)

private struct Form: View {
    @State private var name = ""
    @State private var city = "Oslo"

    var body: some View {
        VStack {
            TextField("Name", text: $name)
            TextField("City", text: $city)
            Text("Hello, \(name) from \(city)")
        }
        .padding()
    }
}

@MainActor
private func fieldIDs(_ host: ViewHost) -> [NodeID] {
    host.root.allNodes.filter { $0.kind == "TextField" }.map(\.id)
}

@MainActor
@Suite("Text fields")
struct TextFieldTests {
    @Test("A text field fills its width, is one line tall, and records its value")
    func layout() throws {
        let host = ViewHost(Form(), device: square)
        let field = try #require(host.root.allNodes.first { $0.kind == "TextField" })
        #expect(field.attributes["placeholder"] == "Name")
        #expect(field.attributes["value"] == "")
        #expect(field.frame?.width == CGFloat(300 - 32))
        // One line of body text: 17 points on a 22-point line.
        #expect(field.frame?.height == 22)
    }

    @Test("Typing inserts at the caret and updates the bound state")
    func typing() throws {
        let host = ViewHost(Form(), device: square)
        let name = fieldIDs(host)[0]
        try host.focus(name)
        host.typeText("Ada")
        #expect(host.caretOffset == 3)
        #expect(host.nodes(withText: "Hello, Ada from Oslo").count == 1)

        host.press(.home)
        host.typeText("Dr ")
        #expect(host.nodes(withText: "Hello, Dr Ada from Oslo").count == 1)
        #expect(host.caretOffset == 3)
    }

    @Test("Editing keys delete and move the caret")
    func editingKeys() throws {
        let host = ViewHost(Form(), device: square)
        try host.focus(fieldIDs(host)[1])  // "Oslo", caret at the end.
        host.press(.backspace)
        #expect(host.nodes(withText: "Hello,  from Osl").count == 1)
        host.press(.left)
        host.press(.left)
        host.press(.delete)
        #expect(host.nodes(withText: "Hello,  from Ol").count == 1)
        #expect(host.caretOffset == 1)
        host.press(.end)
        #expect(host.caretOffset == 2)
        host.press(.right)  // Already at the end.
        #expect(host.caretOffset == 2)
    }

    @Test("Tab and Shift-Tab move focus between fields, wrapping around")
    func tabNavigation() {
        let host = ViewHost(Form(), device: square)
        let fields = fieldIDs(host)
        host.press(.tab)
        #expect(host.focusedNodeID == fields[0])
        host.press(.tab)
        #expect(host.focusedNodeID == fields[1])
        host.press(.tab)
        #expect(host.focusedNodeID == fields[0])
        host.press(.backTab)
        #expect(host.focusedNodeID == fields[1])
        host.press(.return)
        #expect(host.focusedNodeID == nil)
    }

    @Test("Typing without focus does nothing")
    func noFocus() {
        let host = ViewHost(Form(), device: square)
        host.typeText("ignored")
        host.press(.backspace)
        #expect(host.nodes(withText: "Hello,  from Oslo").count == 1)
    }

    @Test("Clicking a field focuses it and puts the caret near the click")
    func clickToFocus() throws {
        let host = ViewHost(Form(), device: square)
        let field = try #require(host.root.node(withID: fieldIDs(host)[1]))
        let city = try #require(field.frame)
        let geometry = TextFieldGeometry(node: field)
        let afterO = geometry.caretX(in: "Oslo", at: 1)

        host.pointerDown(at: CGPoint(x: city.minX + afterO + 0.5, y: city.midY))
        #expect(host.pressedNodeID == nil, "Text fields do not dim while pressed")
        host.pointerUp(at: CGPoint(x: city.minX + afterO + 0.5, y: city.midY))
        #expect(host.focusedNodeID == fieldIDs(host)[1])
        #expect(host.caretOffset == 1)
    }

    @Test("A field that leaves the tree loses focus")
    func focusFollowsTree() throws {
        struct Toggle: View {
            @State private var showField = true
            @State private var text = ""
            var body: some View {
                VStack {
                    if showField { TextField("Text", text: $text) }
                    Button("Hide") { showField = false }
                }
            }
        }
        let host = ViewHost(Toggle(), device: square)
        try host.focus(fieldIDs(host)[0])
        try host.tapButton(labeled: "Hide")
        #expect(host.focusedNodeID == nil)
    }

    @Test("Focusing something that is not a text field fails")
    func focusErrors() throws {
        let host = ViewHost(Form(), device: square)
        let text = try #require(host.root.allNodes.first { $0.kind == "Text" }).id
        #expect(throws: InteractionError.notEditable(text)) { try host.focus(text) }
        #expect(throws: InteractionError.nodeNotFound("Nope")) { try host.focus("Nope") }
    }

    @Test("A focused field draws a tint-colored caret, and an empty one its placeholder")
    func rendering() throws {
        let host = ViewHost(Form(), device: square)
        let name = try #require(host.root.node(withID: fieldIDs(host)[0])?.frame)
        let unfocused = host.render(scale: 2)
        let caretPoint = CGPoint(x: name.minX + 1, y: name.midY)
        #expect(
            unfocused.color(at: caretPoint).blue != 255 || unfocused.color(at: caretPoint).red != 0)

        try host.focus(fieldIDs(host)[0])
        let focused = host.render(scale: 2).color(at: caretPoint)
        #expect([focused.red, focused.green, focused.blue] == [0, 136, 255])

        // The placeholder draws in a light gray, not black.
        var darkest: UInt8 = 255
        for x in stride(from: name.minX + 4, to: name.minX + 40, by: 0.5) {
            for y in stride(from: name.minY, to: name.maxY, by: 0.5) {
                darkest = min(darkest, unfocused.color(at: CGPoint(x: x, y: y)).red)
            }
        }
        #expect(darkest > 100 && darkest < 255)
    }

    @Test("A preview session applies text and key messages")
    func session() throws {
        let tiny = Device(
            name: "Tiny", screenSize: CGSize(width: 120, height: 60), safeAreaInsets: EdgeInsets())
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        let host = ViewHost(Form(), device: tiny)
        for message: HostMessage in [
            .key("tab"), .text("Bo"), .key("backspace"), .text("ob"), .close,
        ] {
            try hostEnd.send(message)
        }
        try PreviewSession(host: host, channel: appEnd, scale: 1, appName: "Form").run()
        #expect(host.nodes(withText: "Hello, Bob from Oslo").count == 1)
    }
}
