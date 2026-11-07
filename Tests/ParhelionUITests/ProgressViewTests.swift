import Foundation
import Testing

@testable import ParhelionUI

private let screen = Device(
    name: "Test", screenSize: CGSize(width: 300, height: 200), safeAreaInsets: EdgeInsets())

private let tall = Device(
    name: "Tall", screenSize: CGSize(width: 300, height: 300), safeAreaInsets: EdgeInsets())

@MainActor
private func node(_ host: ViewHost, kind: String, at index: Int = 0) throws -> ViewNode {
    let matches = host.root.allNodes.filter { $0.kind == kind }
    try #require(matches.indices.contains(index))
    return matches[index]
}

@MainActor
private func frameOf(_ host: ViewHost, kind: String, at index: Int = 0) throws -> CGRect {
    try #require(try node(host, kind: kind, at: index).frame)
}

private func rgb(_ color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> [Int] {
    [Int(color.red), Int(color.green), Int(color.blue)]
}

/// Whether any pixel of a rectangle differs from the white background.
@MainActor
private func draws(_ host: ViewHost, in rect: CGRect) -> Bool {
    let frame = host.render(scale: 1)
    for y in Int(rect.minY)..<Int(rect.maxY) {
        for x in Int(rect.minX)..<Int(rect.maxX)
        where rgb(frame.color(at: CGPoint(x: x, y: y))) != [255, 255, 255] {
            return true
        }
    }
    return false
}

private struct Spinner: View {
    var body: some View { ProgressView().padding(20) }
}

private struct Bar: View {
    var label = false
    var body: some View {
        VStack {
            if label {
                ProgressView(value: 0.4) { Text("Syncing") }
            } else {
                ProgressView(value: 0.4)
            }
        }
        .padding(20)
    }
}

@MainActor
@Suite("ProgressView")
struct ProgressViewTests {
    // MARK: Outlines

    @Test("A spinner, with and without a label, is a circular progress view")
    func spinnerOutline() {
        struct Content: View {
            var body: some View {
                VStack {
                    ProgressView()
                    ProgressView("Loading")
                    ProgressView {
                        Text("Importing")
                    }
                    ProgressView(value: nil as Double?)
                }
            }
        }
        #expect(
            ViewHost(Content(), device: screen).root.outline() == """
                Root
                └─ VStack
                   ├─ ProgressView style=circular
                   │  └─ ProgressIndicator phase=0.000 shape=spinner
                   ├─ ProgressView style=circular
                   │  ├─ ProgressIndicator phase=0.000 shape=spinner
                   │  └─ Text "Loading"
                   ├─ ProgressView style=circular
                   │  ├─ ProgressIndicator phase=0.000 shape=spinner
                   │  └─ Text "Importing"
                   └─ ProgressView style=circular
                      └─ ProgressIndicator phase=0.000 shape=spinner
                """)
    }

    @Test("A bar shows its label above it and its current value label below it")
    func barOutline() {
        struct Content: View {
            var body: some View {
                VStack {
                    ProgressView(value: 0.4)
                    ProgressView("Downloading", value: 0.4)
                    ProgressView(value: 640, total: 1535) {
                        Text("Songs")
                    } currentValueLabel: {
                        Text("640 of 1,535")
                    }
                }
            }
        }
        #expect(
            ViewHost(Content(), device: screen).root.outline() == """
                Root
                └─ VStack
                   ├─ ProgressView style=linear total=1 value=0.4
                   │  └─ ProgressIndicator fraction=0.4 shape=bar
                   ├─ ProgressView style=linear total=1 value=0.4
                   │  ├─ Text "Downloading"
                   │  └─ ProgressIndicator fraction=0.4 shape=bar
                   └─ ProgressView style=linear total=1535 value=640
                      ├─ Text "Songs"
                      ├─ ProgressIndicator fraction=0.42 shape=bar
                      └─ Text "640 of 1,535"
                """)
    }

    @Test("The styles choose a spinner, a ring, or a bar")
    func styleOutline() {
        struct Content: View {
            var body: some View {
                VStack {
                    ProgressView(value: 0.4).progressViewStyle(.circular)
                    ProgressView().progressViewStyle(.linear)
                    ProgressView(value: 0.4).progressViewStyle(.automatic)
                    ProgressView(value: 0.4).progressViewStyle(
                        CircularProgressViewStyle(tint: .red))
                    VStack {
                        ProgressView(value: 0.4)
                    }
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                }
            }
        }
        #expect(
            ViewHost(Content(), device: screen).root.outline() == """
                Root
                └─ VStack
                   ├─ ProgressView style=circular total=1 value=0.4
                   │  └─ ProgressIndicator fraction=0.4 shape=ring
                   ├─ ProgressView style=linear
                   │  └─ ProgressIndicator phase=0.000 shape=bar
                   ├─ ProgressView style=linear total=1 value=0.4
                   │  └─ ProgressIndicator fraction=0.4 shape=bar
                   ├─ ProgressView style=circular tint=red total=1 value=0.4
                   │  └─ ProgressIndicator fraction=0.4 shape=ring
                   └─ VStack
                      └─ ProgressView style=linear tint=green total=1 value=0.4
                         └─ ProgressIndicator fraction=0.4 shape=bar
                """)
    }

    @Test("A value beyond the total fills the bar, and one below zero empties it")
    func clampedValues() {
        struct Content: View {
            var body: some View {
                VStack {
                    ProgressView(value: 3.0, total: 2.0)
                    ProgressView(value: -1.0)
                    ProgressView(value: 1.0, total: 0.0)
                }
            }
        }
        let fractions = ViewHost(Content(), device: screen).root.allNodes
            .filter { $0.kind == "ProgressIndicator" }.map { $0.attributes["fraction"] }
        #expect(fractions == ["1", "0", "0"])
    }

    @Test("A custom style builds its body from the fraction and the labels")
    func customStyle() {
        struct Percent: ProgressViewStyle {
            func makeBody(configuration: Configuration) -> some View {
                HStack {
                    configuration.label
                    Text("\(Int((configuration.fractionCompleted ?? 0) * 100)) %")
                }
            }
        }
        struct Content: View {
            var body: some View {
                ProgressView(value: 0.4) { Text("Songs") }.progressViewStyle(Percent())
            }
        }
        #expect(
            ViewHost(Content(), device: screen).root.outline() == """
                Root
                └─ ProgressView style=Percent total=1 value=0.4
                   └─ HStack
                      ├─ Text "Songs"
                      └─ Text "40 %"
                """)
    }

    @Test("A custom style can wrap the default look with ProgressView(configuration)")
    func customStyleWrapsConfiguration() {
        struct Framed: ProgressViewStyle {
            func makeBody(configuration: Configuration) -> some View {
                ProgressView(configuration).padding(4)
            }
        }
        struct Content: View {
            var body: some View {
                ProgressView(value: 0.4) { Text("Songs") }.progressViewStyle(Framed())
            }
        }
        #expect(
            ViewHost(Content(), device: screen).root.outline() == """
                Root
                └─ ProgressView style=Framed total=1 value=0.4
                   └─ ProgressView padding(4) style=linear total=1 value=0.4
                      ├─ Text "Songs"
                      └─ ProgressIndicator fraction=0.4 shape=bar
                """)
    }

    // MARK: Layout

    @Test("A spinner is 20 points across, centered, with its label below")
    func spinnerLayout() throws {
        struct Content: View {
            var body: some View { ProgressView("Loading") }
        }
        let host = ViewHost(Content(), device: screen)
        let spinner = try frameOf(host, kind: "ProgressIndicator")
        let text = try frameOf(host, kind: "Text")
        #expect(spinner.size == CGSize(width: 20, height: 20))
        #expect(spinner.midX == 150)
        #expect(text.minY >= spinner.maxY)
        #expect(abs(text.midX - 150) < 0.01)
    }

    @Test("A bar is 4 points thick and as wide as it is offered")
    func barLayout() throws {
        let host = ViewHost(Bar(), device: screen)
        let bar = try frameOf(host, kind: "ProgressIndicator")
        #expect(bar == CGRect(x: 20, y: 98, width: 260, height: 4))
    }

    @Test("A bar's label is above it at the leading edge")
    func barLabelLayout() throws {
        let host = ViewHost(Bar(label: true), device: screen)
        let bar = try frameOf(host, kind: "ProgressIndicator")
        let text = try frameOf(host, kind: "Text")
        #expect(text.minX == 20)
        #expect(text.maxY <= bar.minY)
        #expect(bar.width == 260)
    }

    // MARK: Drawing

    @Test("A bar at 40 percent has the tint over 40 percent of a gray track")
    func barPixels() throws {
        let host = ViewHost(Bar(), device: screen)
        let bar = try frameOf(host, kind: "ProgressIndicator")
        let frame = host.render(scale: 1)
        let y = bar.midY
        let filled = rgb(frame.color(at: CGPoint(x: bar.minX + bar.width * 0.2, y: y)))
        let empty = rgb(frame.color(at: CGPoint(x: bar.minX + bar.width * 0.7, y: y)))
        #expect(filled == [0, 136, 255])
        #expect(empty != [0, 136, 255])
        #expect(empty != [255, 255, 255])
        // The tint ends at 40 percent.
        let edge = bar.minX + bar.width * 0.4
        #expect(rgb(frame.color(at: CGPoint(x: edge - 3, y: y))) == [0, 136, 255])
        #expect(rgb(frame.color(at: CGPoint(x: edge + 3, y: y))) != [0, 136, 255])
    }

    @Test("A bar with a label draws the label and the bar")
    func labeledBarPixels() throws {
        let host = ViewHost(Bar(label: true), device: screen)
        let bar = try frameOf(host, kind: "ProgressIndicator")
        let text = try frameOf(host, kind: "Text")
        #expect(draws(host, in: text))
        let frame = host.render(scale: 1)
        #expect(
            rgb(frame.color(at: CGPoint(x: bar.minX + bar.width * 0.2, y: bar.midY)))
                == [0, 136, 255])
    }

    @Test("A bar takes the tint of its style and of tint(_:)")
    func tintedBar() throws {
        struct Content: View {
            var body: some View {
                VStack {
                    ProgressView(value: 1.0).progressViewStyle(LinearProgressViewStyle(tint: .red))
                    ProgressView(value: 1.0).tint(.green)
                }
                .padding(20)
            }
        }
        let host = ViewHost(Content(), device: screen)
        let frame = host.render(scale: 1)
        let red = try frameOf(host, kind: "ProgressIndicator", at: 0)
        let green = try frameOf(host, kind: "ProgressIndicator", at: 1)
        #expect(rgb(frame.color(at: CGPoint(x: red.midX, y: red.midY))) == [255, 56, 60])
        #expect(rgb(frame.color(at: CGPoint(x: green.midX, y: green.midY))) == [52, 199, 89])
    }

    @Test("A spinner draws spokes, with the leading one darkest")
    func spinnerPixels() throws {
        let host = ViewHost(Spinner(), device: screen)
        let spinner = try frameOf(host, kind: "ProgressIndicator")
        #expect(draws(host, in: spinner))
        // At phase 0 the leading spoke points up, and the one behind it, to
        // the upper left, is the faintest.
        let frame = host.render(scale: 4)
        let top = frame.color(at: CGPoint(x: spinner.midX, y: spinner.minY + 3))
        let left = frame.color(at: CGPoint(x: spinner.minX + 3, y: spinner.midY))
        #expect(top.red < left.red)
    }

    @Test("A ring at 40 percent has the tint from the top, clockwise, over a gray track")
    func ringPixels() throws {
        struct Content: View {
            var body: some View {
                ProgressView(value: 0.4).progressViewStyle(.circular)
            }
        }
        let host = ViewHost(Content(), device: screen)
        let ring = try frameOf(host, kind: "ProgressIndicator")
        let frame = host.render(scale: 4)
        func color(angle degrees: Double) -> [Int] {
            let radians = (degrees - 90) * .pi / 180
            let radius = 10 - 1.25
            return rgb(
                frame.color(
                    at: CGPoint(
                        x: ring.midX + radius * cos(radians), y: ring.midY + radius * sin(radians)))
            )
        }
        // 40 percent of a turn is 144 degrees.
        #expect(color(angle: 5) == [0, 136, 255])
        #expect(color(angle: 90) == [0, 136, 255])
        #expect(color(angle: 135) == [0, 136, 255])
        #expect(color(angle: 160) != [0, 136, 255])
        #expect(color(angle: 270) != [0, 136, 255])
        #expect(color(angle: 270) != [255, 255, 255])
        // The middle of the ring is empty.
        #expect(rgb(frame.color(at: CGPoint(x: ring.midX, y: ring.midY))) == [255, 255, 255])
    }

    @Test("The progress bar draws in dark mode")
    func darkBar() throws {
        let host = ViewHost(
            Bar().preferredColorScheme(.dark), device: screen)
        let bar = try frameOf(host, kind: "ProgressIndicator")
        let frame = host.render(scale: 1)
        let filled = rgb(frame.color(at: CGPoint(x: bar.minX + 10, y: bar.midY)))
        #expect(filled != [0, 136, 255])
        #expect(filled[2] > filled[0])
    }

    // MARK: Animation

    @Test("A spinner turns once a second on the host's clock")
    func spinnerAnimates() {
        let host = ViewHost(Spinner(), device: screen)
        func phase() -> String? {
            host.root.allNodes.first { $0.kind == "ProgressIndicator" }?.attributes["phase"]
        }
        #expect(phase() == "0.000")
        #expect(host.isAnimating)
        host.advanceTime(by: 0.25)
        #expect(phase() == "0.250")
        host.advanceTime(by: 0.5)
        #expect(phase() == "0.750")
        host.advanceTime(by: 0.5)
        #expect(phase() == "0.250")
    }

    @Test("A spinner's leading spoke moves with the clock")
    func spinnerFrames() throws {
        let host = ViewHost(Spinner(), device: screen)
        let spinner = try frameOf(host, kind: "ProgressIndicator")
        let before = host.render(scale: 2)
        host.advanceTime(by: 0.25)
        let after = host.render(scale: 2)
        #expect(before.pngData() != after.pngData())
        // A quarter turn on, the leading spoke points to the right.
        let right = after.color(at: CGPoint(x: spinner.maxX - 3, y: spinner.midY))
        let up = after.color(at: CGPoint(x: spinner.midX, y: spinner.minY + 3))
        #expect(right.red < up.red)
    }

    @Test("An indeterminate bar's highlight crosses the track")
    func indeterminateBar() throws {
        struct Content: View {
            var body: some View { ProgressView().progressViewStyle(.linear).padding(20) }
        }
        let host = ViewHost(Content(), device: screen)
        let bar = try frameOf(host, kind: "ProgressIndicator")
        #expect(host.isAnimating)
        host.advanceTime(by: 0.75)
        let frame = host.render(scale: 1)
        #expect(rgb(frame.color(at: CGPoint(x: bar.midX, y: bar.midY))) == [0, 136, 255])
        #expect(rgb(frame.color(at: CGPoint(x: bar.minX + 3, y: bar.midY))) != [0, 136, 255])
    }

    @Test("A bar with a value does not animate")
    func barIsStill() {
        let host = ViewHost(Bar(), device: screen)
        #expect(!host.isAnimating)
    }

    @Test("A spinner that leaves the screen stops the animation")
    func spinnerLeaves() throws {
        struct Content: View {
            @State var loading = true
            var body: some View {
                VStack {
                    if loading { ProgressView() }
                    Button("Done") { loading = false }
                }
            }
        }
        let host = ViewHost(Content(), device: screen)
        #expect(host.isAnimating)
        try host.tapButton(labeled: "Done")
        #expect(!host.isAnimating)
    }

    @Test("A value that changes moves the bar")
    func valueChanges() throws {
        struct Content: View {
            @State var done = 0.0
            var body: some View {
                VStack {
                    ProgressView(value: done, total: 4)
                    Button("Next") { done += 1 }
                }
            }
        }
        let host = ViewHost(Content(), device: screen)
        func fraction() -> String? {
            host.root.allNodes.first { $0.kind == "ProgressIndicator" }?.attributes["fraction"]
        }
        #expect(fraction() == "0")
        try host.tapButton(labeled: "Next")
        try host.tapButton(labeled: "Next")
        #expect(fraction() == "0.5")
    }

    // MARK: Pictures

    /// Writes a picture of the spinner and the bars to a directory, when
    /// `PARHELION_PROGRESS_PNG_DIR` names one, for a person to look at.
    @Test("The spinner, the ring, and the bars draw together")
    func gallery() throws {
        struct Content: View {
            var body: some View {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 24) {
                        ProgressView()
                        ProgressView("Loading")
                        ProgressView(value: 0.4).progressViewStyle(.circular)
                    }
                    ProgressView(value: 0.4)
                    ProgressView(value: 640, total: 1535) {
                        Text("Songs")
                    } currentValueLabel: {
                        Text("640 of 1,535")
                    }
                    ProgressView(value: 0.4).tint(.green)
                    ProgressView("Importing").progressViewStyle(.linear)
                }
                .padding(20)
            }
        }
        let host = ViewHost(Content(), device: tall)
        host.advanceTime(by: 0.3)
        let frame = host.render(scale: 3)
        #expect(frame.pngData().count > 0)
        if let directory = ProcessInfo.processInfo.environment["PARHELION_PROGRESS_PNG_DIR"] {
            try frame.pngData().write(to: URL(fileURLWithPath: directory + "/progress-view.png"))
            let dark = ViewHost(
                Content().preferredColorScheme(.dark), device: tall)
            dark.advanceTime(by: 0.3)
            try dark.render(scale: 3).pngData()
                .write(to: URL(fileURLWithPath: directory + "/progress-view-dark.png"))
        }
    }
}
