import Foundation
import Testing

@testable import ParhelionUI

// Screens that scroll under the navigation bar and the tab bar, drawn with
// the scroll edge effect. The README shows them.

private struct Song: Identifiable {
    var id: String { title }
    var title: String
    var artist: String
}

private let songs = (1...30).map { Song(title: "Song \($0)", artist: "Artist \($0 % 7 + 1)") }

private struct SongsView: View {
    var style: ScrollEdgeEffectStyle?

    var body: some View {
        NavigationStack {
            List {
                ForEach(songs) { song in
                    VStack(alignment: .leading) {
                        Text(song.title)
                        Text(song.artist).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Songs")
            .navigationBarTitleDisplayMode(.inline)
        }
        .scrollEdgeEffectStyle(style, for: .all)
    }
}

private struct TabbedSongs: View {
    var body: some View {
        TabView {
            Tab("Songs", systemImage: "music.note") { SongsView(style: nil) }
            Tab("Radio", systemImage: "dot.radiowaves.left.and.right") { Text("Radio") }
        }
    }
}

@MainActor
enum ScrollEdgeGallery {
    enum Screen: String, CaseIterable {
        case softLight = "scroll-edge-soft"
        case softDark = "scroll-edge-soft-dark"
        case hardLight = "scroll-edge-hard"
        case hardDark = "scroll-edge-hard-dark"
    }

    static func host(showing screen: Screen) -> ViewHost {
        let host: ViewHost
        switch screen {
        case .softLight, .softDark: host = ViewHost(TabbedSongs(), device: .iPhone16)
        case .hardLight, .hardDark:
            host = ViewHost(SongsView(style: .hard), device: .iPhone16)
        }
        if screen == .softDark || screen == .hardDark { host.colorScheme = .dark }
        let list = host.root.allNodes.first { $0.kind == "List" }
        if let list { try? host.scroll(list.id, to: CGPoint(x: 0, y: 120)) }
        host.advanceTime(by: 2)
        return host
    }

    static func readmeImage(_ screen: Screen) -> Data {
        host(showing: screen).render(scale: 2, chrome: .systemBars).pngData()
    }

    static func readmeImageURL(_ screen: Screen, in directory: URL? = nil) -> URL {
        (directory ?? TasksScreens.repository.appendingPathComponent("docs/images"))
            .appendingPathComponent("\(screen.rawValue).png")
    }
}

@MainActor
@Suite("Scroll edge effect")
struct ScrollEdgeTests {
    private func list(_ host: ViewHost) throws -> ViewNode {
        try #require(host.root.allNodes.first { $0.kind == "List" })
    }

    @Test("A list as the screen fills the stack and starts its content below the bar")
    func listUnderTheBar() throws {
        let host = ViewHost(SongsView(style: nil), device: .iPhone16)
        let list = try list(host)
        let bar = try #require(host.root.allNodes.first { $0.kind == "NavigationBar" })
        #expect(list.frame?.minY == 0)
        #expect(list.frame?.maxY == host.device.screenSize.height)
        // The first row starts below the bar, with the list's own inset.
        let row = try #require(list.allNodes.first { $0.kind == "VStack" }?.frame)
        let barBottom = try #require(bar.frame?.maxY)
        #expect(row.minY >= barBottom && row.minY < barBottom + 60)
        // Nothing lies under the bar until the list scrolls.
        #expect(list.attributes["contentUnderBars"] == nil)
    }

    @Test("Scrolling puts content under the navigation bar")
    func contentUnderTheBar() throws {
        let host = ViewHost(SongsView(style: nil), device: .iPhone16)
        try host.scroll(try list(host).id, to: CGPoint(x: 0, y: 100))
        #expect(try list(host).attributes["contentUnderBars"] == "top")
        let outline = try list(host).outline()
        #expect(outline.contains("contentOffset=0, 100"), "\(outline)")
    }

    @Test("A list under a tab bar has content under both bars while it scrolls")
    func bothBars() throws {
        let host = ViewHost(TabbedSongs(), device: .iPhone16)
        #expect(try list(host).attributes["contentUnderBars"] == "bottom")
        try host.scroll(try list(host).id, to: CGPoint(x: 0, y: 100))
        #expect(try list(host).attributes["contentUnderBars"] == "top,bottom")
        try host.scroll(try list(host).id, to: CGPoint(x: 0, y: 100_000))
        #expect(try list(host).attributes["contentUnderBars"] == "top")
    }

    @Test("A navigation bar's buttons stay tappable over the scrolled list")
    func barButtonsTappable() throws {
        struct Screen: View {
            @State var taps = 0
            var body: some View {
                NavigationStack {
                    List(1...30, id: \.self) { Text("Row \($0)") }
                        .navigationTitle("Taps \(taps)")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Add") { taps += 1 }
                            }
                        }
                }
            }
        }
        let host = ViewHost(Screen(), device: .iPhone16)
        try host.scroll(try list(host).id, to: CGPoint(x: 0, y: 100))
        try host.tapButton(labeled: "Add")
        #expect(host.root.allNodes.contains { $0.text == "Taps 1" })
        let button = try #require(host.root.allNodes.first { $0.label == "Add" }?.frame)
        try host.tap(at: CGPoint(x: button.midX, y: button.midY))
        #expect(host.root.allNodes.contains { $0.text == "Taps 2" })
    }

    @Test("A scroll view in a sheet keeps its content below the bar")
    func sheet() {
        struct Screen: View {
            @State var shown = true
            var body: some View {
                Text("Main").sheet(isPresented: $shown) {
                    NavigationStack {
                        List(1...30, id: \.self) { Text("Row \($0)") }.navigationTitle("Sheet")
                    }
                }
            }
        }
        let host = ViewHost(Screen(), device: .iPhone16)
        let list = host.root.allNodes.first { $0.kind == "List" }
        #expect(list?.frame?.minY ?? 0 > 0)
        #expect(list?.attributes["contentUnderBars"] == nil)
    }

    @Test("scrollEdgeEffectStyle and scrollEdgeEffectHidden are recorded on scroll views")
    func recorded() {
        let host = ViewHost(
            VStack {
                ScrollView { Text("a") }
                    .scrollEdgeEffectStyle(.hard, for: .top)
                ScrollView { Text("b") }
                    .scrollEdgeEffectHidden(true, for: .bottom)
                // The modifier nearest the scroll view wins.
                ScrollView { Text("c") }
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .scrollEdgeEffectStyle(nil, for: .bottom)
                    .scrollEdgeEffectStyle(.hard, for: .bottom)
                    .scrollEdgeEffectHidden(false, for: .top)
            },
            device: .iPhone16)
        let views = host.root.allNodes.filter { $0.kind == "ScrollView" }
        #expect(views.count == 3)
        #expect(views[0].attributes["scrollEdgeEffectTop"] == "hard")
        #expect(views[0].attributes["scrollEdgeEffectBottom"] == nil)
        #expect(views[1].attributes["scrollEdgeEffectBottom"] == "hidden")
        #expect(views[2].attributes["scrollEdgeEffectTop"] == "soft")
        #expect(views[2].attributes["scrollEdgeEffectBottom"] == nil)
        #expect(host.root.outline().contains("scrollEdgeEffectTop=hard"))
    }

    @Test("A style applies to the scroll views inside the view it modifies")
    func environmentReach() {
        let host = ViewHost(
            VStack { ScrollView { Text("a") } }.scrollEdgeEffectStyle(.hard, for: [.top, .bottom]),
            device: .iPhone16)
        let view = host.root.allNodes.first { $0.kind == "ScrollView" }
        #expect(view?.attributes["scrollEdgeEffectTop"] == "hard")
        #expect(view?.attributes["scrollEdgeEffectBottom"] == "hard")
    }

    @Test("contentMargins insets the content, and an inner modifier wins on its edges")
    func contentMargins() throws {
        let host = ViewHost(
            ScrollView { Color.red.frame(height: 100) }
                .contentMargins(.top, 30)
                .contentMargins(.vertical, 20)
                .contentMargins(.horizontal, 10),
            device: .iPhone16)
        let view = try #require(host.root.allNodes.first { $0.kind == "ScrollView" })
        #expect(view.attributes["contentMargins"] == "30, 10, 20, 10")
        let color = try #require(host.root.allNodes.first { $0.kind == "Color" })
        #expect(color.frame?.minY == host.device.safeArea.minY + 30)
        #expect(color.frame?.minX == 10)
        // The margins scroll with the content.
        #expect(view.attributes["contentSize"]?.hasSuffix("× 150") == true)
    }

    @Test("contentMargins for the scroll indicators does not change the content")
    func indicatorMargins() {
        let host = ViewHost(
            ScrollView { Text("a") }.contentMargins(.all, 40, for: .scrollIndicators),
            device: .iPhone16)
        let view = host.root.allNodes.first { $0.kind == "ScrollView" }
        #expect(view?.attributes["contentMargins"] == nil)
    }

    @Test("safeAreaPadding insets a scroll view's content, and pads other views")
    func safeAreaPadding() throws {
        let host = ViewHost(
            VStack {
                ScrollView { Text("a") }.safeAreaPadding(.horizontal, 12)
                Text("b").safeAreaPadding(.top, 5)
            },
            device: .iPhone16)
        let view = try #require(host.root.allNodes.first { $0.kind == "ScrollView" })
        #expect(view.attributes["contentMargins"] == "0, 12, 0, 12")
        let text = try #require(host.root.allNodes.first { $0.text == "b" })
        #expect(
            text.modifiers == [.padding(EdgeInsets(top: 5, leading: 0, bottom: 0, trailing: 0))])
    }

