import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

/// A 360 × 200 screen with no safe area.
private let screen = Device(
    name: "Test", screenSize: CGSize(width: 360, height: 200), safeAreaInsets: EdgeInsets())

/// A flat red backdrop, so glass shows as a color that is not red.
@MainActor
private func redBackdrop<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    ZStack {
        Color.red
        content()
    }
}

private struct Circles: View {
    let spacing: CGFloat
    let containerSpacing: CGFloat?

    var body: some View {
        redBackdrop {
            GlassEffectContainer(spacing: containerSpacing) {
                HStack(spacing: spacing) {
                    Color.clear.frame(width: 60, height: 60).glassEffect(in: .circle)
                    Color.clear.frame(width: 60, height: 60).glassEffect(in: .circle)
                }
            }
        }
    }
}

/// A glass circle at the leading edge, and a second one that a button adds
/// and removes with an animation, 20 points from the first.
private struct Morphing: View {
    @Namespace private var glass
    @State private var isShown = false

    var body: some View {
        redBackdrop {
            VStack {
                GlassEffectContainer(spacing: 40) {
                    HStack(spacing: 20) {
                        Color.clear.frame(width: 60, height: 60)
                            .glassEffect(in: .circle)
                            .glassEffectID("a", in: glass)
                        if isShown {
                            Color.clear.frame(width: 60, height: 60)
                                .glassEffect(in: .circle)
                                .glassEffectID("b", in: glass)
                        }
                    }
                }
                .frame(width: 300, height: 60, alignment: .leading)
                Button("Toggle") {
                    withAnimation(.linear(duration: 1)) { isShown.toggle() }
                }
            }
        }
    }
}

/// Above the green of system red, plus a little, glass is not over the backdrop.
private let backdrop = 75

@MainActor
private func green(_ host: ViewHost, _ x: CGFloat, _ y: CGFloat) -> Int {
    Int(host.render(scale: 1).color(at: CGPoint(x: x, y: y)).green)
}

/// The host's current frame drawn from scratch, without its cache.
@MainActor
private func uncachedFrame(_ host: ViewHost, scale: Double) -> [UInt8] {
    TreeRenderer(
        device: host.device, pressedNodeID: host.pressedNodeID,
        focusedNodeID: host.focusedNodeID, caretOffset: host.caretOffset
    )
    .render(host.presentedRoot, scale: scale).pixels
}

@MainActor
@Suite("glassEffect, GlassEffectContainer, and glassEffectID")
struct GlassEffectTests {
    // MARK: The tree

    @Test("glassEffect records its glass, tint, interactivity, and shape in the outline")
    func outline() {
        let host = ViewHost(
            VStack {
                Text("A").glassEffect()
                Text("B").glassEffect(.clear, in: .rect(cornerRadius: 20))
                Text("C").glassEffect(.regular.tint(.blue).interactive(), in: .circle)
                Text("D").glassEffect(.regular, in: .capsule, isEnabled: false)
            }, device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Text "A" glassEffect(regular, in: Capsule)
                   ├─ Text "B" glassEffect(clear, in: RoundedRectangle(cornerRadius: 20))
                   ├─ Text "C" glassEffect(regular.tint(blue).interactive(), in: Circle)
                   └─ Text "D" glassEffect(identity, in: Capsule)
                """)
    }

    @Test("GlassEffectContainer is a node of its own, and glassEffectID shows its ID")
    func containerOutline() {
        struct Screen: View {
            @Namespace var namespace
            var body: some View {
                GlassEffectContainer(spacing: 24) {
                    Text("A").glassEffect().glassEffectID("a", in: namespace)
                    Text("B").glassEffectID(nil as Int?, in: namespace)
                }
            }
        }
        let host = ViewHost(Screen(), device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ GlassEffectContainer spacing=24
                   ├─ Text "A" glassEffect(regular, in: Capsule) glassEffectID(a)
                   └─ Text "B" glassEffectID(nil)
                """)
    }

    @Test("A container lays out its views over each other, like a ZStack")
    func containerLayout() throws {
        let host = ViewHost(
            GlassEffectContainer {
                Color.red.frame(width: 100, height: 40)
                Color.blue.frame(width: 60, height: 80)
            }, device: screen)
        let container = host.root.children[0]
        #expect(container.frame == CGRect(x: 130, y: 60, width: 100, height: 80))
        #expect(container.children[0].frame == CGRect(x: 130, y: 80, width: 100, height: 40))
        #expect(container.children[1].frame == CGRect(x: 150, y: 60, width: 60, height: 80))
    }

    @Test("A glass in a container is marked as the container's to draw")
    func grouped() throws {
        let host = ViewHost(
            GlassEffectContainer { Text("A").glassEffect() }, device: screen)
        let text = try #require(host.root.allNodes.first { $0.kind == "Text" })
        guard case .custom(let modifier) = text.modifiers.first else {
            Issue.record("no custom modifier")
            return
        }
        #expect(modifier.parameters["grouped"] == "true")
        // Alone, it is not.
        let alone = ViewHost(Text("A").glassEffect(), device: screen)
        guard case .custom(let own) = alone.root.children[0].modifiers.first else {
            Issue.record("no custom modifier")
            return
        }
        #expect(own.parameters["grouped"] == nil)
    }

