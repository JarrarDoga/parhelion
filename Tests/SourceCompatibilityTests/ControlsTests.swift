// Written the way an iOS app is written, against `import SwiftUI`, to check
// that toggles, sliders, steppers, pickers, labeled content, dividers,
// forms, tags, and disabled(_:) compile as they do with Apple's SDK.

import SwiftUI
import Testing

private enum Flavor: String, CaseIterable, Identifiable {
    case chocolate, vanilla

    var id: Self { self }
}

private struct Settings: View {
    @State private var isOn = true
    @State private var volume = 0.5
    @State private var level: Float = 3
    @State private var count = 1
    @State private var flavor = Flavor.vanilla
    @State private var optionalFlavor: Flavor?
    @State private var size = 1
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        NavigationStack {
            Form {
                Section("Toggles") {
                    Toggle("Wi-Fi", isOn: $isOn)
                    Toggle(isOn: $isOn) { Text("Bluetooth") }
                        .toggleStyle(.switch)
                        .toggleStyle(SwitchToggleStyle())
                }
                Section {
                    Slider(value: $volume)
                    Slider(value: $volume, in: 0...1) { editing in _ = editing }
                    Slider(value: $level, in: 0...10, step: 1)
                    Slider(value: $volume, in: 0...1) {
                        Text("Volume")
                    } minimumValueLabel: {
                        Image(systemName: "speaker")
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3")
                    }
                    Slider(value: $level, in: 0...10, step: 2) { Text("Level") }
                }
                Section {
                    Stepper("Count: \(count)", value: $count, in: 0...10)
                    Stepper("Count", value: $count, step: 2)
                    Stepper(value: $count, in: 0...10, step: 1) { Text("\(count)") }
                    Stepper("Pages", onIncrement: { count += 1 }, onDecrement: nil)
                    Stepper {
                        Text("Pages")
                    } onIncrement: {
                        count += 1
                    } onDecrement: {
                        count -= 1
                    }
                }
                Section {
                    Picker("Flavor", selection: $flavor) {
                        ForEach(Flavor.allCases) { Text($0.rawValue) }
                    }
                    Picker("Size", selection: $size) {
                        Text("Small").tag(0)
                        Text("Large").tag(1)
                    }
                    .pickerStyle(.segmented)
                    Picker(selection: $optionalFlavor) {
                        Text("None").tag(Flavor?.none)
                        ForEach(Flavor.allCases) {
                            Text($0.rawValue).tag($0, includeOptional: true)
                        }
                    } label: {
                        Text("Optional")
                    }
                    .pickerStyle(.menu)
                    Picker("Inline", selection: $flavor) {
                        ForEach(Flavor.allCases) { Text($0.rawValue) }
                    }
                    .pickerStyle(.inline)
                    Picker("Link", selection: $flavor) {
                        ForEach(Flavor.allCases) { Text($0.rawValue) }
                    }
                    .pickerStyle(.navigationLink)
                    .pickerStyle(.automatic)
                    .pickerStyle(MenuPickerStyle())
                }
                Section {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Build") { Text("42") }
                    LabeledContent {
                        Text("Value")
                    } label: {
                        Text("Label")
                    }
                    Divider()
                    Button("Delete") {}.disabled(!isEnabled)
                }
                .disabled(false)
            }
        }
    }
}

@MainActor
@Suite("Controls source compatibility")
struct ControlsTests {
    @Test("Controls compile under `import SwiftUI` and resolve to their nodes")
    func controls() {
        let host = ViewHost(Settings())
        let kinds = Set(host.root.allNodes.map(\.kind))
        for kind in ["Toggle", "Slider", "Stepper", "Picker", "LabeledContent", "Divider"] {
            #expect(kinds.contains(kind), "\(kind)")
        }
    }
}
