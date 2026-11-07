import Foundation
import Testing

@testable import ParhelionUI

/// A 300 × 400 screen with no safe area.
private let screen = Device(
    name: "Test", screenSize: CGSize(width: 300, height: 400), safeAreaInsets: EdgeInsets())

/// A red square that a button moves from the top leading corner to the bottom
/// trailing corner, as two different views that share one identifier.
private struct Moving: View {
    @Namespace private var space
    @State private var isAtEnd = false

    var body: some View {
        VStack {
            ZStack(alignment: isAtEnd ? .bottomTrailing : .topLeading) {
                Color.clear
                if isAtEnd {
                    Color.red.frame(width: 100, height: 100)
                        .matchedGeometryEffect(id: "box", in: space)
                } else {
                    Color.red.frame(width: 40, height: 40)
                        .matchedGeometryEffect(id: "box", in: space)
                }
            }
            .frame(width: 300, height: 300)
            Button("Move") { withAnimation(.linear(duration: 1)) { isAtEnd.toggle() } }
        }
    }
}

/// A grid cell that opens a full-screen cover which zooms from it.
private struct ZoomCover: View {
    @Namespace private var space
    @State private var isOpen = false

    var body: some View {
        VStack {
            Button("Open") { isOpen = true }
                .frame(width: 60, height: 60)
                .matchedTransitionSource(id: "cell", in: space)
            Spacer()
        }
        .fullScreenCover(isPresented: $isOpen) {
            VStack {
                Text("Detail")
                Button("Close") { isOpen = false }
            }
            .navigationTransition(.zoom(sourceID: "cell", in: space))
        }
    }
}

private struct ZoomPush: View {
    @Namespace private var space

    var body: some View {
        NavigationStack {
            VStack {
                NavigationLink("Row") {
                    Text("Detail").navigationTransition(.zoom(sourceID: "row", in: space))
                }
                .matchedTransitionSource(id: "row", in: space)
                Spacer()
            }
            .navigationTitle("List")
        }
    }
}

/// The width a node is drawn at, with its last scale.
private func drawnWidth(_ node: ViewNode) -> CGFloat? {
    guard let frame = node.frame else { return nil }
    guard case .scaleEffect(let x, _, _)? = node.modifiers.last else { return frame.width }
    return frame.width * x
}

/// The matched square as drawn: the `Color` with a matched geometry modifier.
@MainActor
private func box(_ host: ViewHost) -> ViewNode? {
    host.presentedRoot.allNodes.first { $0.kind == "Color" && !$0.modifiers.isEmpty }
}

/// The frame of the view with `matchedTransitionSource`.
@MainActor
private func sourceRect(_ host: ViewHost) throws -> CGRect {
    let node = try #require(
        host.root.allNodes.first {
            $0.modifiers.contains {
                if case .custom(let modifier) = $0 {
                    modifier.name == "matchedTransitionSource"
                } else {
                    false
                }
            }
        })
    let index = try #require(
        node.modifiers.firstIndex {
            if case .custom(let modifier) = $0 {
                modifier.name == "matchedTransitionSource"
            } else {
                false
            }
        })
    return node.modifierFrames[index]
}

@MainActor
@Suite("matchedGeometryEffect and the zoom navigation transition")
struct MatchedGeometryTests {
    @Test("The matching modifiers appear in the outline")
    func outline() {
        struct Screen: View {
            @Namespace var space
            var body: some View {
                VStack {
                    Color.red.frame(width: 20, height: 20)
                        .matchedGeometryEffect(id: "a", in: space)
                    Color.blue.frame(width: 20, height: 20)
                        .matchedGeometryEffect(
                            id: 2, in: space, properties: .position, isSource: false)
                    Text("Source").matchedTransitionSource(id: "a", in: space)
                    Text("Zoom").navigationTransition(.zoom(sourceID: "a", in: space))
                    Text("Automatic").navigationTransition(.automatic)
                }
            }
        }
        let host = ViewHost(Screen(), device: screen)
        let outline = host.root.outline()
        #expect(outline.contains("matchedGeometryEffect(id: a, namespace: "))
        #expect(outline.contains("id: 2, namespace: "))
        #expect(outline.contains("properties: position, isSource: false)"))
        #expect(outline.contains(#"Text "Source" "# + "matchedTransitionSource(id: a, namespace: "))
        #expect(outline.contains(#"Text "Zoom" "# + "navigationTransition(.zoom(sourceID: a, "))
        #expect(outline.contains(#"Text "Automatic""#))
        #expect(!outline.contains(#"Text "Automatic" navigation"#))
    }

