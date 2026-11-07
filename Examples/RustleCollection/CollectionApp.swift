import SwiftUI

// The shape of Rustle's Collection screen, for measuring frame times in the
// preview: `parhelion mcp --product RustleCollection --window`, then the `drag`
// tool, or `parhelion preview .build/debug/RustleCollection` and scroll. A copy
// of these views is in Tests/ParhelionUITests/RustleFixtures.swift.
@main
struct CollectionApp: App {
    var body: some Scene {
        WindowGroup {
            CollectionFixture()
        }
    }
}

/// A song in the Collection fixture.
struct FixtureSong: Identifiable {
    var id: Int
    var title: String { "Song number \(id)" }
    var artist: String { "Artist \(id % 97) · Album \(id % 31)" }
}

/// The shape of Rustle's Collection screen: a lazy column of 5,000 rows, each
/// with a square of art and two lines of text.
struct CollectionFixture: View {
    var count = 5000
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach((0..<count).map(FixtureSong.init)) { song in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(
                                                red: Double(song.id % 7) / 7, green: 0.4, blue: 0.8),
                                            .indigo,
                                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .frame(width: 56, height: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).font(.body)
                                Text(song.artist).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("Collection")
        }
    }
}
