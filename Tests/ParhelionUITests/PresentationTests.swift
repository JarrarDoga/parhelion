import Foundation
import Testing

@testable import ParhelionUI

/// A 300 × 400 screen with 20 points of safe area at the top and bottom.
private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 400),
    safeAreaInsets: EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0)
)

@MainActor
private final class Log {
    var entries: [String] = []
}

private struct SheetContent: View {
    @State private var count = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented

    var body: some View {
        VStack {
            Text("Count: \(count)")
            Text(isPresented ? "Presented" : "Not presented")
            Button("Increment") { count += 1 }
            Button("Close") { dismiss() }
        }
    }
}

private struct SheetHost: View {
    let log: Log
    @State private var isShowing = false

    var body: some View {
        VStack {
            Button("Show") { isShowing = true }
            Button("Behind") { log.entries.append("behind") }
        }
        .sheet(isPresented: $isShowing, onDismiss: { log.entries.append("dismissed") }) {
            SheetContent()
        }
    }
}

private struct Item: Identifiable {
    var id: String
}

private struct ItemSheetHost: View {
    @State private var item: Item?

    var body: some View {
        VStack {
            Button("A") { item = Item(id: "a") }
            Button("B") { item = Item(id: "b") }
        }
        .sheet(item: $item) { item in
            Text("Item \(item.id)")
        }
    }
}

private struct AlertHost: View {
    let log: Log
    @State private var isShowing = false

    var body: some View {
        Button("Delete") { isShowing = true }
            .alert("Delete the file?", isPresented: $isShowing) {
                Button("Delete", role: .destructive) { log.entries.append("deleted") }
                Button("Cancel", role: .cancel) { log.entries.append("cancelled") }
            } message: {
                Text("You cannot undo this.")
            }
    }
}

private struct ColorKey: EnvironmentKey {
    static var defaultValue: String { "none" }
}

extension EnvironmentValues {
    fileprivate var testColor: String {
        get { self[ColorKey.self] }
        set { self[ColorKey.self] = newValue }
    }
}

private struct ColorReader: View {
    @Environment(\.testColor) private var color

    var body: some View {
        Text("Color: \(color)")
    }
}

@MainActor
private func texts(_ node: ViewNode) -> [String] {
    node.allNodes.compactMap(\.text)
}

@MainActor
@Suite("Presentation")
struct PresentationTests {
    @Test("A sheet joins the root of the tree above the content")
    func sheetOutline() throws {
        let host = ViewHost(SheetHost(log: Log()), device: screen)
        try host.tapButton(labeled: "Show")
        #expect(host.root.children.map(\.kind) == ["VStack", "Sheet"])
        let sheet = host.root.children[1]
        #expect(sheet.id == "SheetHost/sheet")
        #expect(texts(sheet) == ["Count: 0", "Presented", "Increment", "Close"])
        #expect(host.interactiveRoot.id == sheet.id)
        // From the safe area's top down to the bottom of the screen.
        #expect(sheet.frame == CGRect(x: 0, y: 20, width: 300, height: 380))
    }

