import MediaPlayer
import SwiftUI

@main
struct MediaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// A fake player: it plays nothing, but tells the system what it would play.
@MainActor @Observable
final class Player {
    static let shared = Player()

    private(set) var isPlaying = true
    private(set) var track = 1
    private(set) var position = 30.0

    private init() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.playCommand.addTarget { _ in
            MainActor.assumeIsolated { Player.shared.setPlaying(true) }
            return .success
        }
        commands.pauseCommand.addTarget { _ in
            MainActor.assumeIsolated { Player.shared.setPlaying(false) }
            return .success
        }
        commands.nextTrackCommand.addTarget { _ in
            MainActor.assumeIsolated { Player.shared.skip(by: 1) }
            return .success
        }
        commands.previousTrackCommand.addTarget { _ in
            MainActor.assumeIsolated { Player.shared.skip(by: -1) }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            MainActor.assumeIsolated { Player.shared.seek(to: event.positionTime) }
            return .success
        }
        publish()
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        publish()
    }

    func skip(by step: Int) {
        track = max(track + step, 1)
        position = 0
        publish()
    }

    func seek(to seconds: Double) {
        position = seconds
        publish()
    }

    var title: String { "Fixture Song \(track)" }

    private func publish() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Fixture Artist",
            MPMediaItemPropertyAlbumTitle: "Fixture Album",
            MPMediaItemPropertyPlaybackDuration: 240.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
}

struct ContentView: View {
    var body: some View {
        let player = Player.shared
        VStack {
            Text(player.title)
            Text(player.isPlaying ? "Playing" : "Paused")
                .accessibilityIdentifier("status")
            Button(player.isPlaying ? "Pause" : "Play") {
                player.setPlaying(!player.isPlaying)
            }
        }
        .padding()
    }
}
