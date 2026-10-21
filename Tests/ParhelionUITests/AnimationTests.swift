import Foundation
import Testing

@testable import ParhelionUI

/// A 300 × 400 screen with no safe-area insets.
private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 400),
    safeAreaInsets: EdgeInsets()
)

private struct Growing: View {
    @State private var isWide = false
    @State private var count = 0

    var body: some View {
        VStack {
            Color.red.frame(width: isWide ? 200 : 100, height: 50)
            Button("Grow") {
                withAnimation(.linear(duration: 1)) { isWide.toggle() }
            }
            Button("Grow now") { isWide.toggle() }
            Button("Count") { count += 1 }
            Text("Count: \(count)")
        }
    }
}

private struct Implicit: View {
    @State private var isWide = false
    @State private var isTall = false

    var body: some View {
        VStack {
            Color.red
                .frame(width: isWide ? 200 : 100, height: isTall ? 100 : 50)
                .animation(.linear(duration: 1), value: isWide)
            Button("Widen") { isWide.toggle() }
            Button("Heighten") { isTall.toggle() }
        }
    }
}

private struct Disabled: View {
    @State private var isWide = false

    var body: some View {
        VStack {
            Color.red
                .frame(width: isWide ? 200 : 100, height: 50)
                .animation(nil, value: isWide)
            Button("Widen") {
                withAnimation(.linear(duration: 1)) { isWide.toggle() }
            }
        }
    }
}

private struct Appearing: View {
    var transition: AnyTransition = .opacity
    @State private var isShown = false

    var body: some View {
        VStack {
            if isShown {
                Text("Hello").transition(transition)
            }
            Button("Toggle") {
                withAnimation(.linear(duration: 1)) { isShown.toggle() }
            }
        }
    }
}

@MainActor
private func colorFrame(_ node: ViewNode) -> CGRect? {
    node.allNodes.first { $0.kind == "Color" }?.frame
}

@MainActor
private func node(_ root: ViewNode, text: String) -> ViewNode? {
    root.allNodes.first { $0.text == text }
}

@MainActor
@Suite("Animation")
struct AnimationTests {
    @Test("withAnimation changes the tree at once and the drawn frames over time")
    func explicitAnimation() throws {
        let host = ViewHost(Growing(), device: screen)
        try host.tapButton(labeled: "Grow")
        #expect(colorFrame(host.root)?.width == 200)
        #expect(colorFrame(host.presentedRoot)?.width == 100)
        #expect(host.isAnimating)
        host.advanceTime(by: 0.5)
        #expect(abs((colorFrame(host.presentedRoot)?.width ?? 0) - 150) < 0.01)
        host.advanceTime(by: 0.5)
        #expect(colorFrame(host.presentedRoot)?.width == 200)
        #expect(!host.isAnimating)
    }

    @Test("A change without animation is drawn at once")
    func noAnimation() throws {
        let host = ViewHost(Growing(), device: screen)
        try host.tapButton(labeled: "Grow now")
        #expect(host.presentedRoot == host.root)
        #expect(!host.isAnimating)
    }

    @Test("The revision increases on every step while something animates")
    func revision() throws {
        let host = ViewHost(Growing(), device: screen)
        try host.tapButton(labeled: "Grow")
        let start = host.revision
        host.advanceTime(by: 0.1)
        host.advanceTime(by: 0.1)
        #expect(host.revision == start + 2)
        host.advanceTime(by: 1)
        let settled = host.revision
        host.advanceTime(by: 0.1)
        #expect(host.revision == settled)
    }

    @Test("Frames are the same however the clock's time is split")
    func determinism() throws {
        let once = ViewHost(Growing(), device: screen)
        let steps = ViewHost(Growing(), device: screen)
        try once.tapButton(labeled: "Grow")
        try steps.tapButton(labeled: "Grow")
        once.advanceTime(by: 0.3)
        for _ in 0..<3 { steps.advanceTime(by: 0.1) }
        #expect(colorFrame(once.presentedRoot) == colorFrame(steps.presentedRoot))
    }

    @Test("An unanimated change during an animation leaves it running")
    func unrelatedChange() throws {
        let host = ViewHost(Growing(), device: screen)
        try host.tapButton(labeled: "Grow")
        host.advanceTime(by: 0.5)
        try host.tapButton(labeled: "Count")
        #expect(node(host.root, text: "Count: 1") != nil)
        #expect(abs((colorFrame(host.presentedRoot)?.width ?? 0) - 150) < 0.01)
    }

    @Test("animation(_:value:) animates when its value changes, and only then")
    func implicitAnimation() throws {
        let host = ViewHost(Implicit(), device: screen)
        try host.tapButton(labeled: "Heighten")
        #expect(!host.isAnimating)
        try host.tapButton(labeled: "Widen")
        #expect(host.isAnimating)
        host.advanceTime(by: 0.25)
        #expect(abs((colorFrame(host.presentedRoot)?.width ?? 0) - 125) < 0.01)
    }

    @Test("animation(nil, value:) turns animation off inside withAnimation")
    func disabledAnimation() throws {
        let host = ViewHost(Disabled(), device: screen)
        try host.tapButton(labeled: "Widen")
        #expect(colorFrame(host.presentedRoot)?.width == 200)
    }

