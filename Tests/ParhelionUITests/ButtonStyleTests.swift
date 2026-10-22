import Foundation
import Testing

@testable import ParhelionUI

private let square = Device(
    name: "Test",
    screenSize: CGSize(width: 240, height: 200),
    safeAreaInsets: EdgeInsets()
)

private func components(_ color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> [Int] {
    [Int(color.red), Int(color.green), Int(color.blue)]
}

private func width(_ text: String, _ font: Font = .body) -> CGFloat {
    FontTextMeasurer().size(of: text, font: font.resolved(), width: nil).width
}

/// The most saturated color among the pixels across the middle of a frame,
/// which is the label's ink.
@MainActor
private func ink(_ host: ViewHost, in frame: CGRect) -> [Int] {
    let rendered = host.render(scale: 3)
    var best = components(rendered.color(at: CGPoint(x: frame.minX, y: frame.midY)))
    var bestScore = -1
    for x in stride(from: frame.minX, to: frame.maxX, by: 1.0 / 3) {
        let pixel = components(rendered.color(at: CGPoint(x: x, y: frame.midY)))
        let score = 765 - pixel.reduce(0, +) + (pixel.max()! - pixel.min()!) * 2
        if score > bestScore {
            bestScore = score
            best = pixel
        }
    }
    return best
}

private struct Pressed: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(4).background(.yellow)
    }
}

