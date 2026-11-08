import Foundation
import Testing

@testable import ParhelionUI

private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 500),
    safeAreaInsets: EdgeInsets(top: 40, leading: 0, bottom: 30, trailing: 0)
)

private let names = ["Apple", "Banana", "Cherry"]

private func matches(_ query: String) -> [String] {
    query.isEmpty ? names : names.filter { $0.localizedCaseInsensitiveContains(query) }
}

private struct Results: View {
    @Environment(\.isSearching) private var isSearching
    let query: String

    var body: some View {
        List {
            if isSearching { Text("Searching") }
            ForEach(matches(query), id: \.self) { Text($0) }
        }
    }
}

private struct Browse: View {
    var placement: SearchFieldPlacement = .automatic
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Results(query: query)
                .navigationTitle("Browse")
                .searchable(text: $query, placement: placement, prompt: "Find fruit")
        }
    }
}

private struct SearchTab: View {
    @State private var query = ""

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { Text("Home") }
            Tab(role: .search) {
                NavigationStack {
                    Results(query: query)
                        .navigationTitle("Search")
                }
                .searchable(text: $query)
            }
        }
    }
}

private struct SheetOwner: View {
    @State private var showing = true
    @State private var query = ""

    var body: some View {
        Text("Behind")
            .sheet(isPresented: $showing) {
                NavigationStack {
                    VStack {
                        Text("Typed: \(query)")
                        Results(query: query)
                    }
                    .navigationTitle("Browse")
                    .searchable(text: $query)
                }
            }
    }
}

@MainActor
private func field(_ host: ViewHost) throws -> ViewNode {
    try #require(host.root.allNodes.first { $0.kind == "TextField" })
}

@MainActor
private func rows(_ host: ViewHost) -> [String] {
    host.root.allNodes.filter { $0.kind == "Text" }.compactMap(\.text).filter {
        names.contains($0)
    }
}

@MainActor
@Suite("Searchable")
struct SearchableTests {
    @Test("In a navigation stack, the search field is a glass capsule over the bottom")
    func outline() {
        let host = ViewHost(Browse(), device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ NavigationStack
                   ├─ NavigationBar titleDisplayMode=large
                   │  └─ Text "Browse" font=largeTitle.bold
                   └─ Searchable placement=toolbar
                      ├─ List contentOffset=0, 0 contentSize=300 × 176
                      │  └─ Section
                      │     ├─ Text "Apple" listRow
                      │     ├─ Text "Banana" listRow
                      │     └─ Text "Cherry" listRow
                      └─ SearchField placement=toolbar
                         └─ HStack padding(0, 14, 0, 14) frame(height: 48) glassEffect(regular, in: Capsule) spacing=10
                            ├─ Image foregroundStyle=primary systemName=magnifyingglass
                            └─ TextField frame(maxWidth: inf) placeholder=Find fruit value=
                """)
    }

    @Test("With the drawer placement, the search field joins the content under the navigation bar")
    func drawerOutline() {
        let host = ViewHost(Browse(placement: .navigationBarDrawer), device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ NavigationStack
                   ├─ NavigationBar titleDisplayMode=large
                   │  └─ Text "Browse" font=largeTitle.bold
                   └─ Searchable placement=top
                      ├─ List contentOffset=0, 0 contentSize=300 × 176
                      │  └─ Section
                      │     ├─ Text "Apple" listRow
                      │     ├─ Text "Banana" listRow
                      │     └─ Text "Cherry" listRow
                      └─ SearchField placement=top
                         └─ HStack padding(0, 16, 0, 16) padding(8, 0, 8, 0) spacing=12
                            └─ HStack padding(0, 12, 0, 12) frame(height: 36) background(system.tertiaryFill) clipShape(Capsule) spacing=8
                               ├─ Image foregroundStyle=secondary systemName=magnifyingglass
                               └─ TextField frame(maxWidth: inf) placeholder=Find fruit value=
                """)
    }

