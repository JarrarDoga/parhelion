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
                └─ List contentOffset=0, 0 contentSize=300 × 258
                   ├─ Section
                   │  └─ Text "One" listRow
                   ├─ Section
                   │  ├─ SectionHeader
                   │  │  └─ Text "Fruit" font=headline
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
        // No content inset above a first section without a header, and 16
        // points of margin on each side. A line of body text and 15 points
        // above and below it make a 52-point row.
        #expect(cell == CGRect(x: 16, y: 0, width: 268, height: 52))
        // The text sits at the 16-point leading inset, centered vertically.
        let frame = try #require(row.frame)
        #expect(frame.minX == 32)
        #expect(frame.minY == 15)
        #expect(abs(frame.midY - cell.midY) < 0.01)
    }

    @Test("A row is at least 52 points tall, and grows with its content")
    func rowHeight() throws {
        let host = ViewHost(
            List {
                Text("Short")
                Color.red.frame(height: 60)
            },
            device: screen
        )
        let rows = host.root.children[0].children[0].children
        #expect(try #require(rows[0].listRowFrame).height == 52)
        // 60 points of content and 15 points above and below.
        #expect(try #require(rows[1].listRowFrame).height == 90)
        let icon = ViewHost(List { Color.red.frame(width: 10, height: 10) }, device: screen)
        let iconRow = icon.root.children[0].children[0].children[0]
        #expect(try #require(iconRow.listRowFrame).height == 52)
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
        #expect(cell == CGRect(x: 0, y: 0, width: 300, height: 52))
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

    @Test("Headers are semibold 17 points, footers 13 points, and fonts inside them win")
    func headerAndFooterFonts() {
        let host = ViewHost(
            List {
                Section {
                    Text("Row")
                } header: {
                    Text("Header")
                } footer: {
                    Text("Footer")
                }
                Section {
                    Text("Row")
                } header: {
                    Text("Custom").font(.caption)
                }
            },
            device: screen
        )
        #expect(
            host.root.outline() == """
                Root
                └─ List contentOffset=0, 0 contentSize=300 × 252
                   ├─ Section
                   │  ├─ SectionHeader
                   │  │  └─ Text "Header" font=headline
                   │  ├─ Text "Row" listRow
                   │  └─ SectionFooter
                   │     └─ Text "Footer" font=system(13)
                   └─ Section
                      ├─ SectionHeader
                      │  └─ Text "Custom" font=caption
                      └─ Text "Row" listRow
                """)
    }

    @Test("Headers, footers, and sections are spaced as in the iOS 27 UI Kit")
    func headerAndFooterLayout() throws {
        let host = ViewHost(
            List {
                Section {
                    Text("Row")
                } header: {
                    Text("Header")
                } footer: {
                    Text("Footer")
                }
                Section("Next") {
                    Text("Row")
                }
            },
            device: screen
        )
        let sections = host.root.children[0].children
        let header = sections[0].children[0]
        let headerText = try #require(header.children[0].frame)
        // A 42-point header block: 10 above a 22-point line and 10 below.
        let headerFrame = try #require(header.frame)
        #expect(headerFrame.origin == CGPoint(x: 16, y: 0) && headerFrame.height == 42)
        #expect(headerText.origin == CGPoint(x: 32, y: 10))
        let cell = try #require(sections[0].children[1].listRowFrame)
        #expect(cell.minY == 42)
        // A 30-point footer block: 8 below the cells, a 16-point line, and 6.
        let footer = sections[0].children[2]
        let footerFrame = try #require(footer.frame)
        #expect(footerFrame.origin == CGPoint(x: 16, y: 94) && footerFrame.height == 30)
        #expect(try #require(footer.children[0].frame).origin == CGPoint(x: 32, y: 102))
        // 20 points from the footer to the next section's header.
        #expect(try #require(sections[1].children[0].frame).minY == 144)
    }

    @Test("Sections are rounded with radius 26, and separators are inset on both sides")
    func sectionDrawing() throws {
        let host = ViewHost(
            NavigationStack {
                List {
                    NavigationLink("One") { Text("Detail") }
                    NavigationLink("Two") { Text("Detail") }
                }
                .navigationBarTitleDisplayMode(.inline)
            },
            device: screen
        )
        let rows = host.root.children[0].children[1].children[0].children
        let cell = try #require(rows[0].listRowFrame)
        #expect(cell == CGRect(x: 16, y: 54, width: 268, height: 52))
        let frame = host.render(scale: 3)
        func gray(_ x: CGFloat, _ y: CGFloat) -> UInt8 { frame.color(at: CGPoint(x: x, y: y)).red }
        // Outside the corner's arc, 4 points in from both edges, the list's
        // background shows; a radius of 10 would cover it.
        #expect(gray(cell.minX + 4, cell.minY + 4) == 242)
        #expect(gray(cell.minX + 13, cell.minY + 13) == 255)
        // The separator, black at 12%, runs from 16 points inside the cell's
        // leading edge to 16 points inside its trailing edge.
        let separatorY = cell.maxY - 0.1
        #expect(gray(cell.minX + 17, separatorY) == 224)
        #expect(gray(cell.maxX - 17, separatorY) == 224)
        #expect(gray(cell.minX + 15, separatorY) == 255)
        #expect(gray(cell.maxX - 15, separatorY) == 255)
        // The disclosure chevron ends at the trailing inset, in the tertiary
        // label color.
        var inkXs: [CGFloat] = []
        for x in stride(from: cell.maxX - 30, to: cell.maxX, by: 1.0 / 3) {
            if gray(x, cell.midY) < 230 { inkXs.append(x) }
        }
        let rightmost = try #require(inkXs.max())
        #expect(abs(rightmost - (cell.maxX - 16)) < 1)
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
        // Only a list gives the header its font.
        #expect(section.children[0].children.first?.attributes["font"] == nil)
        let header = try #require(section.children[0].frame)
        let row = try #require(section.children[1].frame)
        #expect(row.minY >= header.maxY)
    }
}

@MainActor
private final class TapCounter {
    var count = 0
}