    @Test("ignoresSafeArea reaches the screen's edges where the view meets the safe area")
    func ignoresSafeArea() throws {
        let device = Device.iPhone16
        let all = ViewHost(Color.red.ignoresSafeArea(), device: device)
        let color = try #require(all.root.allNodes.first { $0.kind == "Color" })
        #expect(color.frame == CGRect(origin: .zero, size: device.screenSize))
        #expect(color.attributes["ignoresSafeArea"] == "all")

        let top = ViewHost(Color.red.ignoresSafeArea(edges: .top), device: device)
        let topColor = try #require(top.root.allNodes.first { $0.kind == "Color" })
        #expect(topColor.frame?.minY == 0)
        #expect(topColor.frame?.maxY == device.safeArea.maxY)
        #expect(topColor.attributes["ignoresSafeArea"] == "top")

        let none = ViewHost(Color.red.ignoresSafeArea(.keyboard), device: device)
        let kept = try #require(none.root.allNodes.first { $0.kind == "Color" })
        #expect(kept.frame == device.safeArea)
        #expect(kept.attributes["ignoresSafeArea"] == nil)
    }

    @Test("A root scroll view takes the whole screen and starts its content at the safe area")
    func rootScrollView() throws {
        let device = Device.iPhone16
        let host = ViewHost(ScrollView { Color.red.frame(height: 2000) }, device: device)
        let view = try #require(host.root.allNodes.first { $0.kind == "ScrollView" })
        #expect(view.frame == CGRect(origin: .zero, size: device.screenSize))
        let color = try #require(host.root.allNodes.first { $0.kind == "Color" })
        #expect(color.frame?.minY == device.safeArea.minY)
        // No bar: nothing is under one.
        try host.scroll(view.id, to: CGPoint(x: 0, y: 50))
        #expect(
            host.root.allNodes.first { $0.kind == "ScrollView" }?.attributes["contentUnderBars"]
                == nil)
    }

    // MARK: Drawing

    private func pixel(_ host: ViewHost, _ x: CGFloat, _ y: CGFloat) -> (Int, Int, Int) {
        let color = host.render(scale: 1).color(at: CGPoint(x: x, y: y))
        return (Int(color.red), Int(color.green), Int(color.blue))
    }

    private struct Stripes: View {
        var style: ScrollEdgeEffectStyle?
        var body: some View {
            NavigationStack {
                ScrollView {
                    ForEach(0..<20) { _ in Color.black.frame(height: 40) }
                }
                .navigationTitle("T")
                .navigationBarTitleDisplayMode(.inline)
            }
            .scrollEdgeEffectStyle(style, for: .top)
        }
    }

    @Test("The hard style covers the content under the bar, light and dark")
    func hardCover() throws {
        for scheme in [ColorScheme.light, .dark] {
            let host = ViewHost(Stripes(style: .hard), device: .iPhone16)
            host.colorScheme = scheme
            // At rest nothing is under the bar, and the content is black.
            let rest = pixel(host, 200, 140)
            #expect(rest.0 == 0, "content at rest")
            try host.scroll(
                try #require(host.root.allNodes.first { $0.kind == "ScrollView" }).id,
                to: CGPoint(x: 0, y: 200))
            let covered = pixel(host, 60, 20)
            if scheme == .light {
                // 85% white over black content.
                #expect(covered.0 > 200, "light cover \(covered)")
            } else {
                // 55% black over black content is black.
                #expect(covered.0 < 20, "dark cover \(covered)")
            }
            let below = pixel(host, 60, 140)
            #expect(below.0 == 0, "content below the effect")
        }
    }

    @Test("Hiding the effect leaves the content as it is")
    func hidden() throws {
        let host = ViewHost(
            Stripes(style: .hard).scrollEdgeEffectHidden(true, for: .top), device: .iPhone16)
        try host.scroll(
            try #require(host.root.allNodes.first { $0.kind == "ScrollView" }).id,
            to: CGPoint(x: 0, y: 200))
        // The bar's glass is not at x 60, so the content shows.
        #expect(pixel(host, 200, 20).0 == 0)
    }

    @Test("The soft style blurs the content under the bar and fades out toward the content")
    func softFade() throws {
        // Alternating stripes, so that a blur changes the pixels.
        struct Alternating: View {
            var body: some View {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(0..<40) { index in
                                (index % 2 == 0 ? Color.black : Color.white).frame(height: 20)
                            }
                        }
                    }
                    .navigationTitle("T")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        let host = ViewHost(Alternating(), device: .iPhone16)
        let id = try #require(host.root.allNodes.first { $0.kind == "ScrollView" }).id
        try host.scroll(id, to: CGPoint(x: 0, y: 200))
        let frame = host.render(scale: 1)
        let top = frame.color(at: CGPoint(x: 20, y: 2)).red
        // Neither pure stripe color: the blur mixed them.
        #expect(top > 20 && top < 235, "top \(top)")
        // Below the effect the stripes are untouched.
        let below = (110...130).map { frame.color(at: CGPoint(x: 20, y: $0)).red }
        #expect(below.contains(0) && below.contains(255), "\(below)")
        // Without content under the bar, nothing is drawn.
        try host.scroll(id, to: .zero)
        let rest = host.render(scale: 1)
        #expect(
            rest.color(at: CGPoint(x: 20, y: 105)).red == 0
                || rest.color(at: CGPoint(x: 20, y: 105)).red == 255)
    }

    @Test("A frame drawn through the cache matches one drawn from scratch")
    func cacheMatches() throws {
        let host = ViewHost(TabbedSongs(), device: .iPhone16)
        let id = try list(host).id
        for offset in [0.0, 60, 61, 61, 61, 200] {
            try host.scroll(id, to: CGPoint(x: 0, y: offset))
            let cached = host.render(scale: 2).pixels
            let scratch = TreeRenderer(device: host.device).render(host.presentedRoot, scale: 2)
                .pixels
            #expect(cached == scratch, "offset \(offset)")
        }
        #expect(host.renderCache.glassReuses > 0)
    }

    // MARK: Gallery

    @Test(
        "The README's scroll edge images match a fresh render",
        arguments: ScrollEdgeGallery.Screen.allCases)
    func readmeImages(_ screen: ScrollEdgeGallery.Screen) throws {
        let committed = try Data(contentsOf: ScrollEdgeGallery.readmeImageURL(screen))
        #expect(ScrollEdgeGallery.readmeImage(screen) == committed)
    }

    @Test(
        "Write the README's scroll edge images",
        .enabled(if: ProcessInfo.processInfo.environment["PARHELION_README_IMAGES"] != nil)
    )
    func writeReadmeImages() throws {
        let path = ProcessInfo.processInfo.environment["PARHELION_README_IMAGES"] ?? ""
        let directory = URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        for screen in ScrollEdgeGallery.Screen.allCases {
            try ScrollEdgeGallery.readmeImage(screen).write(
                to: ScrollEdgeGallery.readmeImageURL(screen, in: directory))
        }
    }
}
