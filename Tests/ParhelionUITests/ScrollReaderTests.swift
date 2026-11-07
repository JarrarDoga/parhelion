import Foundation
import Testing

@testable import ParhelionUI

/// A 200 × 200 screen with no safe-area insets.
private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 200, height: 200),
    safeAreaInsets: EdgeInsets()
)

/// Whether two positions are the same, allowing for rounding in layout.
private func near(_ value: CGFloat?, _ expected: CGFloat) -> Bool {
    guard let value else { return false }
    return abs(value - expected) < 0.01
}

@MainActor
private func scrollViewID(_ host: ViewHost) throws -> NodeID {
    try #require(host.root.allNodes.first { $0.kind == "ScrollView" }).id
}

/// A list of 20-point rows, as `rowCount` identified rows in a `VStack`.
private struct JumpList: View {
    var rowCount = 1_535
    var lazy = false
    @State private var shown = ""

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack {
                    Button("Top") { proxy.scrollTo(0, anchor: .top) }
                    Button("Jump") { proxy.scrollTo(1_240, anchor: .top) }
                    Button("Center") { proxy.scrollTo(1_240, anchor: .center) }
                    Button("Show") { proxy.scrollTo(1_240) }
                    Button("Animate") {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(1_000, anchor: .top)
                        }
                    }
                    Button("Mark") {
                        shown = "marked"
                        proxy.scrollTo(900, anchor: .top)
                    }
                    Button("Missing") { proxy.scrollTo("nothing") }
                }
                .frame(height: 44)
                ScrollView {
                    if lazy {
                        LazyVStack(spacing: 0) { rows }
                    } else {
                        VStack(spacing: 0) { rows }
                    }
                }
                Text(shown)
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(0..<rowCount) { index in
            Color.red.frame(height: 20)
        }
    }
}

/// The height of the scroll view in `JumpList`: the screen less the button
/// row and the text.
@MainActor
private func visibleHeight(_ host: ViewHost) throws -> CGFloat {
    try #require(host.root.node(withID: try scrollViewID(host))?.frame?.height)
}

