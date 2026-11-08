import Foundation
import ParhelionRender
import Testing

@testable import ParhelionUI

/// The host's current frame drawn from scratch, without its cache.
@MainActor
private func uncachedFrame(_ host: ViewHost, scale: Double) -> Canvas {
    TreeRenderer(
        device: host.device, pressedNodeID: host.pressedNodeID,
        focusedNodeID: host.focusedNodeID, caretOffset: host.caretOffset
    )
    .render(host.presentedRoot, scale: scale)
}

/// Draws the host's frame through its cache and checks it against the same
/// frame drawn from scratch. At a scale where a whole pixel is not a
/// whole number of 1/1024 points, such as 3, a gradient's step can fall on
/// the other side of a rounding in a pixel here and there, so the frames may
/// differ by `tolerance` levels.
@MainActor
private func expectCachedFrameMatches(
    _ host: ViewHost, scale: Double, _ note: String = "", tolerance: Int = 0,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let frame = host.render(scale: scale)
    let cached = frame.pixels
    let fresh = uncachedFrame(host, scale: scale).pixels
    var differing = 0
    var note2 = ""
    var firstRow = Int.max
    var lastRow = Int.min
    if cached.count == fresh.count {
        for index in stride(from: 0, to: cached.count, by: 4)
        where (0..<4).contains(where: {
            abs(Int(cached[index + $0]) - Int(fresh[index + $0])) > tolerance
        }) {
            differing += 1
            let y = index / 4 / frame.pixelWidth
            firstRow = min(firstRow, y)
            lastRow = max(lastRow, y)
            if differing <= 6 {
                let x = index / 4 % frame.pixelWidth
                note2 +=
                    " (\(x),\(y): \(Array(cached[index..<index + 4])) vs \(Array(fresh[index..<index + 4])))"
            }
        }
    }
    #expect(
        cached.count == fresh.count && differing == 0,
        "frame \(note): \(differing) pixels differ, rows \(firstRow)...\(lastRow)\(note2)",
        sourceLocation: sourceLocation)
}

private struct ShadowRows: View {
    @State private var marked: Set<Int> = []
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<200, id: \.self) { row in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(marked.contains(row) ? Color.orange : Color.blue)
                                .frame(width: 48, height: 48)
                                .shadow(color: .black.opacity(0.4), radius: 6, x: 2, y: 3)
                            Circle().fill(Color.red).frame(width: 30, height: 30).overlay {
                                Circle().fill(Color.white).frame(width: 14, height: 14)
                            }
                            Text("Row \(row)")
                            Spacer()
                            Button("Mark") { marked.insert(row) }
                                .accessibilityLabel("Mark \(row)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Rows")
        }
    }
}

@MainActor
@Suite("Scrolling by moving the last frame")
struct ScrollShiftTests {
    @Test("A scrolled list matches drawing it again, at whole and fractional offsets")
    func collectionScroll() {
        for scale in [2.0, 3.0] {
            let tolerance = scale == 3 ? 1 : 0
            let host = ViewHost(CollectionFixture(count: 300), device: .iPhone18ProMax)
            expectCachedFrameMatches(host, scale: scale, "first", tolerance: tolerance)
            for delta in [10.0, 7.3, 0.4, 25.0, -3.1, -40.0, 9.99, 120.0, 3.0, -250.0] {
                host.scroll(by: CGSize(width: 0, height: delta), at: CGPoint(x: 200, y: 400))
                host.advanceTime(by: 1.0 / 120)
                expectCachedFrameMatches(host, scale: scale, "after \(delta)", tolerance: tolerance)
            }
            #expect(host.renderCache.scrollShifts > 5)
        }
    }

    @Test("A momentum fling matches drawing it again")
    func fling() {
        let host = ViewHost(CollectionFixture(count: 400), device: .iPhone18ProMax)
        expectCachedFrameMatches(host, scale: 2, "first")
        host.scroll(by: CGSize(width: 0, height: 30), at: CGPoint(x: 200, y: 400))
        host.drag(
            from: CGPoint(x: 200, y: 700), to: CGPoint(x: 200, y: 300), duration: 0.1)
        var frames = 0
        repeat {
            host.advanceTime(by: 1.0 / 120)
            expectCachedFrameMatches(host, scale: 2, "fling \(frames)")
            frames += 1
        } while frames < 90 && (host.isAnimating || frames < 4)
        #expect(host.renderCache.scrollShifts > 10)
    }

    @Test("Rows with shadows and strokes match, and a row that changes is drawn again")
    func shadowsAndChanges() throws {
        let host = ViewHost(ShadowRows(), device: .iPhone18ProMax)
        expectCachedFrameMatches(host, scale: 2, "first")
        for delta in [12.0, 17.5, 31.0, -9.0, 44.0] {
            host.scroll(by: CGSize(width: 0, height: delta), at: CGPoint(x: 200, y: 400))
            expectCachedFrameMatches(host, scale: 2, "after \(delta)")
        }
        try host.tapButton(labeled: "Mark 3")
        expectCachedFrameMatches(host, scale: 2, "after mark")
        host.scroll(by: CGSize(width: 0, height: 20), at: CGPoint(x: 200, y: 400))
        expectCachedFrameMatches(host, scale: 2, "scroll after mark")
        #expect(host.renderCache.scrollShifts > 3)
    }

    @Test("Content that blurs what is beneath it is drawn in full")
    func blurredContent() {
        struct Blurred: View {
            var body: some View {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(0..<60, id: \.self) { row in
                                Text("Row \(row)").frame(maxWidth: .infinity, minHeight: 60)
                                    .background(row % 2 == 0 ? Color.yellow : Color.green)
                                    .glassEffect(.regular, in: Capsule())
                            }
                        }
                    }
                }
            }
        }
        let host = ViewHost(Blurred(), device: .iPhone18ProMax)
        expectCachedFrameMatches(host, scale: 2, "first")
        for delta in [13.0, 21.0, -5.0] {
            host.scroll(by: CGSize(width: 0, height: delta), at: CGPoint(x: 200, y: 400))
            expectCachedFrameMatches(host, scale: 2, "after \(delta)")
        }
        #expect(host.renderCache.scrollShifts == 0)
    }
}
