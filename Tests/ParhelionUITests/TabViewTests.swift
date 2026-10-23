import Foundation
import Testing

@testable import ParhelionUI

/// A 300 × 500 screen with 40 points of safe area at the top and 30 at the
/// bottom.
private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 500),
    safeAreaInsets: EdgeInsets(top: 40, leading: 0, bottom: 30, trailing: 0)
)

private struct Counter: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Text("Count: \(count)")
            Button("Increment") { count += 1 }
        }
    }
}

private enum Section: Hashable {
    case home, library, search
}

private struct Selected: View {
    @State private var selection = Section.home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: Section.home) {
                Counter()
            }
            Tab("Library", systemImage: "books.vertical", value: Section.library) {
                NavigationStack {
                    NavigationLink("Details") {
                        Counter().navigationTitle("Details")
                    }
                    .navigationTitle("Library")
                }
            }
            Tab(value: Section.search, role: .search) {
                Text("Search")
            }
        }
    }
}

private struct Unselected: View {
    var body: some View {
        TabView {
            Tab("First", systemImage: "1.circle") {
                Text("One")
            }
            if true {
                Tab("Second", systemImage: "star") {
                    Text("Two")
                }
            }
        }
    }
}

private struct Items: View {
    var body: some View {
        TabView {
            Counter()
                .tabItem {
                    Label("Count", systemImage: "number")
                }
            Text("Two")
                .tabItem {
                    Image(systemName: "star")
                    Text("Star")
                }
        }
    }
}

private struct Tagged: View {
    @State private var selection = 2

    var body: some View {
        VStack {
            Text("Selection: \(selection)")
            TabView(selection: $selection) {
                Text("One")
                    .tabItem { Label("One", systemImage: "star") }
                    .tag(1)
                Text("Two")
                    .tag(2)
                    .tabItem { Label("Two", systemImage: "heart") }
            }
        }
    }
}

private struct Letters: View {
    @State private var selection = "B"

    var body: some View {
        TabView(selection: $selection) {
            ForEach(["A", "B", "C"], id: \.self) { letter in
                Text("Letter \(letter)")
                    .tabItem { Text(letter) }
            }
        }
    }
}

private struct LongList: View {
    var body: some View {
        TabView {
            Tab("Rows", systemImage: "list.bullet") {
                List {
                    ForEach(0..<12) { index in
                        Text("Row \(index)")
                    }
                }
            }
        }
    }
}

@MainActor
private func texts(_ host: ViewHost) -> [String] {
    host.root.allNodes.compactMap(\.text)
}

@MainActor
private func node(_ host: ViewHost, _ suffix: String) throws -> ViewNode {
    try #require(host.root.allNodes.first { $0.id.rawValue.hasSuffix(suffix) })
}

