import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 200),
    safeAreaInsets: EdgeInsets()
)

private struct Fields: View {
    @State private var first = "Hello, world"
    @State private var second = ""
    @State private var pasted: [String] = []
    @State private var links: [URL] = []

    var body: some View {
        VStack {
            TextField("First", text: $first)
            TextField("Second", text: $second)
            PasteButton(payloadType: String.self) { pasted = $0 }
            PasteButton(payloadType: URL.self) { links = $0 }
            Text("pasted=\(pasted.joined(separator: "|")) links=\(links.count)")
        }
        .padding()
    }
}

@MainActor
private func fieldIDs(_ host: ViewHost) -> [NodeID] {
    host.root.allNodes.filter { $0.kind == "TextField" }.map(\.id)
}

@MainActor
private func value(_ host: ViewHost, _ index: Int) -> String {
    host.root.node(withID: fieldIDs(host)[index])?.attributes["value"] ?? ""
}

@MainActor
@Suite("Paste, copy, and text selection")
struct PasteboardTests {
    @Test("A PasteButton is a button labeled Paste, disabled while the pasteboard is empty")
    func pasteButtonOutline() throws {
        let host = ViewHost(PasteButton(payloadType: String.self) { _ in }, device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ PasteButton
                   └─ Button buttonStyle=borderedProminent disabled=true
                      └─ Label
                         ├─ Image systemName=doc.on.clipboard
                         └─ Text "Paste"
                """)
        host.pasteboardText = "x"
        host.update()
        #expect(
            host.root.outline() == """
                Root
                └─ PasteButton
                   └─ Button buttonStyle=borderedProminent
                      └─ Label
                         ├─ Image systemName=doc.on.clipboard
                         └─ Text "Paste"
                """)
    }

    @Test("Tapping a PasteButton hands the pasteboard to its action")
    func pasteButton() throws {
        let host = ViewHost(Fields(), device: screen)
        let button = try #require(
            host.root.allNodes.first { $0.kind == "PasteButton" }?.children.first?.id)
        // Nothing on the pasteboard: the button is disabled.
        #expect(throws: InteractionError.self) { try host.tap(button) }

        host.pasteboardText = "cookie=abc"
        try host.tap(button)
        #expect(host.nodes(withText: "pasted=cookie=abc links=0").count == 1)
    }

    @Test("A URL button pastes text only when it is a URL")
    func urlButton() throws {
        let host = ViewHost(Fields(), device: screen)
        let buttons = host.root.allNodes.filter { $0.kind == "PasteButton" }
        func isDisabled(_ index: Int) -> Bool {
            host.root.node(withID: buttons[index].id)?.allNodes.contains {
                $0.attributes["disabled"] == "true"
            } ?? false
        }
        host.pasteboardText = "just words"
        host.update()
        #expect(!isDisabled(0))
        #expect(isDisabled(1))
        host.pasteboardText = "https://example.com/a"
        host.update()
        #expect(!isDisabled(1))
    }

    @Test("Shift with the arrow keys selects, and a plain arrow collapses the selection")
    func selecting() throws {
        let host = ViewHost(Fields(), device: screen)
        try host.focus(fieldIDs(host)[0])
        #expect(host.selectedRange == nil)
        host.press(.home)
        host.press(.selectRight)
        host.press(.selectRight)
        #expect(host.selectedRange == 0..<2)
        #expect(host.selectedText == "He")
        host.press(.selectLeft)
        #expect(host.selectedText == "H")
        host.press(.right)
        #expect(host.selectedRange == nil)
        #expect(host.caretOffset == 1)

        host.press(.selectEnd)
        #expect(host.selectedText == "ello, world")
        host.press(.left)
        #expect(host.caretOffset == 1)
        host.press(.selectAll)
        #expect(host.selectedText == "Hello, world")
    }

    @Test("Typing and deleting replace the selection")
    func replacing() throws {
        let host = ViewHost(Fields(), device: screen)
        try host.focus(fieldIDs(host)[0])
        host.select(0..<5)
        host.typeText("Bye")
        #expect(value(host, 0) == "Bye, world")
        #expect(host.caretOffset == 3)
        #expect(host.selectedRange == nil)

        host.select(3..<10)
        host.press(.backspace)
        #expect(value(host, 0) == "Bye")
        host.press(.selectAll)
        host.press(.delete)
        #expect(value(host, 0) == "")
    }

    @Test("A selection in one field is copied and pasted into another")
    func copyAndPaste() throws {
        let host = ViewHost(Fields(), device: screen)
        let ids = fieldIDs(host)
        try host.focus(ids[0])
        host.select(7..<12)
        host.press(.copy)
        #expect(host.pasteboardText == "world")
        // Copying leaves the field and the selection alone.
        #expect(value(host, 0) == "Hello, world")
        #expect(host.selectedText == "world")

        try host.focus(ids[1])
        host.press(.paste)
        #expect(value(host, 1) == "world")
        #expect(host.caretOffset == 5)
        host.press(.paste)
        #expect(value(host, 1) == "worldworld")
    }

    @Test("Cut copies the selection and removes it; paste replaces a selection")
    func cut() throws {
        let host = ViewHost(Fields(), device: screen)
        let ids = fieldIDs(host)
        try host.focus(ids[0])
        host.select(5..<12)
        host.press(.cut)
        #expect(host.pasteboardText == ", world")
        #expect(value(host, 0) == "Hello")

        host.select(0..<5)
        host.pasteboardText = "Howdy"
        host.press(.paste)
        #expect(value(host, 0) == "Howdy")
    }

    @Test("Copy with nothing selected keeps the pasteboard; paste with nothing on it does nothing")
    func nothingToDo() throws {
        let host = ViewHost(Fields(), device: screen)
        try host.focus(fieldIDs(host)[0])
        host.pasteboardText = "keep"
        host.press(.copy)
        #expect(host.pasteboardText == "keep")
        host.pasteboardText = nil
        host.press(.paste)
        #expect(value(host, 0) == "Hello, world")
    }

    @Test("Pasting into a one-line field turns line breaks into spaces")
    func lineBreaks() throws {
        let host = ViewHost(Fields(), device: screen)
        let ids = fieldIDs(host)
        try host.focus(ids[1])
        host.pasteboardText = "one\ntwo\r\nthree"
        host.press(.paste)
        #expect(value(host, 1) == "one two three")
    }

    @Test("Copying tells the session; setting the pasteboard from outside does not")
    func copyCallback() throws {
        let host = ViewHost(Fields(), device: screen)
        var copied: [String] = []
        host.onCopy { copied.append($0) }
        try host.focus(fieldIDs(host)[0])
        host.select(0..<5)
        host.press(.copy)
        host.paste("from the system")
        #expect(copied == ["Hello"])
        #expect(value(host, 0) == "from the system, world")
    }

    @Test("Dragging over a field selects the text between the press and the pointer")
    func dragSelects() throws {
        let host = ViewHost(Fields(), device: screen)
        let id = fieldIDs(host)[0]
        let frame = try #require(host.root.node(withID: id)?.frame)
        let y = frame.midY
        host.drag(from: CGPoint(x: frame.minX + 1, y: y), to: CGPoint(x: frame.minX + 200, y: y))
        #expect(host.focusedNodeID == id)
        #expect(host.selectedText == "Hello, world")
        // A click puts the caret and drops the selection.
        host.pointerDown(at: CGPoint(x: frame.minX + 1, y: y))
        host.pointerUp(at: CGPoint(x: frame.minX + 1, y: y))
        #expect(host.selectedRange == nil)
        #expect(host.caretOffset == 0)
    }

    @Test("Losing focus ends the selection")
    func focusEnds() throws {
        let host = ViewHost(Fields(), device: screen)
        let ids = fieldIDs(host)
        try host.focus(ids[0])
        host.press(.selectAll)
        host.press(.tab)
        #expect(host.focusedNodeID == ids[1])
        #expect(host.selectedRange == nil)
        try host.focus(ids[0])
        host.press(.selectAll)
        host.press(.escape)
        #expect(host.selectedRange == nil)
    }

    @Test("The selection draws a highlight behind the text")
    func highlight() throws {
        let host = ViewHost(Fields(), device: screen)
        try host.focus(fieldIDs(host)[0])
        host.press(.home)
        let plain = host.render(scale: 1)
        host.press(.selectEnd)
        let selected = host.render(scale: 1)
        #expect(plain.pngData() != selected.pngData())
        // The frame cache keeps no stale selection.
        host.press(.right)
        #expect(host.render(scale: 1).pngData() != selected.pngData())
    }

    @Test("The inspection reports the selection")
    func inspection() throws {
        let host = ViewHost(Fields(), device: screen)
        try host.focus(fieldIDs(host)[0])
        host.select(1..<4)
        let reply = host.execute(.inspect(json: false))
        #expect(reply.message.contains("selected characters 1..<4"))
        let json = host.execute(.inspect(json: true)).message
        #expect(json.contains("\"selectedRange\":[1,4]"))
    }

    @Test("set_clipboard fills the pasteboard that paste reads")
    func setPasteboardCommand() throws {
        let host = ViewHost(Fields(), device: screen)
        var copied: [String] = []
        host.onCopy { copied.append($0) }
        let reply = host.execute(.setPasteboard("sid=42"))
        #expect(reply.ok)
        #expect(host.pasteboardText == "sid=42")
        #expect(copied == ["sid=42"])
        try host.focus(fieldIDs(host)[1])
        #expect(host.execute(.pressKey("paste")).ok)
        #expect(value(host, 1) == "sid=42")
        #expect(host.execute(.pressKey("selectAll")).ok)
        #expect(host.selectedText == "sid=42")
    }

    @Test("A session pastes the host's clipboard and sends copied text back, once welcomed")
    func session() throws {
        // A small screen, so that the frames fit in the socket's buffer.
        let tiny = Device(
            name: "Tiny", screenSize: CGSize(width: 120, height: 60), safeAreaInsets: EdgeInsets())
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        let host = ViewHost(Fields(), device: tiny)
        let welcome = PreviewWelcome(capabilities: [PreviewCapability.pasteboard])
        for message: HostMessage in [
            .welcome(welcome), .key("tab"), .paste("Ann"), .key("selectAll"), .key("copy"),
            .close,
        ] {
            try hostEnd.send(message)
        }
        try PreviewSession(host: host, channel: appEnd, scale: 1, appName: "Fields").run()
        #expect(value(host, 0) == "Hello, worldAnn")

        var copied: [String] = []
        while let message = try hostEnd.receiveAppMessage(timeout: 0.2) {
            if case .pasteboard(let text) = message { copied.append(text) }
        }
        #expect(copied == ["Hello, worldAnn"])
    }

    @Test("A session sends no pasteboard messages to a host that did not welcome them")
    func sessionWithoutWelcome() throws {
        // A small screen, so that the frames fit in the socket's buffer.
        let tiny = Device(
            name: "Tiny", screenSize: CGSize(width: 120, height: 60), safeAreaInsets: EdgeInsets())
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        let host = ViewHost(Fields(), device: tiny)
        for message: HostMessage in [.key("tab"), .key("selectAll"), .key("copy"), .close] {
            try hostEnd.send(message)
        }
        try PreviewSession(host: host, channel: appEnd, scale: 1, appName: "Fields").run()
        #expect(host.pasteboardText == "Hello, world")
        while let message = try hostEnd.receiveAppMessage(timeout: 0.2) {
            if case .pasteboard = message { Issue.record("sent \(message)") }
        }
    }
}
