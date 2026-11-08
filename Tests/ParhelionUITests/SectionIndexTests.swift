import Foundation
import Testing

@testable import ParhelionUI

/// A 300 × 600 screen with no safe-area insets.
private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 600),
    safeAreaInsets: EdgeInsets()
)

private let letters = ["A", "B", "C", "D", "M", "N", "Z"]

/// A list with a section for each letter, eight rows each, and an index.
private struct Browse: View {
    var visibility: Visibility = .automatic
    var labeled = true

    var body: some View {
        List {
            ForEach(letters, id: \.self) { letter in
                Section {
                    ForEach(0..<8, id: \.self) { Text("\(letter)\($0)") }
                } header: {
                    Text(letter)
                }
                .sectionIndexLabel(labeled ? Text(letter) : nil)
            }
        }
        .listSectionIndexVisibility(visibility)
    }
}

@MainActor
@Suite("Section index")
struct SectionIndexTests {
    /// The top of the section with a label, in screen points.
    private func top(of letter: String, in host: ViewHost) -> CGFloat? {
        host.root.allNodes.first {
            $0.kind == "Section" && $0.attributes["sectionIndexLabel"] == letter
        }?.frame?.minY
    }

    @Test("The index is a column of letters in an overlay of the list")
    func outline() {
        let host = ViewHost(
            List {
                Section("One") { Text("a") }.sectionIndexLabel(Text("A"))
                Section("Two") { Text("b") }.sectionIndexLabel(Text("B"))
            },
            device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ List overlay(alignment: trailing) contentOffset=0, 0 contentSize=300 × 223
                   ├─ Section sectionIndexLabel=A
                   │  ├─ SectionHeader
                   │  │  └─ Text "One" font=headline
                   │  └─ Text "a" listRow
                   ├─ Section sectionIndexLabel=B
                   │  ├─ SectionHeader
                   │  │  └─ Text "Two" font=headline
                   │  └─ Text "b" listRow
                   └─ Overlay sectionIndex=true
                      └─ VStack gesture(drag(minimumDistance: 0)) foregroundStyle=tint spacing=0
                         ├─ Button buttonStyle=plain
                         │  └─ Text "A" frame(width: 15, height: 13.75) frame(width: 28, alignment: trailing) font=system(11).semibold
                         └─ Button buttonStyle=plain
                            └─ Text "B" frame(width: 15, height: 13.75) frame(width: 28, alignment: trailing) font=system(11).semibold
                """)
    }

    @Test("Tapping a letter puts its section at the top")
    func tapLetter() throws {
        let host = ViewHost(Browse(), device: screen)
        #expect(top(of: "M", in: host)! > 100)
        try host.tapButton(labeled: "M")
        #expect(top(of: "M", in: host) == 0)
        #expect(host.scrollOffset(of: host.root.children[0].id)!.y > 0)
        try host.tapButton(labeled: "B")
        #expect(top(of: "B", in: host) == 0)
    }

    @Test("A section near the end scrolls as far as the content allows")
    func lastSection() throws {
        let host = ViewHost(Browse(), device: screen)
        try host.tapButton(labeled: "Z")
        // Nothing follows Z, so it stops short of the top.
        let z = try #require(top(of: "Z", in: host))
        #expect(z > 0)
        #expect(top(of: "N", in: host)! < 0)
    }

    @Test("Tapping at a letter's position scrolls")
    func tapAt() throws {
        let host = ViewHost(Browse(), device: screen)
        let letter = try #require(
            host.root.allNodes.first { $0.kind == "Button" && $0.label == "N" }?.frame)
        try host.tap(at: CGPoint(x: letter.midX, y: letter.midY))
        #expect(top(of: "N", in: host) == 0)
    }

    @Test("The index sits at the trailing edge, centered vertically")
    func placement() throws {
        let host = ViewHost(Browse(), device: screen)
        let column = try #require(host.root.allNodes.first { $0.kind == "VStack" }?.frame)
        #expect(column.maxX == 300)
        #expect(column.width == SectionIndex.width)
        #expect(column.height == SectionIndex.pitch * CGFloat(letters.count))
        #expect(abs(column.midY - 300) < 0.5)
    }

    @Test("Dragging over the letters scrolls to the one under the pointer")
    func dragOverLetters() throws {
        let host = ViewHost(Browse(), device: screen)
        func center(of letter: String) throws -> CGPoint {
            let frame = try #require(
                host.root.allNodes.first { $0.kind == "Button" && $0.label == letter }?.frame)
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        host.pointerDown(at: try center(of: "B"))
        host.pointerMoved(to: try center(of: "M"))
        #expect(top(of: "M", in: host) == 0)
        host.pointerMoved(to: try center(of: "C"))
        #expect(top(of: "C", in: host) == 0)
        host.pointerUp(at: try center(of: "C"))
        #expect(top(of: "C", in: host) == 0)
    }

    @Test("In a navigation stack the section stops below the bar")
    func belowBar() throws {
        let host = ViewHost(
            NavigationStack { Browse().navigationTitle("Browse") }, device: .iPhone16)
        try host.tapButton(labeled: "M")
        let bar = try #require(host.root.allNodes.first { $0.kind == "NavigationBar" }?.frame)
        let section = try #require(
            host.root.allNodes.first {
                $0.kind == "Section" && $0.attributes["sectionIndexLabel"] == "M"
            }?.frame)
        #expect(abs(section.minY - bar.maxY) < 0.5)
    }

    @Test("In a navigation stack the index is centered in the list below the bar")
    func centeredBelowBar() throws {
        let host = ViewHost(
            NavigationStack { Browse().navigationTitle("Browse") }, device: .iPhone16)
        let bar = try #require(host.root.allNodes.first { $0.kind == "NavigationBar" }?.frame)
        let column = try #require(host.root.allNodes.first { $0.kind == "VStack" }?.frame)
        let bottom = Device.iPhone16.safeArea.maxY
        #expect(abs(column.midY - (bar.maxY + bottom) / 2) < 0.5)
        #expect(column.maxX == Device.iPhone16.screenSize.width)
    }

    @Test("A hidden index draws nothing")
    func hidden() {
        let host = ViewHost(Browse(visibility: .hidden), device: screen)
        #expect(!host.root.allNodes.contains { $0.kind == "Overlay" })
        #expect(!host.root.allNodes.contains { $0.kind == "Button" })
    }

    @Test("Visible and automatic show the index")
    func visible() {
        for visibility in [Visibility.visible, .automatic] {
            let host = ViewHost(Browse(visibility: visibility), device: screen)
            #expect(host.root.allNodes.filter { $0.kind == "Button" }.count == letters.count)
        }
    }

    @Test("Without labels there is no index")
    func unlabeled() {
        let host = ViewHost(Browse(labeled: false), device: screen)
        #expect(!host.root.allNodes.contains { $0.kind == "Overlay" })
    }

    @Test("The visibility applies to lists inside the view it modifies")
    func inherited() {
        let list = List {
            Section("One") { Text("a") }.sectionIndexLabel(Text("A"))
        }
        func buttons(_ view: some View) -> Int {
            ViewHost(view, device: screen).root.allNodes.count { $0.kind == "Button" }
        }
        #expect(buttons(list) == 1)
        #expect(buttons(list.listSectionIndexVisibility(.hidden)) == 0)
        #expect(buttons(VStack { list }.listSectionIndexVisibility(.hidden)) == 0)
        #expect(buttons(VStack { list }.listSectionIndexVisibility(.visible)) == 1)
        // The modifier closest to the list wins.
        #expect(
            buttons(
                VStack { list.listSectionIndexVisibility(.visible) }
                    .listSectionIndexVisibility(.hidden)) == 1)
    }

    @Test("Sections with the same label share a letter")
    func sharedLabel() throws {
        let host = ViewHost(
            List {
                Section("One") { Text("a") }.sectionIndexLabel(Text("A"))
                Section("Two") { Text("b") }.sectionIndexLabel(Text("A"))
            },
            device: screen)
        #expect(host.root.allNodes.filter { $0.kind == "Button" }.count == 1)
    }

    @Test("A label can come from the first row of a section")
    func rowLabel() {
        let host = ViewHost(
            List {
                Section("One") { Text("a").sectionIndexLabel(Text("A")) }
            },
            device: screen)
        #expect(host.root.allNodes.filter { $0.kind == "Button" }.map(\.label) == ["A"])
    }

    @Test("The index is drawn over the rows")
    func rendering() throws {
        let host = ViewHost(Browse(), device: screen)
        let frame = host.render(scale: 1)
        let column = try #require(host.root.allNodes.first { $0.kind == "VStack" }?.frame)
        // Letters are drawn in the tint color inside the column.
        var tinted = 0
        for y in Int(column.minY)..<Int(column.maxY) {
            for x in Int(column.minX)..<Int(column.maxX) {
                let i = (y * frame.pixelWidth + x) * 4
                let (r, g, b) = (frame.pixels[i], frame.pixels[i + 1], frame.pixels[i + 2])
                if b > 200, r < 80, g > 80 && g < 180 { tinted += 1 }
            }
        }
        #expect(tinted > 50)
    }

    @Test("A long list scrolls to a section far below the screen")
    func longList() throws {
        let alphabet = (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { String(UnicodeScalar($0)) }
        let host = ViewHost(
            List {
                ForEach(alphabet, id: \.self) { letter in
                    Section(letter) {
                        ForEach(0..<20, id: \.self) { Text("\(letter)\($0)") }
                    }
                    .sectionIndexLabel(Text(letter))
                }
            },
            device: screen)
        try host.tapButton(labeled: "T")
        #expect(top(of: "T", in: host) == 0)
    }
}
