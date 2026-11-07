// Calls the compile-only stubs that Rustle's iPhone app needs, written as an
// iOS app is written: through `import SwiftUI`, `import MediaPlayer`, and
// `import AVFAudio`. The stubs build here and against Apple's SDKs.

import AVFAudio
import MediaPlayer
import SwiftUI
import Testing

private struct Song: Identifiable {
    var id: Int
    var title: String
}

private struct Stubs: View {
    @State private var query = ""
    @State private var text = ""
    @State private var editMode = EditMode.inactive
    @State private var songs = [Song(id: 1, title: "One"), Song(id: 2, title: "Two")]
    @State private var scrolledID: Int?
    @State private var position = ScrollPosition()
    @GestureState private var dragOffset = CGSize.zero
    @Namespace private var namespace
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.editMode) private var environmentEditMode
    @Environment(\.isSearching) private var isSearching
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4, pinnedViews: []) {
                                ForEach(songs) { song in
                                    Text(song.title)
                                        .id(song.id)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button("Delete", role: .destructive) {}
                                        }
                                        .contextMenu {
                                            Button("Play") {}
                                        } preview: {
                                            Text("Preview")
                                        }
                                        .matchedGeometryEffect(id: song.id, in: namespace)
                                        .matchedTransitionSource(id: song.id, in: namespace)
                                        .accessibilityIdentifier("song.\(song.id)")
                                        .accessibilityLabel("Song")
                                        .accessibilityLabel(Text("Song"))
                                }
                                .onMove { _, _ in }
                                .onDelete { _ in }
                            }
                            .scrollTargetLayout()
                            LazyHStack {
                                Text(scenePhase == .active ? "Active" : "Away")
                            }
                        }
                        .scrollPosition(id: $scrolledID, anchor: .top)
                        .scrollPosition($position)
                        .scrollTargetBehavior(.paging)
                        .scrollTargetBehavior(.viewAligned)
                        .onScrollGeometryChange(for: CGFloat.self) { geometry in
                            geometry.contentOffset.y
                        } action: { _, _ in
                            proxy.scrollTo(1, anchor: .center)
                        }
                        .refreshable {}
                        .listSectionIndexVisibility(.hidden)
                        .sectionIndexLabel(Text("A"))
                        .environment(\.editMode, $editMode)
                    }
                    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
                    .searchable(text: $query, placement: .toolbar, prompt: "Search")
                    .searchable(text: $query, prompt: Text("Search"))
                    .navigationTransition(.zoom(sourceID: 1, in: namespace))
                }
            }
            Tab("Player", systemImage: "play") {
                VStack {
                    Group {
                        Menu("Options") { Button("Share") {} }
                        Menu("Options", systemImage: "ellipsis") { Button("Share") {} }
                        Menu {
                            Button("Share") {}
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        ProgressView()
                        ProgressView("Loading")
                        ProgressView(value: 0.5)
                        ProgressView(value: 0.5, total: 2.0) { Text("Loading") }
                        ProgressView(value: 0.5) {
                            Text("Loading")
                        } currentValueLabel: {
                            Text("50%")
                        }
                    }
                    Group {
                        PasteButton(payloadType: String.self) { strings in
                            text = strings.first ?? ""
                        }
                        TextField("Notes", text: $text, axis: .vertical)
                            .lineLimit(1...5)
                            .lineLimit(3)
                            .lineLimit(2, reservesSpace: true)
                            .truncationMode(.middle)
                        Text("Glass")
                            .glassEffect()
                            .glassEffect(.regular.tint(.blue).interactive(), in: .capsule)
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12))
                            .glassEffectID("glass", in: namespace)
                        GlassEffectContainer(spacing: 8) { Text("A") }
                    }
                    Group {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("\(context.date.timeIntervalSince1970)")
                        }
                        TimelineView(.animation) { _ in Text("Animated") }
                    }
                    Circle()
                        .rotationEffect(.degrees(45), anchor: .center)
                        .blur(radius: 4, opaque: true)
                        .mask { Rectangle() }
                        .mask(alignment: .top) { Rectangle() }
                        .offset(dragOffset)
                        .sensoryFeedback(.selection, trigger: query)
                        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: text)
                        .sensoryFeedback(trigger: query) { _, new in new.isEmpty ? nil : .success }
                        .onTapGesture {}
                        .onTapGesture(count: 2) {}
                        .onLongPressGesture(minimumDuration: 0.3) {
                        } onPressingChanged: { _ in
                        }
                        .gesture(
                            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                                .updating($dragOffset) { value, state, _ in
                                    state = value.translation
                                }
                                .onChanged { _ in }
                                .onEnded { _ in }
                        )
                        .simultaneousGesture(TapGesture(count: 2).onEnded {})
                        .highPriorityGesture(LongPressGesture().onEnded { _ in })
                }
                .tabViewBottomAccessory { Text("Now Playing") }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { Text(accessoryPlacement == .inline ? "Inline" : "Expanded") }
        .opacity(
            reduceMotion || isSearching || environmentEditMode?.wrappedValue.isEditing == true
                ? 0.5 : 1)
    }
}

@MainActor
@Test("The stubs for Rustle's missing SwiftUI API resolve to their content")
func rustleStubsResolve() {
    let host = ViewHost(Stubs())
    #expect(host.root.outline().contains("TabView"))
}

@MainActor
@Test("Lazy stacks and menus resolve to plain nodes")
func lazyStacksOutline() {
    struct Content: View {
        var body: some View {
            VStack {
                LazyVStack { Text("A") }
                Menu("More") { Button("Share") {} }
                ProgressView("Loading")
            }
        }
    }
    let outline = ViewHost(Content()).root.outline()
    #expect(
        outline == """
            Root
            └─ VStack
               ├─ VStack
               │  └─ Text "A"
               ├─ Button menu=true
               │  └─ Text "More"
               └─ Text "Loading"
            """)
}

@Test("MediaPlayer's now-playing and remote command API builds")
func mediaPlayerStubs() {
    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = [
        MPMediaItemPropertyTitle: "Song",
        MPMediaItemPropertyArtist: "Artist",
        MPMediaItemPropertyAlbumTitle: "Album",
        MPMediaItemPropertyPlaybackDuration: 180.0,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: 12.0,
        MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        MPMediaItemPropertyArtwork: MPMediaItemArtwork(boundsSize: CGSize(width: 1, height: 1)) {
            _ in 0
        },
    ]
    center.playbackState = .playing
    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.isEnabled = true
    let token = commands.pauseCommand.addTarget { _ in .success }
    commands.pauseCommand.removeTarget(token)
    commands.changePlaybackPositionCommand.addTarget { event in
        (event as? MPChangePlaybackPositionCommandEvent) == nil ? .commandFailed : .success
    }
    commands.nextTrackCommand.isEnabled = false
    commands.previousTrackCommand.isEnabled = false
    commands.togglePlayPauseCommand.isEnabled = true
    commands.skipForwardCommand.preferredIntervals = [15]
    #expect(center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Song")
}

@Test("AVFAudio's audio session API builds")
func audioSessionStubs() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default, options: [.allowAirPlay])
    try session.setActive(true)
    let names = [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification]
    #expect(names.count == 2)
    let info: [AnyHashable: Any] = [
        AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue,
        AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume
            .rawValue,
        AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable
            .rawValue,
    ]
    #expect(info.count == 3)
    try session.setActive(false, options: .notifyOthersOnDeactivation)
}
