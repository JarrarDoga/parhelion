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
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Results(query: query)
                .navigationTitle("Browse")
                .searchable(text: $query, prompt: "Find fruit")
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
    @Test("A search field joins the content under the navigation bar")
    func outline() {
        let host = ViewHost(Browse(), device: screen)
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

    @Test("The field sits under the bar, above the list, and fills the width")
    func topLayout() throws {
        let host = ViewHost(Browse(), device: screen)
        let bar = try #require(host.root.allNodes.first { $0.kind == "NavigationBar" }?.frame)
        let search = try #require(host.root.allNodes.first { $0.kind == "SearchField" }?.frame)
        let list = try #require(host.root.allNodes.first { $0.kind == "List" }?.frame)
        let text = try #require(try field(host).frame)
        #expect(search.minY >= bar.maxY)
        #expect(search.maxY <= list.minY)
        #expect(search.width == 300)
        #expect(text.height == 22)
        #expect(text.maxX <= 300 - 16)
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
        let host = ViewHost(Browse(), device: screen)
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