@MainActor
@Suite("Tab views")
struct TabViewTests {
    @Test("A tab view shows the selected tab above a bar with a button for each tab")
    func outline() {
        let host = ViewHost(Selected(), device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ TabView
                   ├─ VStack
                   │  ├─ Text "Count: 0"
                   │  └─ Button
                   │     └─ Text "Increment"
                   └─ TabBar
                      ├─ Button selected=true
                      │  ├─ Image font=system(18) symbolVariant=fill systemName=house
                      │  └─ Text "Home" font=system(10).semibold
                      ├─ Button
                      │  ├─ Image font=system(18) symbolVariant=fill systemName=books.vertical
                      │  └─ Text "Library" font=system(10).semibold
                      └─ Button label=Search role=search
                         └─ Image font=system(17) systemName=magnifyingglass
                """)
    }

    @Test("A search tab's default label is a magnifying glass titled Search")
    func searchLabel() throws {
        let host = ViewHost(Selected(), device: screen)
        try host.tapButton(labeled: "Search")
        #expect(texts(host) == ["Search", "Home", "Library"])
        let search = try node(host, "TabView/bar/2")
        #expect(search.attributes["selected"] == "true")
        #expect(search.label == "Search")
    }

    @Test("Tapping a tab by label, identifier, or position selects it")
    func switching() throws {
        let host = ViewHost(Selected(), device: screen)
        try host.tapButton(labeled: "Library")
        #expect(texts(host).contains("Details"))
        try host.tap(NodeID("Selected/TabView/bar/0"))
        #expect(texts(host).contains("Count: 0"))
        let library = try #require(try node(host, "TabView/bar/1").frame)
        try host.tap(at: CGPoint(x: library.midX, y: library.midY))
        #expect(try node(host, "TabView/bar/1").attributes["selected"] == "true")
    }

    @Test("A press and release on a tab selects it, as a mouse click in the window does")
    func pointer() throws {
        let host = ViewHost(Selected(), device: screen)
        let library = try #require(try node(host, "TabView/bar/1").frame)
        // Anywhere in the tab's part of the bar, not only on its symbol.
        let point = CGPoint(x: library.minX + 4, y: library.maxY - 4)
        host.pointerDown(at: point)
        #expect(host.pressedNodeID == NodeID("Selected/TabView/bar/1"))
        #expect(host.pointerUp(at: point) == NodeID("Selected/TabView/bar/1"))
        #expect(texts(host).contains("Details"))
    }

    @Test("Each tab keeps its state and its navigation stack while another is selected")
    func keepsState() throws {
        let host = ViewHost(Selected(), device: screen)
        try host.tapButton(labeled: "Increment")
        try host.tapButton(labeled: "Library")
        try host.tapButton(labeled: "Details")
        try host.tapButton(labeled: "Increment")
        try host.tapButton(labeled: "Increment")
        #expect(texts(host).contains("Count: 2"))

        try host.tapButton(labeled: "Home")
        #expect(texts(host).contains("Count: 1"))
        try host.tapButton(labeled: "Library")
        #expect(texts(host).contains("Count: 2"))
        #expect(texts(host).contains("Details"))
    }

    @Test("A tab view without a selection keeps its own, and builds tabs with if")
    func ownSelection() throws {
        let host = ViewHost(Unselected(), device: screen)
        #expect(texts(host).first == "One")
        try host.tapButton(labeled: "Second")
        #expect(texts(host).first == "Two")
        #expect(
            try node(host, "TabView/bar/1").outline() == """
                Button selected=true
                ├─ Image font=system(18) symbolVariant=fill systemName=star
                └─ Text "Second" font=system(10).semibold
                """)
    }

    @Test("Views with tab items are tabs, labeled by their first symbol and text")
    func tabItems() throws {
        let host = ViewHost(Items(), device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ TabView
                   ├─ VStack
                   │  ├─ Text "Count: 0"
                   │  └─ Button
                   │     └─ Text "Increment"
                   └─ TabBar
                      ├─ Button selected=true
                      │  ├─ Image font=system(18) symbolVariant=fill systemName=number
                      │  └─ Text "Count" font=system(10).semibold
                      └─ Button
                         ├─ Image font=system(18) symbolVariant=fill systemName=star
                         └─ Text "Star" font=system(10).semibold
                """)
        try host.tapButton(labeled: "Increment")
        try host.tapButton(labeled: "Star")
        try host.tapButton(labeled: "Count")
        #expect(texts(host).first == "Count: 1")
    }

