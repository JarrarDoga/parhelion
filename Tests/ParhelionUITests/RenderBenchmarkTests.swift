import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

@MainActor
@Test(
    "Render timing", .enabled(if: ProcessInfo.processInfo.environment["PARHELION_BENCHMARK"] != nil)
)
func renderTiming() {
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
