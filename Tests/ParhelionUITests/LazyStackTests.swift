import Foundation
import Testing

@testable import ParhelionUI

/// A 200 × 400 screen with no safe-area insets.
private let tall = Device(
    name: "Test",
    screenSize: CGSize(width: 200, height: 400),
    safeAreaInsets: EdgeInsets()
)

private struct Song: Identifiable {
    var id: Int
}

private func songs(_ count: Int) -> [Song] { (0..<count).map(Song.init) }

/// Records which rows appeared and disappeared.
@MainActor
private final class Log {
    var appeared: [Int] = []
    var disappeared: [Int] = []
}

/// A row 50 points tall with a counter that its button raises.
private struct CountingRow: View {
    var id: Int
    @State private var count = 0

    var body: some View {
        Button("Row \(id): \(count)") { count += 1 }
            .frame(height: 50)
    }
}

private struct LongStack: View {
    var count = 5000
    var log: Log?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(songs(count)) { song in
                    CountingRow(id: song.id)
                        .onAppear { log?.appeared.append(song.id) }
                        .onDisappear { log?.disappeared.append(song.id) }
                }
            }
        }
    }
}

@MainActor
private func scrollViewID(_ host: ViewHost) throws -> NodeID {
    try #require(host.root.allNodes.first { $0.kind == "ScrollView" }).id
}

@MainActor
private func rowNumbers(_ host: ViewHost) -> [Int] {
    host.root.allNodes.filter { $0.kind == "Text" }.compactMap { node in
        node.text.flatMap { text in
            text.hasPrefix("Row ") ? Int(text.dropFirst(4).prefix { $0.isNumber }) : nil
        }
    }
}

