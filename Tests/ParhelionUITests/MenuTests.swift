import Foundation
import Testing

@testable import ParhelionUI

/// A 300 × 500 screen with 20 points of safe area at the top and bottom.
private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 500),
    safeAreaInsets: EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0)
)

@MainActor
private func center(_ host: ViewHost, label: String) throws -> CGPoint {
    let node = try #require(
        host.root.allNodes.first { $0.kind == "Button" && $0.label == label && $0.frame != nil })
    let frame = try #require(node.frame)
    return CGPoint(x: frame.midX, y: frame.midY)
}

/// What the actions of a menu did, in order.
@MainActor
private final class Log {
    var entries: [String] = []
}

private struct SongMenu: View {
    let log: Log

    var body: some View {
        Menu {
            ControlGroup {
                Button {
                    log.entries.append("next")
                } label: {
                    Label("Play next", systemImage: "text.insert")
                }
                Button {
                    log.entries.append("last")
                } label: {
                    Label("Play last", systemImage: "text.append")
                }
                Button {
                    log.entries.append("like")
                } label: {
                    Label("Like", systemImage: "heart")
                }
            }
            Button {
                log.entries.append("album")
            } label: {
                Label("Go to album", systemImage: "square.stack")
            }
            Button {
                log.entries.append("artist")
            } label: {
                Label("Go to artist", systemImage: "person.circle")
            }
            Button("Remove", role: .destructive) { log.entries.append("remove") }
        } label: {
            Image(systemName: "ellipsis")
        }
    }
}