    @Test("The field floats 28 points from the sides and bottom, over a list that fills the screen")
    func toolbarLayout() throws {
        let host = ViewHost(Browse(), device: screen)
        let bar = try #require(host.root.allNodes.first { $0.kind == "NavigationBar" }?.frame)
        let search = try #require(host.root.allNodes.first { $0.kind == "SearchField" }?.frame)
        let list = try #require(host.root.allNodes.first { $0.kind == "List" })
        let text = try #require(try field(host).frame)
        // Measured on an iPhone 18 Pro Max under iOS 27.2.
        #expect(search == CGRect(x: 28, y: 424, width: 244, height: 48))
        // The list is the stack's screen: it scrolls under the bar and the
        // field, and its rows start under the bar.
        #expect(list.frame == CGRect(x: 0, y: 0, width: 300, height: 500))
        let firstRow = try #require(host.root.allNodes.first { $0.text == "Apple" }?.frame)
        #expect(firstRow.minY >= bar.maxY)
        #expect(text.height == 22)
        #expect(search.insetBy(dx: 14, dy: 0).contains(text))
    }

    @Test("With the drawer placement, the field sits under the bar, and the list's rows below it")
    func topLayout() throws {
        let host = ViewHost(Browse(placement: .navigationBarDrawer), device: screen)
        let bar = try #require(host.root.allNodes.first { $0.kind == "NavigationBar" }?.frame)
        let search = try #require(host.root.allNodes.first { $0.kind == "SearchField" })
        #expect(search.attributes["placement"] == "top")
        let searchFrame = try #require(search.frame)
        let text = try #require(try field(host).frame)
        #expect(searchFrame.minY == bar.maxY)
        #expect(searchFrame.width == 300)
        let firstRow = try #require(host.root.allNodes.first { $0.text == "Apple" }?.frame)
        #expect(firstRow.minY >= searchFrame.maxY)
        #expect(text.height == 22)
        #expect(text.maxX <= 300 - 16)
        try host.focus(field(host).id)
        host.update()
        try host.tapButton(labeled: "Cancel")
        #expect(host.focusedNodeID == nil)
    }

    @Test("Typing into the field writes the binding and filters the content")
    func typing() throws {
        let host = ViewHost(Browse(), device: screen)
        #expect(rows(host) == ["Apple", "Banana", "Cherry"])
        try host.focus(field(host).id)
        host.typeText("an")
        #expect(try field(host).attributes["value"] == "an")
        #expect(rows(host) == ["Banana"])
        host.press(.backspace)
        #expect(try field(host).attributes["value"] == "a")
        #expect(rows(host) == ["Apple", "Banana"])
    }