@MainActor
@Suite("Lazy stacks")
struct LazyStackTests {
    @Test("A short stack creates all its views, without lazy attributes")
    func shortStack() {
        let host = ViewHost(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    Text("A")
                    Text("B")
                    Text("C")
                }
            }, device: tall)
        #expect(
            host.root.outline() == """
                Root
                └─ ScrollView axes=vertical contentOffset=0, 0 contentSize=200 × 74
                   └─ LazyVStack alignment=leading spacing=4
                      ├─ Text "A"
                      ├─ Text "B"
                      └─ Text "C"
                """)
    }

    @Test("A lazy stack takes the width it is offered and stacks its views")
    func layout() throws {
        let host = ViewHost(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Color.red.frame(width: 50, height: 30)
                    Color.blue.frame(width: 80, height: 20)
                }
            }, device: tall)
        let stack = try #require(host.root.allNodes.first { $0.kind == "LazyVStack" })
        #expect(stack.frame == CGRect(x: 0, y: 0, width: 200, height: 60))
        let frames = stack.children.compactMap(\.frame)
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 50, height: 30))
        #expect(frames[1] == CGRect(x: 0, y: 40, width: 80, height: 20))
    }

    @Test("A long stack creates the rows near the screen and sizes all of them")
    func longStack() throws {
        let host = ViewHost(LongStack(), device: tall)
        let stack = try #require(host.root.allNodes.first { $0.kind == "LazyVStack" })
        #expect(stack.attributes["lazyCount"] == "5000")
        #expect(stack.attributes["lazyResolved"] == "0..<40")
        #expect(stack.children.count == 40)
        #expect(rowNumbers(host).first == 0)
        let scroll = try #require(host.root.allNodes.first { $0.kind == "ScrollView" })
        #expect(scroll.attributes["contentSize"] == "200 × 250000")
    }

    @Test("Scrolling far creates the rows there and releases the ones it left")
    func scrollFar() throws {
        let host = ViewHost(LongStack(), device: tall)
        let id = try scrollViewID(host)
        try host.scroll(id, to: CGPoint(x: 0, y: 100_000))
        let rows = rowNumbers(host)
        #expect(rows.count < 40)
        #expect(rows.contains(2000))
        #expect(!rows.contains(0))
        let row = try #require(host.root.allNodes.first { $0.text == "Row 2000: 0" })
        #expect(try #require(row.frame).minY == 14)
        #expect(host.scrollOffset(of: id) == CGPoint(x: 0, y: 100_000))
        // The end of the content.
        try host.scroll(id, to: CGPoint(x: 0, y: 1_000_000))
        #expect(rowNumbers(host).last == 4999)
    }

    @Test("Scrolling a little keeps the rows it has until the screen leaves them")
    func scrollSlowly() throws {
        let host = ViewHost(LongStack(), device: tall)
        let id = try scrollViewID(host)
        let before = host.revision
        host.scroll(by: CGSize(width: 0, height: 100), at: CGPoint(x: 100, y: 200))
        #expect(host.revision > before)
        #expect(rowNumbers(host).first == 0)
        for _ in 0..<50 {
            host.scroll(by: CGSize(width: 0, height: 100), at: CGPoint(x: 100, y: 200))
        }
        let rows = rowNumbers(host)
        let offset = try #require(host.scrollOffset(of: id)).y
        #expect(offset == 5100)
        #expect(rows.contains(102))
        #expect(!rows.contains(0))
        #expect(rows.count <= 40)
    }

    @Test("A row keeps its state, by identity, while it is away")
    func stateKept() throws {
        let host = ViewHost(LongStack(), device: tall)
        let id = try scrollViewID(host)
        try host.tapButton(labeled: "Row 1: 0")
        try host.tapButton(labeled: "Row 1: 1")
        #expect(host.nodes(withText: "Row 1: 2").count == 1)
        try host.scroll(id, to: CGPoint(x: 0, y: 100_000))
        #expect(host.nodes(withText: "Row 1: 2").isEmpty)
        try host.scroll(id, to: .zero)
        #expect(host.nodes(withText: "Row 1: 2").count == 1)
        #expect(host.nodes(withText: "Row 2: 0").count == 1)
    }

    @Test("State goes when the row's identity leaves the data")
    func stateDiscarded() throws {
        struct Rows: View {
            @State var ids = Array(0..<100)
            var body: some View {
                VStack {
                    Button("Drop") { ids.removeAll { $0 == 1 } }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(ids, id: \.self) { CountingRow(id: $0) }
                        }
                    }
                }
            }
        }
        let host = ViewHost(Rows(), device: tall)
        try host.tapButton(labeled: "Row 1: 0")
        try host.tapButton(labeled: "Drop")
        #expect(host.nodes(withText: "Row 1: 1").isEmpty)
        #expect(host.nodes(withText: "Row 2: 0").count == 1)
    }

    @Test("onAppear runs as a row is created, onDisappear as it is released")
    func lifecycle() throws {
        let log = Log()
        let host = ViewHost(LongStack(log: log), device: tall)
        let id = try scrollViewID(host)
        #expect(log.appeared == Array(0..<40))
        #expect(log.disappeared.isEmpty)
        try host.scroll(id, to: CGPoint(x: 0, y: 100_000))
        #expect(Set(log.disappeared) == Set(0..<40))
        #expect(log.appeared.count == 40 + host.root.allNodes.filter { $0.kind == "Button" }.count)
        #expect(log.appeared.contains(2000))
    }

    @Test("onAppear on the last row can load more rows")
    func pagination() throws {
        struct Pages: View {
            @State var count = 60
            var body: some View {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<count, id: \.self) { index in
                            Text("Row \(index)").frame(height: 50)
                                .onAppear { if index == count - 1 { count += 60 } }
                        }
                    }
                }
            }
        }
        let host = ViewHost(Pages(), device: tall)
        let id = try scrollViewID(host)
        #expect(host.nodes(withText: "Row 59").isEmpty)
        try host.scroll(id, to: CGPoint(x: 0, y: 100_000))
        // Reaching the end made more rows, which the stack then holds.
        let scroll = try #require(host.root.allNodes.first { $0.id == id })
        #expect(scroll.attributes["contentSize"] == "200 × 6000")
        #expect(!host.nodes(withText: "Row 59").isEmpty)
    }

    @Test("Rows of different heights add up")
    func differentHeights() throws {
        let host = ViewHost(
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<200, id: \.self) { index in
                        Color.red.frame(height: index.isMultiple(of: 2) ? 20 : 60)
                    }
                }
            }, device: tall)
        let id = try scrollViewID(host)
        // Rows measured so far are 20 and 60 points; the others are the mean.
        let scroll = try #require(host.root.allNodes.first { $0.id == id })
        #expect(scroll.attributes["contentSize"] == "200 × 8000")
        try host.scroll(id, to: CGPoint(x: 0, y: 1_000_000))
        // The rows that do not exist are as tall as the mean of those that do.
        let end = try #require(host.root.allNodes.first { $0.id == id })
        let height = try #require(end.attributes["contentSize"]?.split(separator: " ").last)
        #expect(abs(try #require(Double(height)) - 8000) < 100)
        let last = try #require(host.root.allNodes.filter { $0.kind == "Color" }.last?.frame)
        #expect(last.maxY == 400)
    }

    @Test("The mixed content of a stack is looked through")
    func mixedContent() throws {
        let host = ViewHost(
            ScrollView {
                LazyVStack(spacing: 0) {
                    Text("Header").frame(height: 50)
                    ForEach(0..<100, id: \.self) { Text("Item \($0)").frame(height: 50) }
                    if true { Text("Footer").frame(height: 50) }
                }
            }, device: tall)
        let stack = try #require(host.root.allNodes.first { $0.kind == "LazyVStack" })
        #expect(stack.attributes["lazyCount"] == "102")
        #expect(stack.children.first?.text == "Header")
        let id = try scrollViewID(host)
        try host.scroll(id, to: CGPoint(x: 0, y: 1_000_000))
        #expect(host.nodes(withText: "Footer").count == 1)
        #expect(host.nodes(withText: "Header").isEmpty)
    }

    @Test("A lazy stack of horizontal scrolls creates the columns near the screen")
    func horizontal() throws {
        let host = ViewHost(
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<1000, id: \.self) { index in
                        Text("Col \(index)").frame(width: 100, height: 50)
                    }
                }
            }, device: tall)
        let stack = try #require(host.root.allNodes.first { $0.kind == "LazyHStack" })
        #expect(stack.attributes["lazyCount"] == "1000")
        let id = try scrollViewID(host)
        try host.scroll(id, to: CGPoint(x: 50_000, y: 0))
        let columns = host.root.allNodes.filter { $0.text?.hasPrefix("Col ") == true }
        #expect(columns.count < 40)
        let column = try #require(columns.first { $0.text == "Col 500" })
        #expect(try #require(column.frame).midX == 50)
    }

    @Test("Pinned section headers stay at the top of the scroll view")
    func pinnedHeaders() throws {
        func make(_ pinned: PinnedScrollableViews) -> some View {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: pinned) {
                    ForEach(0..<10, id: \.self) { section in
                        Section {
                            ForEach(0..<20, id: \.self) { row in
                                Text("S\(section) R\(row)").frame(height: 50)
                            }
                        } header: {
                            Text("Header \(section)").frame(height: 30)
                        }
                    }
                }
            }
        }
        let host = ViewHost(make(.sectionHeaders), device: tall)
        let id = try scrollViewID(host)
        // Section 3 starts at 3 × 1030, and its fifteenth row is on screen.
        let inside = CGFloat(3 * 1030 + 30 + 14 * 50)
        try host.scroll(id, to: CGPoint(x: 0, y: inside))
        let header = try #require(host.nodes(withText: "Header 3").first)
        let stack = try #require(host.root.allNodes.first { $0.kind == "LazyVStack" })
        let cell = try #require(
            stack.children.first { $0.text == "Header 3" }?.modifierFrames.first)
        #expect(cell.minY == 0 && cell.height == 30)
        #expect(header.frame != nil)
        // It is in front of the rows that scroll under it.
        #expect(stack.children.last?.text == "Header 3")
        // The next section's header pushes it away at the end of its section.
        try host.scroll(id, to: CGPoint(x: 0, y: CGFloat(4 * 1030 - 10)))
        let pushed = try #require(
            host.root.allNodes.first { $0.kind == "LazyVStack" }?.children
                .first { $0.text == "Header 3" }?.modifierFrames.first)
        // The header ends where the section's last row does.
        let lastRow = try #require(host.nodes(withText: "S3 R19").first?.frame)
        let rowCell = lastRow.maxY + (50 - lastRow.height) / 2
        #expect(abs(pushed.maxY - rowCell) < 0.01)
        #expect(pushed.minY < 0)

        // Without pinning, the header scrolls away with its section.
        let plain = ViewHost(make([]), device: tall)
        let plainID = try scrollViewID(plain)
        try plain.scroll(plainID, to: CGPoint(x: 0, y: inside))
        #expect(plain.nodes(withText: "Header 3").isEmpty)
    }

    @Test("Scrolling to a point creates rows that did not exist yet")
    func scrollToReachesUnresolvedRows() throws {
        let host = ViewHost(LongStack(), device: tall)
        let id = try scrollViewID(host)
        #expect(host.nodes(withText: "Row 3500: 0").isEmpty)
        try host.scroll(id, to: CGPoint(x: 0, y: 3500 * 50))
        #expect(host.nodes(withText: "Row 3500: 0").count == 1)
        try host.tapButton(labeled: "Row 3500: 0")
        #expect(host.nodes(withText: "Row 3500: 1").count == 1)
    }

    @Test("A stack outside a scroll view uses the screen as its viewport")
    func outsideScrollView() {
        let host = ViewHost(
            LazyVStack(spacing: 0) {
                ForEach(0..<1000, id: \.self) { Text("Row \($0)").frame(height: 50) }
            }, device: tall)
        // The stack is centered on the screen, so rows far from row 0 are
        // the ones on it.
        let rows = rowNumbers(host)
        #expect(!rows.isEmpty && rows.count < 40)
        let row = host.nodes(withText: "Row \(rows[rows.count / 2])").first
        #expect(row?.frame.map { $0.maxY > 0 && $0.minY < 400 } == true)
    }
}
