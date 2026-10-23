import SwiftUI

@main
struct TabsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

enum AppTab: Hashable {
    case home, favorites, settings, search
}

struct Place: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var symbol: String
}

let places = [
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

struct ContentView: View {
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

struct PlacesView: View {
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

struct PlaceView: View {
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

struct FavoritesView: View {
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

struct SettingsView: View {
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

struct SearchView: View {
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
