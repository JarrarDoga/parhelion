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