    @Test("A matched view moves between two positions over 10 frames")
    func movesAcrossFrames() throws {
        let host = ViewHost(Moving(), device: screen)
        let start = try #require(box(host)?.frame)
        #expect(start.size == CGSize(width: 40, height: 40))
        try host.tapButton(labeled: "Move")
        let final = try #require(
            host.root.allNodes.first { $0.kind == "Color" && !$0.modifiers.isEmpty }?.frame)
        #expect(final.size == CGSize(width: 100, height: 100))
        #expect(final.maxX > start.maxX + 100)

        var frames: [CGRect] = []
        for _ in 0..<10 {
            host.advanceTime(by: 0.1)
            // The arriving square is the one that is not fading out.
            let arriving = host.presentedRoot.allNodes.filter {
                $0.kind == "Color" && !$0.modifiers.isEmpty
            }
            frames.append(try #require(arriving.last?.frame))
        }
        #expect(frames.count == 10)
        let xs = frames.map(\.minX)
        #expect(xs == xs.sorted())
        #expect(Set(xs).count >= 8)
        // Halfway, the square is between its two frames, in position and size.
        #expect(frames[4].minX > start.minX && frames[4].minX < final.minX)
        #expect(frames[4].width > 40 && frames[4].width < 100)
        // After 10 frames of 0.1 s it is at its own.
        #expect(frames[9] == final)
    }

