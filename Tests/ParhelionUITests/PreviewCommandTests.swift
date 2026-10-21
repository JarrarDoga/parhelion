import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

private let small = Device(
    name: "Small", screenSize: CGSize(width: 200, height: 300), safeAreaInsets: EdgeInsets())

private struct Screen: View {
    @State private var count = 0
    @State private var name = ""

    var body: some View {
        VStack {
            Text("Count: \(count)")
            Button("Add") { count += 1 }
            TextField("Name", text: $name)
            Text("Name: \(name)")
            ScrollView {
                ForEach(0..<20) { _ in Color.blue.frame(width: 50, height: 40) }
            }
            .frame(height: 100)
        }
    }
}

@MainActor
@Suite("Preview commands")
struct PreviewCommandTests {
    @Test("Inspecting returns an outline with identifiers and frames")
    func inspectOutline() {
        let host = ViewHost(Screen(), device: small)
        let reply = host.execute(.inspect(json: false))
        #expect(reply.ok)
        #expect(reply.message.hasPrefix("revision \(host.revision)\nRoot  [0, 0, 200 × 300]"))
        #expect(reply.message.contains("#Screen/VStack/1/Button"))
    }

    @Test("Inspecting as JSON includes the tree and the editing state")
    func inspectJSON() throws {
        let host = ViewHost(Screen(), device: small)
        try host.focus(host.root.allNodes.first { $0.kind == "TextField" }!.id)
        let reply = host.execute(.inspect(json: true))
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(reply.message.utf8)) as? [String: Any]
        )
        #expect(object["focusedNodeID"] as? String == "Screen/VStack/2/TextField")
        #expect(object["caretOffset"] as? Int == 0)
        #expect((object["root"] as? [String: Any])?["kind"] as? String == "Root")
    }

    @Test("Taps, typing, and keys change the app and report what happened")
    func actions() {
        let host = ViewHost(Screen(), device: small)
        #expect(
            host.execute(.tapButton(label: "Add")).message == "Tapped the button labeled \"Add\".")
        #expect(host.nodes(withText: "Count: 1").count == 1)

        let noFocus = host.execute(.typeText("x"))
        #expect(!noFocus.ok)
        #expect(host.execute(.focus(id: "Screen/VStack/2/TextField")).ok)
        #expect(host.execute(.typeText("Ada")).ok)
        #expect(host.execute(.pressKey("backspace")).ok)
        #expect(host.nodes(withText: "Name: Ad").count == 1)

        let badKey = host.execute(.pressKey("f13"))
        #expect(!badKey.ok)
        #expect(badKey.message.contains("backspace"))
    }

    @Test("Errors are explained in words")
    func errors() {
        let host = ViewHost(Screen(), device: small)
        #expect(
            host.execute(.tapButton(label: "Missing")).message
                == "No button is labeled \"Missing\".")
        #expect(host.execute(.tapNode(id: "Nope")).message == "No node has the identifier Nope.")
        #expect(!host.execute(.tapPoint(x: 199, y: 1)).ok)
    }

    @Test("Screenshots return a PNG at the requested scale")
    func screenshot() throws {
        let host = ViewHost(Screen(), device: small)
        let reply = host.execute(.screenshot(scale: 1))
        let png = try #require(reply.png)
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(reply.message == "200 × 300 pixels at scale 1.")
        #expect(!host.execute(.screenshot(scale: 10)).ok)
    }

    @Test("A fast drag over a scroll view scrolls it and leaves it moving")
    func drag() throws {
        let host = ViewHost(Screen(), device: small)
        let scrollView = try #require(host.root.allNodes.first { $0.kind == "ScrollView" })
        let frame = try #require(scrollView.frame)
        let reply = host.execute(
            .drag(fromX: 100, fromY: frame.maxY - 5, toX: 100, toY: frame.minY + 5, duration: 0.1)
        )
        #expect(reply.ok)
        #expect(reply.isAnimating)
        #expect((host.scrollOffset(of: scrollView.id)?.y ?? 0) > 50)
    }

    @Test("A preview session answers commands with replies")
    func session() throws {
        let tiny = Device(
            name: "Tiny", screenSize: CGSize(width: 60, height: 60), safeAreaInsets: EdgeInsets())
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        let host = ViewHost(Screen(), device: tiny)
        try hostEnd.send(.command(id: 7, .tapButton(label: "Add")))
        try hostEnd.send(.command(id: 8, .inspect(json: false)))
        try hostEnd.send(.close)
        try PreviewSession(host: host, channel: appEnd, scale: 1, appName: "Screen").run()

        var replies: [Int: PreviewReply] = [:]
        while let message = try hostEnd.receiveAppMessage(timeout: 0.2) {
            if case .reply(let id, let reply) = message { replies[id] = reply }
        }
        #expect(replies[7]?.ok == true)
        #expect(replies[8]?.message.contains("Count: 1") == true)
    }
}
