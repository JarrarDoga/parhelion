import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

private struct Track: Identifiable {
    var id: Int
    var title: String { "Track \(id)" }
}

private func tracks(_ count: Int) -> [Track] { (0..<count).map(Track.init) }

private struct LongList: View {
    var count = 5000
    var body: some View {
        NavigationStack {
            List(tracks(count)) { track in
                Text(track.title)
            }
            .navigationTitle("Songs")
        }
    }
}

@MainActor
private func listID(_ host: ViewHost) throws -> NodeID {
    try #require(host.root.allNodes.first { $0.kind == "List" }).id
}

@MainActor
private func trackNumbers(_ host: ViewHost) -> [Int] {
    host.root.allNodes.filter { $0.kind == "Text" }.compactMap { node in
        node.text.flatMap { text in
            text.hasPrefix("Track ") ? Int(text.dropFirst(6)) : nil
        }
    }
}

@MainActor
@Suite("Lazy list rows")
struct LazyListTests {
    @Test("A list of 5,000 rows creates the rows near the screen")
    func longList() throws {
        let host = ViewHost(LongList())
        let section = try #require(host.root.allNodes.first { $0.kind == "Section" })
        #expect(section.attributes["lazyCount"] == "5000")
        let numbers = trackNumbers(host)
        #expect(numbers.first == 0)
        #expect(numbers.count <= 40)
        // Every row is a cell at the list's minimum height, 52 points.
        let list = try #require(host.root.allNodes.first { $0.kind == "List" })
        let height = try #require(list.attributes["contentSize"]?.split(separator: " ").last)
        let content = try #require(Double(height))
        // 5,000 rows, the insets above and below, and the section.
        #expect(abs(content - (5000 * 52 + 35 + 35)) < 100)
    }

