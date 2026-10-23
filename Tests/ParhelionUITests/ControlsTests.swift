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
private func center(_ host: ViewHost, _ suffix: String) throws -> CGPoint {
    let frame = try #require(try node(host, suffix).frame)
    return CGPoint(x: frame.midX, y: frame.midY)
}

private struct WiFiSettings: View {
    @State var isOn = false

    var body: some View {
        Form {
            Toggle("Wi-Fi", isOn: $isOn)
            LabeledContent("Network", value: isOn ? "Home" : "None")
        }
    }
}

@MainActor
@Suite("Toggle, LabeledContent, Divider, Form, and disabled")
struct ControlsTests {
    // MARK: Toggle

    @Test("A toggle is its label and a switch with a knob")
    func toggleOutline() {
        let host = ViewHost(Toggle("Wi-Fi", isOn: .constant(true)))
        #expect(
            host.root.outline() == """
                Root
                └─ Toggle isOn=true
                   ├─ Text "Wi-Fi"
                   └─ Switch label=Wi-Fi
                      └─ Knob
                """)
    }

    @Test("A toggle fills its width, with the switch at the trailing edge")
    func toggleLayout() throws {
        let host = ViewHost(Toggle("Wi-Fi", isOn: .constant(false)).padding(16), device: screen)
        let toggle = try #require(try node(host, "Toggle").frame)
        let control = try #require(try node(host, "Toggle/switch").frame)
        let knob = try #require(try node(host, "switch/knob").frame)
        #expect(toggle.width == 268)
        #expect(control == CGRect(x: 220, y: toggle.midY - 14, width: 64, height: 28))
        // The knob rests 2 points inside the leading end while off.
        #expect(knob == CGRect(x: 222, y: toggle.midY - 12, width: 38, height: 24))
    }

    @Test("Tapping the switch toggles; tapping the label does nothing")
    func toggleInteraction() throws {
        let host = ViewHost(WiFiSettings(), device: screen)
        try host.tap(at: try center(host, "Toggle/switch"))
        #expect(try node(host, "Toggle").attributes["isOn"] == "true")
        #expect(host.nodes(withText: "Home").count == 1)

        try host.tapButton(labeled: "Wi-Fi")
        #expect(try node(host, "Toggle").attributes["isOn"] == "false")

        // A press and release on the switch, as from the preview window or
        // parhelion mcp's tap.
        let point = try center(host, "Toggle/switch")
        host.pointerDown(at: point)
        #expect(host.pressedNodeID == (try node(host, "Toggle/switch")).id)
        #expect(host.pointerUp(at: point) == (try node(host, "Toggle/switch")).id)
        #expect(try node(host, "Toggle").attributes["isOn"] == "true")

        let label = try #require(host.nodes(withText: "Wi-Fi").first?.frame)
        #expect(throws: InteractionError.self) {
            try host.tap(at: CGPoint(x: label.midX, y: label.midY))
        }
    }

    @Test("The knob slides to its new position; content that depends on the value does not")
    func knobAnimates() throws {
        let host = ViewHost(WiFiSettings(), device: screen)
        try host.tap(try node(host, "Toggle/switch").id)
        let final = try #require(try node(host, "switch/knob").frame)
        func presented(_ suffix: String) -> CGRect? {
            host.presentedRoot.allNodes.first { $0.id.rawValue.hasSuffix(suffix) }?.frame
        }
        #expect(host.isAnimating)
        #expect(try #require(presented("switch/knob")).minX < final.minX)
        // The labeled content's new value appears at once.
        #expect(host.presentedRoot.allNodes.contains { $0.text == "Home" && $0.opacity == 1 })

        host.advanceTime(by: 0.1)
        let midway = try #require(presented("switch/knob"))
        #expect(midway.minX > final.minX - 22 && midway.minX < final.minX)
        host.advanceTime(by: 2)
        #expect(!host.isAnimating)
        #expect(presented("switch/knob") == final)
    }

    @Test("A switch is green when on, gray when off, and takes the tint")
    func switchColors() throws {
        let host = ViewHost(
            VStack {
                Toggle("On", isOn: .constant(true))
                Toggle("Off", isOn: .constant(false))
                Toggle("Tinted", isOn: .constant(true)).tint(.orange)
            }, device: screen)
        let frame = host.render(scale: 2)
        let switches = host.root.allNodes.filter { $0.kind == "Switch" }.compactMap(\.frame)
        #expect(switches.count == 3)
        // Between the knob and the far end of the track.
        func track(_ rect: CGRect, on: Bool) -> [Int] {
            components(
                frame.color(at: CGPoint(x: on ? rect.minX + 8 : rect.maxX - 8, y: rect.midY)))
        }
        #expect(track(switches[0], on: true) == [52, 199, 89])
        #expect(track(switches[1], on: false) == [196, 196, 198])
        #expect(track(switches[2], on: true) == [255, 141, 40])
        // The knob is white.
        #expect(
            components(frame.color(at: CGPoint(x: switches[0].maxX - 21, y: switches[0].midY)))
                == [255, 255, 255])
    }

    // MARK: Rows in a form

    @Test("A form is an inset grouped list; a toggle row is as tall as a text row")
    func formRows() throws {
        let host = ViewHost(WiFiSettings(), device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ List contentOffset=0, 0 contentSize=300 × 124
                   └─ Section
                      ├─ Toggle listRow isOn=false
                      │  ├─ Text "Wi-Fi"
                      │  └─ Switch label=Wi-Fi
                      │     └─ Knob
                      └─ LabeledContent listRow
                         ├─ Text "Network"
                         └─ Text "None" foregroundStyle=secondary
                """)
        let toggle = try node(host, "Toggle")
        let cell = try #require(toggle.listRowFrame)
        #expect(cell.height == 52)
        // The switch is 16 points from the trailing edge of the cell and
        // centered in it.
        let control = try #require(try node(host, "Toggle/switch").frame)
        #expect(control.maxX == cell.maxX - 16)
        #expect(control.midY == cell.midY)
        // The value sits at the trailing edge of its row.
        let value = try #require(host.nodes(withText: "None").first?.frame)
        let valueCell = try #require(try node(host, "LabeledContent").listRowFrame)
        #expect(abs(value.maxX - (valueCell.maxX - 16)) < 0.01)
        #expect(valueCell.height == 52)
    }

    // MARK: LabeledContent and Divider

    @Test("Labeled content stacks several label views and keeps the content's own style")
    func labeledContent() {
        let host = ViewHost(
            LabeledContent {
                Text("4.2").foregroundStyle(.blue)
            } label: {
                Text("Version")
                Text("Build")
            })
        #expect(
            host.root.outline() == """
                Root
                └─ LabeledContent
                   ├─ VStack alignment=leading spacing=0
                   │  ├─ Text "Version"
                   │  └─ Text "Build"
                   └─ Text "4.2" foregroundStyle=blue
                """)
    }

    @Test("A divider spans its stack's cross axis")
    func divider() throws {
        let host = ViewHost(
            VStack(spacing: 0) {
                Text("Above")
                Divider()
                HStack {
                    Text("Left")
                    Divider()
                    Text("Right")
                }
                .frame(height: 40)
            }
            .frame(width: 200),
            device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack frame(width: 200) spacing=0
                   ├─ Text "Above"
                   ├─ Divider
                   └─ HStack frame(height: 40)
                      ├─ Text "Left"
                      ├─ Divider
                      └─ Text "Right"
                """)
        let dividers = host.root.allNodes.filter { $0.kind == "Divider" }.compactMap(\.frame)
        #expect(dividers[0].width == 200)
        #expect(abs(dividers[0].height - 1.0 / 3) < 0.001)
        #expect(dividers[1].height == 40)
        #expect(abs(dividers[1].width - 1.0 / 3) < 0.001)
    }

    // MARK: disabled(_:)

    @Test("A disabled control records it, draws dimmed, and takes no taps")
    func disabledControls() throws {
        let host = ViewHost(
            VStack {
                Toggle("Wi-Fi", isOn: .constant(true))
                Button("Delete") {}
                TextField("Name", text: .constant(""))
            }
            .disabled(true)
            .disabled(false),
            device: screen)
        #expect(
            host.root.outline() == """
                Root
                └─ VStack
                   ├─ Toggle disabled=true isOn=true
                   │  ├─ Text "Wi-Fi"
                   │  └─ Switch label=Wi-Fi
                   │     └─ Knob
                   ├─ Button disabled=true
                   │  └─ Text "Delete"
                   └─ TextField disabled=true placeholder=Name value=
                """)
        let toggle = try node(host, "Toggle")
        #expect(throws: InteractionError.notTappable(toggle.id)) {
            try host.tapButton(labeled: "Wi-Fi")
        }
        #expect(throws: InteractionError.self) { try host.tap(try node(host, "Toggle/switch").id) }
        #expect(throws: InteractionError.self) { try host.tapButton(labeled: "Delete") }
        #expect(throws: InteractionError.notEditable((try node(host, "TextField")).id)) {
            try host.focus(try node(host, "TextField").id)
        }

        // The switch draws at half opacity: green over white.
        let control = try #require(try node(host, "Toggle/switch").frame)
        let pixel = host.render(scale: 2).color(at: CGPoint(x: control.minX + 8, y: control.midY))
        #expect(components(pixel) == [153, 227, 172])
    }

    @Test("The isEnabled environment value is false inside a disabled view")
    func isEnabledEnvironment() {
        struct Probe: View {
            @Environment(\.isEnabled) var isEnabled
            var body: some View { Text(isEnabled ? "enabled" : "disabled") }
        }
        let host = ViewHost(
            VStack {
                Probe()
                Probe().disabled(true)
            })
        #expect(host.root.allNodes.compactMap(\.text) == ["enabled", "disabled"])
    }
}
