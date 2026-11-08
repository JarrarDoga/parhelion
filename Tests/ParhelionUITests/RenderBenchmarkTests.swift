import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

@MainActor
@Test(
    "Render timing", .enabled(if: ProcessInfo.processInfo.environment["PARHELION_BENCHMARK"] != nil)
)
func renderTiming() throws {
    struct Rows: View {
        var body: some View {
            ScrollView {
                ForEach(1..<41) { row in
                    Text("Row \(row)").padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(row % 2 == 0 ? .white : .gray)
                }
            }
        }
    }
    let host = ViewHost(Rows())
    let clock = ContinuousClock()
    var layout = Duration.zero
    var render = Duration.zero
    for _ in 0..<20 {
        layout += clock.measure {
            host.scroll(by: CGSize(width: 0, height: 3), at: CGPoint(x: 100, y: 400))
        }
        render += clock.measure { _ = host.render(scale: 1) }
    }
    print("BENCH layout per frame: \(layout / 20), render per frame: \(render / 20)")
    try rustleTiming()
}

@Test(
    "Canvas timing", .enabled(if: ProcessInfo.processInfo.environment["PARHELION_BENCHMARK"] != nil)
)
func canvasTiming() {
    let clock = ContinuousClock()
    var canvas = Canvas(width: 393, height: 852, scale: 1)
    let blank = clock.measure { canvas = Canvas(width: 393, height: 852, scale: 1) }
    let rects = clock.measure {
        for row in 0..<20 {
            canvas.fill(CGRect(x: 0, y: Double(row) * 44, width: 393, height: 44), color: .black)
        }
    }
    let text = clock.measure {
        for row in 0..<20 {
            canvas.drawText(
                "Row \(row)", font: .interRegular, size: 17,
                origin: CGPoint(x: 12, y: Double(row) * 44 + 30), color: .black)
        }
    }
    print("BENCH blank canvas: \(blank), 20 full-width rects: \(rects), 20 text rows: \(text)")
}

@MainActor
@Test(
    "Glass timing", .enabled(if: ProcessInfo.processInfo.environment["PARHELION_BENCHMARK"] != nil)
)
func glassTiming() throws {
    let clock = ContinuousClock()
    for screen in [TasksScreens.Screen.list, .detail, .alert, .sheet] {
        let host = try TasksScreens.host(showing: screen)
        for scale in [2.0, 3.0] {
            _ = host.render(scale: scale, chrome: .screen)
            let render = clock.measure {
                for _ in 0..<10 { _ = host.render(scale: scale, chrome: .screen) }
            }
            print("BENCH \(screen.rawValue) at \(Int(scale))×: \(render / 10) per frame")
        }
    }
}

/// A long list under a large title with glass toolbar buttons, for scrolling.
private struct Inbox: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    ForEach(1..<61) { row in
                        NavigationLink("Message \(row)", value: row)
                    }
                }
            }
            .navigationTitle("Inbox")
            .navigationDestination(for: Int.self) { row in Text("Message \(row)") }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") {}
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }
}

/// Times the frames of an animation the way the preview draws them at 120
/// Hz. The preview draws one frame as soon as the input that starts the
/// animation arrives, which is timed on its own; then, for each tick, the
/// clock advances by 1/120 s and a frame renders, until nothing moves or
/// `limit` frames have drawn. Prints the average and slowest tick frame.
@MainActor
private func timeAnimation(_ name: String, scale: Double, limit: Int = 240, host: ViewHost) {
    let clock = ContinuousClock()
    let first = clock.measure { _ = host.render(scale: scale, chrome: .screen) }
    var total = Duration.zero
    var slowest = Duration.zero
    var frames = 0
    while host.isAnimating, frames < limit {
        host.advanceTime(by: 1.0 / 120)
        let render = clock.measure { _ = host.render(scale: scale, chrome: .screen) }
        total += render
        slowest = max(slowest, render)
        frames += 1
    }
    let average = frames > 0 ? total / frames : .zero
    print(
        "BENCH \(name) at \(Int(scale))×: \(average) per frame, slowest \(slowest), "
            + "\(frames) frames; first frame \(first)")
}

