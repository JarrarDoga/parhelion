import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

// A copy of the views of Examples/Settings, which shows each control: a
// toggle, a slider, a segmented picker, a menu picker, a navigation-link
// picker, an inline picker, a stepper, labeled content, a divider, and a
// disabled control. A test checks that the copy matches the example, apart
// from `private`.

private enum Appearance: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case automatic = "Automatic"

    var id: Self { self }
}

private enum TextSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
}

private struct SettingsView: View {
    @State private var airplaneMode = false
    @State private var wifi = true
    @State private var brightness = 0.6
    @State private var textSize = TextSize.medium
    @State private var appearance = Appearance.automatic
    @State private var volume = 6.0
    @State private var ringtone = "Reflection"
    @State private var lockAfter = 5
    @State private var copies = 1

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Airplane Mode", isOn: $airplaneMode)
                    Toggle("Wi-Fi", isOn: $wifi)
                    LabeledContent("Network", value: wifi ? "Home" : "Not Connected")
                }
                Section("Display") {
                    Slider(value: $brightness) {
                        Text("Brightness")
                    } minimumValueLabel: {
                        Text("Dim")
                    } maximumValueLabel: {
                        Text("Bright")
                    }
                    Picker("Text Size", selection: $textSize) {
                        ForEach(TextSize.allCases, id: \.self) { size in
                            Text(size.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { appearance in
                            Text(appearance.rawValue)
                        }
                    }
                }
                Section("Sounds") {
                    Slider(value: $volume, in: 0...10, step: 1) {
                        Text("Volume")
                    }
                    Picker("Ringtone", selection: $ringtone) {
                        ForEach(["Reflection", "Radar", "Chimes", "Signal"], id: \.self) { name in
                            Text(name)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                Picker("Auto-Lock", selection: $lockAfter) {
                    Text("30 seconds").tag(0)
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("Never").tag(-1)
                }
                .pickerStyle(.inline)
                Section {
                    Stepper("Copies: \(copies)", value: $copies, in: 1...10)
                    Toggle("Developer Mode", isOn: .constant(false))
                        .disabled(true)
                    VStack(alignment: .leading) {
                        Text("Parhelion")
                        Divider()
                        Text("Version 0.7")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Developer Mode turns on in the Simulator only.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

/// The Settings example's screens, settled after each step.
@MainActor
enum SettingsScreens {
    enum Screen: String, CaseIterable {
        /// The top of the form.
        case top
        /// The Appearance picker's menu, open.
        case menu
        /// The Ringtone picker's list of options, pushed.
        case ringtone
        /// The bottom of the form: the inline picker, the stepper, and the
        /// disabled toggle.
        case bottom
    }

    static func host(showing screen: Screen, device: Device = .iPhone16) throws -> ViewHost {
        let host = ViewHost(SettingsView(), device: device)
        switch screen {
        case .top:
            break
        case .menu:
            try host.tapButton(labeled: "Automatic")
        case .ringtone:
            try host.tapButton(labeled: "Ringtone Reflection")
        case .bottom:
            let list = try #require(host.root.allNodes.first { $0.kind == "List" })
            try host.scroll(list.id, to: CGPoint(x: 0, y: 10_000))
        }
        host.advanceTime(by: 2)
        return host
    }

    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

@MainActor
private func node(_ host: ViewHost, _ suffix: String) throws -> ViewNode {
    try #require(host.root.allNodes.first { $0.id.rawValue.hasSuffix(suffix) })
}

@MainActor
@Suite("Settings screens")
struct SettingsScreensTests {
    @Test("The test's copy of the Settings example matches the example")
    func copyMatchesExample() throws {
        let example = try String(
            contentsOf: SettingsScreens.repository.appendingPathComponent(
                "Examples/Settings/SettingsApp.swift"),
            encoding: .utf8)
        let copy = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        let views = example[example.range(of: "enum Appearance")!.lowerBound...]
        let copied = copy[
            copy.range(of: "private enum Appearance")!
                .lowerBound..<copy.range(of: "/// The Settings example's screens")!.lowerBound
        ]
        #expect(
            copied.replacingOccurrences(of: "private enum", with: "enum")
                .replacingOccurrences(of: "private struct", with: "struct")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                == views.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("parhelion mcp's tap and drag drive every control in the example")
    func agentsDriveEveryControl() throws {
        let host = ViewHost(SettingsView())
        func run(_ command: PreviewCommand) {
            let reply = host.execute(command)
            #expect(reply.ok, "\(reply.message)")
            host.advanceTime(by: 2)
        }
        func point(_ suffix: String) throws -> (x: Double, y: Double) {
            let frame = try #require(try node(host, suffix).frame)
            return (Double(frame.midX), Double(frame.midY))
        }
        func attribute(_ suffix: String, _ name: String) throws -> String? {
            try node(host, suffix).attributes[name]
        }

        // A toggle by label and by point.
        run(.tapButton(label: "Airplane Mode"))
        #expect(host.root.allNodes.first { $0.kind == "Toggle" }?.attributes["isOn"] == "true")
        let wifi = try #require(
            host.root.allNodes.first { $0.label == "Wi-Fi" && $0.kind == "Switch" })
        run(.tapNode(id: wifi.id.rawValue))
        #expect(host.nodes(withText: "Not Connected").count == 1)

        // A slider by drag, from its knob to the trailing end of its track.
        let brightness = try #require(
            host.root.allNodes.first { $0.attributes["label"] == "Brightness" })
        let knob = try #require(brightness.allNodes.first { $0.kind == "Knob" }?.frame)
        let track = try #require(brightness.allNodes.first { $0.kind == "SliderTrack" }?.frame)
        run(
            .drag(
                fromX: Double(knob.midX), fromY: Double(knob.midY), toX: Double(track.maxX),
                toY: Double(knob.midY), duration: 0.3))
        #expect(
            host.root.allNodes.first { $0.attributes["label"] == "Brightness" }?
                .attributes["value"] == "1")

        // A segment by point.
        let large = try point("Picker/option[large]")
        run(.tapPoint(x: large.x, y: large.y))
        #expect(
            host.root.allNodes.first { $0.attributes["label"] == "Text Size" }?
                .attributes["selection"] == "large")

        // A menu: open it by its value, choose by label.
        run(.tapButton(label: "Automatic"))
        #expect(host.root.children.last?.kind == "Menu")
        run(.tapButton(label: "Dark"))
        #expect(host.root.children.last?.kind != "Menu")
        #expect(host.nodes(withText: "Dark").count == 1)

        // An inline picker's option and a stepper's half, by label.
        run(.tapButton(label: "Never"))
        #expect(
            host.root.allNodes.contains {
                $0.label == "Never" && $0.attributes["selected"] == "true"
            })
        run(.tapButton(label: "Increment"))
        #expect(host.nodes(withText: "Copies: 2").count == 1)

        // A navigation-link picker: push, choose, and come back.
        run(.tapButton(label: "Ringtone Reflection"))
        run(.tapButton(label: "Chimes"))
        #expect(host.nodes(withText: "Chimes").count == 1)
        #expect(host.root.allNodes.contains { $0.label == "Ringtone Chimes" })

        // The disabled toggle does not respond.
        let reply = host.execute(.tapButton(label: "Developer Mode"))
        #expect(!reply.ok)
    }

    /// Writes the screens at 3× on an iPhone 16 Pro, the size of Apple's iOS
    /// 27 UI Kit, to compare with its artwork. Set `PARHELION_DEMO_DIR` to a
    /// directory, and optionally `PARHELION_DEMO_PREFIX`.
    @Test(
        "Write the Settings screens at 3×",
        .enabled(if: ProcessInfo.processInfo.environment["PARHELION_DEMO_DIR"] != nil)
    )
    func renderScreens() throws {
        let directory = ProcessInfo.processInfo.environment["PARHELION_DEMO_DIR"] ?? ""
        let prefix = ProcessInfo.processInfo.environment["PARHELION_DEMO_PREFIX"] ?? "settings-"
        for screen in SettingsScreens.Screen.allCases {
            let host = try SettingsScreens.host(showing: screen, device: .iPhone16Pro)
            let url = URL(fileURLWithPath: directory)
                .appendingPathComponent("\(prefix)\(screen.rawValue).png")
            try host.render(scale: 3, chrome: .systemBars).pngData().write(to: url)
        }
    }
}
