import Foundation
import Testing

@testable import ParhelionUI

/// A 300 × 400 screen with 20 points of safe area at the top and bottom.
private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 300, height: 400),
    safeAreaInsets: EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0)
)

private func components(_ color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> [Int] {
    [Int(color.red), Int(color.green), Int(color.blue)]
}

@MainActor
private func node(_ host: ViewHost, _ suffix: String) throws -> ViewNode {
    try #require(host.root.allNodes.first { $0.id.rawValue.hasSuffix(suffix) })
}

@MainActor
private func frame(_ host: ViewHost, _ suffix: String) throws -> CGRect {
    try #require(try node(host, suffix).frame)
}

/// Records what a control reported, across updates.
@MainActor
private final class Log {
    var events: [String] = []
}

private struct Quantity: View {
    @State var count = 3

    var body: some View {
        Form {
            Stepper("Quantity: \(count)", value: $count, in: 1...4)
        }
    }
}

private struct Volume: View {
    @State var volume = 5.0
    var step: Double?
    var log: Log?

    var body: some View {
        VStack {
            if let step {
                Slider(value: $volume, in: 0...10, step: step) { Text("Volume") }
            } else {
                Slider(value: $volume, in: 0...10) {
                    Text("Volume")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("10")
                } onEditingChanged: { editing in
                    log?.events.append(editing ? "began" : "ended")
                }
            }
            Text("Volume \(volume)")
        }
        .padding(16)
    }
}

@MainActor
@Suite("Stepper and Slider")
struct SliderStepperTests {
    // MARK: Stepper

    @Test("A stepper is its label and two halves labeled for VoiceOver")
    func stepperOutline() {
        let host = ViewHost(Quantity())
        #expect(
            host.root.outline() == """
                Root
                └─ List contentOffset=0, 0 contentSize=393 × 72
                   └─ Section
                      └─ Stepper listRow bounds=1...4 value=3
                         ├─ Text "Quantity: 3"
                         ├─ StepperButton label=Decrement
                         └─ StepperButton label=Increment
                """)
    }

    @Test("A stepper's 92 × 32 capsule sits at the trailing edge of a 52-point row")
    func stepperLayout() throws {
        let host = ViewHost(Quantity(), device: screen)
        let cell = try #require(try node(host, "Stepper").listRowFrame)
        let decrement = try frame(host, "Stepper/decrement")
        let increment = try frame(host, "Stepper/increment")
        #expect(cell.height == 52)
        #expect(decrement.size == CGSize(width: 46, height: 32))
        #expect(increment.minX == decrement.maxX)
        #expect(increment.maxX == cell.maxX - 16)
        #expect(decrement.midY == cell.midY)
    }

    @Test("The halves change the value by label, identifier, and pointer, and stop at the bounds")
    func stepperInteraction() throws {
        let host = ViewHost(Quantity(), device: screen)
        try host.tapButton(labeled: "Increment")
        #expect(host.nodes(withText: "Quantity: 4").count == 1)
        // At the upper bound, the increment half turns off.
        let increment = try node(host, "Stepper/increment")
        #expect(increment.isDisabled)
        #expect(throws: InteractionError.notTappable(increment.id)) {
            try host.tapButton(labeled: "Increment")
        }

        try host.tap(try node(host, "Stepper/decrement").id)
        let half = try frame(host, "Stepper/decrement")
        let point = CGPoint(x: half.midX, y: half.midY)
        host.pointerDown(at: point)
        #expect(host.pressedNodeID == (try node(host, "Stepper/decrement")).id)
        host.pointerUp(at: point)
        #expect(host.nodes(withText: "Quantity: 2").count == 1)
    }

    @Test("A stepper with actions runs them and turns off a half without one")
    func stepperActions() throws {
        let log = Log()
        let host = ViewHost(
            Stepper("Pages", onIncrement: { log.events.append("+") }, onDecrement: nil))
        try host.tapButton(labeled: "Increment")
        #expect(log.events == ["+"])
        #expect(try node(host, "Stepper/decrement").isDisabled)
        #expect(try node(host, "Stepper").attributes["value"] == nil)
    }

    @Test("A stepper draws a gray capsule with a line between black symbols")
    func stepperDrawing() throws {
        let host = ViewHost(Stepper("Pages", value: .constant(0), in: 0...2), device: screen)
        let image = host.render(scale: 2)
        let decrement = try frame(host, "Stepper/decrement")
        // The tertiary fill over white.
        #expect(
            components(image.color(at: CGPoint(x: decrement.minX + 30, y: decrement.minY + 4)))
                == [238, 238, 240])
        // The minus of the half that is turned off is tertiary gray; the
        // plus is black.
        #expect(
            components(image.color(at: CGPoint(x: decrement.midX, y: decrement.midY)))
                == [185, 185, 188])
        let increment = try frame(host, "Stepper/increment")
        #expect(
            components(image.color(at: CGPoint(x: increment.midX, y: increment.midY)))
                == [0, 0, 0])
        // The line between the halves.
        #expect(
            components(image.color(at: CGPoint(x: decrement.maxX - 0.25, y: decrement.midY)))
                != [238, 238, 240])
    }

    // MARK: Slider

    @Test("A slider records its value, bounds, and label, between its value labels")
    func sliderOutline() {
        let host = ViewHost(Volume())
        #expect(
            host.root.outline() == """
                Root
                └─ VStack padding(16)
                   ├─ Slider bounds=0...10 label=Volume value=5
                   │  ├─ Text "0"
                   │  ├─ SliderTrack
                   │  │  └─ Knob
                   │  └─ Text "10"
                   └─ Text "Volume 5.0"
                """)
    }

    @Test("The track fills the space between the value labels, with the knob at the value")
    func sliderLayout() throws {
        let host = ViewHost(Volume(), device: screen)
        let slider = try frame(host, "Slider")
        let track = try frame(host, "Slider/track")
        let knob = try frame(host, "track/knob")
        let maximum = try #require(host.nodes(withText: "10").first?.frame)
        #expect(slider.width == 268)
        #expect(slider.height == 22)
        #expect(track.maxX == maximum.minX - 12)
        #expect(knob.size == CGSize(width: 37, height: 24))
        #expect(abs(knob.midX - track.midX) < 0.01)
        #expect(knob.midY == track.midY)
    }

    @Test("Dragging the knob moves it with the pointer and reports editing")
    func sliderDrag() throws {
        let log = Log()
        let host = ViewHost(Volume(log: log), device: screen)
        let track = try frame(host, "Slider/track")
        let knob = try frame(host, "track/knob")
        let travel = track.width - knob.width
        // Grab the knob 5 points right of its center and move 10% of the
        // travel to the right.
        let start = CGPoint(x: knob.midX + 5, y: knob.midY)
        host.pointerDown(at: start)
        #expect(log.events == ["began"])
        #expect(host.pressedNodeID == (try node(host, "Slider/track")).id)
        host.pointerMoved(to: CGPoint(x: start.x + travel / 10, y: start.y + 3))
        #expect(try node(host, "Slider").attributes["value"] == "6")
        #expect(abs(try frame(host, "track/knob").minX - (knob.minX + travel / 10)) < 0.01)
        #expect(host.pointerUp(at: CGPoint(x: start.x + travel / 5, y: start.y)) != nil)
        #expect(try node(host, "Slider").attributes["value"] == "7")
        #expect(log.events == ["began", "ended"])
        #expect(host.pressedNodeID == nil)
    }

    @Test("A tap or a press elsewhere on the track moves the knob there, snapped to the step")
    func sliderTapAndStep() throws {
        let host = ViewHost(Volume(step: 2), device: screen)
        let track = try frame(host, "Slider/track")
        let knobWidth = LayoutDefaults.sliderKnobSize.width
        func x(_ fraction: CGFloat) -> CGFloat {
            track.minX + knobWidth / 2 + fraction * (track.width - knobWidth)
        }
        try host.tap(at: CGPoint(x: x(0.86), y: track.midY))
        #expect(try node(host, "Slider").attributes["value"] == "8")
        #expect(try node(host, "Slider").attributes["step"] == "2")

        // The same through parhelion mcp's tap and drag.
        var reply = host.execute(.tapPoint(x: Double(x(0.1)), y: Double(track.midY)))
        #expect(reply.ok)
        #expect(try node(host, "Slider").attributes["value"] == "2")
        let knob = try frame(host, "track/knob")
        reply = host.execute(
            .drag(
                fromX: Double(knob.midX), fromY: Double(knob.midY), toX: Double(track.maxX + 40),
                toY: Double(knob.midY + 30), duration: 0.2))
        #expect(reply.ok)
        #expect(try node(host, "Slider").attributes["value"] == "10")
        #expect(host.nodes(withText: "Volume 10.0").count == 1)
    }

    @Test("A drag on a slider in a list moves the knob instead of scrolling")
    func sliderInList() throws {
        struct Rows: View {
            @State var value = 0.5
            var body: some View {
                List {
                    Slider(value: $value)
                    ForEach(0..<20) { Text("Row \($0)") }
                }
            }
        }
        let host = ViewHost(Rows(), device: screen)
        let row = try #require(try node(host, "Slider").listRowFrame)
        #expect(row.height == 52)
        let knob = try frame(host, "track/knob")
        host.drag(
            from: CGPoint(x: knob.midX, y: knob.midY),
            to: CGPoint(x: knob.midX - 60, y: knob.midY + 40), duration: 0.3)
        let list = try node(host, "List")
        #expect(host.scrollOffset(of: list.id) == .zero)
        #expect(try node(host, "Slider").attributes["value"] != "0.5")
    }

    @Test("A disabled slider does not move")
    func disabledSlider() throws {
        let host = ViewHost(Volume().disabled(true), device: screen)
        let track = try frame(host, "Slider/track")
        try? host.tap(at: CGPoint(x: track.minX + 20, y: track.midY))
        host.drag(
            from: CGPoint(x: track.midX, y: track.midY),
            to: CGPoint(x: track.maxX, y: track.midY), duration: 0.2)
        #expect(try node(host, "Slider").attributes["value"] == "5")
        #expect(try node(host, "Slider").isDisabled)
    }

    @Test("The track is tinted up to the knob and gray after it; a dragged knob is glass")
    func sliderDrawing() throws {
        let host = ViewHost(Volume(), device: screen)
        let track = try frame(host, "Slider/track")
        let knob = try frame(host, "track/knob")
        var image = host.render(scale: 2)
        #expect(
            components(image.color(at: CGPoint(x: track.minX + 6, y: track.midY))) == [0, 136, 255])
        #expect(
            components(image.color(at: CGPoint(x: track.maxX - 6, y: track.midY)))
                == [228, 228, 228])
        #expect(
            components(image.color(at: CGPoint(x: knob.midX, y: knob.midY))) == [255, 255, 255])

        host.pointerDown(at: CGPoint(x: knob.midX, y: knob.midY))
        image = host.render(scale: 2)
        // The lens reaches past the knob's ends.
        let beyond = CGPoint(x: knob.maxX + 6, y: knob.midY)
        #expect(components(image.color(at: beyond)) != [228, 228, 228])
    }
}