@MainActor
@Test(
    "Glass animation timing",
    .enabled(if: ProcessInfo.processInfo.environment["PARHELION_BENCHMARK"] != nil)
)
func glassAnimationTiming() throws {
    for scale in [2.0, 3.0] {
        // The alert fades in over the dimming screen.
        let alert = try TasksScreens.host(showing: .detail)
        _ = alert.render(scale: scale, chrome: .screen)
        try alert.tapButton(labeled: "Delete")
        timeAnimation("alert animating in", scale: scale, host: alert)

        // The sheet slides up.
        let sheet = try TasksScreens.host(showing: .list)
        _ = sheet.render(scale: scale, chrome: .screen)
        try sheet.tapButton(labeled: "Add")
        timeAnimation("sheet animating in", scale: scale, host: sheet)

        // A flung list scrolls under the toolbar's glass and slows down.
        let list = ViewHost(Inbox())
        _ = list.render(scale: scale, chrome: .screen)
        list.pointerDown(at: CGPoint(x: 200, y: 700))
        for step in 1...6 {
            list.advanceTime(by: 1.0 / 120)
            list.pointerMoved(to: CGPoint(x: 200, y: 700 - 25 * Double(step)))
        }
        list.pointerUp(at: CGPoint(x: 200, y: 550))
        timeAnimation("list scrolling under the toolbar", scale: scale, limit: 120, host: list)
    }
}

/// A long list under an inline title and a tab bar, scrolled under both.
private struct EdgeInbox: View {
    var style: ScrollEdgeEffectStyle?
    var hidden: Bool

    var body: some View {
        TabView {
            Tab("Inbox", systemImage: "tray") {
                NavigationStack {
                    List(1..<61, id: \.self) { Text("Message \($0)") }
                        .navigationTitle("Inbox")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .scrollEdgeEffectStyle(style, for: .all)
                .scrollEdgeEffectHidden(hidden, for: .all)
            }
        }
    }
}

/// The CPU time this process has used, which other programs' load on the
/// machine changes much less than the time on the clock.
private func cpuSeconds() -> Double {
    Double(clock()) / Double(CLOCKS_PER_SEC)
}

@MainActor
@Test(
    "Scroll edge effect timing",
    .enabled(if: ProcessInfo.processInfo.environment["PARHELION_BENCHMARK"] != nil)
)
func scrollEdgeTiming() throws {
    for scale in [2.0, 3.0] {
        for (name, style, hidden) in [
            ("hidden", ScrollEdgeEffectStyle?.none, true), ("soft", .soft, false),
            ("hard", .hard, false),
        ] {
            let host = ViewHost(EdgeInbox(style: style, hidden: hidden))
            let list = try #require(host.root.allNodes.first { $0.kind == "List" })
            _ = host.render(scale: scale, chrome: .screen)
            // A fling: a frame for every scrolled position, each drawn
            // through the cache as the preview draws it.
            var wall = Duration.zero
            let cpuStart = cpuSeconds()
            let clock = ContinuousClock()
            let frames = 120
            for frame in 1...frames {
                try host.scroll(list.id, to: CGPoint(x: 0, y: 3.7 * Double(frame)))
                wall += clock.measure { _ = host.render(scale: scale, chrome: .screen) }
            }
            let cpu = (cpuSeconds() - cpuStart) / Double(frames)
            print(
                "BENCH scrolling under both bars, \(name) edge effect at \(Int(scale))×: "
                    + "\(wall / frames) per frame, \(Int(cpu * 1000 * 100) / 100) ms CPU per frame")
        }
    }
}

@MainActor
@Test(
    "Scroll edge effect drawing timing",
    .enabled(if: ProcessInfo.processInfo.environment["PARHELION_BENCHMARK"] != nil)
)
func scrollEdgeDrawingTiming() throws {
    let clock = ContinuousClock()
    let rect = CGRect(x: 0, y: 0, width: 393, height: 101)
    for scale in [2.0, 3.0] {
        var canvas = Canvas(width: 393, height: 852, scale: scale, background: .white)
        for y in stride(from: 0, to: 852, by: 28) {
            canvas.fill(
                CGRect(x: 0, y: y, width: 393, height: 14), color: RGBA(red: 0, green: 0, blue: 0))
        }
        let palette = ColorPalette.appearance(.light)
        let effects: [(String, ScrollEdgeEffect)] = [
            (
                "soft",
                ScrollEdgeEffect(
                    kind: .soft(peak: ColorPalette.softScrollEdgePeak),
                    blurRadius: ColorPalette.softScrollEdgeBlurRadius, atTop: true)
            ),
            (
                "hard",
                ScrollEdgeEffect(
                    kind: .hard(
                        tint: palette.hardScrollEdge.tint, line: palette.hardScrollEdge.line),
                    blurRadius: ColorPalette.hardScrollEdgeBlurRadius, atTop: true)
            ),
        ]
        for (name, effect) in effects {
            var copy = canvas
            let time = clock.measure {
                for _ in 0..<20 { copy.drawScrollEdge(effect, in: rect) }
            }
            let region = canvas.scrollEdgeRegion(effect, in: rect)
            let sum = clock.measure { for _ in 0..<20 { _ = canvas.checksum(of: region) } }
            print(
                "BENCH \(name) scroll edge effect at \(Int(scale))×: \(time / 20) to draw, "
                    + "\(sum / 20) to checksum its region")
        }
    }
}
