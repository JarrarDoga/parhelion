import SwiftUI

@main
struct RustApp: App {
    var body: some Scene {
        WindowGroup {
            TrackList()
        }
    }
}

struct TrackList: View {
    private let backend = FixtureBackend()

    var body: some View {
        VStack(alignment: .leading) {
            Text(backend.greeting())
            ForEach(backend.tracks(), id: \.id) { track in
                Text("\(track.title) by \(track.artist)")
            }
        }
        .padding()
    }
}
