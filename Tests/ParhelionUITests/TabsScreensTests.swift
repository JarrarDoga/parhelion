import Foundation
import Testing

@testable import ParhelionUI

// A copy of the views of Examples/Tabs, whose screens show the tab bar,
// symbol images, and labels. The README shows them. A test checks that the
// copy matches the example, apart from `private`.

private enum AppTab: Hashable {
    case home, favorites, settings, search
}

private struct Place: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var symbol: String
}

private let places = [
    Place(name: "Home", symbol: "house"),
    Place(name: "Work", symbol: "building.2"),
    Place(name: "Gym", symbol: "figure.run"),
    Place(name: "Café", symbol: "cup.and.saucer"),
    Place(name: "Library", symbol: "books.vertical"),
    Place(name: "Park", symbol: "tree"),
    Place(name: "Station", symbol: "tram"),
    Place(name: "Airport", symbol: "airplane"),
    Place(name: "Market", symbol: "cart"),
    Place(name: "Museum", symbol: "building.columns"),
    Place(name: "Beach", symbol: "sun.max"),
    Place(name: "Hospital", symbol: "cross.case"),
]

private struct ContentView: View {
    @State private var selection = AppTab.home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Places", systemImage: "map", value: AppTab.home) {
                PlacesView()
            }
            Tab("Favorites", systemImage: "heart", value: AppTab.favorites) {
                FavoritesView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }
        }
    }
}

private struct PlacesView: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(places) { place in
                    NavigationLink(value: place) {
                        Label(place.name, systemImage: place.symbol)
                    }
                }
            }
            .navigationTitle("Places")
            .navigationDestination(for: Place.self) { place in
                PlaceView(place: place)
            }
        }
    }
}

private struct PlaceView: View {
    var place: Place
    @State private var visits = 0

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: place.symbol)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Visits: \(visits)")
            Button("Visit") { visits += 1 }
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle(place.name)
    }
}

private struct FavoritesView: View {
    @State private var likes = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: likes > 0 ? "heart.fill" : "heart")
                    .font(.largeTitle)
                    .foregroundStyle(.pink)
                Text("Likes: \(likes)")
                Button {
                    likes += 1
                } label: {
                    Label("Like", systemImage: "hand.thumbsup")
                }
                .buttonStyle(.bordered)
            }
            .navigationTitle("Favorites")
        }
    }
}

private struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    Label("Notifications", systemImage: "bell")
                    Label("Privacy", systemImage: "lock")
                    Label("Display", systemImage: "sun.max")
                }
                Section("Account") {
                    Label("Profile", systemImage: "person.crop.circle")
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct SearchView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Search places", text: $query)
                    .padding(10)
                    .background(.gray.opacity(0.15))
                ForEach(places.filter { !query.isEmpty && $0.name.contains(query) }) { place in
                    Label(place.name, systemImage: place.symbol)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Search")
        }
    }
}

/// The Tabs example's screens, settled after each step.
@MainActor
enum TabsScreens {
    enum Screen: String, CaseIterable {
        case places, place, settings, search
    }

    static func host(showing screen: Screen, device: Device = .iPhone16) throws -> ViewHost {
        let host = ViewHost(ContentView(), device: device)
        switch screen {
        case .places:
            break
        case .place:
            try host.tapButton(labeled: "Café")
            host.advanceTime(by: 2)
            try host.tapButton(labeled: "Visit")
        case .settings:
            try host.tapButton(labeled: "Settings")
        case .search:
            try host.tapButton(labeled: "Search")
            try host.focus(host.root.allNodes.first { $0.kind == "TextField" }?.id)
            host.typeText("a")
            try host.focus(nil)
        }
        host.advanceTime(by: 2)
        return host
    }

    /// A screen as the README shows it: at 2× with the status bar and the
    /// home indicator, as `--png` draws.
    static func readmeImage(_ screen: Screen) throws -> Data {
        try host(showing: screen).render(scale: 2, chrome: .systemBars).pngData()
    }

    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func readmeImageURL(_ screen: Screen, in directory: URL? = nil) -> URL {
        (directory ?? repository.appendingPathComponent("docs/images"))
            .appendingPathComponent("tabs-\(screen.rawValue).png")
    }
}

@MainActor
@Suite("Tabs screens")
struct TabsScreensTests {
    @Test("The test's copy of the Tabs example matches the example")
    func copyMatchesExample() throws {
        let example = try String(
            contentsOf: TabsScreens.repository.appendingPathComponent(
                "Examples/Tabs/TabsApp.swift"),
            encoding: .utf8)
        let copy = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        let views = example[example.range(of: "enum AppTab")!.lowerBound...]
        let copied = copy[
            copy.range(of: "private enum AppTab")!
                .lowerBound..<copy.range(of: "/// The Tabs example's screens")!.lowerBound
        ]
        let unprivate = copied.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("private ") ? $0.dropFirst(8) : $0 }
            .joined(separator: "\n")
        #expect(
            unprivate.trimmingCharacters(in: .whitespacesAndNewlines)
                == views.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("Switching tabs keeps each tab's navigation stack")
    func switching() throws {
        let host = try TabsScreens.host(showing: .place)
        #expect(!host.isAnimating)
        #expect(!host.nodes(withText: "Visits: 1").isEmpty)
        try host.tapButton(labeled: "Favorites")
        try host.tapButton(labeled: "Like")
        #expect(!host.nodes(withText: "Likes: 1").isEmpty)
        try host.tapButton(labeled: "Places")
        #expect(!host.nodes(withText: "Visits: 1").isEmpty)
    }

    /// Rendering is deterministic, so the README's images must match a fresh
    /// render. After an intended rendering change, regenerate them with
    /// `PARHELION_README_IMAGES=docs/images swift test --filter writeTabsReadmeImages`.
    @Test("The README's Tabs images match a fresh render", arguments: TabsScreens.Screen.allCases)
    func readmeImages(_ screen: TabsScreens.Screen) throws {
        let committed = try Data(contentsOf: TabsScreens.readmeImageURL(screen))
        #expect(try TabsScreens.readmeImage(screen) == committed)
    }

    @Test(
        "Write the README's Tabs images",
        .enabled(if: ProcessInfo.processInfo.environment["PARHELION_README_IMAGES"] != nil)
    )
    func writeTabsReadmeImages() throws {
        let path = ProcessInfo.processInfo.environment["PARHELION_README_IMAGES"] ?? ""
        let directory = URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        for screen in TabsScreens.Screen.allCases {
            try TabsScreens.readmeImage(screen).write(
                to: TabsScreens.readmeImageURL(screen, in: directory))
        }
    }

    /// Writes the screens at 3× on an iPhone 16 Pro, the size of Apple's iOS
    /// 27 UI Kit, to compare with its artwork. Set `PARHELION_DEMO_DIR` to a
    /// directory.
    @Test(
        "Write the Tabs screens at 3×",
        .enabled(if: ProcessInfo.processInfo.environment["PARHELION_DEMO_DIR"] != nil)
    )
    func renderTabsScreens() throws {
        let directory = ProcessInfo.processInfo.environment["PARHELION_DEMO_DIR"] ?? ""
        for screen in TabsScreens.Screen.allCases {
            let host = try TabsScreens.host(showing: screen, device: .iPhone16Pro)
            let url = URL(fileURLWithPath: directory)
                .appendingPathComponent("tabs-\(screen.rawValue).png")
            try host.render(scale: 3, chrome: .systemBars).pngData().write(to: url)
        }
    }
}
