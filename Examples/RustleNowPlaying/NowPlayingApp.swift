import SwiftUI

// The shape of Rustle's Now Playing screen, for measuring frame times in the
// preview: `parhelion preview .build/debug/RustleNowPlaying` and press Play.
// A copy of these views is in Tests/ParhelionUITests/RustleFixtures.swift.
@main
struct NowPlayingApp: App {
    var body: some Scene {
        WindowGroup {
            NowPlayingFixture()
        }
    }
}

/// The shape of Rustle's Now Playing screen: large art that grows while
/// playing, a title and artist, a scrubber, and transport buttons on glass.
struct NowPlayingFixture: View {
    @State private var isPlaying = false
    @State private var progress = 0.3
    /// With `--autoplay`, Play and Pause toggle on their own so that a run
    /// measures the animation without anyone pressing the button.
    var autoplay = CommandLine.arguments.contains("--autoplay")

    var body: some View {
        VStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [.purple, .pink, .orange], startPoint: .topLeading,
                        endPoint: .bottomTrailing)
                )
                .frame(width: isPlaying ? 360 : 300, height: isPlaying ? 360 : 300)
                .shadow(radius: isPlaying ? 24 : 8)
            VStack(spacing: 4) {
                Text("Blinding Lights").font(.title2).bold()
                Text("The Weeknd · After Hours").font(.body).foregroundStyle(.secondary)
            }
            Slider(value: $progress)
                .padding(.horizontal, 24)
            HStack(spacing: 32) {
                Button {
                } label: {
                    Image(systemName: "backward.fill").font(.title)
                }
                Button {
                    withAnimation(.spring(duration: 0.5, bounce: 0.3)) { isPlaying.toggle() }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.largeTitle)
                        .frame(width: 72, height: 72)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                Button {
                } label: {
                    Image(systemName: "forward.fill").font(.title)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 40)
        .task {
            guard autoplay else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.spring(duration: 0.5, bounce: 0.3)) { isPlaying.toggle() }
            }
        }
    }
}
