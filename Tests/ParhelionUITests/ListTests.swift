import Foundation
import Testing

@testable import ParhelionUI

/// A 300 × 400 screen with no safe-area insets.
private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 400),
    safeAreaInsets: EdgeInsets()
)

private struct Fruit: Identifiable {
    var id: String
}

private func components(_ color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> [UInt8] {
    [color.red, color.green, color.blue, color.alpha]
}

@MainActor
@Suite("List")
struct ListTests {
    @Test("Rows outside a section form sections of their own")
    func outline() {
        let host = ViewHost(
            List {
                Text("One")
                Section("Fruit") {
                    Text("Apple")
                }
                Text("Two")
            },
            device: screen
        )
        #expect(
            host.root.outline() == """
                Root
                └─ List contentOffset=0, 0 contentSize=300 × 269.57
                   ├─ Section
                   │  └─ Text "One" listRow
                   ├─ Section
                   │  ├─ SectionHeader
                   │  │  └─ Text "Fruit"
                   │  └─ Text "Apple" listRow
                   └─ Section
                      └─ Text "Two" listRow
                """)
        let sections = host.root.allNodes.filter { $0.kind == "Section" }.map(\.id.rawValue)
        #expect(sections == ["List/Section[0]", "List/1/Section", "List/Section[1]"])
    }

    @Test("A section has a header, rows, and a footer")
    func sectionParts() {
        let host = ViewHost(
            List {
                Section {
                    Text("Row")
                } header: {
                    Text("Header")
                } footer: {
                    Text("Footer")
                }
            },
            device: screen
        )
        let section = host.root.children[0].children[0]
        #expect(section.children.map(\.kind) == ["SectionHeader", "Text", "SectionFooter"])
        #expect(section.children[0].id == "List/Section/header")
        #expect(section.children[2].label == "Footer")
    }

    @Test("Data initializers make one row per element")
    func dataInitializers() {
        let fruits = [Fruit(id: "apple"), Fruit(id: "pear")]
        let identifiable = ViewHost(List(fruits) { Text($0.id) }, device: screen)
        #expect(
            identifiable.root.allNodes.filter { $0.kind == "Text" }.map(\.id.rawValue) == [
                "List/ForEach[apple]/Text", "List/ForEach[pear]/Text",
            ])
        let keyPath = ViewHost(List(["a", "b"], id: \.self) { Text($0) }, device: screen)
        #expect(keyPath.root.allNodes.filter { $0.kind == "Text" }.count == 2)
        let range = ViewHost(List(0..<3) { Text("Row \($0)") }, device: screen)
        #expect(range.root.allNodes.filter { $0.kind == "Text" }.count == 3)
    }

    @Test("A list fills its proposal, and rows fill the inset width of their section")
    func layout() throws {
        let host = ViewHost(List { Text("One") }, device: screen)
        let list = host.root.children[0]
        #expect(list.frame == CGRect(x: 0, y: 0, width: 300, height: 400))
        let row = list.children[0].children[0]
        let cell = try #require(row.listRowFrame)
        // 20 points of content inset, 16 points of margin on each side.
        #expect(cell == CGRect(x: 16, y: 20, width: 268, height: 44))
        // The text sits at the leading inset, centered vertically.
        let frame = try #require(row.frame)
        #expect(frame.minX == 36)
        #expect(abs(frame.midY - cell.midY) < 0.01)
    }

    @Test("A row is at least 44 points tall, and grows with its content")
    func rowHeight() throws {
        let host = ViewHost(
            List {
                Text("Short")
                Color.red.frame(height: 60)
            },
            device: screen
        )
        let rows = host.root.children[0].children[0].children
        #expect(try #require(rows[0].listRowFrame).height == 44)
        #expect(try #require(rows[1].listRowFrame).height == 82)
    }

    @Test("A button row responds to taps across its whole cell")
    func buttonRowTap() throws {
        let tapped = TapCounter()
        let host = ViewHost(List { Button("Add") { tapped.count += 1 } }, device: screen)
        let row = host.root.children[0].children[0].children[0]
        let cell = try #require(row.listRowFrame)
        let frame = try #require(row.frame)
        let point = CGPoint(x: cell.maxX - 5, y: cell.midY)
        #expect(!frame.contains(point))
        try host.tap(at: point)
        #expect(tapped.count == 1)
    }

    @Test("A long list scrolls")
    func scrolling() throws {
        let host = ViewHost(List(0..<20) { Text("Row \($0)") }, device: screen)
        let list = host.root.children[0]
        #expect(host.scroll(by: CGSize(width: 0, height: 100), at: CGPoint(x: 150, y: 200)))
        #expect(host.scrollOffset(of: list.id) == CGPoint(x: 0, y: 100))
    }

    @Test("The plain style has no margins or section spacing")
    func plainStyle() throws {
        let host = ViewHost(
            List {
                Text("One")
            }
            .listStyle(.plain),
            device: screen
        )
        let list = host.root.children[0]
        #expect(list.attributes["listStyle"] == "plain")
        let cell = try #require(list.children[0].children[0].listRowFrame)
        #expect(cell == CGRect(x: 0, y: 0, width: 300, height: 44))
    }

    @Test("A grouped list draws a gray background and white rows")
    func rendering() {
        let host = ViewHost(List { Text("One") }, device: screen)
        let frame = host.render(scale: 1)
        #expect(components(frame.color(at: CGPoint(x: 5, y: 5))) == [242, 242, 247, 255])
        #expect(components(frame.color(at: CGPoint(x: 250, y: 40))) == [255, 255, 255, 255])
    }

    @Test("A pressed button row highlights its cell")
    func pressedRow() {
        let host = ViewHost(List { Button("Add") {} }, device: screen)
        host.pointerDown(at: CGPoint(x: 250, y: 42))
        let frame = host.render(scale: 1)
        #expect(components(frame.color(at: CGPoint(x: 250, y: 42))) == [209, 209, 214, 255])
    }

    @Test("Outside a list, a section stacks its parts vertically")
    func sectionOutsideList() throws {
        let host = ViewHost(
            Section("Header") {
                Text("Row")
            },
            device: screen
        )
        let section = host.root.children[0]
        let header = try #require(section.children[0].frame)
        let row = try #require(section.children[1].frame)
        #expect(row.minY >= header.maxY)
    }
}

@MainActor
private final class TapCounter {
    var count = 0
}