    @Test("A matched view that arrives starts at the frame of the one it replaces")
    func startsAtSource() throws {
        let host = ViewHost(Moving(), device: screen)
        let start = try #require(box(host)?.frame)
        try host.tapButton(labeled: "Move")
        let arriving = try #require(
            host.presentedRoot.allNodes.last { $0.kind == "Color" && !$0.modifiers.isEmpty })
        #expect(arriving.frame == start)
        // The square that leaves moves to the new frame while it fades.
        let leaving = try #require(
            host.presentedRoot.allNodes.first { $0.kind == "Color" && !$0.modifiers.isEmpty })
        #expect(leaving.frame == start)
        host.advanceTime(by: 1)
        #expect(!host.isAnimating)
        #expect(
            host.presentedRoot.allNodes.filter { $0.kind == "Color" && !$0.modifiers.isEmpty }.count
                == 1)
    }

    @Test("Without an animation the matched view jumps")
    func jumps() throws {
        struct Plain: View {
            @Namespace var space
            @State var isAtEnd = false
            var body: some View {
                VStack {
                    if isAtEnd {
                        Color.red.frame(width: 100, height: 100)
                            .matchedGeometryEffect(id: "box", in: space)
                    } else {
                        Color.red.frame(width: 40, height: 40)
                            .matchedGeometryEffect(id: "box", in: space)
                    }
                    Button("Move") { isAtEnd.toggle() }
                }
            }
        }
        let host = ViewHost(Plain(), device: screen)
        try host.tapButton(labeled: "Move")
        #expect(
            host.presentedRoot.outline(includeFrames: true)
                == host.root.outline(includeFrames: true))
        #expect(!host.isAnimating)
    }

    // MARK: Zoom

    @Test("A full-screen cover with a zoom transition grows from its source frame")
    func coverGrows() throws {
        let host = ViewHost(ZoomCover(), device: screen)
        let sourceFrame = try sourceRect(host)
        #expect(sourceFrame.size == CGSize(width: 60, height: 60))

        try host.tapButton(labeled: "Open")
        let final = try #require(host.root.children.last?.frame)
        #expect(final == CGRect(x: 0, y: 0, width: 300, height: 400))

        // At the start the cover is drawn in the source's frame.
        var cover = try #require(host.presentedRoot.children.last)
        #expect(cover.kind == "FullScreenCover")
        guard case .scaleEffect(let x, let y, _) = try #require(cover.modifiers.last) else {
            Issue.record("The cover is drawn with a scale.")
            return
        }
        #expect(cover.frame?.origin == sourceFrame.origin)
        #expect(abs(x * 300 - sourceFrame.width) < 0.5)
        #expect(abs(y * 400 - sourceFrame.height) < 0.5)

        var widths: [CGFloat] = []
        for _ in 0..<10 {
            host.advanceTime(by: 0.05)
            cover = try #require(host.presentedRoot.children.last)
            if case .scaleEffect(let x, _, _)? = cover.modifiers.last { widths.append(x * 300) }
        }
        #expect(widths == widths.sorted())
        #expect(widths.first! > sourceFrame.width)
        #expect(widths.count > 3)

        host.advanceTime(by: 5)
        #expect(!host.isAnimating)
        cover = try #require(host.presentedRoot.children.last)
        #expect(cover.modifiers.isEmpty)
        #expect(cover.frame == final)
    }

    @Test("A full-screen cover with a zoom transition shrinks into its source when it closes")
    func coverShrinks() throws {
        let host = ViewHost(ZoomCover(), device: screen)
        let sourceFrame = try sourceRect(host)
        try host.tapButton(labeled: "Open")
        host.advanceTime(by: 5)
        try host.tapButton(labeled: "Close")
        #expect(host.root.children.count == 1)

        var cover = try #require(host.presentedRoot.children.last)
        #expect(cover.kind == "FullScreenCover")
        host.advanceTime(by: 0.1)
        cover = try #require(host.presentedRoot.children.last)
        #expect(cover.kind == "FullScreenCover")
        guard case .scaleEffect(let x, _, _)? = cover.modifiers.last else {
            Issue.record("The cover is drawn with a scale.")
            return
        }
        #expect(x < 1)
        // It does not slide off the bottom edge.
        #expect((cover.frame?.minY ?? 1000) < sourceFrame.maxY + 400)
        host.advanceTime(by: 5)
        #expect(host.presentedRoot.children.count == 1)
        #expect(!host.isAnimating)
    }

    @Test("A cover closed while it still zooms in shrinks from where it was drawn")
    func coverClosesMidZoom() throws {
        let host = ViewHost(ZoomCover(), device: screen)
        try host.tapButton(labeled: "Open")
        host.advanceTime(by: 0.1)
        let before = try #require(host.presentedRoot.children.last)
        let beforeWidth = try #require(drawnWidth(before))
        #expect(beforeWidth < 300)
        try host.tapButton(labeled: "Close")
        let after = try #require(host.presentedRoot.children.last)
        #expect(after.kind == "FullScreenCover")
        let scales = after.modifiers.filter {
            if case .scaleEffect = $0 { return true }
            return false
        }
        #expect(scales.count == 1)
        let afterWidth = try #require(drawnWidth(after))
        #expect(abs(afterWidth - beforeWidth) < 1)
        host.advanceTime(by: 5)
        #expect(host.presentedRoot.children.count == 1)
    }

    @Test("A cover without a zoom transition still slides up")
    func coverSlides() throws {
        struct Slide: View {
            @State var isOpen = false
            var body: some View {
                Button("Open") { isOpen = true }
                    .fullScreenCover(isPresented: $isOpen) { Text("Detail") }
            }
        }
        let host = ViewHost(Slide(), device: screen)
        try host.tapButton(labeled: "Open")
        let cover = try #require(host.presentedRoot.children.last)
        #expect(cover.frame?.minY == 400)
        #expect(cover.modifiers.isEmpty)
    }

    @Test("A pushed screen with a zoom transition grows from its source")
    func pushGrows() throws {
        let host = ViewHost(ZoomPush(), device: screen)
        let sourceFrame = try sourceRect(host)
        try host.tapButton(labeled: "Row")
        let detail = try #require(
            host.presentedRoot.allNodes.first { node in
                node.kind == "Text"
                    && node.modifiers.contains {
                        if case .scaleEffect = $0 { true } else { false }
                    }
            })
        #expect(detail.frame?.origin == sourceFrame.origin)
        host.advanceTime(by: 5)
        #expect(!host.isAnimating)
        let settled = try #require(host.presentedRoot.allNodes.first { $0.label == "Detail" })
        #expect(settled.modifiers.isEmpty)
    }
}