    @Test("A namespace keeps its ID when the view is evaluated again")
    func namespace() throws {
        struct Holder: View {
            @Namespace var namespace
            @State var count = 0
            var body: some View {
                VStack {
                    Text("\(namespace.hashValue)").glassEffectID("x", in: namespace)
                    Button("Again") { count += 1 }
                }
            }
        }
        let host = ViewHost(Holder(), device: screen)
        let before = host.root.allNodes.first { $0.kind == "Text" }?.text
        try host.tapButton(labeled: "Again")
        #expect(host.root.allNodes.first { $0.kind == "Text" }?.text == before)
    }

    // MARK: Drawing

    @Test("Glass draws behind its view, with clear glass fainter than regular")
    func drawsGlass() {
        func center(_ glass: Glass) -> Int {
            green(
                ViewHost(
                    redBackdrop {
                        Color.clear.frame(width: 120, height: 60).glassEffect(glass)
                    }, device: screen), 180, 100)
        }
        #expect(center(.regular) > 100)
        #expect(center(.clear) < center(.regular))
        #expect(center(.clear) >= 0)
        // No glass leaves the backdrop alone.
        #expect(center(.identity) < backdrop)
        // And glass stays inside its shape.
        let host = ViewHost(
            redBackdrop { Color.clear.frame(width: 120, height: 60).glassEffect(.regular) },
            device: screen)
        #expect(green(host, 30, 100) < backdrop)
    }

    @Test("A tint colors the glass, and the glass is clipped to a circle")
    func tint() {
        let host = ViewHost(
            redBackdrop {
                Color.clear.frame(width: 80, height: 80)
                    .glassEffect(.regular.tint(.blue), in: .circle)
            }, device: screen)
        let frame = host.render(scale: 1)
        let center = frame.color(at: CGPoint(x: 180, y: 100))
        #expect(center.blue > center.red)
        // The corner of the square frame is outside the circle.
        let corner = frame.color(at: CGPoint(x: 142, y: 62))
        #expect(corner.blue < 80)
    }

    @Test("Two circles in a container merge when they are closer than its spacing")
    func merges() {
        // The circles are 10 points apart; the middle is between them.
        let apart = ViewHost(Circles(spacing: 10, containerSpacing: 5), device: screen)
        let merged = ViewHost(Circles(spacing: 10, containerSpacing: 20), device: screen)
        let plain = ViewHost(Circles(spacing: 10, containerSpacing: nil), device: screen)
        #expect(green(apart, 180, 100) < backdrop)
        #expect(green(merged, 180, 100) > 100)
        #expect(green(plain, 180, 100) < backdrop)
        // The circle's own middle is glass either way.
        #expect(green(apart, 145, 100) > 100)
        #expect(green(merged, 145, 100) > 100)
        // A neck is thinner than the circles: just above it is still apart.
        #expect(green(merged, 180, 100 - 28) < backdrop)
        // Circles that touch merge with no spacing at all.
        let touching = ViewHost(Circles(spacing: 0, containerSpacing: nil), device: screen)
        #expect(green(touching, 180, 100) > 100)
        // Outside a container, the same circles never merge.
        let alone = ViewHost(
            redBackdrop {
                HStack(spacing: 10) {
                    Color.clear.frame(width: 60, height: 60).glassEffect(in: .circle)
                    Color.clear.frame(width: 60, height: 60).glassEffect(in: .circle)
                }
            }, device: screen)
        #expect(green(alone, 180, 100) < backdrop)
    }

    @Test("A glass that appears morphs out of the glass beside it, and back into it")
    func morphs() throws {
        let host = ViewHost(Morphing(), device: screen)
        // The first circle spans x 30 to 90 at y 70 to 130; the second will
        // span 110 to 170.
        let first = CGPoint(x: 60, y: 100)
        let second = CGPoint(x: 140, y: 100)
        #expect(green(host, first.x, first.y) > 100)
        #expect(green(host, second.x, second.y) < backdrop)

        try host.tapButton(labeled: "Toggle")
        // The tree already holds the final layout; the second circle's glass
        // is drawn where it comes from.
        host.advanceTime(by: 0.5)
        #expect(green(host, second.x, second.y) < backdrop)
        // Halfway, the second circle is half way out of the first, and the
        // two are one piece: its middle is glass.
        #expect(green(host, 90, 100) > 60)
        let halfway = host.render(scale: 1).color(at: CGPoint(x: 90, y: 100))
        #expect(halfway.green > 60)
        host.advanceTime(by: 0.5)
        #expect(green(host, second.x, second.y) > 100)
        #expect(!host.isAnimating)

        // It goes back into the first the same way.
        try host.tapButton(labeled: "Toggle")
        host.advanceTime(by: 0.5)
        #expect(host.isAnimating)
        #expect(green(host, second.x, second.y) < backdrop)
        #expect(green(host, 90, 100) > 60)
        host.advanceTime(by: 0.5)
        #expect(green(host, 90, 100) < backdrop)
    }