    @Test("A tap on the field focuses it, and typing then writes the binding")
    func tapToFocus() throws {
        let host = ViewHost(Browse(), device: screen)
        let frame = try #require(try field(host).frame)
        host.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY))
        host.pointerUp(at: CGPoint(x: frame.midX, y: frame.midY))
        #expect(host.focusedNodeID == (try field(host)).id)
        host.typeText("Ch")
        #expect(rows(host) == ["Cherry"])
    }

    @Test("isSearching is true in the content while the field is focused or holds text")
    func isSearching() throws {
        let host = ViewHost(Browse(placement: .navigationBarDrawer), device: screen)
        func searching() -> Bool {
            host.root.allNodes.contains { $0.text == "Searching" }
        }
        #expect(!searching())
        try host.focus(field(host).id)
        host.update()
        #expect(searching())
        #expect(
            host.root.allNodes.contains {
                $0.kind == "Searchable" && $0.attributes["isSearching"] == "true"
            })
        host.typeText("x")
        host.press(.return)
        // Still searching: there is text.
        #expect(searching())
        try host.tapButton(labeled: "Cancel")
        #expect(!searching())
        #expect(try field(host).attributes["value"] == "")
        #expect(host.focusedNodeID == nil)
    }

    @Test("The clear button empties the field")
    func clear() throws {
        let host = ViewHost(Browse(), device: screen)
        try host.focus(field(host).id)
        host.typeText("zzz")
        #expect(rows(host).isEmpty)
        try host.tapButton(labeled: "Clear text")
        #expect(try field(host).attributes["value"] == "")
        #expect(rows(host).count == 3)
    }

    @Test("The prompt is the placeholder, and defaults to Search")
    func prompt() throws {
        #expect(
            try field(ViewHost(Browse(), device: screen)).attributes["placeholder"] == "Find fruit")
        let host = ViewHost(SearchTab(), device: screen)
        try host.tapButton(labeled: "Search")
        #expect(try field(host).attributes["placeholder"] == "Search")
    }

    // MARK: Search tab

    @Test("In a search tab, the field is a glass capsule above the tab bar")
    func searchTab() throws {
        let host = ViewHost(SearchTab(), device: screen)
        try host.tapButton(labeled: "Search")
        let searchable = try #require(host.root.allNodes.first { $0.kind == "Searchable" })
        #expect(searchable.attributes["placement"] == "bottom")
        let search = try #require(host.root.allNodes.first { $0.kind == "SearchField" }?.frame)
        let tabBar = try #require(host.root.allNodes.first { $0.kind == "TabBar" }?.frame)
        #expect(search.maxY <= tabBar.minY)
        #expect(tabBar.minY - search.maxY < 20)
        #expect(search.height == 64)
        let row = try #require(host.root.allNodes.first { $0.kind == "SearchField" })
        #expect(
            row.allNodes.contains {
                $0.attributes["glassEffect"] != nil
                    || $0.modifiers.description.contains("glassEffect")
            })
    }

    @Test("Typing into a search tab's field writes the binding")
    func searchTabTyping() throws {
        let host = ViewHost(SearchTab(), device: screen)
        try host.tapButton(labeled: "Search")
        try host.focus(field(host).id)
        host.typeText("che")
        #expect(try field(host).attributes["value"] == "che")
        #expect(rows(host) == ["Cherry"])
        // No Cancel button at the bottom.
        #expect(!host.root.allNodes.contains { $0.label == "Cancel" })
    }

    @Test("A search field in another tab goes under the bar")
    func otherTabs() throws {
        struct Tabs: View {
            @State var query = ""
            var body: some View {
                TabView {
                    Tab("Home", systemImage: "house") {
                        NavigationStack { Results(query: query).searchable(text: $query) }
                    }
                    Tab(role: .search) { Text("Search") }
                }
            }
        }
        let host = ViewHost(Tabs(), device: screen)
        #expect(
            host.root.allNodes.first { $0.kind == "Searchable" }?.attributes["placement"] == "top")
    }

    // MARK: Sheet

    @Test("A search field in a sheet takes typing and writes the binding")
    func sheet() throws {
        let host = ViewHost(SheetOwner(), device: screen)
        let sheet = try #require(host.root.children.first { $0.kind == "Sheet" })
        #expect(sheet.allNodes.contains { $0.kind == "SearchField" })
        try host.focus(field(host).id)
        host.typeText("Ban")
        #expect(host.root.allNodes.contains { $0.text == "Typed: Ban" })
        #expect(rows(host) == ["Banana"])
        let frame = try #require(try field(host).frame)
        #expect(frame.minY > (sheet.frame?.minY ?? 0))
    }

    @Test("dismissSearch clears the text and ends editing")
    func dismissSearch() throws {
        struct Dismiss: View {
            @Environment(\.dismissSearch) private var dismissSearch
            var body: some View { Button("Done") { dismissSearch() } }
        }
        struct Host: View {
            @State var query = "abc"
            var body: some View {
                NavigationStack { Dismiss().searchable(text: $query) }
            }
        }
        let host = ViewHost(Host(), device: screen)
        try host.focus(field(host).id)
        try host.tapButton(labeled: "Done")
        #expect(try field(host).attributes["value"] == "")
        #expect(host.focusedNodeID == nil)
    }

    // MARK: Tab views (#115)

    @Test("A searchable list in a tab scrolls under the bars and minimizes the tab bar")
    func listInTab() throws {
        struct Albums: View {
            @State var query = ""
            var body: some View {
                TabView {
                    Tab("Library", systemImage: "square.stack") {
                        NavigationStack {
                            List(1..<60) { Text("Album \($0)") }
                                .navigationTitle("Library")
                                .searchable(text: $query)
                        }
                    }
                    Tab("Radio", systemImage: "dot.radiowaves.left.and.right") { Text("Radio") }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
            }
        }
        let host = ViewHost(Albums(), device: .iPhone18ProMax)
        let tabView = try #require(host.root.allNodes.first { $0.kind == "TabView" })
        let list = try #require(host.root.allNodes.first { $0.kind == "List" })
        // The scroll edge effect and the tab bar find the list.
        #expect(TreeRenderer.scrollView(under: tabView)?.id == list.id)
        // The list fills the screen; its content starts under the bar and
        // the field below it.
        #expect(list.frame == CGRect(x: 0, y: 0, width: 440, height: 956))
        let bar = try #require(host.root.allNodes.first { $0.kind == "NavigationBar" }?.frame)
        let search = try #require(host.root.allNodes.first { $0.kind == "SearchField" })
        #expect(search.attributes["placement"] == "top")
        let searchFrame = try #require(search.frame)
        #expect(searchFrame.minY == bar.maxY)
        let firstRow = try #require(host.root.allNodes.first { $0.text == "Album 1" }?.frame)
        #expect(firstRow.minY >= searchFrame.maxY)

        try host.scroll(list.id, to: CGPoint(x: 0, y: 300))
        host.advanceTime(by: 1)
        let tabBar = try #require(host.root.allNodes.first { $0.kind == "TabBar" })
        #expect(tabBar.attributes["minimized"] == "true")
        let scrolled = try #require(host.root.allNodes.first { $0.kind == "List" })
        #expect(scrolled.attributes["contentUnderBars"] == "top,bottom")
    }

    private struct SearchOnTabView: View {
        @State var query = ""
        var body: some View {
            TabView {
                Tab("Home", systemImage: "house") { Text("Home") }
                Tab(role: .search) {
                    NavigationStack {
                        Results(query: query).navigationTitle("Search")
                    }
                }
            }
            .searchable(text: $query)
        }
    }

    @Test("A search field on a tab view belongs to its search tab")
    func onTabView() throws {
        let host = ViewHost(SearchOnTabView(), device: screen)
        // No field while another tab is selected.
        #expect(
            host.root.outline() == """
                Root
                └─ TabView
                   ├─ Text "Home"
                   └─ TabBar
                      ├─ Button selected=true
                      │  ├─ Image font=system(23) symbolVariant=fill systemName=house
                      │  └─ Text "Home" font=system(10).semibold
                      └─ Button label=Search role=search
                         └─ Image font=system(24) systemName=magnifyingglass
                """)
        try host.tapButton(labeled: "Search")
        let searchable = try #require(host.root.allNodes.first { $0.kind == "Searchable" })
        #expect(searchable.attributes["placement"] == "bottom")
        let search = try #require(host.root.allNodes.first { $0.kind == "SearchField" }?.frame)
        let tabBar = try #require(host.root.allNodes.first { $0.kind == "TabBar" }?.frame)
        #expect(search.maxY <= tabBar.minY)
        #expect(host.execute(.focus(id: try field(host).id.rawValue)).ok)
        #expect(host.execute(.typeText("ban")).ok)
        #expect(try field(host).attributes["value"] == "ban")
        #expect(rows(host) == ["Banana"])
        // The field keeps its text when the search tab is selected again.
        try host.tapButton(labeled: "Home")
        #expect(!host.root.allNodes.contains { $0.kind == "SearchField" })
        try host.tapButton(labeled: "Search")
        #expect(try field(host).attributes["value"] == "ban")
    }

    @Test("A search field on a tab view without a search tab stays at the top")
    func onTabViewWithoutSearchTab() throws {
        struct Tabs: View {
            @State var query = ""
            var body: some View {
                TabView {
                    Tab("Home", systemImage: "house") { Text("Home") }
                }
                .searchable(text: $query)
            }
        }
        let host = ViewHost(Tabs(), device: screen)
        let searchable = try #require(host.root.allNodes.first { $0.kind == "Searchable" })
        #expect(searchable.attributes["placement"] == "top")
    }

    @Test("An agent focuses the field and types through the preview commands")
    func commands() throws {
        let host = ViewHost(Browse(), device: screen)
        let id = try field(host).id
        #expect(host.execute(.typeText("x")).ok == false)
        #expect(host.execute(.focus(id: id.rawValue)).ok)
        #expect(host.execute(.typeText("Apple")).ok)
        #expect(rows(host) == ["Apple"])
        #expect(host.execute(.pressKey("return")).ok)
        #expect(host.focusedNodeID == nil)
    }
}