    @Test("A tab view with a selection selects the view whose tag equals it")
    func tags() throws {
        let host = ViewHost(Tagged(), device: screen)
        #expect(texts(host).prefix(2) == ["Selection: 2", "Two"])
        #expect(
            try node(host, "TabView").children[0].outline() == """
                Text "Two" tag=2
                """)
        try host.tapButton(labeled: "One")
        #expect(texts(host).prefix(2) == ["Selection: 1", "One"])
    }

    @Test("The views of a ForEach are tagged with their elements' identifiers")
    func forEachTags() throws {
        let host = ViewHost(Letters(), device: screen)
        #expect(texts(host).first == "Letter B")
        try host.tapButton(labeled: "C")
        #expect(texts(host).first == "Letter C")
    }

    @Test("The bar floats 21 points above the bottom of the screen, below the safe area")
    func barLayout() throws {
        let host = ViewHost(Selected(), device: screen)
        let tabView = try node(host, "Selected/TabView")
        #expect(tabView.frame == CGRect(x: 0, y: 40, width: 300, height: 430))
        let bar = try node(host, "TabView/bar")
        #expect(bar.frame == CGRect(x: 21, y: 417, width: 258, height: 62))
        // Two tabs share the capsule beside the search tab's 62-point circle,
        // 8 points away.
        #expect(
            try node(host, "TabView/bar/0").frame == CGRect(x: 29, y: 421, width: 86, height: 54))
        #expect(
            try node(host, "TabView/bar/1").frame == CGRect(x: 115, y: 421, width: 86, height: 54))
        #expect(
            try node(host, "TabView/bar/2").frame == CGRect(x: 217, y: 417, width: 62, height: 62))
        // The symbol is centered 21 points below the top of the tab, and the
        // title starts 36 points below it.
        #expect(try node(host, "bar/0/Image").frame == CGRect(x: 63, y: 433, width: 18, height: 18))
        #expect(try node(host, "bar/0/Text").frame?.minY == 457)
        // Content that does not scroll is centered above the bar.
        let content = try #require(host.root.children[0].children[0].frame)
        #expect(abs(content.midY - (40 + 417) / 2) < 0.01)
    }

    @Test("A list fills the tab and can scroll its last row above the bar")
    func scrollsUnderBar() throws {
        let host = ViewHost(LongList(), device: screen)
        let list = try node(host, "TabView/Tab/List")
        #expect(list.frame == CGRect(x: 0, y: 40, width: 300, height: 430))
        try host.scroll(list.id, to: CGPoint(x: 0, y: 10_000))
        let bar = try #require(try node(host, "TabView/bar").frame)
        let last = try #require(host.nodes(withText: "Row 11").first?.frame)
        #expect(last.maxY < bar.minY)
        // Without the bar's inset, the list could stop with the last row
        // under the bar.
        let offset = try #require(host.scrollOffset(of: list.id))
        let content = try #require(list.attributes["contentSize"])
        #expect(content.hasSuffix("× \(formatPoints(offset.y + 430 - 53))"))
    }

    @Test("The selected tab is in the tint color over a gray highlight")
    func drawing() throws {
        let host = ViewHost(Selected(), device: screen)
        let frame = host.render(scale: 2)
        let home = try #require(try node(host, "bar/0/Image").frame)
        let tint = ColorPalette.color(named: "tint")
        let center = frame.color(at: CGPoint(x: home.midX, y: home.midY))
        #expect([center.red, center.green, center.blue] == [tint.red, tint.green, tint.blue])
        // Beside the symbol, the highlight darkens the glass.
        let tab = try #require(try node(host, "TabView/bar/0").frame)
        let highlight = frame.color(at: CGPoint(x: tab.minX + 6, y: tab.midY))
        let library = try #require(try node(host, "TabView/bar/1").frame)
        let glass = frame.color(at: CGPoint(x: library.minX + 6, y: library.midY))
        #expect(highlight.red < glass.red)
    }
}

@MainActor
@Suite("Labels")
struct LabelTests {
    private struct Styles: View {
        var body: some View {
            VStack {
                Label("Both", systemImage: "star")
                Label("Title", systemImage: "star").labelStyle(.titleOnly)
                Label("Icon", systemImage: "star").labelStyle(.iconOnly)
                Label("Explicit", systemImage: "star").labelStyle(.titleAndIcon)
                Label {
                    Text("Custom")
                } icon: {
                    Image(systemName: "heart")
                }
                .labelStyle(VerticalLabelStyle())
            }
        }
    }