    @Test("Merged glass drawn through the cache is identical to drawn from scratch")
    func cacheMatches() throws {
        let host = ViewHost(Morphing(), device: screen)
        try host.tapButton(labeled: "Toggle")
        var frames = 0
        while host.isAnimating, frames < 100 {
            host.advanceTime(by: 1.0 / 30)
            frames += 1
            let cached = host.render(scale: 2).pixels
            #expect(cached == uncachedFrame(host, scale: 2), "frame \(frames)")
        }
        #expect(frames > 10)
        // A still, merged frame is kept and reused.
        let still = ViewHost(Circles(spacing: 10, containerSpacing: 20), device: screen)
        _ = still.render(scale: 2)
        _ = still.render(scale: 2)
        _ = still.render(scale: 2)
        #expect(still.renderCache.glassReuses >= 1)
    }

    @Test("Glass that is not a rounded rectangle draws inside its shape")
    func customShape() {
        struct Diamond: Shape {
            func path(in rect: CGRect) -> Path {
                var path = Path()
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                path.closeSubpath()
                return path
            }
        }
        let host = ViewHost(
            redBackdrop {
                Color.clear.frame(width: 100, height: 100).glassEffect(in: Diamond())
            }, device: screen)
        #expect(green(host, 180, 100) > 100)
        // The corner of the frame is outside the diamond.
        #expect(green(host, 135, 55) < backdrop)
    }

    // MARK: Pictures

    /// Writes the pictures of Rustle's token screen to a directory, when
    /// `PARHELION_GLASS_PNG_DIR` names one, for a person to look at.
    @Test("The glass of Rustle's token screen draws on board 17's sizes")
    func tokenScreen() throws {
        let host = ViewHost(TokenScreen(), device: .iPhone18ProMax)
        let frame = host.render(scale: 2, chrome: .systemBars)
        // Regular glass over the artwork is lighter than the artwork around it.
        let inside = frame.color(at: CGPoint(x: 220, y: 330))
        let beside = frame.color(at: CGPoint(x: 220, y: 300))
        #expect(inside.red != beside.red || inside.green != beside.green)
        if let directory = ProcessInfo.processInfo.environment["PARHELION_GLASS_PNG_DIR"] {
            try frame.pngData().write(to: URL(fileURLWithPath: directory + "/token-screen.png"))
            let dark = ViewHost(
                TokenScreen().environment(\.colorScheme, .dark), device: .iPhone18ProMax)
            try dark.render(scale: 2, chrome: .systemBars).pngData()
                .write(to: URL(fileURLWithPath: directory + "/token-screen-dark.png"))
            let morphing = ViewHost(Morphing(), device: screen)
            try morphing.tapButton(labeled: "Toggle")
            for (index, time) in [0.0, 0.25, 0.5, 0.75, 1.0].enumerated() {
                if time > 0 { morphing.advanceTime(by: 0.25) }
                try morphing.render(scale: 3).pngData()
                    .write(to: URL(fileURLWithPath: directory + "/morph-\(index).png"))
            }
        }
    }
}

/// Rustle's token preview: regular and clear glass, tinted glass, buttons, a
/// banner, and a merging group, over artwork.
private struct TokenScreen: View {
    @Namespace private var glass

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.purple, .orange, .teal], startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 24) {
                Text("Regular").font(.headline).padding(.horizontal, 24).padding(.vertical, 12)
                    .glassEffect(.regular)
                Text("Clear").font(.headline).padding(.horizontal, 24).padding(.vertical, 12)
                    .glassEffect(.clear)
                Text("Tinted").font(.headline).padding(.horizontal, 24).padding(.vertical, 12)
                    .glassEffect(.regular.tint(.blue).interactive())
                HStack {
                    Image(systemName: "backward.fill").frame(width: 56, height: 56)
                        .glassEffect(in: .circle)
                    Image(systemName: "play.fill").frame(width: 72, height: 72)
                        .glassEffect(.regular.tint(.pink), in: .circle)
                    Image(systemName: "forward.fill").frame(width: 56, height: 56)
                        .glassEffect(in: .circle)
                }
                GlassEffectContainer(spacing: 24) {
                    HStack(spacing: 12) {
                        Image(systemName: "heart").frame(width: 56, height: 56)
                            .glassEffect(in: .circle).glassEffectID("heart", in: glass)
                        Image(systemName: "plus").frame(width: 56, height: 56)
                            .glassEffect(in: .circle).glassEffectID("plus", in: glass)
                        Image(systemName: "ellipsis").frame(width: 56, height: 56)
                            .glassEffect(in: .circle).glassEffectID("more", in: glass)
                    }
                }
                HStack {
                    Image(systemName: "music.note").frame(width: 44, height: 44)
                    VStack(alignment: .leading) {
                        Text("Now playing").font(.subheadline)
                        Text("Artist").font(.caption)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(width: 400, height: 76)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
            }
        }
    }
}
