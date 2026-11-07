import Foundation
import Testing

@testable import ParhelionUI

private struct Item: Identifiable {
    var id: Int
}

private struct Songs: View {
    var count: Int
    var body: some View {
        NavigationStack {
            List((0..<count).map(Item.init)) { item in
                HStack {
                    Text("Song \(item.id)")
                    Spacer()
                    Text("3:45").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Songs")
        }
    }
}

private struct Stack: View {
    var count: Int
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach((0..<count).map(Item.init)) { item in
                    Text("Song \(item.id)").padding(14).frame(
                        maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Times the first layout of 5,000 rows, and then the frames of a scroll the
/// way the preview draws them at 120 Hz: the clock advances by 1/120 s and
/// one frame renders. Prints the average and the slowest frame, and the same
/// for a list of 40 rows, which creates all its rows, for comparison.
@MainActor
@Test(
    "Lazy rows timing",
    .enabled(if: ProcessInfo.processInfo.environment["PARHELION_BENCHMARK"] != nil)
)
func lazyTiming() {
    let clock = ContinuousClock()
    let makers: [(String, @MainActor () -> any View)] = [
        ("List of 5000", { Songs(count: 5000) }),
        ("List of 40", { Songs(count: 40) }),
        ("LazyVStack of 5000", { Stack(count: 5000) }),
    ]
    for (name, make) in makers {
        for scale in [2.0, 3.0] {
            var host: ViewHost?
            let first = clock.measure { host = ViewHost(anyRootView: make()) }
            guard let host else { return }
            _ = host.render(scale: scale, chrome: .screen)
            var layout = Duration.zero
            var render = Duration.zero
            var slowest = Duration.zero
            var jumps = Duration.zero
            var frames = 0
            var jumpCount = 0
            for step in 0..<240 {
                // 10 points a frame is 1,200 points a second; every 100th frame
                // jumps a thousand rows.
                let isJump = step % 100 == 99
                let delta = isJump ? 52_000 : 10
                let moved = clock.measure {
                    host.scroll(by: CGSize(width: 0, height: delta), at: CGPoint(x: 200, y: 400))
                    host.advanceTime(by: 1.0 / 120)
                }
                let drawn = clock.measure { _ = host.render(scale: scale, chrome: .screen) }
                if isJump {
                    jumps += moved
                    jumpCount += 1
                } else {
                    layout += moved
                    render += drawn
                    slowest = max(slowest, moved + drawn)
                    frames += 1
                }
            }
            let count = host.root.allNodes.count
            print(
                "BENCH lazy \(name) at \(Int(scale))×: first layout \(first); per frame, scroll and layout "
                    + "\(layout / frames), render \(render / frames), slowest \(slowest); "
                    + "a jump of 1,000 rows \(jumps / max(jumpCount, 1)); \(count) nodes in the tree"
            )
        }
    }
}