@MainActor
@Suite("Button styles")
struct ButtonStyleTests {
    @Test("Button styles record themselves on the button")
    func outline() {
        let host = ViewHost(
            VStack {
                Button("A") {}
                Button("B") {}.buttonStyle(.bordered).controlSize(.large)
                Button("C") {}.buttonStyle(.glass)
                Button("D") {}.buttonStyle(Pressed())
            }
            .buttonStyle(.borderedProminent),
            device: square
        )
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Button buttonStyle=borderedProminent
                   │  └─ Text "A"
                   ├─ Button buttonStyle=bordered controlSize=large
                   │  └─ Text "B"
                   ├─ Button buttonStyle=glass
                   │  └─ Text "C" font=body.medium
                   └─ Button buttonStyle=Pressed
                      └─ Text "D" padding(4) background(yellow)
                """)
    }

    @Test("Bordered and glass buttons are 34-point capsules with 12 points of padding")
    func frames() throws {
        for (style, font) in [
            (BuiltInButtonStyle.bordered, Font.body), (.borderedProminent, .body),
            (.glass, Font.body.weight(.medium)), (.glassProminent, Font.body.weight(.medium)),
        ] {
            let button = Button("Label") {}
            let host: ViewHost
            switch style {
            case .bordered: host = ViewHost(button.buttonStyle(.bordered), device: square)
            case .borderedProminent:
                host = ViewHost(button.buttonStyle(.borderedProminent), device: square)
            case .glass: host = ViewHost(button.buttonStyle(.glass), device: square)
            default: host = ViewHost(button.buttonStyle(.glassProminent), device: square)
            }
            let frame = try #require(host.root.children[0].frame)
            #expect(abs(frame.width - (width("Label", font) + 24)) < 0.01)
            #expect(frame.height == 34)
            #expect(frame.midX == 120 && frame.midY == 100)
            // The label is centered in the capsule.
            let label = try #require(host.root.children[0].children[0].frame)
            #expect(abs(label.midX - 120) < 0.01 && abs(label.midY - 100) < 0.01)
        }
        // Plain and borderless buttons hug their labels.
        let plain = ViewHost(Button("Label") {}.buttonStyle(.plain), device: square)
        #expect(plain.root.children[0].frame?.height == 22)
    }

    @Test("Control sizes change a bordered button's height, padding, and text")
    func controlSizes() throws {
        func frame(_ size: ControlSize, glass: Bool = false) throws -> CGRect {
            let button = Button("Label") {}
            let host =
                glass
                ? ViewHost(button.buttonStyle(.glass).controlSize(size), device: square)
                : ViewHost(button.buttonStyle(.bordered).controlSize(size), device: square)
            return try #require(host.root.children[0].frame)
        }
        let small = try frame(.small)
        #expect(small.height == 28)
        #expect(abs(small.width - (width("Label", .subheadline) + 20)) < 0.01)
        #expect(try frame(.mini) == small)
        let regular = try frame(.regular)
        #expect(regular.height == 34)
        let large = try frame(.large)
        #expect(large.height == 50 && abs(large.width - (width("Label") + 40)) < 0.01)
        #expect(try frame(.large, glass: true).height == 46)
        let host = ViewHost(
            Button("Label") {}.buttonStyle(.bordered).controlSize(.small), device: square)
        #expect(host.root.children[0].children[0].attributes["font"] == "subheadline")
    }

    @Test("Each style draws its fill and label colors")
    func colors() throws {
        func host(_ view: some View) -> ViewHost { ViewHost(view, device: square) }
        func frame(_ host: ViewHost) throws -> CGRect {
            try #require(host.root.children[0].frame)
        }

        let bordered = host(Button("MMM") {}.buttonStyle(.bordered))
        let borderedFrame = try frame(bordered)
        let fill = components(
            bordered.render(scale: 2).color(
                at: CGPoint(x: borderedFrame.minX + 4, y: borderedFrame.midY)))
        // 118,118,128 at 12% over white.
        #expect(fill == [238, 238, 240])
        #expect(ink(bordered, in: borderedFrame) == [0, 136, 255])

        let prominent = host(Button("MMM") {}.buttonStyle(.borderedProminent))
        let prominentFrame = try frame(prominent)
        #expect(
            components(
                prominent.render(scale: 2).color(
                    at: CGPoint(x: prominentFrame.minX + 4, y: prominentFrame.midY)))
                == [0, 136, 255])

        let destructive = host(
            Button("MMM", role: .destructive) {}.buttonStyle(.borderedProminent))
        let destructiveFrame = try frame(destructive)
        #expect(
            components(
                destructive.render(scale: 2).color(
                    at: CGPoint(x: destructiveFrame.minX + 4, y: destructiveFrame.midY)))
                == [255, 56, 60])

        let glass = host(Button("MMM") {}.buttonStyle(.glass))
        let glassInk = ink(glass, in: try frame(glass))
        #expect(glassInk.max()! < 40 && glassInk.max()! - glassInk.min()! < 4)

        let glassProminent = host(Button("MMM") {}.buttonStyle(.glassProminent).tint(.green))
        let glassProminentFrame = try frame(glassProminent)
        #expect(
            components(
                glassProminent.render(scale: 2).color(
                    at: CGPoint(x: glassProminentFrame.minX + 4, y: glassProminentFrame.midY)))
                == [52, 199, 89])

        // A plain button's label is primary, a borderless one's the tint.
        let plain = host(Button("MMM") {}.buttonStyle(.plain))
        #expect(ink(plain, in: try frame(plain)) == [0, 0, 0])
        let borderless = host(Button("MMM") {}.buttonStyle(.borderless).tint(.purple))
        #expect(ink(borderless, in: try frame(borderless)) == [203, 48, 224])
    }

    @Test("A custom style's body replaces the label, and the button still taps")
    func customStyle() throws {
        var tapped = false
        let host = ViewHost(
            Button("Go") { tapped = true }.buttonStyle(Pressed()), device: square)
        let button = host.root.children[0]
        let frame = try #require(button.frame)
        #expect(abs(frame.width - (width("Go") + 8)) < 0.01)
        try host.tapButton(labeled: "Go")
        #expect(tapped)
    }

    @Test("tint(_:) records the tint on its view")
    func tintOutline() {
        let host = ViewHost(Text("Hi").tint(.orange), device: square)
        #expect(
            host.root.outline() == """
                Root
                └─ Text "Hi" tint=orange
                """)
    }
}