    @Test("A long list shows only its window of rows in the outline")
    func longListOutline() throws {
        let host = ViewHost(
            List {
                Section("Songs") {
                    ForEach(0..<1000, id: \.self) { Text("Song \($0)") }
                }
            },
            device: Device(
                name: "Test", screenSize: CGSize(width: 200, height: 160),
                safeAreaInsets: EdgeInsets()))
        try host.scroll(try listID(host), to: CGPoint(x: 0, y: 26_000))
        #expect(
            host.root.outline() == """
                Root
                └─ List contentOffset=0, 26000 contentSize=200 × 51860.25
                   └─ Section lazyCount=1001 lazyResolved=498..<510
                      ├─ Text "Song 497" listRow
                      ├─ Text "Song 498" listRow
                      ├─ Text "Song 499" listRow
                      ├─ Text "Song 500" listRow
                      ├─ Text "Song 501" listRow
                      ├─ Text "Song 502" listRow
                      ├─ Text "Song 503" listRow
                      ├─ Text "Song 504" listRow
                      ├─ Text "Song 505" listRow
                      ├─ Text "Song 506" listRow
                      ├─ Text "Song 507" listRow
                      └─ Text "Song 508" listRow
                """)
    }

    @Test("A short list is evaluated in full, as before")
    func shortList() throws {
        let host = ViewHost(List(tracks(30)) { Text($0.title) })
        let section = try #require(host.root.allNodes.first { $0.kind == "Section" })
        #expect(section.attributes["lazyCount"] == nil)
        #expect(section.children.count == 30)
    }

    @Test("Scrolling a list creates its rows as they come on screen")
    func scrolling() throws {
        let host = ViewHost(LongList())
        let id = try listID(host)
        try host.scroll(id, to: CGPoint(x: 0, y: 52 * 3000))
        let numbers = trackNumbers(host)
        #expect(numbers.contains(3000))
        #expect(!numbers.contains(0))
        #expect(numbers.count <= 40)
        // Each row fills its cell, and the cells touch.
        let rows = host.root.allNodes.filter { $0.listRowFrame != nil }
        let cells = rows.compactMap(\.listRowFrame)
        for (above, below) in zip(cells, cells.dropFirst()) {
            #expect(abs(above.maxY - below.minY) < 0.01)
            #expect(below.width == above.width)
        }
        // A wheel scroll goes on from there.
        let before = try #require(host.scrollOffset(of: id)).y
        host.scroll(by: CGSize(width: 0, height: 2000), at: CGPoint(x: 200, y: 400))
        #expect(try #require(host.scrollOffset(of: id)).y == before + 2000)
        #expect(trackNumbers(host).contains(3000 + 2000 / 52 + 3))
    }

    @Test("A row far down can be tapped after scrolling there")
    func tapRow() throws {
        struct Rows: View {
            @State var tapped: Int?
            var body: some View {
                VStack {
                    Text("Tapped \(tapped.map(String.init) ?? "none")")
                    List(0..<2000, id: \.self) { row in
                        Button("Row \(row)") { tapped = row }
                    }
                }
            }
        }
        let host = ViewHost(Rows())
        let id = try listID(host)
        #expect(throws: InteractionError.self) { try host.tapButton(labeled: "Row 1500") }
        try host.scroll(id, to: CGPoint(x: 0, y: 52 * 1500))
        try host.tapButton(labeled: "Row 1500")
        #expect(host.nodes(withText: "Tapped 1500").count == 1)
    }

    @Test("Sections of a long list are lazy, with their headers and footers")
    func sections() throws {
        let host = ViewHost(
            List {
                Section {
                    ForEach(0..<1000, id: \.self) { Text("Alpha \($0)") }
                } header: {
                    Text("First")
                } footer: {
                    Text("End of first")
                }
                Section("Second") {
                    ForEach(0..<1000, id: \.self) { Text("Beta \($0)") }
                }
            })
        let list = try #require(host.root.allNodes.first { $0.kind == "List" })
        #expect(list.children.count == 2)
        #expect(list.children[0].attributes["lazyCount"] == "1002")
        #expect(list.children[0].children.first?.kind == "SectionHeader")
        #expect(list.children[1].attributes["lazyCount"] == "1001")
        // The second section's rows are not created until the screen is there.
        #expect(list.children[1].children.isEmpty)
        let id = try listID(host)
        try host.scroll(id, to: CGPoint(x: 0, y: 1_000_000))
        let end = try #require(host.root.allNodes.first { $0.kind == "List" })
        #expect(end.children[0].children.isEmpty)
        #expect(end.children[1].children.last?.text == "Beta 999")
        #expect(host.nodes(withText: "Second").count == 0)
        try host.scroll(id, to: CGPoint(x: 0, y: 51_500))
        #expect(host.nodes(withText: "End of first").count == 1)
    }

    @Test("A ForEach of sections makes a lazy section for each")
    func forEachOfSections() throws {
        let host = ViewHost(
            List {
                ForEach(0..<3, id: \.self) { group in
                    Section("Group \(group)") {
                        ForEach(0..<500, id: \.self) { Text("G\(group) R\($0)") }
                    }
                }
            })
        let list = try #require(host.root.allNodes.first { $0.kind == "List" })
        #expect(list.children.count == 3)
        #expect(list.children.map { $0.attributes["lazyCount"] } == ["501", "501", "501"])
        #expect(host.nodes(withText: "Group 0").count == 1)
        #expect(host.nodes(withText: "G0 R0").count == 1)
        #expect(host.nodes(withText: "G1 R0").isEmpty)
    }

    @Test("A row keeps its state while it is away")
    func state() throws {
        struct Row: View {
            var id: Int
            @State private var on = false
            var body: some View {
                Button(on ? "On \(id)" : "Off \(id)") { on.toggle() }
            }
        }
        let host = ViewHost(List(0..<3000, id: \.self) { Row(id: $0) })
        let id = try listID(host)
        try host.tapButton(labeled: "Off 2")
        try host.scroll(id, to: CGPoint(x: 0, y: 52 * 2000))
        #expect(host.nodes(withText: "On 2").isEmpty)
        try host.scroll(id, to: .zero)
        #expect(host.nodes(withText: "On 2").count == 1)
    }

    @Test("A long list draws the rows that exist")
    func drawing() throws {
        let host = ViewHost(LongList())
        let id = try listID(host)
        try host.scroll(id, to: CGPoint(x: 0, y: 52 * 2500 + 20))
        let frame = host.render(scale: 1)
        // A row on screen is white, between the list's gray margins.
        let rows = host.root.allNodes.compactMap(\.listRowFrame)
        let cell = try #require(rows.first { $0.minY > 150 && $0.maxY < 700 })
        func rgb(_ point: CGPoint) -> [UInt8] {
            let color = frame.color(at: point)
            return [color.red, color.green, color.blue]
        }
        #expect(rgb(CGPoint(x: cell.midX + 80, y: cell.midY)) == [255, 255, 255])
        #expect(rgb(CGPoint(x: 5, y: cell.midY)) == [242, 242, 247])
    }
}
