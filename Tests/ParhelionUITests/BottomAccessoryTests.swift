import Foundation
import Testing

@testable import ParhelionUI

// A tab view with a bottom accessory above its bar, and a bar that
// minimizes while the content scrolls down. Sizes are the iOS 27 UI Kit's
// where it gives them, and assumed otherwise; see LayoutDefaults.

private struct Track: Identifiable {
    var id: Int
    var title: String { "Track \(id)" }
}

private let tracks = (1...40).map { Track(id: $0) }

private struct AccessoryLabel: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Text(placement == .inline ? "Inline" : placement == .expanded ? "Expanded" : "None")
    }
}

private struct PlayerTabs: View {
    var behavior: TabBarMinimizeBehavior = .onScrollDown
    var hasAccessory = true

    var body: some View {
        TabView {
            Tab("Collection", systemImage: "square.grid.2x2") {
                NavigationStack {
                    List(tracks) { track in Text(track.title) }
                        .navigationTitle("Collection")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            Tab("Library", systemImage: "books.vertical") { Text("Library") }
            Tab(role: .search) { Text("Search") }
        }
        .tabBarMinimizeBehavior(behavior)
        .tabViewBottomAccessory(isEnabled: hasAccessory) { AccessoryLabel() }
    }
}

@MainActor
@Suite("Tab view bottom accessory")
struct BottomAccessoryTests {
    private func host(_ view: PlayerTabs = PlayerTabs()) -> ViewHost {
        ViewHost(view, device: .iPhone18ProMax)
    }

    private func node(_ kind: String, in host: ViewHost) throws -> ViewNode {
        try #require(host.root.allNodes.first { $0.kind == kind })
    }

    private func frame(_ kind: String, in host: ViewHost) throws -> CGRect {
        try #require(try node(kind, in: host).frame)
    }

    private func scrollList(_ host: ViewHost, by delta: CGFloat) throws {
        let list = try node("List", in: host)
        let offset = host.scrollOffset(of: list.id) ?? .zero
        try host.scroll(list.id, to: CGPoint(x: 0, y: offset.y + delta))
        host.advanceTime(by: 1)
    }

    @Test("An open tab bar has the accessory's capsule above it")
    func openLayout() throws {
        let host = host()
        let bar = try frame("TabBar", in: host)
        let accessory = try frame("TabViewBottomAccessory", in: host)
        #expect(bar == CGRect(x: 21, y: 873, width: 398, height: 62))
        #expect(accessory == CGRect(x: 21, y: 817, width: 398, height: 48))
        #expect(accessory.maxY <= bar.minY)
        #expect(try node("TabViewBottomAccessory", in: host).attributes["placement"] == "expanded")
        #expect(host.root.allNodes.contains { $0.text == "Expanded" })
    }

    @Test("The accessory's content is inside its capsule")
    func contentInCapsule() throws {
        let host = host()
        let accessory = try frame("TabViewBottomAccessory", in: host)
        let text = try #require(host.root.allNodes.first { $0.text == "Expanded" }?.frame)
        #expect(accessory.insetBy(dx: 16, dy: 0).contains(text))
    }

    @Test("Scrolling down minimizes the bar and moves the accessory next to it")
    func minimizedLayout() throws {
        let host = host()
        try scrollList(host, by: 300)
        let bar = try frame("TabBar", in: host)
        let accessory = try frame("TabViewBottomAccessory", in: host)
        #expect(bar == CGRect(x: 21, y: 887, width: 64, height: 48))
        #expect(accessory == CGRect(x: 93, y: 887, width: 326, height: 48))
        #expect(bar.midY == accessory.midY)
        #expect(try node("TabViewBottomAccessory", in: host).attributes["placement"] == "inline")
        #expect(host.root.allNodes.contains { $0.text == "Inline" })
        // Only the selected tab's symbol remains in the small capsule.
        let bars = try node("TabBar", in: host)
        #expect(bars.children.count == 1)
        #expect(bars.children[0].children.map(\.kind) == ["Image"])
    }

    @Test("Scrolling up, or back to the top, restores the bar")
    func restores() throws {
        let host = host()
        try scrollList(host, by: 300)
        #expect(try frame("TabBar", in: host).width == 64)
        try scrollList(host, by: -40)
        #expect(try frame("TabBar", in: host).width == 398)
        #expect(try frame("TabViewBottomAccessory", in: host).minY == 817)

        try scrollList(host, by: 200)
        #expect(try frame("TabBar", in: host).width == 64)
        let list = try node("List", in: host)
        try host.scroll(list.id, to: .zero)
        #expect(try frame("TabBar", in: host).width == 398)
    }

    @Test("A mouse wheel minimizes the bar, and a tap on it brings it back")
    func wheelAndTap() throws {
        let host = host()
        #expect(host.scroll(by: CGSize(width: 0, height: 200), at: CGPoint(x: 200, y: 400)))
        let bar = try node("TabBar", in: host)
        #expect(bar.frame?.width == 64)
        try host.tap(bar.children[0].id)
        host.advanceTime(by: 1)
        #expect(try frame("TabBar", in: host).width == 398)
        #expect(try node("TabViewBottomAccessory", in: host).attributes["placement"] == "expanded")
    }

    @Test("The minimized bar and the accessory animate")
    func animates() throws {
        let host = host()
        _ = host.root
        let list = try node("List", in: host)
        try host.scroll(list.id, to: CGPoint(x: 0, y: 300))
        // The tree has its final frames, and what is drawn is on its way.
        #expect(try frame("TabBar", in: host).width == 64)
        #expect(host.isAnimating)
        host.advanceTime(by: 1)
        #expect(!host.isAnimating)
    }

    @Test("onScrollUp minimizes the bar when the content scrolls up")
    func onScrollUp() throws {
        let host = host(PlayerTabs(behavior: .onScrollUp))
        try scrollList(host, by: 300)
        #expect(try frame("TabBar", in: host).width == 398)
        try scrollList(host, by: -50)
        #expect(try frame("TabBar", in: host).width == 64)
        try scrollList(host, by: 50)
        #expect(try frame("TabBar", in: host).width == 398)
    }

    @Test("Automatic and never keep the bar open")
    func neverMinimizes() throws {
        for behavior in [TabBarMinimizeBehavior.automatic, .never] {
            let host = host(PlayerTabs(behavior: behavior))
            try scrollList(host, by: 300)
            #expect(try frame("TabBar", in: host).width == 398)
            #expect(try node("TabView", in: host).attributes["tabBarMinimizeBehavior"] == nil)
        }
    }

    @Test("Without an accessory, the bar minimizes alone")
    func noAccessory() throws {
        let host = host(PlayerTabs(hasAccessory: false))
        #expect(!host.root.allNodes.contains { $0.kind == "TabViewBottomAccessory" })
        try scrollList(host, by: 300)
        #expect(try frame("TabBar", in: host) == CGRect(x: 21, y: 887, width: 64, height: 48))
    }

    @Test("A scrolling list ends above the accessory")
    func listEndsAboveAccessory() throws {
        let host = host(PlayerTabs(behavior: .never))
        let list = try node("List", in: host)
        let metrics = host.scrollOffset(of: list.id)
        #expect(metrics != nil)
        try host.scroll(list.id, to: CGPoint(x: 0, y: 100_000))
        let last = try #require(
            host.root.allNodes.last { $0.text == "Track 40" }?.frame)
        #expect(last.maxY <= 817)
    }

    @Test("Scrolling to the end minimizes the bar and keeps it minimized")
    func minimizesAtEnd() throws {
        for hasAccessory in [true, false] {
            let host = host(PlayerTabs(hasAccessory: hasAccessory))
            let list = try node("List", in: host)
            try host.scroll(list.id, to: CGPoint(x: 0, y: 100_000))
            host.advanceTime(by: 1)
            #expect(try frame("TabBar", in: host).width == 64)
            let offset = try #require(host.scrollOffset(of: list.id))
            try host.scroll(list.id, to: CGPoint(x: 0, y: 100_000))
            host.advanceTime(by: 1)
            #expect(try frame("TabBar", in: host).width == 64)
            #expect(host.scrollOffset(of: list.id) == offset)
        }
    }

    @Test("The outline names the accessory, its placement, and the minimize behavior")
    func outline() {
        let host = host()
        let outline = host.root.outline()
        #expect(outline.contains("TabViewBottomAccessory"), "\(outline)")
        #expect(outline.contains("placement=expanded"), "\(outline)")
        #expect(outline.contains("tabBarMinimizeBehavior=onScrollDown"), "\(outline)")
    }

    @Test("The placement is nil outside an accessory")
    func placementOutside() {
        struct Reader: View {
            @Environment(\.tabViewBottomAccessoryPlacement) var placement
            var body: some View { Text(placement == nil ? "nil" : "set") }
        }
        let host = ViewHost(Reader())
        #expect(host.root.allNodes.contains { $0.text == "nil" })
    }

    @Test("Both layouts render")
    func render() throws {
        let host = host()
        let open = host.render(scale: 2, chrome: .systemBars).pngData()
        try scrollList(host, by: 300)
        let minimized = host.render(scale: 2, chrome: .systemBars).pngData()
        #expect(open != minimized)
        if let directory = ProcessInfo.processInfo.environment["PARHELION_ACCESSORY_PNG_DIR"] {
            let url = URL(fileURLWithPath: directory)
            try open.write(to: url.appendingPathComponent("tab-accessory-open.png"))
            try minimized.write(to: url.appendingPathComponent("tab-accessory-minimized.png"))
        }
    }
}