    private struct VerticalLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            VStack {
                configuration.icon
                configuration.title
            }
        }
    }

    @Test("A label shows its icon and title, as its style chooses")
    func outline() {
        let host = ViewHost(Styles(), device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Label
                   │  ├─ Image systemName=star
                   │  └─ Text "Both"
                   ├─ Label labelStyle=titleOnly
                   │  └─ Text "Title"
                   ├─ Label labelStyle=iconOnly
                   │  └─ Image systemName=star
                   ├─ Label labelStyle=titleAndIcon
                   │  ├─ Image systemName=star
                   │  └─ Text "Explicit"
                   └─ Label labelStyle=VerticalLabelStyle
                      └─ VStack
                         ├─ Image systemName=heart
                         └─ Text "Custom"
                """)
    }

    @Test("A label lays out its icon beside its title")
    func layout() throws {
        let host = ViewHost(Styles(), device: screen)
        let label = try #require(host.root.children[0].children.first)
        let icon = try #require(label.children[0].frame)
        let title = try #require(label.children[1].frame)
        #expect(title.minX - icon.maxX == LayoutDefaults.stackSpacing)
        #expect(icon.midY == title.midY)
    }

    @Test("In a toolbar, a label shows only its icon, on a glass circle")
    func toolbar() throws {
        struct Toolbar: View {
            var body: some View {
                NavigationStack {
                    Text("Content")
                        .toolbar {
                            Button(action: {}) {
                                Label("Add", systemImage: "plus")
                            }
                        }
                }
            }
        }
        let host = ViewHost(Toolbar(), device: screen)
        let group = try node(host, "bar/trailing")
        #expect(
            group.outline() == """
                ToolbarItemGroup placement=trailing
                └─ Button
                   └─ Label
                      └─ Image systemName=plus
                """)
        #expect(group.frame?.width == LayoutDefaults.toolbarButtonSize)
    }
}

@MainActor
@Suite("Symbol images")
struct SymbolImageTests {
    @Test("Every mapped name draws a Phosphor icon in both weights")
    func everyIconParses() {
        for name in phosphorIconNames.keys {
            for symbol in [name, name + ".fill"] {
                let resolved = SymbolLibrary.resolve(symbol)
                #expect(resolved.source == .phosphor, "\(symbol)")
                #expect(!resolved.path.isEmpty, "\(symbol)")
            }
        }
    }

    @Test("A name Parhelion cannot draw is reported in the tree and drawn as a ring")
    func missing() {
        let host = ViewHost(
            VStack {
                Image(systemName: "house.fill")
                Image(systemName: "no.such.symbol")
                Image(systemName: "chevron.right")
            },
            device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Image systemName=house.fill
                   ├─ Image missingSymbol=true systemName=no.such.symbol
                   └─ Image systemName=chevron.right
                """)
        #expect(SymbolLibrary.resolve("no.such.symbol").source == .placeholder)
        #expect(SymbolLibrary.resolve("chevron.right").source == .builtIn)
    }

    @Test("Symbols take the size of their font and image scale from around them")
    func sizing() throws {
        let host = ViewHost(
            VStack {
                Image(systemName: "star")
                Image(systemName: "star").font(.title)
                VStack {
                    Image(systemName: "star")
                }
                .imageScale(.large)
            },
            device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Image systemName=star
                   ├─ Image font=title systemName=star
                   └─ VStack
                      └─ Image imageScale=large systemName=star
                """)
        let sides = host.root.allNodes.filter { $0.kind == "Image" }.compactMap(\.frame?.width)
        #expect(sides.map(formatPoints) == ["17", "28", "21.93"])
    }

    @Test("A symbol is drawn in its foreground style")
    func drawing() throws {
        let host = ViewHost(
            Image(systemName: "square.fill").font(.system(size: 40)).foregroundStyle(.red),
            device: screen)
        let frame = host.render(scale: 2)
        let image = try #require(host.root.children[0].frame)
        let center = frame.color(at: CGPoint(x: image.midX, y: image.midY))
        let red = ColorPalette.color(named: "red")
        #expect([center.red, center.green, center.blue] == [red.red, red.green, red.blue])
        let outside = frame.color(at: CGPoint(x: image.minX - 10, y: image.midY))
        #expect([outside.red, outside.green, outside.blue] == [255, 255, 255])
    }
}
