import Foundation
import Testing

@testable import ParhelionUI

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

/// The shape of Rustle's Now Playing screen: large art that grows while
/// playing, a title and artist, a scrubber, and transport buttons on glass.
struct NowPlayingFixture: View {
    @State private var isPlaying = false
    @State private var progress = 0.3

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
    }
}

/// Times the Rustle-shaped fixtures the way the preview draws them at 120
/// Hz: a scroll of the Collection and the animation of Now Playing.
/// `renderTiming` calls it; each line starts with `BENCH rustle`.
@MainActor
func rustleTiming() throws {
    let clock = ContinuousClock()
    for scale in [2.0, 3.0] {
        var host: ViewHost?
        let first = clock.measure { host = ViewHost(CollectionFixture(), device: .iPhone18ProMax) }
        let collection = try #require(host)
        _ = collection.render(scale: scale, chrome: .screen)
        var layout = Duration.zero
        var render = Duration.zero
        var slowest = Duration.zero
        let frames = 60
        for _ in 0..<frames {
            let moved = clock.measure {
                collection.scroll(by: CGSize(width: 0, height: 10), at: CGPoint(x: 200, y: 400))
                collection.advanceTime(by: 1.0 / 120)
            }
            let drawn = clock.measure { _ = collection.render(scale: scale, chrome: .screen) }
            layout += moved
            render += drawn
            slowest = max(slowest, moved + drawn)
        }
        print(
            "BENCH rustle Collection of 5,000 at \(Int(scale))×: first layout \(first); per frame, "
                + "scroll and layout \(layout / frames), render \(render / frames), "
                + "slowest \(slowest)")

        let playing = ViewHost(NowPlayingFixture(), device: .iPhone18ProMax)
        _ = playing.render(scale: scale, chrome: .screen)
        var total = Duration.zero
        var worst = Duration.zero
        var animated = 0
        for label in ["Play", "Pause"] {
            try playing.tapButton(labeled: label)
            _ = playing.render(scale: scale, chrome: .screen)
            while playing.isAnimating, animated < 480 {
                playing.advanceTime(by: 1.0 / 120)
                let drawn = clock.measure { _ = playing.render(scale: scale, chrome: .screen) }
                total += drawn
                worst = max(worst, drawn)
                animated += 1
            }
        }
        print(
            "BENCH rustle Now Playing animating at \(Int(scale))×: \(total / max(animated, 1)) "
                + "per frame, slowest \(worst), \(animated) frames")
    }
}