@MainActor
@Suite("ScrollViewReader")
struct ScrollViewReaderTests {
    @Test("A reader is invisible in the tree, and id(_:) records the identifier")
    func outline() {
        let host = ViewHost(
            ScrollViewReader { _ in
                VStack {
                    Text("A").id(1)
                    Text("B").id("two")
                }
            },
            device: square)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "A" viewID=Int:1
                   └─ Text "B" viewID=String:two
                """)
    }

    @Test("scrollTo scrolls a 1,535-row list to a row and puts it at the anchor")
    func jump() throws {
        let host = ViewHost(JumpList(), device: square)
        let id = try scrollViewID(host)
        #expect(host.scrollOffset(of: id) == .zero)
        try host.tapButton(labeled: "Jump")
        let top = try #require(host.scrollOffset(of: id))
        #expect(near(top.y, 1_240 * 20))
        let node = try #require(host.root.node(withID: id))
        #expect(node.attributes["contentSize"] == "200 × 30700")
        // The row is at the top of the scroll view, under the button row.
        let row = node.children[0].children[1_240]
        #expect(near(row.frame?.minY, try #require(node.frame?.minY)))

        let height = try visibleHeight(host)
        try host.tapButton(labeled: "Center")
        #expect(near(host.scrollOffset(of: id)?.y, 1_240 * 20 + 10 - height / 2))

        try host.tapButton(labeled: "Top")
        #expect(host.scrollOffset(of: id) == .zero)
    }

    @Test("Without an anchor, scrollTo scrolls by the least that shows the row")
    func minimal() throws {
        let host = ViewHost(JumpList(), device: square)
        let id = try scrollViewID(host)
        let height = try visibleHeight(host)
        try host.tapButton(labeled: "Show")
        // Scrolling down, the row ends at the bottom of the visible region.
        #expect(near(host.scrollOffset(of: id)?.y, 1_241 * 20 - height))
        // It is visible now, so the same call does not move it.
        try host.tapButton(labeled: "Show")
        #expect(near(host.scrollOffset(of: id)?.y, 1_241 * 20 - height))
    }

    @Test("An identifier nobody has changes nothing")
    func missing() throws {
        let host = ViewHost(JumpList(rowCount: 50), device: square)
        let id = try scrollViewID(host)
        try host.tapButton(labeled: "Missing")
        #expect(host.scrollOffset(of: id) == .zero)
    }

    @Test("A scroll sees the changes made in the same action")
    func sameAction() throws {
        let host = ViewHost(JumpList(rowCount: 1_000), device: square)
        let id = try scrollViewID(host)
        try host.tapButton(labeled: "Mark")
        #expect(near(host.scrollOffset(of: id)?.y, 900 * 20))
        #expect(host.nodes(withText: "marked").count == 1)
    }

    @Test("scrollTo inside withAnimation animates the content")
    func animated() throws {
        let host = ViewHost(JumpList(rowCount: 1_500), device: square)
        let id = try scrollViewID(host)
        try host.tapButton(labeled: "Animate")
        #expect(near(host.scrollOffset(of: id)?.y, 1_000 * 20))
        #expect(host.isAnimating)
        let first = try #require(host.presentedRoot.node(withID: id)?.children[0].frame?.minY)
        host.advanceTime(by: 1)
        #expect(!host.isAnimating)
        let last = try #require(host.presentedRoot.node(withID: id)?.children[0].frame?.minY)
        #expect(first != last)
        let origin = try #require(host.presentedRoot.node(withID: id)?.frame?.minY)
        #expect(near(last, origin - 1_000 * 20))
    }

    @Test("Lazy rows scroll the same way")
    func lazyRows() throws {
        let host = ViewHost(JumpList(lazy: true), device: square)
        let id = try scrollViewID(host)
        try host.tapButton(labeled: "Jump")
        #expect(near(host.scrollOffset(of: id)?.y, 1_240 * 20))
        // The row did not exist before the jump; now it does, at the top.
        let stack = try #require(host.root.allNodes.first { $0.kind == "LazyVStack" })
        let resolved = try #require(stack.attributes["lazyResolved"])
        let bounds = resolved.split(separator: ".").compactMap { Int($0.replacing("<", with: "")) }
        #expect(bounds.count == 2 && bounds[0] <= 1_240 && 1_240 < bounds[1])
        let height = try visibleHeight(host)
        try host.tapButton(labeled: "Center")
        #expect(near(host.scrollOffset(of: id)?.y, 1_240 * 20 + 10 - height / 2))
        try host.tapButton(labeled: "Top")
        #expect(near(host.scrollOffset(of: id)?.y, 0))
        try host.tapButton(labeled: "Show")
        #expect(near(host.scrollOffset(of: id)?.y, 1_241 * 20 - height))
    }

    @Test("A lazy list scrolls to a row whose height was estimated wrong")
    func lazyListEstimate() throws {
        struct Rows: View {
            var body: some View {
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        Button("Jump") { proxy.scrollTo(1_240, anchor: .top) }
                        Button("Near") { proxy.scrollTo(30, anchor: .top) }
                        List(0..<1_535, id: \.self) { index in
                            // The first rows are short, so the estimate of the
                            // rows not yet made is too short.
                            Text("Row \(index)").frame(height: index < 60 ? 20 : 80)
                        }
                    }
                }
            }
        }
        let host = ViewHost(Rows(), device: square)
        let list = try #require(host.root.allNodes.first { $0.kind == "List" })
        let top = try #require(list.frame?.minY)
        try host.tapButton(labeled: "Near")
        let near = try #require(host.root.allNodes.first { $0.text == "Row 30" })
        #expect(abs((near.listRowFrame?.minY ?? 0) - top) < 1)
        try host.tapButton(labeled: "Jump")
        let row = try #require(host.root.allNodes.first { $0.text == "Row 1240" })
        let cell = try #require(row.listRowFrame)
        #expect(abs(cell.minY - top) < 1)
    }

    @Test("A lazy stack reports the row at the start after a drag")
    func lazyReadBack() throws {
        let host = ViewHost(
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<1_535, id: \.self) { Color.red.frame(height: 20).id("row\($0)") }
                }
            }, device: square)
        let id = try scrollViewID(host)
        try host.scroll(id, to: CGPoint(x: 0, y: 1_240 * 20))
        host.drag(from: CGPoint(x: 100, y: 150), to: CGPoint(x: 100, y: 50), duration: 1)
        host.advanceTime(by: 2)
        let offset = try #require(host.scrollOffset(of: id)?.y)
        #expect(offset > 1_240 * 20)
        #expect(
            host.scrollPositionID(of: id) == AnyHashable("row\(Int((offset / 20).rounded(.down)))"))
    }

    @Test("The host scrolls to a view by its identifier")
    func hostScroll() throws {
        let host = ViewHost(
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<100) { index in
                        Color.red.frame(height: 50).id("row\(index)")
                    }
                }
            },
            device: square)
        let id = try scrollViewID(host)
        host.scroll(toViewID: "row40", anchor: .top)
        #expect(near(host.scrollOffset(of: id)?.y, 2_000))
        #expect(host.scrollPositionID(of: id) == AnyHashable("row40"))
    }

    @Test("A different id gives a view new state")
    func identity() throws {
        struct Counter: View {
            @State private var count = 0
            var body: some View {
                Button("Count \(count)") { count += 1 }
            }
        }
        struct Root: View {
            @State private var generation = 0
            var body: some View {
                VStack {
                    Counter().id(generation)
                    Button("New") { generation += 1 }
                }
            }
        }
        let host = ViewHost(Root(), device: square)
        try host.tapButton(labeled: "Count 0")
        #expect(host.nodes(withText: "Count 1").count == 1)
        try host.tapButton(labeled: "New")
        #expect(host.nodes(withText: "Count 0").count == 1)
    }
}

// MARK: - scrollPosition

private struct PositionList: View {
    @State private var scrolledID: Int?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Go 500") { scrolledID = 500 }
                Button("Go 3") { scrolledID = 3 }
            }
            .frame(height: 44)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<1_000) { index in
                        Color.blue.frame(height: 20).id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrolledID)
            Text("At \(scrolledID.map(String.init) ?? "nil")")
        }
    }
}

@MainActor
@Suite("scrollPosition")
struct ScrollPositionTests {
    @Test("The id binding follows a drag, and setting it scrolls")
    func bothDirections() throws {
        let host = ViewHost(PositionList(), device: square)
        let id = try scrollViewID(host)
        #expect(host.nodes(withText: "At nil").count == 1)

        // Dragging up by 205 points moves 205 points of content past the top.
        host.pointerDown(at: CGPoint(x: 100, y: 150))
        host.pointerMoved(to: CGPoint(x: 100, y: 100))
        host.pointerMoved(to: CGPoint(x: 100, y: -55))
        host.advanceTime(by: 1)
        host.pointerUp(at: CGPoint(x: 100, y: -55))
        host.update()
        #expect(near(host.scrollOffset(of: id)?.y, 205))
        // Row 10 spans 200...220: its end is past the top of the view.
        #expect(host.nodes(withText: "At 10").count == 1)

        try host.tapButton(labeled: "Go 500")
        #expect(near(host.scrollOffset(of: id)?.y, 10_000))
        #expect(host.nodes(withText: "At 500").count == 1)

        try host.tapButton(labeled: "Go 3")
        #expect(near(host.scrollOffset(of: id)?.y, 60))
        #expect(host.nodes(withText: "At 3").count == 1)
    }

    @Test("The binding can start with a value, and scrolls there")
    func initialValue() throws {
        struct Start: View {
            @State private var position: Int? = 30
            var body: some View {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<100) { index in Color.blue.frame(height: 20) }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $position, anchor: .top)
            }
        }
        let host = ViewHost(Start(), device: square)
        #expect(host.scrollOffset(of: try scrollViewID(host))?.y == 600)
    }

    @Test("A ScrollPosition value scrolls to an edge, a point, and a view")
    func positionValue() throws {
        struct Positioned: View {
            @State private var position = ScrollPosition()
            var body: some View {
                VStack(spacing: 0) {
                    HStack {
                        Button("Bottom") { position.scrollTo(edge: .bottom) }
                        Button("Point") { position.scrollTo(point: CGPoint(x: 0, y: 70)) }
                        Button("Row") { position.scrollTo(id: 8, anchor: .top) }
                        Button("Y") { position.scrollTo(y: 30) }
                    }
                    .frame(height: 44)
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(0..<50) { index in Color.blue.frame(height: 20) }
                        }
                    }
                    .scrollPosition($position)
                    Text(position.point.map { "Point \($0.y)" } ?? "No point")
                }
            }
        }
        let host = ViewHost(Positioned(), device: square)
        let id = try scrollViewID(host)
        let height = try visibleHeight(host)
        try host.tapButton(labeled: "Bottom")
        #expect(near(host.scrollOffset(of: id)?.y, 50 * 20 - height))
        try host.tapButton(labeled: "Point")
        #expect(near(host.scrollOffset(of: id)?.y, 70))
        try host.tapButton(labeled: "Row")
        #expect(near(host.scrollOffset(of: id)?.y, 160))
        try host.tapButton(labeled: "Y")
        #expect(near(host.scrollOffset(of: id)?.y, 30))

        // A drag writes the offset back, as positioned by the user.
        host.pointerDown(at: CGPoint(x: 100, y: 150))
        host.pointerMoved(to: CGPoint(x: 100, y: 100))
        host.pointerMoved(to: CGPoint(x: 100, y: 70))
        host.advanceTime(by: 1)
        host.pointerUp(at: CGPoint(x: 100, y: 70))
        host.update()
        #expect(near(host.scrollOffset(of: id)?.y, 110))
        #expect(host.nodes(withText: "Point 110.0").count == 1)
    }

    @Test("scrollTargetLayout records itself, and can be turned off")
    func targetLayoutOutline() {
        let host = ViewHost(
            ScrollView {
                VStack {
                    Text("A")
                }
                .scrollTargetLayout()
                VStack {
                    Text("B")
                }
                .scrollTargetLayout(isEnabled: false)
            },
            device: square)
        let outline = host.root.outline()
        #expect(outline.contains("VStack scrollTargetLayout=true"))
        #expect(outline.components(separatedBy: "scrollTargetLayout").count == 2)
    }
}

// MARK: - Geometry

@MainActor
private final class GeometryLog {
    var values: [CGFloat] = []
    var geometry: ScrollGeometry?
}

@MainActor
@Suite("onScrollGeometryChange")
struct ScrollGeometryTests {
    @Test("The action sees the geometry, and the scrubber thumb follows the list")
    func thumbFollowsList() throws {
        let log = GeometryLog()
        struct Scrubbed: View {
            let log: GeometryLog
            @State private var fraction = 0.0
            var body: some View {
                VStack {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(0..<100) { index in Color.blue.frame(height: 20) }
                        }
                    }
                    .onScrollGeometryChange(for: ScrollGeometry.self) {
                        $0
                    } action: { _, new in
                        log.geometry = new
                        let range = new.contentSize.height - new.containerSize.height
                        fraction = range > 0 ? Double(new.contentOffset.y / range) : 0
                    }
                    Text("Thumb \(Int((fraction * 100).rounded()))")
                }
            }
        }
        let host = ViewHost(Scrubbed(log: log), device: square)
        let id = try scrollViewID(host)
        // It runs once when the view appears.
        let first = try #require(log.geometry)
        #expect(first.contentSize == CGSize(width: 200, height: 2_000))
        #expect(first.containerSize.width == 200)
        #expect(first.contentOffset == .zero)
        #expect(host.nodes(withText: "Thumb 0").count == 1)

        let height = first.containerSize.height
        let range = 2_000 - height
        try host.scroll(id, to: CGPoint(x: 0, y: range / 2))
        host.update()
        #expect(log.geometry?.contentOffset.y == range / 2)
        #expect(host.nodes(withText: "Thumb 50").count == 1)

        try host.scroll(id, to: CGPoint(x: 0, y: 1_000_000))
        host.update()
        #expect(host.nodes(withText: "Thumb 100").count == 1)
        #expect(log.geometry?.visibleRect.maxY == 2_000)
    }

    @Test("The action runs only when the transformed value changes")
    func onlyOnChange() throws {
        let log = GeometryLog()
        let host = ViewHost(
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<100) { index in Color.blue.frame(height: 20) }
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentOffset.y > 100 ? 1 : 0
            } action: {
                old, new in
                log.values.append(new - old)
                log.values.append(new)
            },
            device: square)
        let id = try scrollViewID(host)
        #expect(log.values == [0, 0])
        try host.scroll(id, to: CGPoint(x: 0, y: 50))
        #expect(log.values == [0, 0])
        try host.scroll(id, to: CGPoint(x: 0, y: 150))
        #expect(log.values == [0, 0, 1, 1])
        try host.scroll(id, to: CGPoint(x: 0, y: 160))
        #expect(log.values == [0, 0, 1, 1])
    }

    @Test("A scroll view below the safe area has a negative offset at rest")
    func insets() throws {
        let log = GeometryLog()
        let host = ViewHost(
            ScrollView {
                Color.blue.frame(height: 2_000)
            }
            .onScrollGeometryChange(for: ScrollGeometry.self) {
                $0
            } action: { _, new in
                log.geometry = new
            })
        _ = host
        let geometry = try #require(log.geometry)
        #expect(geometry.contentInsets.top > 0)
        #expect(geometry.contentOffset.y == -geometry.contentInsets.top)
    }
}

// MARK: - Settling

private struct Covers: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(0..<3) { index in
                    Color.red.frame(width: 200, height: 200)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
    }
}

@MainActor
@Suite("scrollTargetBehavior")
struct ScrollTargetBehaviorTests {
    private func swipe(
        _ host: ViewHost, left: Bool, distance: CGFloat = 150, duration: Double = 0.2
    ) {
        let start = CGPoint(x: left ? 180 : 20, y: 100)
        host.drag(
            from: start, to: CGPoint(x: start.x + (left ? -distance : distance), y: 100),
            duration: duration)
    }

    @Test("The behavior is recorded on the scroll view")
    func outline() {
        let host = ViewHost(Covers(), device: square)
        let outline = host.root.outline()
        #expect(outline.contains("ScrollView axes=horizontal"))
        #expect(outline.contains("scrollTargetBehavior=paging"))
        #expect(outline.contains("HStack scrollTargetLayout=true"))

        let aligned = ViewHost(
            ScrollView { Text("A") }.scrollTargetBehavior(.viewAligned(limitBehavior: .always)),
            device: square)
        #expect(aligned.root.outline().contains("scrollTargetBehavior=viewAligned(always)"))
    }

    @Test("One swipe each pages between three covers")
    func pagesBetweenCovers() throws {
        let host = ViewHost(Covers(), device: square)
        let id = try scrollViewID(host)
        swipe(host, left: true)
        #expect(host.scrollOffset(of: id) == CGPoint(x: 200, y: 0))
        swipe(host, left: true)
        #expect(host.scrollOffset(of: id) == CGPoint(x: 400, y: 0))
        // There is no fourth cover.
        swipe(host, left: true)
        #expect(host.scrollOffset(of: id) == CGPoint(x: 400, y: 0))
        swipe(host, left: false)
        #expect(host.scrollOffset(of: id) == CGPoint(x: 200, y: 0))
        swipe(host, left: false)
        #expect(host.scrollOffset(of: id) == .zero)
    }

    @Test("A slow, short drag springs back to the page")
    func springBack() throws {
        let host = ViewHost(Covers(), device: square)
        let id = try scrollViewID(host)
        swipe(host, left: true, distance: 60, duration: 2)
        #expect(host.scrollOffset(of: id) == .zero)
        // Past half a page, even slowly, turns the page.
        swipe(host, left: true, distance: 120, duration: 4)
        #expect(host.scrollOffset(of: id) == CGPoint(x: 200, y: 0))
    }

    @Test("A fast fling pages one cover and no more")
    func oneAtATime() throws {
        let host = ViewHost(Covers(), device: square)
        let id = try scrollViewID(host)
        swipe(host, left: true, distance: 180, duration: 0.05)
        #expect(host.scrollOffset(of: id) == CGPoint(x: 200, y: 0))
        host.advanceTime(by: 2)
        #expect(host.scrollOffset(of: id) == CGPoint(x: 200, y: 0))
    }

    @Test("The id binding follows the page")
    func pageBinding() throws {
        struct Pager: View {
            @State private var page: Int?
            var body: some View {
                VStack(spacing: 0) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(0..<3) { index in
                                Color.red.frame(width: 200, height: 180).id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $page)
                    Text("Page \(page.map(String.init) ?? "nil")")
                }
            }
        }
        let host = ViewHost(Pager(), device: square)
        swipe(host, left: true)
        host.update()
        #expect(host.nodes(withText: "Page 1").count == 1)
        swipe(host, left: true)
        host.update()
        #expect(host.nodes(withText: "Page 2").count == 1)
        swipe(host, left: false)
        host.update()
        #expect(host.nodes(withText: "Page 1").count == 1)
    }

    @Test("Paging works on a vertical scroll view")
    func verticalPaging() throws {
        let host = ViewHost(
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<3) { index in Color.green.frame(height: 200) }
                }
            }
            .scrollTargetBehavior(.paging),
            device: square)
        let id = try scrollViewID(host)
        host.drag(from: CGPoint(x: 100, y: 180), to: CGPoint(x: 100, y: 30), duration: 0.2)
        #expect(host.scrollOffset(of: id) == CGPoint(x: 0, y: 200))
    }

    @Test("View alignment settles on the start of a view")
    func viewAligned() throws {
        let host = ViewHost(
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(0..<8) { index in
                        Color.orange.frame(width: 120, height: 200).id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned),
            device: square)
        let id = try scrollViewID(host)
        // A short slow drag lands on the nearest view.
        host.drag(from: CGPoint(x: 150, y: 100), to: CGPoint(x: 70, y: 100), duration: 3)
        #expect(host.scrollOffset(of: id) == CGPoint(x: 130, y: 0))
        // A fast swipe passes one view on a horizontal scroll view.
        host.drag(from: CGPoint(x: 190, y: 100), to: CGPoint(x: 10, y: 100), duration: 0.1)
        #expect(host.scrollOffset(of: id) == CGPoint(x: 260, y: 0))
    }

    @Test("Without a limit, a fling can pass several views")
    func viewAlignedNever() throws {
        let host = ViewHost(
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(0..<30) { index in
                        Color.orange.frame(width: 120, height: 200).id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never)),
            device: square)
        let id = try scrollViewID(host)
        host.drag(from: CGPoint(x: 190, y: 100), to: CGPoint(x: 10, y: 100), duration: 0.1)
        let x = try #require(host.scrollOffset(of: id)?.x)
        #expect(x > 260)
        #expect(x.truncatingRemainder(dividingBy: 130) == 0)
    }
}
