// Written the way an iOS app is written, against `import SwiftUI`, to check
// that button styles, control sizes, tints, toolbar placements, and sheet
// presentation options compile as they do with Apple's SDK.

import SwiftUI
import Testing

private struct Outlined: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

private struct Controls: View {
    @State private var isShowing = true

    var body: some View {
        NavigationStack {
            VStack {
                Button("Plain") {}.buttonStyle(.plain)
                Button("Borderless") {}.buttonStyle(.borderless)
                Button("Automatic") {}.buttonStyle(.automatic)
                Button("Bordered") {}.buttonStyle(.bordered)
                Button("Prominent") {}.buttonStyle(.borderedProminent).tint(.red)
                Button("Glass") {}.buttonStyle(.glass)
                Button("Glass prominent") {}.buttonStyle(.glassProminent)
                Button("Small") {}.buttonStyle(BorderedButtonStyle()).controlSize(.small)
                Button("Custom") {}.buttonStyle(Outlined())
                Button("Untinted") {}.tint(nil)
            }
            .controlSize(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") {} }
            }
            .sheet(isPresented: $isShowing) {
                Text("Sheet")
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

@MainActor
@Suite("Button style source compatibility")
struct ButtonStyleTests {
    @Test("Button styles and sheet options compile under `import SwiftUI`")
    func controls() {
        let host = ViewHost(Controls())
        let styles = host.root.allNodes.filter { $0.kind == "Button" }.map {
            "\($0.label): \($0.attributes["buttonStyle"] ?? "-")"
        }
        #expect(
            styles == [
                "Done: glassProminent",
                "Plain: plain",
                "Borderless: borderless",
                "Automatic: -",
                "Bordered: bordered",
                "Prominent: borderedProminent",
                "Glass: glass",
                "Glass prominent: glassProminent",
                "Small: bordered",
                "Custom: Outlined",
                "Untinted: -",
            ])
    }
}