    @Test("An inserted view fades in, and a removed one fades out of the drawn tree")
    func opacityTransition() throws {
        let host = ViewHost(Appearing(), device: screen)
        try host.tapButton(labeled: "Toggle")
        #expect(node(host.presentedRoot, text: "Hello")?.opacity == 0)
        host.advanceTime(by: 0.5)
        #expect(abs((node(host.presentedRoot, text: "Hello")?.opacity ?? 0) - 0.5) < 0.01)
        host.advanceTime(by: 0.5)
        #expect(node(host.presentedRoot, text: "Hello")?.opacity == 1)

        try host.tapButton(labeled: "Toggle")
        #expect(node(host.root, text: "Hello") == nil)
        host.advanceTime(by: 0.25)
        #expect(abs((node(host.presentedRoot, text: "Hello")?.opacity ?? 0) - 0.75) < 0.01)
        host.advanceTime(by: 1)
        #expect(node(host.presentedRoot, text: "Hello") == nil)
    }

    @Test("A move transition starts the view one width away from its place")
    func moveTransition() throws {
        let host = ViewHost(Appearing(transition: .move(edge: .leading)), device: screen)
        try host.tapButton(labeled: "Toggle")
        let target = try #require(node(host.root, text: "Hello")?.frame)
        let drawn = try #require(node(host.presentedRoot, text: "Hello")?.frame)
        #expect(abs(drawn.minX - (target.minX - target.width)) < 0.01)
        #expect(node(host.presentedRoot, text: "Hello")?.opacity == 1)
    }

    @Test("Timing curves and springs reach their targets")
    func curves() {
        #expect(abs(Animation.linear(duration: 2).progress(at: 0.5) - 0.25) < 1e-6)
        #expect(abs(Animation.easeInOut(duration: 1).progress(at: 0.5) - 0.5) < 0.001)
        #expect(Animation.easeIn(duration: 1).progress(at: 0.5) < 0.5)
        #expect(Animation.easeOut(duration: 1).progress(at: 0.5) > 0.5)
        #expect(abs(Animation.linear(duration: 1).delay(0.5).progress(at: 0.75) - 0.25) < 1e-6)
        #expect(Animation.linear(duration: 1).speed(2).totalDuration == 0.5)

        let smooth = Animation.smooth
        #expect(smooth.totalDuration > 0 && smooth.totalDuration < 3)
        #expect(smooth.progress(at: smooth.totalDuration) == 1)
        let samples = stride(from: 0.0, to: 2, by: 0.01).map { Animation.bouncy.progress(at: $0) }
        #expect(samples.contains { $0 > 1 })
        #expect(!stride(from: 0.0, to: 2, by: 0.01).contains { smooth.progress(at: $0) > 1.0001 })
    }

    @Test("opacity(_:) records an opacity that multiplies with its ancestors'")
    func opacityModifier() {
        let host = ViewHost(Text("Faded").opacity(0.5).opacity(0.5), device: screen)
        #expect(host.root.outline() == "Root\n└─ Text \"Faded\" opacity=0.25")
    }

    @Test("offset(x:y:) moves a view without changing the layout around it")
    func offsetModifier() throws {
        let tapped = Box()
        let host = ViewHost(
            VStack(spacing: 0) {
                Button("Moved") { tapped.value += 1 }.offset(x: 50)
                Color.red.frame(width: 10, height: 10)
            },
            device: screen
        )
        let button = host.root.children[0].children[0]
        #expect(button.outline() == "Button offset(x: 50, y: 0)\n└─ Text \"Moved\"")
        let frame = try #require(button.frame)
        let color = try #require(host.root.children[0].children[1].frame)
        #expect(abs(frame.midX - (150 + 50)) < 0.01)
        #expect(abs(color.minY - frame.maxY) < 0.01)
        try host.tap(at: CGPoint(x: frame.midX, y: frame.midY))
        #expect(tapped.value == 1)
    }

    @Test("A push slides the new screen in while the tree already shows it")
    func navigationPush() throws {
        let host = ViewHost(
            NavigationStack {
                NavigationLink("Open") { Text("Detail") }
            },
            device: screen
        )
        try host.tapButton(labeled: "Open")
        #expect(node(host.root, text: "Open") == nil)
        let detail = try #require(node(host.root, text: "Detail")?.frame)
        let drawn = try #require(node(host.presentedRoot, text: "Detail")?.frame)
        #expect(drawn.minX > detail.minX + 100)
        #expect(node(host.presentedRoot, text: "Open") != nil)
        host.advanceTime(by: 2)
        #expect(host.presentedRoot == host.root)
    }

    @Test("A sheet slides up from the bottom of the screen")
    func sheetEntrance() throws {
        let host = ViewHost(SheetPresenter(), device: screen)
        try host.tapButton(labeled: "Show")
        #expect(host.root.children.last?.kind == "Sheet")
        let resting = try #require(host.root.children.last?.frame)
        let drawn = try #require(host.presentedRoot.children.last?.frame)
        #expect(drawn.minY >= screen.screenSize.height - 0.01)
        host.advanceTime(by: 2)
        #expect(host.presentedRoot.children.last?.frame == resting)
    }
}

private struct SheetPresenter: View {
    @State private var isShowing = false

    var body: some View {
        Button("Show") { isShowing = true }
            .sheet(isPresented: $isShowing) { Text("Sheet") }
    }
}

@MainActor
private final class Box {
    var value = 0
}