@MainActor
@Suite("Menu")
struct MenuTests {
    @Test("A closed menu is a button that marks itself as a menu")
    func closed() {
        let log = Log()
        let host = ViewHost(
            Menu("Options") {
                Button("One") { log.entries.append("one") }
            }, device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ Button menu=true
                   └─ Text "Options"
                """)
    }

    @Test("Tapping the button opens the menu, and tapping an item runs it and closes the menu")
    func opensAndRuns() throws {
        let log = Log()
        let host = ViewHost(
            Menu("Options") {
                Button("One") { log.entries.append("one") }
                Button("Two") { log.entries.append("two") }
            }, device: screen)
        try host.tapButton(labeled: "Options")
        #expect(
            host.root.outline() == """
                Root
                ├─ Button expanded=true menu=true
                │  └─ Text "Options"
                └─ MenuPopover anchor=Menu/Button label=Dismiss Menu
                   └─ MenuPanel label=Menu
                      ├─ Button
                      │  └─ Text "One"
                      └─ Button
                         └─ Text "Two"
                """)
        try host.tapButton(labeled: "Two")
        #expect(log.entries == ["two"])
        #expect(!host.root.allNodes.contains { $0.kind == "MenuPopover" })
    }

    @Test("A tap outside the menu closes it without running an item")
    func tapOutside() throws {
        let log = Log()
        let host = ViewHost(
            Menu("Options") { Button("One") { log.entries.append("one") } }, device: screen)
        try host.tapButton(labeled: "Options")
        try host.tap(at: CGPoint(x: 5, y: 480))
        #expect(log.entries.isEmpty)
        #expect(!host.root.allNodes.contains { $0.kind == "MenuPopover" })
    }

    @Test("Sections get a header and a separator, a Divider is a separator, destructive is red")
    func structure() throws {
        let host = ViewHost(
            Menu("Options") {
                Section("Queue") {
                    Button("Play next") {}
                }
                Section {
                    Button("Share") {}
                }
                Divider()
                Button("Delete", role: .destructive) {}
            }, device: screen)
        try host.tapButton(labeled: "Options")
        let popover = try #require(host.root.children.first { $0.kind == "MenuPopover" })
        #expect(
            popover.outline() == """
                MenuPopover anchor=Menu/Button label=Dismiss Menu
                └─ MenuPanel label=Menu
                   ├─ Section
                   │  ├─ SectionHeader foregroundStyle=secondary
                   │  │  └─ Text "Queue" font=footnote
                   │  └─ Button
                   │     └─ Text "Play next"
                   ├─ MenuSeparator
                   ├─ Section
                   │  └─ Button
                   │     └─ Text "Share"
                   ├─ MenuSeparator
                   └─ Button foregroundStyle=red role=destructive
                      └─ Text "Delete"
                """)
    }

    @Test("The menu opens next to its button, inside the safe area, 250 points wide")
    func placement() throws {
        let host = ViewHost(
            Menu("Options") {
                Button("One") {}
                Button("Two") {}
            }, device: screen)
        try host.tapButton(labeled: "Options")
        let button = try #require(host.root.allNodes.first { $0.kind == "Button" }?.frame)
        let panel = try #require(host.root.allNodes.first { $0.kind == "MenuPanel" }?.frame)
        #expect(panel.width == 250)
        #expect(abs(panel.height - (2 * 42 + 2 * 10)) < 0.01)
        #expect(panel.minY == button.minY)
        #expect(panel.minX >= 16 && panel.maxX <= 300 - 16)
    }

    @Test("A control group is one row of equal columns, with icons above titles")
    func controlGroup() throws {
        let log = Log()
        let host = ViewHost(SongMenu(log: log), device: screen)
        try host.tapButton(labeled: "")
        let group = try #require(host.root.allNodes.first { $0.kind == "ControlGroup" })
        let columns = group.children.compactMap(\.frame)
        #expect(columns.count == 3)
        #expect(columns.allSatisfy { $0.width == columns[0].width && $0.height == 64 })
        #expect(columns[1].minX == columns[0].maxX)
        for button in group.children {
            let label = try #require(button.children.first)
            let icon = try #require(label.children.first?.frame)
            let title = try #require(label.children.last?.frame)
            #expect(icon.maxY <= title.minY)
        }
        try host.tapButton(labeled: "Play last")
        #expect(log.entries == ["last"])
    }

    @Test("Items with icons put their titles after a column for the icons")
    func iconColumn() throws {
        let log = Log()
        let host = ViewHost(SongMenu(log: log), device: screen)
        try host.tapButton(labeled: "")
        let panel = try #require(host.root.allNodes.first { $0.kind == "MenuPanel" }?.frame)
        let album = try #require(
            host.root.allNodes.first { $0.kind == "Button" && $0.label == "Go to album" })
        let label = try #require(album.children.first)
        let icon = try #require(label.children.first?.frame)
        let title = try #require(label.children.last?.frame)
        #expect(icon.minX == panel.minX + 10 + 16)
        #expect(title.minX == panel.minX + 10 + 40)
        #expect(album.frame?.height == 42)
    }

    @Test("A long title makes the menu wider than 250 points, within the margins and 320 points")
    func widens() throws {
        let host = ViewHost(
            Menu("Options") {
                Button {
                } label: {
                    Label("Pick a stretch from here", systemImage: "scissors")
                }
            }, device: .iPhone18ProMax)
        try host.tapButton(labeled: "Options")
        let wide = try #require(host.root.allNodes.first { $0.kind == "MenuPanel" }?.frame)
        #expect(wide.width > 250 && wide.width < 320)

        let narrow = ViewHost(
            Menu("Options") {
                Button("A title that is much too long to fit in a menu of any reasonable size") {}
            }, device: screen)
        try narrow.tapButton(labeled: "Options")
        let capped = try #require(narrow.root.allNodes.first { $0.kind == "MenuPanel" }?.frame)
        // The 300-point screen less two 16-point margins.
        #expect(capped.width == 268)
    }

    @Test("A disabled menu does not open")
    func disabled() throws {
        let host = ViewHost(
            Menu("Options") { Button("One") {} }.disabled(true), device: screen)
        #expect(throws: InteractionError.self) { try host.tapButton(labeled: "Options") }
        #expect(!host.root.allNodes.contains { $0.kind == "MenuPopover" })
    }

    @Test("With a primary action, a tap runs it and a long press opens the menu")
    func primaryAction() throws {
        let log = Log()
        let host = ViewHost(
            Menu(
                content: { Button("Two") { log.entries.append("two") } },
                label: { Text("Split") },
                primaryAction: { log.entries.append("primary") }), device: screen)
        try host.tapButton(labeled: "Split")
        #expect(log.entries == ["primary"])
        #expect(!host.root.allNodes.contains { $0.kind == "MenuPopover" })
        let button = try #require(host.root.allNodes.first { $0.kind == "Button" }?.frame)
        try host.longPress(at: CGPoint(x: button.midX, y: button.midY))
        #expect(host.root.allNodes.contains { $0.kind == "MenuPopover" })
        try host.tapButton(labeled: "Two")
        #expect(log.entries == ["primary", "two"])
    }

    @Test(
        "A menu opens from a button in a toolbar-less list row, and the state of the screen stays")
    func inList() throws {
        struct Screen: View {
            let log: Log
            @State var taps = 0
            var body: some View {
                List {
                    HStack {
                        Text("Song")
                        Spacer()
                        Menu {
                            Button("Go to album") { log.entries.append("album") }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                    Button("Count \(taps)") { taps += 1 }
                }
            }
        }
        let log = Log()
        let host = ViewHost(Screen(log: log), device: screen)
        try host.tapButton(labeled: "Count 0")
        let menu = try #require(
            host.root.allNodes.first { $0.attributes["menu"] == "true" }?.frame)
        try host.tap(at: CGPoint(x: menu.midX, y: menu.midY))
        try host.tapButton(labeled: "Go to album")
        #expect(log.entries == ["album"])
        #expect(host.root.allNodes.contains { $0.label == "Count 1" })
    }
}

@MainActor
@Suite("contextMenu")
struct ContextMenuTests {
    private struct Row: View {
        let log: Log
        var withPreview = false

        var body: some View {
            if withPreview {
                row.contextMenu {
                    Button("Play next") { log.entries.append("next") }
                    Button("Delete", role: .destructive) { log.entries.append("delete") }
                } preview: {
                    Text("Preview of the song").frame(width: 200, height: 120)
                }
            } else {
                row.contextMenu {
                    Button("Play next") { log.entries.append("next") }
                    Button("Delete", role: .destructive) { log.entries.append("delete") }
                }
            }
        }

        var row: some View {
            HStack {
                Text("Song")
                Spacer()
            }
            .padding()
            .frame(width: 280)
        }
    }

    @Test("A modifier changes nothing until a long press")
    func closed() {
        let host = ViewHost(Row(log: Log()), device: screen)
        #expect(!host.root.allNodes.contains { $0.kind == "ContextMenu" })
    }

    @Test("A long press lifts the view to 1.03 and opens the menu; a tap on an item runs it")
    func opensAndRuns() throws {
        let log = Log()
        let host = ViewHost(Row(log: log), device: screen)
        try host.longPress(at: CGPoint(x: 150, y: 250))
        #expect(
            host.root.children.last?.outline() == """
                ContextMenu anchor=Row/else/HStack label=Dismiss Menu
                ├─ ContextMenuPreview shadow(color: black@0.25, radius: 12, y: 6) scaleEffect(1.03) background=background custom=false
                │  └─ HStack padding(16) frame(width: 280)
                │     ├─ Text "Song"
                │     └─ Spacer
                └─ MenuPanel label=Menu
                   ├─ Button
                   │  └─ Text "Play next"
                   └─ Button foregroundStyle=red role=destructive
                      └─ Text "Delete"
                """)
        try host.tapButton(labeled: "Play next")
        #expect(log.entries == ["next"])
        #expect(!host.root.allNodes.contains { $0.kind == "ContextMenu" })
    }

    @Test("The lifted view keeps its place, and the menu opens below it")
    func liftedFrames() throws {
        let host = ViewHost(Row(log: Log()), device: screen)
        let original = try #require(host.root.allNodes.first { $0.kind == "HStack" }?.frame)
        try host.longPress(at: CGPoint(x: 150, y: 250))
        let preview = try #require(host.root.allNodes.first { $0.kind == "ContextMenuPreview" })
        #expect(preview.frame == original)
        let panel = try #require(host.root.allNodes.first { $0.kind == "MenuPanel" }?.frame)
        #expect(panel.minY > original.maxY)
        #expect(panel.width == 250)
    }

    @Test("A menu that does not fit below the view opens above it")
    func opensAbove() throws {
        let host = ViewHost(
            VStack {
                Spacer()
                Row(log: Log())
            }, device: screen)
        let original = try #require(host.root.allNodes.first { $0.kind == "HStack" }?.frame)
        try host.longPress(at: CGPoint(x: original.midX, y: original.midY))
        let panel = try #require(host.root.allNodes.first { $0.kind == "MenuPanel" }?.frame)
        #expect(panel.maxY < original.minY)
    }

    @Test("A tap outside closes the menu without running an item")
    func tapOutside() throws {
        let log = Log()
        let host = ViewHost(Row(log: log), device: screen)
        try host.longPress(at: CGPoint(x: 150, y: 250))
        try host.tap(at: CGPoint(x: 5, y: 5))
        #expect(log.entries.isEmpty)
        #expect(!host.root.allNodes.contains { $0.kind == "ContextMenu" })
    }

    @Test("A preview of its own takes the place of the copy of the view")
    func customPreview() throws {
        let log = Log()
        let host = ViewHost(Row(log: log, withPreview: true), device: screen)
        try host.longPress(at: CGPoint(x: 150, y: 250))
        let preview = try #require(host.root.allNodes.first { $0.kind == "ContextMenuPreview" })
        #expect(preview.attributes["custom"] == "true")
        #expect(preview.allNodes.contains { $0.text == "Preview of the song" })
        #expect(!preview.allNodes.contains { $0.text == "Song" })
        #expect(preview.frame?.size == CGSize(width: 200, height: 120))
        try host.tapButton(labeled: "Delete")
        #expect(log.entries == ["delete"])
    }

    @Test("A long press on a disabled view opens nothing")
    func disabled() {
        let host = ViewHost(Row(log: Log()).disabled(true), device: screen)
        #expect(throws: InteractionError.self) {
            try host.longPress(at: CGPoint(x: 150, y: 250))
        }
    }
}

/// Rustle's song list: a row has a menu button, and a long press opens the
/// same menu on the lifted row.
private struct SongList: View {
    let log: Log

    private let songs = [
        ("Blue in Green", "Miles Davis"), ("So What", "Miles Davis"), ("Take Five", "Dave Brubeck"),
        ("Naima", "John Coltrane"), ("Giant Steps", "John Coltrane"),
    ]

    @ViewBuilder
    private func menuItems(_ title: String) -> some View {
        ControlGroup {
            Button {
                log.entries.append("next \(title)")
            } label: {
                Label("Play next", systemImage: "text.insert")
            }
            Button {
                log.entries.append("last \(title)")
            } label: {
                Label("Play last", systemImage: "text.append")
            }
            Button {
                log.entries.append("like \(title)")
            } label: {
                Label("Like", systemImage: "heart")
            }
        }
        Button {
            log.entries.append("album \(title)")
        } label: {
            Label("Go to album", systemImage: "square.stack")
        }
        Button {
            log.entries.append("artist \(title)")
        } label: {
            Label("Go to artist", systemImage: "person.circle")
        }
        Button {
            log.entries.append("stretch \(title)")
        } label: {
            Label("Pick a stretch from here", systemImage: "scissors")
        }
        .tint(.blue)
        .foregroundStyle(.tint)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(songs, id: \.0) { title, artist in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(title).font(.headline)
                            Text(artist).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            menuItems(title)
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 32, height: 32)
                        }
                        .buttonStyle(.glass)
                    }
                    .contextMenu { menuItems(title) }
                }
            }
            .navigationTitle("Collection")
        }
    }
}

@MainActor
@Suite("Menu rendering")
struct MenuRenderingTests {
    private func write(_ host: ViewHost, _ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["PARHELION_TEST_PNG_DIR"] else {
            return
        }
        let frame = host.render(scale: 2, chrome: .systemBars)
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        try? frame.pngData().write(to: URL(fileURLWithPath: directory + "/" + name + ".png"))
    }

    @Test("An open context menu blurs the screen behind it and draws glass over it")
    func contextMenuDraws() throws {
        let log = Log()
        let host = ViewHost(SongList(log: log), device: .iPhone18ProMax)
        let closed = host.render(scale: 1)
        write(host, "song-list")
        let row = try #require(
            host.root.allNodes.first { $0.kind == "Text" && $0.text == "So What" }?.frame)
        try host.longPress(at: CGPoint(x: row.midX, y: row.midY))
        host.advanceTime(by: 1)
        write(host, "context-menu")
        let open = host.render(scale: 1)
        let panel = try #require(host.root.allNodes.first { $0.kind == "MenuPanel" }?.frame)
        // The screen is blurred: text of another row is smeared, so a pixel
        // on its glyph edge changed.
        var changed = 0
        for y in stride(from: 150, to: 400, by: 3) {
            for x in stride(from: 20, to: 200, by: 3)
            where closed.color(at: CGPoint(x: x, y: y)) != open.color(at: CGPoint(x: x, y: y)) {
                changed += 1
            }
        }
        #expect(changed > 100)
        // The panel is not the page background.
        let inPanel = open.color(at: CGPoint(x: panel.midX, y: panel.minY + 4))
        #expect(inPanel != closed.color(at: CGPoint(x: panel.midX, y: panel.minY + 4)))
        try host.tapButton(labeled: "Go to artist")
        #expect(log.entries == ["artist So What"])
    }

    @Test("The menu button opens the same menu from the row")
    func buttonMenuDraws() throws {
        let log = Log()
        let host = ViewHost(SongList(log: log), device: .iPhone18ProMax)
        let menus = host.root.allNodes.filter { $0.attributes["menu"] == "true" }
        let button = try #require(menus.first?.frame)
        try host.tap(at: CGPoint(x: button.midX, y: button.midY))
        host.advanceTime(by: 1)
        write(host, "menu-button")
        try host.tapButton(labeled: "Like")
        #expect(log.entries == ["like Blue in Green"])
    }
}