    @Test("Only the sheet receives input while it is presented")
    func modality() throws {
        let log = Log()
        let host = ViewHost(SheetHost(log: log), device: screen)
        let behind = try #require(host.root.allNodes.first { $0.label == "Behind" })
        try host.tapButton(labeled: "Show")
        #expect(throws: InteractionError.covered(behind.id)) { try host.tap(behind.id) }
        #expect(throws: InteractionError.noButton(label: "Behind")) {
            try host.tapButton(labeled: "Behind")
        }
        #expect(log.entries.isEmpty)
    }

    @Test("dismiss closes the sheet, onDismiss runs, and the sheet's state is discarded")
    func dismissAction() throws {
        let log = Log()
        let host = ViewHost(SheetHost(log: log), device: screen)
        try host.tapButton(labeled: "Show")
        try host.tapButton(labeled: "Increment")
        #expect(texts(host.root).contains("Count: 1"))
        try host.tapButton(labeled: "Close")
        #expect(host.root.children.count == 1)
        #expect(log.entries == ["dismissed"])
        try host.tapButton(labeled: "Show")
        #expect(texts(host.root).contains("Count: 0"))
    }

    @Test("Dragging a sheet down far enough dismisses it")
    func dragToDismiss() throws {
        let host = ViewHost(SheetHost(log: Log()), device: screen)
        try host.tapButton(labeled: "Show")
        host.drag(from: CGPoint(x: 150, y: 60), to: CGPoint(x: 150, y: 120), duration: 0.2)
        #expect(host.root.children.last?.frame?.minY == 20)
        host.pointerDown(at: CGPoint(x: 150, y: 60))
        host.pointerMoved(to: CGPoint(x: 150, y: 100))
        #expect(host.root.children.last?.frame?.minY == 60)
        host.pointerMoved(to: CGPoint(x: 150, y: 220))
        host.pointerUp(at: CGPoint(x: 150, y: 220))
        #expect(host.root.children.map(\.kind) == ["VStack"])
    }

    @Test("An item sheet shows its item and is identified by the item's ID")
    func itemSheet() throws {
        let host = ViewHost(ItemSheetHost(), device: screen)
        try host.tapButton(labeled: "A")
        #expect(host.root.children.last?.id == "ItemSheetHost/sheet[a]")
        #expect(texts(host.root.children[1]) == ["Item a"])
    }

    @Test("A medium detent shows the sheet over half of the screen")
    func detents() throws {
        var isShowing = true
        let host = ViewHost(
            Text("Content").sheet(
                isPresented: Binding(get: { isShowing }, set: { isShowing = $0 })
            ) {
                Text("Half").presentationDetents([.medium, .large])
            },
            device: screen
        )
        let sheet = host.root.children[1]
        #expect(sheet.attributes["detents"] == "large,medium")
        #expect(sheet.frame?.minY == 200)
    }

    @Test("A full-screen cover covers the screen")
    func fullScreenCover() {
        let host = ViewHost(
            Text("Content").fullScreenCover(isPresented: .constant(true)) { Text("Cover") },
            device: screen
        )
        let cover = host.root.children[1]
        #expect(cover.kind == "FullScreenCover")
        #expect(cover.frame == CGRect(x: 0, y: 0, width: 300, height: 400))
    }

    @Test("An alert shows its title, message, and buttons, with cancel first in a row")
    func alertOutline() throws {
        let host = ViewHost(AlertHost(log: Log()), device: screen)
        try host.tapButton(labeled: "Delete")
        let alert = host.root.children[1]
        #expect(
            alert.outline() == """
                Alert
                ├─ Text "Delete the file?" font=headline
                ├─ Text "You cannot undo this."
                ├─ Button role=cancel
                │  └─ Text "Cancel" font=body.medium
                └─ Button role=destructive
                   └─ Text "Delete" font=body.medium
                """)
        let frame = try #require(alert.frame)
        #expect(frame.width == 300)
        #expect(abs(frame.midY - 200) < 0.01)
        let cancel = try #require(alert.children[2].frame)
        #expect(cancel.width == 132 && cancel.height == 48)
    }

    @Test("An alert's button runs its action, then dismisses the alert")
    func alertAction() throws {
        let log = Log()
        let host = ViewHost(AlertHost(log: log), device: screen)
        try host.tapButton(labeled: "Delete")
        // The button behind the alert has the same label, but only the
        // alert receives input.
        try host.tapButton(labeled: "Delete")
        #expect(log.entries == ["deleted"])
        #expect(host.root.children.count == 1)
    }

    @Test("An alert without actions has an OK button")
    func defaultButton() throws {
        var isShowing = true
        let host = ViewHost(
            Text("Content").alert(
                "Saved", isPresented: Binding(get: { isShowing }, set: { isShowing = $0 })
            ) {},
            device: screen
        )
        try host.tapButton(labeled: "OK")
        #expect(!isShowing)
    }

    @Test("An alert can present data")
    func presentingData() {
        let host = ViewHost(
            Text("Content").alert("Error", isPresented: .constant(true), presenting: "Disk full") {
                _ in
                Button("Retry") {}
            } message: { detail in
                Text(detail)
            },
            device: screen
        )
        #expect(texts(host.root.children[1]) == ["Error", "Disk full", "Retry"])
    }

    @Test("A destructive button's label is red")
    func destructiveRole() throws {
        let host = ViewHost(Button("Delete", role: .destructive) {}, device: screen)
        let button = host.root.children[0]
        #expect(button.attributes["role"] == "destructive")
        let text = try #require(button.children[0].frame)
        let frame = host.render(scale: 4)
        // Sample the text's pixels and find the reddest one.
        var reddest = (red: UInt8(0), green: UInt8(255))
        var x = text.minX
        while x < text.maxX {
            let color = frame.color(at: CGPoint(x: x, y: text.midY))
            if color.green < reddest.green { reddest = (color.red, color.green) }
            x += 0.25
        }
        #expect(reddest.red == 255 && reddest.green < 100)
    }

    @Test("dismiss in a pushed view pops it")
    func dismissPushedView() throws {
        let host = ViewHost(
            NavigationStack {
                NavigationLink("Open") { SheetContent() }
            },
            device: screen
        )
        try host.tapButton(labeled: "Open")
        #expect(texts(host.root).contains("Presented"))
        try host.tapButton(labeled: "Close")
        #expect(texts(host.root) == ["Open"])
    }

    @Test("Environment values flow to content, and environment(_:_:) changes them")
    func environment() {
        let host = ViewHost(
            VStack {
                ColorReader()
                ColorReader().environment(\.testColor, "blue")
            },
            device: screen
        )
        #expect(texts(host.root) == ["Color: none", "Color: blue"])
    }
}
