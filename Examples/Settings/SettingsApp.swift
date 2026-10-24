import SwiftUI

@main
struct SettingsApp: App {
    var body: some Scene {
        WindowGroup {
            SettingsView()
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case automatic = "Automatic"

    var id: Self { self }

    /// The color scheme the app prefers, or `nil` to follow the device.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .automatic: nil
        }
    }
}

enum TextSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
}

struct SettingsView: View {
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
        .preferredColorScheme(appearance.colorScheme)
    }
}
